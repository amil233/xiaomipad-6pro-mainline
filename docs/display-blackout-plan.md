# 显示黑屏：现状梳理与排查方案（按 skill 标准化流程）

本文按 `android-mainline-port` 的"排查故障"流程组织：先按
`experience/patterns.md` 判类，按类别的"通用处理"排查，再用
`experience/display.md` 的条目定位具体判据。目的是把当前工作从
"逐寄存器猜测"改成"取证 → 差异 → 单变量实验"。

## 1. 流程位置

skill 第 4 步（点亮与内存桌面）之"原生接管"，sub-step 1（黄金快照）与
sub-step 5（先在固件刷新率下完成接管）未完成；验收标准未达成。

## 2. 现象（版本钉死）

- 内核：`7.0.14-gb684020b832f`（`liuqin-7.0`，b684020b832f），RAM 启动，
  `repack/b684-boot/boot-liuqin-firstboot.img`。
- 现象：接管后全黑（有背光，亮度 100→1500 可见变化，见
  `migration-7.0.md` 首测记录）。
- DRM 侧全绿：connector connected/enabled、mode 1800x2880、DPMS On、
  `/sys/kernel/debug/dri/0/state` 里 plane-0→crtc-0，DPU multirect 双
  900x2880 分发两路 DSI。
- 往 `/dev/kmsg` 写字：面板无任何文字（扫描出的流没被面板显示）。
- 硬件侧：INTF_1/INTF_2 `TIMING_ENGINE_EN=1`，`FRAME_COUNT` 以 ~121 fps
  增长；SSPP/LM/PP/CTL/DSC 编程值齐全（详见 §4 第 6 条）。

## 3. 判类

| 依据 | 结论 |
|---|---|
| `patterns.md` | 主类 **B（资源/所有权）+ C（时序与生命周期）**；已两次踩 **E（测量方法本身错了）**；潜在 **H（别人的实现不能整搬）**（6.17 的 CSOT 验证机 ≠ 本机天马） |
| `display.md` | 命中"**软件状态全部正常，屏幕却是黑的，被误判为已点亮**"；其"怎么确认"要求：全黑先查背光 → **把厂商显示驱动源码逐项对完** → 再做黑盒二分 |
| `display.md` 验收条款 | "没有欠载和 DSI 错误"；实测 `dsi_err_worker status=4/5` ⇒ 按该条**判失败**，不得记作通过 |

按 `display.md` 的顺序，背光已排除（§4.1），因此下一个规定动作不是继续
读寄存器，而是"厂商源码逐项对照"与"厂商黄金快照 diff"。

## 4. 已排除（每条带版本与证据）

| # | 假设 | 结论 | 证据 |
|---|---|---|---|
| 1 | 背光总使能未写 | 排除 | ktz8866 注册成功，100→1500 可见变化（`migration-7.0.md` 首测记录） |
| 2 | mdss probe 失败（ubwc 机器表） | 排除 | `d24eb13a3854`；probe 返回 0，`/sys/class/drm` 有 card0/DSI-1 |
| 3 | 面板 init 序列用错模块（CSOT vs 天马） | 排除为"唯一病因" | `df7a67b4b081` 按 cmdline 选天马序列（216 包逐字节翻译），仍黑 |
| 4 | mode_flags（LPM/BURST/NON_CONTINUOUS） | 排除为"唯一病因" | `b684020b832f` 改为 `VIDEO｜VIDEO_BURST｜LPM`、去 `NON_CONTINUOUS`，仍黑 |
| 5 | 供电轨/偏置（VSP/VSN/KTZ8866 bias） | 排除 | 电源轨审计；ktz8866 `enable-lcd-bias` 生效，亮度可调 |
| 6 | DPU 管线编程错误 | 排除 | `SSPP_MULTIRECT_OPMODE(0x170)=0x3`；RECT0 src(0,0)/RECT1 src(900,0)；XRGB8888、STRIDE 7296、SRC0_ADDR=0x3000；LM OUT_SIZE=900×2880；CTL_0 `INTF_ACTIVE=0x06`、`DSC_ACTIVE=0x03`；INTF 帧计数 121 fps |
| 7 | SMMU/IOVA 缺页 | 排除 | dmesg 无 SMMU fault；fb IOVA 0x3000 落在已映射区间 |
| 8 | 时序/DSC 参数与厂商 DT 不一致 | **本机与厂商 DT 逐项相等** | 见下表（本次新增，代码级确定性比对） |

### 4.8 参数比对表（厂商 DTBO `fragment@87`（天马 m81_36_02_0a）vs 主线驱动）

| 项 | 厂商（`repack/e15.dts:11087-11230`） | 主线（`panel-novatek-nt36532.c:647`） | 判 |
|---|---|---|---|
| panel-width / height | 0x384=900（每链路）/ 0xb40=2880 | hdisplay 1800（双链路合计）、vdisplay 2880 | 等价 |
| hfp / hpw / hbp | 100 / 2 / 46 | 200 / 4 / 92（合计口径） | 等价（每链路 1048） |
| vfp / vpw / vbp | 26 / 2 / 214 | 26 / 2 / 214 | 相等 |
| htotal / vtotal | 1048×2 / 3122 | 2096 / 3122 | 相等 |
| framerate | 0x78=120 | 120 | 相等 |
| panel-clockrate | 0x3c061800 = 1 007 032 320 Hz | 由 pclk×DSC 推算，实测 PLL 1.007 GHz | 相等 |
| DSC slice | 0x1c2×0x14 = 450×20，slice-per-pkt=2 | 450×20，slice_count=2 | 相等 |
| bpp / bpc / block-pred | 8 / 8 / enable | 8 / 8 / enable | 相等 |
| traffic-mode | burst_mode | `VIDEO_BURST` | 相等 |
| clock 连续性 | 无 non-continuous 属性（连续） | `NON_CONTINUOUS` 已去掉 | 相等（b684 之后） |
| on-command-state | dsi_lp_mode | `MIPI_DSI_MODE_LPM`（另有运行时 LPM 切换，`:809/:896`） | 相等 |
| **DSC slice-per-pkt** | **2** | **主线 `dsc_slice_per_pkt ?: 1` → 1**（`dsi_host.c:939`） | **差异，未判责** |
| phy-timings | `[00 22 08 09 19 23 09 09 09 02 04 00 1c 0e]` | 由 `dsi_phy_7nm` 按 1.007 GHz 自算 | **未逐值比对** |
| phy-voltage | 0x51（厂商索引，两模块相同） | 主线不消费，用固定 regulator | 未消费项，列入快照范围 |

## 5. 未排除：按物理层从下往上

| 层 | 已知 | 未知（决定性问题） | 怎么测（规定动作） |
|---|---|---|---|
| L1 面板 | 供电正常、init 216 包已按 LP 发送 | 面板是否真的退出 sleep / display-on 被接受 | **DCS 读回**（skill 举例 DCS 0x0A）→ 需原厂侧通道（W3） |
| L2 DSI PHY | PLL 锁 1.007 GHz；byte/esc/pclk 时钟使能 | PHY 是否进入 HS，lane 是否真在传输 | `LANE_STATUS`/`CLK_STATUS` 受采样时刻影响（class E），单点读数不可作证 → 用 W3 的厂商快照对照 |
| L3 DSI 引擎 | `DSI_CTRL=0x1F3` = ENABLE(0)+**VID_MODE_EN(1)**+LANE0-3(4-7)+CLK_EN(8)，即视频模式已使能（见 §9.1 更正） | 视频引擎是否 `STATUS0.VIDEO_MODE_ENGINE_BUSY`、`FIFO_STATUS` 是否欠载 | 与 L2 同一批快照 |
| L4 DPU 记账 | `INTR_EN=0`、`/proc/interrupts` 无 GIC 83 行、`INTR_STATUS` 有 vsync pending | 与"无画面"是否有关 | **与黑屏无因果链**（硬件自走扫描）→ 降级为独立技术债，点亮后单变量核查 |

## 6. 方案：三条工作流

### W1 参数级确定性比对（离线，本次收尾）

- 范围：上述表中两项未闭合项——**DSC slice-per-pkt** 与 **PHY timing 表**。
- 方法：不看设备。把主线在 1.007 GHz 下算出的 PHY lane timing（
  `dsi_phy_7nm` 的 clk_pre/clk_post/hs_zero/hs_exit/…）与厂商 14 字节表
  逐字段换算比对；slice-per-pkt 的语义从厂商驱动源码确认（W2）。
- 判据：每项要么相等/等价，要么给出"差异会导致什么"的可证伪说明。
- 产出：§4.8 表补全。
- 预算：0.5 h。

### W2 厂商显示驱动源码逐项对照（离线，可与 W3 并行）

- 输入：小米开源内核（liuqin/sm8450）的 `techpack/display/msm/`（
  `dsi/dsi_panel.c`、`dsi/dsi_display.c`、`dsi/dsi_host.c`、`dsi/dsi_phy_7nm*.c`、
  `msm/sde_encoder*.c`、`sde_crtc.c`）。
- 对照点（只对照"会导致无显示"的项）：
  1. 视频模式启动序列：CTL flush → INTF 使能 → DSI 视频引擎使能 → 面板
     display-on 的**顺序与时机**；
  2. 双 DSI 主从：master/slave 的 sync、`qcom,sync-dual-dsi` 的握手点；
  3. DSC packing（slice-per-pkt 的寄存器编码与 PPS 字段）；
  4. PHY 1.007 GHz 的 lane timing 表；
  5. 面板 on/off 与 DPU 使能的先后（skill"熄屏后再亮屏失败"条目的判据）。
- 判据：每条差异标注"会导致无显示 / 不会"；**只把"会导致无显示"的进候选**。
- 产出：候选差异清单（附源码行号），供 W3 快照验证。
- 预算：2–4 h（取决于是稀疏取文件还是浅克隆）。

### W3 原厂黄金快照（真机，信息量最高，d24eb13 那次之后一直缺这一步）

- 目的：拿到"厂商驱动点亮本机面板时的运行时寄存器/PPS/时钟树"，与我方
  同一位置快照做 **diff**，把"猜"变成"看差异"。
- 做法：`fastboot boot` 打过 Magisk 的原厂 `boot.img`（**只 RAM 启动，
  不写任何分区**，可回），`adb root` 后采集：
  - `ls /sys/kernel/debug/`（先发现厂商节点名，不预设）
  - DSI0/DSI1 的 dsi debugfs dump、PHY 状态、`clk_summary` 显示子树
  - 面板 DCS 读回（电源模式 0x0A）
  - `cat /proc/interrupts | grep -i mdss`（顺带解掉 §5 L4 的悬案）
- 判据：与我方运行时快照的 diff 必须为空或可解释；**第一条不可解释的
  差异即根因候选**。
- 预算：1 个真机会话（1–2 h）。

### 顺序与门控

W1（本次，离线）→ W2（离线，出候选清单）→ W3（真机窗口，拿 diff）→
按 diff 出**单变量补丁** → 一次 CI → 复测。
W3 的 diff 未到手前，不再做"读一个寄存器猜一个原因"的探测。

## 7. 候选补丁（只在对应证据出现时才做，且一次一个）

| 触发证据 | 候选改动 | 风险 |
|---|---|---|
| 厂商源码确认 slice-per-pkt 影响解码 | 面板 DT/驱动补 `dsc_slice_per_pkt=2` | 低，可回；但**必须先证明语义**再改 |
| PHY timing 逐值比对出现偏差 | 校正 PHY timing 计算或引入厂商表 | 中，影响所有面板 |
| W3 快照显示视频引擎启动顺序不同 | 按 diff 调整 encoder/DSI 启动顺序 | 中，牵涉 commit 路径 |
| 面板 DCS 0x0A 显示仍在 sleep | 回到 init 序列/时序，但要按 diff 定位具体包 | 低 |

## 8. 停止条件与记录纪律

- 同一失败第二次出现即停（已执行一次：df7a67 之后转物理层取证）。
- 每次只改一个变量；b684 同时改了三项（BURST/LPM/NON_CONTINUOUS），
  后续补丁不得重复这种打包。
- 每个补丁必须能指回 W2 清单或 W3 快照中的一条差异，否则不提交。
- 结论变化当天更新本文与 `migration-7.0.md`；失败记录不删。

## 9. 本次纠正的旧结论

### 9.1 `DSI_CTRL=0x1F3` 的解码

`dsi.xml` 定义：ENABLE=0、**VID_MODE_EN=1**、CMD_MODE_EN=2、
LANE0-3=4-7、CLK_EN=8。`0x1F3 = 0b1_1111_0011` ⇒
ENABLE + **VID_MODE_EN** + 四条 lane + CLK_EN，即**视频模式已正确使能**，
不是命令模式。此前"命令模式/模式位存疑"的推断作废。

### 9.2 "6.17 在本机同样黑 ⇒ 非 7.0 回归"不成立

6.17 的面板驱动**根本没有天马 init 序列**（`liuqin-6.17` 的
`panel-novatek-nt36532.c` 只含 CSOT 序列；天马序列由 `df7a67b4b081` 新增，
`pipa_tm_desc` 亦然）。因此 6.17 在本机的失败是"给天马面板发 CSOT 初始化"
的必然结果，属混杂变量，**不能据此排除 7.0 回归**。该条从"已排除"移入
"未验证"。

### 9.3 DPU 中断（INTR_EN=0 / GIC 83 未见）

这是记账层异常，与"硬件扫描但面板不显示"无因果链（INTF 帧计数与 DSI
传输都不依赖该中断）。降级为独立技术债，点亮后单独单变量核查；不并入
本次根因链。

## 10. 需要用户决定

1. **W3 是否执行**：用 `fastboot boot` 启动打过 Magisk 的原厂 `boot.img`
   取黄金快照（不刷写分区，重启即回）。这是 skill 早该做而一直缺的一步，
   也是把排查从"猜"变"diff"的关键。
2. **W2 是否允许联网取源码**：小米开源内核仓库较大，只稀疏取
   `techpack/display/` 与相关 DT。
