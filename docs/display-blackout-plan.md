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

## 6.9 W1/W2 执行结果（2026-10-27）

两个检查脚本（主机侧，自带"故意注入一个错误必须被发现"的自检）：
`repack/verify-init-seq.py`、`repack/verify-phy-timing.py`。

### 结论 1（关闭）：天马 init 序列与厂商 DTBO 完全一致

- 216 包 vs 216 包，payload 与包间延时逐项相同（自检生效：翻转一个位即报
  mismtach）。此前"216 包逐字节翻译"的结论现在有了可复现的证明。
- 仅两处无害差异：`0x35`（SET_TEAR_ON）主线用长写带 `0x00` 参数、厂商用
  短写无参（视频模式不用 TE）；display-on 后主线等 40 ms、厂商等 20 ms
  （等待更长无害）。两者都不构成"无显示"，不列入候选补丁。
- 记录一次过程错误：初版脚本按行解析，漏掉跨行书写的那条 `0x91 …
  0x1a` 长写，误报"缺 3 包"。修正为按语句解析后差异消失。说明"检查器
  自身要有自检输入"这条纪律必要。

### 结论 2（新差异，已判级）：DSC slice-per-pkt 厂商 2、主线 1

CAF 源码（`caf-display/msm/sde_dsc_helper.c:588-614`、
`msm/dsi/dsi_ctrl_hw_cmn.c:428-475`）证实该属性决定 DSI 打包方式：

```
bytes_per_pkt = bytes_in_slice * slice_per_pkt
pkt_per_line  = slice_count / slice_per_pkt
```

写进 `DSI_VIDEO_COMPRESSION_MODE_CTRL(_2)` 的 PKT_PER_LINE / bytes_per_pkt。
主线 `dsi_host.c:939` 在面板未提供时用 1，故我们是"每包 1 slice、每行 2 包"，
厂商是"每包 2 slice、每行 1 包"。

按 `display.md` 的 DSC 条目，这类不一致的典型表现是**条纹/花屏/彩条**，不是
全黑。因此记为候选补丁（W3 快照确认后再落地），**不作为黑屏根因**。

### 结论 3（新差异，已判级）：PHY lane timing 14 项中 5 项不同

厂商 DTBO 的 `qcom,mdss-dsi-panel-phy-timings` 14 字节被 CAF 原样写进
`DSIPHY_CMN_TIMING_CTRL_0..13`（`dsi_phy_hw_v4_0.c:748`
`dsi_phy_hw_timing_val_v4_0()`），与主线 `dsi_phy_7nm.c:1157-1184` 的寄存器
一一对应。按 1.007 GHz 复算主线值后逐项比对：

| CTRL | 字段 | 主线 | 厂商 |
|---|---|---|---|
| 0 | 常量 | 0x00 | 0x00 |
| 1 | clk_zero | 34 | 34 |
| 2 | clk_prepare | 8 | 8 |
| 3 | clk_trail | **10** | **9** |
| 4 | hs_exit | **37** | **25** |
| 5 | hs_zero | 35 | 35 |
| 6 | hs_prepare | 9 | 9 |
| 7 | hs_trail | 9 | 9 |
| 8 | hs_rqst | **6** | **9** |
| 9 | 常量 | 0x02 | 0x02 |
| 10 | 常量 | 0x04 | 0x04 |
| 11 | 常量 | 0x00 | 0x00 |
| 12 | clk_pre | **31** | **28** |
| 13 | clk_post | **25** | **14** |

三个常量与 6 个派生值完全相等，说明寄存器映射与复算方法正确——这条检查
可信。差异集中在 `hs_exit`/`clk_post`（主线更保守），保守值不会阻止进入
HS，故**不作为黑屏根因**，留作"接管后花屏/稳定性"阶段的候选。

### 结论 4（W2 输入就位）

小米 OSS 内核（`liuqin-t-oss`）与 LineageOS sm8450 树**都不含**
`techpack/display`（厂商只发 GKI 部分）。已从 CodeLinaro 取到 CAF 显示驱动
源码：`caf-display/`（`display-kernel.lnx.5.10.r11-rel`），后续 video 启动
顺序/双 DSI 同步/PPS 生成的逐项对照都用它。

## 7. 候选补丁（只在对应证据出现时才做，且一次一个）

| 触发证据 | 候选改动 | 风险 | 现状 |
|---|---|---|---|
| W3 快照确认厂商每包 2 slice 的行为可复现 | 面板 desc 补 `dsc_slice_per_pkt = 2` | 低，可回 | 语义已由 CAF 源码证实（§6.9.2）；按 skill 属"花屏"类，待快照确认 |
| 接管后出现花屏/条纹 | 用厂商 14 字节 PHY timing 表替换计算值 | 中，影响所有面板 | 5/14 差异已量化（§6.9.3）；黑屏阶段不动 |
| W3 快照显示视频引擎启动顺序不同 | 按 diff 调整 encoder/DSI 启动顺序 | 中，牵涉 commit 路径 | 等快照 |
| 面板 DCS 0x0A 读回显示仍在 sleep | 回到 init 序列/时序，按补丁日志定位具体包 | 低 | 等 W4 构建的读回结果 |

### 7.1 W4（当前主路径）：仪器化 DCS 读回

W3（原厂快照）在真机侧受阻：Magisk 应用能打开、显示 `Ramdisk 是`，但
**超级用户是灰的、读不到内核信息**，即 magiskd 没起来、`su` 不可用。这条
路要继续得重打 ramdisk 再引导、装完应用再重启，成本高于收益，暂缓。
但结论不变：**厂商运行时状态仍是缺的那块证据**——只是换更便宜的方式取。

W4 只回答一个此前无法测量的问题：**面板自己认为它开没开**。DSI/MDP 的
寄存器状态可以走 telnet + `devmem` 读，但面板的电源/显示状态只有 DCS
读回能拿到，而这必须在内核里发。补丁 `4090f33f442e`
（`nt36532_diag_panel_state()`）在三个时点读 DCS 0x0A / 0x0D：

- 时点：`post-init`（初始化序列刚发完）、`prepared`（prepare 结尾）、
  `enabled`（enable 之后）；
- 只读：不改时序、不改寄存器、不改序列；点亮后即删（已登记技术债）。

判据（0x0A：bit2 display on、bit3 normal mode、bit4 sleep out）：

| 读到 | 含义 | 下一步 |
|---|---|---|
| `0x0C` / `0x1C` | 面板已醒、已开显示 | 问题在视频流/解码侧 → 查 DSC 打包与 PHY timing（§6.9.2、§6.9.3） |
| `0x08` | 醒了但显示关着 | display-on 没被接受 → 查命令时序 |
| `0x00` / `0x04` | 仍在 sleep | 初始化没生效 → 查 LP/HS 命令通路与 lane |
| `ret=-110` 等负值 | 命令通路不通 | 回到 L2（PHY/lane），面板根本没应答 |

同一份 dmesg 里还会带上既有的 `dsi_err_worker` 记录，可判定 DSI
FIFO/超时错误发生在哪个阶段。

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

## 10. 用户决定（2026-10-27 已确认）

- W2+W3 并行推进；允许联网稀疏取源码。结果见 §6.9、§11。

## 11. W3 真机会话清单（原厂黄金快照）

目的：拿到厂商驱动**点亮本机面板时**的运行时状态，与我方同一位置快照做
diff。全程只 RAM 启动、不写分区；失败只需长按电源回原厂。

### 11.1 镜像（2026-10-27 修正：必须用**本机同版本 ROM**）

**作废**：先前用 `liuqin_images_OS2.0.6.0.VMYCNXM_15.0` 的 `boot.img`
（Android 15 / HyperOS 2）打的 `repack/stock-golden/boot-stock-magisk.img`。
本机实际运行 **V14.0.9.0.TMYCNXM_20230907（Android 13 / MIUI 14）**，
版本不匹配，Magisk 起不来（应用可开、`Ramdisk 是`、超级用户灰、读不到
内核信息），镜像与流程一并作废。

正确做法：从**本机同版本线刷包** `V14.0.9.0.TMYCNXM_20230907` 的
`images/boot.img` 取原始 boot，用设备上已安装的 Magisk"选择并修补一个
文件"生成 `magisk_patched-*.img`，再 `fastboot boot` 该镜像（只 RAM
启动，不写分区）。判据：进系统后 Magisk 显示"已安装"，
`adb shell su -c id` 返回 `uid=0`。

### 11.2 步骤

1. 主机：`fastboot boot boot-stock-magisk.img`。
2. 起 Android 后 `adb install Magisk-v30.7.apk`，在设备上打开一次完成
   初始化；`adb shell su -c id` 应返回 `uid=0`。
3. 主机：`python3 tools/collect-vendor-display-snapshot.py out/vendor-display`
   —— 一次性把 debugfs 树、DSI/mdss/SDE 节点清单、`clk_summary`、
   `/proc/interrupts`、dmesg、cmdline、显示相关 getprop 与常见寄存器 dump
   存档；读不到的项目记进 `_errors.txt` 而不中断。
4. 若第 3 步显示厂商没有现成 dump 节点，改用 §7.1（W4）的仪器化 DCS 读回。

### 11.2b 零成本先做的 B 计划（不需要 root）

跑着的系统里 `/proc/device-tree` 对 shell 可读，所以"本机这版 ROM 用哪条
面板 init 序列"可以直接取出来，与我们现在用的（来自 OS2.0.6.0 DTBO 的
天马 216 包）逐字节比对：

```bat
adb shell "ls -d /proc/device-tree/*m81*"
adb exec-out cat "/proc/device-tree/<上一步得到的节点>/qcom,mdss-dsi-on-command" > oncmd_v14.bin
adb exec-out cat "/proc/device-tree/<上一步得到的节点>/qcom,mdss-dsi-panel-phy-timings" > phytim_v14.bin
```

用 `exec-out` 而不是 `shell` 重定向，避免 Windows 把二进制按文本换行改写。
若这版 ROM 的 init 序列与 OS2.0.6.0 不同，直接就是线索（我们可能移植了
另一版 ROM 的序列）；若相同，则"序列取错版本"这条彻底关闭。

### 11.2c R1 结果（2026-10-27，本机 ROM 线刷包已到手）：**面板数据完全一致**

输入：`liuqin_images_V14.0.9.0.TMYCNXM_13.0`（本机 ROM）的 `dtbo.img`
拆成 38 个 entry 后，天马节点位于 `entry.15`（`fragment@102`），与
OS2.0.6.0 的同名节点逐项比对（脚本 `repack/compare-panel-node.py`）：

| 项 | 结果 |
|---|---|
| 面板宽/高、h/v porch、pulse、帧率 | 全部相等（0x384/0xb40、100/46/2、26/214/2、0x78） |
| `panel-clockrate` | 0x3c061800 相等 |
| DSC slice 0x1c2×0x14、slice-per-pkt 2、8bpp/8bpc | 相等 |
| `traffic-mode` / `panel-type` / `phy-voltage` / `phy-timings` | 相等 |
| **`qcom,mdss-dsi-on-command`** | **216 包 / 2047 字节，逐字节相同** |
| 仅本机 ROM 有的属性 | `displayon-command`（1 包：`05 … 01 29`，20 ms）、`displayoff-command` |

结论：**我们移植的面板数据就是本机 ROM 的数据**，"取错 ROM 版本"这条假设
关闭。此前 §6.9 的比对结论因此升级为对本机成立（时序/DSC/PHY 参数与
本机 ROM 相同），而 §6.9.2（slice-per-pkt=2）与 §6.9.3（PHY timing 5 项
差异）也随之变成"与本机 ROM 的差异"，不再有版本混杂。

`displayon-command` 是 DCS `0x29` 短写 + 20 ms；我们的 `nt36532_enable()`
也发 `mipi_dsi_dcs_set_display_on()`，功能等价（差异仅在等待时长：
我们 10–11 ms 后再发 PPS，厂商 20 ms），不构成候选。

**剩下唯一未测的层**：面板是否真的醒了（DCS 0x0A），见 §7.1 的 W4
（内核 `4090f33f442e`）。

### 11.2d W3 第一次采集（2026-10-27）：熄屏空跑，但拿到 4 条硬事实

状态：部分成功。采集落在**熄屏**状态——`disp_cc_mdss_{mdp,byte0,pclk0}_clk`
使能计数全为 0、`dsi-ctrl-0/1 state_info` 三个引擎全 OFF、`reg_dump` 与
`core_irq` 为空。因此寄存器部分不可用，需重跑（采集器已改为先强制亮屏
并校验，`ab301d0`）。

仍然确认到的事实（都在 `out/vendor-display/`）：

1. **厂商用的就是这个天马节点**：cmdline
   `msm_drm.dsi_display0=qcom,mdss_dsi_m81_36_02_0a_dualdsi_dsc_lcd_video`，
   与我们一致；厂商内核 5.10.136-android12，构建于 2023-02-09。
2. **链路速率与我们相同**：`dsi0_phy_pll_out_byteclk = 125 879 040 Hz`
   （对应 1.007 Gbps / 8），与我们 clk_summary 里的 byte0/byte1 完全一致；
   `state_info` 里 `PIXEL_CLK = 167 838 720`。
3. **厂商 msm_drm 中断在走**：`GICv3 115 Level msm_drm`，计数
   1050 / 0 / 2263 / 6329（CPU0/2/3）。我们这边 GIC 83 一行都没有——
   真实差异，但需在亮屏状态确认（这次厂商也熄屏）。
4. **SDE 也不常开 DPU 中断**：`dri/0/debug/core_irq` 只有
   `idx:27 irq:9422 enable:0 cb:0`、`idx:67 irq:95 enable:0 cb:0`，
   即正常系统上这些 DPU 中断同样 enable=0、无回调。与 §9.3 的降级判断
   一致（INTR_EN=0 不是黑屏原因）。
5. 另有一处待解：`dump_info` 报 **144fps**，而 V14 的 DT 节点只有 120fps
   一个 timing。重跑时采集器会读运行中 DT 的 `panel-framerate` 定论。

重跑要点：平板解锁、屏幕点亮（采集器会 `input keyevent WAKEUP` +
`svc power stayon true` + `screen_off_timeout=30min`），随后照旧运行脚本；
结尾若打印"enable count 0"警告，说明仍是熄屏，无效。

### 11.4 6.17 ↔ 7.0 显示链全量差异（2026-10-27，`git diff liuqin-6.17 liuqin-7.0`）

思路：`liuqin-6.17` 是同一 SoC 上已被点亮的基线，**7.0 与它的差异就是全部候选**。
以下按"是否影响本机（sm8450/sm8475、DPU 7.x、DSI 6G v2.6、视频模式、双 DSI、DSC 3:1、
UBWC 4.0）"过滤后的结果。

| 文件 | 改动 | 对本机 |
|---|---|---|
| `dsi_host.c` | byte clk 先 `clk_round_rate` 再设；byte_intf 由取整值推导 | 生效，值不变则无影响 |
| `dsi_host.c` | `dsi_link_clk_disable_6g()` 删除 `dev_pm_opp_set_rate(dev, 0)` | 生效 |
| `dsi_host.c` | `bits_per_pclk` 改写（原 `bytes_per_pclk`） | **数值等价**：宽总线+视频模式两版都得 3 字节/pclk |
| `dsi_host.c` | `dsi_adjust_pclk_for_compression()` 双链路分别取整 | **数值等价**：900×8/24=300 整除 |
| `dsi_phy.c` | 显式 `clk_prepare_enable(ahb)` 改为 PM clock（`pm_clk_add(dev,"iface")`） | 生效 |
| `dsi_phy_7nm.c` | PLL bias 开关重排、`pll_enable_cnt`、自旋锁 | 生效（PLL 计费） |
| `dsi_phy_7nm.c` | `QUIRK_V7_0` → `V7_2` 改名 | 不影响（sm8750 用） |
| `dsi_phy.c` | `msm_dsi_dphy_timing_calc_v4()` | **完全未改** ⇒ §6.9.3 的 5 项 PHY 差异在 6.17 上同样存在 |
| `dsi_cfg.*` | `V2_2_0`→`V2_0_0` 改名、新增 kaanapali | 不影响（V2_6_0 → `sdm845_dsi_cfg` 两版相同） |
| `dsi.xml` | ACTIVE/TOTAL 位域 12→16 位 | 不影响（本机值未溢出） |
| `dpu_encoder.c` | `MAX_CHANNELS_PER_ENC` 4→2；`num_dsc` 判定改写 | **拓扑结果相同**（2 LM/2 DSC/2 INTF） |
| `dpu_crtc.c` | 新增 GC LUT；拓扑收口改写；`mode_valid` 用 adjusted clock | 拓扑结果相同 |
| `dpu_hw_intf.c` | DPU 8.x 的 WD timer / vsync_sel | 不影响 |
| `dpu_hw_interrupts.c` | 新增 13xx 中断表 | 不影响 |
| `dpu_hw_sspp.c` | **`SSPP_FETCH_CONFIG` HBB 字段：`hbb<<18`(16) → `(hbb-13)<<18`(3)** | **唯一的寄存器写值差异** |
| `dpu_plane.c` | 虚拟平面/分屏裁剪重构 | 生效 |
| DT `sm8475-xiaomi-liuqin.dts` | 显示段逐行比对 | **完全相同**（仅 dsi1_phy 位置挪动） |

#### 11.4.1 面板驱动侧的核查（排除"天马移植错"）

* `pipa_mode_120` 的 200/4/92 水平 porch **正是厂商 100/2/46 的双链路倍乘**，
  总行数 2096 与厂商一致；垂直 26/2/214 与厂商一致 ⇒ **mode 正确**。
* V14 DTBO 中 `m81_36_02_0a`（天马）与 `m81_42_02_0b`（CSOT）的时序、DSC、
  时钟率**完全相同** ⇒ 两个模块共用一份 mode/DSC 是对的。
* init 序列 216 包与 V14 DTBO 逐字节相同（§6.9 结论 1 升级为本机成立）。

#### 11.4.2 关于 UBWC HBB 的三种写法

| 来源 | `SSPP_FETCH_CONFIG` HBB 写入 |
|---|---|
| 厂商 CAF `sde_hw_sspp.c:317` | `highest_bank_bit << 18`（原始值） |
| 6.17（已点亮） | `highest_bank_bit << 18`（原始值） |
| 7.0 | `(highest_bank_bit - 13) << 18` |

`sm8350_data.highest_bank_bit = 16`（两版相同，未改表）。即本机上
**6.17 写 16，7.0 写 3**。注意 `msm_mdss.c` 在两版里都一直用 `-13`，
所以 7.0 是把 SSPP 与 MDSS 的编码统一了；但厂商在 SSPP 上写的是原值。
此项只在 framebuffer 走 UBWC 时生效（线性 fb 不走这条分支）。

#### 11.4.3 `dsi_err_worker: status=4` 是误报（关闭）

厂商**正常工作**状态的 `DSI_FIFO_STATUS`（物理 0x0C）= **0x00001010**，
bit12 = `DLN0_LP_FIFO_EMPTY`（正常），bit4 未定义。主线
`dsi_fifo_status()` 对**任何非零**都置 `DSI_ERR_STATE_FIFO` 并打印，
因此 `status=4` 在本硬件上是恒定误报，不是症状。

#### 11.4.4 新增诊断（`c4d5a7e30408`）：打印本机 DSI 寄存器

在 `dsi_op_mode_config(enable)` 末尾按 link 各打三行，字段与厂商
`dsi0_ctrl_reg` 可逐项对照（主线 `REG_*` 物理地址 = 厂商地址 − 4）：

| 寄存器 | 厂商正常工作值 |
|---|---|
| `CTRL` | `0x000001f3` |
| `STATUS0` | `0x00002008` |
| `FIFO_STATUS` | `0x00001010` |
| `VID_CFG0` | `0x02009230` |
| `ACTIVE_H` | `0x015c0030`（end−start = 300 = 900/3 DSC） |
| `ACTIVE_V` | `0x0c1800d8`（end−start = 2880） |
| `TOTAL` | `0x15f30254`（厂商 144 fps 模式，仅供参考） |
| `ACTIVE_HSYNC` | `0x00020000` |
| `CMD_DMA_CTRL` | `0xd4000000` |

判据：`CTRL` 的 bit0/1/4-7/8 是否为 1；`VID_CFG0` bit25（widebus）是否为 1；
`ACTIVE_H` 的 end−start 是否为 300；`ACTIVE_V` 的 end−start 是否为 2880。
四项中任一不符即为该层的直接证据。

### 11.2e 厂商寄存器全量对照（2026-10-27，亮屏实采）

在已 root 的 MIUI14 上把 `_off` 窗口开大后读到的真值（物理地址，等价于
厂商 `dsi0_ctrl_reg`）：

| 地址 | 寄存器 | 厂商值 | 我们的代码会写 | 判 |
|---|---|---|---|---|
| 0x004 | `DSI_CTRL` | `0x000001f3` | 视频模式+4 lane+clk en | 一致 |
| 0x010 | `VID_CFG0` | `0x02009230` | 同（bit25 widebus 置位） | 一致 |
| 0x024 | `ACTIVE_H` | `0x015c0030` | 48..348（300 = 900/3） | 一致 |
| 0x028 | `ACTIVE_V` | `0x0c1800d8` | 216..3096（2880） | 一致 |
| 0x02c | `TOTAL` | `0x15f30254` | 厂商当时跑 144 fps | 仅模式差异 |
| 0x0a8 | `LANE_STATUS` | `0x00001f1f` | — | 链路空闲态正常 |
| **0x0ac** | **`LANE_CTRL`** | **`0x01000000`** | **`0x10000000`** | **不一致（见 11.2f）** |
| 0x2a0 | `DSC_MODE_CTRL` | `0x03840b01` | bytes/pkt 900、pkt/line 1、eol 0 | 一致 |

`DSC_MODE_CTRL = 0x03840b01` 解码：`WC=0x384=900`（= 450×2，即
`slice_per_pkt=2` 被正确合包）、`DATATYPE=0x0b`、`PKT_PER_LINE=0`
（1 包/行）、`EOL_BYTE_NUM=0`、`EN=1`。主线 `dsi_update_dsc_timing()`
对同样的输入算出的正是这个值 —— **§6.9.2 的 slice-per-pkt 差异已闭合**。

#### PHY 时序：DT 表 = 寄存器真值，5/14 与主线计算不同

`DSIPHY_CMN_TIMING_CTRL_0..13`（0x0b4–0x0e8）读数为
`00 22 08 09 19 23 09 09 09 02 04 00 1c 0e`，与 DT 属性
`qcom,mdss-dsi-panel-phy-timings` **逐字节相同**（厂商确为原样写入）。

| idx | 字段 | 主线计算 | 厂商 |
|---|---|---|---|
| 3 | clk_trail | 10 | 9 |
| 4 | hs_exit | 37 | 25 |
| 8 | hs_rqst | 6 | 9 |
| 12 | clk_pre | 31 | 28 |
| 13 | clk_post | 25 | 14 |

但 `msm_dsi_dphy_timing_calc_v4()` 在 6.17 与 7.0 **完全相同**，而 6.17 用
同一套计算点亮了使用**同一张 PHY 表**的 CSOT 模块 ⇒ 这 5 项不是拦路虎。

#### 面板期望状态：`0x9d`

厂商 ESD 检查读 DCS `0x0a`，期望值 `qcom,mdss-dsi-panel-status-value = <0x9d>`
（读长 1）。`0x9d` = bit0 booster + **bit2 显示开** + **bit3 正常模式** +
**bit4 退出睡眠**。我们的诊断打印拿到 `0x9d` 即表示面板已完全唤醒。

### 11.2f 已确认的寄存器级差异与修复（`703ce73dd750`）

厂商 `_dsi_display_continuous_clk_ctrl()` 第一句就是
`if (!panel->host_config.force_hs_clk_lane) return;`，而该属性
（`qcom,mdss-dsi-force-clock-lane-hs`）在 `m81_36_02_0a` 节点里**不存在**，
所以厂商从不改 `LANE_CTRL`：bit24 保持上电默认 1、bit28 = 0（BLLP 期间
时钟通道进 LP）。

主线相反：未设 `MIPI_DSI_CLOCK_NON_CONTINUOUS` 时会**主动**清 bit24、
置 bit28，把时钟通道钉在 HS。修复：给 `pipa_tm_desc` 加
`MIPI_DSI_CLOCK_NON_CONTINUOUS`，主机就整段跳过，寄存器与厂商一致。

只改 `pipa_tm_desc`：`pipa_desc` 与 pipa 设备共用，且 CSOT 模块在本 SoC 上
用连续时钟已被 6.17 点亮，不动它。

顺带修正 `pipa_desc` 里一段错误注释：它引用的
`qcom,mdss-dsi-non-continuous-clock` 厂商驱动根本不读，真正读的是
`qcom,mdss-dsi-force-clock-lane-hs`，且极性相反。

### 11.3 判据

- 与我方运行时快照逐项 diff，**第一条不可解释的差异即根因候选**；
- `/proc/interrupts` 中 mdss 中断计数顺带解掉 §9.3 的悬案；
- 厂商 `clk_summary` 中 DSI/DSC/DPU 时钟的投票与频率，与我方差集。
