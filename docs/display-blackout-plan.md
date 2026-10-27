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

### 11.3 判据

- 与我方运行时快照逐项 diff，**第一条不可解释的差异即根因候选**；
- `/proc/interrupts` 中 mdss 中断计数顺带解掉 §9.3 的悬案；
- 厂商 `clk_summary` 中 DSI/DSC/DPU 时钟的投票与频率，与我方差集。
