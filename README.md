# xiaomipad-6pro-mainline（liuqin-install 分支）

Xiaomi Pad 6 Pro（liuqin，**128G**）上的 Ubuntu 26.04 arm64 单系统：
本工作区自建的主线 **7.3** 内核 + 树外驱动，**没有 Android**，
**从 A 槽直接启动**。分区表保持原厂：`boot_a` 换成我们的 boot.img，
`userdata` 是唯一的数据分区（根在这里，`/home` 只是它上面的一个目录），
**不建** `linux_root`/`linux_home`，也**没有** `/boot` 分区。

本分支只维护**本机**的设备状态、装配工具与文档。`main` 是 2026 年从参考项目
v0.6.0 分出来时的用户态骨架，不再更新；参考项目的文档已整体归档到
[`docs/archive/reference-v0.6.0/`](docs/archive/reference-v0.6.0/)，不再作为依据。

## 一条线：一个内核 commit → 两个可刷产物

```
内核仓 linux-sm8450-liuqin（分支 liuqin-7.3）
        │ push
        ▼
GitHub Actions ──▶ ci/liuqin-kernel-<sha>/        锁：kernel/source.json
                      │
                      ├── kernel/（Image + DTB）
                      └── kernel-modules/（.ko + kernel.release）
                      │
        ┌─────────────┴──────────────────┐
        ▼                                ▼
  装配 boot.img                     整机装配（CI）
  Image + DTB + initramfs           Ubuntu + 设备/内核 deb
  + ABL overlay                            │
        │                                  ▼
        │                            rootfs.tar.gz
        │                                  │ 刷机主机转换
        │                                  ▼
        │                             rootfs.img
        ▼                                  ▼
  fastboot flash boot_a          fastboot flash userdata
        └───────────────┬────────────────┘
             冷启动 → 首启 provision → GNOME
```

两样产物必须对得上，工具会在装配时检查，不靠人记：

| 衔接点 | 检查 | 谁检查 |
|---|---|---|
| 内核 commit | artifact 的 `build-info.json` 与 `kernel/source.json` 一致、`SHA256SUMS` 通过 | `build-liuqin-boot.sh`、`build-liuqin-image.py` |
| 内核 ↔ rootfs | rootfs 的 `/usr/share/liuqin/kernel.release` 等于 Image 的 release；rootfs 镜像里该 release 必须有模块目录 | `build-liuqin-native-boot.sh`（整机）、`build-liuqin-rootfs-image.sh`（模块目录） |
| boot ↔ rootfs | boot.img 的 initramfs 内嵌 rootfs 的设备文件契约；不符就拒绝挂载 | `build-liuqin-boot.sh`、initramfs |

由此得到两条规则：**只换内核** → 新 boot.img + 新内核 deb（契约不锁内核文件，
所以契约不变，`userdata` 不动）；**动了用户态** → boot.img 与 rootfs 成对换
（契约随 rootfs 变，整块 `userdata` 重写，`/home` 先备份）。

## 三条命令（开发机 + 刷机主机）

```sh
# 开发机：内核。CI artifact 放进 ci/ 后，一条命令装配 boot.img（含配对检查）
sh tools/build-liuqin-boot.sh          # 加 --deb 同时打出配套的内核 deb

# 刷机主机：用户态。把整机装配产出的 rootfs.tar.gz 变成可刷的 ext4 镜像
sudo sh tools/build-liuqin-rootfs-image.sh --rootfs rootfs.tar.gz --out out/dist

# 刷机主机：连平板
fastboot flash boot_a    repack/<sha6>-boot/boot-liuqin-firstboot.img
fastboot flash userdata out/dist/rootfs.img
```

日常循环只有第 1 条（约 15 秒，不编译内核）。第 2、3 条只在首次安装、重装
rootfs 或用户态更新时用；首启后的一次性 provision 与验收见
[`docs/INSTALL.zh-CN.md`](docs/INSTALL.zh-CN.md)。

## 先读

| 文档 | 内容 |
|---|---|
| [`docs/STATUS.zh-CN.md`](docs/STATUS.zh-CN.md) | **唯一状态源**：设备、内核、已工作/未验证、待办、决策 |
| [`docs/INSTALL.zh-CN.md`](docs/INSTALL.zh-CN.md) | 刷机与更新：分区前提、两条 fastboot、首启 provision、验收、恢复 |
| [`docs/BUILD.zh-CN.md`](docs/BUILD.zh-CN.md) | 从源码到可刷产物：CI、artifact 契约、boot/rootfs 装配、内核 deb |
| [`docs/FEATURES.zh-CN.md`](docs/FEATURES.zh-CN.md) | 指纹/相机/快充/Waydroid 细节（状态以 STATUS 为准） |
| [`docs/display.md`](docs/display.md) · [`docs/AUDIO.zh-CN.md`](docs/AUDIO.zh-CN.md) | 显示点亮、外放 TDM 的结论与判读陷阱 |
| [`docs/kernel-v73-divergence.md`](docs/kernel-v73-divergence.md) · [`docs/userspace-port.md`](docs/userspace-port.md) | 内核偏离清单 / 用户态取舍提案 |
| [`docs/archive/`](docs/archive/) | 冻结的历史取证，不是任务 |

## 铁律

1. 内核只在 GitHub Actions 编译；本机不做 `make`/交叉编译。
2. 不执行 `git push`；本地提交后把 SHA 与命令交给维护者。
3. ROM 输入只用本机 `V14.0.9.0.TMYCNXM`；OS2 是参考项目的 ROM，不混用。
4. 文档只维护中文；英文版已删除，不再生成。
