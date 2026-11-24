# 从源码到可刷产物

内核在 GitHub Actions 编译，整机 rootfs 在构建机或集成仓的自托管 runner 上装配。
开发机不在本地编译，是因为 CI 更快、磁盘和时间更省，不是这台机器做不了。

这里的四台机器各干各的：

| 角色 | 做什么 |
|---|---|
| 开发机 | 本工作区这台 Ubuntu 26.04.1 arm64（2 核 / 11 GB）：装配 boot.img、打内核 deb、离线检查 |
| 构建机 | 另一台 arm64，40 GB 以上空闲：装配整机 rootfs（Ubuntu 桌面太大，开发机放不下） |
| 刷机主机 | 树莓派：把 `rootfs.tar.gz` 转成 ext4 镜像，fastboot 刷机 |
| 平板 | liuqin 本体，只接收镜像 |

仓库里**不保存内核 commit、配置哈希或镜像哈希**。用到的每个文件都由脚本在
当场核对：产物目录名和它自己的 `build-info.json` 对得上、`SHA256SUMS` 通过、
配置文件哈希和仓库里的分片一致、boot.img 里的 rootfs 文件清单和实际 rootfs
一致。数字会变，检查不会过期。

## 1. 产物

| 产物 | 内容 | 谁产出 |
|---|---|---|
| `ci/liuqin-kernel-<commit>/` | `kernel/`：Image、设备树、`.config`、`build-info.json`、`SHA256SUMS`；`kernel-modules/`：模块包和版本文件 | 内核仓 CI |
| `boot.img` | Image + 设备树 + initramfs + ABL overlay，刷到 `boot_a` | 开发机 `tools/build-liuqin-boot.sh`，或整机装配 |
| `rootfs.tar.gz` | Ubuntu 26.04 桌面加设备/内核 deb，路径相对 `/`，保留属主、ACL、xattr | 构建机 `tools/build-liuqin-rootfs.sh` |
| `rootfs.img` | 上面 tar 的 ext4 版本，刷到 `userdata` | 刷机主机 `tools/build-liuqin-rootfs-image.sh` |
| `liuqin-kernel_*.deb` | 内核模块、`/boot` 文件、`kernel.release` | 开发机 `build-liuqin-boot.sh --deb` |

`kernel/source.json` 只记录三样东西：内核仓的**分支**、设备树路径、参与配置
的**分片文件列表**。没有 commit，也没有哈希。

## 2. 内核：只在 CI 编译

- 推内核仓 `liuqin-7.3`，或在内核仓手动触发，跑
  `linux-sm8450-liuqin/.github/workflows/liuqin.yml`（`ubuntu-24.04-arm`）。
- CI 用 `kernel/source.json` 的分支和分片构建，产物目录名是构建出来的
  commit。用户把产物放进 `ci/`，agent 不下载。
- 用之前脚本会自己核对：目录名等于 `build-info.json` 里的 commit、两个
  `SHA256SUMS` 通过、`.config` 的哈希等于构建时记录的值、分片哈希和仓库
  当前文件一致。

开发机不要运行 `tools/build-liuqin-kernel.py`；那是 CI 的入口。

## 3. 装配 boot.img（开发机，约 15 秒）

```sh
sh tools/build-liuqin-boot.sh            # 取 ci/ 里最新的产物，输出 repack/<commit>-boot
sh tools/build-liuqin-boot.sh --deb      # 同时打配套的内核 deb
sh tools/build-liuqin-boot.sh --check    # 只检查，不生成
```

脚本做三件事：

1. 找到 `ci/` 里的内核产物，核对目录名、commit、`SHA256SUMS`、模块版本；
2. 从 `out/native-root/native-root.hashes` 重新算出 rootfs 文件清单，和
   initramfs 里的那份比较，不一致就停（说明 initramfs 是为另一份 rootfs
   做的）；
3. 调 `tools/lib/build-bootimg.sh` 装配，内部再做一次解包/重打包的往返检查。

输出目录里有 `boot-liuqin-firstboot.img`、`Image.gz`、合并后的设备树和
`boot-liuqin-firstboot.info`。已有同名目录不会被覆盖；换版本用 `--out`。

只换内核时 rootfs 不变，所以文件清单不变，旧 ramdisk 可以继续用；内核模块
和版本号由新的内核 deb 更新。动了用户态，清单会变，boot.img 和 rootfs 要
一起重新生成。

脚本还会读 `out/liuqin-debs` 里内核 deb 的版本：如果它和这次 Image 的版本
不一致，会提示先装配套的 deb，或者加 `--deb` 让两半一起生成。

## 4. 装配整机（构建机）

```sh
sudo sh tools/build-liuqin-rootfs.sh --check   # 报告还缺什么
sudo sh tools/build-liuqin-rootfs.sh           # 准备输入，然后装配
```

`--check` 逐项检查：是不是 arm64（或有没有 qemu binfmt）、是不是 root、空闲
空间、需要的命令、Ubuntu 桌面基础系统、内核产物、V14 提取树、WLAN 固件、
固件池、busybox/mkbootimg、AudioReach 源码。

正式运行分三步：

1. 第一次运行时下载 Ubuntu 26.04 桌面 ISO，校验后解出基础系统；
2. `tools/prepare-image-inputs.py run` 重建需要的输入（传感器用户态、GNOME
   设置程序、音频拓扑、固件树），没变的会复用缓存；
3. `tools/build-liuqin-image.py` 依次做模块、deb、根目录装配、文件清单、
   boot.img、打包，结果在 `out/image/bundle/`。

bundle 里有 `boot.img`、`rootfs.tar.gz`、`native-root.hashes`、
`liuqin-firstboot.cpio.gz`、`bundle.json`、`SHA256SUMS` 和文档。

构建机需要：

| 项 | 要求 |
|---|---|
| 架构 | aarch64（原生 chroot）；x86 需要 qemu-aarch64 和 binfmt 的 P 标志 |
| 权限 | root（chroot、属主、tar 的 ACL/xattr） |
| 磁盘 | 40 GB 以上 |
| 命令 | `dpkg-deb`、GNU `tar`、`unsquashfs`、`7z`、`m4`、`alsatplg`、`zstd`、`patch`、`git`、`curl`、`chroot`/`mount`/`unshare` |
| 输入 | `tools/local`、V14 提取树、AudioReach 源码、内核产物 |

Ubuntu 26.04 上一次装齐：

```sh
sudo apt install 7zip squashfs-tools erofs-utils mtools alsa-utils m4 zstd \
  patch build-essential git curl dpkg-dev
```

构建机不需要内核源码：模块直接用产物里的 `kernel-modules/`（先核对 commit、
版本和校验和），`dtc`/`fdtoverlay` 用系统包。

集成仓的 `.github/workflows/image.yml` 是同一套脚本的另一条入口（自托管
x86-64 runner，需要 `LIUQIN_IMAGE_CI=enabled`），产物和构建机一致；
`.github/workflows/build.yml` 在集成仓 push 时也能编译内核。

## 5. 把 rootfs 变成可刷镜像（刷机主机）

```sh
sudo sh tools/build-liuqin-rootfs-image.sh --rootfs rootfs.tar.gz --out out/dist
```

- fastboot 只能写块设备，所以要把 tar 变成 ext4；initramfs 把
  `<userdata>/native-root` 当作 `/`，树就放在这个子目录里。
- 工具会校验文件清单里的标记、内核模块目录和卷标，生成
  `LABEL=LIUQIN_ROOT` 的 ext4，再用 `e2fsck` 和 `dumpe2fs` 检查一遍。
  它不改 `/etc/fstab`：没有第二个分区要挂载。
- 默认大小是树的 1.25 倍（至少 6 GB）。刷进 `userdata` 后用
  `resize2fs /dev/disk/by-partlabel/userdata` 扩到整个分区。
- 这台平板的分区表必须是原厂的；分区表操作见 INSTALL 第 1 节。

## 6. 内核 deb

```sh
sh tools/build-liuqin-boot.sh --deb
# → out/liuqin-debs/liuqin-kernel_0.1_arm64.deb
```

它就是 `build-liuqin-debs.sh kernel` 加上从产物里取好的模块、Image 和设备树。
包是纯文件：模块目录（自带依赖索引）、`/boot` 下的内核文件和
`kernel.release`。没有维护脚本，装完不用 `depmod`；`/boot` 下的 initrd 不
参与启动，启动用的是 boot.img 里的 initramfs。

更新内核时，deb 和新的 boot.img 一起上机，顺序见 INSTALL 第 3 节。

## 7. 输入从哪来

通用镜像的输入都能从 V14 线刷包和公开上游得到，不需要额外提供文件：

其中三样可以在这台开发机上先准备好，不需要 root，也不编译：

```sh
# AudioReach 源码（约 1 MB）
git clone https://github.com/linux-msm/audioreach-topology tools/local/audioreach-topology
# 板级 m4 文件是按 2026-08-24 的源码写的；换别的版本可能生成不同的 topology
git -C tools/local/audioreach-topology checkout \
  "$(git -C tools/local/audioreach-topology log --before=2026-08-25 -1 --format=%H)"

# 传感器栈的三个源码仓库（约 4 MB），按 sources.manifest 的 commit 检出
SOURCES_ONLY=1 sh tools/build-liuqin-sensors-stack.sh

# GNOME 设置程序的源码和补丁（约 54 MB）
python3 tools/build-liuqin-settings.py --prepare-only --out out/prepared-inputs/settings
```

真正编译传感器栈和 GNOME 设置程序（也就是生成二进制缓存）需要 root 和
Ubuntu 桌面 root，在构建机上执行：

```sh
sudo python3 tools/prepare-image-inputs.py run
```

它复用上面三份源码，写出 `tools/local/artifacts-cache/`（传感器栈 tar 和
`gnome-control-center` 二进制）和 `out/prepared-inputs/`。这两处都在
`.gitignore` 里，不提交；把 `tools/local/` 和 `out/prepared-inputs/` 一起拷
到构建机，构建机就不用重新下载或重编这些慢输入。


| 输入 | 来源 |
|---|---|
| Ubuntu 26.04 桌面 ISO | cdimage.ubuntu.com，下载时核对官方 `SHA256SUMS` |
| 触摸/GPU/VPU/传感器配置 | V14 `super.img` 的 vendor 分区；`tools/extract-v14-vendor.sh` 解出 |
| WLAN qca6490 固件 | V14 `NON-HLOS.bin`（modem 分区的 FAT）里的 `/qca6490/` |
| 指纹固件 | 同一个 FAT 根目录的 `fpcliu.*` |
| 指纹用户态 | `device/fingerprint/oem/` 的源码；默认另下载参考项目 v0.6.0 发布包里的预编译输入（解压时核对包内 `SHA256.json`），可用 `FINGERPRINT_BUNDLE` 换成本地重建的包 |
| 蓝牙固件 | V14 `BTFM.bin` |
| ABL 覆盖层和基设备树 | V14 `dtbo.img`、`vendor_boot.img` |
| WLAN 上游固件 | linux-firmware 的 WCN6855 文件 |
| WLAN bdencoder | qca-swiss-army-knife 的 `ath11k-bdencoder`（Python） |
| 音频拓扑 | linux-msm/audioreach-topology |
| GNOME 设置、传感器、fprintd 源码 | Ubuntu 源和 `device/` |
| 每机校准（MAC、蓝牙地址、喇叭校准、传感器数据） | 平板自己的 `persist` 分区，第一次启动时导入，不进镜像 |

外部文件只核对**发布方给的**校验值：Ubuntu ISO 对 Canonical 的
`SHA256SUMS`，Ubuntu 软件包交给 apt 的签名元数据，AOSP 工具用 git 传输时的
对象校验，指纹包用它自带的 `SHA256.json`。没有发布方校验值的下载（例如
WLAN bdencoder 的 tarball）只记录来源和实际哈希用于识别，不自己生成一个
“校验值”再比对；那只能发现本地文件变了，不能证明下载可信。

镜像里**不放**每机校准。线刷包里的 `persist.img` 是通用数据，用了会把别的
机器的 MAC 和校准带进来。

## 8. 发布

目前没有公开发布包。bundle 的 `bundle.json` 默认标 `OFFLINE_ASSEMBLED`；
只有在平板上完整装过、冷启动并逐项检查之后，才能标 `DEVICE_TESTED`。
