#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build the checked-out kernel with the configuration in kernel/source.json."""

import argparse
import fcntl
import hashlib
import json
import os
import platform
import re
from pathlib import Path
import shutil
import subprocess


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    project = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=project.parent / 'linux-sm8450-liuqin')
    parser.add_argument('--out', type=Path, default=project / 'out/kernel')
    parser.add_argument('--jobs', type=int, default=min(os.cpu_count() or 1, 12))
    parser.add_argument('--configure-only', action='store_true')
    parser.add_argument('--revision', help='Require the checkout to be this exact commit')
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    source, out = args.source.resolve(), args.out.resolve()
    lock = json.loads((project / 'kernel/source.json').read_text())
    commit = output('git', '-C', str(source), 'rev-parse', 'HEAD').strip()
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        parser.error('kernel source has no commit')
    if args.revision:
        if not re.fullmatch(r'[0-9a-f]{40}', args.revision):
            parser.error('--revision must be a full commit SHA')
        if commit != args.revision:
            parser.error('checked-out kernel is not the requested revision')
    if out == source or source in out.parents:
        parser.error('--out must be outside the kernel source tree')
    if output('git', '-C', str(source), 'status', '--porcelain', '--untracked-files=normal'):
        parser.error('kernel source must be clean')
    # Compile natively when the host itself is aarch64 (e.g. the
    # ubuntu-24.04-arm runner); cross-compile everywhere else.
    default_cross = '' if platform.machine() == 'aarch64' else 'aarch64-linux-gnu-'
    cross = os.environ.get('CROSS_COMPILE', default_cross)
    compiler = shutil.which(cross + 'gcc')
    if not compiler:
        parser.error('no gcc for arm64 found: on aarch64 hosts install gcc, '
                     'elsewhere install the AArch64 cross compiler '
                     '(or set CROSS_COMPILE)')
    # Kconfig records the invoked compiler name in CC_VERSION_TEXT. Use the
    # versioned executable consistently during configuration and compilation.
    compiler = str(Path(compiler).resolve())
    fragments = [project / path for path in lock['config_fragments']]
    identity = {
        'commit': commit,
        'fragments': {str(p.relative_to(project)): digest(p) for p in fragments},
        'compiler': str(Path(compiler).resolve()), 'compiler_sha256': digest(compiler),
        'compiler_version': output(compiler, '--version'),
        'builder_sha256': digest(__file__),
    }
    out.mkdir(parents=True, exist_ok=True)
    with (out / '.build.lock').open('a') as owner:
        try:
            fcntl.flock(owner, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error('another writer owns this output directory')
        stamp = out / 'build-inputs.json'
        if stamp.exists():
            previous = json.loads(stamp.read_text())
            # Kbuild tracks source changes on the same base; keep those builds
            # incremental.  Compare the fields both records share, so an older
            # build-inputs.json with extra fields still matches.
            shared = (set(previous) & set(identity)) - {'commit', 'fragments'}
            if {k: previous[k] for k in shared} != {k: identity[k] for k in shared}:
                parser.error('build inputs changed; use a new --out directory')
        elif any(p.name != '.build.lock' for p in out.iterdir()):
            parser.error('output has no input identity; use a new --out directory')
        stamp.write_text(json.dumps(identity, indent=2) + '\n')
        env = os.environ.copy()
        env.update(ARCH='arm64', CROSS_COMPILE=cross, KBUILD_BUILD_USER='liuqin',
                   KBUILD_BUILD_HOST='build', KBUILD_BUILD_VERSION='1',
                   KBUILD_BUILD_TIMESTAMP=output('git', '-C', str(source), 'show',
                                                '-s', '--format=%cI', 'HEAD'))
        for key in ('KCONFIG_CONFIG', 'KCONFIG_ALLCONFIG', 'KBUILD_OUTPUT',
                    'KBUILD_EXTMOD', 'KBUILD_KCONFIG', 'LOCALVERSION',
                    'KCFLAGS', 'KAFLAGS', 'KCPPFLAGS', 'LDFLAGS_vmlinux'):
            env.pop(key, None)
        # The locked GCC configuration does not use Rust; ignore host Rust installs.
        make = ['make', '-C', str(source), 'O=' + str(out), 'RUSTC=false', 'CC=' + compiler]
        subprocess.run(make + ['defconfig'], env=env, check=True)
        subprocess.run(['sh', str(source / 'scripts/kconfig/merge_config.sh'),
                        '-m', '-O', str(out), str(out / '.config'),
                        *map(str, fragments)], env=env, check=True)
        subprocess.run(make + ['olddefconfig'], env=env, check=True)
        config_sha256 = digest(out / '.config')
        if args.configure_only:
            print('Configuration verified; no Image or modules built.')
            return
        cc = ('ccache ' if shutil.which('ccache') else '') + compiler
        maps = f'-ffile-prefix-map={source}=/build/linux -ffile-prefix-map={out}=/build/kernel'
        subprocess.run(make + ['-j' + str(args.jobs), 'CC=' + cc, 'KCFLAGS=' + maps, 'KAFLAGS=' + maps,
                               'Image', lock['dtb'], 'modules'], env=env, check=True)
        subprocess.run(make + ['modules_install', 'INSTALL_MOD_PATH=' + str(out / 'modules')],
                       env=env, check=True)
        if output('git', '-C', str(source), 'rev-parse', 'HEAD').strip() != commit or output(
                'git', '-C', str(source), 'status', '--porcelain', '--untracked-files=normal'):
            identity['invalidated'] = 'source changed during build'
            stamp.write_text(json.dumps(identity, indent=2) + '\n')
            parser.error('source changed during build; discard this output')
        paths = ['arch/arm64/boot/Image', 'arch/arm64/boot/dts/' + lock['dtb'],
                 '.config', 'vmlinux', 'System.map']
        public_info = {key: identity[key] for key in
                       ('commit', 'fragments', 'compiler_sha256',
                        'compiler_version', 'builder_sha256')}
        public_info['config_sha256'] = config_sha256
        (out / 'build-info.json').write_text(json.dumps(public_info, indent=2) + '\n')
        paths.append('build-info.json')
        (out / 'SHA256SUMS').write_text(''.join(f'{digest(out / p)}  {p}\n' for p in paths))
        print(f'Kernel build complete: {out}. Hardware validation is separate.')


if __name__ == '__main__':
    main()
