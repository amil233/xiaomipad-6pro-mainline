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
| `liuqin-6.18-fix1` | `liuqin-6.18` | —（回退 mode 过滤 2 个上游提交） | **证伪**：刷机仍黑（见 §6），失败层比该过滤更早 |
| `liuqin-6.18-fix2` | `liuqin-6.18` | —（回移 a6xx NULL 保护 1 个提交） | 回归实验分支，**真根因**（见 §6），待推送 CI |
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
**实测（2026-10-31）：`dri/0` 整个路径不存在**——`dri/<minor>` 符号链接在
DRM 设备注册时建立，它缺失意味着 msm 显示驱动可能**根本没 probe/注册成功**
（比 atomic check 更早的失败），需要 `dmesg` 进一步定位：
`ls /sys/kernel/debug/dri/`、`dmesg | grep -iE 'mdss|dpu|dsi|drm|panel'`。

### fix1 构建与镜像（2026-10-31）

CI 通过（`liuqin-6.18-fix1`，artifact
`ci/liuqin-kernel-a2f0e2d326619882e03e854f3e9fe4924c827949/`，`sha256sum -c`
全过，`kernel.release = 6.18.0-ga2f0e2d32661`）。镜像
`repack/618fix1-boot/boot-liuqin-firstboot.img`，58,859,520 字节，
sha256 `0e9b3b86344877c60f0826098edf26b72e8a72d9aa99924ca6de34ba119a3ba0`
（输入：Image.gz `9b0b53e5…23f3c56`、ABL DTB `643337f7…65f36e`、
ramdisk `a04d2b25…7682` —— 后两者与 618-boot 相同）。

**判读**：`fastboot boot repack/618fix1-boot/boot-liuqin-firstboot.img`
- 点亮 ⇒ 根因确认，把 fix1 快进进 `liuqin-6.18`，第二级完成。
- 仍黑 ⇒ 两条线并行：(1) 抓 dmesg 看 msm/mdss/dpu probe 到哪一步
  （`dri/0` 缺失指向早期 probe 失败，不是 mode_valid 阶段）；
  (2) 回退 `dsi_phy_7nm.c` 那 6 个提交。

## 6. 真正的根因：a6xx `ifpc_reglist` NULL 解引用（2026-10-31）

fix1 刷机**仍黑**（黑屏+背光），串口取证如下：

```
~ # ls /sys/kernel/debug/dri/
bridges                 ← 只有空目录
~ # ls /sys/class/drm/
version                 ← 没有 card0：没有任何 DRM 设备注册
```

失败发生在 **component master bind 之前/之中**，比模式过滤（atomic check）
和 DSI PHY（link 层）都更早。顺这条线重查 diff，定位到上游 v6.18 提交
`a6a0157cc68e` `drm/msm/a6xx: Enable IFPC on Adreno X1-85`：

```c
/* a6xx_gpu.c, a7xx_patch_pwrup_reglist() */
reglist = adreno_gpu->info->a6xx->ifpc_reglist;   /* Adreno 730 条目里是 NULL */
lock->ifpc_list_len = reglist->count;             /* ← 开机必现 NULL 解引用 */
```

成立的三段证据：

1. 本机 GPU 是 Adreno 730（`qcom,adreno-730.1`，`&gpu { status = "okay" }`），
   目录条目 `0x07030001` / `ADRENO_7XX_GEN1` 只有 `pwrup_reglist`，
   **没有 `ifpc_reglist`**（全表只有 X1-85 与 Adreno 740 两个条目带它）。
2. `adreno_is_a7xx()` 对 7xx family（含 730）返回 true，`a6xx_hw_init()`
   会调用 `a7xx_patch_pwrup_reglist()`。
3. **上游已在 v6.19 补上 `if (reglist) {…}` 保护**（即本修复的出处）。

崩溃链：

```
component master: msm_drm_bind()
  → adreno_load_gpu()
    → msm_gpu.c:169  gpu->funcs->hw_init()
      → a6xx_hw_init()
        → a7xx_patch_pwrup_reglist()  ← oops，bind 中断
  → drm_dev_register() 永不执行 ⇒ 没有 card0
  ⇒ 整条显示管线一次都没起来（DSI/panel 从未 enable）
  ⇒ 黑屏（ABL splash 背光还在）
```

与全部观察吻合：`/sys/class/drm/` 只有 `version`、无 dmesg 报错线索（默认
atomic 调试信息不打印）、6.17 不含此重构所以一切正常、GPU 固件
（`a730_sqe.fw` / `gmu_gen70000.bin` / `a730_zap.mbn`）都在 initramfs 里，
GPU 初始化能走到崩溃点。fix1（mode 过滤回退）证伪：失败层比它早，但其中
两个 revert 无害，fix2 不含它（单变量）。

### 修复实验：分支 `liuqin-6.18-fix2`

从 `liuqin-6.18` tip（`47048e710209`）分出，只加一个提交
`c4f967f12ea0`：回移 v6.19 的 `if (reglist)` 保护（patch 后函数体与
`liuqin-6.19` 里的版本**逐字节一致**，已 diff 验证；GEM 分配的
`pwrup_reglist` 缓冲页是清零的，NULL 时 `ifpc_list_len` 保持 0，与 6.17
行为等价）。另 `7c18dc40cbd9` 把 `liuqin-6.18-fix2` 加进 workflow 触发
列表。

**已推送并构建通过**（CI artifact
`ci/liuqin-kernel-7c18dc40cbd9eb39767db875fc839b653c659270/`，`sha256sum -c`
全过，`kernel.release = 6.18.0-g7c18dc40cbd9`）。

镜像 `repack/618fix2-boot/boot-liuqin-firstboot.img`，58,855,424 字节，
sha256 `f2a64964caf9085b19d97d0f57bdfe930b48954b61bd63d87ab0750c371d536e`
（输入：Image.gz `1a660fa4…d536e`、ABL DTB `643337f7…65f36e`、
ramdisk `a04d2b25…7682` —— 后两者与前两级相同）。

**判读**：`fastboot boot repack/618fix2-boot/boot-liuqin-firstboot.img`
- **点亮** ⇒ 根因确认，第二级（v6.18）完成：把 fix2 快进进 `liuqin-6.18`，
  进 v6.19 合并（**v6.19 已自带此 NULL 保护**，第三级会自动消化，fix2 只是
  让 6.18 提前变好）。
- 仍黑 ⇒ 再抓 dmesg（`dmesg | grep -iE 'mdss|dpu|dsi|drm|panel'`，
  `/tmp` 不存在就直接屏幕输出），转其它线索。

### fix2 刷机结果：仍黑，但 a6xx 修复确认有效（2026-10-31）

fix2 镜像刷机**仍然黑屏**，串口 dmesg 证实 fix2 的 a6xx NULL 保护**起了作用**：
GPU oops 消失，`msm_drm`、`mdss_gdsc`、`mdss_int2_gdsc`、`dispcc`、
`ae94000.dsi`、`ae96000.dsi` 全部探测成功（return 0）。**失败点后移到面板**，
真凶露面：

```
[    2.169048] disp_cc_mdss_mdp_clk_src: rcg didn't update its configuration.
[    2.500591] sm8475-tlmm f100000.pinctrl: pin GPIO_0 already requested by ae94000.dsi.0; cannot claim for f100000.pinctrl:551
[    2.501948] panel-nt36532 ae94000.dsi.0: error -EINVAL: Failed to get reset-gpios
[    2.501965] panel-nt36532 ae94000.dsi.0: probe with driver panel-nt36532 failed with error -22
```

面板探测 `-EINVAL` ⇒ DSI 永远不会 prepare ⇒ 整条 DRM 管线一次没起来 ⇒
黑屏（ABL 背光还在）。同次 dmesg 里 `[NVT-ts] failed to add panel follower:
-517` 只是触摸屏跟随者在面板缺失时的连带 deferral。

## 7. 第二个根因：pinctrl `strict` 语义 + sm8475 漏标 GPIO 函数（2026-10-31）

### 机制（源码级，逐行验证）

v6.18 的 `drivers/pinctrl/qcom/pinctrl-msm.c` 转用通用 pinmux ops，带来
三个新东西：`.strict = true`、`.function_is_gpio =
pinmux_generic_function_is_gpio`、`gpio_request_enable`。其中
`pinmux_generic_function_is_gpio()`（`drivers/pinctrl/pinmux.c:891`）只认
函数表里带 `PINFUNCTION_FLAG_GPIO` 的条目。

上游 `480dc1952404`（"pinctrl: qcom: mark the `gpio` and `egpio` pins
function as non-strict functions"，2025-09-02 落入 v6.18）把 **48 个高通
平台**的函数表改成 `MSM_GPIO_PIN_FUNCTION(gpio/egpio)`，**唯独漏掉
`pinctrl-sm8475.c`**——本机芯片正是 SM8475。同代相邻的 sm8450、sm8550、
sar2130p 全都有。

于是板级 dts 里面板节点（`sm8475-xiaomi-liuqin.dts` 的 `panel@0`）：

```dts
pinctrl-0 = <&sde_dsi_active>;      /* 先把 GPIO_0 mux 到 function "gpio" */
pinctrl-names = "default";
reset-gpios = <&tlmm 0 GPIO_ACTIVE_HIGH>;   /* 再用 gpiod 申请同一个脚 */
```

在 `pin_request()`（`drivers/pinctrl/pinmux.c:140-165`）里：

- 6.17：`ops->strict=false` ⇒ 第一个检查 `(!gpio_range || ops->strict)`
  对 GPIO 请求为 **false** ⇒ 直接放行，面板正常。
- 6.18：`strict=true` 且 `function_is_gpio()` 因漏标返回 **false**
  （`gpio_ok=false`）⇒ `desc->mux_usecount=1`、`mux_owner="ae94000.dsi.0"`
  ⇒ **"pin GPIO_0 already requested by ae94000.dsi.0; cannot claim for
  f100000.pinctrl:551"**（申请方标签 `f100000.pinctrl:551` 来自
  `pinmux_request_gpio()` 的 `kasprintf("%s:%d", range->name, gpio)`，
  551 是 tlmm 的全局 GPIO 基号，即本机的 reset-gpios 请求）。

这是**上游的真实遗漏 bug**，不只影响本机：任何 6.18 上的 SM8475 设备，
只要"先用 pinctrl 状态把脚 mux 到 gpio、再用 gpiod 申请"，都会被拒。

### 修复实验：分支 `liuqin-6.18-fix3`

从 `liuqin-6.18-fix2` 顶点（`7c18dc40cbd9`）分出，**只改上游忘改的那两行**
（`drivers/pinctrl/qcom/pinctrl-sm8475.c`）：

```diff
 static const struct pinfunction sm8475_functions[] = {
-	MSM_PIN_FUNCTION(gpio),
+	MSM_GPIO_PIN_FUNCTION(gpio),
 ...
-	MSM_PIN_FUNCTION(egpio),
+	MSM_GPIO_PIN_FUNCTION(egpio),
```

与 `480dc1952404` 对 sm8450 的改法**逐字同构**（同 commit 同样两行）。
提交 `7bac0e681a93`；`9c6dfba69e93` 把 `liuqin-6.18-fix3` 加进 workflow
触发列表。分支顶点 `9c6dfba69e9386356cf3d6fd7066e7c7e4941974`。

**设计说明（为什么不动 DTS 也不回退 strict）**：
不动面板节点的 `pinctrl-0`、也不回退 `pinctrl-msm.c` 的 strict 语义——
strict 行为本身是上游有意引入的，DTS 的 pinctrl 状态是正常的设备树用法；
漏的是平台驱动的一行宏。这不是 workaround，是**上游遗漏的回补**，
未来上游若补上也必然是这一步。

**遗留观察（不在本变量内）**：fix2 dmesg 里还有
`disp_cc_mdss_mdp_clk_src: rcg didn't update its configuration.`（clk-rcg2
`update_config` 超时，`fc2fb59..47048e71` 之间该文件 +8/-4 行）。dispcc 探测
返回 0、无失败对应，按单变量原则暂不动，记为下一轮候选（fix4）。

**已构建并装配**（CI run 41205848526 success，artifact
`ci/liuqin-kernel-9c6dfba69e9386356cf3d6fd7066e7c7e4941974/`，
`sha256sum -c` 全过，`kernel.release = 6.18.0-g9c6dfba69e93`）。
镜像 `repack/618fix3-boot/boot-liuqin-firstboot.img`，58,855,424 字节，
sha256 `9771be3cdc9f8dc703067bb7b17e91013af4ef756c2c39800f540cf7b0e31943`
（输入：Image.gz `283134a5…f9a9b`；ABL DTB `643337f7…65f36e`、
ramdisk `a04d2b25…7682` 与前四级相同）。

**刷机结果：✅ 2026-10-31 点亮**（`fastboot boot
repack/618fix3-boot/boot-liuqin-firstboot.img`，串口可见
`liuqin-initramfs starting local emergency shell`，屏幕出画面）。

至此 v6.18 两处回归都已修复且验证：
fix2（a6xx NULL 解引用）+ fix3（pinctrl-sm8475 漏标）。

**第二级（v6.18）完成。已做的收尾**：
**收尾修正（用户两点意见，2026-10-31）**：
1. **fix1 是证伪旁支，不应入谱系**——已重建干净的 `liuqin-6.18`：
   从 `47048e710209`（原 6.18 tip）cherry-pick 两个实质修复
   （`755c769d253e` a6xx + `d73093a229fc` pinctrl），新 tip
   `d73093a229fc`。树与点亮的 fix3 tip `9c6dfba69e93` **逐字节等价**
   （唯一差异是 workflow 触发列表），已用 `git diff --stat` 与 blob
   hash 双重验证。顺带修正谱系：fix2/fix3 本就是从 6.18 tip 直分，
   fix1 从未进入点亮链。
2. **旧 6.19 废路线作废**——它是在本地尚无主线源码时按 Ubuntu 26.04
   源码/tag 合并的（本地 `v6.19-rc6` tag 是 `24d479d26b25`，与
   kernel.org 的 rc6 `c8a4a774a9b0` 哈希不同，来源不纯）。

## 8. 第三级 v6.19：合并完成，待推送 CI（2026-10-31）

### 来源与基线

- tag `v6.19` 从上游 `git.kernel.org/torvalds/linux.git` fetch
  （`e9ec05addd1a` → commit `05f7e89ab973` "Linux 6.19"），**与工作区
  `linux/` 主线仓的 v6.19 tag 完全一致**。fetch 意外带回 942 个历史
  tag（v2.6.11…v7.3-rc7），已按 mtime 识别并删除，只留 v6.19。
- 基线：干净的 `liuqin-6.18` = `d73093a229fc`；merge commit
  `92457c175160`（`--no-ff`），加 CI 触发后 tip
  `f4ba03317a7c415008e3d1453e9185dabafaab51`。

### 10 个冲突与解决（含一个重要发现）

**重要发现**：liuqin 依赖的 quad-pipe 系列**本来就是 yzddmr6 提交到
上游的**，v6.19 合并后又把其中两个 revert 了：
`da9168d8ef1c Revert "Enable quad-pipe for DSC and dual-DSI case"`、
`35ab5123bd24 Revert "support plane splitting in quad-pipe case"`。
liuqin 双 DSI DSC 点亮依赖完整 quad-pipe，故必须保留 ours。

| 文件 | 解决 |
|---|---|
| `dpu_hw_mdss.h` | ours：`STAGES_PER_PLANE=2`（上游 revert 回 1） |
| `dpu_encoder.c` | ours：`MAX_CHANNELS_PER_ENC=4`（上游 revert 回 2）；非 quad-pipe 上游修复（WB number、dead-code）在自动合并区已合入 |
| `dpu_plane.c` (7处) | ours：完整 quad-pipe 多 pipe 结构 |
| `msm_gpu.h` | ours：`busy_percent` sysfs |
| `sc8280xp.c` | theirs：v6.19 改用通用 `qcom_snd_sdw_*` helper，liuqin cs35l41 TDM 定制让位（音频非当前目标） |
| `qcom_scm.c` | 混合：保留 liuqin QSEECOM TEE init（及注释），allowlist 检查换用上游新 API `of_machine_device_match()`——旧 helper 已被上游删除；两者语义等价 |
| `ubwc_config.c` | 合并：`qcom,cape`（liuqin）+ `kaanapali`/`glymur`（上游） |
| `dts/qcom/Makefile` | 合并：xiaomi 板级 dtb + 上游 sm8550-hdk 规则 |
| `iris_platform_common.h` | const 化 + 并集（补回 liuqin 的 sm8450_data 声明） |
| `iris_platform_gen2.c` | 保留 liuqin `sm8450_data` 定义（const 化）；v6.19 已从上游列表删 sm8450，但 SM8475 liuqin 视频解码匹配它 |

**安全检查（merge 后）**：`MSM_GPIO_PIN_FUNCTION(gpio)` ✓、a6xx
`if (reglist)` ✓、quad-pipe 三个标记 ✓、`busy_percent` ✓、板级
dtb 在 Makefile ✓、全树无残留冲突标记。

**待用户推送**：`git -C linux-sm8450-liuqin push GitHub liuqin-6.18 liuqin-6.19`
（先 6.18 树等价复跑 CI，或直接推 6.19 也可；两者 push 都会触发 CI）。
**判读**：CI 通过 → 装配 `repack/619-boot/` → `fastboot boot` →
- **点亮** ⇒ 第三级完成，进 v6.20 规划；
- 黑屏 ⇒ 串口看 dmesg（`dpu/dsi/panel/gpu`），重点检查 quad-pipe
  与 v6.19 上游 DPU 重构的交互。
