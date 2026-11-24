> 归档于 2026-11-24：这是当时的记录，不再维护；当前状态见 [../STATUS.zh-CN.md](../STATUS.zh-CN.md)。\n\n# 功能细节：指纹 / 相机 / 快充 / Waydroid

> 状态以 `STATUS.zh-CN.md` §5 为准。本文只保留设备特定细节，不重复状态表。
> 参考项目（`liuqin-6.17test`，6.17 + OS2.0.6.0）的旧说明在
> `docs/archive/reference-v0.6.0/`，不能当成本机结论。

## 1. 指纹（🧪 未验证）

- 硬件/软件栈：FPC1264 + `libfprint` TOD + `fprintd`，原生 GNOME 设置页录入；
  用户态仍是参考项目 v0.6.0 形态（`0.1` 包，`apt-mark hold`）。
- 参考项目在 **6.17 内核 + 其用户态**上验证过同指通过、异指拒绝、锁屏与
  重启后登录；**本机 7.3 内核没有重测**。不要写"✅ 可用"。
- 本机要验证时：
  1. 确认 `liuqin-fingerprint` 包与当前内核模块匹配（`/usr/lib/modules/$(uname -r)`）；
  2. 冷启动后看 `fprintd` 与内核日志有没有 probe/传输错误；
  3. 在「设置 → 用户 → 指纹登录」录入一枚，锁屏验证同指/异指；
  4. 通过后把证据（内核 tip、包版本、日志）写回 STATUS，才升级状态。
- 已知边界（参考项目记录，未在本机复核）：限首个本地账号（UID 1000）、
  一枚指纹；模板与凭据不能跨设备复制。
- 不要在 7.3 上直接套用 6.17 的模块哈希或旧 deb。

## 2. 相机（🧪 未验证）

- 硬件：后摄 Samsung S5KJN1（5000 万像素）；前置未启用。
- 驱动：`qcom-camss`（`qcom,sm8475-camss`，用到 CSIPHY3/CSID0/IFE0）、
  `camcc-sm8450`（`qcom,sm8475-camcc`）、`i2c-qcom-cci`、`s5kjn1`；
  `libcamera` 软件 ISP 在 CPU 上做图像处理，无自动对焦、无硬件编码。
- 已验证的范围仅限：用 `fastboot boot` 临时启动相机内核，10 次采集启停、
  300 帧 RAW、Snapshot 拍照/10 秒录像/回放。**本项目完整镜像没有带相机启动过**。
- 本机的 camcc GDSC 修复已在 7.3 树（`66f4fbf82d26`）；要复测还需要：
  1. 去掉 `/etc/modprobe.d/liuqin-camcc.conf`（它会把 camcc 挡在模块裁剪之外）；
  2. 用完整镜像冷启动，确认 `media-ctl`/`cam` 能看到 sensor 与 ISP；
  3. Snapshot 预览、拍照、录像各跑一遍；
  4. 记录内核 tip 与镜像 sha256 到 STATUS。
- 不要因为"参考项目支持后摄"就把本机标成可用。

## 3. 快充（部分验证）

- 充电功率由 ADSP 充电固件协商；小米私有认证在用户态完成。
  内核通过 PMIC GLINK 电源设备导出 `xiaomi` 属性组：
  `/sys/devices/platform/pmic-glink/pmic_glink.power-supply.0/xiaomi/`。
- 已验证（参考项目在本机同类硬件上的记录）：`xiaomi` 属性可读、双电芯
  电量计认证通过；认证后标准 PD 适配器可到 9 V / 2 A。
- **未验证**：MiPPS 适配器认证、标准 PPS 开关、67W 原装适配器的实际功率。
  要验收需分别用支持 MiPPS 的小米适配器与 PPS 适配器实测，并记录
  `fastchg_mode`、`power_max`、`real_type` 与功率计读数。
- 非小米适配器默认停在 9 V；`10-allow-unverified-adapter.conf` 会为满足
  条件的 PPS 合同置位 `pd_verifed`，但这属于未验收路径。
- 不要在没有 V14 节点读数的情况下照抄参考项目的属性号或换算系数。

## 4. Waydroid（🧪 未验证）

- 内核配置已包含 Binder/binderfs、IPv4/IPv6 策略路由（FIB rules）、PSI、
  memfd、network namespace、cgroup freezer、veth 模块
  （`device/configs/liuqin-waydroid.config` 等）。
- 这些选项会改变 `struct net` 布局：换内核时必须 **Image + modules 一起换**，
  只刷 Image 会让旧模块用错结构偏移。
- 安装（需要联网，镜像约 1 GB）：

```sh
sudo apt update
sudo apt install waydroid
sudo waydroid init
sudo systemctl enable --now waydroid-container
```

- 状态：**未做整机验收**。相机/麦克风/传感器等依赖厂商 HAL 的功能不可用；
  图形走 Mesa/Freedreno；不要把它写成本机已支持。
