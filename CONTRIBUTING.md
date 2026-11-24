# 参与贡献

本仓库只维护 **Xiaomi Pad 6 Pro（liuqin，128G）** 的本机状态，工作分支是
**`liuqin-install`**（与内核仓的 `liuqin-7.3` 区分开）。`main` 只保留 2026 年从参考项目 v0.6.0 分出来时的历史骨架，
不再接受更新。

## 范围

- 内核改动在内核仓 `linux-sm8450-liuqin` 的 `liuqin-7.3` 分支；本仓库只放
  设备配置、用户态适配、构建/安装工具、initramfs 与文档。
- **不要提交 Android/双系统相关内容**：Android 资产、KernelSU 回切模块、
  `liuqin-switch` 已移除；参考项目式的安装器（`installer.img` / `install.py` /
  `--layout dual`）已整体移除，不再实现设备端安装流程。上机只保留两条 fastboot：
  `boot.img → boot_a`、`rootfs.img → userdata`（原厂单块数据分区）；rootfs
  镜像在刷机主机上由 `rootfs.tar.gz` 生成（`tools/build-liuqin-rootfs-image.sh`）。
- ROM 输入只用 `V14.0.9.0.TMYCNXM`；不要引入 `OS2.0.6.0` 或其他版本的
  数值、固件或校验值。
- 文档只维护中文；英文版已删除。

## 提交

- 先取证再改：提交信息写清内核/镜像版本、证据位置、影响范围。
- 一个提交只做一件事；内核升级按"新分支 → merge → 解冲突 → CI → 刷机 →
  点亮才进下一级"。
- 本地提交即可，**不要 push**；把 SHA 和推送命令交给维护者。
- 文档改动同步更新 `docs/STATUS.zh-CN.md`（唯一状态源），历史文档只进
  `docs/archive/`。
