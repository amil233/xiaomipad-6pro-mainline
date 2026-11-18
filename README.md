# xiaomipad-6pro-mainline（liuqin-7.3 分支）

Xiaomi Pad 6 Pro（liuqin，**128G**）上的 Ubuntu 26.04 arm64 单系统、
主线 **7.3** 内核 + 树外驱动。设备**没有 Android**，**从 A 槽直接启动**。

- 本分支：`liuqin-7.3`，只维护**本机**的设备状态、安装/构建工具与文档。
- `main` 分支只保留 2026 年从参考项目 v0.6.0 搭起的用户态骨架，不再更新；
  参考项目的双语 README、安装手册、构建指南已整体归档到
  [`docs/archive/reference-v0.6.0/`](docs/archive/reference-v0.6.0/)。
- **不要**把参考项目（`liuqin-6.17test`）的文档、ROM（`OS2.0.6.0`）、
  槽位方案（B 槽）或版本号当作本项目事实。唯一上游是主线 Linux。

## 先读

| 文档 | 内容 |
|---|---|
| [`docs/STATUS.zh-CN.md`](docs/STATUS.zh-CN.md) | **唯一状态源**：设备、内核、已工作/未验证、待办、决策 |
| [`docs/INSTALL.zh-CN.md`](docs/INSTALL.zh-CN.md) | 安装/重装/恢复：128G、A 槽单系统、安装器 + 手动修正 |
| [`docs/BUILD.zh-CN.md`](docs/BUILD.zh-CN.md) | 只允许 CI 编译内核；artifact 契约、本机装配、打包 |
| [`docs/FEATURES.zh-CN.md`](docs/FEATURES.zh-CN.md) | 指纹/相机/快充/Waydroid 细节 |
| [`docs/display.md`](docs/display.md) | 显示结论与判读陷阱 |
| [`docs/AUDIO.zh-CN.md`](docs/AUDIO.zh-CN.md) | 外放 TDM |
| [`docs/kernel-v73-divergence.md`](docs/kernel-v73-divergence.md) | 相对主线 v7.3 的偏离与 7.4 决策 |
| [`docs/archive/`](docs/archive/) | 冻结的历史取证（不是任务） |

## 铁律

1. 内核只在 GitHub Actions 编译；本机不做 `make`/交叉编译。
2. 不执行 `git push`；本地提交后把 SHA 与命令交给用户。
3. ROM 输入只用本机 `V14.0.9.0.TMYCNXM`；OS2 是参考项目的 ROM。
4. 文档只维护中文；英文版已删除，不再生成。
