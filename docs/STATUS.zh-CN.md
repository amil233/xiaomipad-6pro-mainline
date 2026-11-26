# 状态（2026-11-26，Fedora 分支）

这条分支做的是把平板从 Ubuntu + GNOME 换成 Fedora 45 KDE Plasma Mobile。**还没在
真机上启动过**，下面分开写"CI 上已经产出的"和"还没验证的"。

会变的数字（内核版本、镜像哈希）不写死，用命令现场查。

## 已经跑通的（都在 CI 上）

| 项 | 现状 |
|---|---|
| 取自 Live ISO 的根 | Fedora 45 KDE Mobile，ext4（ISO 里那层是 EROFS，解开就是根）；131,266 个文件、1713 个包、6107 MiB |
| 内核包 | `kernel-liuqin` RPM 装进树：756 个模块，树降到 5377 MiB（Fedora 自带内核和 `/boot` 已清掉） |
| 根整理 | marker、`machine-id` 清空、SELinux permissive，`native-root.hashes` 已生成 |
| 桌面 | `plasma-mobile 6.8.1`、`plasma-workspace 6.8.1`、`plasma-setup 6.8.1`、登录管理器 `plasmalogin` |
| boot.img / ext4 镜像 | 装配步骤已接入工作流，首次结果以最近一次 run 为准 |

## 还没验证的

| 项 | 状态 | 说明 |
|---|---|---|
| 真机启动 | 未验证 | 一次都没刷过；这是下一步 |
| 显示 / 触控 | 未验证 | 依赖主线内核 + Mesa，与 Ubuntu 线同一套驱动 |
| Wi-Fi / 蓝牙 | 未验证 | 地址来自 persist，需要跑 `provision-liuqin-from-persist.sh` |
| 音频 | 未验证 | 拓扑和 UCM2 的移植还没做，KDE 侧走 PipeWire |
| 传感器 / 电源键 / 指纹 / 相机 | 未验证 | Ubuntu 线那套设备载荷还没移植成 RPM |
| 首次设置 | 未验证 | 应当进 plasma-setup 建用户 |

## 已知问题 / 待办

| 项 | 现状 |
|---|---|
| 设备载荷没移植 | 固件、UCM2、传感器栈、电源键、指纹这些都还只在 Ubuntu 线的 deb 里 |
| SELinux | 先 permissive；策略和标签没打全之前不收紧 |
| 自动登录 | `etc/plasmalogin.conf` 里有 autologin 相关配置，树里没有人类账户，第一次启动走 plasma-setup，上机时确认 |
| 无 `/etc/fstab` | 根由 initramfs 挂好，systemd 不需要 fstab；确认没有服务因此报错 |
| 内核升代 | 现在跟主线 7.3；Fedora 45 自带的也是 7.3.6，同代 |

## 文档

| 文档 | 内容 |
|---|---|
| [`FEDORA.zh-CN.md`](FEDORA.zh-CN.md) | 换发行版的来龙去脉、五个阶段、还没确认的事 |
| [`BUILD.zh-CN.md`](BUILD.zh-CN.md) | 从 ISO 到可刷产物 |
| [`INSTALL.zh-CN.md`](INSTALL.zh-CN.md) | 刷机、更新、回滚 |
| [`RESCUE.zh-CN.md`](RESCUE.zh-CN.md) | initramfs 救援 shell、救援 boot.img 的生成 |
| [`archive/`](archive/) | 历史记录，不再维护 |
