# 换 Fedora KDE Plasma Mobile 的计划（计划稿，未执行）

**状态：只做计划。** 没有新建分支，没有改任何脚本，没有碰平板。开工前先过第 7 节的
决策点；每个阶段的完成标准写在第 5 节。

## 1. 动机和代价

现在跑的是 Ubuntu 26.04.1 arm64 desktop（GNOME），已经按
[`INSTALL.zh-CN.md`](INSTALL.zh-CN.md) 装到实机。换 Fedora KDE Plasma Mobile
Spin 能换来什么、要付什么，要一起看：

| | 换来什么 | 要付什么 |
|---|---|---|
| 桌面 | Plasma Mobile 本来就是触摸优先的形态（虚拟键盘、移动布局、手势）；GNOME 侧要靠 `liuqin-osk-guard` 这类扩展补 | `device/gnome-overlay` 里所有 GNOME 专属件（gnome-control-center 电源面板、gnome-shell 扩展、gdm/dconf 策略）在 KDE 上没有对应物，要逐项重做 |
| 发行版 | Fedora 45 的内核就是 7.3.6（工作区里 `fedora-kernel-src` 就是 `rpms/kernel` 的 f45 分支），和我们的 `liuqin-7.3` 同代 | 打包从 deb 换 RPM，chroot 从 apt 换 dnf，SELinux 默认 enforcing |
| 启动链 | 不变：`boot_a` + `userdata`，自定义 initramfs，文件哈希清单 | 不变 |

内核和启动链这两层几乎不动，这是这次评估里最重要的结论：**换发行版是用户态工程，
不是内核工程。** 内核侧唯一要动的是"把模块打成什么包"。

## 2. 现状里哪些是 Ubuntu/Debian 特有的

按"改起来难不难"排：

| # | 环节 | 现在怎么做 | Fedora 侧对应 | 改动量 |
|---|---|---|---|---|
| 1 | 基础 rootfs 来源 | Ubuntu ISO 的 casper squashfs：`tools/build-liuqin-ubuntu-desktop-rootfs.sh`（校验 SHA256SUMS → 7z 抽 squashfs → `unsquashfs` → 写 manifest） | Fedora 45 的 aarch64 同时有 Live ISO（`Fedora-KDE-Mobile-Live-45-1.4.aarch64.iso`，2.54 GiB）和 Disk 镜像（`...raw.xz`，2.78 GiB 压缩 / 11.7 GiB 解压）。Live ISO 里是 squashfs 套 ext4 的 `rootfs.img`，和 casper 同构，改动最小；Disk 镜像的根是 btrfs 子卷，要动 initramfs | 小–中 / 大 |
| 2 | 打包 | `dpkg-deb` 打 5 个包（firmware / device-support / sensors / kernel / meta），chroot 里 `apt-get` + `dpkg -i` | `rpmbuild` 打对应 RPM，chroot 里 `dnf install` | 大 |
| 3 | 内核模块交付 | `.deb` 里带 `/usr/lib/modules/<release>` + `/boot` 载荷 | Fedora 拆 `kernel-core` / `kernel-modules` / `kernel-modules-extra`，都是 `/lib/modules/<KVERREL>/`；`modules.dep*`、`modules.alias*` 等是 `%ghost`，装的时候由 `depmod -a` 生成 | 中 |
| 4 | initramfs | 自定义 `cpio.gz`：busybox + 根文件哈希清单 + ext4 只读校验后切根 | **不动**（与发行版无关，只认 ext4）；但 Fedora 的 `kernel-core` 装完会跑 `kernel-install`、`kernel-modules` 会跑 `dracut`，必须屏蔽 | 小 |
| 5 | 首次启动 | `gnome-initial-setup` 建用户，GDM | Fedora 44 起 KDE 系统一走 **plasma-setup**（`kde-mobile` 包组里就有），登录管理器是 SDDM/plasma-login-manager | 中 |
| 6 | 桌面策略 | `device/gnome-overlay`：gnome-control-center 电源面板（从源码编）、gnome-shell `osk-guard` 扩展、gdm/dconf 锁、GNOME Snapshot | KDE 没有等价物，要换成 Plasma 设置模块 / KWin 脚本 / SDDM 配置；这是最大的一块 | 大 |
| 7 | 系统服务与策略 | NetworkManager keyfile、BlueZ `main.conf`、udev 规则、systemd unit | 基本通用：NM keyfile 同一路径；DNS 走 `systemd-resolved`（F33 起默认）；AppArmor 换 SELinux | 中 |
| 8 | 用户态组件 | `hexagonrpcd`、SSC sensor registry、`iio-sensor-proxy`、ALSA UCM2、指纹 | UCM2 路径一致；其余自建件与发行版无关；`iio-sensor-proxy`、`libfprint` 在 Fedora 有对应包，版本要逐项确认 | 小–中 |

结论：工作量的 80% 在第 2、3、6 项；第 1 项走 Live ISO 路线时很小，走 Disk 镜像路线
会连带改 initramfs。

## 3. 分支和仓库规划

### 内核仓 `linux-sm8450-liuqin`：新分支 `liuqin-7.3-fedora`

- 从 `liuqin-7.3` 派生，**只改打包，不改内核代码和配置碎片**。
- 目标产物：Fedora 风格的内核 RPM，能 `rpm -i` 进 Fedora rootfs，`/usr/lib/modules/<release>/modules.dep` 完整。
- 注意结构：内核仓自己的 CI 只调用集成仓的复合 action
  （`xiaomipad-6pro-mainline/.github/actions/kernel`），所以真正要改的是集成仓里那段
  打包逻辑，内核仓分支主要提供"跟哪个基线、用什么配置"。
- 基线选择见决策点 D3：Fedora 45 的 `kernel.spec`（本地 `fedora-kernel-src`，7.3.6-300）
  当模板，或者继续用我们自己的精简 config + `make binrpm-pkg`（后者打出来的包结构与
  Fedora 的 `kernel-core` 完全不同，别混着用）。

### 集成仓 `xiaomipad-6pro-mainline`：新分支 `liuqin-installer-fedora`

- 从 `liuqin-install` 派生，新增：
  - `tools/build-liuqin-fedora-rootfs.sh`：下载 / 校验 / 抽 Live ISO 的 squashfs / 解 `rootfs.img` / 写 manifest；
  - `tools/build-liuqin-rpms.sh`：第 2 项里的 5 个 RPM（对应现在的 `build-liuqin-debs.sh`）；
  - `tools/build-liuqin-fedora-image.sh`：chroot `dnf install` + 首启整理（对应 `build-liuqin-native-root.sh`）。
- 原样保留：`initramfs/`、`tools/build-liuqin-native-boot.sh`、
  `tools/build-liuqin-rootfs-image.sh`（只把 "not an Ubuntu root" 这类断言换成发行版中立的写法）、
  `tests/`、`provision-liuqin-from-persist.sh`（与发行版无关，可直接复用）。
- 分支隔离：`kernel/source.json` 的 `branch` 指向 `liuqin-7.3-fedora`；
  `rootfs.yml` 里换成新分支名或加一个 `vars` 开关；两条线的 checks 各自独立，不互相阻塞。

## 4. 阶段 0 要回答的问题

1. `Fedora-KDE-Mobile-Live-45-1.4.aarch64.iso` 里的 `LiveOS/squashfs.img` 结构：解出来
   是不是 ext4 的 `rootfs.img`，`unsquashfs` + 挂载能不能拿到干净的根，体积多大。
2. Disk 镜像实测：根分区 9.28 GiB、btrfs、`used` 3.38 GiB（子卷 `root`/`home`/`var`，
   挂在 `/`、`/home`、`/var`）。这意味着"直接换成官方 btrfs 根"要动 initramfs，
   而"把内容搬进 ext4"又要处理子卷和 `compress=zstd`。
3. 离线装配的 rootfs 首启时 SELinux 的实际行为：`selinux-policy-*` 的 `%post` 自带
   `restorecon`/`fixfiles`，但整盘标签是否足够、要不要 `.autorelabel`。
4. Fedora 内核 RPM 的 `%posttrans`（`kernel-install` / `dracut`）在我们这套没有 `/boot`
   分区的布局里会做什么，怎么安全地屏蔽。

## 5. 分阶段工作和完成标准

| 阶段 | 做什么 | 完成标准 | 在哪做 |
|---|---|---|---|
| 0 可行性 | 从 Live ISO 抽一份 rootfs tar；统计包清单、体积、SELinux 状态；确认 `plasma-mobile` 6.8.1 装齐 | 能在 aarch64 runner 上 `chroot` 跑 `rpm -qa`；体积能进 8 GiB ext4 镜像（官方根实测占 3.38 GiB，够）；Plasma Mobile 装得上 | CI，不碰平板 |
| 1 内核 RPM | 出 kernel RPM，装进阶段 0 的 rootfs | `rpm -i` 后模块树完整、`modules.dep` 存在；沿用现有 rootfs 装配 gate（systemd 可执行、marker、`kernel.release`） | CI |
| 2 镜像装配 | 走通 rootfs.img + boot.img + hashes + tgz 分片 | `e2fsck` / label / debugfs 门禁与 Ubuntu 线同构；产物清单可直接刷机 | CI |
| 3 首启 | 第一次上机：刷 `boot_a` + `userdata`，进 Plasma Mobile，触控可用，能建用户 | 冷启动三次成功；`provision-liuqin-from-persist.sh` 与 `resize2fs` 按 INSTALL 第 2 节走通 | 真机（用户在场一次） |
| 4 打磨 | 硬件逐项回归（音频 4ch/24bit、传感器、指纹、相机、亮度、挂起）、SELinux 策略、文档与回滚 | STATUS 表里每一项有明确结论；回滚到 Ubuntu 线的步骤写成文档 | 真机 + CI |

阶段 0 和 1 不改变任何现有行为，可以随时停；阶段 3 才是有代价的一步。

## 6. 工作量估算（粗估，阶段 0 后校正）

| 阶段 | 人日 | 说明 |
|---|---|---|
| 0 | 1–2 | 主要是抽镜像、跑 dnf、确认包集合 |
| 1 | 2–4 | RPM 打法和 `%posttrans` 隔离是主要摩擦 |
| 2 | 2–3 | 复用现有装配与打包链路，改动集中在断言和路径 |
| 3 | 5–10 | 桌面能不能起、SELinux、首启流程，不确定最大 |
| 4 | 5–10 | 硬件逐项回归 + 策略 + 文档 |
| 合计 | **约 3–6 周** | 单人、CI 可用、不走弯路的前提下 |

## 7. 需要你拍板的决策

| ID | 问题 | 选项 | 建议 |
|---|---|---|---|
| D1 | 拿哪种 Fedora 产物当基础 | (a) Live ISO 里的 squashfs → ext4 `rootfs.img`（和现在 casper 路线同构）；(b) 官方 Disk 镜像的 btrfs 根直接搬；(c) Fedora Minimal + `dnf group install kde-mobile` | (a)。(b) 会把 btrfs 一起引进来，(c) 等于自己拼 spin，都留作退路 |
| D2 | 根文件系统 | ext4（现状，initramfs 与哈希清单不动）/ btrfs（要改 initramfs、`LIUQIN_ROOT` 识别、哈希清单） | ext4。btrfs 是另一个独立工程，别和换发行版捆在一起 |
| D3 | 内核打包基线 | (a) 跟 Fedora `kernel.spec` 7.3.6 的结构；(b) 自己的 config + `make binrpm-pkg` | 先 (b) 打通，再评估 (a)。(a) 的好处是以后能直接跟 Fedora 内核更新 |
| D4 | SELinux 起步档位 | permissive / enforcing / disabled | permissive 起步，阶段 4 再收紧；disabled 不在候选里（Fedora 生态会破） |
| D5 | Ubuntu 线是否保留 | 并行维护到阶段 3 通过 / 立即切换 | 并行。Ubuntu 线现在是可用系统，也是回滚路径 |
| D6 | 释放形态 | 单系统替换（现状）/ 双系统 | 单系统。分区表里只有 `userdata` 一个数据分区，双系统要重分区，代价不成比例 |

## 8. 风险和缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| SELinux 打标不全 | 首启服务被拒、桌面起不来 | 阶段 3 先 permissive + `.autorelabel`，策略在阶段 4 补 |
| Plasma Mobile 体积与依赖 | 8 GiB 镜像放不下，或缺 flatpak/远程仓库导致首启慢 | 阶段 0 量化；必要时裁包、去掉 `fedora-flathub-remote` 预置 |
| GNOME 那套触摸策略要重写 | 虚拟键盘/旋转/亮度在 KDE 下行为不同 | 阶段 0 就列映射表：osk-guard → KWin 脚本 / Plasma 输入法设置 |
| Plasma Mobile 只支持主线内核 | 不能退回 Android HAL 路线 | 已经是主线内核 + Mesa，路径一致；文档见 KDE porting 页 |
| 音频后端差异 | Plasma 的 Phonon 只有 VLC 后端（Qt6），我们验的是 PipeWire/ALSA 直通 | 阶段 3 先按 PipeWire 走，VLC 后端有问题就换应用层 |
| Fedora 生命周期 13 个月 | 每年至少一次大版本升级 | 升级路径（`dnf system-upgrade`）在阶段 4 验证，写进文档 |
| 内核 RPM 的 `%posttrans` 插手 `/boot` | 生成多余 initramfs 或安装失败 | 装包时 `--noscripts` 或做空 stub，装完手动 `depmod -a <ver>`，写进装配脚本 |

## 9. 现在就能做的准备工作（无副作用）

1. 留着 `fedora-kernel-src`（Fedora 45 的 `kernel.spec`，7.3.6-300）当模板参考。
2. 阶段 0 的脚本可以先写在新分支上跑 CI，不合并、不改 `liuqin-install` 的任何流程。
3. 把 Ubuntu 线的现状钉住（[`STATUS.zh-CN.md`](STATUS.zh-CN.md)），它是回滚路径。

## 10. 明确不做

- 不在本机编译、不在本机跑 Fedora chroot 装配（CI 做，和现在的分工一致）。
- 不在决策点确认前新建分支或改现有脚本。
- 不为了"能装上"而长期关掉 SELinux，也不为了省事把根换成 btrfs。

## 11. 参考

- Spin 与下载：<https://fedoraproject.org/spins/kde-mobile/>、<https://fedoraproject.org/spins/kde-mobile/download/>、立项 Change <https://fedoraproject.org/wiki/Changes/Fedora_KDE_Plasma_Mobile>
- aarch64 产物目录：<https://dl.fedoraproject.org/pub/fedora/linux/releases/45/Spins/aarch64/iso/>、`.../Spins/aarch64/images/`
- 官方镜像构建描述（kiwi）：<https://forge.fedoraproject.org/releng/kiwi-descriptions>
- 移动桌面包组：<https://docs.fedoraproject.org/en-US/kde/getmobile/>、<https://fedoraproject.org/wiki/SIGs/KDE/Mobile>
- Unified KDE OOBE（plasma-setup）：<https://fedoraproject.org/wiki/Changes/Unified_KDE_OOBE>
- dnf5 installroot：<https://dnf5.readthedocs.io/en/latest/misc/installroot.7.html>
- Fedora 内核 spec：<https://src.fedoraproject.org/rpms/kernel/raw/rawhide/f/kernel.spec>；自定义内核：<https://docs.fedoraproject.org/en-US/quick-docs/kernel-build-custom/>
- Plasma Mobile 移植（只支持主线内核）：<https://develop.kde.org/docs/packaging/plasma-mobile/porting/>
