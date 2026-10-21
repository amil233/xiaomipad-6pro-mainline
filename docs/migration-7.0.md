# 内核迁移到 Ubuntu 7.0：状态与技术债

记录 liuqin（Xiaomi Pad 6 Pro）从 `liuqin-6.17`（真机验证过的基线）迁移到
`liuqin-7.0`（Ubuntu 7.0，`Ubuntu-7.0.0-42.42` 基线）的进度、证据和债务。

参考过程：`android-mainline-port` skill（本文的状态词、技术债格式和首启检查
清单遵循 `references/verification.md` 与 `references/discipline.md`）。

除非注明，以下所有离线结论的版本：

| 项 | 版本 |
|---|---|
| 内核分支 | `linux-sm8450-liuqin` `liuqin-7.0`，tip `2c2092606bed` |
| 安装器 | `xiaomipad-6pro-mainline` main，`f983dc8`、`a1d4efa`（均待推送） |
| 内核 CI | Run #8（`liuqin-kernel-e6c2f01…`，conclusion success）覆盖到 `e6c2f01cd036`；`253032ac87c8`/`2c2092606bed` 待推送触发新构建 |
| 产品锁 | `kernel/source.json` 仍钉 `a322d592cb92`（迁移前的干净历史 tip） |

**当前一句话**：8 个移植提交离线全绿（编译、`.config`、DTB 引用链、boot 镜像
合约、ABL overlay 合并），等真机首测；安装器侧两个断链点（启动参数漂移、文档
分支名）已修复，未推送。

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

内核三提交（`253032ac87c8`、`2c2092606bed`）与安装器 `a1d4efa` 均在本地，
等推送（SSH 推送由用户执行）；`025e562`、`6b9b688` 已推送至 amil233 fork。

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

1. 用 Run #8 产物（Image + DTB）在已备好输入的机器上跑
   `build-liuqin-native-boot.sh` 产出 v2 boot 镜像（`fastboot boot` RAM 启动，
   不写任何分区）。
2. **首启检查清单**（经验库 step 3）：
   - `cat /proc/device-tree/compatible` 与 model——与源码对比，注意 ABL 可能
     覆盖根身份
   - `systemd-detect-virt` 应非 vm；`hostnamectl` Chassis 应为 tablet（Gunyah
     遮蔽生效）
   - `uname -r` 等于 bundle 记录的 kernel_release
   - `/sys/kernel/debug/devices_deferred` 为空或每项可解释
   - sync_state：`/sys/kernel/debug/pm_genpd_summary` 无长期挂起的提供者
   - 最终 `.config` 关键项与 Run #8 产物一致
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

- **阻塞**：真机测试窗口；两个修复提交待推送。
- 推送后：`checks.yml` 验证安装器侧改动；内核侧无待办。
- path A 通过后：推进锁（TD4）→ 完整镜像装配 → `--layout linux-only
  --allow-unverified` 首装（该布局从未真机安装过）。
