# 从源码到可刷产物

**铁律：内核只在 GitHub Actions 编译。** 开发机 2 核 / 11 GB、无 ccache，只做
`dtc`/`fdtoverlay`/`mkbootimg` 装配和 `dpkg-deb`；刷机主机再跑 `mke2fs`。
详见根 `AGENTS.md` §0.1。

## 1. 产物与锁

| 产物 | 内容 | 谁产出 |
|---|---|---|
| `ci/liuqin-kernel-<sha>/` | `kernel/`：Image、`sm8475-xiaomi-liuqin.dtb`、`.config`、`vmlinux`、`System.map`、`SHA256SUMS`、`build-info.json`；`kernel-modules/`：`modules.tar`、`modules.manifest`、`kernel.release`、`kernel.commit`、`SHA256SUMS` | 内核仓 CI |
| `boot.img` | Image + DTB + initramfs + ABL overlay，刷到 `boot_a` | 本机 `tools/build-liuqin-boot.sh`（日常），或整机装配（成对） |
| `rootfs.tar.gz` | Ubuntu 26.04 桌面 + 设备/内核 deb；路径相对 `/`，保留属主、ACL、xattr | 整机装配（CI） |
| `rootfs.img` | 上面那个 tar 的 ext4 版本，树放在 `native-root/` 下 | 刷机主机 `tools/build-liuqin-rootfs-image.sh` |
| `liuqin-kernel_*.deb` | `/usr/lib/modules/<release>` + `/boot` 载荷 + `/usr/share/liuqin/kernel.release` | 本机 `tools/build-liuqin-debs.sh` |

`kernel/source.json` 是**唯一内核锁**：`commit`、`config_sha256`、10 个配置分片、
`dtb` 名。换内核 = 内核仓分支推进 + 把这里的 `commit` 改成新 tip；配置分片变了，
把新 artifact `build-info.json` 里的 `config_sha256` 抄进来。装配脚本只认这把锁。

## 2. 内核：只走 CI

- 推内核仓 `liuqin-7.3` → `linux-sm8450-liuqin/.github/workflows/liuqin.yml`
  （`ubuntu-24.04-arm`，原生 arm64）。
- artifact 由用户放进工作区根的 `ci/`，**agent 不下载**。
- 使用前两条校验，缺一不可：

```sh
python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' \
  ci/liuqin-kernel-<sha>/kernel/build-info.json     # 必须等于 kernel/source.json
(cd ci/liuqin-kernel-<sha>/kernel && sha256sum -c SHA256SUMS)
(cd ci/liuqin-kernel-<sha>/kernel-modules && sha256sum -c SHA256SUMS)
```

本机**不要**运行 `tools/build-liuqin-kernel.py`——它是 CI 的构建入口。

## 3. 装配 boot.img（日常，约 15 秒）

```sh
sh tools/build-liuqin-boot.sh            # 取锁对应的 artifact，装配到 repack/<sha6>-boot
sh tools/build-liuqin-boot.sh --check    # 只做下面三道检查，不生成镜像
```

它检查三件事，失败就停：

1. artifact 的 commit 等于 `kernel/source.json`，两个 `SHA256SUMS` 都通过；
2. ramdisk 内嵌的 `etc/liuqin-native-root.contract` 等于由
   `out/native-root/native-root.hashes` 重新生成的契约；
3. `dtc`/`fdtoverlay` 可用。

输出目录含 `boot-liuqin-firstboot.img`、`Image.gz`、合并后的 ABL DTB、
`boot-liuqin-firstboot.info`（cmdline、ramdisk、ABL 元数据）。
**已有同名目录不会被覆盖**，换版本用 `--out` 换个名字，旧镜像自然留作回滚。

为什么只换内核时可以复用现成 ramdisk：契约只锁**用户态设备文件**（systemd 单元、
固件、辅助程序）；`/usr/lib/modules/*` 和 `/usr/share/liuqin/kernel.release`
属于内核包，**故意不在契约里**，否则每次内核升级都会被 initramfs 拒绝。所以换内核
时 boot.img 只换 Image/DTB/initramfs，模块和 release 由内核 deb 更新（§6）。

底层是 `tools/lib/build-bootimg.sh`（dtc + fdtoverlay + mkbootimg，内置
round-trip 校验），wrapper 只补前后两道身份检查。

## 4. 整机装配：boot.img + rootfs.tar.gz

入口 `.github/workflows/image.yml`，跑在自托管 x86-64 runner
（`liuqin-images`，手动触发，或仓库变量 `LIUQIN_IMAGE_CI=enabled`）：

```sh
sudo python3 tools/build-liuqin-image.py --inputs <inputs.json> --kernel-out <内核构建目录>
```

- 阶段可续跑：`modules → debs → copy → install → assemble → manifest → boot →
  pack → bundle`，`--stage <名字>` 从某一步继续；`--out` 必须在 `out/` 下。
- **不在本机跑**：需要 root、ARM64 chroot（apt/dpkg）、GNU tar/ACL/xattr、
  squashfs，2 核笔记本不具备这个条件。
- 产物是 `out/image/bundle/`：`boot.img`、`rootfs.tar.gz`、`native-root.hashes`、
  `liuqin-firstboot.cpio.gz`、`bundle.json`、`SHA256SUMS`，加上安装/构建/功能
  文档和指纹构建输入。
  `native-root.hashes` 是 boot.img 内嵌契约的来源清单，`liuqin-firstboot.cpio.gz`
  是携带该契约的 initramfs。刷完这套镜像后把这两个文件拷到开发机的
  `out/native-root/native-root.hashes` 和
  `out/initramfs-liuqin/liuqin-firstboot.cpio.gz`，下一轮只换内核的装配就能用
  它们核对“新 Image + 实机 root”（BUILD §3）。

rootfs 与内核是怎么对上的：

1. deb 里的 `.ko` 来自同一个 artifact（`modules` 阶段直接复用 CI 打包好的模块集）；
2. `manifest` 阶段把设备文件哈希写成 `native-root.hashes`，
   `build-root-contract.py` 再把它变成 initramfs 内嵌的契约；
3. `boot` 阶段同时检查 root 的 `kernel.release` 等于 Image 的 release。

所以**同一 bundle 里的 boot.img 与 rootfs.tar.gz 是一对**，不要跨 bundle 混用。

## 5. 把 rootfs 变成可刷镜像（刷机主机）

```sh
sudo sh tools/build-liuqin-rootfs-image.sh --rootfs rootfs.tar.gz --out out/dist
# 连 /home 也重装时（会清空 /home）：
sudo sh tools/build-liuqin-rootfs-image.sh --rootfs rootfs.tar.gz --out out/dist --home-size 8G
```

- **为什么需要这一步**：fastboot 写块设备；initramfs 把
  `<linux_root>/native-root` 绑定成 `/`，所以树必须放在这个子目录。
- 工具做什么：解包（`rootfs-archive.sh`，保留属主/ACL/xattr）→ 校验 marker 与
  模块目录 → 补 `/etc/fstab` 的 `LABEL=LIUQIN_HOME /home`（这是布局，不属于
  共享 rootfs）→ `mke2fs -d` → `e2fsck`/`dumpe2fs` 验证。
- 默认大小 = 树 + 25%（至少 6G）。刷进分区后可以
  `resize2fs /dev/disk/by-partlabel/linux_root` 长到整分区。
- 只适用于**已存在** `linux_root`（以及可选的 `linux_home`）的设备；分区表是
  一次性前提，见 `INSTALL.zh-CN.md` §1。

## 6. 内核 deb：更新内核的另一半

```sh
sh tools/build-liuqin-debs.sh kernel
# → out/liuqin-debs/liuqin-kernel_0.1_arm64.deb
```

纯文件包：`/usr/lib/modules/<release>`（自带 `modules.dep`）、
`/boot/{vmlinuz,initrd,dtb}-<release>`、`/usr/share/liuqin/kernel.release`。
没有维护脚本，装机后不需要 `depmod`；`/boot/initrd` 也不参与启动——启动用的
initramfs 在 boot.img 里。更新内核时它与新 boot.img 一起上机：
**deb 换模块与 release，boot.img 换 Image/DTB/initramfs**；契约不变。
上机顺序见 `INSTALL.zh-CN.md` §3。

## 7. 发布与验收

**本项目目前没有公开发布包。** bundle 的 `bundle.json` 默认
`OFFLINE_ASSEMBLED`，只有本机完整安装、冷启动、功能复核之后才能标
`DEVICE_TESTED`（`--stage release-assets --device-tested`）。安装路径相关文件
一变，就必须重新真机验收——这是 `build-liuqin-image.py` 里的构建期断言，
不是文档约定。
