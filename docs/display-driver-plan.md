# liuqin 显示驱动总计划（7.0 主线）

> 目的：把"试一个、改一个"的循环，换成"分层定位 → 一次只改一层 → 用判据退出"的流程。
> 基线：kernel `liuqin-7.0` @ `3b7bf64894c2`、integration `main` @ `1245c30`。
> 采集镜像：`repack/oneshot-boot/boot-oneshot-3b7bf64.img`
> （sha256 `35d861d22f05cdcc14e2ea53919879fbdc975574b85d5c54b8ddb6157351ecef`，只用于 `fastboot boot`）。
>
> 原厂对照数据：`liuqin-vendor-check-20261028-022846.tgz`（原厂 V14.0.9.0 运行态，
> 抓取时面板在 50 Hz 正常显示）。

---

## 1. 完成定义

1. 天马 `m81_36_02_0a` 在 7.0 主线点亮：fbcon/DRM 客户端有画面，背光与亮度可控。
2. CSOT `m81_42_02_0b` 不回归（6.17 上已验证过的路径）。
3. 驱动不依赖诊断代码：`/sys/kernel/debug/*` 探针可以留作可选，但正常路径不依赖它。
4. 配置、文档、构建流程入库；RAM 启动与正常启动都能复现。
5. 60/90/120/144 刷新率切换不黑屏（与厂商支持的列表一致）。

## 2. 栈分层与每层的"正确"判据

| 层 | 代码 | 职责 | 可观测判据 |
|---|---|---|---|
| Panel | `panel-novatek-nt36523.c` | desc、时序、DSC/PPS、init、reset、供电 | 面板 DCS `0x45` 扫描行推进、`0x0A=0x9d` |
| DSI host | `msm/dsi/dsi_host.c` | 视频模式寄存器、PPS、lane | `CTRL/VID_CFG0/ACTIVE/TOTAL/CLKOUT` 与厂商一致 |
| DSI PHY | `msm/dsi/phy/dsi_phy_7nm.c` | lane 时序、PLL | PHY 寄存器一致、`CLK_STATUS` PLL 锁定位 |
| DPU 8.0 | `msm/disp/dpu1/*` | CTL/INTF/PP/LM/DSC/UBWC | `INTF_FRAME_COUNT` 推进、`CTL_TOP/INTF_ACTIVE/DSC_ACTIVE` 一致 |
| 时钟/PD/稳压 | `dispcc`、`gcc`、`rpmh` | pclk/byteclk/mdp、供电 | 频率与厂商一致 |
| DT/bootloader | `sm8475-xiaomi-liuqin.dts` | 面板节点、端口、供电 | probe 成功、面板型号选择正确 |

**定位原则**：每一层只对"它自己能证明的东西"负责。DPU 出帧不能证明面板收到；
DSI 寄存器正确不能证明面板解码。任何结论必须标注它停在哪一层。

## 3. 已确证的事实（证据索引）

| 事实 | 证据 |
|---|---|
| 面板、背光、供电、ABL 的 DSI/DSC 通路都能工作 | bootloader splash 正常显示 |
| 原厂运行态 50 Hz 的完整 DSI/PHY/SDE/时钟快照 | `liuqin-vendor-check-20261028-022846.tgz` |
| 厂商 `CTRL/ACTIVE_H/V/DSC/LANE_CTRL/CLK_STATUS` 与我们一致 | 归档 vs `dsi0/regs` |
| 厂商 `VID_CFG0` 是 burst、`CMD_DMA_CTRL=0xd4000000` | 归档；已在 `f5e92f4` 改 |
| DPU 在按 120 fps 出帧 | `INTF_FRAME_COUNT +121/s` |
| 面板 init 序列 216 包与 DTBO 逐字节相同 | `repack/e15.dts` vs 驱动 |
| 面板从未离开 idle（`0x9e`） | 旧驱动多次读数 |

## 4. 尚未确证（计划要消灭的未知）

| # | 未知 | 对应的采集 |
|---|---|---|
| 1 | 面板是否在扫我们的帧 | `nt36523/state` 的 `advancing` |
| 2 | 同模式下我们的 DSI 是否与厂商逐值一致 | 完整 `dsi0/regs` vs 归档（模式需可比） |
| 3 | DPU `CTL_TOP/INTF/DSC` 与厂商的差异 | `bundle` vs `sde_top/sde_ctl` |
| 4 | 我们发出的 PPS 与厂商 DSC 参数是否一致 | `dmesg` 的 `pps:`/`dsc:` |
| 5 | PHY lane 时序是否一致 | `phy0/phy1` vs 归档 |
| 6 | 面板是否需要 DT 之外的初始化 | 点亮后再查 |

## 5. 定位判定树

```
P0 采集（一次镜像，全部单元）
        │
        ├─ Q1 面板扫描行推进？
        │      │
        │      ├─ 否 → 链路分支 L
        │      │      L1 DSI 控制器：同模式逐值对照（先解决模式可比性）
        │      │      L2 PHY：lane 时序/PLL 锁
        │      │      L3 时钟：pclk/byteclk/mdp 与厂商比值
        │      │      L4 DSC 使能顺序：PPS 与 compression mode 的时序/通道
        │      │
        │      └─ 是 → 内容分支 C
        │             C1 PPS/DSC 参数（slice/bpp/bpc/块预测/版本）
        │             C2 像素格式/UBWC/stride
        │             C3 DPU CTL/INTF 路由与打包
        │             C4 面板解码（DSC 版本、slice 排布、双 DSI 分半）
        │
        └─ 每步只允许改一层，改完用同一套采集复测
```

## 6. 阶段计划

### P0 采集（就绪，一次启动）

- 输入：`repack/oneshot-boot/boot-oneshot-3b7bf64.img`，`fastboot boot`（不写分区）。
- 动作：启动后跑附录 A 的采集脚本，30 秒后再跑一次。
- 产物：`oneshot.txt`、`oneshot2.txt`。
- 退出条件：六个未知都有读数，不允许"某个节点没挂上"。

### P1 差异清单（不写代码）

- 输入：P0 产物 + 归档。
- 动作：把第 7 节的清单逐项填成"同/异/模式相关/无法比"。
- 退出条件：每个"异"都归属到唯一一层；若全部"同"而面板仍不扫，进入 P2-L4 或升级路径（第 10 节）。

### P2 修复（按分支，一次一层）

- L1：同模式对照。若 `TOTAL/CLKOUT` 之外仍有差异 → 改 `dsi_host.c`。
- L2：PHY 差异 → 改 `dsi_phy_7nm.c` 的 lane 时序表。
- L3：时钟比值不同 → 改 DT 的 `clock-frequency` 或时钟驱动。
- L4：PPS/压缩模式顺序 → 改 `nt36523_prepare` 的发送顺序。
- C1/C2：DSC/格式 → 改 desc 的 `dsc`/`format`。
- C3：DPU → 改 `dpu_encoder`/`dpu_hw_ctl` 的绑定配置。
- 每个改动：一个提交、一个假设、一个预期观测；不达预期立即回退。

### P3 点亮验证

- 面板 `0x45` 推进、`0x0A=0x9d`。
- fbcon 文字可见；背光随面板 enable 亮。
- 60/90/120/144 切换不黑。

### P4 清理与产品化

- 移除/收敛诊断代码（保留只读探针也可以，但默认路径不依赖）。
- 撤回 `CONFIG_CMDLINE_FORCE`（`1245c30`）。
- CSOT 回归；suspend/resume；ESD 恢复（如需要）。
- 文档与配置入库。

### P5 回归

- 6.17 对照、Ubuntu 桌面、长时间稳定性。

## 7. 每层必须匹配的清单（厂商值来自归档，50 Hz）

| 项 | 厂商值 | 我们的 | 状态 |
|---|---|---|---|
| DSI `CTRL` | `000001f3` | 同 | ✅ |
| DSI `VID_CFG0` | `02009230` | 同（burst 已在 desc） | ✅ |
| DSI `ACTIVE_H` / `ACTIVE_V` | `015c0030` / `0c1800d8` | 同 | ✅ |
| DSI `ACTIVE_HSYNC` | `00020000` | 同 | ✅ |
| DSI `TOTAL` | `15f30254` | `0c3101bf` | 模式不同，待同模式对照 |
| DSI `CMD_DMA_CTRL` | `d4000000` | 同（`f5e92f4`） | ✅ |
| DSI `LANE_CTRL` | `01000000` | 同 | ✅ |
| DSI `LANE_STATUS` | `00010100` | 需采 | 待对照 |
| DSI `CLKOUT` | `13e0391f` | `0000191f` | 模式不同 |
| DSI `CLK_STATUS` | `008047c3` | 同 | ✅ |
| DSI `DSC_MODE_CTRL` | `03840b01` | 同 | ✅ |
| PPS 128 字节 | 未采 | 本次采 | 待对照 |
| PHY 0x000–0x1ff | 归档有 | 本次采 | 待对照 |
| DPU `CTL_TOP` | `28000300` | 本次采 | 待对照 |
| DPU `CTL+0x20/+0x24` | `00033000` / `1` | 本次采 | 待对照 |
| DPU `sde_top+0x54/+0x58` | `40000002` / `40000000` | 本次采 | 待对照 |
| 时钟 | pclk 167.84 / byteclk 125.88 / mdp 375 MHz | 本次采 | 待对照 |

## 8. 变更纪律

1. **一次构建带全部单元**；不为单个读数单独构建。
2. **一个提交一个假设**；提交信息写清预期观测。
3. **先证据后改**；没有原始读数支撑的值不进代码。
4. **不写分区**：实验只走 `fastboot boot`；恢复/安装由用户按已验证流程操作。
5. 每次实验记录：假设、改动、预期、实测、结论（回填本文档）。

## 9. 不再重复的实验（negative list）

- `no_dsc`（旧驱动实现有缺陷）、`skip_panel_init`、link flags、clock lane LP。
- 写 `0x2a4..0x33c`（官方只写 `0x2a0`）。
- 关屏时读 `bundle`（会重启）。
- 手动 `fastboot flash boot*`（尾部/校验问题未明）。
- 改 vbmeta（危险，未验证）。
- 用 144 Hz 外推时序（DTBO 只有 120 Hz，144 未实测）。

## 10. 升级路径（所有寄存器都匹配但面板仍不扫）

1. 同模式（50 Hz）复测：排除时序/ porch 影响。
2. 检查 DCS 写入的通道与时机（PPS 在 init 之后、display-on 之前/之后）。
3. 检查双 DSI 分半与 DSC slice 排布。
4. 检查面板 reset/power 时序（reset 脉冲宽度、供电上升时间）。
5. 最后才怀疑面板固件差异（同型号不同批次）。

## 11. 里程碑

| 里程碑 | 判据 |
|---|---|
| M0 | P0 采集完成，六个未知都有读数 |
| M1 | 差异清单闭环，根因层唯一 |
| M2 | 面板 `0x45` 推进、`0x0A=0x9d` |
| M3 | fbcon 可见、背光正常 |
| M4 | 刷新率切换正常、诊断代码清理 |
| M5 | CSOT 回归、文档/配置入库 |

---

## 附录 A：P0 采集脚本

```sh
mount -t debugfs none /sys/kernel/debug 2>/dev/null

dump() { a=$1; n=$2; i=0
  while [ $i -lt $n ]; do
    printf '%08x %08x\n' $((a+i*4)) "$(devmem $((a+i*4)))"
    i=$((i+1))
  done; }

{
  echo "== uname ==";   uname -a
  echo "== cmdline =="; cat /proc/cmdline
  echo "== panel ==";   cat /sys/kernel/debug/nt36523/state
  echo "== dsi0 ==";    cat /sys/kernel/debug/dsi0/regs
  echo "== dsi1 ==";    cat /sys/kernel/debug/dsi1/regs
  echo "== dpu ==";     cat /sys/kernel/debug/dri/0/debug/bundle
  echo "== phy0 ==";    dump 0xae94400 128
  echo "== phy1 ==";    dump 0xae96400 128
  echo "== clk ==";     cat /sys/kernel/debug/clk/clk_summary
  echo "== reg ==";     cat /sys/kernel/debug/regulator/regulator_summary
  echo "== dmesg ==";   dmesg
} > /tmp/oneshot.txt 2>&1
```

30 秒后重复一次写入 `/tmp/oneshot2.txt`。
