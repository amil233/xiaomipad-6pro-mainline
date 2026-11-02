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

### Review 与二次修正（2026-11-01 凌晨）

用户要求"在不破坏我们驱动的前提下尽量符合主线新设计"，遂把每个冲突
解决重新审了一遍，发现一个系统性问题并已修正：

**问题**：初版对 `dpu_hw_mdss.h`/`dpu_encoder.c`/`dpu_plane.c`/
`msm_gpu.h` 用了 `git checkout --ours`——这是**整文件**替换，把上游
在冲突区之外的改动也一并丢了（例如 dpu_hw_mdss.h 里上游为 Glymur
新增的 `DSPP_4..7`/`CTL_6..7`，msm_gpu.h 里 cd5697865258 的
kernel-doc 修复）。

**修正**：前三个非 dpu_plane 文件改为**真实三方合并**
（`git merge-file` ours vs 7d0a66e4bb90 vs v6.19），只保留 quad-pipe
使能的 delta，其余全部回到上游；结果（相对 v6.19 的偏离）：
- `dpu_hw_mdss.h`：仅 `STAGES_PER_PLANE=2`（Glymur enum 已合入）
- `dpu_encoder.c`：仅 quad-pipe 使能（DSC 拓扑延后到 crtc），
  上游 `helper_reset_mixers` 修复已合入
- `msm_gpu.h`：仅 liuqin `busy_percent` 字段（kernel-doc 风格已
  换成上游格式）

**dpu_plane.c 维持 ours 的论证**：
1. 上游 base..v6.19 对该文件的改动**全部**是 quad-pipe 系列
   （Jun Nie 的 5 个 + Abel Vesa 的 2 个 revert），**没有**独立
   bugfix 可吸收。
2. 上游 revert 的两条理由：Hamoa（X Elite）上 plane splitting 引起
   IOMMU fault；quad-pipe 使能"dual-DSI dual-DSC seems to be broken"
   ——**后者正是我们的配置**。我们的 SM8475 机器靠 yzddmr6 树里的
   早期 quad-pipe 版本实测点亮（铁证），换成上游最终版反而是引入
   被维护者报告 broken 的行为到我们的场景。
3. ours 与上游"完整 quad-pipe 版本"（d7ec9366b15c 时刻）的 143 行
   diff 全是风格清理（guard clause、参数简化、label 移除），功能等价。
   结论：采用 ours 无功能损失，也不丢任何上游修复。

**iris 编译性核对**：sm8450_data 的 51 个字段逐一对照 v6.19 的
`struct iris_platform_data`（61 字段），全部兼容；caps/clks 定义
风格与上游一致。

**谱系澄清（回答"liuqin 定制"）**：这一轮冲突涉及的上游改动里，
quad-pipe 系列是 **Jun Nie (Linaro)** 的主线提交（v6.19 有他 81 个
提交），**不是**我们的私有内容；被 Abel Vesa (Qualcomm) revert 了
其中 2 个。真正 ours 侧的内容是 yzddmr6/本机私有：
`2cd5a6f8` 板级支持（含 sc8280xp cs35l41 TDM 音频、ubwc cape、
SM8450 iris 平台数据）、`e8f8cc13bcb7` QSEECOM TEE init、
`0301490788d9` gpu_busy_percent——**经查 v6.19 主线没有 yzddmr6 的
任何提交**（按作者名与邮箱查均为空）。sc8280xp.c 的 TDM 定制让位于
上游 sdw helper 重构（音频非当前目标）。

修正落在 commit `8c9e1062d984`（merge `92457c175160` 之上），
CI 触发 `191acc9719dd`。

**首次 CI 失败与修复（run 41220679779）**：唯一编译错误是
`cs35l41.c:333: implicit declaration of 'snd_soc_kcontrol_component'`——
v6.19 移除了该 ASoC helper，正是旧废路线记录的"cs35l41
`snd_soc_kcontrol_component` 移除"破坏因素（旧路线自己也没修）。
已按 v6.19 标准模式改为 `snd_kcontrol_chip()`（88pm860x/ab8500 等
codec 的惯用写法，经 `soc.h → control.h` 可见），commit
`9c518c034818`。日志确认全树只有这一处编译错误。

**复跑 CI 通过**（run 41253853040，`6.19.0-g9c518c034818`）；
artifact `ci/liuqin-kernel-9c518c034818…/` 按契约核对通过
（commit 一致、`sha256sum -c` 全过）。

**镜像已装配**：`repack/619-boot/boot-liuqin-firstboot.img`，
59,162,624 字节，sha256
`44968430133d171aa57a612f024a9850853ef9f70e71f825dafbf2c5cb896271`
（Image.gz `b832f3d6…` 唯一变量；ABL DTB `7626954b…`、
ramdisk `a04d2b25…`）。

**判读**：`fastboot boot repack/619-boot/boot-liuqin-firstboot.img`
- **点亮** ⇒ 第三级完成，进 v6.20 规划；
- 黑屏 ⇒ 串口看 dmesg；首要怀疑 quad-pipe（ours 早期版本）与
  v6.19 上游 DPU 重构的交互，备选 fix 是回退到上游双 pipe 语义。
**判读**：CI 通过 → 装配 `repack/619-boot/` → `fastboot boot` →
- **点亮** ⇒ 第三级完成，进 v6.20 规划；
- 黑屏 ⇒ 串口看 dmesg（`dpu/dsi/panel/gpu`），重点检查 quad-pipe
  与 v6.19 上游 DPU 重构的交互。

### 8.1 刷机结果：ICC NULL deref（上游 v6.19 回归），fix1 已装配

**结果（2026-11-01）**：`repack/619-boot/` 刷机后未点亮也未黑屏，
内核在 2.22s 捕获 oops 后挂起（`panic=0` 不重启）：

```
Unable to handle kernel NULL pointer dereference at virtual address 0000000000000008
pc / lr: icc_link_nodes+0x34/0xf0
Workqueue: events_unbound deferred_probe_work_func
Call trace: icc_link_nodes ← qcom_icc_rpmh_probe+0x1b4/0x528 ← platform_probe
  ← really_probe ← … ← deferred_probe_work_func
Code: … (f94002a0)
```

**与显示无关**（原"首要怀疑 quad-pipe 与 v6.19 DPU 重构交互"的预判
作废——oops 发生在显示探测之前的 ICC 阶段）。

**根因**：v6.19 的 `51513bec806f`（"sm8450: convert to dynamic IDs"）
把 sm8450 ICC 描述符从 `u16 links[]`（ID 数组）改为
`struct qcom_icc_node *link_nodes[]`（指针柔性数组），**漏改两条**：
`qhs_compute_cfg`（`.link_nodes = { MASTER_CDSP_NOC_CFG }`）与
`qhs_lpass_cfg`（`.link_nodes = { MASTER_CNOC_LPASS_AG_NOC }`）。
两个 ID 在 `dt-bindings/interconnect/qcom,sm8450.h` 都定义为 0 ⇒
指针槽位存 0 ⇒ probe 里
`icc_link_nodes(node, &qn->link_nodes[j]->node)` ⇒ `&NULL->node` = 0x8。
本机 `sm8475.dtsi` include `sm8450.dtsi`，ICC provider 全是
`qcom,sm8450-*`，deferred probe 重试时必现。

**上游修复**（v6.19 之后）：`dbbd550d7c8d`（Vladimir Zapolskiy, Linaro，
"interconnect: qcom: sm8450: Fix NULL pointer dereference in
icc_link_nodes()"）——其 commit message 所贴 oops 与本机串口日志
**逐字一致**（同 0x8、同 `qcom_icc_rpmh_probe+0x1b4/0x528`、同
`deferred_probe_work_func`、连 Code 尾部 `(f94002a0)` 都相同）。

**fix1 分支** `liuqin-6.19-fix1` tip `11d739ea62a6`（从干净 6.19 tip
`9c518c034818` 直分）：
- `919a8ab07908` = `dbbd550d7c8d` 回移，`sm8450.c` 两行，**diff 与上游
  逐字节一致**（blob hash 同为 `669a638bf3ef..c88327d200ac`）；目标
  `&qhm_nsp_noc_config` / `&qhm_config_noc` 与文件内遗留
  `[MASTER_*] = &node` 查找表一致。
- **用点亮的 `liuqin-6.18` 全量核对**（`scratch/compare-icc-topology.py`，
  6.18 `.links = { ID }` 经两版一致的 `[ID] = &node` 表解析后比对
  6.19 `link_nodes`）：150/150 节点拓扑逐节点等价、`num_links` 与
  条目数全一致（无 NULL 尾巴残留）、全文件非指针 `link_nodes` 条目
  只有被修复的那两条 ⇒ 转换只漏了这两条，与点亮基线无其他差异。
- `11d739ea62a6` = workflow 触发列表加 `liuqin-6.19-fix1`。

**CI 通过**：artifact `ci/liuqin-kernel-11d739ea62a68…/` 按契约核对
通过（commit 一致、`sha256sum -c` 全过，`6.19.0-g11d739ea62a6`）。

**镜像已装配待刷**：`repack/619fix1-boot/boot-liuqin-firstboot.img`
（59,162,624 字节，sha256
`e4fed406aa3b915dee6860c091585ec1a2090d584bca250033feb7052e890f25`；
唯一变量 Image.gz `7c9071bc…`，ABL DTB `7626954b…`、ramdisk
`a04d2b25…` 与 619 镜像逐字节一致——`cmp` 首个差异在 boot header 的
kernel_size 字段）。

**刷机结果：✅ 点亮**（2026-11-01）。第三级 v6.19 完成：`liuqin-6.19`
fast-forward 到 `11d739ea62a6`（= fix1 tip，树与点亮内核一致），
`liuqin-6.19-fix1` 作为历史见证分支保留；远端推送为 fast-forward
（`git -C linux-sm8450-liuqin push GitHub liuqin-6.19 liuqin-6.19-fix1`）。
镜像 `repack/619fix1-boot/`。

**清理（第四级启动前，2026-11-01）**：删除内核仓 Ubuntu 比对时代遗留：
`liuqin-7.0` 分支（Ubuntu-7.0.0 产品线，领先远端 1 个提交
`0b86178f3fc0`；远端 `GitHub/liuqin-7.0` 是否删由用户定）与 15 个比对
tag（`v7.0`、`Ubuntu-7.0.0-*` 9 个、`archive/github-main-import`、
`archive/liuqin-7.0-orphan`、`liuqin-7.0-dts-v1`、`liuqin-dts-v1`）；
从 `linux/` 主线仓 fetch v7.0 时被带回的全历史 tag 一并清理，**只保留
`v6.17`/`v6.19`/`v7.0` 三个分级 tag**。

## 9. 第四级 v7.0：合并（进行中）

- tag `v7.0`（commit `028ef9c96e96`，2026-04-12 "Linux 7.0"）从工作区
  `linux/` 主线仓 fetch（torvalds master 一致；merge base 与 v6.19 的
  `05f7e89ab973` 吻合，谱系干净）。
- delta：15623 提交 / 17955 文件；msm 显示驱动 86 文件 2291+/2338-、
  pinctrl+interconnect 19 文件、qcom DTS + sound/soc 433 文件。
- 新分支 `liuqin-7.0` 从点亮 6.19 tip（`11d739ea62a6`）直分；旧同名
  Ubuntu 产品线分支已清理。

**merge 完成**（`2973d45c5c9f`，8 个冲突全部解决；CI 触发
`367984528b38`）：

| 冲突文件 | 解决方式 |
|---|---|
| `drivers/gpu/drm/msm/adreno/adreno_gpu.c` | 采用上游 `family >= ADRENO_6XX_GEN4`（与 ours 的 a650/a730/a740 集合精确等价的清理） |
| `drivers/media/i2c/s5kjn1.c` | 整文件采用上游（上游 6.19→7.0 合入该驱动；ours 是本地移植，相机非当前目标，同 6.19 sc8280xp 先例） |
| `samsung,s5kjn1.yaml` | 保留 ours 的 `power-domains`（板级 DTS 在用） |
| `drivers/power/reset/nvmem-reboot-mode.c` | 采用上游重写的写入路径（cell 长度校验）；ours 的 `cpu_to_le32`+`cell_bytes` 在 LE arm64 功能等价 |
| `drivers/soc/qcom/pmic_glink_altmode.c` | 整文件采用上游（`mux_ctrl` 状态机 + extended_data 报文结构）；ours 的 liuqin DP svid 0xff01/去重通知探索补丁退场（DP 控制器在 DTS 本就 disabled，且与新报文格式不兼容） |
| `drivers/soc/qcom/qcom_pdr_msg.c` | 采用上游 `SERVREG_PFR_LENGTH + 1`（与 `sizeof_field` 语义相同：结构体字段即 `reason[SERVREG_PFR_LENGTH+1]`） |
| `include/linux/soc/qcom/mdt_loader.h` | 保留 ours 的 split-image 原型/存根 + 上游新原型并集 |
| `sound/soc/qcom/qdsp6/audioreach.h` | ours AUDIO_IF + 上游 SPEAKER_PROTECTION 宏并集 |

**显示管线零冲突**：上游 6.19→v7.0 未改 `dpu_hw_mdss.h` /
`dpu_encoder.c` / `dpu_plane.c`，quad-pipe（`STAGES_PER_PLANE=2`、
`MAX_CHANNELS_PER_ENC=4`）原样保留。sm8450 ICC 描述符自动合并（含上游
`dbbd550d7c8d` NULL 修复）；FROMLIST `pinctrl-sm8475.c` 连同
`MSM_GPIO_PIN_FUNCTION` 标记保留（上游从未有此文件）；a6xx `if (reglist)`
保护、cs35l41 `snd_kcontrol_chip` 适配、`qcom_scm_qseecom_init`（v7.0
仍在）均存活。

**待推送**：`git -C linux-sm8450-liuqin push GitHub liuqin-7.0`（新分支，
无需 force）。CI 通过 → artifact 核对 → 装配 `repack/700-boot/` →
`fastboot boot` 验证点亮。

**首次 CI（run 41272915901）：失败，已修复（`8b8477af0a3c` +
`640a16da3722`）**：构建死在 `drivers/media/platform/qcom/camss/camss.o`，
唯一致命错误类是 `-Werror=incompatible-pointer-types` —— 上游 6.19→v7.0 把
`struct camss_subdev_resources.regulators` 从 `char *[]` 改成
`struct regulator_bulk_data[]`，而 yzddmr6 加的 SM8450/SM8475 资源表被
merge 原样带过来、还用旧的位置初始化 `.regulators = { "vdda-phy",
"vdda-pll" }`（camss.c:2742/2755/2768）。**这是自动合并的典型陷阱**：
结构体在 camss.h 变了、而新增的表所在的 camss.c 区域上游从不碰，git 无法
察觉。修复 = 改成上游的 designated-initializer 形式 `{ { .supply = ... } }`
（消费端 camss-csiphy.c/camss-csid.c 按 `.supply != NULL` 计数，无需动）。
顺带清掉合并残留：`mdt_loader.h` 里 `qcom_mdt_pas_init` 原型在 v7.0 的
`__qcom_mdt_pas_init`/`qcom_mdt_pas_load` 重构后已无实现无调用方，且仍引用
已删除的 `struct qcom_scm_pas_metadata` → 删除原型与存根（split-image 两个
helper 保留，QSEECOM 在用）。另有若干非致命告警（audioreach const 丢弃、
nt36523 缺原型、dpu_encoder 未用变量）为 6.17 既有代码，不动。
**yzddmr6 驱动存活盘点（merge 后全树核对）**：66 个全新驱动文件 100% 在
（fts_spi/nt36523 触控、nt36532 面板、fpc1264 指纹、qseecom TEE、
ipa_data-v5.2、tfa9872、eusb2 repeater、pinctrl-sm8475…）；修改型补丁全部
以"上游 v7.0 + 补丁"形式存活（battmgr 小米鉴权、ucsi CCI 去抖、dwc3 role
switch、camcc-sm8450、SLPI、a6xx cold-boot、gpu_busy_percent 等）；
三处主动让位：sc8280xp.c（6.19 上游 sdw 重构）、s5kjn1.c（v7.0 换上游版）、
pmic_glink_altmode.c（v7.0 换上游 mux_ctrl 版）；camss 后摄三件套
（camss-csid/vfe-780）早在 6.18 随上游 rename（780→gen2）消失。
- **二次 CI（run 41276402613）：camss 已过，iris 同类报错，已修复
  （`b560194ffc4b`）**：`iris_platform_gen2.c:967`
  `-Werror=incompatible-pointer-types`——上游 v7.0 把平台数据的
  `tz_cp_config` 拆成"指针 + 显式 size 字段"（`iris_firmware.c` 按
  `tz_cp_config_data_size` 遍历），而 6.19 树保留的 SM8450 条目仍用旧的
  `&数组` 写法且无 size。改为上游形式（与 sm8550/sm8650/sm8750/qcs8300
  条目一致）。**此类"上游结构体/字段重构 vs merge 惯性带过来的旧表"是
  本级主要破坏模式**（camss regulators、iris tz_cp_config 两连），机制
  相同：结构体在头里变、新增表所在的 .c 区域上游不碰，git 自动合并无感。
- **推 CI 前的静态排查（已做，2026-11-01）**：分析 run 日志发现
  `drivers/firmware`、`drivers/tee`、`drivers/misc`、`drivers/remoteproc`
  在两次失败中**几乎没编到**——`qcom_scm.c`、`qseecom`、指纹、SLPI 尚未
  经 v7.0 编译检验（合并前点名的头号风险）。静态核对结果：
  - 上游把 `qcom_scm.h` 从 `include/linux/soc/qcom/` 挪到
    `include/linux/firmware/qcom/`，**全树 36 处 includer 已全部跟随新路径**（merge 自动完成）；
  - qseecom 调用的 6 个 `qcom_scm_qseecom_*` 函数在新头全部有声明（另两个误匹配是 static 函数注释与结构体）；
  - `qcom_scm.c` 对 v7.0 的 delta 是**纯增量**（444+/3-），全部挂在上游 QSEECOM 区段上，未改动上游核心调用路径；
  - 未编译的 yzddmr6 文件 include 路径全部可解析；`earlycon-simplefb.c`
    引用了哪都不存在的 `<asm/early_ioremap.h>`，但该文件在当前 config
    （`CONFIG_SERIAL_EARLYCON` 未开）下不参与编译——6.17/6.19 亦如此，良性。

**第三次 CI：✅ 通过**（`7.0.0-gb560194ffc4b`）。artifact
`ci/liuqin-kernel-b560194ffc4b…/` 按契约核对：
`build-info.json.commit` 与目录名一致，`kernel/` 与 `kernel-modules/`
的 `sha256sum -c` 全过。

**镜像已装配待刷**：`repack/700-boot/boot-liuqin-firstboot.img`
（59,375,616 字节，sha256 `128ac4e9…550c5`；唯一变量 Image.gz
`5c7dd102…`，ABL DTB `7626954b…d48f`、ramdisk `a04d2b25…7682` 与
619fix1 镜像逐字节一致；CMDLINE 与点亮的 619fix1 逐字相同）。
判读：`fastboot boot repack/700-boot/boot-liuqin-firstboot.img`——
点亮 ⇒ 第四级完成，进 v7.1 规划；黑/卡住 ⇒ 串口取证（上游
6.19→v7.0 未改显示管线三件套，首要怀疑延迟探测顺序或运行时交互）。

**刷机结果：✅ 2026-11-01 点亮——第四级 v7.0 完成**。`liuqin-7.0`
tip `b560194ffc4b` = 点亮内核（三个修复直接在 merge 分支上，无需
fix 分支或 ff）。镜像清单与判读记录见 `display-panel-checklist.md` §11。

## 10. 第五级 v7.1：合并 → 花屏两轮 → 点亮（2026-11-01，✅ 完成）

tag `v7.1` = `8cd9520d35a6`（2026-06-14 "Linux 7.1"），已从工作区
`linux/` 主线仓一次性 fetch（路径 fetch 带回的全历史 tag 已清理，仓内只留
`v6.17` / `v6.19` / `v7.0` / `v7.1` 四个分级 tag）。

**delta：17275 提交 / 13457 文件**——显著大于 v6.19→v7.0，且**上游
重新推进了 quad-pipe 系列**：`9c171c36d83a`（plane splitting in
quad-pipe case）、`febcd37fec12`（拆分 plane splitting 函数）、
`25ee10927752`（延迟 SSPP 分配到 CRTC check）、`1ce61688875d`（去掉
VBIF index）。**`dpu_plane.c` 上游改 303 行，如预期冲突**。

风险分级：

| 文件 | 变化 | 冲突风险 | 策略 |
|---|---|---|---|
| `dpu_plane.c` | 上游 303 行（quad-pipe 续作 + VBIF） | **高** | 实际为整文件 theirs（见下"执行记录"：上游定稿原生支持 PIPES_PER_PLANE=4） |
| `audioreach.h/.c` | 9/71 行（上游清理，可能顺带修 const 告警） | 中 | 合并（注意 v7.0 的宏并集） |
| `sound/soc/qcom/common.c` | +6 | 中 | 保留 ours TDM helper + 上游增量 |
| `qcom_scm.c` | +64/-7（QSEECOM allowlist 扩展、kmemdup 清理） | 低 | 自动 + 关注 TEE 区段 |
| `pinctrl-msm.h` | +10（新增 `QCA_GPIO_PIN_FUNCTION`，无关 sm8475） | 无 | 验证 `MSM_GPIO_PIN_FUNCTION` 仍在 |
| camss.c / iris vpu* | bugfix（sa8775p 时钟、iris UAF/依赖） | 低 | 自动（平台表区域未动） |
| `dsi_host.c` / `dsi_phy_7nm.c` | 5 个小修（寄存器转储边界、RGB101010、版本比较 helper） | 低 | 自动 |

**显示不变量（相对 v7.0 全部安全）**：
- `dpu_encoder.c` 上游未改 ⇒ `MAX_CHANNELS_PER_ENC=4` 不变；
- `dpu_hw_mdss.h` 上游只删了无关的 `enum dpu_vbif`，`STAGES_PER_PLANE`
  定义保持（ours=2 的行未动）⇒ 可自动合并；
- `drivers/interconnect/qcom/sm8450.c` 上游未改（ICC 修复安全）；
- `pinctrl-sm8475.c` 是 FROMLIST 本地文件，上游任何版本都没有；
- 其它 6.17→7.0 存活项（QSEECOM、指纹、触控、battmgr 等）未受影响。

**执行步骤**（等用户确认）：
1. `git fetch /home/ubuntu/linux_kernel_git/linux tag v7.1`（路径一次性
   fetch，不带 remote；fetch 会带回全历史 tag，事后
   `git tag -l | grep -vE '^(v6\.17|v6\.19|v7\.0|v7\.1)$' | xargs git tag -d`
   只留四个分级 tag）；
2. 从 `liuqin-7.0` tip（`b560194ffc4b`）直分 `liuqin-7.1`；
3. `git merge v7.1`；
4. 冲突按上表处理；合并后逐项验证不变量（dp0 disabled、面板 desc、
   quad-pipe 三处、pinctrl `MSM_GPIO_PIN_FUNCTION`、a6xx `if (reglist)`、
   cs35l41、ICC 修复行）；
5. CI 触发 commit；用户 push liuqin-7.1 → 构建 → 装配 `repack/710-boot/`
   → 刷机验证。

### 执行记录（2026-11-01）

步骤 1–3 已按计划执行：`liuqin-7.1` 从点亮 7.0 tip（`b560194ffc4b`）
直分，`git merge --no-edit v7.1` 产出 **12 个冲突**（比规划表的预估更广：
`dpu_plane.c` 之外还有 dp_ctrl、wm_adsp、ipa_data 等），全部解决：

| 冲突文件 | 解决方式 |
|---|---|
| `.gitignore` | 并集：保留上游新 `# bc language scripts` 段 + 我们的 `!.github` / `!.github/**`（§5.2 的 8ca4a94d4b52 修复） |
| `drivers/of/platform.c` | 取 theirs 的变量重命名（`rmem`→`reserved`）+ 保留 ours 的高通 vendor-overlay ramoops 0 地址注释 |
| `MAINTAINERS` | 两节并集（NANOSIC ours + NAMESPACES theirs，按字母序） |
| `sound/soc/qcom/common.h` | 并集：ours `struct qcom_snd_tdm_slot_cfg` + theirs `#define LPASS_MAX_PORT` |
| `drivers/soc/qcom/ubwc_config.c` | 表头并集 `qcom,cape`（ours WIP）+ `qcom,eliza`（theirs）；`qcom,sm8475` 在表尾安全 |
| `drivers/clk/qcom/camcc-sm8450.c` | 保留 ours 的 `cam_cc_sm8450_clk_regs_configure`（SM8475 GDSC 保留）+ struct 加 `const`（theirs） |
| `drivers/power/supply/qcom_battmgr.c` | `of_variants` 表并集（glymur/kaanapali/sc8180x/sc8280xp/sm8475/sm8550/x1e80100）；`QCOM_BATTMGR_SM8475` 枚举存活 |
| `dpu_crtc.c` | 保留 ours 的 else-if 链：外层 `if (topology.num_dsc)` 块已整体处理 DSC，`num_rt_intf==2` 比 theirs 的 `num_intf==2&&!cwb` 更准，theirs 的 `num_dsc==0` 守卫在我们结构下是空操作 |
| `dpu_plane.c` | **整文件 theirs**（6 处冲突一次消除）：上游版本是 quad-pipe 系列定稿，原生支持我们的 `PIPES_PER_PLANE=4`（`STAGES_PER_PLANE=2`）；残留 30 处 `r_pipe` 全是局部变量（向 `pstate->pipe_cfg[idx+1]` 取址），非被删字段 |
| `dp_ctrl.c`（3 处） | 全取 ours：`msm_dp_ctrl_phy_init` 的 PHY-before-AUX 扩展；两处 `msm_dp_ctrl_phy_power_off` + DRM_DEBUG_DP。v7.1 把该函数改 void，但 `dp_display.c` 自动合并保留了 ours 的 `ret = msm_dp_ctrl_phy_init(...)`，int 签名一致 |
| `wm_adsp.c`（2 处） | 冲突 1 保留 ours 的 `asoc_component_prefix` 分支但翻译为新 API（`fw->filename = kasprintf(...)`）；冲突 2 全取 theirs（`&fw->coeff` + `goto err` + 完整 suffix 回退） |
| `ipa_data-v5.2.c` | **整文件 theirs**：ours 是 yzddmr6 WIP（FIXME 满篇），theirs 是同 Luca Weiss 系列的上游定稿（值相同）；theirs 去掉的 `.imem_addr/.imem_size` 仅 v5.2 未初始化（v5.0/v4.9 仍有） |

**自动合并的险情（无需改动，已核实）**：
- `wm_adsp.h` 的 `struct wm_adsp` 中 ours 加的 `post_run`/`post_stop` 回调
  字段、`wm_adsp.c` 内两个钩子调用点（`wm_adsp_event_post_run` /
  `wm_adsp_event_post_stop`）**都被自动合并保留**（ours 未改的位置 vs
  theirs 删除，git 站 ours 一边）⇒ cs35l41 的
  `pre_run`/`post_run`/`post_stop` liuqin 钩子链完整存活。
- `dpu_plane.h` 自动合并为数组布局（`pipe[PIPES_PER_PLANE]` /
  `pipe_cfg[PIPES_PER_PLANE]`），与 dpu_plane.c theirs 版本一致。

**上游 API 删除适配（`b6420bd5aa0c`，v7.1 删 `<linux/of_gpio.h>` 与
`of_get_named_gpio()`）**——merge 后静态扫描发现 ours 的两个触控驱动仍用
旧 API（nt36xxx.c 是 CI 必编文件），修为公共 gpiod API（commit
`f1afdbeb9edd`）：
- `nt36xxx.c` / `fts.c`：新增 `*_of_get_named_gpio()` helper
  （`fwnode_gpiod_get_index()` + `desc_to_gpio()` + `gpiod_put()`，
  均为 EXPORT_SYMBOL_GPL 公共 API；get 后立即 put 保持原先"先查编号、
  后另行 request"的语义；DTS 属性不用改——`of_find_gpio()` 的
  `for_each_gpio_property_name` 会同时尝试 `foo-gpios` 与 legacy
  `foo-gpio` 后缀）；
- `fts_lib/ftsIO.c`：删掉无使用者的 `#include <linux/of_gpio.h>`。
- 全树扫描确认无其他 `of_get_named_gpio()` 调用方（仅剩 gpiolib-of.c
  内部实现）。

**合并后不变量逐项验证通过**：`STAGES_PER_PLANE=2` / `PIPES_PER_PLANE=4`
（dpu_hw_mdss.h）、`MAX_CHANNELS_PER_ENC=4`（dpu_encoder.c）、
pinctrl-sm8475 两处 `MSM_GPIO_PIN_FUNCTION`、sm8450.c ICC 两行
（`&qhm_nsp_noc_config` / `&qhm_config_noc`）、a6xx `if (reglist)`
（a6xx_gpu.c:889）、`&mdss_dp0` disabled、面板 `pipa_tm_desc`
（compatible `xiaomi,pipa-nt36532`）、`snd_kcontrol_chip`、audioreach
宏并集 3 处、`mdt_loader.h` 无 `qcom_mdt_pas_init` 残留、
`qcom_scm.h` 位于 `include/linux/firmware/qcom/`（36 处 includer 跟随）。

**提交**：merge `4ea6e0f42a3f`（12 冲突）+ of_gpio 适配
`f1afdbeb9edd` + CI 触发 `065fea6a7712`（workflow 分支表加
`liuqin-7.1`）。工作树干净。

**待推送**：
```
git -C linux-sm8450-liuqin push GitHub liuqin-7.1
```
（新分支，无需 force。推送即触发 CI。）CI 通过 → artifact 核对 →
装配 `repack/710-boot/` → `fastboot boot` 验证。若黑屏，按用户预先
指导的调试手段：cmdline 加 `msm.dpu_use_virtual_planes=false`
（上游 v7.1 虚拟平面默认开启，关闭可排除该路径）。

### CI 与装配（2026-11-01）

- **CI run 41293956964：✅ 首次即通过**（of_gpio 类 API 删除在 push
  前已被静态扫描抓出修复，无其他编译错误）。
- artifact `ci/liuqin-kernel-065fea6a7712…/` 按契约核对：
  `build-info.json.commit` 与目录名一致，`kernel/`（6 件）+
  `kernel-modules/`（4 件）`sha256sum -c` 全过，
  `kernel.release` = `7.1.0-g065fea6a7712`。
- **镜像已装配待刷**：`repack/710-boot/boot-liuqin-firstboot.img`
  （59,969,536 字节，sha256 `414c64fa…8dea`；唯一变量 Image.gz
  `35850124…b88c`；ramdisk `a04d2b25…7682` 与 700 镜像逐字节一致）。
  ABL DTB `998b90b0…` 与 700 的 `7626954b…` 仅差 4 处上游 dtsi
  清理（GPU OPP 160→162 MHz、GIC ITS reg 窗口、sdhci-caps-mask
  删除、timer PPI flags），**显示节点零变化**。
- **判读**：`fastboot boot repack/710-boot/boot-liuqin-firstboot.img`——
  点亮 ⇒ 第五级完成；黑屏 ⇒ 串口取证，备用调试
  `msm.dpu_use_virtual_planes=false`。

**CI 若失败的风险预判**：本级与 v7.0 同类的"结构体重构 vs merge 惯性旧表"
盲区已按模式排查（of_gpio 已抓到）；`dpu_plane.c` 上游定稿 +
`PIPES_PER_PLANE=4` 的组合是运行期变量，编译无碍；qcom_scm/TEE 区段
上游改动（+64/-7，QSEECOM allowlist 扩展、kmemdup 清理）为自动合并，
ours TEE 段纯增量。

### 刷机：两轮花屏与定位（2026-11-01）

**背景**：v7.1 把 `dpu_use_virtual_planes` 默认从 false 翻成 **true**
（`dpu_kms.c:55`）——这激活了我们 `dpu_crtc_get_topology` 里的 4-LM 扩展
（`num_dsc = num_rt_intf * 2`），即拓扑首次在双 DSI 上走到 **4 LM / 4 DSC**。

**第一轮花屏（四个竖条）** → 取证 `/sys/kernel/debug/dri/0/state`：

| 拓扑 | rect | LM |
|---|---|---|
| 点亮（2 LM/2 DSC） | 2 个 900 宽（sspp_0 rect_0/rect_1 parallel） | 2 个 900 宽 |
| 花屏（4 LM/4 DSC） | **只有 2 个 900 宽**（sspp_8/solo、sspp_9/solo） | 4 个 **450** 宽（`lm_bounds=hdisplay/num_mixers`） |

根因：`dpu_plane_split` 只在 src 宽 > `max_linewidth`（5120）或 MDP 时钟
超限时拆 rect；4-LM 时每段 900 宽不触发，一**对** LM 共享一个 900 宽
rect → 每个 450 宽的 LM 渲染了错的 900 宽流 → 四竖条。
修复 `988a7f6e14c6`：拆分条件增加「rect 不得比单个 mixer 宽」
（`mixer_rect / PIPES_PER_STAGE`）。4-LM 时产出 4×450 rect；
2-LM 时复现原 900+900 拆分，行为不变。

**第二轮花屏（上下/左右两种图案）** → 寄存器转储显示 **DPU 侧全对**：
LM 4×450、4 个 DSC（MULTIPLEX + num_active=1）、`CTL DSC_ACTIVE=0xF` /
`INTF_ACTIVE=0x6`、双 INTF 同帧数扫描、SSPP rect 正确；DSC `ENC_DF_CTRL`
两 DCE 的差异属 NATIVE_42x 的正常 2400/1-1 vs 2400/2-1。LM 寄存器长度
也已核实为 `0x400`（`f7bf13197392`，v7.0 已入）。

**真根因在上游**：quad-pipe + 双 DSI 双 DSC 是**上游已 revert 的已知缺陷**：

| 上游提交 | 内容 |
|---|---|
| `d7ec9366b15c` | "Enable quad-pipe for DSC and dual-DSI case" |
| `da9168d8ef1c` | 2025-12-19 revert，理由逐字 *"The dual-DSI dual-DSC scenario seems to be broken by this commit"* |
| `35ab5123bd24` | 关联 revert（IOMMU faults + "all sorts of artifacts on eDP"） |

v7.1..master（至 2026-11-01）无重启用、无修复。Jun Nie 的通用拆分系列
（`9c171c36d83a`/`febcd37fec12`/`25ee10927752`）保留在 v7.1 且与我们的
拆分修复不冲突。结论：这是**上游设计性缺陷**，不是可修 bug——用户要求
查证上游已知缺陷后，确认我们的 4-DSC 扩展恰落在被 revert 的场景里。

**修复 `6ded9f48ec96`**：撤掉 4-DSC 拓扑扩展，拓扑选择回到上游 v7.1：

- `dpu_crtc.c`：恢复上游拓扑分支（`num_intf==2 && !cwb` → 2 LM；
  `num_dsc==2` → 2 LM），删除 `num_rt_intf` 与 `num_dsc = num_rt_intf * 2`；
- `dpu_encoder.c`：`dpu_encoder_update_topology` 恢复上游 2-DSC 块
  （`WARN(num_intf > 2)` + `num_intf >= 2 || dsc_count >= 2` → 2 DSC）；
- 保留 `STAGES_PER_PLANE=2` / `MAX_CHANNELS_PER_ENC=4`（惰性常量：
  拓扑回到上游逻辑后 4-LM 不可能被选中）；
- v7.1 的 `dpu_use_virtual_planes=true` 与 `dpu_crtc_reassign_planes`
  延迟 SSPP 分配**全保留**（上游新设计核心）；`dpu_plane.c` 与上游
  **逐字节相同**。

### CI 与点亮（2026-11-01）

- CI（`6ded9f48ec96`）：✅ 通过；artifact
  `ci/liuqin-kernel-6ded9f48ec96…/` 按契约核对（commit 一致、
  `sha256sum -c` 全过，`7.1.0-g6ded9f48ec96`）。
- **镜像**：`repack/710-boot/boot-liuqin-firstboot.img`（59,969,536 字节，
  sha256 `8f3ff94c…407ec1`；唯一变量 Image.gz `0b001b6f…`）。
- 判读：`fastboot boot repack/710-boot/boot-liuqin-firstboot.img`
  → **✅ 点亮**。参照 `repack/710-novirt-boot/`（同源 +
  `msm.dpu_use_virtual_planes=false`，2-LM 下同样点亮）证明虚拟平面
  延迟分配不是因素。
- **第五级完成**：`liuqin-7.1` tip `6ded9f48ec96` 即点亮内核；分支已推送
  远端（用户推送 + CI 与本地逐一一致）。

**点亮拓扑结论（供后续级别沿用）**：本机双 DSI + DSC 的稳定拓扑是
**2 LM / 2 DSC**（每链路 1 DSC、900+900 拆分）。上游 quad-pipe 在
"每 mixer 一个 SSPP 段"的通用拆分上可用，但 **num_dsc > num_intf 的
合流路径（DSC MULTIPLEX）上游自己都撤了**——后续级别不要重新启用
4-DSC，除非上游重新合入。

## 11. 第六级 v7.2：合并完成，待推送 CI（2026-11-02）

tag `v7.2` = `8d3ae59288f1`，从工作区 `linux/` 主线仓一次性 fetch（带回的
全历史 tag 已清理，仓内只留 `v6.17`/`v6.19`/`v7.0`/`v7.1`/`v7.2` 五个分级
tag）。**delta：17833 提交 / 16355 文件**。merge base = v7.1
（`8cd9520d35a6`），谱系干净：`liuqin-7.2` 从点亮 7.1 tip
（`6ded9f48ec96`）直分。

**v7.2 的两处主干变化**（决定本级冲突形状）：

1. **`drm_atomic_state` → `drm_atomic_commit` 半树重命名**：DRM 各驱动
   的 atomic 回调签名换类型名（v7.2 仍保留 `drm_atomic_state` 给未改造
   的路径）。msm 显示栈全部自动合并，无手工干预。
2. **iris 平台数据整体重构**：`iris_platform_gen1/2.c` 删除，平台数据
   移入按 SoC 的头文件（`iris_platform_sm8550.h` 等）并在
   `iris_platform_vpu2/vpu3x.c` 装配；`iris_platform_data` 结构换面——
   `fwname`/`pas_id`/`core_arch` 等并入 `firmware_desc`，删除
   `get_instance`/`inst_fw_caps_dec`/`dec_input_config_params_*`/
   `hw_response_timeout`/`resume_without_payload`/`ubwc_config`
   （UBWC 改从 `drivers/soc/qcom/ubwc_config.c` 的
   `qcom_ubwc_config_get_data()` 取）。上游 mainline 对 SM8450 视频编解码
   仍无任何支持（venus 止于 sm8250，iris 无 sm8450 条目）。

**9 个冲突与解决**：

| 冲突文件 | 解决方式 |
|---|---|
| `drivers/gpu/drm/msm/dp/dp_display.c` | **整体取 v7.2**：采用新 HPD 设计（`host_phy_init` 返回 bool，`plugged`/`sink_count` 取代 `hpd_state` 状态机）。**回移**：我们的 DPCD 读 5 次重试环（`process_hpd_high` 结构 v7.2 未动，直接套入） |
| `drivers/gpu/drm/msm/dp/dp_ctrl.c` | 保留我们的 PHY-before-AUX 补丁（int 签名 + `phy_powered` 引用计数包装）；**接受**上游对 `msm_dp_ctrl_off_link()` 的删除（v7.2 无调用方，`dp_ctrl.h` 自动合并已同步删声明） |
| `iris_hfi_gen2.c` / `iris_platform_common.h` | **整体取 v7.2**：撤下 yzddmr6 的 sm8450 平台数据（用了约 15 个结构里已删除的字段）。**iris 驱动不再绑定** DTS 的 `qcom,sm8450-iris`（视频解码从未验证可用，等同 v7.0 退役 s5kjn1 的先例；板级 dtsi 节点保持 okay 但不绑定，无运行期影响） |
| `iris_probe.c` | 删除 `qcom,sm8450-iris` 的 dt_match 条目（自动合并保留了它，引用已删除的 `sm8450_data` 会编译失败） |
| `qcom,sm8550-iris.yaml` | 取 v7.2（加 `x1p42100` 条件分支），撤我们的 `qcom,sm8450-iris` compatible 与 resets 条件 |
| `camss-csiphy-3ph-1-0.c` | **并集**：保留我们的 `lane_regs_sm8450`（GEN2 2.1.3 2PH）+ 上游新增 `lane_regs_sm6350`（同位置两侧各加一张表）；派发表两套都在 |
| `q6apm.c` / `q6apm-dai.c` | 跟随上游 push-pull shmem 系列；我们的 `alloc_fragments` 重复调用删除（else 分支已分配），CMD-format 错误传播上游已做 |
| `ktz8866.c` | i2c ID 指定初始化风格（树级清理）；我们的 `driver_data` 1/2（a/b 双芯片联动）保留 |

**自动合并险情（已核实）**：
- `iris_hfi_gen2_command.c` 自动合并把我们的 `resume_without_payload`
  `session_resume` 包装与 v7.2 的 drc/drain 并存——v7.2 删了该字段，
  保留包装会编译失败；已手工回退为 v7.2 的直接实现（`reason` payload）。
- `iris_platform_common.h` 的冲突块（我们的 4 个字段）随 iris 决策删除；
  `core_arch` 在 v7.2 移入 `struct iris_firmware_data`（保留在新结构）。
- `mdt_loader.h`：v7.2 把它从 `drivers/soc/qcom/` **移到**
  `include/linux/soc/qcom/` 并统一 API；qseecom 用的
  `qcom_mdt_get_image_size()`/`qcom_mdt_read_image()` 在新头与
  `mdt_loader.c`（EXPORT_SYMBOL）中齐备（我们 v7.1 的 split-image
  helper 与上游 v7.2 的 `qcom_mdt_read_image` 形态收敛）。
- `qcom_scm.h` 的 qseecom 导出 API 7 个全部在合并后的头中
  （`qcom_scm_qseecom_call` 是 `qcom_scm.c` 的 static 内部函数，qseecom
  仅注释引用，不是缺声明）。

**显式决策（用户确认）**：
- **iris**：全面采用上游 v7.2，放弃 sm8450 平台数据（正向移植需新建
  平台头 + Waipio 固件描述符，且无法设备验证；视频解码非当前目标）。
- **DP**：同意上述 dp_display/dp_ctrl 处理。

**合并后不变量逐项验证通过**：`STAGES_PER_PLANE=2` / `PIPES_PER_PLANE=4`
（dpu_hw_mdss.h）、`MAX_CHANNELS_PER_ENC=4`、拓扑选择 = 上游 2 LM/2 DSC
（dpu_crtc.c `num_intf==2&&!cwb`、dpu_encoder.c
`num_intf>=2||dsc_count>=2`）、`dpu_use_virtual_planes=true`（上游默认，
dpu_kms.c:55）、`dpu_plane.c` mixer 粒度拆分条件（`988a7f6e14c6`，2-LM 下
等价 900+900）、pinctrl-sm8475 ×2 `MSM_GPIO_PIN_FUNCTION`、sm8450.c ICC
两行、a6xx `if (reglist)` ×2、`&mdss_dp0` disabled、面板
`pipa_tm_desc`（nt36532.c）、`snd_kcontrol_chip`、of_gpio 适配
（fwnode get-put helper）、a6xx 冷启动修复、`gpu_busy_percent`、
SM8475 USB3 PHY 表、`slpi_auto_boot`、pd_mapper `qcom,sm8475`。

**盲区扫描**（v7.0 教训：结构体在头里变、表所在 .c 上游不碰）：双方都改过
的文件 38 个（排除 9 个已解决）；高风险的 camss 系列在 v7.2 只**增**字段
（`camss.h` 无字段重命名/删除），我们的 `.supply` 形表保持有效；
`a6xx_gmu`/`msm_gpu`/`qmp-combo`/`fsa4480`/`drm_mipi_dsi.h`/`pd_mapper`/
`platform.c`/`rtnetlink.c`/`q6v5_pas` 的 ours 残留 delta 全部是我们有意
的本地改动（注释、sysfs、模块参数、NULL 守卫、板级表项），无合并伪影。
DTSI 的显示节点零 delta。

**提交**：merge `0e2962579d78`（含 workflow 触发列表加 `liuqin-7.2`——
本轮把 CI 触发放进了 merge commit 而非独立 commit，效果等价）。

**待推送**：
```
git -C linux-sm8450-liuqin push GitHub liuqin-7.2
```
（新分支，无需 force；推送即触发 CI。）

**风险预判**：编译期风险最高的是 yzddmr6 的 TEE/remoteproc/指纹等
"未经 v7.2 编译检验" 的文件（qseecom、SLPI、fpc1264）——已按契约核对
其 include 的头（`qcom_scm.h`、`mdt_loader.h` 新位置）与调用 API 齐备；
运行期变量集中在 iris 退役（节点不绑定）与上游新增 milos 平台（无关）。
若 CI 失败，按 v7.0/v7.1 的"结构体重构 vs merge 惯性旧表"模式排查。

### v7.3 预研：SM8475 核心外设的上游支持（2026-11-02）

复查本级 merge 时顺手预研了 v7.3（`c03c1a14507d`，工作区 `linux/` 仓），
确认 v7.3 为 **SM8475 新增了三个核心外设的主线支持**（作者均为
Esteban Urrutia，应持有实机）：

| v7.3 提交 | 内容 | 对我们的影响 |
|---|---|---|
| `9583243a524c` + binding `f8bb67fa3651` | `phy: qcom: qmp-combo: Add SM8475 support`——注册 `qcom,sm8475-qmp-usb3-dp-phy` | **板级 DTS 已用该兼容串为首选**（`sm8475-xiaomi-liuqin.dts:1846`：`"qcom,sm8475-qmp-usb3-dp-phy", "qcom,sm8450-..."`）；v7.2 下走的是我们 yzddmr6 移植的本地表 |
| `9e953732c3ed` + `bae047e91213` + `f8b4493d5e7e` | `phy: qcom: qmp-pcie: Add support for SM8475 Gen3x1 PCIe0 port`（`qcom,sm8475-qmp-gen3x1-pcie-phy`，v5 offsets + sar2130p pcs_lane1） | 我们 dtsi 用的是 `qcom,sm8450-qmp-gen3x1-pcie-phy`（v7.2 有）；v7.3 提供了 sm8475 专用条目可选 |
| `1ad05292c01b` + `a95cfed54bf9` + `c1d0a877c7be` | `ASoC: qcom: sc8280xp: Add support for SM8475`——`qcom,sm8475-sndcard` 机器驱动 | 我们 DTS 用 `qcom,sm8450-sndcard`（§8 记录的 liuqin TDM/cs35l41 音频链） |

**表来源差异（重要的合并预判）**：上游的 `sm8475_usb3dpphy_cfg` 复用
`sar2130p_usb3_serdes_tbl`（+ 独立的 `sm8475_usb3_pcs_usb_tbl`），DP 侧
同样是 `qmp_v6_dp_v1_*` 表；我们的本地版用的是**厂商移植的
`sm8475_usb3_*` 表**（注释说明 QSERDES V5 / QPHY V4 布局，DP 用 v6 表
因为本机 DP PHY 是 4nm "4nm-v1"）。**merge v7.3 时 qmp-combo.c 会冲突，
需要在"上游 sar2130p 源"与"我们的厂商移植源"之间定夺**——优先按主线
原则取上游（作者有实机），若 USB 出现回归再保留 ours，并用一次 CI 分别
验证。

**明确没有 SM8475/SM8450 支持的（v7.3 仍然没有）**：
- iris / venus 视频编解码（v7.3 的 iris dt_match 与 v7.2 相同：
  milos/qcs8300/sc7280/sm8250/sm8550…，**无 sm8450**）——本级退役
  sm8450 平台数据的选择在 v7.3 仍然成立；
- 无 sm8475 的 dtsi/板级、interconnect provider、pinctrl
  （`pinctrl-sm8475.c` 继续保持 FROMLIST）。

**复查结论（v7.2 当前状态）**：iris 七个文件（`iris_hfi_gen2.c`、
`iris_platform_common.h`、`iris_hfi_gen2_command.c`、`iris_probe.c`、
`iris_hfi_gen1.c`、`iris_platform_vpu2/vpu3x.c`、Makefile）与上游 v7.2
**逐字节一致**；全 iris 目录无 `sm8450_data`/旧结构字段
（`get_instance`/`fwname`/`dec_input_config_params_*`/
`resume_without_payload` 等）的悬空引用；`iris_platform_genN.c` 已从
工作树删除。9 个冲突文件的最终 delta 全部复核：
- `q6apm.c/q6apm-dai.c` 残留 = 我们的错误路径回滚 + DAI 状态机守卫（有意）；
- `ktz8866.c` = 双芯片（a/b）寄存器镜像逻辑（有意）；
- `dp_display.c` = 仅 DPCD 重试环；`dp_ctrl.c` = 仅 `msm_dp_ctrl_off_link`
  删除（其余与点亮 7.1 逐字节一致）；
- 其余自动合并的 38 个"双方都改过"文件 ours delta 亦全部为有意改动
  （a6xx 冷启动、`gpu_busy_percent`、SM8475 USB3 表、`slpi_auto_boot`、
  `qcom,sm8475` pd_mapper、`IFLA_PARENT_DEV_NAME` NULL 守卫等）。

### 首次 CI（run 41326639294）：失败，已修复 `d837cfa6f187`

唯一编译错误（全树仅此一处）：

```
drivers/gpu/drm/panel/panel-novatek-nt36532.c:1208:9: error: implicit
declaration of function 'drm_panel_init'; did you mean 'drm_panel_put'?
```

**根因（同 v7.1 的 of_gpio 同类盲区）**：v7.2 把 `drm_panel_init()`
从公开头里删除——面板改为"refcounted panel"范式，由
`devm_drm_panel_alloc(dev, struct type, member, funcs, connector_type)`
一次完成分配+初始化+引用计数（内部 static `drm_panel_init` 只服务它）。
我们的三个面板驱动都是 FROMLIST/yzddmr6 文件（v7.2 不触碰 merge 不到），
仍用 `devm_kzalloc` + `drm_panel_init` 旧范式。

**修复** = 完全照上游转换 `panel-novatek-nt36523.c` 的写法：`devm_kzalloc`
换成 `devm_drm_panel_alloc`（`IS_ERR`/`PTR_ERR`），删掉 `drm_panel_init`
调用，保留 `prepare_prev_first` 与 `drm_panel_remove`（两者 v7.2 仍在）：
- `panel-novatek-nt36532.c`——**点亮用的面板驱动**（CI 必编，
  `CONFIG_DRM_PANEL_NOVATEK_NT36532=y`）；
- `panel-tianma-nt37705.c` / `panel-visionox-nt37705.c`——同样用了旧
  API 的 FROMLIST 驱动（config 未开、不参与编译，但是定时炸弹，一并修）。

**教训补充**：逐级合并前的静态扫描要加上"v7.X 上游从公开头删除的导出
符号 vs 我们 FROMLIST 驱动的调用点"这一项；v7.1 抓到 `of_gpio`，v7.2
抓到 `drm_panel_init`。已核对面板/DSI 驱动用到的其余 API
（`drm_panel_of_backlight`、`drm_panel_add/remove`、
`of_find_mipi_dsi_host_by_node`、`devm_mipi_dsi_device_register_full`）
在 v7.2 全部保留。

### 二次 CI（run 41365242101）：ucsi 签名失败，已修复 `bf7540f8f07b`

第一次修复后重推，又一个**同类盲区**（报错全树仅此一处）：

```
drivers/usb/typec/ucsi/ucsi.c:1634:23: error: too few arguments to
function 'ucsi->ops->sync_control'
```

v7.2 给 `struct ucsi_operations.sync_control` 扩了
`(void *msg_out, size_t msg_out_size)` 两个参数（使命令可以自带
message-out 载荷，不必再走 `write_message_out`；后者 v7.2 **保留**——
此前我误读头文件以为删了，复核后订正）。被截的调用点在**我们的 CCI
去抖补丁**里（`ucsi_reset_ppm` 的 stale-ack 前奏）——merge 时该 hunk
保留 ours 旧签名。修复 = `NULL, 0` 补齐两个新参数（与 v7.2
`ucsi_send_command()` 的无载荷惯用法一致）。

补充核对（防同类漏网）：
- 所有 ucsi 后端（含我们实际使用的 `ucsi_glink.c`）已全部是 v7.2 形态
  （`.sync_control = ucsi_sync_control_common`）；`ucsi_glink.c` 相对
  v7.2 唯一差异是我们板级的 `qcom,sm8475-pmic-glink` 兼容串，无害。
- v7.1→v7.2 的三个机械式大改已确认ours 侧干净：
  `995832b2cebe`（mod_devicetable include 清理 1507 文件，仅删 include）、
  `5164f7e7ff8e`（drm_atomic_commit 重命名 362 文件，msm 栈自动合并）、
  `f68afce8e8a7`（iio 初始化）。
- v7.2 删除的 40 个头文件**无任何** drivers//sound//arch/ 文件再 include。

### 第三次 CI（run 41371562984）：✅ 通过，镜像已装配（2026-11-02）

CI 通过；artifact `ci/liuqin-kernel-bf7540f8f07b…/` 按契约核对
（`build-info.json.commit` 一致，kernel/modules 的 `sha256sum -c` 全过，
`kernel.release` = `7.2.0-gbf7540f8f07b`）。

**镜像已装配待刷**：`repack/720-boot/boot-liuqin-firstboot.img`
（59,174,912 字节，sha256 `fb3332bd…5c`；唯一变量 Image.gz
`9dabb7ee…`；ramdisk `a04d2b25…` 与 710 逐字节一致）。

**ABL DTB 与 710 的差异**（反编译逐节点比对）：**仅一处**，且与显示
无关——v7.2 上游修了 `sm8450.dtsi` 的 `crypto@1d88000`
（inline-crypto-engine：`reg` 窗口 `0x8000`→`0x18000`、加 `iface`
时钟与 power-domain）。DSI/DPU/面板/PHY 节点零变化。

判读：`fastboot boot repack/720-boot/boot-liuqin-firstboot.img`——
点亮 ⇒ 第六级完成；否则取 `/sys/kernel/debug/dri/0/state` 与 710
点亮态（2 rect×900 / 2 LM）对比定位。
