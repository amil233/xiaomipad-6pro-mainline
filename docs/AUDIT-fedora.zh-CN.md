# Fedora 线改动审计（逐文件，2026-11-27）

每条非显然的决定都写明依据。依据分三类：

- **源码**：工作区里的内核或组件源码，可直接核对；
- **上游文档/默认值**：组件的 `--help`、`meson_options.txt`、安装脚本；
- **待验证**：目前只有推理，设备上尚未证实——列出来是为了不被当成事实。

## 新增脚本

| 文件 | 关键决定 | 依据 | 状态 |
|---|---|---|---|
| `tools/fedora-container.sh` | 用 `fedora:45` 容器跑 rpmbuild/dnf；`--platform` 钉架构，容器内再核 `uname -m` | GitHub 没有 arm64 的 Fedora runner；容器是原生 aarch64 | 已验证（多次 run 成功） |
| `tools/build-liuqin-fedora-base.sh` | 从 Live ISO 的 `LiveOS/squashfs.img` 取根；按魔数判 squashfs/EROFS/ext4；EROFS 用 loop 挂 | Fedora 42 起 Live 媒体改 EROFS（fedora wiki Changes/EROFSforLiveMedia）；镜像内结构以实际 ISO 为准 | 已验证（run 成功） |
| `tools/build-liuqin-kernel-rpm.sh` | 一个 `kernel-liuqin` 包；Version/Release 从 `uname -r` 拆开（RPM 不允许 `-`）；`Provides: kernel-uname-r` | RPM 字段限制；Fedora 包约定 | 已验证 |
| `tools/build-liuqin-device-rpm.sh` | 固件 + WLAN tuple + UCM2 + 救援通道；不搬 gnome-overlay | Ubuntu 线同类内容 + 桌面差异 | 已验证 |
| `tools/build-liuqin-fedora-rootfs.sh` | 目标布局 `/usr/share/qcom/sm8450/Xiaomi/liuqin`；`sensors/registry`、`socinfo` 做软链；fastrpc 账户离线创建 | `hexagonrpcd --help`（默认 `/usr/share/qcom/`）与 `rpcd.c` 的自动探测；Ubuntu 线同布局 | 布局已按源码修正；软链待设备确认 |
| `tools/build-liuqin-fedora-boot.sh` | 无契约、无哈希清单；`EXPECTED_RELEASE` 钉内核版本 | 让 boot.img 与 root 的版本绑定，取代旧的文件清单机制 | 已验证（boot.img 生成且能启动） |
| `tools/build-liuqin-fedora-image.sh` | ext4 + `LABEL=LIUQIN_ROOT` + `native-root/` | 原厂分区表与 initramfs 布局 | 已验证（真机可启动） |
| `tools/build-liuqin-sensors-rpm.sh` | 三个组件按依赖顺序编；`libssc` 装两遍（容器 + staging）；文件清单从 staging 生成 | `meson` 依赖关系、`%files` 时序问题 | 编过；打包待确认 |
| `tools/lib/rootfs-manifest.sh` | 批量哈希（一次 `find` + 一次 `xargs sha256sum`） | 旧实现每文件 fork 一次，13 万文件约 6 分钟 | 已验证（本机测量） |
| `initramfs/init` 的准入 | 只判：marker、systemd、`ID=fedora`、`kernel.release` 与 boot.img 一致 | 本分支只服务 Fedora；版本钉住是"两个一起刷"的执行方式 | 已验证（真机启动） |

## 上游行为（读源码确认，不是猜）

| 事项 | 结论 | 出处 |
|---|---|---|
| `/dev/fastrpc-*` 的 udev 属性 | `SUBSYSTEM=="misc"`，名字 `fastrpc-<domain>[-secure]` | `drivers/misc/fastrpc.c:2468-2473`（`misc_register`） |
| `hexagonrpcd` 的 `-R` 默认值 | `/usr/share/qcom/`，并自动探测 `{soc}/{vendor}/{codename}` | `rpcd.c:79`、`rpcd.c:275,324` |
| 固件的虚拟目录 | `<prefix>/sensors/{registry,sns_reg.conf,sns_reg_version,config}`、`<prefix>/socinfo`、`<prefix>/acdb` | `rpcd_builder.c` 的 `construct_root_dir` |
| iio-sensor-proxy 的安装内容 | unit、bus policy、udev 规则、polkit 策略都由上游 `meson install` 装 | `data/meson.build`、`meson_options.txt:systemdsystemunitdir` |
| 属性白名单 | 该检查没有任何安全收益（函数只返回空串），只有丢传感器的副作用 | `sns_registry.c` 补丁实现 |

## 仍然只有推理、必须验证的

| 假定 | 风险 | 怎样才是可信的验证 |
|---|---|---|
| 校准文件 `acc_caldata.txt` 等要放在 `<prefix>/sensors/` 下 | 放错位置等于没导 | 需要设备上跑一次；或从固件侧文档/反汇编确认路径 |
| `sns_reg_version` 内容格式（我手工造的 `version=12\0`） | 格式不对会被固件拒绝 | 需要真实样本；目前 persist 里没有 |
| `fastrpc` 用 201–999 的第一个空位 | 若 Fedora 系统号段不同会越界 | 查 Fedora `setup` 包的 `SYS_UID_MIN/MAX`（本机无 Fedora root） |
| 清空 `/boot` 与移除 Fedora `kernel*` 包不影响其他服务 | 可能有 unit 引用 `/boot` | 设备上 `systemctl --failed` |
| 移除 Fedora `iio-sensor-proxy` 包后 `dnf upgrade` 不会装回来 | 升级后可能被换回 | 设备上 `dnf upgrade` 后 `rpm -q` |

## 已删除的 Ubuntu 线内容

`build-liuqin-{boot,rootfs,debs,native-root,rootfs-image,settings,ubuntu-desktop-rootfs,rescue-boot}.sh`、
`build-liuqin-image.py`、`prepare-image-inputs.py`、`build-root-contract.py`、Ubuntu 的
`rootfs.yml`，以及对应的 7 个测试。理由：这条分支只装配 Fedora，保留它们会让
"哪套布局是对的"变得含糊。
