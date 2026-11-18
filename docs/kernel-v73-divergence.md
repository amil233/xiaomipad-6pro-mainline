# 内核树相对上游 v7.3 的偏离，与 v7.4 升级决策

**基准**：上游 tag `v7.3`（`c03c1a14507d`，由内核仓 `linux` remote 同步）vs 本仓 `liuqin-7.3` @ `c03e1015c71d`
（当前运行内核 `7.3.0-gc03e1015c71d`，`repack/c03e10-boot/` 已上机点亮）。

**总览**：**174 个文件**（新增 63 / 修改 111 / **删除 0**），
+58,425 / −308 行。

来源三分：① yzddmr6 厂商树的板级外设驱动；② 我们的点亮修复与改进；
③ 构建/CI/文档。**无删除文件**——所有偏离都是叠加性质，升级时不存在
"上游删了我们靠它"以外的隐性丢失风险（该风险体现在"上游改 / revert"侧，
逐级记录见 `docs/archive/kernel-version-upgrade-full.md`）。

> 2026-11-15/17 曾有两批从参考项目移植的改动（v0.7.0 的 `liuqin-7.3-v070`
> 与 v0.8.0 整批）。**前者已丢弃、从未并入 `liuqin-7.3`；后者全部回退。**
> 因此本文不再列它们的"增量"——那张表描述的不是这棵树。

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
| `panel-novatek-nt36532.c`（新增） | **当前点亮的面板驱动**（天马 `m81_36_02_0a` desc + cmdline 匹配；DTS compatible `xiaomi,pipa-nt36532`） |
| `soc/qcom/ubwc_config.c` | `qcom,cape` 机器别名（ABL 实传 root compatible 为 cape 系列） |

## 2. 触控（36 文件，36677+/0-）—— 厂商树

- `input/touchscreen/fts_spi/`（30 文件）：FocalTech FTS 触控完整厂商库
- `input/touchscreen/nt36523/`（6 文件）：Novatek 触控（**本机实际在用**）

## 3. TEE/QSEECOM（9 文件，2043+/0-）

- `tee/qseecom/core.c` + `include/linux/tee_core.h` + `uapi/linux/tee.h`
  + `Documentation/tee/` + `tee/Kconfig`/`Makefile`：QSEE 代理，
  指纹/DRM 等 TA 依赖。

## 4. 音频（13 文件，711+/16-）

- `sound/soc/codecs/cs35l41.c`/`.h` + `wm_adsp.c`/`.h`
  + `firmware/cirrus/cs_dsp.c`：喇叭保护 DSP（cs35l41 主体是上游驱动）
- `sound/soc/qcom/qdsp6/`（audioreach.c/.h、q6apm.c、q6apm-dai.c、
  topology.c）+ `sound/soc/qcom/common.c`：TDM 支持
- **外放 TDM 链路**：`sc8280xp.c` 的板级策略在 `17abc027f75f` 收敛为
  **v7.4 的 per-DAI 形式**（对齐上游 `ea6e98472c65`）：`struct
  sc8280xp_dai_data` + `SC8280XP_DAI_DATA()`，liuqin 的
  `TERTIARY_TDM_RX_0` 一条配置表达 DSP_A、逐 codec slot 与 component
  sysclk；`cs35l41.c` 的 `.set_tdm_slot` 保留。
  **7.4 合并注意**：上游 per-DAI 结构会与我们的三个扩展字段相邻，别丢
  `codec_dai_fmt`/`codec_tdm_slot_each`/`codec_component_sysclk`。
  细节与复测见 `AUDIO.zh-CN.md`。

## 5. 相机（6 文件，447+/64-）

- `media/platform/qcom/camss/` 五件套：SM8475 资源表 + regulators
  结构适配；`clk/qcom/camcc-sm8450.c`：相机时钟。

## 6. PHY / USB / UFS（12 文件，592+/34-）

- `phy/qualcomm/phy-qcom-qmp-combo.c`、`phy-qcom-qmp-common.h`、
  `phy-qcom-qmp-pcie.c`：厂商移植表残留 + DP PLL 失败上送
- `phy/qualcomm/phy-qcom-i2c-eusb2-repeater.c`（新增）：eUSB2 中继
- `usb/dwc3/drd.c`、`usb/typec/ucsi/ucsi.c`/`ucsi_glink.c`、
  `usb/typec/mux/fsa4480.c`：USB-C role switch + CCI 去抖
- `ufs/host/ufs-qcom.c`/`.h`：UNIPRO 850 MHz 时钟修复

## 7. pinctrl（3 文件，1715+/0-）

- `pinctrl/qcom/pinctrl-sm8475.c`（新增，FROMLIST）：**上游至今没有
  SM8475 pinctrl**，且含 `MSM_GPIO_PIN_FUNCTION` 修复（6.18 点亮修复）。
  与主线 `pinctrl-sm8450.c` 逐行 diff 后唯一实质差异是 pin[98] 多一个
  `pll_clk` 功能，其余全是标识符重命名 ⇒ **可作为 sm8450 的扩展提交上游化**。

## 8. SoC / 固件 / 电源

- `firmware/qcom/qcom_scm.c` + 头文件：TEE 初始化 + allowlist
- `soc/qcom/mdt_loader.c`/头文件：split-image loader（qseecom 用）
- `soc/qcom/pmic_glink.c`、`qcom_pd_mapper.c`、`pdr_internal.h`：
  PD mapper 厂商定义
- `power/supply/qcom_battmgr.c`：小米鉴权协议（v7.3 上 +978/−4 行的既有实现，
  **不是** v0.8.0 移植的产物）
- `remoteproc/qcom_q6v5_pas.c`：SLPI
- `power/reset/msm-poweroff.c`、`qcom-pon.c`：reboot reason 寄存器
- `cpufreq/cpufreq-dt-platdev.c`：SM8475 白名单（1 行）

## 9. 比上游更新的正向修复（2 文件，34+/5-）

- `net/core/rtnetlink.c`：**`dev_name(parent)` NULL 守卫**——上游 v7.3
  缺这个守卫，gnome-shell dump 接口列表时会 oops；我们的树已修
  （跑 Ubuntu 桌面的实际前提之一）
- `drivers/of/platform.c`：reserved-memory 遍历处理

## 10. 设备外设杂项（新增）

- `hid/hid-nanosic.c` + selftest：Nanosic WN8030 磁吸键盘桥接
- `misc/fpc1264_spi_diag.c`：指纹
- `video/backlight/ktz8866.c`：背光芯片（全局 `ktz_b` + debugfs）
- `tty/serial/earlycon-simplefb.c`：早期串口控制台（调试用，
  未开 `CONFIG_SERIAL_EARLYCON_SIMPLEFB` 时不参与编译）
- 3 个面板驱动留档（`panel-l3-42-02-0a-dsc.c`、`panel-tianma-nt37705.c`、
  `panel-visionox-nt37705.c`）：历史 bring-up 载体，未启用

## 11. DTS / 构建 / 仓库（9+11 文件，7023+/11-）

- `arch/arm64/boot/dts/qcom/`：`sm8475.dtsi`（新增）、`sm8450.dtsi`
  （修改）、板级 dts ×5（liuqin/cupid/diting/pong/yudi）、`Makefile`、
  `sm8450.config`
- `.github/workflows/liuqin.yml`、`.gitignore`（`!.github`）、
  `MAINTAINERS`、`README.liuqin.md`
- `Documentation/devicetree/bindings/` ×10（配套新驱动）

## 12. 从 v7.4-rc2 回移的修复（2026-11-14，共 6 个）

这些提交让本树在这些文件上**比 v7.3 更新**；7.4 正式版合并时若上游已有
等价实现，应以"是否仍缺该修复"为准决定保留或丢弃：

- `a6xx_gmu.c`：`128a0ed`（次级 rail 按量化后主 rail 匹配）、
  `eab0aff`（dep votes 改用 GPU 设备，修 MX 投票恒为最低档）
- `clk-alpha-pll.c`：`eb34e28`（Lucid Ole PLL 已使能时跳过重配，SM8475 花屏）
- `dispcc-sm8450.c`：`8464e22`（`mdss_mdp_clk_src` 用 `no_init_park`）
- `dpu_encoder.c`：`32d0428`（bonded DSI 先关 slave encoder）
- `dsi_host.c`：`ab91ba6`（tx buffer VM 引用泄漏）

## 13. 主线兼容性核查（liuqin 基本功能视角）

逐文件核实，含 blob hash 直接比对（避免 grep 误判）。
`tfa9872`（功放）与 `fts_spi`（FocalTech 触控）虽在偏离清单里，但
**不被 liuqin 引用**——tfa9872 只服务 `sm8475-nothing-pong`，fts 是多设备树遗留。

### 主线已有、基本功能开箱可用

| 功能 | 芯片/节点 | 主线驱动 | 偏离性质 |
|---|---|---|---|
| WiFi | WCN6855（PCIe 0x1103） | `ath11k/pci.c` | 无（纯主线） |
| 蓝牙 | WCN6855 | `hci_qca.c` | 无 |
| 音频编解码 | wcd9380 | `wcd938x.c` | **完全相同**（blob 一致） |
| 音频功放 | cs35l41 ×4 | `cs35l41*.c` | 喇叭保护是增强 |
| USB-C / 充电 | pmic-glink + ucsi | `pmic_glink.c`/`ucsi*.c`/`qcom_battmgr.c` | 厂商表 + 小米鉴权是增强 |
| USB DP mux | fsa4480 | `fsa4480.c` | 去抖是增强 |
| USB3+DP PHY | qmp-combo | `phy-qcom-qmp-combo.c`（v7.3 已含 SM8475 表） | DP PLL 失败上送是增强 |
| 背光 | ktz8866 | `ktz8866.c` | 双芯片互锁是增强 |
| GPU | Adreno 730 | `a6xx_gpu.c` | 冷启动修复是增强 |
| UFS / SCM / SLPI | — | `ufs-qcom.c`/`qcom_scm.c`/`qcom_q6v5_pas.c` | 小补丁 |
| 相机传感器 | s5kjn1 | `drivers/media/i2c/s5kjn1.c` | **完全相同** |
| eUSB2 中继 | ptn3222 | `phy-nxp-ptn3222.c` | 主线 compatible 是 `nxp,ptn3222`；我们 DTS 用 `nxp,eusb2-repeater` + 本地驱动 |

### 主线没有、且是基本功能必需的三个硬缺口

| 功能 | 芯片 | 本地驱动 | 主线缺口 |
|---|---|---|---|
| **触控** | Novatek NT36523（SPI） | `input/touchscreen/nt36523/` | 主线 `novatek-nvt-ts.c` **仅 I2C**，不支持 SPI |
| **显示面板** | 天马 `m81_36_02_0a` | `panel-novatek-nt36532.c` | 主线 nt36523 驱动无本机 desc |
| **pinctrl** | SM8475 TLMM | `pinctrl-sm8475.c` | 上游至今没有 SM8475 pinctrl |

其余外设（指纹、相机捕获、键盘套、早期控制台）是**设备特性**而非基本功能，
逐一见 §3/§5/§10。显示链主体全是主线驱动，但没有我们的拓扑/PLL/ubwc/
`dsc_slice_per_pkt`/面板 desc 补丁就点不亮。

---

# v7.4 升级：必须保留的偏离与已实测的决策

## 升级纪律

- 新分支从**已点亮**的上一级直分，merge 主线新 tag，解冲突，推 CI，
  刷机验证；**点亮才进下一级**。
- `v7.4-rc1..rc3` 对 sm8450/sm8475、msm、clk、qcom DTS 只有 2 个
  **treewide 机械化提交**（`devm_kmalloc()` → `devm_kmalloc_obj()` 系列），
  没有针对象的语义改动；不必为 rc 单独准备，等正式版。
- 上游新进入的 revert 必须扫：
  `git log v7.(N-1)..v7.N --grep '^Revert ' -- drivers/gpu/drm/msm/`。

## 结构性决策（7.4 升级前必须定）

1. **面板驱动撞名**：v7.4 新增 `panel-novatek-nt36532.c`
   （CSOT PPC100HB1，OnePlus Pad 2），与我们的同名、同 Kconfig 符号 ⇒
   **add/add 冲突 + 符号冲突**。决定：merge 时**以主线文件为底重加**
   pipa/Tianma desc，不现在改名（改名会动 `CONFIG_DRM_PANEL_NOVATEK_NT36532`
   与集成仓的 config 锁）。
2. **QSEECOM 分叉**：主线走 `qcomtee`（对象模型 + TEE ioctl），我们是
   vendor `/dev/qseecom` + `qcom_scm`（指纹/keymaster blob 需要）。
   不是重复代码而是 ABI 分叉，短期保留。
3. **音频 TDM**：已提前改成 v7.4 的 per-DAI 形式（见 §4）。
4. **GPU 依赖投票**：上游 7.4 正在重做（secondary rail、dep 设备、clamp、
   BX rail）。我们的 `qcom,opp-cx-level` 走 v1 perf-table 的 `acd` 字，
   是并行方案；合并时要决定并入上游 dep-vote 模型还是保留 DT 属性。
5. **DP/DSI**：主线 7.4 对 DP 做 stream-aware 大改（stream_id、p1/p2/p3），
   PHY-before-AUX 补丁届时需重写；DSI bonded PLL 修复上游仍未恢复，
   我们的重贴依旧需要，建议改成"仅 shared PLL/bonded 生效"以便未来上游化。

## 实测冲突清单（13 个文件）

`a6xx_gmu.c`、`panel/Kconfig`、`panel-novatek-nt36532.c`(add/add)、
`misc/Kconfig`、`phy-qcom-qmp-combo.c`、`phy-qcom-qmp-pcie.c`、
`qcom-pon.c`、`qcom_q6v5_pas.c`、`ucsi.c`、`ktz8866.c`、`cs35l41.c`、
`q6apm.c`、`sc8280xp.c`。

其余 77 个被上游动过的文件自动合并，但按既往教训仍需人工复查
（机器匹配表条目、被上游重构的结构体旧表、revert 扫描）。

## 面板驱动与 v7.4 主线的差距

| 项目 | 主线 v7.4 驱动 | 我们的驱动 |
|---|---|---|
| 面板 | CSOT PPC100HB1 一块 | pipa CSOT、pipa Tianma、yudi |
| 面板选择 | 每 compatible 一块 | same compatible + cmdline 模块名 |
| 供电 | 仅 `vddio` | `vddio`/`dvddbuck`/`dvddldo` |
| 复位 | 固定 10/5/15 ms | 每面板一个 reset 回调（CSOT 12/12/12/12，Tianma 10/3/3/15） |
| DSC | v1.2，750x20，flag `ALL_SLICES_IN_PKT` | v1.1，450x20，`dsc_slice_per_pkt = 2` |
| 模式 | 3000x2120@120 | 1800x2880@120（+60/120 覆盖、burst 开关） |
| 其他 | `devm_drm_panel_add`、DSC helper | 额外 diag debugfs、`desc_sel` 模块参数 |

天马部分本身只占：init 序列 302 行（214 条 DCS）、desc 约 25 行、reset 13 行。
并入主线驱动的**新增工作量约 380–420 行**，另需四处基础设施扩展
（每面板供电表、reset 回调、`dsc_slice_per_pkt`、面板选择方式）。
预计 1 天代码 + 2–4 次上机迭代。结论：可行，是长期正确形态。

## 建议顺序

- **P0**：等 7.4 正式版；合并前把 13 个冲突逐个定调（上面 §结构性决策）。
- **P1**：面板驱动并入主线骨架、a6xx CX 模型对齐、PHY-before-AUX 条件化。
- **P2（长期上游化）**：QSEECOM 接口设计、camss SM8475、
  pinctrl-sm8475（`MSM_GPIO_PIN_FUNCTION`）。

---

## 14. 参考项目 commit 级筛选（2026-11-18）

目的：模仿"看主线、也看参考项目，只取与内核版本/ROM 无关的通用修复"的流程，
不按分支合并、不按版本号跟进。

**范围**：`liuqin-6.17test/liuqin-6.17` tip `ed0dad5d20d0`（v0.8.0），
相对共同 6.17 基点 `c64b7fc85a8b` 的 **67 个非 merge 提交**。

**筛法**：对每个提交 `git show | git apply --check [-R]`，再人工看代码：

| 结果 | 数量 | 含义 |
|---|---:|---|
| reverse 可应用 | 17 | 7.3 树里已有等价实现（含已移植的 24 个中的一部分） |
| forward 干净应用 | 2 | 代码上下文兼容，可直接取 |
| 冲突/需重写 | 48 | 6.17 上下文或设备/ROM 专属，逐个判断 |

**本轮进 `liuqin-7.3-backports`（不在 `liuqin-7.3`）**：

1. `44be305f0718` `media: iris: Fix power-off ordering to disable power domain
   after clocks` —— 直接来自**主线** `9cfae7726a9a`（已在 `v7.4-rc3`），
   7.3 树上干净应用；关电顺序错误，通用媒体修复。
2. `9a81b1a45c66` `drm/msm: fall back to vmalloc for large msm_gem_submits` ——
   参考项目 `03b536ad4e2c`（Sam Day），未进 `v7.4-rc3`；按 7.3 的
   `size_add()/array_size()` 重写，保留 `KMALLOC_MAX_SIZE` 上限，
   所有释放路径改 `kvfree()`。

**未取的代表性提交及理由**：

- `qcom_battmgr` 的 QC/DCP、500 mA、电量计单位、NTC、s2idle 唤醒等
  （约 20 个）：绑定 OS2 充电语义/本机固件值，属"参考项目的数字"，
  继续按 `STATUS` §6 #8/#9 的纪律单独取证。
- 连接器温度整链、面板 follower 改 `enabled`：v0.7.0 积压，已随
  `liuqin-7.3-v070` 丢弃；`STATUS` #2 撤销后没有对应症状。
- `misc: fastrpc: freeze userspace invocation waiters`：通用但需要真实
  传感器守护进程做 suspend/resume 验证，先留在候选池。
- `drm/msm: let legacy GEM close exit after terminal GPU failure`：虽可
  干净应用，但引用了 7.3 树里不存在的 `priv->gpu->wedged`，直接取会编译
  失败，需先补 GPU 挂死状态模型。
- `phy: qcom: qmp-combo`、`serial: qcom-geni`、`soc: qcom: rpmh-rsc`：
  对应修复 7.3 树里已经存在（reverse 检查确认），不再重复。
- 相机 cleanups（缩进/注释/DTS tidy）：设备专属且纯整理，收益低于风险，
  不进本轮。

**验证边界**：本机禁止编译，只做了 `git apply --check`、`git diff --check`、
`scripts/checkpatch.pl --strict`（0 errors / 0 warnings）与符号存在性检查。
两个提交都要经过 CI 编译 + 真机冷启动才可进 `liuqin-7.3`。
