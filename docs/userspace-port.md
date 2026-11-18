# 用户态：从参考项目 v0.6.0 到 v0.8.0 的取舍清单

> **状态：提案，未决策。** 本文不是排期表，只是把"换新的有什么用、代价是什么"
> 摊开，供对照实机症状逐项打勾。任何一项动工前，先回到
> `STATUS.zh-CN.md` §3 与 `AGENTS.md` §1。

## 0. 三个前提

1. **两侧的数据源不同。** 我们的包是「v0.6.0 的代码 + `V14.0.9.0.TMYCNXM` 的
   数据」，参考项目 v0.8.0 是「v0.8.0 的代码 + `OS2.0.6.0` 的数据」。凡读 ROM
   数值或充电/电池语义的，不能照抄。
2. **内核侧已经证明过不能照抄一次。** v0.8.0 的电池属性表在 `c03e10` 上被整批
   回退（`STATUS` §4）。用户态里同源的 `charge-policy` 必须先取证。
3. **只能成套升。** `liuqin-device` 元包依赖 `= <version>`；两个 divert 二进制
   （`/usr/bin/gnome-control-center`、`/usr/libexec/iio-sensor-proxy`）随包冻结。

## 1. 批次 A —— 体验补（0.2，低风险）

| 项 | 参考项目出处 | 作用 / 现在缺什么 | 依赖 | 风险 |
|---|---|---|---|---|
| 时钟下限 | `gnome-overlay/usr/local/libexec/liuqin-clock-floor`、`fake-hwclock-load.service.d` | 无 RTC 时 fake-hwclock 把时间往回调；会影响 TLS、日志时序 | 无 | 低 |
| WLAN 竞态 | `liuqin-wlan-mac` 的 udev 等待、`liuqin-wlan-mac.service` | netdev 早于 udev 改名时 MAC 下错接口；`NetworkManager` 是 `Requires=` 它，竞态直接表现为没 WiFi | 无 | 低 |
| 电源键回睡 | `liuqin-power-key-action` 的 `resuspend` + `liuqin-power-keyd.c` | 后台唤醒后不等 GNOME 的 15 分钟，直接回睡 | 需重编一个 C | 低 |
| 键盘布局 | `gnome-overlay/usr/libexec/liuqin-keyboard-layout`、两个 `set-debian-keyboard` | 初次设置/设置面板把布局落成 Debian 变体 | 无 | 低 |
| 会话音频时序 | `org.gnome.Shell@.service.d/50-liuqin-audio.conf`、`session-audio-condition`、wireplumber greeter drop-in | 登录界面/首会话时 PipeWire 抢设备的时序 | 无 | 低 |
| 物理平台标识 | `platform/liuqin-physical-platform` + unit | 让 systemd/GNOME 不把真机当虚拟机 | 需确认 `systemd-detect-virt` 在本机返回 none | 低 |
| OSK guard 扩展 | `liuqin-osk-guard@io.github.liuqin` | 修 GNOME 50 `maybeHandleEvent` 在触摸释放时抛 null 错。**不是"熄屏后键盘唤不出"的解**——那条已撤销 | `gnome-shell` 必须为 50 | 低 |

验收：冷启动 3 次；WiFi 每次起；电源键短按/长按；时间不倒退；登录界面有声。

## 2. 批次 B —— 传感器（0.3，需重建 sensors-stack）

| 项 | 参考项目出处 | 作用 | 依赖 | 风险 |
|---|---|---|---|---|
| hexagonrpc 补丁 | `sensors/hexagonrpc/patches/`（5 个） | 类型序列编组、非对齐元数据、大输入、registry 错误应答 | 与我们现有 2 个补丁重定基 | 中 |
| libssc 补丁 | `sensors/libssc/patches/`（4 个） | 运行时选择 stream 投递/批处理，按传感器类型选 stream | 同上 | 中 |
| iio-sensor-proxy 补丁 | `sensors/patches/0001/0007/0008/0009` | 等待发现通知、串行化 light 轮询、上报 discovery 错误、close 前静默回调 | 与现有 4 个补丁重定基 | 中 |
| 环境光 | `sensors-overlay/.../80-liuqin-fastrpc.rules` 加 `ssc-light` | **自动亮度**（你现在没有） | 先确认 V14 配置里有 ALS：设备上 `ssccli --sensor=light` | 中 |

验收：重启 10 次 `accelerometer-ready` 全部成功；自动亮度可用；
`journalctl -u iio-sensor-proxy` 无重复报错。

## 3. 批次 C —— 充电/电池（0.4，最高风险）

| 项 | 出处 | 作用 | 依赖 |
|---|---|---|---|
| 充电采样与指示灯 | `charge-policy/*` | 面板显示实时功率/充电细节（GNOME 50 扩展）；插入电源时保持唤醒 | `qcom-battmgr-{bat,usb}`、`qcom-battmgr-charge` wakeup 源 |
| MiPPS 认证改造 | `gnome-overlay/usr/local/libexec/liuqin-mipps-auth`（约 480 行） | 认证失败即闭闸、按 kernfs 设备识别伙伴、只读 6 Pro 面板可见的固件节点 | 7.3 的 `xiaomi` 属性组 |
| 认证拆分 | `liuqin-mipps-auth.service`、`liuqin-mipps-battery-auth.service` | 电芯认证与适配器认证解耦 | 同上 |

**先决条件**：在 `c03e10` 上逐项读一遍上述节点并做功率对照（原装 67W / PPS /
PD / 电脑口）。没有这张表不动工。

## 4. 明确不取

| 项 | 原因 |
|---|---|
| `liuqin-switch`、`switch-common.sh`、重启到 Android 入口 | A 槽直启、无 Android |
| KSU 模块（`android/ksu-boot-ubuntu`） | 同一原因 |
| `charger-mode` 动画/认证 UI | 与启动方式无关；只有"关机充电屏"值得单独再看 |
| `mainline-release-notifier` | 提醒上游有新版本，价值极低 |
| firefox 的 snap 移除/apt 源改造 | 发行版策略，容易帮倒忙 |
| `liuqin-devmode` | 已有 initramfs telnet 救援；需要常驻 USB SSH 时再取 |
| 删除 `liuqin-gnome-usb-rescue` / `liuqin-rescue` | 参考项目 v0.8.0 删了，我们的救援链还在用 |

## 5. 构建前置（本机现状）

- `out/liuqin-debs/` 目前只有 `liuqin-kernel_0.1_arm64.deb`，其余三个包要重打。
- `device-support` 在 overlay 带 `power.gschema.xml` 时**强制要求** g-c-c 电源面板
  二进制（`build-liuqin-debs.sh` 的 `POWER_SETTINGS_BINARY`）。没有就先重建
  g-c-c，或临时从 overlay 去掉该 gschema。
- `sensors` 需要 `sensor-stack.tar` 与 V14 的传感器提取物；本机
  `tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/` 只有 `analysis`。可从设备回捞
  `/usr/share/qcom/sm8450/Xiaomi/liuqin/sensors/`。

## 6. 升级注意事项

- 版本整套 bump（`0.1` → `0.2`），元包 `= 0.2`；保留 `0.1` 的 deb 作回滚。
- 旧版本没有的 unit，降级后 `deb-systemd-helper` 会记住"管理员禁用"，再升回来
  仍是关的（参考项目 `9fae989` 就是修这个）。我们的包没有这层 prerm 处理，
  升级后要 `systemctl list-unit-files 'liuqin-*'` 对一遍。
- 一次只改一批，冷启动验证；记录镜像/包 sha256。
