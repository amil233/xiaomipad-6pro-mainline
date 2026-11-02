# 内核树相对上游 v7.3 的偏离统计（stage 2 基线）

**基准**：上游 tag `v7.3`（`c03c1a14507d`）vs 本仓 `liuqin-7.3` @ `db08160915e3`
（= 点亮 tip）。

**总览**：159 个文件（新增 67 / 修改 92 / 删除 0），+62,913 / −199 行。
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
  `MAINTAINERS`、`README.liuqin.md`、`repack/diff-70-710/` 留档
- `Documentation/devicetree/bindings/` ×10（vendor-prefixes、qcom.yaml
  等，配套新驱动）

---

## stage 2 启示

内核定制集中在两处：**显示栈**（点亮必需，主线驱动 + 我们的拓扑/PLL/
面板修复）与**外设驱动**（触控/TEE/音频/相机/指纹/键盘等按需启用）。
`net/core/rtnetlink.c` 的 NULL 守卫是跑 Ubuntu 桌面（gnome-shell）的
实际前提之一。外设侧哪些有主线等价驱动、哪些只能用厂商树，见
`docs/` 内主线兼容性核查记录（同阶段产出）。
