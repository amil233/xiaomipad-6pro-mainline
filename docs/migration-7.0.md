# 内核迁移到 Ubuntu 7.0：状态与技术债

记录 liuqin（Xiaomi Pad 6 Pro）从 `liuqin-6.17`（真机验证过的基线）迁移到
`liuqin-7.0`（Ubuntu 7.0，`Ubuntu-7.0.0-42.42` 基线）的进度、证据和债务。

参考过程：`android-mainline-port` skill（本文的状态词、技术债格式和首启检查
清单遵循 `references/verification.md` 与 `references/discipline.md`）。

除非注明，以下所有离线结论的版本：

| 项 | 版本 |
|---|---|
| 内核分支 | `linux-sm8450-liuqin` `liuqin-7.0`，tip `2c2092606bed` |
| 安装器 | `xiaomipad-6pro-mainline` main，`541b866`（含 `f983dc8`、`a1d4efa`），已推送 |
| 内核 CI | Run #9（head `2c2092606bed`，conclusion success，约 11 分钟）覆盖全部 10 个移植提交；Run #8 覆盖到 `e6c2f01cd036` |
| 产物复核 | Run #9 的 `.config` 与 Run #8 实质符号零差异；新 DTB 的 bootimg 合约断言 10/10 通过 |
| 产品锁 | `kernel/source.json` 仍钉 `a322d592cb92`（迁移前的干净历史 tip） |

**当前一句话**：10 个移植提交（含 SLPI 启动所有权）离线全绿并 CI 全绿
（Run #9），安装器侧断链已修复并全部推送，等真机首测（path A 执行版见文末）。

## 移植状态

| 组件 | 状态 | 证据 |
|---|---|---|
| qcom-pon 暖复位 PS_HOLD | 离线通过 | 提交 `b70b53febdbb`，`POWER_RESET_QCOM_PON=y` |
| `/reserved-memory` 割区探测限制 | 离线通过 | 提交 `85feb95e7cc2`；见下方"已验证符合经验" |
| simple-framebuffer earlycon | 离线通过 | 提交 `b034fb07e84f`；DTB 断言全通过（见下） |
| SM8475 TLMM pinctrl | 离线通过 | 提交 `55e410f4f603`，`PINCTRL_SM8475=y` |
| I2C eUSB2 repeater | 离线通过 | 提交 `91552d3b4a72`；dtb 引用链闭合 |
| NT36532 面板驱动 | 离线通过 | 提交 `9719bc3c5f38`（6.17 tip 逐字移植） |
| DSI 双 slice/包 | 离线通过 | 提交 `993054693403`；与 6.17 行为核对（见下） |
| NT36523 触控驱动 | 离线通过 | 提交 `e6c2f01cd036`，`TOUCHSCREEN_NT36523_SPI=y` |
| SLPI 启动所有权（用户态） | 离线通过 | 提交 `253032ac87c8` + `2c2092606bed`；送 `sensor-startup.py` 的启动参数断言通过 |
| `.config` P0 符号 | 离线通过 | Run #8 产物 `.config`：受害者清单全部 `=y`（见下） |
| DTB 引用链 | 离线通过 | 面板/背光/触控/hyphy/repeater phandle 闭合 |
| boot 镜像合约 | 离线通过 | 10/10 断言 + fdtoverlay 实测（见下） |
| ABI/模块树 | 离线通过 | `kernel.release` 派生路径全部动态（`build-liuqin-debs.sh`） |
| 真机启动 | 待测 | 阻塞：无设备测试窗口 |

### 离线核对记录（本次 review 新做）

用 CI 产物 `.config` 与 DTB（Run #8）逐项对照经验库：

1. **`.config` 受害者符号**（`=m` 但 RAM 镜像无模块目录会静默缺失）：`QCOM_GPI_DMA`、
   `SPI_QCOM_GENI`、`RTC_DRV_PM8XXX`、`OVERLAY_FS`、`UHID`、
   `FW_LOADER_COMPRESS_ZSTD`、`PSI`、`QRTR`、`QCOM_PD_MAPPER`、
   `BATTERY_QCOM_BATTMGR` 全部 `=y`。`MODVERSIONS` 未开——模块 ABI 检测依赖
   打包脚本的 vermagic 校验，跨版本不兼容由 `uname -r` 强校验兜底，可接受。
2. **SPI 三层**（父包装器/GPI DMA/驱动内建）：`geniqup@8c0000` 存在，触控所在
   SPI 的 DMA（phandle `0x72`）`status = "okay"`，`QCOM_GPI_DMA=y`。
3. **触控 TDDI 生命周期**：驱动是完整的 panel follower——`drm_is_panel_follower()`
   检测、probe 在 follower 模式不发工程复位、`IRQF_NO_AUTOEN`、
   `panel_prepared`/`panel_unpreparing` 回调重新下载固件；DTB 触控节点带
   `panel = <&panel>`。经验库的"TDDI 熄屏后触控失效"、"面板上电前 probe"两个坑
   在驱动层面已规避。`input_allocate_device()` 未设父设备但该驱动不用
   `touchscreen_parse_properties()`，该路径不适用。
4. **DSC RC 参数**：`dsi_populate_dsc_params()`（`dsi_host.c:1858`）调用
   `drm_dsc_setup_rc_params(dsc, DRM_DSC_1_1_PRE_SCR)` 覆盖 RC 表——核对 6.17
   分支（`2cd5a6f8ef67`）**同一函数同一行为**，且面板驱动不自设 RC 值。该面板
   本就是 pre-SCR 类，标准表即真机验证过的组合，无移植回归。面板侧仅
   `slice_width=450 / slice_count=2 / bpp=8<<4`，已核对。
5. **USB 角色切换 `-ENOENT`**（经验库记为 7.x 上游问题）：本板 `dr_mode=peripheral`，
   dwc3 不注册角色切换，glue-dir 重建路径不触发；initramfs 的 `usb_role` 强制
   仅作无 UDC 时的兜底。
6. **Gunyah `/hypervisor` 误判虚拟机**：安装器用户态已处理
   （`liuqin-hide-gunyah-node.service` + gnome-control-center 补丁强制 chassis
   tablet）；运行时确认仍进首启检查清单。
7. **boot 镜像合约**：用 Run #8 的 DTB 跑 `build-bootimg.sh` 的全部断言
   （bootargs 全等、simple-framebuffer 六属性、`/chosen` cells 与 ranges）
   10/10 通过；再忠实复刻 `dtc -@` + `fdtoverlay` 合并 `liuqin-abl-boot-overlay`，
   三个 ABL 身份属性（msm-id 531/540/530、board-id `0x10008`、miboard-id `0x10`）
   注入成功，合并后断言仍全通过。
8. **6.17 提交全集审计**（本 review 的系统性部分）：逐个过了
   `a19585977c11..liuqin-6.17` 的全部提交，按首启相关性分类。结论：
   - 触控固件按面板模块选择（`4dcb6801404b`）、触控笔坐标缩放
     （`fba87d1d7c6f`/`a40b967b3d03`）随触控目录的逐字移植到位；
   - **SLPI 启动所有权补丁对（`569f79be4a7d` + `a54c2b5501a7`）漏移植**——
     7.0 的 PAS 驱动 `auto_boot` 只来自平台描述符，无模块参数可覆盖，
     SLPI 会在内核启动阶段自动拉起，把 6.17 收敛到用户态服务里的
     SLPI 复位窗口推回内核引导期（无 USB、只能按键恢复）。已补移植
     （`253032ac87c8` + `2c2092606bed` + 安装器 `a1d4efa`）；
   - `e6604d01be72`（rtnetlink 不解引用无名父设备）未移植，7.0 代码结构
     已变，对 NCM-only 的 RAM 首启路径无交集——留作真机上若出现
     rtnetlink dump NULL deref 时的第一怀疑项；
   - 其余未移植项（DP/指纹/相机/音频/充电/GPU/USB3/ucsi/qmp-combo/
     ASoC TDM）全部是计划内延后的 P1/P2，首启不需要。

### 安装器侧已修复的断链

- `device/native-bootargs.txt` 与 7.0 板级 DTS 的 `/chosen/bootargs` 漂移（6.17
  时两者全等，7.0 端口改了 DTS 后安装器侧未同步），`build-bootimg.sh` 的全等
  断言会让所有 boot 镜像构建失败——提交 `6b9b688` 同步（`panic=0`→`panic=15`，
  顺带删除 7.0 上已是死参数的 `qcom_q6v5_pas.slpi_auto_boot=0`）。
- 6 处文档仍写 `liuqin-6.17`——提交 `025e562`。
- SLPI 参数补移植后，令牌重新生效——安装器提交 `a1d4efa` 把
  `qcom_q6v5_pas.slpi_auto_boot=0` 加回 native 启动参数，与内核 DTS 保持
  全等。事后看 `6b9b688` 删令牌是对的（当时的树确实无此参数），漏的是驱动
  补丁本身；三个新提交合起来恢复 6.17 验证过的完整行为。

内核三提交（`253032ac87c8`、`2c2092606bed`）与安装器 `a1d4efa` 已全部推送，两个 fork 与本地一致；Run #9 绿。

Run #9 产物复核（`ci/liuqin-kernel-2c2092606bed…/`，本地副件）：`.config`
与 Run #8 逐符号对比零差异（补丁不碰 Kconfig）；DTB 的 bootimg 全套断言
（bootargs 与 native-bootargs 全等、simple-framebuffer 六属性、`/chosen`
cells 与 ranges）10/10 通过，fdtoverlay 合并 ABL overlay 后仍全通过，SLPI
固件名节点在位。

## 技术债表

| 编号 | 债务 | 位置 | 为什么需要 | 影响 | 去除条件 |
|---|---|---|---|---|---|
| TD1 | `clk_ignore_unused pd_ignore_unused` 仍在 native 启动参数 | `device/native-bootargs.txt`（来自 6.17 调试集） | 首测期需要排除"资源回收"类失败 | 无法省电、无法休眠；经验库未解决问题提示这些参数可能影响面板点亮时序 | 首测确认显示链稳定后撤除，并把固件留下的资源需求写进真正的消费者节点；撤除后按经验库做回收前后 `clk_summary`/`pm_genpd_summary` 差集 |
| TD2 | 多媒体驱动一次性内建（面板/触控/pinctrl 全 `=y`） | `.config`（`liuqin-*.config` 片段） | RAM 阶段无模块目录；6.17 产品即此配置 | 与经验库"新驱动先做模块"的默认相悖 | 驱动代码逐字来自 6.17 真机验证版本；首测如有早期挂死，改为模块化验证后重测 |
| TD3 | ~~SLPI 无内核级关闭手段~~ **已解决** | 6.17 的 `slpi_auto_boot` 模块参数补丁已移植（内核 `253032ac87c8` + `2c2092606bed` + 安装器 `a1d4efa`），SLPI 注册但不自动启动，与 6.17 验证配置一致 | — | ~~-~~ | 首测仍观察 SLPI 启动日志；用户态 `/etc/liuqin-slpi-disabled` 标记仍是复位问题的退出手段 |
| TD4 | `config_sha256` 未在标准镜像主机定版 | `kernel/source.json`（仍钉 `a322d592`） | `build-liuqin-image.py:97-100` 硬失败；本地生成会因编译器版本漂移 | 完整安装包装配被阻塞（path A RAM 测试不受影响） | 真机验证通过后推进锁到 `e6c2f01cd036`，在镜像主机跑配置定版回写 |
| TD5 | P1/P2 外设全部延后 | 内核树无对应驱动 | 首版优先启动与交互 | WiFi/BT/电池/GPU/音频/传感器/DP/相机/指纹/键盘均不可用 | 按用户优先级逐个移植，每次一个候选 |
| TD6 | 文档仓库地址未统一 | `README.md:142` 等指 yzddmr6，`source.json` 指 amil233 fork | fork 迁移进行中 | 工作流 owner 推导可能 checkout 错仓库 | 用户定项目归属后统一 |

## 真机首测计划（path A：只测内核）

1. 用 Run #9 产物（Image + DTB）在主机上构建 **stage-1-only 诊断
   boot 镜像**（`fastboot boot` RAM 启动，不写任何分区）——构建步骤见文末
   "树莓派 4B 主机执行补编"。
2. **首启检查清单**（经验库 step 3）：
   - `cat /proc/device-tree/compatible` 与 model——与源码对比，注意 ABL 可能
     覆盖根身份
   - `systemd-detect-virt` 应非 vm；`hostnamectl` Chassis 应为 tablet（Gunyah
     遮蔽生效）
   - `uname -r` 等于 bundle 记录的 kernel_release
   - `/sys/kernel/debug/devices_deferred` 为空或每项可解释
   - sync_state：`/sys/kernel/debug/pm_genpd_summary` 无长期挂起的提供者
   - 最终 `.config` 关键项与 Run #9 产物一致
3. **通道验收**：earlycon 面板出字 → USB NCM 枚举（主机 DHCP 拿
   192.168.7.10-19）→ telnet 192.168.7.2:2323 双向命令 + dmesg 完整。
4. **显示链观察**（R2/R5）：面板 init 的 accum_err 日志、dmesg 中 DSI 错误、
   人眼确认画面、帧计数。
5. **触控观察**：dmesg 的 `probe complete: follower=... panel_on=...`、固件
   下载日志、ABL cmdline 里的面板型号字符串（`m81_36_02_0a`/`m81_42_02_0b`）。
6. 每项失败按层定位（模式 A–I），同类失败第二次出现停下来写分析。

### 首测前的用户侧前提

- 设备身份与电量（`fastboot getvar`、≥30%）
- 备份与恢复路径（安装器的备份流程或可刷回的原厂 ROM）
- 首测建议用户在场（人眼确认画面与触控）

## 下一步与阻塞

- **阻塞**：真机测试窗口。
- 推送状态：内核与安装器两 fork 均与本地一致，无积压提交。
- 推送后：`checks.yml` 验证安装器侧改动；内核侧无待办。
- path A 通过后：推进锁（TD4）→ 完整镜像装配 → `--layout linux-only
  --allow-unverified` 首装（该布局从未真机安装过）。
probe

## 真机操作手册（path A 执行版）

### 红线：本流程只读不写

- **只用 `fastboot boot`**（RAM 启动）。不 `flash`、不 `erase`、不
  `--set-active`、不跑 `install.py` 及任何安装流程。
- 槽 A 保持原厂且仍标记成功：任何重启（含 panic 自动重启、长按电源强制重启）
  都自动回原厂。9008 只能由 XBL 级灾难产生，本流程不写 XBL，无从触发。
- persist 分区：path A 不写 UFS——存储接受失败即回落诊断 shell，而该 shell
  只在“所有 UFS 块设备已证只读”（`ufs_safe`）后才开 telnet。persist 唯一的
  威胁是万一需要 9008 全刷：刷前核对线刷脚本是否含 persist 分区，含则跳过
  （persist 内是本机唯一的校准/MAC 数据，不可从其他机器复制）。

### 测前准备

- `fastboot getvar all` 存档（解锁状态、`current-slot`、`max-download-size` 应
  ≥ 0xC0000000 以容纳 192 MiB 镜像、`product=liuqin`、电量）。
- 电量 ≥50%，用原厂充电器或 PD 口供电：普通 SDP 口有
  boot/drain/reboot 循环风险（initramfs 注释，androidboot.mode=charger 分流）。
- **无 pstore**：7.0 板级 DTS 未含 ramoops/pstore 节点，panic 重启后内核日志
  不可恢复。相机/手机待命，面板是早期唯一的证据渠道。
- 主机备好 telnet 录制手段（`script` 或终端日志），全程留存。

### 执行序列

1. 进 fastboot（音量下+电源），`fastboot getvar all 2>&1 | tee getvar-before.txt`。
2. 主机按 "树莓派 4B 主机执行补编" 构建 stage-1-only 诊断 boot 镜像。
3. `fastboot boot <out>/boot-liuqin-firstboot.img`：期望 `OKAY`，随后面板出现
   earlycon 文本（移植的 `earlycon=simplefb`），主机出现 usb0（NCM）。
4. 主机取地址：`sudo dhclient usb0`（或 nmcli），应得 192.168.7.10-19。
5. `telnet 192.168.7.2 2323` → busybox 诊断 shell。开场命令：
   ```
   mount -t debugfs none /sys/kernel/debug
   cat /proc/cmdline; cat /proc/device-tree/compatible; cat /proc/device-tree/model
   uname -r
   cat /sys/kernel/debug/devices_deferred
   cat /sys/kernel/debug/pm_genpd_summary
   dmesg
   ```
   `/proc/cmdline` 里 ABL 会追加约 800 字符 `androidboot.*`——这不是漂移；
   但结尾应能看到本板的 `qcom_q6v5_pas.slpi_auto_boot=0`。
6. 移植验收（本次 review 的直接验证点）：
   - **SLPI**：`ls /sys/class/remoteproc/` 有 slpi 节点且 dmesg 无
     "Booting processor" —— 参数生效、未在内核期自动启动（本次移植的目标）。
   - **显示/触控**：`dmesg | grep -iE "panel|dsi|dsc|nt36|ktz|backlight"`，
     人眼确认画面与背光；触控看 `probe complete: follower=` 行与
     `dmesg | grep -i nvt`。
   - `dmesg | grep -iE "gpi-dma|eusb2|i2c@|spi@"` 确认三条数据通路。
   - `cat /sys/kernel/debug/clk/clk_summary` 只读一次（会唤醒部分子系统，
     供 TD1 撤除 `clk_ignore_unused` 前后做差集）。
7. 结束：shell 内 `reboot -f`（或长按电源），验证设备回到原厂 Android
   （这是本流程可随时挽回的证明）。

### 失败决策树（不要盲迭代）

- `fastboot boot` OK 但无面板无 USB：长按电源回原厂，先验证硬件无恙再报回；
  高度怀疑镜像未带 ABL overlay sink（离线已证 DTB 有 `__symbols__` 注入）。
- 面板有 earlycon、telnet 不通：`ufs_safe` 未过，dmesg 的 UFS 行是关键，
  只能靠面板拍照读。此时诊断 shell 仍只读，无 persist 风险。
- telnet 通、无画面：从 dmesg 的 panel/DSI 累积错误定位（R2/R5），勿调参。
- 设备自行重启（panic=15 自动重启）：日志已丢，只能靠重启前面板照片；
   重试时相机连续拍摄。
- 反复起不来：停止，回原厂，以上就是全部挽回手段（外加已备的线刷包）。

### 回报格式（便于离线对账）

操作时间线 + getvar 存档 + telnet 全程录制 + 上述命令输出（cmdline/compatible/
uname/devices_deferred/pm_genpd_summary/clk_summary/dmesg 全文）+ 面板照片
（尤其 earlycon 首帧与黑屏状态）。

## 树莓派 4B 主机执行补编

实机测试的主机是一台 arm64 Debian 的树莓派 4B，经 USB 连接平板（128 GB/8 GB）。

### 形态选择：复用 v0.6.0 installer.img 的 ramdisk

镜像装配不再从零打 initramfs——那需要 `tools/local/firmware-liuqin/` 固件池
（本地从未存在，见下节"为什么不用 build-liuqin-native-boot.sh"），而是
**复用 release v0.6.0 `installer.img` 的 ramdisk**：它已是
`readonly + native` 形态（boot 后不探任何存储，直接救援 shell +
telnet 2323），内置全套哈希钉死的固件。与设备已验证的 v0.6.0 启动相比，
测试只换 `Image` 与 DTB——ramdisk 逐字节不变，隔离出唯一变量。

代价：诊断 shell 没有 systemd（`systemd-detect-virt`/`hostnamectl` chassis
两项 stage-2 检查做不了），Gunyah 遮蔽验证顺延到首装后的全镜像测试；内核
层一切可测（启动、NCM、earlycon、显示、触控、remote proc、时钟/电源域）。

### 为什么不用 build-liuqin-native-boot.sh

不是偏好问题，是三条硬前提当前全缺：脚本读 `$kernel_out/scripts/dtc/{dtc,
fdtoverlay}` 与 `include/config/kernel.release`（本地不编译内核就没有这棵
构建树）；断言源码 HEAD 与 `kernel/source.json` 锁一致且 `.config` 哈希吻合
（锁仍钉 `a322d592cb92`，tip 是 `2c2092606bed`，直接硬失败）；还要
`NATIVE_ROOT_HASHES`/`AUDIO_TOPOLOGY`/`WLAN_HSP2_TUPLE` 一整套产品链输入。
诊断形态与它共用 `build-bootimg.sh`，只是换 env，不碰锁、不拖产品流水线。
该脚本留给 path A 通过后推进 TD4 与首装使用。

### 主机软件（apt 即可，全部架构中立）

`git curl python3 gzip device-tree-compiler fastboot telnet
isc-dhcp-client`（或 dhcpcd/NetworkManager 之一）。不编译任何东西：
内核靠 CI 产物，initramfs 复用 release。

### 输入件（全部可联网取得，无"另一台机器"依赖）

- Run #9 内核产物：`Image` 与 `sm8475-xiaomi-liuqin.dtb`——从 Action
  artifact 下载（102 MB，`…/actions/artifacts/12347240243/zip`）
- v0.6.0 release 的 `installer.img`：**ramdisk 复用**——内置全套
  stage-1（哈希钉死的固件池、busybox、安装器运行时），形态
  `readonly + native`，boot 后不探任何存储、直接救援 shell + telnet。
  与设备已验证的 v0.6.0 启动相比，**唯一变量就是 7.0 内核与 DTB**
  （本机构建已离线验证这条替换路径：overlay identity、漂移断言、
  round-trip 全通过，产出 58 MB 镜像）
- stock ROM 的 `dtbo.img` 与 `vendor_boot.img`（须 OS2.0.6.0.VMYCNXM）：
  ABL 私有验收要 44 个 DTBO 条目 + 14 个基 DTB，仓库新增
  `tools/extract-stock-dtbo-entries.py` / `tools/extract-stock-base-dtbs.py`
  机械拆出，构建器再用 44/14/1781 三重计数断言兜住拆分正确性
- `sh tools/fetch-aosp-mkbootimg.sh`（mkbootimg/unpack_bootimg）

### 构建

```
# 1) 从 stock ROM 拆 ABL 要的 overlay 集与基 DTB 集
python3 tools/extract-stock-dtbo-entries.py <dtbo.img> \
  tools/local/roms/liuqin/OS2.0.6.0.VMYCNXM/analysis/dtbo
python3 tools/extract-stock-base-dtbs.py <vendor_boot.img> \
  tools/local/roms/liuqin/OS2.0.6.0.VMYCNXM/analysis/vendor_boot/dtbs

# 2) 复用 v0.6.0 installer.img 的 ramdisk
python3 tools/local/aosp-mkbootimg/unpack_bootimg.py \
  --boot_img installer.img --out out/installer-unpacked

# 3) 装配（dtc/fdtoverlay 传 apt 的绝对路径；镜像 ~58 MB，只受 192 MiB
#    分区上限约束，不做填充）
CI=<Run #9 artifact 解包目录>
ABL_OVERLAY_SINK=1 ABL_DTB02_IDS=0 \
  MKBOOTIMG_DIR="$PWD/tools/local/aosp-mkbootimg" \
  DTC=/usr/bin/dtc FDTOVERLAY=/usr/bin/fdtoverlay \
  IMAGE="$CI/Image" DTB="$CI/sm8475-xiaomi-liuqin.dtb" \
  RAMDISK="$PWD/out/installer-unpacked/ramdisk" \
  CMDLINE="$(cat device/native-bootargs.txt)" HEADER_CMDLINE= \
  OUT_DIR="$PWD/out/boot-test" sh tools/lib/build-bootimg.sh
```

`ABL_DTB02_IDS=0` 与 release 一致（release DTB 的 identity 来自 ABL
overlay 的声明身份，已与 Run #9 DTB + overlay 的合并结果对齐）；
`ABL_OVERLAY_SINK=1` 需要 ROM 拆出的两个目录，`abl-symbols.py` 钉死 1781
个符号。CI DTB 的 `/chosen/bootargs` 与 `device/native-bootargs.txt` 已逐字
节全等，故不需要 native-boot.sh 的 cmdline overlay 步骤。

### Pi 4B 特定注意

- **USB 口**：优先蓝色 USB 3.0 口直连（USB-A→C 数据线）；镜像约 58 MB，
  枚举不稳再退黑色 USB 2.0 口。不要用 Hub。
- **供电**：Pi 口只给 SDP 电流，平板耗电靠电池——先用原厂充电器把平板
  充到 ≥50%，测试期间插着的 Pi 口仅作数据。深度放电 + SDP 供电有
  boot/drain/reboot 循环风险。
- **取地址**：`sudo dhclient usb0`（或 `dhcpcd`/NetworkManager），应得
  192.168.7.10-19。
- **录制**：`script -c 'telnet 192.168.7.2 2323' session.log` 全程留存，
  连同 `getvar-before.txt`、面板照片一起回报。
