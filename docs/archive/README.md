# docs/archive —— 冻结的历史取证

**这里的文档不再维护，也不构成任何任务或计划。** 保留它们只有两个理由：
失败记录不能删，以及"某个结论是怎么被推翻的"必须可追溯。

每条文件顶部都有同样的横幅。里面出现的**提交号、镜像哈希、分区槽、ROM
版本**都是写作当时的现场值，其中一部分已经被后来的工作推翻（最典型：
"Ubuntu 从 B 槽启动"）。当前事实只认：

- [`../STATUS.zh-CN.md`](../STATUS.zh-CN.md) —— 唯一状态源
- [`../display.md`](../display.md) —— 显示侧已确立的结论
- [`../kernel-v73-divergence.md`](../kernel-v73-divergence.md) —— 内核偏离与 7.4 决策

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
