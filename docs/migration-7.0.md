# liuqin 内核迁移到 Ubuntu 7.0：状态记录与真机首测手册

liuqin（Xiaomi Pad 6 Pro）从 `liuqin-6.17`（真机验证过的基线）迁移到
`liuqin-7.0`（Ubuntu 7.0，`Ubuntu-7.0.0-42.42` 基线）。本文分两部分：前半是
移植内容与离线证据，后半是真机首测的执行手册与测试镜像的可复现装配。

文档惯例：状态词与技术债格式遵循 `android-mainline-port` skill 的
`references/verification.md` 与 `references/discipline.md`。

## 关键事实

| 项 | 值 |
|---|---|
| 内核分支 | `linux-sm8450-liuqin` `liuqin-7.0`，tip `2c2092606bed`（10 个移植提交） |
| 内核 CI | Run #9（head `2c2092606bed`，success，约 11 分钟）；Run #8 覆盖到 `e6c2f01cd036` |
| Run #9 artifact | id 12347240243，102.6 MB；`SHA256SUMS` 六项校验通过 |
| kernel.release | `7.0.14-g2c2092606bed` |
| 安装器 | `xiaomipad-6pro-mainline` main（推送由用户执行，以 `git log @{u}..HEAD` 为准） |
| 产品锁 | `kernel/source.json` 仍钉 `a322d592cb92`（迁移前 tip）——TD4，首测后推进 |
| 测试镜像 | 开发机本地 `repack/final-boot/boot-liuqin-firstboot.img`，58,564,608 字节 |
| 线刷包 | `OS2.0.6.0.VMYCNXM`；`vendor_boot`/`dtbo`/`boot`/`super` 哈希命中 `tools/lib/liuqin-rom-images.json` 钉值 |

**一句话**：10 个移植提交离线全绿、CI 全绿，测试镜像已装配并逐项对齐
v0.6.0 已验证启动，等真机首测（手册见后半）。

## 移植内容

13 个提交 = 3 个既有分支基建（board DTS、CI 工作流、checkout 锁，未改动）
+ 10 个移植提交：

| 组件 | 提交 | 状态 |
|---|---|---|
| qcom-pon 暖复位 PS_HOLD | `b70b53febdbb` | 离线通过（`POWER_RESET_QCOM_PON=y`） |
| `/reserved-memory` 割区探测限制 | `85feb95e7cc2` | 离线通过 |
| simple-framebuffer earlycon | `b034fb07e84f` | 离线通过（DTB 六属性断言） |
| SM8475 TLMM pinctrl | `55e410f4f603` | 离线通过（`PINCTRL_SM8475=y`） |
| I2C eUSB2 中继器 | `91552d3b4a72` | 离线通过（dtb 引用链闭合） |
| NT36532 面板驱动 | `9719bc3c5f38` | 离线通过（6.17 tip 逐字移植） |
| DSI 双 slice/包 | `993054693403` | 离线通过（与 6.17 行为核对） |
| NT36523 触控驱动 | `e6c2f01cd036` | 离线通过（`TOUCHSCREEN_NT36523_SPI=y`） |
| SLPI 启动所有权（驱动） | `253032ac87c8` | 离线通过 |
| SLPI 启动所有权（启动参数） | `2c2092606bed` | 离线通过 |

**SLPI 专项**：6.17 用补丁对（`569f79be4a7d` + `a54c2b5501a7`）把 SLPI
启动交给用户态；7.0 的 PAS 驱动 `auto_boot` 只来自平台描述符，无模块参数
可覆盖，SLPI 会在内核启动阶段自动拉起——把 6.17 收敛到用户态服务里的
SLPI 复位窗口推回内核引导期（无 USB、只能按键恢复）。补移植恢复
验证过的行为：SLPI 在 `/sys/class/remoteproc/` 注册但 `auto_boot=0`。
安装器侧 `a1d4efa` 把 `qcom_q6v5_pas.slpi_auto_boot=0` 加回
`device/native-bootargs.txt`，与内核 DTS 的 `/chosen/bootargs` 保持全等。

## 离线证据

以下记录于 2026-10-21/22，用 CI 产物 `.config` 与 DTB 逐项对照经验库。

1. **`.config` 受害者符号**（`=m` 但 RAM 镜像无模块目录会静默缺失）：
   `QCOM_GPI_DMA`、`SPI_QCOM_GENI`、`RTC_DRV_PM8XXX`、`OVERLAY_FS`、
   `UHID`、`FW_LOADER_COMPRESS_ZSTD`、`PSI`、`QRTR`、`QCOM_PD_MAPPER`、
   `BATTERY_QCOM_BATTMGR` 全部 `=y`。`MODVERSIONS` 未开——模块 ABI 检测
   依赖打包脚本的 vermagic 校验，跨版本不兼容由 `uname -r` 强校验兜底。
2. **SPI 三层**（父包装器/GPI DMA/驱动内建）：`geniqup@8c0000` 存在，触控
   所在 SPI 的 DMA（phandle `0x72`）`status = "okay"`，`QCOM_GPI_DMA=y`。
3. **触控 TDDI 生命周期**：驱动是完整的 panel follower——`drm_is_panel_follower()`
   检测、probe 在 follower 模式不发工程复位、`IRQF_NO_AUTO_EN`、
   `panel_prepared`/`panel_unpreparing` 回调重新下载固件；DTB 触控节点带
   `panel = <&panel>`。经验库的"TDDI 熄屏后触控失效"、"面板上电前 probe"
   两个坑在驱动层面已规避。
4. **DSC RC 参数**：`dsi_populate_dsc_params()`（`dsi_host.c:1858`）调用
   `drm_dsc_setup_rc_params(dsc, DRM_DSC_1_1_PRE_SCR)` 覆盖 RC 表——核对
   6.17（`2cd5a6f8ef67`）同一函数同一行为，且面板驱动不自设 RC 值。该面板
   本就是 pre-SCR 类，标准表即真机验证过的组合。面板侧仅
   `slice_width=450 / slice_count=2 / bpp=8<<4`。
5. **USB 角色切换 `-ENOENT`**（经验库记为 7.x 上游问题）：本板
   `dr_mode=peripheral`，dwc3 不注册角色切换；initramfs 的 `usb_role` 强制
   仅作无 UDC 时的兜底。
6. **DTB 引用链**：面板/背光/触控/hyphy/repeater phandle 闭合；
   `build-bootimg.sh` 的全套断言（bootargs 全等、simple-framebuffer 六
   属性、`/chosen` cells 与 ranges）10/10 通过；再忠实复刻 `dtc -@` +
   `fdtoverlay` 合并 `liuqin-abl-boot-overlay`，三个 ABL 身份属性注入成功，
   合并后断言仍全通过。
7. **6.17 提交全集审计**：逐个过了 `a19585977c11..liuqin-6.17` 的全部
   提交，按首启相关性分类——
   - 触控固件按面板模块选择（`4dcb6801404b`）、触控笔坐标缩放
     （`fba87d1d7c6f`/`a40b967b3d03`）随触控目录逐字移植到位；
   - **SLPI 补丁对漏移植**（见上文 SLPI 专项，已补）；
   - `e6604d01be72`（rtnetlink 不解引用无名父设备）未移植，7.0 代码结构
     已变，对 NCM-only 的 RAM 首启路径无交集——留作真机上若出现
     rtnetlink dump NULL deref 时的第一怀疑项；
   - 其余未移植项（DP/指纹/相机/音频/充电/GPU/USB3/ucsi/qmp-combo/
     ASoC TDM）全部是计划内延后的 P1/P2，首启不需要。
8. **ROM 身份**：本机线刷包 `liuqin_images_OS2.0.6.0.VMYCNXM_15.0` 的
   `vendor_boot.img`、`dtbo.img`、`boot.img`、`super.img` 哈希全部命中
   `tools/lib/liuqin-rom-images.json` 钉值——ABL 叠加层输入与项目验证
   过的 ROM 同源。

## 安装器侧改动

| 提交 | 内容 |
|---|---|
| `6b9b688` | `device/native-bootargs.txt` 与 7.0 板级 DTS 同步（`panic=0`→`panic=15` 等） |
| `a1d4efa` | SLPI 启动参数令牌恢复（内核补丁落地后） |
| `025e562` | 6 处文档的 `liuqin-6.17` 引用更新 |
| `f983dc8` | 本文档初版（状态与技术债记录） |
| `541b866` | 6.17 提交全集审计记录 |
| `42a5af0` `8823e5f` | 真机首测执行手册（本文件后半的雏形） |
| `74134c7` | 记录 `build-liuqin-native-boot.sh` 为何不能跑 |
| `be95ebc` | runbook 重构（ramdisk 复用）+ `tools/extract-stock-dtbo-entries.py`、`tools/extract-stock-base-dtbs.py` 两个 ROM 拆包工具 |
| `d25e010` `19d3953` | Run #9 artifact 布局记录、镜像装配记录、决策树拆分 |
| `e9be352` | 文档结构重写（本文） |
| `8084e9e` | `fetch-aosp-mkbootimg.sh` 去掉无法锚定的 tar 包级校验（googlesource +archive tarball 两次下载字节不同；文件级哈希稳定，校验留在文件级） |

`6b9b688` 当时删掉 SLPI 令牌是对的（当时的树确实无此参数），漏的是驱动
补丁本身；`a1d4efa` 恢复令牌后三者合起来还原 6.17 验证过的完整行为。

## 技术债

| 编号 | 债务 | 为什么需要 | 影响 | 去除条件 |
|---|---|---|---|---|
| TD1 | `clk_ignore_unused pd_ignore_unused` 仍在 native 启动参数 | 首测期排除"资源回收"类失败 | 无法省电/休眠，可能影响面板点亮时序 | 首测确认显示链稳定后撤除，撤除前后按经验库做 `clk_summary`/`pm_genpd_summary` 差集 |
| TD2 | 面板/触控/pinctrl 等一次性全部内建 | RAM 阶段无模块目录；6.17 产品即此配置 | 与"新驱动先做模块"的经验相悖 | 驱动逐字来自 6.17 真机验证版本；首测有早期挂死再改模块化重测 |
| TD4 | `config_sha256` 未在标准镜像主机定版 | `build-liuqin-image.py` 硬失败；本地生成会因编译器版本漂移 | 完整安装包装配被阻塞（RAM 首测不受影响） | 首测通过后把锁推进到 `2c2092606bed` 并钉 `d81ff750ac6ec47a299d78cab9582fedb4b270747040bfd796ff2e71814ebecc`（Run #9 `build-info.json`） |
| TD5 | P1/P2 外设全部延后 | 首版优先启动与交互 | WiFi/BT/电池/GPU/音频/传感器/DP/相机/指纹/键盘均不可用 | 按用户优先级逐个移植，每次一个候选；BT 详见 `docs/triage-2026-10.md`（7.0 树已有 BT 节点，bring-up 时注意 btqca 的 `wcn*` 主名回退语义） |
| TD6 | 文档仓库地址未统一（`README.md` 指上游，`source.json` 指 fork） | fork 迁移进行中 | 工作流 owner 推导可能 checkout 错仓库 | 用户定项目归属后统一 |

TD3（SLPI 无内核级关闭手段）已由 SLPI 补丁对解决，不再追踪；用户态
`/etc/liuqin-slpi-disabled` 标记仍是复位问题的退出手段。

## 真机首测手册（只测内核，RAM 启动）

### 红线：本流程只读不写

- **只用 `fastboot boot`**（RAM 启动）。不 `flash`、不 `erase`、不
  `--set-active`、不跑 `install.py` 及任何安装流程。
- 槽 A 保持原厂且仍标记成功：任何重启（含 panic 自动重启、长按电源强制
  重启）都自动回原厂。9008 只能由 XBL 级灾难产生，本流程不写 XBL，无从
  触发。
- persist 分区：本流程不写 UFS——存储接受失败即回落诊断 shell，而该
  shell 只在"所有 UFS 块设备已证只读"（`ufs_safe`）后才开 telnet（BLKROSET
  只设块层只读标志，非媒体写入）。persist 唯一的威胁是万一需要 9008 全刷：
  刷前核对线刷脚本是否含 persist 分区，含则跳过（persist 内是本机唯一的
  校准/MAC 数据，不可从其他机器复制）。

### 测前前提

- **电量 ≥50%**，用原厂充电器充：普通 SDP 口（含 Pi 的口）有
  boot/drain/reboot 循环风险。
- `fastboot getvar all` 存档（解锁状态、`current-slot`、
  `max-download-size` 应 ≥ 镜像尺寸 58.5 MB——与已验证可 RAM 启动的
  v0.6.0 installer 同级、`product=liuqin`、电量）。
- **pstore**：首测实测 pstore 可用（`/sys/fs/pstore`），panic 重启后内核
  日志可从 pstore 取回。相机/手机待命；telnet 通之前面板仍是唯一早期
  证据渠道，telnet 通后以 dmesg 为准。
- 主机备好 telnet 录制手段（`script` 或终端日志），全程留存。
- 用户在场（人眼确认画面与触控）。

### 执行序列

1. 进 fastboot（音量下+电源），
   `fastboot getvar all 2>&1 | tee getvar-before.txt`。
2. 从开发机取测试镜像 `repack/final-boot/boot-liuqin-firstboot.img`
   （58.5 MB）传到 Pi。Pi 侧无构建。
3. `fastboot boot boot-liuqin-firstboot.img`：期望 `OKAY`，随后面板出现
   earlycon 文本（移植的 `earlycon=simplefb`），主机出现 usb0（NCM）。
4. 主机取地址：`sudo dhclient usb0`（或 nmcli/dhcpcd），应得
   192.168.7.10-19。
5. `telnet 192.168.7.2 2323` → busybox 诊断 shell。开场命令：
   ```
   mount -t debugfs none /sys/kernel/debug
   cat /proc/cmdline; cat /proc/device-tree/compatible; cat /proc/device-tree/model
   uname -r
   cat /sys/kernel/debug/devices_deferred
   cat /sys/kernel/debug/pm_genpd_summary
   blockdev --getsize64 /dev/sde   # 见下注
   dmesg
   ```
   `/proc/cmdline` 里 ABL 会追加约 800 字符 `androidboot.*`——这不是漂移；
   但结尾应能看到本板的 `qcom_q6v5_pas.slpi_auto_boot=0`。
   `uname -r` 应为 `7.0.14-g2c2092606bed`。
6. 移植验收：
   - **SLPI**：`ls /sys/class/remoteproc/` 有 slpi 节点且 dmesg 无
     "Booting processor"——参数生效、未在内核期自动启动。
   - **显示/触控**：`dmesg | grep -iE "panel|dsi|dsc|nt36|ktz|backlight"`，
     人眼确认画面与背光；触控看 `probe complete: follower=` 行与
     `dmesg | grep -i nvt`。触控固件按 panel 模块选择：ABL 在 cmdline 里
     带 `msm_drm.dsi_display0=qcom,mdss_dsi_m81_42_02_0b…`（或
     `m81_36_02_0a`），驱动据此加载 CSOT/TM 固件，DT 的 firmware-name
     （csot）只是兜底——回报时对 cmdline 模块串与实际加载的固件名做一次
     交叉确认。
   - `dmesg | grep -iE "gpi-dma|eusb2|i2c@|spi@"` 确认三条数据通路。
   - `cat /sys/kernel/debug/clk/clk_summary` 只读一次（供 TD1 撤除前后差集）。
   - `devices_deferred` 为空或每项可解释；`pm_genpd_summary` 无长期挂起
     的提供者。
7. 结束：shell 内 `reboot -f`（或长按电源），验证设备回到原厂 Android
   （这是本流程可随时挽回的证明）。

**`/dev/sde` 尺寸注记**：`liuqin-mark-slot-successful.c` 把持有 GPT 的
`/dev/sde` 钉死 2923429888 B（只有 256 GB 布局验证过）。本机是 128 GB：
读到的值等于钉值 ⇒ 跨 SKU 一致，首装的槽标记无虞；不等 ⇒ 首装前必须先
处理容量变体（见 `docs/triage-2026-10.md` 第一节）。

**顺延到首装的检查**：诊断 shell 无 systemd，`systemd-detect-virt`、
`hostnamectl` chassis（Gunyah 遮蔽）等 stage-2 检查在全镜像首装后做。

### 失败决策树（不要盲迭代）

- `fastboot boot` OK 但无面板无 USB：长按电源回原厂，先验证硬件无恙再报回；
  高度怀疑 ABL 叠加层未按预期落到 7.0 树上（离线已证符号表与 v0.6.0 release
  等同）。
- 面板有 earlycon、telnet 不通：两种可分辨的成因，都靠面板拍照读日志——
  - 日志含 `remote shell will remain disabled because UFS is not
    fail-closed`：`ufs_safe` 未过，dmesg 的 UFS 行是关键。此时诊断 shell
    仍只读，无 persist 风险。
  - 日志含 `charger boot lacks its exact low-power state machine; refusing
    normal boot`：ABL 在 cmdline 追加了 `androidboot.mode=charger`（深度
    放电唤醒情景），而复用的 v0.6.0 ramdisk 不带 charger-mode 文件——init
    拒绝继续、无 gadget 无 telnet。回原厂充够电再用组合键启动重试，绝不
    是镜像问题。
  记录设备实际 `androidboot.mode`，两者都不构成返工理由。
- telnet 通、无画面：从 dmesg 的 panel/DSI 累积错误定位，勿调参。
- 设备自行重启（panic=15 自动重启）：日志已丢，只能靠重启前面板照片；
  重试时相机连续拍摄。
- 反复起不来：停止，回原厂——以上就是全部挽回手段（外加已备并哈希验证
  的线刷包）。

### 回报格式

操作时间线 + getvar 存档 + telnet 全程录制 + 上述命令输出（cmdline/
compatible/uname/devices_deferred/pm_genpd_summary/clk_summary/dmesg 全文）
+ 面板照片（尤其 earlycon 首帧与黑屏状态）。

## 测试镜像的可复现装配

### 形态选择：复用 v0.6.0 installer.img 的 ramdisk

镜像 = 内核 + ramdisk + DTB。不从零打 initramfs——那需要
`tools/local/firmware-liuqin/` 固件池（本地从未存在，见"为什么不用
build-liuqin-native-boot.sh"），而是**复用 release v0.6.0
`installer.img` 的 ramdisk**：它已是 `readonly + native` 形态（boot 后
不探任何存储，直接救援 shell + telnet 2323），内置全套哈希钉死的固件。
与设备已验证的 v0.6.0 启动相比，测试只换 `Image` 与 DTB——ramdisk 逐字节
不变，隔离出唯一变量。

其 v0.6.0 时代 init 的 readonly 路径已逐行复核：不探根（persistent 探测
分支不进入）、BLKROSET 只设块层只读标志、telnet 仅在 UFS 证闭后开。

### 为什么不用 build-liuqin-native-boot.sh

不是偏好问题，是三条硬前提当前全缺：脚本读 `$kernel_out/scripts/dtc/{dtc,
fdtoverlay}` 与 `include/config/kernel.release`（本地不编译内核就没有这棵
构建树）；断言源码 HEAD 与 `kernel/source.json` 锁一致且 `.config` 哈希吻合
（锁仍钉 `a322d592cb92`，tip 是 `2c2092606bed`，直接硬失败）；还要
`NATIVE_ROOT_HASHES`/`AUDIO_TOPOLOGY`/`WLAN_HSP2_TUPLE` 一整套产品链输入。
诊断形态与它共用 `build-bootimg.sh`，只是换 env，不碰锁、不拖产品流水线。
该脚本留给首测通过后推进 TD4 与首装使用。

### 输入与构建

```
# 0) 联网输入：mkbootimg/unpack_bootimg
sh tools/fetch-aosp-mkbootimg.sh

# 1) 从 stock ROM 拆 ABL 要的 overlay 集与基 DTB 集
python3 tools/extract-stock-dtbo-entries.py <dtbo.img> \
  tools/local/roms/liuqin/OS2.0.6.0.VMYCNXM/analysis/dtbo
python3 tools/extract-stock-base-dtbs.py <vendor_boot.img> \
  tools/local/roms/liuqin/OS2.0.6.0.VMYCNXM/analysis/vendor_boot/dtbs

# 2) 复用 v0.6.0 installer.img 的 ramdisk
python3 tools/local/aosp-mkbootimg/unpack_bootimg.py \
  --boot_img installer.img --out out/installer-unpacked

# 3) 装配（dtc/fdtoverlay 用 apt 的；镜像 ~58 MB，只受 192 MiB 分区上限
#    约束，不做填充）
CI=<Run #9 artifact 解包目录>
ABL_OVERLAY_SINK=1 ABL_DTB02_IDS=0 \
  MKBOOTIMG_DIR="$PWD/tools/local/aosp-mkbootimg" \
  DTC=/usr/bin/dtc FDTOVERLAY=/usr/bin/fdtoverlay \
  IMAGE="$CI/kernel/arch/arm64/boot/Image" \
  DTB="$CI/kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-liuqin.dtb" \
  RAMDISK="$PWD/out/installer-unpacked/ramdisk" \
  CMDLINE="$(cat device/native-bootargs.txt)" HEADER_CMDLINE= \
  OUT_DIR="$PWD/out/boot-test" sh tools/lib/build-bootimg.sh
```

要领：

- `ABL_DTB02_IDS=0` 与 release 一致（release DTB 的身份来自 ABL overlay
  的声明身份，已与 Run #9 DTB + overlay 的合并结果对齐）。
- `ABL_OVERLAY_SINK=1` 需要 ROM 拆出的两个目录；构建器用 **44 条目 / 14
  基 DTB / 1781 符号**三重计数断言兜住拆分正确性——错了构建失败，不会
  上机器。
- CI DTB 的 `/chosen/bootargs` 与 `device/native-bootargs.txt` 已逐字节
  全等，故不需要 native-boot.sh 的 cmdline overlay 步骤。
- 产物文件名由 `build-bootimg.sh` 定为 `boot-liuqin-firstboot.img`。

### 装配记录（2026-10-22，开发机本机）

Run #9 artifact 布局：`kernel/`（`Image`、`dts/qcom/sm8475-xiaomi-liuqin.dtb`、
`.config`、`vmlinux`、`System.map`、`SHA256SUMS`、`build-info.json`）+
`kernel-modules/`（`modules.tar` + 623 行 `modules.manifest`）。
`SHA256SUMS` 六项全过；`build-info.json` 的 `config_sha256` 即 TD4 要钉
的值；`kernel.release = 7.0.14-g2c2092606bed`。

装配（`ABL_OVERLAY_SINK=1 ABL_DTB02_IDS=0`，apt 的 `dtc`/`fdtoverlay`，
复用 v0.6.0 ramdisk）全部断言通过：44 个 DTBO 条目 + 14 个基 DTB 由
`tools/extract-stock-*` 从线刷包拆出；`abl-symbols.py` 的 1781 符号断言
通过，符号表与 v0.6.0 release 镜像的 sink 逐项一致；mkbootimg v2 回拆
round-trip、bootargs 漂移断言、identity 断言全过。产物
`repack/final-boot/boot-liuqin-firstboot.img`，58,564,608 字节（开发机本地
路径，不入仓库）。镜像已就绪，Pi 侧只做 `fastboot boot`。

### 复测记录（2026-10-25 晚，d24eb13 真机）

mdss `-EINVAL` 已消除：`ae00000.display-subsystem`、两个 DSI host、
`ae94000.dsi.0`（面板）probe 全部返回 0，dpu bound，`/sys/class/drm` 出现
card0/DSI-1/renderD128，`devices_deferred` 消失（触控解除 defer），`console
[drm_log0] enabled`，`uname -r` = `7.0.14-gd24eb13a3854`。但**接管后黑屏**：

- connector `connected`/`enabled`，模式 1800x2880，DPMS On
- `/sys/kernel/debug/dri/0/state`：plane-0 绑 crtc-0，fb 由 drm_log 分配，
  DPU multirect 双 900x2880 分发两路 DSI——**扫描链路完整**
- ktz8866 背光设备注册，亮度可调（100→1500 有可见变化）
- 无 fb 设备（`/dev/fb0` 不存在；`CONFIG_DRM_FBDEV_EMULATION=y` 等 ] 配置项都开）
- 往 /dev/kmsg 写字后面板**无任何文字**——扫描出的流没被面板显示

**根因：面板模块不匹配。** 本机面板是天马 `m81_36_02_0a`（cmdline
`dsi_display0` 指明，触控固件也按天马选择），而 DT 的 pipa 面板描述 init
序列按 CSOT `m81_42_02_0b` 建模。两模块的模式/DSC/时序/复位序列完全相
同，**唯一差异是 init 指令序列**（stock entry.15：天马 216 包 vs CSOT
194 包）。A/B 佐证：**v0.6.0（6.17）镜像在本机同样短暂输出后黑屏**——
非 7.0 回归；6.17 验证机的面板模块与本次 128G 测试机不同（同型号两种
屏幕，与触控固件不可互换已知，见 `4dcb6801404b`）。

**修复（内核 `df7a67b4b081`）**：`panel-novatek-nt36532.c` 增加按 cmdline
选择 init 的第二个 desc（天马序列，由 stock DTBO 216 条 DSI 包逐字节翻
译），选择方式照搬触控固件的既定模式；模式/DSC/复位不变；未列出的模块
保持 CSOT 序列。checkpatch 0 错 0 警。等新 CI 构建后复测。

次级观察（复测后再追）：NVT 触控 `nvt_check_fw_reset_state` 报错（固件
选择本身已命中 `novatek_nt36532_m81_fw_tm.bin`）；PCIe host 初始化
`-110`（P1 外设）；BT 链路活着，7.0 新固件名 `wcnhpbtfw21.tlv` 主请求
`-2` 后按预期走旧名回退。

### 装配记录（2026-10-26，df7a67b4 复装）

面板修复构建（commit `df7a67b4b081eb3fcf334c6c5386c577cd47a80a`，
release `7.0.14-gdf7a67b4b081`，config_sha256 与历次一致）解包校验通过，
同一管线复装：`repack/df7a67-boot/boot-liuqin-firstboot.img`，
58,568,704 字节，sha256
`00182b082053723eb280c41832fa9927891eb14538407095049eab9136dbc397`。
mkbootimg v2 回拆：kernel 解压 = 新 Image `dcdbc8dc…`；ramdisk
`a04d2b25…`；boot DTB 仍为 `4c15a591…`（DTS 未动）。

### 装配记录（2026-10-25，d24eb13 复装）

含 `d24eb13a3854` 的 CI artifact 解包到 `ci/`，`SHA256SUMS` 全过，
`config_sha256` 与 Run #9 一致（`d81ff750…`，未动配置）。复用
`tools/lib/build-bootimg.sh`（apt 的 `dtc`/`fdtoverlay`、v0.6.0
ramdisk `repack/unpacked/ramdisk`）全部断言通过；产物
`repack/d24-boot/boot-liuqin-firstboot.img`，58,564,608 字节，sha256
`3e723a9626ca5a21f2d08a9494b09f2765d5cc090117052aa04c1fca81d8d4a1`。
mkbootimg v2 回拆三段 byte-cmp 通过；kernel 负载解压 = 新 Image
`758c38bb…`；ramdisk `a04d2b25…`；最终 boot DTB 与首测镜像的
`4c15a591…` **逐字节相同**——预期：修复只改 `ubwc_config.c`，DTS
未动，编译产物 DTB 理应不变。

### 首测记录（2026-10-25，128G/8G 真机，RAM 启动）

通过：
- `uname -r` = `7.0.14-g2c2092606bed`；CMDLINE 带
  `qcom_q6v5_pas.slpi_auto_boot=0`，dmesg 中 slpi "available" 但从未
  "powering up"（adsp/cdsp 正常启动）——SLPI 所有权补丁生效。
- UFS fail-closed 契约完整：等块设备 → 置只读 → "UFS was not mounted"
  → telnet 192.168.7.2:2323 可用；`/dev/sde` = **2923429888**，与
  `liuqin-mark-slot-successful.c:31` 钉值全等——bug-1 的容量变体悬念在
  128G 单位上闭环，首装槽标记不会被几何拒绝。
- QUP/eUSB2/i2c 总线起来；deferred 只有 sound/codec/lpass-pinctrl（音频，
  TD5 预期）与 spi0.0。

失败（已定位并修复）：
- 黑屏有背光。`probe of ae00000.display-subsystem returned 22`（-EINVAL），
  无 mipi_dsi 总线、`/sys/class/drm` 只有 version、`byte0/pclk0` 时钟为 0。
  根因：ABL 叠加的 stock DTBO 条目 15 把运行时根 compatible 改写为
  `qcom,cape-mtp/qcom,cape/qcom,mtp`（我们写的 `xiaomi,liuqin` +
  `qcom,sm8475` 被覆盖），而 7.0 上游 `57f77cb75b74` 重构后的
  `drivers/soc/qcom/ubwc_config.c` 机器表没有 cape 条目（6.17 移植时加过），
  `qcom_ubwc_config_get_data()` 查表失败 → mdss 全灭。内核侧修复
  `d24eb13a3854`（恢复 cape→sm8350_data，补 sm8475）。

待新 CI 构建（含 `d24eb13a3854`）出 artifact 后重新装配测试镜像、复测；
mdss 起来后再看：DSI 面板 init（本机 cmdline 面板串是
`m81_36_02_0a`，DT 面板描述固定为 `xiaomi,pipa-nt36532`，
42_02_0b 与 36_02_0a 差异是否影响点亮）、触控 spi0.0 是否随 panel@0 解除
defer、以及 dmesg 全量里是否还有其它机器级查表缺口。

记录修正：本机 7.0 实测 **pstore 可用**（"pstore is available at
/sys/fs/pstore"），与本文"无 pstore"的旧断言相反（下文红线已据此修
正）。

### Pi 4B 主机注意

- **USB 口**：优先蓝色 USB 3.0 口直连（USB-A→C 数据线）；镜像约 58 MB，
  枚举不稳再退黑色 USB 2.0 口。不要用 Hub。
- **供电**：Pi 口只给 SDP 电流，平板耗电靠电池——先用原厂充电器充到
  ≥50%，测试期间插着的 Pi 口仅作数据。
- **取地址**：`sudo dhclient usb0`（或 `dhcpcd`/NetworkManager），应得
  192.168.7.10-19。
- **录制**：`script -c 'telnet 192.168.7.2 2323' session.log` 全程留存，
  连同 `getvar-before.txt`、面板照片一起回报。

## 下一步

- **阻塞**：含 `d24eb13a3854`（ubwc cape 条目）的新 CI 构建与复测窗口。
- 首测通过后：推进 TD4（锁到 `2c2092606bed` + 钉 `config_sha256`）→
  完整镜像装配 → `--layout linux-only --allow-unverified` 首装（该布局
  从未真机安装过）。目标即整机 ARM PC：默认 `--android-size 0` 全盘
  归 Ubuntu，不保留 Android。**代价**：首启若系统性失败（持久根探针被
  拒或槽标记被拒）没有在机回退，落点是 fastboot；容错路径是
  `fastboot boot installer.img` 重装（RAM 安装器完好、telnet 通道可
  诊断）。因此首测里的 `blockdev --getsize64 /dev/sde`（容量变体闭环）
  与 bug-1 分诊清单不是可选项，是首装前置门（见
  `docs/triage-2026-10.md`）。
- 推送状态：内核 `liuqin-7.0` 全部推送；安装器 main 的本地提交由用户
  分批推送，堆积量以 `git log @{u}..HEAD` 为准（写本文时为 `8084e9e`、
  `bac9197`、`a5aaff7`）。
