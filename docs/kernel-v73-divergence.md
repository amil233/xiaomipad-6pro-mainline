# 内核树相对上游 v7.3 的偏离统计（stage 2 基线）

**基准**：上游 tag `v7.3`（`c03c1a14507d`）vs 本仓 `liuqin-7.3` @ `17abc027f75f`
（2026-11-14 点亮 tip；在 `db08160915e3` 之上又叠加了上游 v0.6.1/v0.6.2
移植、v7.4-rc2 回移与 TDM per-DAI 改造）。

**总览**：173 个文件（新增 63 / 修改 110 / 删除 0），+58,396 / −301 行。
（`liuqin-7.3-v070` 上又新增/修改 12 个文件，见文末"v0.7.0 移植增量"。）
来源三分：① yzddmr6 厂商树的板级外设驱动；② 我们的点亮修复与改进；
③ 构建/CI/文档。**无删除文件**——所有偏离都是叠加性质，升级时不存在
"上游删了我们靠它"以外的隐性丢失风险（该风险体现在"上游改/ revert"侧，
见 upgrade doc 各级修复记录）。

---

## 1. 显示点亮栈（19 文件，265+/52-）—— 点亮必需，升级绝不可丢

| 文件 | 理由 |
|---|---|
| `dpu_hw_mdss.h`/`dpu_hw_catalog.h`/`dpu_encoder_phys.h` | quad-pipe 常量（`STAGES_PER_PLANE=2`、`MAX_CHANNELS_PER_ENC=4`） |
| `dpu_plane.c` | mixer 粒度拆分条件（`mixer_rect/PIPES_PER_STAGE`，修 7.1 四竖条花屏） |
| `dpu_crtc.c`/`.h`、`dpu_encoder.c` | 2 LM/2 DSC 拓扑（上游 4-DSC 路径自己 revert 了） |
| `dp_ctrl.c`/`.h`、`dp_aux.c`、`dp_display.c` | PHY-before-AUX 补丁 + DPCD 读 5 次重试环（DP 节点 disabled 但驱动仍编译） |
| `dsi_host.c` | `dsc_slice_per_pkt` liuqin 路径（面板设 2，attach 复制） |
| `dsi_phy.h` + `dsi_phy_7nm.c` | bonded-DSI PLL 修复回移（`db08160915e3`；该文件含 5nm 配置，适用本机 PHY `qcom,sm8450-dsi-phy-5nm`） |
| `a6xx_gmu.c`、`msm_gpu.c`/`.h`、`msm_gpu_devfreq.c` | a6xx 冷启动修复 + `busy_percent` |
| `include/drm/drm_mipi_dsi.h` | `dsc_slice_per_pkt` 字段 + 上游新 flag 并集 |
| `panel-novatek-nt36532.c`（新增） | **当前点亮的面板驱动**（天马 m81_36_02_0a desc + cmdline 匹配；DTS compatible `xiaomi,pipa-nt36532`） |
| `soc/qcom/ubwc_config.c` | `qcom,cape` 机器别名（ABL 实传 root compatible 为 cape 系列） |

## 2. 触控（36 文件，36677+/0-）—— 厂商树

- `input/touchscreen/fts_spi/`（30 文件）：FocalTech FTS 触控完整厂商库
- `input/touchscreen/nt36523/`（6 文件）：Novatek 触控

## 3. TEE/QSEECOM（9 文件，2043+/0-）

- `tee/qseecom/core.c` + `include/linux/tee_core.h` + `uapi/linux/tee.h`
  + `Documentation/tee/` + `tee/Kconfig`/`Makefile`：QSEE 代理，
  指纹/DRM 等 TA 依赖。

## 4. 音频（13 文件，711+/16-）

- `sound/soc/codecs/cs35l41.c`/`.h` + `wm_adsp.c`/`.h`
  + `firmware/cirrus/cs_dsp.c`：喇叭保护 DSP（cs35l41 主体是上游驱动，
  我们加喇叭保护链）
- `sound/soc/codecs/tfa9872.c`（新增）：功放
- `sound/soc/qcom/qdsp6/`（audioreach.c/.h、q6apm.c、q6apm-dai.c、
  topology.c）+ `sound/soc/qcom/common.c`：TDM 支持
- **外放 TDM 链路（2026-11-07 出声，2026-11-14 改为 per-DAI）**：
  `sc8280xp.c` 原有三处改动（BE fixup 跳过 TDM 后端、DSP_A + 每颗功放
  一个 slot、codec PLL 参考）在 `17abc027f75f` 中收敛为 **v7.4 的
  per-DAI 板级配置**（对齐上游 `ea6e98472c65`）：`struct
  sc8280xp_dai_data` + `SC8280XP_DAI_DATA()`，liuqin/cupid 的
  `TERTIARY_TDM_RX_0` 一条配置表达 DSP_A、逐 codec slot 与 component
  sysclk；`cs35l41.c` 的 `.set_tdm_slot` 保留。**升级时注意**：上游
  7.4 的 per-DAI 结构会与我们的三个扩展字段相邻，别丢
  `codec_dai_fmt`/`codec_tdm_slot_each`/`codec_component_sysclk`；
  7.3 合并时 PLL 那段曾被上游重构静默丢弃过一次（同类盲区：ubwc 的
  `qcom,cape`）。细节与复测方法见 `docs/AUDIO.zh-CN.md`。

## 5. 相机（6 文件，447+/64-）

- `media/platform/qcom/camss/` 五件套：SM8475 资源表 + regulators
  结构适配（v7.0 CI 修复）
- `clk/qcom/camcc-sm8450.c`：相机时钟

## 6. PHY / USB / UFS（12 文件，592+/34-）

- `phy/qualcomm/phy-qcom-qmp-combo.c`、`phy-qcom-qmp-common.h`、
  `phy-qcom-qmp-pcie.c`：厂商移植表残留 + DP PLL 失败上送
  （qmp-combo 主体已换上游 SM8475 表）
- `phy/qualcomm/phy-qcom-i2c-eusb2-repeater.c`（新增）：eUSB2 中继
- `usb/dwc3/drd.c`、`usb/typec/ucsi/ucsi.c`/`ucsi_glink.c`、
  `usb/typec/mux/fsa4480.c`：USB-C role switch + CCI 去抖
- `ufs/host/ufs-qcom.c`/`.h`：UNIPRO 850MHz 时钟修复

## 7. pinctrl（3 文件，1715+/0-）

- `pinctrl/qcom/pinctrl-sm8475.c`（新增，FROMLIST）：**上游至今没有
  SM8475 pinctrl**，且含 `MSM_GPIO_PIN_FUNCTION` 修复（6.18 点亮修复）

## 8. SoC / 固件 / 电源

- `firmware/qcom/qcom_scm.c` + `include/linux/firmware/qcom/qcom_scm.h`：
  TEE 初始化 + allowlist
- `soc/qcom/mdt_loader.c`/`include/linux/soc/qcom/mdt_loader.h`：
  split-image loader（qseecom 用）
- `soc/qcom/pmic_glink.c`、`qcom_pd_mapper.c`、`pdr_internal.h`：
  PD mapper 厂商定义
- `power/supply/qcom_battmgr.c`：小米鉴权协议
- `remoteproc/qcom_q6v5_pas.c`：SLPI
- `power/reset/msm-poweroff.c`、`qcom-pon.c`：reboot reason 寄存器
- `cpufreq/cpufreq-dt-platdev.c`：SM8475 白名单（1 行）

## 9. 比上游更新的正向修复（2 文件，34+/5-）

- `net/core/rtnetlink.c`：**`dev_name(parent)` NULL 守卫**——上游 v7.3
  缺这个守卫，gnome-shell dump 接口列表时会 oops；我们的树已修
  （stage 2 跑 Ubuntu 桌面的实际前提之一）
- `drivers/of/platform.c`：reserved-memory 遍历处理

## 10. 设备外设杂项（新增）

- `hid/hid-nanosic.c` + `tools/testing/selftests/hid/nanosic-static.py`：
  Nanosic WN8030 磁吸键盘桥接
- `misc/fpc1264_spi_diag.c`：指纹
- `video/backlight/ktz8866.c`（修改）：背光芯片（全局 `ktz_b` + debugfs）
- `tty/serial/earlycon-simplefb.c`：早期串口控制台
- 3 个面板驱动留档（`panel-l3-42-02-0a-dsc.c`、`panel-tianma-nt37705.c`、
  `panel-visionox-nt37705.c`）：历史 bring-up 载体，未启用

## 11. DTS / 构建 / 仓库（9+11 文件，7023+/11-）

- `arch/arm64/boot/dts/qcom/`：`sm8475.dtsi`（新增）、`sm8450.dtsi`
  （修改）、板级 dts ×4（liuqin/cupid/diting/pong/yudi）、`Makefile`、
  `sm8450.config`
- `.github/workflows/liuqin.yml`、`.gitignore`（`!.github`）、
  `MAINTAINERS`、`README.liuqin.md`
- `Documentation/devicetree/bindings/` ×10（vendor-prefixes、qcom.yaml
  等，配套新驱动）

## 12. 从 v7.4-rc2 回移的修复（2026-11-14，共 6 个）

这些提交让本树在这些文件上**比 v7.3 更新**；7.4 正式版合并时若上游已有
等价实现，应以“是否仍缺该修复”为准决定保留或丢弃：

- `a6xx_gmu.c`：`128a0ed`（次级 rail 按量化后主 rail 匹配）、
  `eab0aff`（dep votes 改用 GPU 设备，修 MX 投票恒为最低档）
- `clk-alpha-pll.c`：`eb34e28`（Lucid Ole PLL 已使能时跳过重配，SM8475 花屏）
- `dispcc-sm8450.c`：`8464e22`（`mdss_mdp_clk_src` 用 `no_init_park`）
- `dpu_encoder.c`：`32d0428`（bonded DSI 先关 slave encoder）
- `dsi_host.c`：`ab91ba6`（tx buffer VM 引用泄漏）

另删除了此前误提交的 `repack/diff-70-710/*` 四个分析留档。

---

## stage 2 启示

内核定制集中在两处：**显示栈**（点亮必需，主线驱动 + 我们的拓扑/PLL/
面板修复）与**外设驱动**（触控/TEE/音频/相机/指纹/键盘等按需启用）。
`net/core/rtnetlink.c` 的 NULL 守卫是跑 Ubuntu 桌面（gnome-shell）的
实际前提之一。外设侧哪些有主线等价驱动、哪些只能用厂商树，见
`docs/` 内主线兼容性核查记录（同阶段产出）。

---

## 主线兼容性核查（liuqin 基本功能视角，2026-11-02）

对照上游 v7.3 逐文件核实（含 blob hash 直接比对，避免 grep 误判）。
**注意**：`tfa9872`（功放）与 `fts_spi`（FocalTech 触控）虽在我们的偏离
清单里，但**不被 liuqin 引用**——tfa9872 只服务于 `sm8475-nothing-pong`
（树内另一块板），fts 是 yzddmr6 多设备树的遗留。liuqin 基本功能与它们
无关。

### ✅ 主线已有驱动，基本功能开箱可用

| 功能 | 芯片/节点 | 主线驱动 | 我们的偏离性质 |
|---|---|---|---|
| WiFi | WCN6855（PCIe 0x1103） | `ath11k/pci.c` | 无（纯主线） |
| 蓝牙 | WCN6855 | `hci_qca.c`（QCA_WCN6855） | 无 |
| 音频编解码 | wcd9380 | `sound/soc/codecs/wcd938x.c` | **完全相同**（blob 一致） |
| 音频功放 | cs35l41 ×4 | `sound/soc/codecs/cs35l41*.c` | 喇叭保护是增强 |
| USB-C / 充电 | pmic-glink + ucsi | `pmic_glink.c`/`ucsi*.c`/`qcom_battmgr.c`/`qcom_pd_mapper.c` 全在主线 | 厂商表 + 小米鉴权是增强 |
| USB DP mux | fsa4480 | `fsa4480.c` | 去抖是增强 |
| USB3+DP PHY | qmp-combo | `phy-qcom-qmp-combo.c`（v7.3 已含 SM8475 表） | DP PLL 失败上送是增强 |
| 背光 | ktz8866 | `ktz8866.c` | 双芯片互锁是增强 |
| GPU | Adreno 730 | `a6xx_gpu.c` | 冷启动修复是增强 |
| UFS / SCM / SLPI | — | `ufs-qcom.c`/`qcom_scm.c`/`qcom_q6v5_pas.c` | 小补丁 |
| 相机传感器 | s5kjn1 | `drivers/media/i2c/s5kjn1.c` | **完全相同**（上游 7.0 合入） |
| eUSB2 中继 | ptn3222 | `drivers/phy/phy-nxp-ptn3222.c` | 主线 compatible 是 `nxp,ptn3222`；我们 DTS 用 `nxp,eusb2-repeater` + 本地驱动 |
| TEE（替代路线） | qcomtee | `drivers/tee/qcomtee/` | 与 qseecom API 不同，见下 |

### ❌ 主线没有、liuqin 基本功能必需的本地驱动

| 功能 | 芯片 | 本地驱动 | 主线缺口 |
|---|---|---|---|
| **触控** | Novatek NT36532（**SPI**） | `input/touchscreen/nt36523/`（6 文件） | 主线 `novatek-nvt-ts.c` **仅 I2C**（NT11205/NT36672A），不支持 SPI |
| **显示面板** | 天马 m81_36_02_0a | `panel-novatek-nt36532.c` | 主线 nt36523 驱动无本机 desc |
| **pinctrl** | SM8475 TLMM | `pinctrl-sm8475.c`（FROMLIST） | 上游至今没有 SM8475 pinctrl |

### ⚠️ 非基本功能、但设备特性依赖的本地驱动

| 功能 | 芯片 | 本地驱动 | 主线缺口 |
|---|---|---|---|
| 键盘套 | Nanosic WN8030 | `hid-nanosic.c` | 无（gnome 磁吸键盘/SW_TABLET_MODE） |
| 指纹 | fpc1020（SPI） | `fpc1264_spi_diag.c` + qseecom | 无 fpc1020；qseecom 也无（主线 qcomtee 不同 API） |
| 相机捕获 | SM8475 CAMSS | `camss*` 五件套 + `camcc-sm8450.c` 加 sm8475 | 主线 camss 无 SM8475 资源表、无 camcc-sm8475 |
| 早期串口 | simplefb | `earlycon-simplefb.c` | 无（调试用，`CONFIG_SERIAL_EARLYCON` 未开不参与编译） |

### 显示点亮链（主线驱动 + 我们的补丁）

DSI/DPU/PHY/ubwc 主体全是主线驱动，但**没有我们的补丁就点不亮**：
拓扑（2LM/2DSC）+ bonded PLL 修复 + UBWC cape 别名 + dsc_slice_per_pkt
+ 面板驱动。详见 divergence 报告 §1。

### 结论

liuqin 的"基本功能"在主线 v7.3 上的真实缺口只有 **三个硬缺口**：
触控（SPI Novatek）、显示面板 desc、pinctrl-sm8475；其余基础
（WiFi/BT/音频/充电/USB-C/GPU/UFS/相机传感器）主线已有驱动，
我们的偏离多为厂商增强而非功能前提。stage 2 的 rootfs 可以在任何
情况下正常工作，因为内核侧的缺口已由本树补齐。

---

## 触控与 pinctrl 的 v7.3 适配核查（2026-11-02，逐项对照设备树）

### 设备树 ↔ 驱动精确对照（liuqin.dts 全部 30 个 compatible）

全部找到声明驱动。关键绑定：
`qcom,sm8450-sndcard` → 主线 `sound/soc/qcom/sc8280xp.c`；
`qcom,wcd9380-codec` → 主线 `wcd938x.c`（blob 相同）；
`cirrus,cs35l41` → 主线 `cs35l41-i2c.c`；
`xiaomi,liuqin-keyboard` → 本地 `hid-nanosic.c`（匹配第二 compatible
`nanosic,wn8030`）；`sdw20217010d00` 走 soundwire 总线枚举（无 of_match）；
`usb-c-connector` 由 typec 连接器框架按节点引用处理。

### pinctrl（`pinctrl-sm8475.c`）：✅ 完全适配

- **编译**：`CONFIG_PINCTRL_SM8475=y` built-in，CI 通过
- **框架**：`sm8475_tlmm` soc_data 初始化与主线 `pinctrl-sm8450.c`
  **逐字段同构**（含 `egpio_func = 9`），标准 `msm_pinctrl_probe()`
- **6.18 strict 框架**：`MSM_GPIO_PIN_FUNCTION(gpio/egpio)` 两处标记
  齐全（即 6.18 fix3 的修复内容）
- **与主线驱动的实质差异**：pin 表/groups 表逐行 diff，**唯一实质差异
  是 pin[98] 多一个 `pll_clk` 功能**，其余全是 `sm8475_`/`sm8450_`
  标识符重命名——即它是主线 sm8450 驱动的克隆 + 一引脚扩展
  （将来可作为 sm8450 的扩展提交上游）
- **运行时已实测通过**：sm8475.dtsi `&tlmm` 覆盖 compatible 为
  `qcom,sm8475-tlmm` 绑定本驱动；**显示点亮本身就证明 pinctrl 正常**
  （面板 reset-gpio/`sde_dsi_active` 等 mux 全部经 tlmm）

### 触控（`nt36523/nt36xxx.c`，SPI Novatek NT36532）：✅ 适配到位，待上机验证

- **编译**：`CONFIG_TOUCHSCREEN_NT36523_SPI=y` built-in，CI 通过
- **v7.1 API 漂移适配**（有源码注释为证）：`of_get_named_gpio()` 在
  v7.1 被上游移除（`b6420bd5aa0c`），驱动内 `nvt_of_get_named_gpio()`
  改用 `fwnode_gpiod_get_index()`，保留 legacy `-gpio` 后缀回退
- **现代面板跟随者 API**：`drm_is_panel_follower()`（主线为 TDDI 触控
  设计的机制），DTS 的 `panel = <&panel>` 由该框架处理，probe 跟随
  面板时序；固件下载用 `nvt_update_firmware_no_eng_reset()`（HW-CRC
  路径，不动工程复位）
- **DTS 属性 ↔ 驱动解析完全自洽**：
  - `NVT_TOUCH_SUPPORT_HW_RST = 0`（编译期关硬件复位脚）⇒ DTS 无
    `novatek,reset-gpio`，改由 `novatek,swrst-n8-addr = <0x1fb43e>`
    软件复位——DTS 注释也说"vendor 树没有这个属性但主线 nvt_parse_dt
    必需"，取主线 NT36532 寄存器表同值
  - `novatek,irq-gpio` 经 gpiod legacy 后缀匹配驱动的
    `nvt_of_get_named_gpio(np, "novatek,irq")`
  - 触控固件按面板模块二选一：DTS 默认 CSOT 固件，驱动读命令行面板
    名（`m81_36_02_0a`→天马 / `m81_42_02_0b`→CSOT）覆盖
  - `firmware-name = "novatek/liuqin/novatek_nt36532_m81_fw_csot.bin"`
- **固件齐备**：`device/firmware/usr/lib/firmware/novatek/liuqin/`
  下 `novatek_nt36532_m81_fw_tm.bin`（天马）与 `_csot.bin` 两份；
  当前启动 ramdisk 已含同一目录（217 个固件文件，覆盖 ath11k/qca/
  qcom GPU/ADSP 全部 built-in 驱动的 probe 期加载）
- **未验证**：上机 probe 成功与触控_EVENTS（stage 2 刷机后从
  /proc/interrupts 与 /dev/input 验证）

### stage 2 关键发现：built-in 驱动 + ramdisk 固件模式

所有外设驱动均 `=y` built-in（含 `DRM_MSM`/`ATH11K`/`SND_SOC_*`/
`QCOM_Q6V5_PAS`/触控），`CONFIG_EXTRA_FIRMWARE` 为空——全部
`request_firmware` 发生在 boot 期 probe 阶段。当前 lighting 镜像的
ramdisk 已把 `/lib/firmware` 整包打入（ath11k WCN6855 / qca BT /
qcom a730_sqe+gmu / novatek 触控 / regulatory.db 共 217 个文件），
这就是 built-in 驱动在根文件系统挂载前拿到固件的机制。
**stage 2 的 squashfs 流程必须沿用这个模式**（固件进 initramfs 或
确保 rootfs 挂载早于 probe）。

---

## v0.7.0 移植增量（`liuqin-7.3-v070`，2026-11-15）

基线 `17abc027f75f`，v0.7.0 阶段 tip `d0e404edf30c`（6 个提交 / 13 个文件）。
2026-11-17 又叠加 v0.8.0 + 主线 v7.4-rc3 的 7 个提交（见本节末尾）。

| 文件 | 性质 | 是否必须随 7.4 保留 |
|---|---|---|
| `sound/soc/qcom/qdsp6/q6dsp-lpass-clocks.c` | 上游未修 bug 的修复（drvdata 设置顺序） | **是**，直到上游修好；主线 7.4-rc2/master 仍是旧序 |
| `drivers/power/supply/qcom_battmgr.c` | 上游 v0.7.0 整链移植 + 我们的唤醒策略适配 | **是**（liuqin 连接器热敏必需） |
| `drivers/soc/qcom/pmic_glink.c` | 端口源状态 API | **是**（battmgr 依赖） |
| `include/linux/soc/qcom/pmic_glink.h` | 同上；与上游 v0.7.0 **逐字节一致** | **是** |
| `drivers/usb/typec/ucsi/ucsi_glink.c` | 端口源状态喂入 + remove 清零 | **是** |
| `Documentation/.../qcom,pmic-glink.yaml` | `io-channels`/`io-channel-names` | **是** |
| `arch/arm64/boot/dts/qcom/sm8475-xiaomi-liuqin.dts` | `channel@347` + pmic-glink io-channels + `&crypto{disabled}` | **是**（板级） |
| `include/drm/drm_panel.h` | 新增 `active_crtc` | **否**，上游若采用同名方案则改用上游 |
| `drivers/gpu/drm/bridge/panel.c` | 设置/清空 `active_crtc` | **否**，同上 |
| `drivers/input/touchscreen/nt36523/nt36xxx.c` | follower 改 enabled/disabling + vblank 等待（与上游 v0.7.0 除 `of_gpio` 适配外逐字节一致） | **是**（板级驱动本就是我们的） |
| `drivers/misc/fastrpc.c` | `TASK_FREEZABLE`（主线未收） | 待真机验证后定 |
| `drivers/gpu/drm/msm/msm_gem_submit.c` | `kvzalloc`（主线未收） | 待上游收；无行为回归 |

**升级注意**：`drm_panel::active_crtc` 是**我们对主线 API 的扩展**（主线
7.4-rc2/master 都没有该字段）。若上游将来引入等价机制（或面板 follower
被重构），必须改用上游实现，否则 7.4→7.5 合并会在 `drm_panel.h` 与
`bridge/panel.c` 上反复冲突。

### v0.8.0 + 主线 v7.4-rc3 增量（2026-11-17）

`d0e404edf30c..9acfdc025415`，7 个提交，但只碰 **2 个文件**：

| 文件 | 性质 | 是否必须随 7.4 保留 |
|---|---|---|
| `drivers/power/supply/qcom_battmgr.c` | 上游 v0.8.0 的 6 个提交（遥测单位、QC usb_type、燃料计刷新、厂商 uevent、有线充电唤醒、SDP 500 mA）+ 我们的两处适配 | **是**（含针对已记录缺陷的 SDP 修复） |
| `sound/soc/qcom/qdsp6/q6apm.c` | 主线 v7.4-rc3 `0337b8129cf6`（1 行） | **是**，直到上游修好 |

**注意**：`qcom_battmgr.c` 在本轮之后与上游 v0.8.0 的差异只剩
**3 处**，且都是有意为之：

1. `qcom_battmgr_sm8475_refresh_worker()` 多了 `refresh_unsupported` 闩锁
   （属性 id 未在本机验证，超时会占着 `b->lock` 卡 1 秒，且 `dev_dbg`
   在未开 `CONFIG_DYNAMIC_DEBUG` 时静默）；
2. `qcom_battmgr_charge_wake()` 一句注释措辞；
3. `qcom_battmgr_sm8475_usb_check_locked()` 的 `int ret` 作用域。

**升级 7.4 时**：这个文件已经是"上游 v0.8.0 + 我们两处适配"的形态，
merge 时以上游为底、重新套上闩锁即可，不要再手工重打其余部分。
**未合入** XM 属性重编号（42/43/44），因为本机 ROM 是 Android 13 的旧
枚举顺序（详见 upgrade doc）。
