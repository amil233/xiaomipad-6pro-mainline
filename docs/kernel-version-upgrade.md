# 内核版本逐级升级计划与冲突解决记录

任务模型：`liuqin-6.17-tianma`（基于主线 **v6.17-rc1-211-g90d970cade8e**，能点亮天马面板）
是起点。逐级合并主线稳定版（v6.17 → v6.18 → v6.19 → …），每级：

1. agent 本地合并并解冲突；
2. 用户 `git -C linux-sm8450-liuqin push GitHub <branch>` 触发 CI；
3. 用户取 CI artifact 装配 boot 镜像刷机，验证是否仍点亮；
4. 点亮则进入下一级，不亮则定位回退。

绝对禁止本地编译（AGENTS.md §0.1），正确性一律由 CI 判定。

## 1. 各级分支命名

| 分支 | 来源 | 合并的目标 tag | 状态 |
|---|---|---|---|
| `liuqin-6.17` | yzddmr6 上游 | —（基线，勿动） | 只读参照 |
| `liuqin-6.17-tianma` | 上一分支 + 5 提交 | —（**当前点亮版本** @ `c7e51cdf3290`） | 点亮基准 |
| `liuqin-6.17-stable` | `liuqin-6.17-tianma` | `v6.17`（`e5f0a698b34e`） | 第一级，进行中 |
| `liuqin-6.18` | 点亮的那一级 | `v6.18`（`f7b88edb52c8`） | 试验合并已完成冲突分析，待执行 |
| `liuqin-6.19` | — | `v6.19-rc6` | 已尝试，CI 失败（见 §2） |

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

这三处问题在 **v6.18 里都不存在**（无 glymur catalog、
`snd_soc_kcontrol_component` API 还在、dwc3 未合并），所以把 6.18 作为
6.17 之后的下一级，而不是直接修 6.19。

## 3. v6.18 试验合并的冲突分析（合并已做过，尚未落盘）

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
`25cca3bba20a`（13 个冲突，详见 §3 的执行记录）。待推送 CI + 刷机验证：
`git -C linux-sm8450-liuqin push GitHub liuqin-6.18`。
