#!/bin/sh
# SPDX-License-Identifier: MIT
#
# 在 Fedora 45 的容器里执行一条命令，给需要在 Fedora 用户态里做的事用
# （rpmbuild、dnf、rpm）。runner 是 arm64 的 Ubuntu，容器用官方 aarch64 镜像，
# 是原生执行，不做模拟。
#
#   sh tools/fedora-container.sh 'sh tools/build-liuqin-kernel-rpm.sh build'
#
# 项目目录挂到容器的 /work，工作目录就是 /work，所以容器里的相对路径和
# 宿主机上一样。容器的架构必须和 runner 一致：镜像仓库里有 x86_64 的
# fedora:45，拉错了会在 qemu 模拟下跑，既慢又容易在 rpm 打包这类地方出怪问题，
# 所以这里显式钉 --platform，并在容器里再核一次 uname -m。
#
# 可选环境变量：
#   FEDORA_CONTAINER_IMAGE     默认 docker.io/library/fedora:45
#   FEDORA_CONTAINER_PACKAGES  进容器后先用 dnf 装上的包
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image=${FEDORA_CONTAINER_IMAGE:-docker.io/library/fedora:45}
packages=${FEDORA_CONTAINER_PACKAGES:-rpm-build tar gzip}

die() { printf 'fedora-container: %s\n' "$*" >&2; exit 1; }
say() { printf 'fedora-container: %s\n' "$*"; }

[ $# -ge 1 ] || die 'usage: fedora-container.sh COMMAND...'

command -v docker >/dev/null 2>&1 || die 'docker is required'

host_arch=$(uname -m)
case $host_arch in
aarch64) platform=linux/arm64 ;;
x86_64) platform=linux/amd64 ;;
*) die "unsupported runner architecture: $host_arch" ;;
esac

say "image $image ($platform), packages: $packages"

# 容器里的命令：先核对架构，再装需要的包，最后执行调用方的命令。
inner='
set -e
want_arch=$1
shift
have_arch=$(uname -m)
[ "$have_arch" = "$want_arch" ] || {
	printf "fedora-container: container reports %s, expected %s (wrong image platform)\n" \
		"$have_arch" "$want_arch" >&2
	exit 1
}
if [ -n "$FEDORA_CONTAINER_PACKAGES" ]; then
	dnf -y install --setopt=install_weak_deps=False $FEDORA_CONTAINER_PACKAGES >/tmp/dnf.log 2>&1 || {
		tail -30 /tmp/dnf.log >&2
		exit 1
	}
fi
exec sh -c "$*"
'

exec docker run --rm --platform "$platform" \
	-e FEDORA_CONTAINER_PACKAGES="$packages" \
	-v "$project_root:/work" \
	-w /work \
	"$image" \
	bash -c "$inner" _ "$host_arch" "$*"
