# docs/archive —— 历史记录

**这里的文档不再维护，也不构成任务。** 保留它们是为了留下失败记录和结论
变化的过程。里面的提交号、镜像哈希、分区号和 ROM 版本都是写作当时的值，
现在未必成立。当前事实只看：

- [`../STATUS.zh-CN.md`](../STATUS.zh-CN.md) —— 设备现状
- [`../INSTALL.zh-CN.md`](../INSTALL.zh-CN.md) —— 刷机、更新、回滚
- [`../BUILD.zh-CN.md`](../BUILD.zh-CN.md) —— 从源码到可刷产物

## 2026-11-24 精简时归档

安装方式和分区布局定下来之后，下面这些文档不再作为依据，整体移到这里：

| 文件 | 原来是什么 |
|---|---|
| `status-2026-11-24.zh-CN.md` | 旧的状态文档（含安装器历史、决策记录和大量哈希） |
| `FEATURES.zh-CN.md` | 指纹/相机/快充/Waydroid 的细节 |
| `display.md` | 显示点亮的排查记录 |
| `AUDIO.zh-CN.md` | 外放 TDM 的调试记录 |
| `userspace-port.md` | 从参考项目 v0.6.0 到 v0.8.0 的取舍提案 |
| `kernel-v73-divergence.md` | 内核相对 7.3 的偏离清单和 7.4 合并预演 |

## 参考项目旧文档（`reference-v0.6.0/`）

这一组是 2026 年从 `liuqin-6.17test`（yzddmr6）v0.6.0 分出来时保留的旧文档：
双语 README、BUILD/INSTALL-TESTING/FLASHING、STAGE2、CAMERA/FINGERPRINT/
FASTCHARGE/WAYDROID 的中文版。它们描述的是**参考项目**（6.17 内核、
`OS2.0.6.0` ROM、256GB 开发机、B 槽/双系统），**不是本机**。

保留原因只有一个：追溯"用户态骨架从哪来"。里面的容量、槽位、ROM、内核、
版本号一律不得引用；本机事实只认上面列出的现行文档。

## 索引

| 文件 | 是什么 | 现在的价值 |
|---|---|---|
| `kernel-version-upgrade-full.md` | 6.17→7.3 逐级升级全程、每次冲突与 CI 失败的原始记录，以及参考项目 v0.6.1/v0.6.2/v0.7.0/v0.8.0 各批移植的评估 | 升级流程与判读教训；**其中 v0.7.0/v0.8.0 批次已作废** |
| `display-panel-checklist.md` | 天马面板全量问题清单（B–I 共 60 余项打勾排除） | 排除法清单本身可复用 |
| `display-blackout-plan.md` | 7.0 黑屏的标准流程排查方案与 W1/W2 结果 | W1 的两条判级结论（init 序列一致、slice-per-pkt 差异）仍有效 |
| `display-driver-plan.md` | 显示驱动分层计划与判定树 | 分层判据仍可参考 |
| `display-driver-repair-plan.md` | 新旧两份面板驱动的差异复核，含"desc 选型不透明"的取证 | desc 选择规则与 ~10 s 复位的记录；**"不打印 desc"一条已被推翻**，现驱动会打印 `panel desc:` |
| `display-617-tianma-lit.md` | 6.17 天马面板点亮时的权威配置记录（可逐位复现） | §2 的黄金值、§4 的 bootargs、§5 的 desc 字段、§8 的观测与陷阱 |
| `known-wrong-changes.md` | 已证伪的显示改动与判读陷阱登记表（W1–W8、R 系列） | 每条"错在哪"的理由；改显示前必读 |
| `diff-308065ef-vs-head.md` | 基线镜像与当时 HEAD 的源码差异审计 | 曾经"唯一能改变显示路径"的候选也失败了，这条路线已关闭 |
| `migration-7.0.md` | 6.17→7.0 迁移的状态记录与真机首测手册 | RAM 启动流程与失败决策树 |
| `triage-2026-10.md` | 早期现场报告分诊（安装后自动进 fastboot、蓝牙 BR/EDR） | 分诊方法 |
