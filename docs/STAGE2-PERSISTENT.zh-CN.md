# Stage 2：持久化单系统 Ubuntu（arm64 宿主执行手册）

把已点亮的 v7.3 内核与 Ubuntu 26.04 LTS 桌面系统持久安装到
Xiaomi Pad 6 Pro（liuqin），使平板成为一台单系统 ARM PC：
**不含 Android，不做双系统**，整片 userdata 尾部空间交给 Ubuntu。

[构建总览](BUILD.zh-CN.md) ｜ [安装步骤](INSTALL-TESTING.zh-CN.md) ｜
[刷机须知](FLASHING.zh-CN.md)

---

## 0. 定位与分工

- **谁来执行**：你在连接平板实机的 **arm64 原生** Linux 机器上执行全部步骤。
  本手册不替你做任何下载、解包或刷写；所有命令都需要你确认后亲自运行。
- **分工**（与 6.17–7.3 点亮验证相同的模式）：
  - **内核编译交给 GitHub Actions**——推 `liuqin-7.3` 到 GitHub 触发
    `build.yml`（`ubuntu-24.04-arm` 托管 runner，原生 arm64 编译），
    产物就是 `ci/liuqin-kernel-<SHA>/` 的两个目录；
  - **你的 arm64 机器做组装**——桌面根提取、固件物料准备、镜像装配，
    不编译内核（`build-liuqin-image.py` 只消费 CI artifact）；
  - **唯一碰设备的工具**是 `install-liuqin.py`。
- **为什么 arm64 原生**：chroot 阶段（deb 安装、传感器栈、GNOME 设置程序）
  在 arm64 宿主上原生执行，不需要 qemu/binfmt；管线已为此放宽
  （`build-liuqin-native-root.sh` 在 `uname -m`=aarch64 时跳过 binfmt 检查；
  `build-liuqin-debs.sh` 的编译器回退 `gcc` 并断言目标架构）。
- **单系统边界**：`--layout linux-only`。安装器只动 B 槽与尾部分区，
  不需要 ROM 目录、不恢复 Android 固件分区、不写 `super`/`metadata`。

## 1. 现状与前置事实

| 项 | 值 | 证据 |
|---|---|---|
| 点亮内核 | `liuqin-7.3` @ `db08160915e3`（`7.3.0-gdb08160915e3`） | `docs/kernel-version-upgrade.md` §13；CI run 41409689334 |
| **产品锁** | `kernel/source.json` 已推进到 `liuqin-7.3 @ db08160915e3`（本手册配套提交 `3a56981`） | 锁值与 CI `build-info.json` 一致；`config_sha256` 与 10 个分片哈希不变 |
| 基础系统 | Ubuntu Desktop 26.04 LTS arm64（`c2afd538…` / 4161089536 B） | `tools/build-liuqin-ubuntu-desktop-rootfs.sh` 钉扎 |
| ROM 输入 | **全部用 V14.0.9.0.TMYCNXM**（设备实际在装的 ROM，点亮全程在用）；ROM 内容哈希钉扎默认仍是 OS2 值，V14 提取后覆盖 | 见 §2-3 说明 |
| 单系统布局 | 删 userdata，尾部建 `linux_root`(36)+`linux_home`(37)，boot 镜像写 `boot_b`，`--set-active b` | `tools/lib/liuqin_layout.py:340-360`；`install-liuqin.py:36` |
| 设备门槛 | 出厂分区表、4096 逻辑扇区、userdata 为最后一个分区、Bootloader 解锁、电量 ≥30% | `FLASHING.zh-CN.md`；`liuqin_layout.py:274` |

> **存储空间**：你已确认机器内部存储远大于本流程需要（内核构建树 + 双桌面树
> + rootfs 归档约需 60 GB 量级），此项不设关卡。

**一个硬约束（不可绕过）**：`build-liuqin-image.py` 校验 kernel artifact 的
`build-info.json.commit` 必须等于 `kernel/source.json` 锁值。锁已推进到
`db08160915e3`，CI artifact 自报同一 commit，所以**此关已通**。若之后换内核
版本（例如 v7.4），锁必须同步推进，否则组装直接 `parser.error`。

## 2. ROM 输入：两个来源，各管一侧

整条链路对 ROM 的消费分两类，来源不同：

| 侧 | 输入 | 来源 | 你要做的 |
|---|---|---|---|
| **boot 镜像侧** | ABL overlay 符号集（DTBO 条目 + 基 DTB） | **V14.0.9.0** 线刷包的 `dtbo.img`/`vendor_boot.img` | 用仓库 `tools/extract-stock-*.py` 生成 analysis 树（§4.2） |
| **rootfs 侧** | 触摸/GPU/DSP/蓝牙/WLAN/VPU 固件、传感器配置 | **V14.0.9.0** 线刷包的 `super.img`/`NON-HLOS.bin`/`BTFM.bin` | 解包后摆到固件池与 ROM 提取目录（布局见 §4.2） |

**为什么 ROM 全部用 V14**：这些是驱动运行时 `request_firmware()` 加载的
厂商二进制，与硬件版本而非 Android 版本相关——设备在装 V14，V14 的固件
就是这批硬件出厂时匹配的。管线的 ROM 内容哈希钉扎
（`build-liuqin-sensors-stack.sh` 钉 `sns_reg_config` 与配置清单；
`build-liuqin-firmware-prep.sh` 钉 VPU 哈希）默认仍是上游验证过的 OS2 值，
因为 V14 提取物的真实哈希要等你解包后才能算（不能编造）。**路径默认值已
全部改为 V14**（提交 `f092a3c`），ROM 内容钉扎改为环境变量可覆盖——你解包
后把真实哈希告诉我，我把默认钉值换掉，就不用每次 export。

## 3. 前置条件

### 3.1 宿主软件（apt 可装）

```
curl, rsync, 7z (p7zip-full), squashfs-tools, cpio,
python3 (≥3.11) + pyelftools, util-linux (flock),
gcc (原生 arm64), git, fastboot (platform-tools),
dtc / fdtoverlay (device-tree-compiler), zstd,
atool 或 lpunpack/simg2img（解 V14 super.img 用）
```

若在 x86 宿主跑，需另备 `qemu-aarch64` binfmt（P flag）与
`aarch64-linux-gnu-gcc`。

### 3.2 你必须自备的输入

| 输入 | 说明 | 从哪来 |
|---|---|---|
| Ubuntu 26.04 desktop arm64 ISO | 钉扎 `c2afd538…` / 4161089536 B | **你已下载并校验通过**；放到 `tools/local/ubuntu-desktop-26.04-arm64/ubuntu-26.04-desktop-arm64.iso` 后跑 `verify-iso` |
| V14.0.9.0.TMYCNXM 线刷包 | 全部 ROM 物料来源（boot 侧 + rootfs 侧） | 你已有；只需要其中 6 个镜像（§4.2） |
| QCA6490 原厂目录 | `amss20.bin`/`m3.bin`/`regdb.bin`/`bd_m81gf.elf`（4 个文件哈希钉死） | 从 V14 包 `super` 的 `vendor/firmware_mnt/image/qca6490/` 等位置解出 |
| 上游 `board-2.bin.zst` | 哈希 `ba583c35…` | linux-firmware 上游；`build-liuqin-wlan.py --base-board` |
| audioreach-topology 源 | 固定提交 `2af1f1ebb8d…` | `git clone linux-msm/audioreach-topology`，放 `$INT/../audioreach-topology`（或 `tools/local/audioreach-topology`） |
| 指纹构建输入 | `fingerprint-build-inputs.tar.gz` | `prepare-image-inputs.py` 自动下载并校验 |

## 4. 执行步骤（每步都有校验关卡）

> 工作目录 `$INT` = 集成仓根；所有命令在 `$INT` 下执行。
> `sudo -v` 先刷新，几处 chroot 要 root。

### 4.1 桌面根（ISO → rootfs）

```sh
# ISO 已就位后先校验指纹，再抽 casper 层、提取根
sh tools/build-liuqin-ubuntu-desktop-rootfs.sh verify-iso
sh tools/build-liuqin-ubuntu-desktop-rootfs.sh casper
sudo sh tools/build-liuqin-ubuntu-desktop-rootfs.sh extract
```

**关卡**：`verify-iso` 校验 size+sha256；`casper` 校验
`minimal.squashfs`(`82613d06…`)/`minimal.standard.squashfs`(`fce0e244…`)
哈希；`extract` 产出
`tools/local/ubuntu-desktop-26.04-arm64/rootfs` + `rootfs.manifest`
（manifest 哈希 `175ca229…`，`native-root` 会再校一次）。

### 4.2 ROM 拆包（全部用 V14.0.9.0）

从 V14 线刷包里只需要 **6 个镜像**——格式只有两类操作：拆 Android sparse
（`super.img`）与挂载文件系统镜像（FAT/ext4）。

**① boot 侧（DTBO/基 DTB）**——仓库工具直接吃 `images/` 下的原文件：

```sh
python3 tools/extract-stock-dtbo-entries.py <V14包>/images/dtbo.img \
  tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/analysis/dtbo
python3 tools/extract-stock-base-dtbs.py <V14包>/images/vendor_boot.img \
  tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/analysis/vendor_boot/dtbs
```

应产出 38 个 DTBO 条目与 11 个基 DTB。**原理**：bootloader 启动时会把它
持有的 stock DTBO overlay 应用到 boot 镜像携带的 DTB，缺 `__symbols__`
就拒绝启动；`build-bootimg.sh` 的 ABL overlay sink 需要这 38+11 个文件的
符号表。这两个分区不要动其他内容。

**② rootfs 侧（固件物料）**——从另外 3 个镜像提取，按
`tools/build-liuqin-firmware-prep.sh` 顶部注释的布局摆好：

| 提取物 | 源镜像 | 格式 | 放置位置 |
|---|---|---|---|
| 触摸 2 bin | `super` → vendor | sparse→逻辑分区 | `tools/local/firmware-liuqin/touch-nt36532/vendor/firmware/` |
| GPU 3 bin（`a730_sqe.fw`/`a730_zap.mbn`/`gmu_gen70000.bin`） | `super` → vendor | sparse→逻辑分区 | `…/gpu-adreno730/vendor/` |
| WLAN 板号 `bd_m81.elf` | `super` → vendor/firmware_mnt/image/qca6490 | sparse→逻辑分区 | `…/wlan-qca6490/vendor/firmware_mnt/image/qca6490/` |
| VPU `vpu20_4v.mbn` | `super` → vendor | sparse→逻辑分区 | `tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/extracted/super-work/vendor-extract/firmware/`（或 `VPU_BLOB` 直指） |
| 传感器配置（`config/` 56 个 + `sns_reg_config`） | `super` → vendor | sparse→逻辑分区 | `…/V14.0.9.0.TMYCNXM/extracted/super-work/vendor-extract/etc/sensors/` |
| DSP 68 个 `.mbn` | `NON-HLOS.bin` | FAT16 | `…/dsp-sm8475/vendor/qcom/sm8475/liuqin/` |
| 蓝牙整套（`hpbtfw2*.tlv`/`hpnv2*.*`） | `BTFM.bin` | FAT16 | `…/bt-qca6490/vendor/bt_firmware/image/` |
| QCA6490 原厂 4 文件（`amss20.bin`/`m3.bin`/`regdb.bin`/`bd_m81gf.elf`） | `super` → vendor/firmware_mnt/image/qca6490 | sparse→逻辑分区 | 自选位置，喂给 `build-liuqin-wlan.py --vendor` |

（`super` 是 dynamic partition：先 sparse→raw，再拆出 `vendor` 逻辑分区
才能挂载。`metadata.img`/`userdata.img`/`cust.img`/`boot.img`/
`recovery.img`/`vbmeta.img`/`persist.img` 都不需要。）

**关卡**：固件池缺项或结构性错误会在 `prepare-image-inputs.py`（§4.4）
与构建脚本里 `die`，不会上机失败。ROM/固件的**内容哈希已全部按本机
V14.0.9.0 实测值设为默认，并且只作信息打印**（自用安装不追求发布级
字节复现，按解包实际内容走即可）；仍会硬 `die` 的是结构性防错：
文件/目录存在、WLAN 板号文件的 ELF 魔数、DSP 恰好 68 个文件、
固件树恰好 197 个文件且不含 per-device 校准、我们自己补丁的 SHA、
生成的 `sns_reg_version` 一致性。

> 传感器栈在 chroot 里 `apt-get update` 拉取构建依赖（提取出的 rootfs
> 不带 apt 索引），**arm64 机器需要联网**。这一步由
> `prepare-image-inputs.py` 自动经 sudo 传 `UPDATE_APT=1`，无需手工指定。
### 4.3 杂项 fetch

```sh
sh tools/fetch-busybox-arm64.sh      # 钉扎 busybox-static 1.36.1
sh tools/fetch-aosp-mkbootimg.sh     # mkbootimg/unpack_bootimg（文件级哈希）
```

单系统不切换 Android，KernelSU 资产不需要；若以后跑全量
`build-liuqin-image.py --stage all` 的 bundle 阶段，再补
`sh tools/fetch-kernelsu-assets.sh`。

### 4.4 准备输入汇总

```sh
sudo -v
python3 tools/prepare-image-inputs.py check   # 先看哪些要重建
python3 tools/prepare-image-inputs.py run     # 传感器栈/设置程序经 sudo chroot
```

产出 `out/image-inputs.local.json`（传感器栈、GNOME 设置程序按来源指纹
缓存在 `tools/local/artifacts-cache/`，重跑可复用）。传感器栈与设置程序
在 chroot 里构建（arm64 原生宿主直接执行，无 qemu）。

### 4.5 内核产物（CI，不本地编译）

**不用重跑编译。** 内核仓的 `liuqin.yml` 与集成仓的 `build.yml` 跑的是
**同一份 action**（`.github/actions/kernel`，内核仓 CI 反过来 checkout
集成仓 main 取构建脚本），确定性参数相同 → 产物字节一致。唯一的差别是
标签：内核仓传 `revision` → `build_kind=development`；集成仓按锁构建 →
`build_kind=product-input`，两者在组装器眼里等价
（`build-liuqin-image.py` 对 development 只多查"分片哈希与锁一致"，
本仓库 10/10 分片哈希已核对一致）。

所以**直接复用内核仓 CI 已产出的 artifact**（run 41409689334 的
`liuqin-kernel-db08160915e3…`，即工作区 `ci/` 里那份）：

```
ci/liuqin-kernel-db08160915e3…/
├── kernel/          Image、dtb、.config、build-info.json、SHA256SUMS
└── kernel-modules/  modules.tar、modules.manifest、kernel.release、kernel.commit
```

使用前核对 `build-info.json.commit` 与目录名一致、`sha256sum -c` 通过。

> **modules 阶段复用**：新版 action 把预打模块集登记进
> `build-info.json` 的 `prepared_modules` 字段，`build-liuqin-image.py`
> 的 `modules` 阶段直接从 artifact 的 `kernel-modules/` 目录复用，
> **本地不需要内核构建树、不跑 Kbuild**。若 artifact 的 build-info
> 里没有 `prepared_modules`（旧 action 产物），组装器会明确报
> "lacks its prepared module set, rerun the CI action"——重跑一次
> 内核仓 CI 即可。

### 4.6 组装系统镜像

```sh
sudo python3 tools/build-liuqin-image.py \
  --inputs out/image-inputs.local.json \
  --kernel-out <ci/liuqin-kernel-db08160915e3…/kernel 目录的绝对路径> \
  --stage all
```

阶段顺序：`modules → debs → copy → install → assemble → manifest →
boot → runtime → installer → pack → bundle`。中断后用 `--stage <名>` 续跑。
产物在 `out/image/bundle/`：`boot.img`、`installer.img`、
`rootfs.tar.gz`、`bundle.json`、安装器脚本与文档。

> `--kernel-out` 指向 CI artifact 的 `kernel/` 子目录；脚本仅读取其中的
> Image/dtb/.config/build-info.json 与同级的 `kernel-modules/`，不在里面编译。
> 产物锁（`kernel/source.json`）已推进到同一 commit，commit 门已通。

**关卡**：
- `debs` 断言 gdm3/gnome-shell/gnome-initial-setup 在树里、
  gdm autologin 未残留、snap admission 未挂 basic.target；
- `assemble` 执行 BlueZ 策略改写、单元链接、`/etc/liuqin-native-root`
  marker（哈希 `4fdae4f7…`）、逐设备私有数据**必须不存在**的断言；
- `boot`/`installer` 断言 boot 镜像 ≤ 192 MiB boot 分区（`build-bootimg.sh`）。

### 4.7 本地校验（不碰设备）

```sh
python3 tools/install-liuqin.py --bundle out/image/bundle --check
```

`--check` 只做本地 bundle 校验与（加 `--layout` 时）分区计划预览，
不访问设备。**没过这关不要接平板。**

## 5. 安装（连平板）

### 5.1 设备侧准备

- Bootloader 已解锁；平板进 Fastboot；电量 ≥30%。
- 个人文件已备份到平板外；安装清空整个 userdata（单系统删分区）。

### 5.2 执行安装

```sh
sudo python3 tools/install-liuqin.py \
  --bundle out/image/bundle \
  --serial <设备序列号> \
  --backup <包外私密备份目录> \
  --erase-userdata --layout linux-only --allow-unverified
```

单系统布局不需要 `--rom-dir`。`--allow-unverified` 是因为本次 bundle
未经真机验收（首次安装本就要求有人在场；验收后用 `--device-tested`
生成 release 资产）。非交互环境显式加 `--yes`。

**安装器实际做什么**（`install-liuqin.py` + RAM installer）：
`fastboot boot installer.img` → USB 网络（`192.168.7.2`）→
备份 `boot_a`/`boot_b`/`persist` + 分区表双副本到 `--backup` →
删 userdata、建 `linux_root`(ext4, 36)+`linux_home`(37) →
主机 HTTP 下载 rootfs.tar.gz 并校验 → 解包到 `linux_root`、
从 **persist 分区**（只读挂载）抽取本机校准与地址（WLAN MAC、
蓝牙地址、cs35l41 校准、传感器 registry）→ 写 `boot_b`（零填充到整分区）、
`fastboot --set-active=b` → 重启。

不写 `persist`、不重锁 Bootloader、不碰 `super`/`metadata`/A 槽分区。

### 5.3 首启验证关卡

1. 串口/控制台：内核日志到 systemd，无 oops/panic；
2. `gdm` 起来 → GNOME 初始设置（`gnome-initial-setup` 必须跑，
   安装器断言过 autologin 不残留）；
3. 触控：`/proc/interrupts` 见 nt36523 中断、`/dev/input` 有事件节点；
4. WLAN/蓝牙：MAC 与地址来自 persist（`liuqin-wlan-mac` /
   `liuqin-bt-public-addr`），`ip link` 与 `bluetoothctl` 可用；
5. 音频：`cs35l41` 带本机校准（`/usr/lib/firmware/cirrus/`）；
6. `/home` 是 `LABEL=LIUQIN_HOME` 的独立挂载（`install-root.sh` 写的 fstab）。

## 6. 回退与恢复

| 情形 | 处置 |
|---|---|
| installer.img 起不来 | `fastboot boot` 失败本身不写任何分区；检查 USB 网络与 `--serial` |
| 分区表写错 | 安装器内置「写后重读逐项比对」；必要时 `--restore-partition-table <备份目录>` |
| Ubuntu 起不来 | 备份在 `--backup`：先 `--restore-partition-table` 恢复出厂分区表，再用 V14 线刷包 `flash_all` 回 Android |
| 想完全回出厂 | V14 线刷包 `flash_all`（设备在装的就是 V14），并从备份还原分区表 |

## 7. 已知缺口（技术债，不在本手册解决）

| 编号 | 缺口 | 影响 | 去除条件 |
|---|---|---|---|
| S2-1 | 固件池/ROM 解包无自动化工具，全手工摆目录 | 首装准备时间长、易错 | 哈希断言兜底；后续可加 `tools/fetch-rom-inputs.sh` |
| S2-3 | 单系统布局未真机验证（与 dual 共用布局引擎） | 分区/挂载风险 | 本次首装即验证 |
| S2-4 | ISO 点版本重钉扎需手工 | 26.04.1 等需重钉 | `tools/repin-ubuntu-release.sh` 已提供 |
| S2-5 | ROM 内容钉扎默认仍是 OS2 值，V14 提取物的真实哈希待填 | 首跑需 env 覆盖或按报错换值 | 你提供 V14 哈希后，我替换默认钉值 |

## 8. 复盘检查表（首启成功后回填）

- [ ] 内核：`uname -r` == bundle `kernel_release`
- [ ] 显示：GNOME 桌面点亮，120 Hz mode 可选
- [ ] 触控/WLAN/BT/音频：§5.3 四项
- [ ] 持久化：重启后用户数据保留（`linux_home` 独立挂载）
- [ ] 回归：`--restore-partition-table` 后 V14 `flash_all` 可回 Android
