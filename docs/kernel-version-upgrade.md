# 内核版本逐级升级计划与冲突解决记录

任务模型：`liuqin-6.17-tianma`（基于主线 **v6.17-rc1-211-g90d970cade8e**，能点亮天马面板）
是起点。逐级合并主线稳定版（v6.17 → v6.18 → v6.19 → …），每级：

1. agent 本地合并并解冲突；
2. 用户 `git -C linux-sm8450-liuqin push GitHub <branch>` 触发 CI；
3. 用户取 CI artifact 装配 boot 镜像刷机，验证是否仍点亮；
4. 点亮则进入下一级，不亮则定位回退。

绝对禁止本地编译（AGENTS.md §0.1），正确性一律由 CI 判定。

## 1. 各级分支命名

谱系链条（每个新分支都直接长在**已点亮**的上一级之上）：

```
liuqin-6.17            c64b7fc85a8b  上游作者 yzddmr6 的分支（只读参照，勿改）
  └─ liuqin-6.17-tianma  c7e51cdf3290  上一级 + 本机天马面板文件（点亮，6.17-rc1 内核）
     └─ liuqin-6.17-stable  8ca4a94d4b52  上一级升级到 6.17 正式版（✅ 点亮）
        └─ liuqin-6.18  47048e710209  上一级升级到 6.18（CI ✓，镜像已装配，待刷机）
```

| 分支 | 直接父分支 | 合并的目标 tag | 状态 |
|---|---|---|---|
| `liuqin-6.17` | —（上游 yzddmr6） | — | 只读参照，勿改 |
| `liuqin-6.17-tianma` | `liuqin-6.17` | —（+ 天马面板文件） | ✅ 点亮（6.17-rc1，`c7e51cdf3290`） |
| `liuqin-6.17-stable` | `liuqin-6.17-tianma` | `v6.17`（`e5f0a698b34e`） | ✅ 点亮（`fc2fb59ef397`，2026-10-30 上机） |
| `liuqin-6.18` | `liuqin-6.17-stable` | `v6.18`（`f7b88edb52c8`） | ✓ CI 通过（run `41065191567`，tip `47048e710209`），镜像 `repack/618-boot/` **刷机黑屏**（回归定位见 §5，实验分支 `liuqin-6.18-fix1`） |
| `liuqin-6.18-fix1` | `liuqin-6.18` | —（回退 2 个上游提交） | 回归实验分支，待推送 CI |
| `liuqin-6.19` | —（废路线，**不在链上**） | `v6.19-rc6` | CI 两次失败，弃 |

workflow 触发分支列表在
`linux-sm8450-liuqin/.github/workflows/liuqin.yml`（`on.push.branches`），
每新增一级分支要追加进去，否则 push 不触发 CI。

## 2. 为什么不直接上 6.19（已验证失败）

`liuqin-6.19`（合并 `v6.19-rc6`）用户已推送，CI 两次失败：

- run `40984167517`（DTC）：`sm8475-xiaomi-liuqin.dts:1816 Label or path
  usb_1_dwc3 not found` —— v6.19 把 dwc3 合进了 `usb_1` 外壳。已由提交
  `e77eae91afa2`（把 `&usb_1_dwc3` 块并入 `&usb_1`）修复，并做过离线
  label 引用闭包检查，无其它陈旧 label。
- run `40999521479`（编译，7 处错误）：
  1. `sound/soc/codecs/cs35l41.c:333: implicit declaration of
     'snd_soc_kcontrol_component'` —— 该 helper 在 v6.19 被移除（v6.18
     仍在），liuqin 本地的 `cs35l41_calibrated_get()` 会断编译。
  2. `drivers/gpu/drm/msm/disp/dpu1/catalog/dpu_12_2_glymur.h:
     'CTL_6'/'CTL_7'/'DSPP_4'..'DSPP_7' undeclared` —— v6.19 新增 glymur
     catalog 引用了 6.17 侧 `dpu_hw_mdss.h` 里不存在的枚举（上游已加到
     CTL_7/DSPP_7），同时 `STAGES_PER_PLANE` 本地=2 / 上游=1 语义冲突。

这三处问题里，**cs35l41 helper 移除**和 **glymur catalog 枚举缺失**在 v6.18
确实不存在（实证：`snd_soc_kcontrol_component` 仍在 v6.18 的
`include/sound/soc.h`；v6.18 无 `dpu_12_2_glymur.h`）。但 **dwc3 合并在
v6.18 同样发生**——早先"v6.18 未合并 dwc3"的判断是错的：CI run
`41031588689`（merge `25cca3bba20a`）在 DTC 阶段（8m34s）以同一个
`Label or path usb_1_dwc3 not found` 失败。已由 `6ba4e603cf21` 按
`e77eae91afa2` 同款修法修复（dwc3 属性并入 `&usb_1`，base dtsi 已自带
`usb-role-switch`/`phys`/`phy-names`），并跑过 label 引用闭包离线校验
（预处理后 399 个 `&label` 引用全部可解析）。教训：**上游 API/结构变动
不能凭印象判断，要用 `git grep <tag>` 实证**。

## 3. v6.18 试验合并的冲突分析（已落盘：`25cca3bba20a` + 4 个 CI 修复）

`git merge v6.18`（FETCH_HEAD = `f7b88edb52c8dd01b7e576390d658ae6eef0e134`）
在 `liuqin-6.17-tianma` 上做试验合并：**14 个冲突文件 / 21 个 hunk**，
**面板驱动、DSI、显示控制器、板级 DTS 全部零冲突** —— 这是选 6.18 的核
心理由；显示通路唯一的冲突是 `dpu_plane.c`（本地四管线改动）。

冲突解决策略（逐级沿用）：

- 本地功能**保我们的**（ours）：四管线 dpu_plane、qseecom 驱动、
  CS35L41 四喇叭音频、TDM/AUDIO_IF token、SM8450 iris/camss 板级表。
- 纯相邻新增**取并集**（两边都留）。
- 上游的**错误传播修正采纳他们的**（本地吞错误处改用上游的
  `return ret;`）。
- 上游重命名（`validate_sspp`→`sspp`、qseecom→qcomtee 等）不能打断本地
  调用点。

14 个冲突文件与决定：

| 文件 | 决定 |
|---|---|
| `drivers/gpu/drm/msm/disp/dpu1/dpu_plane.c` | 四处 hunk：保 ours 的四管线 `dpu_plane_is_multirect_capable(sspp, pipe_cfg, fmt, validate_sspp)` 四参签名与 `int ret, i` 声明；`dpu_assign_plane_resources` 里采用 theirs 的 `return ret;`（ours 吞错误） |
| `Documentation/tee/index.rst` | 并集（qseecom + qtee 两章） |
| `drivers/tee/Kconfig` | 并集（两条 source 行） |
| `drivers/tee/Makefile` | 并集（两条 obj 行） |
| `include/uapi/linux/tee.h` | 并集：`TEE_IMPL_ID_QTEE 4` + `TEE_IMPL_ID_QSEECOM 5` |
| `Documentation/tee/qseecom.rst` | 顺带修一处过期注释 |
| `include/uapi/sound/snd_ar_tokens.h` | 并集：本地 TDM/AUDIO_IF token 262–276 + 上游 `SND_SOC_AR_TPLG_MODULE_CFG_TYPE` / `struct audioreach_module_priv_data` |
| `sound/soc/qcom/qdsp6/audioreach.h` | 并集：ours `MODULE_ID_TDM_SINK 0x0700100E`、`MODULE_ID_AUDIO_IF_SINK/SOURCE 0x0700117C/0x0700117D`；theirs SAL `0x07001010`、MFC `0x07001015`、OPUS_DEC `0x07001174` |
| `sound/soc/qcom/sc8280xp.c` | 保 ours 的 `#include <sound/cs35l41.h>`（本地四喇叭 CS35L41 时钟设置用到） |
| `sound/soc/codecs/Makefile` | 并集：tfa9872 + tas2783-sdw |
| `drivers/media/platform/qcom/iris/iris_hfi_gen2_command.c` | 保 ours 一行式 `return iris_hfi_gen2_session_resume(inst, plane, HFI_CMD_DRAIN);`（helper 在 988 行，签名 `(inst, plane, reason)`，v6.18 里仍在） |
| `drivers/media/platform/qcom/iris/iris_platform_gen2.c` | 保 ours 的 `struct iris_platform_data sm8450_data`（整段），同时保留 theirs 新增的 `sm8550_enc_op_int_buf_tbl` 等（并集，注意 `};` 收尾归属） |
| `drivers/media/platform/qcom/camss/camss-csiphy-3ph-1-0.c` | 保 ours 的 `lane_regs_sm8450[]`（GEN2 2.1.3 2PH DPHY，SM8450/SM8475 Cape downstream），对照 theirs 决定是否并集 |
| `drivers/power/supply/qcom_battmgr.c` | 2 个 hunk，待解 |
| `drivers/soc/qcom/ubwc_config.c` | 1 个 hunk，待解 |

> 以上是 6.17-rc 基线上的**分析结论**。实际在 `liuqin-6.17-stable`
> （已含 v6.17 final）之上重做合并时：冲突文件 **13 个**（`ubwc_config.c`、
> `Documentation/tee/qseecom.rst` 已被第一级合并消化），逐文件解决同上表，
> 两处与表不同：`qcom_battmgr.c` 的枚举不能直接并集（ours 的
> `QCOM_BATTMGR_SM8350` 与 theirs 重复）⇒ 恢复 theirs 全集后把
> `QCOM_BATTMGR_SM8475` 插在 `SM8350` 之后；NOTIF 只留 ours 独有的
> `NOTIF_XM_PROPERTY 0x50`（`NOTIF_BAT_INFO` 重复，删）。
> `iris_platform_gen2.c` 的并集注意：theirs 的 `sm8550_enc_op_int_buf_tbl`
> 数组要自带 `};`（共享的 `};` 留给 ours 的 `sm8450_data`）。
> 已执行：merge commit `25cca3bba20a`（基座含 `8ca4a94d4b52`，推这一个
> 分支即同时带上 .gitignore 修复）。
> **两次 CI 失败与修复**（均因照抄 theirs 侧，已记为教训）：
> 1. run `41031588689`（8m，DTC）：v6.18 同样合并了 dwc3 → 修 `6ba4e603cf21`。
> 2. run `41045897486`（30m，编译）：`dpu_plane.c:1383 assignment to expression
>    with array type` —— 冲突 hunk3 里 theirs 的 `prev_adjacent_plane_state =
>    plane_state;` 照抄，但本树该变量是 `struct drm_plane_state
>    *[STAGES_PER_PLANE]` 数组，写回已在被调函数 `dpu_plane_virtual_assign_resources`
>    内按下标完成 → 修 `636b65781fcd`（只留 `return ret;` 错误传播）。
> 3. run `41059030062`（28m，编译，首次 ubuntu-24.04-arm 原生构建）：`iris_platform_gen2.c`
>    里 ours 的 `sm8450_data` 仍用旧字段名——v6.18 把
>    `inst_fw_caps`→`inst_fw_caps_dec/_enc`、`input_config_params_*`→
>    `dec_input_config_params_*`、`output_config_params`→`dec_output_config_params`
>    （decode/encode 拆分）→ 修 `47048e710209`（映射到新字段；SM8450 只有解码，
>    只设 `_dec` 变体；51 个字段已用脚本对合并后 struct 逐一核对）。
> **教训**：冲突解决不能照抄任一侧代码，必须先核对合并后本树的声明类型
> 与数据结构（数组 vs 标量、参数个数、ID 是否重复、**结构体成员是否改名**）。
> 此类错误的完整检测只能靠编译；每轮 CI 约暴露一个，修一个推一次。

## 4. v6.17 final 合并记录（第一级，已完成）

- 基线：`liuqin-6.17-tianma` @ `c7e51cdf3290`（merge-base 与 v6.17 为
  `90d970cade8e` = `v6.17-rc1-211`，距 final 1834 个提交）。
- 结果：**只有 2 个冲突文件**（对比 v6.18 的 14 个），**面板驱动、DSI、
  DSI PHY、DPU catalog、板级 DTS 全部零冲突**；`dpu_crtc.c`、
  `dpu_encoder.c`、`msm_gpu.c` 自动合并成功。
- 冲突解决：
  - `drivers/gpu/drm/msm/disp/dpu1/dpu_plane.c`
    （`dpu_plane_virtual_atomic_check` 声明区）：保 ours 的 `int ret, i`
    （`i` 被 `for (i = 0; i < PIPES_PER_PLANE; i++) pstate->pipe[i].sspp = NULL;`
    用到），采用 theirs 的 `crtc_state = NULL` 初始化。
  - `drivers/soc/qcom/ubwc_config.c`（兼容表）：保 ours 的 `qcom,cape`
    条目，其余全取 theirs（上游 `197713d0cf01` 加 msm8226/msm8916、
    `5cfd298cc035` 把 msm8917 改 `no_ubwc_data`）。liuqin 走
    `qcom,sm8475` 匹配，本来就用不到 cape 行。
- 提交：`fc2fb59ef397`（merge `c7e51cdf3290` + `e5f0a698b34e`），
  同一提交把 `liuqin-6.17-stable` 加进了 workflow 触发分支列表。
- 点亮关键未受影响：板级 DTS 的 `&mdss_dp0 { status = "disabled"; }`
  原样保留（v6.17 final 未触碰该文件）。
- **CI**：run `41016697809` ✓ build in 55m8s；artifact
  `ci/liuqin-kernel-fc2fb59ef397…/` 已核对（`build-info.json.commit` 一致、
  `sha256sum -c` 全过，`kernel.release = 6.17.0-gfc2fb59ef397`）。
- **镜像**：`repack/617s-boot/boot-liuqin-firstboot.img`，58,695,680 字节，
  sha256 `d524db1cb8d90eeac301c16080a409cfad2f905f8a94b2f0562b8b86f2fdcd84`；
  装配管线与输入（cmdline、ABL overlay、ramdisk）与点亮版完全相同，
  只换 Image/DTB。**待刷机验证**。
- 附：另有一个本地提交 `8ca4a94d4b52`（.gitignore 取消忽略 `.github`，
  见 AGENTS.md §5.2）未推送——对构建无影响，且 workflow 有
  `cancel-in-progress: true`，故等本次 CI 落定后再随下一轮推上去。

**结果（2026-10-30）：6.17 final 刷机点亮** ✅ ——逐级升级第一级成功，
显示通路零回归。镜像 `repack/617s-boot/` 已记入 checklist §11 镜像表。

**第二级已落盘**：在 `liuqin-6.17-stable` 之上合并 v6.18，merge commit
`25cca3bba20a` + 4 个修复（`6ba4e603cf21` dwc3、`636b65781fcd` dpu_plane、
`f637e004a84c` camss、`47048e710209` iris，详见 §3 的执行记录）。
**CI 通过**：run `41065191567` ✓ 30m40s（首次 `ubuntu-24.04-arm` 原生
构建），artifact `ci/liuqin-kernel-47048e71…/` 已核对（`kernel.release =
6.18.0-g47048e710209`）。
**镜像**：`repack/618-boot/boot-liuqin-firstboot.img`，58,855,424 字节，
sha256 `2a2f8101…e3052`，同一装配管线。**待刷机验证**：
`fastboot boot repack/618-boot/boot-liuqin-firstboot.img`。

## 5. v6.18 刷机黑屏：回归定位与修复实验（2026-10-31）

6.18 镜像（装配管线/输入与点亮的 617s 完全相同）**黑屏，未点亮**。
对 `fc2fb59ef397..47048e710209`（6.17-stable → 6.18）的显示通路做了
文件级全量 diff，结论如下。

**DSI 控制器（dsi_host.c / dsi_manager.c / dsi_ctrl*）、DPU encoder、
DSC、INTF 驱动零改动**；板级 DTS 与 `sm8450.dtsi` 的 mdss/dsi 节点也
零改动（唯一 DT 变化是 `mdss_dp0` 新增 `stream_1_pixel` 时钟，该节点被
本机禁用，无影响）。

显示通路相关 delta：

| 文件 | 变动 | 风险评估 |
|---|---|---|
| `disp/dpu1/dpu_crtc.c` | **新增** `dpu_crtc_mode_valid` 核心时钟上限过滤（`62b7d6835288` + 修 `f5d079564c44`） | **头号嫌疑**（计算见下） |
| `dsi/phy/dsi_phy_7nm.c` | 6 个上游提交重构 PLL bias 序列：`5ddcb0cb9d10`（初始 VCO 速率）、`3bb6433ecb65`（位域宏）、`b63f008f395c`（vco_prepare 里写 `RBUF_CTRL=1`，含 slave）、`cb55f39bf7b1`（PLL bias 引用计数）、`93c97bc8d85d`（修 bonded DSI，已带入）、`6e5173e7bf80`（`round_rate`→`determine_rate`） | 二号嫌疑（本机正是 bonded 双 DSI；但 bonded 回归在同一窗口内已修） |
| `disp/dpu1/dpu_core_perf.c/.h` | 上面那条的重构载体 | 随头号嫌疑一起回退 |
| `disp/dpu1/dpu_rm.c` | SSPP 偏好顺序微调（`!reqs->scale`→`!reqs->yuv`） | 无影响（本机 RGB 无缩放，走 DMA 分支，与 6.17 相同） |
| `disp/dpu1/dpu_hw_catalog.c` | VIG sblk 格式表 YUV→RGB、LM sblk 去掉 `maxwidth` 字段 | 无影响 |
| `msm_kms.c` / `dpu_kms.c` | IOMMU：**删掉**"无 IOMMU 退回物理连续扫描"兜底 | **排除**：本机 mdss 节点带 `iommus = <&apps_smmu 0x2800 0x402>`，新旧代码都走 mdss 侧映射 |
| `msm_mdss.c` | irq domain 用 `dev_fwnode()` | 等价改写 |
| `pinctrl-msm.c` | pinmux 通用化 + `PIN_CONFIG_OUTPUT`→`LEVEL` 改名 | 无影响（面板复位走 gpiod） |
| `drm_mipi_dsi.c` / `drm_panel.c` / `drm_atomic_helper.c` | 均为**新增** API 与 bridge 引用计数补正 | 无影响 |

### 头号嫌疑的计算

`pipa_mode_120.clock = (1800+200+4+92)*(2880+26+2+214)*120/1000 = 785 245 kHz`。
新检查（`dpu_crtc_mode_valid`，挂在 `drm_atomic_helper_check_modeset`）：

```
adjusted = 785245 * 105/100 / 2   /* clk_inefficiency_factor=105, has_3d_merge=true */
         = 412 253 kHz  →  412 253 000 Hz
通过条件:  max_core_clk_rate ≥ 412 253 000
```

而 `max_core_clk_rate = clk_get_rate(DISP_CC_MDSS_MDP_CLK)`（DPU 探测时的
**运行期读数**；读不到才取默认 `DPU_PERF_DEFAULT_MAX_CORE_CLK_RATE =
412 500 000`）。**余量只有 247 kHz = 0.06%**：只要 MDP 核心时钟在探测时
低于 412.253 MHz（例如挂在 dispcc_pll0 的常见 358.4 MHz、或 ABL 留下的
任何较低档位），面板唯一的 120 Hz 模式就会以 `MODE_CLOCK_HIGH` 被拒，
atomic check 直接失败 → 整条显示管线不 enable → 黑屏（串口无其它报错）。
6.17 里同一运行期值只被 DVFS 夹取（`min(demand, max)`），不构成硬性过滤，
所以 6.17 亮。

该检查本意是给 QCS615 这类低核心时钟上限的芯片筛模式；对 DSC 大分辨率
模式与 6.17 行为不兼容。

### 修复实验：分支 `liuqin-6.18-fix1`

在 `47048e710209`（`liuqin-6.18` tip）之上回退上面两个提交
（`246be824d623`、`09d6fe6e5757`），并已把 `liuqin-6.18-fix1` 加入
workflow 触发列表（`a2f0e2d32661`）。
**核对**：回退后 `dpu_crtc.c`、`dpu_core_perf.c/.h` 与 `fc2fb59ef397`
（6.17-stable）**逐字节一致**（`git diff` 为空），即完全恢复点亮语义。

**待用户推送**：`git -C linux-sm8450-liuqin push GitHub liuqin-6.18-fix1`。

- 点亮 ⇒ 确认根因；把 fix1 合进 `liuqin-6.18`（快进），记入本文档。
- 仍黑 ⇒ 二号嫌疑转正：回退 `dsi_phy_7nm.c` 那 6 个提交（逆序
  `git revert 6e5173e7bf80 93c97bc8d85d cb55f39bf7b1 b63f008f395c
  3bb6433ecb65 5ddcb0cb9d10` 后重编译）。

一次可先做的**零成本确认**（在黑屏的 6.18 镜像串口 shell 上）：

```
mount -t debugfs none /sys/kernel/debug
cat /sys/kernel/debug/dri/0/debug/core_perf/max_core_clk_rate
```

读数 `< 412253000` 即证实头号嫌疑，可直接推 fix1；`≥` 则转二号嫌疑。
