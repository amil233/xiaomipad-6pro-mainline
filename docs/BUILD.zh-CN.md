# 从产物到刷机

内核在内核仓的 GitHub Actions 编译；整机 rootfs 和配套 boot.img 在集成仓的
`rootfs` workflow 上装配。开发机不跑整机装配，也不需要把 tar 转成 ext4。

## 1. 产物

| 产物 | 内容 | 谁产出 |
|---|---|---|
| `ci/liuqin-kernel-<commit>/` | `kernel/`：Image、设备树、`.config`、`build-info.json`、`SHA256SUMS`；`kernel-modules/`：模块包和版本文件 | 内核仓 CI |
| `rootfs.tgz` | `rootfs.img` 的 Android sparse 版本（`rootfs.simg`）打成的 gzip 包；artifact 里再切成 1900 MiB 的 `rootfs.tgz.part-NN` | 集成仓 `rootfs` workflow |
| `boot.img` | Image + 设备树 + initramfs + ABL overlay，补零到 192 MiB | 同一次 `rootfs` workflow |
| `native-root.hashes` | 这次 rootfs 的文件清单 | 同一次 `rootfs` workflow |
| `liuqin-firstboot.cpio.gz` | boot.img 里的 initramfs | 同一次 `rootfs` workflow |
| `liuqin-kernel_*.deb` | 模块、`/boot` 文件、`kernel.release` | `build-liuqin-boot.sh --deb` |

`kernel/source.json` 只记录内核仓的**分支**、设备树和配置分片，不保存
commit 或哈希。用到的文件都由脚本当场核对。

## 2. 内核 CI

- 推内核仓 `liuqin-7.3`，或手动触发
  `linux-sm8450-liuqin/.github/workflows/liuqin.yml`（`ubuntu-26.04-arm`）。
- CI 用 `kernel/source.json` 的分支和分片构建，产物目录名就是构建出来的
  commit。
- 使用前核对目录名等于 `build-info.json` 的 commit、两个 `SHA256SUMS` 通过、
  `.config` 和分片的哈希一致。

## 3. rootfs 和 boot 的 CI

集成仓的 `.github/workflows/rootfs.yml`：

1. 用 `PAT_GET_KERNEL` 下载内核仓该分支最近一次成功的 artifact；
2. 用仓库里跟踪的固件池、WLAN tuple、传感器配置、AudioReach 子集和 ABL
   分析重建输入；
3. 下载 Ubuntu 26.04.1 桌面 ISO，解出桌面 root，随后删除 ISO 和 casper；
4. 装配 rootfs、对应 boot.img 和 ramdisk；
5. 生成 ext4 的 `rootfs.img`，再转成 Android sparse 的 `rootfs.simg`；
6. 把 `rootfs.simg` 打进 `rootfs.tgz`（tar + gzip），`SHA256SUMS` 记它；
7. 把 `rootfs.tgz` 切成 1900 MiB 的片，和 `boot.img`、`SHA256SUMS`、
   `native-root.hashes`、ramdisk 一起上传。

产物名：`liuqin-rootfs-<commit>`。boot 和 root 来自同一次内核 artifact 和
同一份文件清单，不会错配。

运行环境：`ubuntu-26.04-arm`，清理后约 118 GiB 可用；不需要本地构建机。

## 4. 刷机

下载 artifact 后，在能运行 fastboot 的机器上：

```sh
cat rootfs.tgz.part-* > rootfs.tgz
sha256sum -c SHA256SUMS      # 核对的是 rootfs.tgz，里面的 simg 一并受它覆盖
tar -xzf rootfs.tgz          # 得到 rootfs.simg

fastboot flash boot_a   boot.img
fastboot flash userdata rootfs.simg
fastboot reboot
```

在 Windows 刷机主机上先合并分片，再用 7-Zip 解两层（`rootfs.tgz` → `rootfs.tar`
→ `rootfs.simg`）：

```
copy /b rootfs.tgz.part-* rootfs.tgz
```

首次启动进 `gnome-initial-setup`。进桌面后：

```sh
sudo resize2fs /dev/disk/by-partlabel/userdata
```

分区表必须是原厂表；从旧的 `linux_root`/`linux_home` 迁移见
[`INSTALL.zh-CN.md`](INSTALL.zh-CN.md) 第 1 节。

## 5. 只换内核

rootfs 不变时，不需要重跑整机装配：

```sh
sh tools/build-liuqin-boot.sh --deb
```

用内核仓 CI 的 artifact，加上平板当前 root 的 `out/native-root/native-root.hashes`
和 ramdisk，生成新的 boot.img 和配套 deb。刷 `boot_a`，在系统里装 deb。

用户态变了就要重新跑 `rootfs` workflow，boot.img 和 rootfs 一起换。

## 6. 输入从哪来

| 输入 | 来源 |
|---|---|
| 内核产物 | 内核仓 CI |
| Ubuntu 26.04.1 桌面 ISO | cdimage.ubuntu.com，下载时核对官方 `SHA256SUMS` |
| 固件池、传感器配置 | 已跟踪在 `device/firmware-pool`、`device/sensors/rom` |
| WLAN tuple | 已跟踪在 `device/wlan-tuple` |
| 音频拓扑源码 | 已跟踪在 `device/audio-topology/upstream` |
| ABL overlay/基设备树 | 已跟踪在 `device/abl-analysis` |
| 指纹用户态 | 可选，默认不装；见 [`FINGERPRINT.zh-CN.md`](FINGERPRINT.zh-CN.md) |

外部下载只核对发布方给的校验值；没有校验值的只记录来源和实际哈希，不用
自造的哈希冒充验证。

## 7. 发布

目前没有公开发布包。通用镜像在平板上完整安装、冷启动并逐项检查之前，不标
“已验证”。
