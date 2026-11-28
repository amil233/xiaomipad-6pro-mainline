# 产物怎么来

内核在内核仓的 GitHub Actions 上编译；整机镜像在集成仓的 `fedora-rootfs` 工作流
上装配。开发机不跑整机装配。

## 1. 产物清单

artifact 解开后是平铺的一层（没有 `upload/` 之类的子目录），文件名直接可用。

| 产物 | 内容 |
|---|---|
| `boot.img` | 内核 Image + 设备树 + initramfs + ABL overlay，补零到 192 MiB |
| `rootfs.tgz.part-NN` | Android sparse 的 ext4 镜像（`rootfs.simg`）打成的 tgz，按 1900 MiB 切分 |
| `SHA256SUMS` | 上面那个 `rootfs.tgz` 的哈希 |
| `native-root.hashes.gz` | 装配前那棵树的逐文件哈希（`sha256  /绝对路径`） |
| `rootfs.manifest.gz` | 同一棵树的类型、权限、属主、路径 |
| `kernel-liuqin-*.aarch64.rpm` | 内核模块包，用于只换内核时在系统里升级 |

## 2. 内核 CI

内核仓 `liuqin-7.3-fedora` 分支一推就会构建（跑集成仓的
`.github/actions/kernel`），产物是 `liuqin-kernel-<commit>/`，里面
`kernel/` 有 Image、dtb、`.config`、`build-info.json`，`kernel-modules/` 有
`modules.tar`、`kernel.release`、`modules.manifest`。

内核代码和 `liuqin-7.3` 分支完全一样；区别只在这个分支会去取集成仓的
`liuqin-installer-fedora` 分支，用那份配置（带 SELinux）。

## 3. 镜像 CI（`fedora-rootfs` 工作流）

手动触发（`workflow_dispatch`）或推送到 `liuqin-installer-fedora` 且改动了
`tools/` 下的相关脚本、`initramfs/init`、`device/configs/liuqin-fedora.config`、
工作流本身时触发。它分七段：

1. **下 ISO**：从 `dl.fedoraproject.org` 取
   `Fedora-KDE-Mobile-Live-45-1.4.aarch64.iso`，按官方 `CHECKSUM` 核对；
2. **解根**：抽出 `LiveOS/squashfs.img`（Fedora 42 起实为 EROFS），按魔数判断格式，
   挂上里面的根，整棵树复制出来（保留属主、ACL、SELinux 标签）；
3. **内核包**：下载内核 CI 产物，在 `fedora:45` 容器里打成一个 `kernel-liuqin`
   RPM，装进树里，同时删掉 Fedora 自带的 `kernel*` 包和 `/boot` 内容；
4. **整理树**：写 `/etc/liuqin-native-root`、清 `machine-id`、SELinux 改 permissive，
   写出 `native-root.hashes`；
5. **boot.img**：编扬声器拓扑，用内核产物 + ABL overlay + 新 initramfs 组装；
6. **ext4 镜像**：树放进 `native-root/`，`mke2fs` 成卷标 `LIUQIN_ROOT` 的 ext4，
   过 `e2fsck`、卷标和 `debugfs` 检查；
7. **打包**：`img2simg` → `rootfs.tgz` → 1900 MiB 分片，连同其他产物上传。

树整理完之后还有两步离线校验，都在 CI 上跑，失败就不出镜像：

- `tools/verify-tree-runtime.py`：读每个二进制的 ELF 头，顺着 `DT_NEEDED` 一路
  查到树的库目录里（`libssc → libqmi-glib → libqrtr-glib` 这种间接依赖也查），
  缺库在这里就断，不用等刷机；
- 代理启动链：单元、udev 规则、bus/polkit 策略、`monitor-sensor`、我们的
  `/usr/local` 二进制和 D-Bus 激活条目都存在，且 drop-in 的 `ExecStart` 确实指向
  打过补丁的那份。

运行环境：`ubuntu-26.04-arm`（arm64），约 118 GiB 可用。RPM 相关的部分在
`fedora:45` 容器里跑——GitHub 没有 arm64 的 rpm 系 runner，容器是原生执行，
`tools/fedora-container.sh` 会钉 `--platform linux/arm64` 并核对容器里的
`uname -m`。

## 4. 刷机

见 [`INSTALL.zh-CN.md`](INSTALL.zh-CN.md) 第 2 节。

## 5. 只换内核

boot.img 里钉的是内核版本号，所以只换内核时：

1. 用新的内核产物重新装配 boot.img（同一次工作流的第 5 步，或本地
   `tools/build-liuqin-fedora-boot.sh`）；
2. 平板上装新的 `kernel-liuqin-*.aarch64.rpm`；
3. 刷 `boot_a`。

rootfs 不动。反过来，动了树的任何内容（固件、桌面、包），boot.img 里的版本钉虽然
还能对上，但树已经变了，重新跑一遍工作流更省事。

## 6. 输入从哪来

| 输入 | 来源 |
|---|---|
| 内核产物 | 内核仓 `liuqin-7.3-fedora` 的 CI |
| Fedora Live ISO | `dl.fedoraproject.org`，官方 `CHECKSUM` 核对 |
| 固件池、WLAN tuple、ABL 分析 | 仓库里跟踪的 `device/firmware-pool`、`device/wlan-tuple`、`device/abl-analysis` |
| 音频拓扑源码 | `device/audio-topology/upstream` |

外部下载只核对发布方给的校验值。
