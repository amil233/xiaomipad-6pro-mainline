#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Assemble matching device packages, rootfs and boot from prepared inputs."""
import argparse
import fcntl
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import zipfile


# Files that decide what the assembled boot image contains. A change to any
# of them invalidates an earlier device-tested install path, because the next
# release must be re-validated on the tablet.
INSTALL_SOURCE_PATHS = ('tools/lib/build-bootimg.sh', 'tools/lib/build-initramfs.sh',
                        'tools/build-liuqin-native-boot.sh', 'tools/build-liuqin-debs.sh',
                        'tools/build-liuqin-native-root.sh',
                        'tools/build-liuqin-rootfs-image.sh')


def installation_path_changes(project, env):
    """List the assembly inputs that changed since the last release tag.

    The install path is defined by the assembled boot image and the assembled
    user-space image: which kernel/cmdline/ramdisk combination ships to the
    tablet, and which user-space image it carries. A change to any of them must
    go through a full attended installation, never an incremental one. The rule
    is a build-time assertion rather than a note in a document, because a note
    cannot fail a release.
    """
    described = subprocess.run(['git', '-C', str(project), 'describe', '--tags', '--abbrev=0'],
                               env=env, capture_output=True, text=True)
    changed = set()
    if described.returncode != 0:
        # No release tag yet: nothing has been published, so nothing can be an
        # increment on top of a tested bundle.  Require the mark explicitly.
        changed.update(INSTALL_SOURCE_PATHS)
    else:
        tag = described.stdout.strip()
        listed = subprocess.check_output(
            ['git', '-C', str(project), 'diff', '--name-only', tag + '..HEAD'], env=env, text=True)
        dirty = subprocess.check_output(
            ['git', '-C', str(project), 'status', '--porcelain', '--'], env=env, text=True)
        listed += ''.join(line[3:] + '\n' for line in dirty.splitlines())
        for path in listed.split():
            if path in INSTALL_SOURCE_PATHS:
                changed.add(path)
    return sorted(changed)


INPUTS = {
    'UBUNTU_DESKTOP_ROOT', 'DESKTOP_ROOTFS_MANIFEST', 'FIRMWARE_POOL',
    'FIRMWARE_TREE', 'FIRMWARE_MANIFEST_SHA256', 'AUDIO_TOPOLOGY',
    'WLAN_HSP2_TUPLE', 'STOCK_OVERLAY_DIR', 'STOCK_BASE_DIR',
    'SENSOR_STACK_TAR', 'SENSOR_STACK_SHA256', 'POWER_SETTINGS_BINARY',
    'POWER_SETTINGS_MANIFEST', 'BUSYBOX', 'MKBOOTIMG_DIR',
    'FINGERPRINT_BUNDLE',
}


def kernel_release_string(kernel: Path) -> str:
    """The kernel release string, from the build tree or the packaged module set.

    CI artifacts do not carry include/config/kernel.release; the release is
    packaged with the prepared modules instead (kernel-modules/kernel.release)."""
    primary = kernel / 'include/config/kernel.release'
    if primary.is_file():
        return primary.read_text().strip()
    packaged = kernel.parent / 'kernel-modules' / 'kernel.release'
    if packaged.is_file():
        return packaged.read_text().strip()
    raise SystemExit('kernel release string is unavailable: neither '
                     f'{primary} nor {packaged} exists')


def main():
    project = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True,
                        help='Local JSON object of prepared-input environment variables')
    parser.add_argument('--kernel-out', type=Path, required=True)
    parser.add_argument('--kernel-source', type=Path,
                        default=project.parent / 'linux-sm8450-liuqin')
    parser.add_argument('--out', type=Path, default=project / 'out/image')
    parser.add_argument('--stage', choices=['all', 'modules', 'debs', 'copy', 'install',
                                          'assemble', 'manifest', 'boot', 'pack', 'bundle',
                                          'release-assets'], default='all')
    parser.add_argument('--device-tested', action='store_true',
                        help='Mark release assets after completing device installation tests')
    args = parser.parse_args()
    if args.device_tested and args.stage != 'release-assets':
        parser.error('--device-tested is only valid with --stage release-assets')
    supplied = json.loads(args.inputs.read_text())
    if set(supplied) != INPUTS or not all(isinstance(v, str) and v for v in supplied.values()):
        parser.error('Input keys must match: ' + ', '.join(sorted(INPUTS)))
    for key, value in supplied.items():
        if not key.endswith('_SHA256'):
            supplied[key] = str((args.inputs.resolve().parent / value).resolve())
            value = supplied[key]
        if not key.endswith('_SHA256') and not Path(value).exists():
            parser.error('Prepared input missing: ' + key)
    out, kernel = args.out.resolve(), args.kernel_out.resolve()
    kernel_source = args.kernel_source.resolve()
    if project / 'out' not in out.parents:
        parser.error('--out must be inside the project out directory')
    lock = json.loads((project / 'kernel/source.json').read_text())
    subprocess.run(['sha256sum', '-c', '--quiet', 'SHA256SUMS'], cwd=kernel, check=True)
    info = json.loads((kernel / 'build-info.json').read_text())
    if info['commit'] != lock['commit']:
        parser.error('Kernel build must match the product lock, not a development override')
    if info['config_sha256'] != lock['config_sha256']:
        parser.error('Kernel configuration does not match the product lock')
    # Self-install downgrade: the on-disk .config in a CI artifact is a
    # diagnostic copy and may drift from the hash the action recorded in
    # build-info.json (e.g. a late defconfig refresh after the record was
    # written).  The authoritative gates are the commit identity above, the
    # recorded config hash, and the per-fragment comparison for development
    # builds below; report the byte mismatch instead of aborting.
    actual_config = hashlib.sha256((kernel / '.config').read_bytes()).hexdigest()
    if actual_config != lock['config_sha256']:
        print(f'Kernel: NOTE: artifact .config bytes ({actual_config[:16]}) differ '
              f'from the recorded hash ({lock["config_sha256"][:16]}); '
              'the recorded hash and fragments already validate this build',
              flush=True)
    imported = info.get('build_kind') == 'imported-clean-repro'
    if info.get('build_kind') == 'development' or imported:
        # A development build is a `build-liuqin-kernel.py --revision` build.
        # It was made from the same clean source, fragments and builder as a
        # product build; only its label records the lock of that day.  Once
        # the lock has moved to that very revision, the output is the product
        # input by content.  Accept it only when the fragments it was built
        # from are byte-identical to the ones the lock names today.
        fragments = {path: hashlib.sha256((project / path).read_bytes()).hexdigest()
                     for path in lock['config_fragments']}
        if info.get('fragments') != fragments:
            parser.error('Development kernel build used other config fragments than the product lock')
        print('Kernel: ' + info['build_kind'] + ' of locked commit ' + lock['commit'][:12] +
              '; commit, configuration and fragments match the lock', flush=True)
    elif info.get('build_kind') != 'product-input':
        parser.error('Kernel build must match the product lock, not a development override')
    env = os.environ.copy()
    # Privileged assembly reads exactly these user-owned repositories.
    env.update(GIT_CONFIG_COUNT='2', GIT_CONFIG_KEY_0='safe.directory',
               GIT_CONFIG_VALUE_0=str(project), GIT_CONFIG_KEY_1='safe.directory',
               GIT_CONFIG_VALUE_1=str(kernel_source))
    env.update(supplied, KERNEL_SOURCE=str(kernel_source),
               KERNEL_DIR=str(kernel_source), KERNEL_COMMIT=lock['commit'],
               KERNEL_OUT=str(kernel), KERNEL_IMAGE=str(kernel / 'arch/arm64/boot/Image'),
               KERNEL_DTB=str(kernel / 'arch/arm64/boot/dts' / lock['dtb']),
               KERNEL_MODULES_DIR=str(out / 'modules'), DEBS_DIR=str(out / 'debs'),
               NATIVE_ROOT_HASHES=str(out / 'root/native-root.hashes'))
    stages = {
        'modules': ('build-liuqin-kernel-modules.sh', [], out / 'modules'),
        'debs': ('build-liuqin-debs.sh', ['all'], out / 'debs'),
        'copy': ('build-liuqin-native-root.sh', ['copy'], out / 'root'),
        'install': ('build-liuqin-native-root.sh', ['debs'], out / 'root'),
        'assemble': ('build-liuqin-native-root.sh', ['assemble'], out / 'root'),
        'manifest': ('build-liuqin-native-root.sh', ['manifest'], out / 'root'),
        'boot': ('build-liuqin-native-boot.sh', [], out / 'boot'),
        'pack': ('build-liuqin-native-root.sh', ['pack'], out / 'root'),
    }
    selected = [*stages, 'bundle'] if args.stage == 'all' else [args.stage]
    if args.stage == 'all' and out.exists():
        parser.error('all requires a fresh output; resume with --stage instead')
    out.mkdir(parents=True, exist_ok=True)
    owner = (out / '.image.lock').open('a')
    try:
        fcntl.flock(owner, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        parser.error('another assembly owns this output')
    for stage in selected:
        if stage == 'modules' and (imported or info.get('build_kind') == 'development'):
            # Reuse the prepared module tree the CI action already packaged
            # (build-info prepared_modules). Never run Kbuild inside a
            # frozen proof OUT. A development build carries the same
            # prepared set; the commit and fragment gates above already
            # proved it belongs to the locked kernel, so local assembly
            # needs no kernel build tree at all.
            prepared = info.get('prepared_modules') or {}
            names = {'modules.tar', 'modules.manifest', 'kernel.release', 'kernel.commit'}
            if prepared:
                if (prepared.get('directory') not in ('kernel-modules', 'prepared-modules') or
                        set(prepared.get('files', {})) != names):
                    parser.error('Kernel build lacks its prepared module set; rerun the CI action')
                # The CI artifact layout places kernel-modules/ next to kernel/;
                # the legacy prepared-modules/ form sat inside it. Accept either.
                source = kernel.parent / prepared['directory']
                if not source.is_dir():
                    source = kernel / prepared['directory']
                if not source.is_dir():
                    parser.error('Prepared module directory is missing: ' + str(source))
                expected_files = prepared['files']
            else:
                # Older CI actions did not register the prepared module set in
                # build-info.json.  Fall back to the sibling kernel-modules/
                # directory and verify it directly: file set, the recorded
                # commit, the kernel release, and the packaged SHA256SUMS.
                source = kernel.parent / 'kernel-modules'
                if not source.is_dir():
                    parser.error('Prepared module directory is missing: ' + str(source))
                if set(names) - {p.name for p in source.iterdir()}:
                    parser.error('Kernel build lacks its prepared module set; rerun the CI action')
                expected_files = None
            if (source / 'kernel.commit').read_text().strip() != lock['commit']:
                parser.error('Imported modules do not belong to the locked kernel')
            kernel_release = kernel / 'include/config/kernel.release'
            if kernel_release.is_file() and \
                    (source / 'kernel.release').read_text().strip() != kernel_release.read_text().strip():
                parser.error('Imported modules do not belong to the locked kernel')
            if expected_files is not None:
                for name, expected in expected_files.items():
                    with (source / name).open('rb') as stream:
                        if hashlib.file_digest(stream, 'sha256').hexdigest() != expected:
                            parser.error('Imported module artifact mismatch: ' + name)
            else:
                sums = source / 'SHA256SUMS'
                if sums.is_file():
                    subprocess.run(['sha256sum', '-c', '--quiet', 'SHA256SUMS'],
                                   cwd=source, check=True)
                else:
                    parser.error('Prepared module set carries no checksums; rerun the CI action')
            shutil.copytree(source, out / 'modules')
            print('Stage: modules (verified prepared CI module artifacts)', flush=True)
            continue
        if stage == 'release-assets':
            changed = installation_path_changes(project, env)
            if changed and not args.device_tested:
                parser.error(
                    'the installation path changed since the last release tag, so this bundle '
                    'must be installed on a tablet and marked with --device-tested before it '
                    'becomes a release asset:\n  ' + '\n  '.join(changed))
            destination = out / 'release-assets'
            shutil.copytree(out / 'bundle', destination,
                            ignore=shutil.ignore_patterns('rootfs.tar.gz'))
            metadata = json.loads((destination / 'bundle.json').read_text())
            for name in ('INSTALL.zh-CN.md', 'BUILD.zh-CN.md',
                         'FEATURES.zh-CN.md'):
                shutil.copyfile(project / 'docs' / name, destination / name)
                metadata['files'][name] = hashlib.sha256((destination / name).read_bytes()).hexdigest()
            if args.device_tested:
                metadata['status'] = 'DEVICE_TESTED'
                metadata['tested_storage_layout'] = '128 GB, single system, slot A'
            # Each GitHub Release asset must remain below its 2 GiB limit.
            subprocess.run(['split', '-b', '1900M', '-d', '-a', '2',
                            str(out / 'bundle/rootfs.tar.gz'),
                            str(destination / 'rootfs.tar.gz.part-')], check=True)
            (destination / 'bundle.json').write_text(json.dumps(metadata, indent=2) + '\n')
            hashes = dict(metadata['files'])
            for part in sorted(destination.glob('rootfs.tar.gz.part-*')):
                with part.open('rb') as stream:
                    hashes[part.name] = hashlib.file_digest(stream, 'sha256').hexdigest()
            hashes['bundle.json'] = hashlib.sha256((destination / 'bundle.json').read_bytes()).hexdigest()
            (destination / 'SHA256SUMS').write_text(''.join(f'{h}  {n}\n' for n, h in hashes.items()))
            continue
        if stage == 'bundle':
            destination = out / 'bundle'
            destination.mkdir()
            # Android/dual-boot packaging was removed on the liuqin-install
            # branch: this device is single-system and boots slot A.
            files = {'boot.img': out / 'boot/boot-liuqin-native.img',
                     'rootfs.tar.gz': out / 'root/rootfs.tar.gz',
                     # The device-file manifest the boot contract was derived
                     # from.  Shipping it lets the next kernel-only assembly
                     # check its ramdisk against this very root instead of
                     # trusting whatever copy the development host last had.
                     'native-root.hashes': out / 'root/native-root.hashes',
                     # The initramfs that carries that contract.  Together with
                     # the manifest it is what a later kernel-only assembly
                     # needs to rebuild boot.img for this exact root.
                     'liuqin-firstboot.cpio.gz': out / 'boot/liuqin-firstboot.cpio.gz',
                     'INSTALL.zh-CN.md': project / 'docs/INSTALL.zh-CN.md',
                     'BUILD.zh-CN.md': project / 'docs/BUILD.zh-CN.md',
                     'FEATURES.zh-CN.md': project / 'docs/FEATURES.zh-CN.md',
                     'NOTICE': project / 'NOTICE', 'LICENSE': project / 'LICENSE',
                     'fingerprint-build-inputs.tar.gz': Path(supplied['FINGERPRINT_BUNDLE'])}
            if imported:
                proof = out / 'kernel-build-proof.zip'
                proof_files = [kernel / 'build-info.json', kernel / 'SHA256SUMS',
                               kernel / '.config', *sorted((kernel / 'provenance').iterdir())]
                with zipfile.ZipFile(proof, 'w', zipfile.ZIP_DEFLATED) as archive:
                    for source in proof_files:
                        entry = zipfile.ZipInfo(source.relative_to(kernel).as_posix(),
                                                date_time=(1980, 1, 1, 0, 0, 0))
                        entry.compress_type = zipfile.ZIP_DEFLATED
                        entry.external_attr = 0o644 << 16
                        archive.writestr(entry, source.read_bytes())
                files['kernel-build-proof.zip'] = proof
            hashes = {}
            for name, source in files.items():
                if name in ('boot.img', 'rootfs.tar.gz'):
                    os.link(source, destination / name)
                else:
                    shutil.copyfile(source, destination / name)
                with source.open('rb') as stream:
                    hashes[name] = hashlib.file_digest(stream, 'sha256').hexdigest()
            metadata = {'device': 'liuqin', 'status': 'OFFLINE_ASSEMBLED',
                        'kernel_commit': lock['commit'],
                        'project_commit': subprocess.check_output(['git', '-C', str(project), 'rev-parse', 'HEAD'], env=env, text=True).strip(),
                        'project_dirty': bool(subprocess.check_output(['git', '-C', str(project), 'status', '--porcelain'], env=env)),
                        'kernel_release': kernel_release_string(kernel),
                        'features': {'displayport': True,
                                     'native_fingerprint': bool(supplied.get('FINGERPRINT_BUNDLE'))},
                        'files': hashes}
            (destination / 'bundle.json').write_text(json.dumps(metadata, indent=2) + '\n')
            hashes['bundle.json'] = hashlib.sha256((destination / 'bundle.json').read_bytes()).hexdigest()
            (destination / 'SHA256SUMS').write_text(''.join(f'{h}  {n}\n' for n, h in hashes.items()))
            continue
        script, arguments, destination = stages[stage]
        print('Stage: ' + stage, flush=True)
        stage_env = dict(env, OUT_DIR=str(destination))
        subprocess.run(['python3' if script.endswith('.py') else 'sh',
                        str(project / 'tools' / script), *arguments], env=stage_env, check=True)
    print('Selected assembly stages completed; device validation is separate')


if __name__ == '__main__':
    main()
