# Stage 2：持久化单系统 Ubuntu（arm64 宿主执行手册）

本手册把已点亮的 v7.3 内核与 Ubuntu 26.04 LTS 桌面系统持久安装到
Xiaomi Pad 6 Pro（liuqin），使平板成为一台单系统 ARM PC：
**不含 Android，不做双系统**，整片 userdata 尾部空间交给 Ubuntu。

[English](STAGE2-PERSISTENT.md) ｜ [构建总览](BUILD.zh-CN.md) ｜ [安装步骤](INSTALL-TESTING.zh-CN.md)

---

## 0. 本文 Zum 的定位

- **谁来执行**：你在另一台连接平板实机的 **arm64 原生** Linux 机器上执行全部步骤。
  本手册不替你做任何下载、解包或刷写；所有命令都需要你确认后亲自运行。
- **为什么是 arm64 原生机**：管线的 chroot 阶段（debs 安装、传感器栈、
  GNOME 设置程序）在 arm64 宿主上是**原生执行**，不需要 qemu/binfmt；
  本项目从 2026-10-30 起 CI runner 也统一为 `ubuntu-24.04-arm` 原生编译。
  若你在 x86 宿主执行，需自行补 `qemu-aarch64` binfmt 与交叉工具链。
- **单系统边界**：`--layout linux-only`。安装器只动 B 槽与尾部分区，
  不需要 ROM 目录、不恢复 Android 固件分区、不写 `super`/`metadata`。
  见 §6 与 [安装指南](FLASHING.zh-CN.md)。
- **不做的事**：本文不组 RAM 桌面镜像（那是另一条 `LIUQIN_STORAGE_MODE=readonly`
  路线），不做 Kubuntu/KDE 适配（Kubuntu 无 arm64 desktop ISO），
  不碰内核显示栈（v7.3 已点亮，见 `docs/kernel-version-upgrade.md` §13）。

## 1. 现状与前置事实（先读）

| 项 | 值 | 证据 |
|---|---|---|
| 点亮内核 | `liuqin-7.3` @ `db08160915e3`（`7.3.0-gdb08160915e3`） | `docs/kernel-version-upgrade.md` §13；CI run 41409689334 |
| 基础系统 | Ubuntu Desktop 26.04 LTS arm64（`ubuntu-26.04-desktop-arm64.iso`） | `tools/build-liuqin-ubuntu-desktop-rootfs.sh` 钉扎 |
| 产物锁 | `kernel/source.json` 仍钉 `a322d592`（7.0 时代）—— **§4-1 必须推进到 7.3** | TD4，`docs/migration-7.0.md` 技术债表 |
| 单系统布局 | 删 userdata，尾部建 `linux_root`(36)+`linux_home`(37)，boot 镜像写 `boot_b`，`--set-active b` | `tools/lib/liuqin_layout.py:340-360`；`install-liuqin.py:36` |
| 设备门槛 | 出厂分区表、4096 逻辑扇区、userdata 为最后一个分区、Bootloader 解锁、电量 ≥30% | `FLASHING.zh-CN.md`；`liuqin_layout.py:274` |

**关键约束（不可绕过）**：

1. `build-liuqin-image.py` 硬性校验 kernel 产物 `build-info.json.commit` 与
   `kernel/source.json` 钉值一致。7.3 点亮产物自报 `commit=db08160915e3`，
   锁还钉 `a322d592` ⇒ **不推进锁，镜像组不起来**。
2. 持久 boot 镜像只认**本机构建**的内核树（`native-boot.sh` 要
   `$KERNEL_OUT/scripts/dtc/dtc` 与 `include/config/kernel.release`）。
   CI artifact 缺这两样 ⇒ 必须在 arm64 宿主**本地构建一次内核**。
   这是管线设计（`image.yml` 在 CI 里也先跑 `build-liuqin-kernel.py`
   再组装），不是本手册的额外要求。
3. ROM 输入钉的是 **OS2.0.6.0.VMYCNXM** 线刷包。手头的 V14.0.9.0 包
   **哈希不匹配**（`dtbo` 44 vs 38 条目、`entry.15` 字节不同），
   固件池与 ABL overlay 输入必须来自 OS2.0.6.0。

## 2. 前置条件

### 2.1 宿主软件（apt 可装）

```
curl, rsync, 7z (p7zip-full), squashfs-tools, cpio,
python3 (≥3.11) + pyelftools, util-linux (flock),
gcc (原生 arm64 即可), git, fastboot (platform-tools),
dtc / fdtoverlay (device-tree-compiler),
zstd, debootstrap 不需要
```

`build-liuqin-native-root.sh` 与 `build-liuqin-debs.sh` 已按 arm64
原生宿主放宽（`uname -m` = aarch64 时跳过 binfmt 检查、编译器回退
`gcc`）。若在 x86 宿主跑，需另备 `qemu-aarch64` binfmt（P flag）与
`aarch64-linux-gnu-gcc`。

### 2.2 宿主磁盘

内核构建树 + 两份桌面树（extract + copy）+ rootfs 归档：
**不少于 60 GB** 可用空间。`out/` 与 `tools/local/` 都在仓内但被
gitignore，别提交。

### 2.3你必须自备的输入

| 输入 | 说明 | 从哪来 |
|---|---|---|
| Ubuntu 26.04 desktop arm64 ISO | 钉扎 `c2afd538…` / 4161089536 B | `tools/build-liuqin-ubuntu-desktop-rootfs.sh download`（脚本下载）或自行下载后 `verify-iso` |
| OS2.0.6.0.VMYCNXM 线刷包 | 7.7 GB `super.img` 等，哈希见 `tools/lib/liuqin-rom-images.json` | 小米官方线刷包；**不可**用 V14.0.9.0 替代 |
| QCA6490 原厂目录 | `amss20.bin`/`m3.bin`/`regdb.bin`/`bd_m81gf.elf` | 从 OS2 包 modem/vendor 分区解出 |
| audioreach-topology 源 | 固定提交 `2af1f1ebb8d…` | `git clone linux-msm/audioreach-topology`，放项目旁 |
| 指纹构建输入 | `fingerprint-build-inputs.tar.gz` | `prepare-image-inputs.py` 自动下载并校验 |

固件池（`tools/local/firmware-liuqin`）由 OS2 的
`vendor_a`(触摸/GPU/VPU)、`NON-HLOS.bin`(DSP)、`BTFM.bin`(蓝牙)、
上游 `WCN6855`(WLAN)、上游 `regulatory.db` 组成；脚本里有逐项哈希
断言，凑不齐会在构建期失败而不是上机失败。

## 3. 输入准备（每步都有校验关卡）

> 工作目录约定：`$INT` = 集成仓根目录；所有命令在 `$INT` 下执行。
> `sudo -v` 先刷新，几处 chroot 要 root。

### 3.1 桌面根（ISO → rootfs）

```sh
sh tools/build-liuqin-ubuntu-desktop-rootfs.sh download   # 或自行下载后 verify-iso
sh tools/build-liuqin-ubuntu-desktop-rootfs.sh casper     # 7z 抽两层 squashfs
sudo sh tools/build-liuqin-ubuntu-desktop-rootfs.sh extract
```

**关卡**：`download` 校验 ISO size+sha256；`casper` 校验
`minimal.squashfs`(`82613d06…`)/`minimal.standard.squashfs`(`fce0e244…`)
哈希并拒绝 English-pruning 层；`extract` 产出
`tools/local/ubuntu-desktop-26.04-arm64/rootfs` + `rootfs.manifest`
（manifest 哈希 = `175ca229…`，§5 的 `native-root` 会再校一次）。

### 3.2 ROM 拆包

```sh
# dtbo → 44 个 entry；vendor_boot → 14 个基 DTB
python3 tools/extract-stock-dtbo-entries.py <OS2包>/dtbo.img \
  tools/local/roms/liuqin/OS2.0.6.0.VMYCNXM/analysis/dtbo
python3 tools/extract-stock-base-dtbs.py <OS2包>/vendor_boot.img \
  tools/local/roms/liuqin/OS2.0.6.0.VMYCNXM/analysis/vendor_boot/dtbs
```

**关卡**：`build-bootimg.sh` 在装配时用「44 条目 / 14 基 DTB / 1781 符号」
三重计数断言 + `abl-symbols.py` 符号表比对；拆错了这里失败，不会到上机。

固件池与 `super` 解包按 `tools/build-liuqin-firmware-prep.sh` 顶部注释
的目录布局摆好（`FIRMWARE_POOL` 环境变量可指到别处）。传感器栈需要
`extracted/super-work/vendor-extract/etc/sensors`（含 `config/` 与
`sns_reg_config`），VPU 需要 `firmware/vpu20_4v.mbn`。

### 3.3 杂项 fetch

```sh
sh tools/fetch-busybox-arm64.sh      # 钉扎 busybox-static 1.36.1
sh tools/fetch-aosp-mkbootimg.sh     # mkbootimg/unpack_bootimg（文件级哈希）
sh tools/fetch-kernelsu-assets.sh    # 单系统不切换，但 bundle 仍打包
```

### 3.4 音频拓扑

```sh
AUDIOREACH_TOPOLOGY_DIR="$PWD/../audioreach-topology" \
  OUTPUT="$PWD/out/audio-topology/Xiaomi-Pad-6-Pro-tplg.bin" \
  sh tools/build-liuqin-audio-topology.sh
```

### 3.5 WLAN 组合（需原厂 QCA6490 目录）

```sh
python3 tools/build-liuqin-wlan.py \
  --vendor <原厂QCA6490目录> \
  --base-board <bd_m81gf.elf> \
  --bdencoder tools/scripts/ath11k/ath11k-bdencoder \
  --out out/wlan-source-check
```

### 3.6 准备输入汇总

```sh
sudo -v
python3 tools/prepare-image-inputs.py check   # 先看哪些要重建
python3 tools/prepare-image-inputs.py run     # 传感器栈/设置程序经 sudo chroot
```

产出 `out/image-inputs.local.json`（传感器栈、设置程序按来源指纹缓存在
`tools/local/artifacts-cache/`，重跑可复用）。`--prepare-only` 只解包
GNOME 设置源；正式构建需 sudo（在隔离挂载命名空间里跑，不改输入树）。

## 4. 内核与组装

### 4.1 推进产物锁到 7.3（必须先做）

编辑 `kernel/source.json`：

```json
{
  "branch": "liuqin-7.3",
  "commit": "db08160915e3138748a45f9a3fa868ccfb536e8b",
  "config_sha256": "<用 §4-2 build-info.json 里的实际值>",
  ... config_fragments / dtb 保持不变 ...
}
```

`config_sha256` 必须取**本机构建产物**自报的值（CI 产物是
`d81ff750…`；本机若分片合并结果不同，以本机为准——构建器只警告不拒绝，
镜像组装器则强校验）。`upstream_base` 字段不受校验，可留 7.0 值。

> 风险提示：这一步把「产品内核」从 7.0 推进到 7.3。7.3 点亮依赖两项
> 修复（ubwc `qcom,cape` 别名 `489807127e50`、bonded-DSI PLL
> `db08160915e3`），都在 `db08160915e3` 提交里；锁推进后这两项自然带上。

### 4.2 本地构建内核（原生 arm64）

```sh
# 内核仓在 $INT/../linux-sm8450-liuqin，checkout liuqin-7.3 @ db08160915e3 且工作树干净
python3 tools/build-liuqin-kernel.py --jobs <核数>
```

**关卡**：构建器断言源树 HEAD == 锁值且工作树干净、交叉链按宿主自动
（arm64 原生 → 无前缀）；产物 `out/kernel/` 含 `Image`、
`arch/arm64/boot/dts/qcom/sm8475-xiaomi-liuqin.dtb`、`include/config/kernel.release`、
`scripts/dtc/dtc`、`build-info.json`。把 `build-info.json` 的
`config_sha256` 回填进 `kernel/source.json`（若与 CI 值不同）。

### 4.3 组装系统镜像

```sh
sudo python3 tools/build-liuqin-image.py \
  --inputs out/image-inputs.local.json \
  --kernel-out "$PWD/out/kernel" \
  --stage all
```

阶段顺序：`modules → debs → copy → install → assemble → manifest →
boot → runtime → installer → pack → bundle`。中断后用 `--stage <名>` 续跑。
产物在 `out/image/bundle/`：`boot.img`、`installer.img`、
`rootfs.tar.gz`、`bundle.json`、安装器脚本与文档、KernelSU 返回模块
（单系统不用它，但 bundle 仍打包）。

**关卡**：
- `debs` 阶段断言 gdm3/gnome-shell/gnome-initial-setup 在树里、
  gdm autologin 未残留、snap admission 未挂 basic.target；
- `assemble` 执行 BlueZ 策略改写、单元链接、`/etc/liuqin-native-root`
  marker（哈希 `4fdae4f7…`）、逐设备私有数据**必须不存在**的断言；
- `boot`/`installer` 阶段跑 `build-liuqin-native-boot.sh`：内核源树
  HEAD/配置/`kernel.release` 与根内 `/usr/share/liuqin/kernel.release`
  三方一致；boot 镜像断言 ≤ 192 MiB boot 分区（`build-bootimg.sh`）。

### 4.4 本地校验

```sh
python3 tools/install-liuqin.py --bundle out/image/bundle --check
python3 tools/install-liuqin.py --bundle out/image/bundle --layout linux-only \
  --serial <序列号>  # 加 --layout 可预览分区计划，仍不访问设备
```

bundle 自校验（`bundle.json` 逐文件 sha256）、设备身份门槛、布局计划
全在这里。**没过这关不要接平板。**

## 5. 安装（连平板）

### 5.1 设备侧准备

- Bootloader 已解锁；平板进 Fastboot；电量 ≥30%。
- `fastboot -s <序列号> getvar partition-size:boot_b` 等核对用安装器自检。
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
生成 release 资产）。若脚本无交互环境，显式加 `--yes`。

**安装器实际做什么**（`install-liuqin.py` + RAM installer）：
`fastboot boot installer.img` → USB 网络（`192.168.7.2`）→
备份 `boot_a`/`boot_b`/`persist` + 分区表双副本到 `--backup`（可 `--check`
校验）→ 删 userdata、建 `linux_root`(ext4, 36)+`linux_home`(37) →
主机 HTTP 下载 rootfs.tar.gz 并校验 → 解包到 `linux_root`、
从 **persist 分区**（只读挂载）抽取本机校准与地址（WLAN MAC、
蓝牙地址、cs35l41 校准、传感器 registry）→ 写 `boot_b`（零填充到整分区）、
`fastboot --set-active=b` → 重启。

不写 `persist`、不重锁 Bootloader、不碰 `super`/`metadata`/A 槽分区。

### 5.3 首启验证关卡

1. 串口/控制台：内核日志到 systemd，无 oops/panic；
2. `gdm` 起来 → GNOME 初始设置（`gnome-initial-setup` 必须跑，安装器
   断言过 autologin 不残留）；
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
| Ubuntu 起不来 | 备份在 `--backup`：`fastboot -s <序列号> flash boot_b <备份>/boot_b.img`，再 `fastboot --set-active=a` 回原厂 Android（A 槽与 super 未动，Android 数据分区虽被删除，可由 OS2 线刷包重刷 userdata 恢复） |
| 想完全回出厂 | 用 OS2.0.6.0 线刷包 `flash_all`，并从备份还原分区表 |

## 7. 已知缺口（登记为技术债，不在本手册解决）

| 编号 | 缺口 | 影响 | 去除条件 |
|---|---|---|---|
| S2-1 | 固件池/ROM 解包无自动化工具，全手工摆目录 | 首装准备时间长、易错 | 哈希断言兜底；后续可加 `tools/fetch-rom-inputs.sh` |
| S2-2 | `kernel/source.json` 由 7.0 推进到 7.3 属产品决策 | 锁推进即生效 | v7.3 持久首启验证通过后视为完成（TD4 收口） |
| S2-3 | 单系统布局未真机验证（与 dual 共用布局引擎） | 分区/挂载风险 | 本次首装即验证 |
| S2-4 | English-pruning 层、ISO 点版本重钉扎需手工 | 26.04.1 等需重钉 | `tools/repin-ubuntu-release.sh` 已提供 |

## 8. 复盘检查表（首启成功后回填）

- [ ] 内核：`uname -r` == bundle `kernel_release`
- [ ] 显示：GNOME 桌面点亮，120 Hz mode 可选
- [ ] 触控/WLAN/BT/音频：§5.3 四项
- [ ] 持久化：重启后用户数据保留（`linux_home` 独立挂载）
- [ ] 回归：`fastboot --set-active=a` 可回 Android（验证 A 槽未被动过）
