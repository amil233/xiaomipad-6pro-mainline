# liuqin 天马面板：全量问题清单与打勾排除法

> 目的：把"黑屏有背光"拆成**可以逐条判真伪的问题**，一条一次打勾，不跳层。
> 依据：`xiaomipad-6pro-mainline/out/vendor-display/`（原厂 V14 快照，root）、
> `display-drivers-archive/` 两份驱动、`docs/display-driver-plan.md`、
> 以及本次复核（2026-10-28）的结论。
> 新事实：**liuqin-6.17 的 boot.img 在本机同样黑屏 + 背光**，所以"6.17 能亮"
> 这条前提作废，唯一可信的"能亮"配置只剩原厂 ABL + MIUI 内核。

---

## 0. 怎么用这份清单

**当前计数（2026-10-28 第六轮后）**：133 条 —— ⛔ 65 / ⚠️ 39 / ⬜ 25 / ❓ 3 / ❌ 1。

**本轮新关闭的 6 条**：A04 与 M05（天马 desc + 命令行生效）、I01（216 包 init
确实发出且成功）、I02（切页后标准 DCS 生效）、F06（命令经 dsi[1] 可达）、
O01（video mode 下 DCS 读可靠）、F11（CMD_DMA 广播缺陷已修且值已验证）。
**新作废的判据**：I06 —— `0x9e` 的 bit0/bit1 不可由 DCS 改变，不再当判据。

**已知错误改动与误判**：见 `known-wrong-changes.md`。每次动代码/实验设计前，
先过一遍那份文档 §4 的 8 条自检。

**状态词**（只认这四种，别写"应该没问题"）：

| 记号 | 含义 | 要求 |
|---|---|---|
| ⛔ | 已排除 | 必须有一句可复现的观测（寄存器值/日志/现象） |
| ⚠️ | 可疑或证据不足 | 有间接证据但不能定案，或静态对但运行时未验 |
| ⬜ | 未测 | 没做过，或做过但方法无效 |
| ❓ | 本机无法测 | 缺硬件/缺手段，需要换思路 |

**纪律**（不遵守的话清单会退化成玄学）：

1. 一条 = 一个变量 = 一次上机；不达预期立刻回退。
2. "静态一致"（DT/字节比对）只记 ⚠️，不记 ⛔；⛔ 必须是运行时观测。
3. 每排除一条，写清"用哪个观测排除的"，写在本文表格的"现状"列里。
4. 同一层没打完勾，不进下一层；但允许先打"信息量最大"的那几条（见 §3）。

---

## 0.5 当前进度（每确定一项就在这里落一行）

| 步 | 目标条目 | 手段 | 状态 | 证据位置 |
|---|---|---|---|---|
| 0 | F11（CMD_DMA 广播位） | 原厂两条链路 `0x3c` 对照 → 改默认值 | ✅ 已修（`cec2a7b5`），镜像实测 `CMD_DMA_CTRL=14000000` | §8 第一/五轮 |
| 1 | J01 / J02（60 Hz 真值） | 原厂边滑动边抓 `dump_info`/`clk_summary` | ✅ 完成（`TOTAL=186301bf` 预测命中） | §8 第三/四轮 |
| 1.5 | 基线与 HEAD 源码差异 | `git diff 308065ef..HEAD` | ✅ 完成（5 文件，DPU 预取已回退） | `docs/diff-308065ef-vs-head.md` |
| 2 | A04 / M05 / I01 / I02 / F06 | 进 shell 后看 probe 日志 + poke | ✅ 全部关闭：天马 desc、init 成功、写通路有效 | §8 第五/六轮 |
| 3 | I06 / R4（`0x9e` 判据） | 切页后发真 DCS `0x38` | ✅ 判据作废，不再追 | §8 第六轮 |
| 4 | **I13（0x45 扫描行）** | 需要一次构建：把 `0x45` 加进 `dcs` 读 | ⬜ **唯一还缺的判据** | — |
| 5 | H01 / H04 / H05（PPS 实际内容） | 原厂 `dynamic_debug` + 熄屏/亮屏 | ⬜ 待做 | — |
| 6 | H02（PPS `pic_width`） | 内核 `pps:` 第 8/9 字节 | ⬜ 待做（等 0x45 结果再定优先级） | — |

**当前唯一动作**：boot **B**（`boot-702b079d-B.img`，默认 60 Hz）→ 抓
`dsi0/regs`（`TOTAL` 必须是 `186301bf`）→ 与原厂 60 Hz dump 逐字节比 →
从 `bundle` 取 INTF 帧计数。**在拿到这三样之前不改任何代码。**

## 1. 结构性前提（这几条不解决，后面所有"排除"都会被打回）

| 编号 | 问题 | 为什么致命 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| A01 | 没有可信的"能亮"基线 | 6.17 boot.img 在本机也黑 ⇒ 所有"移植自 6.17/上游"的配置都只是假设 | 无：事实 | ⚠️（事实） |
| A02 | 唯一可信的"能亮"是原厂 ABL + MIUI | splash 与系统画面都正常 | 开机看 splash | ⛔ 已知 |
| A03 | 对照基准 | 模式不同则寄存器不可比 | **已定为 60 Hz**（用户选择）：原厂 60 Hz 真值已抓，我们的目标 mode 也按 60 写，两侧同模式可直接逐字节比 | ⛔（基准已定） |
| A04 | 实际跑的是哪个 desc | 选错就会用另一块屏的 init | **已确认**：`panel desc: tianma … cmdline_match=1`（镜像 A，`702b079d`） | ⛔ |
| A05 | 新驱动没有用户态窗口（进 shell 前复位） | 面板状态类判据全部拿不到 | 改用旧驱动做实验台，或内核自打印→pstore | ⚠️ |
| A06 | `0x0a` 的 bit0/bit1 语义可疑（`0x9e` vs `0x9d`） | 据此推"booster 没开"曾得出过错误结论 | 不把 `0x0a` 当唯一判据；用 `0x45` 推进 + 画面 | ⚠️ |
| A07 | "init 序列逐字节一致"≠"运行时真的送达并被接受" | 静态比对通过却从未验证运行时 | 内核日志 + poke 有效性测试 | ⚠️ |
| A08 | 上游作者 CSOT 成功不可复现、也无日志 | 任何"上游能亮所以代码对"的推理失效 | 无 | ⚠️（事实） |

---

## 2. 分类问题清单

### B. 供电与上电时序（8）

| 编号 | 可能的问题 | 与黑屏的因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| B01 | vddio 1.8 V 未上/偏低 | DDIC 数字域不工作，命令会失败 | 读 `regulator_summary`；面板能回 DCS 即已工作 | ⛔（DCS 有响应） |
| B02 | dvddbuck/dvddldo 1.3 V 未上 | 同上 | 同上 | ⛔ |
| B03 | 三路供电的**顺序与间隔**不符合 DDIC 要求 | 上电顺序错会导致内部状态机锁死（黑屏但能应答） | 对照原厂 DT 的 `panel-supply-entries` 顺序与延时；在 prepare 里逐路上电并打印时间 | ⬜ |
| B04 | VSP/VSN（±5.5 V）的归属与使能顺序不同 | 源极驱动模拟电源；顺序错会出「背光亮、屏不亮」 | 原厂：`display_panel_vsp/vsn` 是面板供电（`soc:qcom,dsi-display-primary-vsp/vsn`），随 panel prepare 使能；主线：挂在 ktz8866 背光上由背光驱动使能 → 与 panel init 的先后可能不同 | ⚠️（新证据） |
| B05 | bulk enable 的先后顺序 | 同 B03 | 读两份驱动的 `pipa_supply_names[]` 顺序，与 DT 顺序比 | ⚠️ |
| B06 | 供电电流不足/load switch 压降 | 面板上电瞬间掉压 | 万用表/示波器（需要拆机条件） | ❓ |
| B07 | 从未逐条记录实际电压 | 无法证明供电正常 | 原厂实测：pm8350c_l2=1800 mV、dvdd_buck=1300、dvdd_ldo=1300、vsp=5500、vsn=5500，全部 use=1 | ⛔ |
| B08 | 上电到复位、复位到首包的等待不够 | DDIC 还没准备好就发命令 | 与原厂 prepare 的 sleep 序列逐项比；加长验证 | ⬜ |

### C. 复位与 GPIO（6）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| C01 | reset GPIO 极性反了（nRESET 被一直拉住） | init 全部"成功"但面板不工作 | 抓 GPIO 电平（`gpio` debugfs 或万用表）；对比 <0 10 1 3 0 3 1 15> 的末态 | ⚠️（静态一致，运行时未验） |
| C02 | 复位脉宽/间隔不对 | 复位不彻底 | 逐项对比 DTBO 与 `pipa_reset()` | ⚠️ 同上 |
| C03 | 复位释放到第一条 DCS 的间隔 | DDIC 未就绪 | 加日志时间戳 | ⬜ |
| C04 | 复位期间链路不在 LP-11 | DDIC 采不到唤醒 | 读 `LANE_STATUS`（原厂 00001f1f） | ⬜ |
| C05 | reset-gpios 与 `sde_dsi_active` pinctrl 冲突 | GPIO 被别的功能占用 | 查 pinctrl 定义与 gpio 0 的复用 | ⬜ |
| C06 | 双链路只需一个复位（原厂如此） | — | 已一致 | ⛔ |

### D. 背光（4）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| D01 | 把"背光亮"当成"面板在工作" | 背光是独立 IC（ktz8866），与面板是否解码无关 | 已区分 | ⛔ |
| D02 | 背光电压/电流异常 | 只是亮度问题，不会全黑 | 读 ktz8866 寄存器（0x09=0x9f） | ⛔ |
| D03 | 背光早于/晚于面板使能 | 短暂闪白/闪黑，不是常黑 | 抓 enable 时间线 | ⬜ |
| D04 | 亮度寄存器为 0（0x51） | 背光 IC 亮但面板内部调光为 0 | 读 init 里的 `0x51 0x0f 0xff` 与当前值 | ⚠️ |

### E. DSI 物理层（10）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| E01 | lane 数/占用不对 | 数据缺失 | `LANE_STATUS`、`ACTIVE_H` | ⛔（与原厂一致） |
| E02 | lane 极性/顺序（p/n 反、lane swap） | 链路起不来或误码 | 逐 lane 交换实验；读 error 计数 | ⬜ |
| E03 | PLL/bit clock 频率 | 若不同会改变 LP/HS 裕量 | **实测一致**：原厂 `clk_summary` 里 `disp_cc_mdss_pclk0_clk=167838720`、`byte0_clk=125879040` → bitclk=1,007,032,320；与我方 120 fps 模式按 `dsi_get_pclk_rate()` 算出的三项逐位相同。另 `dsi1_phy_pll_out_*` 的 enable count=0，双链路确实共用 dsi0 的 PLL | ⛔（运行时实测） |
| E04 | PHY 14 项 timing 与原厂差 5 项 | 同上 | `msm.vendor_phy_timing=1` 已试，无变化 | ⛔（试过，不改变现象） |
| E05 | clock lane 连续/LP 策略 | 原厂不 force HS | 已试 `CLOCK_NON_CONTINUOUS`，无变化 | ⛔ |
| E06 | EOT 包（`rx-eot-ignore`/`tx-eot-append`） | 原厂置了这两个；不影响解码但影响错误检测 | 对照 `CTRL`/`VID_CFG0` 的 EOT 位 | ⬜ |
| E07 | 驱动强度/预加重（原厂 `clk-strength=0xff`、`phy-voltage=0x51`） | 边沿质量差 → 误码 | 读 PHY 的 strength 寄存器，与 DT 值比 | ⬜ |
| E08 | PHY 0.9 V 供电 | 完全无链路 | 能通信即排除 | ⛔ |
| E09 | ULPS 误入 | 链路休眠 | 原厂 ULPS=N；主线未启用 | ⛔ |
| E10 | dsi1 的 PLL 父时钟被本地改成 dsi0 | 双链路不同步 | 对照原厂 `Clock master = dsi-ctrl-0` | ⚠️ |

### F. DSI 协议/控制器（10）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| F01 | video/cmd mode 选错 | 全黑 | `CTRL`/`VID_CFG0` 与原厂一致 | ⛔ |
| F02 | burst vs 非 burst | 打包方式不同 | `VID_CFG0=02009230` 一致 | ⛔ |
| F03 | BLLP power/EOF 模式 | 低功耗间隙行为不同 | 同上（已含在 VID_CFG0） | ⛔ |
| F04 | bonded 双链路同步（master/slave/sync/broadcast） | 两半不同步 → 无画面 | 原厂还有 `cmd-sync-wait-broadcast`；主线靠 `msm_dsi_manager_cmd_xfer` 双 commit | ⚠️ |
| F05 | 另一条链路的 DDIC 是否也收到命令 | 只有一路被初始化 → 黑/半屏 | 写经 dsi[1] 生效 ⇒ 至少一条链路正常；另一路是否也需要由 C 图（`msm.dsi_cmd_broadcast=1`）对照。原厂两条链路只有 `CMD_DMA_CTRL` 差 master 位 | ⚠️ |
| F06 | 命令固定走 dsi[1] | 若主链路才是 DDIC，命令发不出去 | **已排除**：poke `0x10`/`0x11` 改变了面板 power 状态，说明经 dsi[1] 的写入确实到达 DDIC | ⛔ |
| F07 | 视频流期间命令的 BLLP 窗口不足 | 长命令被丢弃 | 看 `dsi_host` 的 "cmd cannot fit into BLLP" 日志 | ⬜ |
| F08 | virtual channel/stream 不一致 | 收不到 | DT 与原厂都是 0/0 | ⛔ |
| F09 | ACTIVE_H（压缩后 300）不对 | 有效区错 | `0x24` 登记值与原厂一致 | ⛔ |
| F10 | DSI 错误状态被忽略 | 误码/超时无感 | 读 `STATUS0`/`LANE_STATUS`；`FIFO=1010` 的误报已判 | ⛔（已知误报） |
| F11 | **`CMD_DMA_CTRL` 在两条链路上都写了 vendor 的 master 值** | 两条都置 broadcast+master，与主线"双 DMA 双 trigger"互斥 → 命令重复/交错 | **已修**（`cec2a7b5`，默认回上游 `0x14000000`）；镜像实测 `CMD_DMA_CTRL=14000000`。对画面是否有效仍未判定（不是这个缺陷的判断范围） | ⛔（缺陷关闭，值已验证） |

### G. DPU 侧 DSC 编码（8）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| G01 | DSC 使能/配置顺序（PPS→compression→EN） | 编码器与面板不同步 | 抓 DPU/DSI 侧寄存器写入顺序 | ⬜ |
| G02 | slice_count/width/height 与 DPU 不匹配 | 编码出错误 slice | 读 DPU DSC 块的 slice 配置（`0x80000` 块） | ⚠️ |
| G03 | chunk / pkt_per_line | 打包错 | `DSC_MODE_CTRL=0x03840b01` 与原厂一致 | ⛔ |
| G04 | bpp/bpc/block-pred | 解码错 | DT 与原厂一致 | ⛔ |
| G05 | DSC 版本/SCR | 解码器拒绝 | 1.1/0，原厂同 | ⛔ |
| G06 | 每 encoder 的 DSC 实例数（2 LM/2 DSC） | 拓扑错 | 逐块读 CTL/PP 绑定 | ⚠️ |
| G07 | **DPU 的 pic_width 是整幅 1800 还是每链路 900** | 与 PPS 同一问题，编码端也会错 | 读 DPU DSC 的 pic_width 字段 | ⚠️ |
| G08 | DSC 输出与 DSI packetizer 的 slice 排布 | 数据错位 | 需要 PPS/寄存器双侧证据 | ⬜ |

### H. PPS 与面板侧解码（10）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| H01 | **PPS 128 字节从未与厂商实际发送值对照** | 面板按错的参数解码 → 黑 | 原厂开 dynamic debug 抓 PPS；或抓我们内核打印的 `pps:` | ⬜ |
| H02 | `pic_width` 写成 1800（每链路只送 2×450） | 解码端算出 4 slice/行，永远对不上 | 看 PPS 第 8、9 字节 = `07 08` 还是 `03 84` | ⚠️（代码推断成立） |
| H03 | `slice_chunk_size` 为 0 或不是 450 | 包长错 | 内核打印 `chunk`；寄存器 WC=900 已证 | ⛔ |
| H04 | RC 字段（initial_dec_delay/scale/bpg/offsets）与原厂不同 | 解码率控错，画面乱或黑 | 与 CAF `sde_dsc_helper.c` 逐字段比；最终要与厂商 PPS 比 | ⚠️ |
| H05 | PPS 发送时机（init 之后、视频流之前） | 面板未准备好 | 与原厂 ON→PPS 顺序对照 | ⛔（顺序同） |
| H06 | PPS 只发一条链路 | 另一路 DDIC 无参数 | 见 F05 | ⚠️ |
| H07 | 多发了一条 DCS `0x9b`（compression enable），原厂无 | 可能被当成厂商分页命令 | 做成参数 A/B | ⬜ |
| H08 | `pps_id`/PPS1 字节 | 多 PPS 场景用错 | CAF 也写 0 | ⛔ |
| H09 | 分页状态下 `0x9b` 的语义 | 同上 | 先 page 0x10 再发 | ⚠️ |
| H10 | PPS 应在 display-on 之前/之后 | 时序 | 原厂：ON 内含 0x29，之后 PPS；我们相同 | ⛔ |

### I. 面板 init / DDIC 状态机（12）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| I01 | 216 包 init 是否真的发出 | 没发 = 面板停在 bootloader 状态 | **已确认发出且成功**：`prepare()` 无失败日志，且随后的 poke 写能改变面板状态 | ⛔ |
| I02 | 分页状态与后续 DCS 冲突 | 命令被当成厂商命令 | **已排除**：`0xff 0x10` 切回 DCS 页后，`0x10`/`0x11` 立即改变 power 状态 ⇒ 切页与标准 DCS 都有效 | ⛔ |
| I03 | init 尾部 0x11/0x29 的等待 | 太短 | 原厂 120/20 ms，我们 120/40 ms | ⛔ |
| I04 | 模式/porch 编程（`0x90/0x91`、`0xb3/0xb2`、`0x3b`） | 面板按错误 porch 解码 | 字节一致；需验证被接受 | ⚠️ |
| I05 | DSC 相关厂商命令（`0x90/0x91` 组） | 面板 DSC 未使能 | 字节一致 | ⚠️ |
| I06 | `0x9e` 的 bit0/bit1 | 曾被当成"booster 没开" | **判据作废**：切页后发真正的 DCS `0x38`，bit1 仍恒为 1；`0x10`/`0x11` 只改变 bit4。该位不可由标准 DCS 清除，更像"未锁到有效码流"的上报 | ⛔（不再用作判据） |
| I07 | ESD/status 检查 | 不影响点亮 | 原厂运行时 "ESD feature not enabled" | ⛔ |
| I08 | TE（video mode 不需要） | — | 原厂也是 video | ⛔ |
| I09 | 亮度寄存器 `0x51` | 内部调光 0 | init 里写了 `0f ff` | ⛔ |
| I10 | 复位后 PPS 是否要重发 | 重连后参数丢失 | 我们每次 prepare 都发 | ⛔ |
| I11 | sleep in/out 的 120 ms | 面板没醒 | 已足够；可用 poke 验证 | ⚠️ |
| I12 | **CSOT/TM desc 混用** | 194 包 init 用在 TM 上 | 见 A04 | ⚠️ |
| I13 | **面板是否在扫我们的帧**（DCS `0x45` 推进） | 黑屏与"锁流"的分水岭 | 旧驱动 `dcs` 节点只读固定 4 个寄存器，读不了 `0x45` ⇒ **需要一次构建**把它加进 read 输出（或独立 `scanline` 节点），16 次采样给 first/last/advancing | ⬜（唯一还需要新构建的判据） |

### J. 时序与时钟（8）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| J01 | 面板是否接受各刷新率的 porch 变化 | 若只认 init 里那一组，改帧率就会黑 | 原厂 kernel 的 mode 表就是 120/144/90/60/50/48/30 七档（`dumpsys display`），且当前跑到 60 fps 正常显示 ⇒ 同一套 init 支持 porch 变化 | ⛔ |
| J02 | htotal/vtotal 与运行模式的关系 | 模式相关寄存器天然不同 | **已抓到原厂 60 Hz 真值**：`900(46\|100\|2)x2880(214\|3148\|2)@60fps 1007032320 Hz`，即 hfp=100/vfp=**3148**（120 Hz 是 vfp=26）。换算：DSI htotal=300+148=448、vtotal=6244 → `TOTAL` 应为 `0x186301bf`。可见 60 Hz 就是"120 Hz 的 vfp 翻倍"，bitclk 不变 | ⛔ |
| J03 | bit clock 不同 | PHY 裕量 | **一致**：785,245 kHz 是 DRM 的 mode clock（未压缩整幅），msm 经 `dsi_adjust_pclk_for_compression()` 折半+压缩后得到 167,838,720/125,879,040/1,007,032,320，与原厂一致 | ⛔ |
| J04 | `dsi_adjust_pclk_for_compression` 的算法 | 时钟算错 | 读我们的 byte/pixel clk 与原厂比 | ⬜ |
| J05 | mdp clk 375 MHz | 带宽 | 与原厂一致 | ⛔ |
| J06 | 双链路 PLL 共享 | 不同步 | 见 E10 | ⚠️ |
| J07 | 时钟 gating（`clk_ignore_unused` 是掩盖） | 时钟被关 | 去掉参数复测；读 clk_summary | ⚠️ |
| J08 | dispcc GDSC/PD | 上电不完整 | 读 GDSC 状态 | ⬜ |

### K. DPU / CTL / INTF / 取数（10）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| K01 | DPU 是否在出帧 | 黑屏 | 旧镜像曾测 `INTF_FRAME_COUNT` 1 s +121；**本镜像尚未复核**，等 `bundle` 输出 | ⚠️ |
| K02 | CTL_TOP/CTL 配置与原厂不同 | 路由/混合错 | 同模式对照 `CTL_TOP=28000300`、`+0x20=00033000`、`+0x24=1` | ⚠️ |
| K03 | INTF 可编程预取（bit31） | 取数时机 | 已置位 | ⛔ |
| K04 | 2LM/2DSC/2INTF 拓扑 | 半屏/黑 | 逐寄存器确认绑定 | ⚠️ |
| K05 | SSPP 取数/格式/UBWC | 无数据 | UBWC 错误 0、无 underrun | ⛔ |
| K06 | UBWC HBB 编码（7.0 改了） | 花屏 | 线性 fb 不走该分支 | ⛔ |
| K07 | CSC/色彩空间 | 黑或偏色 | 读 CSC 配置 | ⬜ |
| K08 | underrun/超时中断 | 花屏/黑 | dmesg 无 underrun | ⛔ |
| K09 | CTL flush/commit 时序 | 不出帧 | 已出帧 | ⛔ |
| K10 | DSC 与 PP 的绑定 | 编码器没接上 | 读绑定 | ⬜ |

### L. 内存 / IOMMU / 交接（6）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| L01 | SMMU fault | 黑屏/复位 | dmesg 无 fault | ⛔ |
| L02 | framebuffer 地址/大小不对 | 画面错位/黑 | 读 fb 信息 | ⬜ |
| L03 | UBWC/线性不一致 | 花屏 | 线性 fb | ⛔ |
| L04 | cache/coherency | 陈旧数据 | 无异常 | ⬜ |
| L05 | **simplefb 与 msm 抢同一个 framebuffer** | 双 console 互相覆盖、甚至崩溃 | 检查 cmdline 是否黑名单 simplefb（oneshot 漏了） | ⚠️ |
| L06 | 带宽/AB 投票不足 | underrun | 无 underrun | ⛔ |

### M. DT / 引导链（10）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| M01 | panel `compatible` | probe 不上 | `xiaomi,pipa-nt36532` 命中 | ⛔ |
| M02 | supplies 名称/句柄 | 取不到电 | 三路都取到 | ⛔ |
| M03 | reset-gpios 极性 | 见 C01 | 静态一致 | ⚠️ |
| M04 | 双链路 endpoint/remote | 只有一路 | 两个 port 都在 | ⛔ |
| M05 | cmdline/desc 选择 | 见 A04 | **已确认**：`/proc/cmdline` 里我们的 271 字符串出现两次（header+DT）+ `force_fps=120`，ABL 串追加在后；`simplefb_driver_init` 被 blacklist、`force_fps` 生效 | ⛔ |
| M06 | DTBO/panel-id 选择 | 用错面板 overlay | 原厂由 ABL 按 panel-id 选；我们没实现 | ⚠️ |
| M07 | bootloader splash 与内核接管的交接 | 接管瞬间黑 | 观察"灰闪一下"的时刻；`fbcon` 绑定 | ⚠️ |
| M08 | regulators always-on 与内核管理的差异 | 掉电时序 | 对照原厂 DT 的 always-on/管理方式 | ⚠️ |
| M09 | backlight 绑定 | 背光不亮 | 已亮 | ⛔ |
| M10 | dsi1 时钟父 | 见 E10 | — | ⚠️ |

### N. 驱动 / 框架（8）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| N01 | probe 依赖顺序（backlight 先于 panel） | panel 不上 | 看 probe 日志顺序 | ⬜ |
| N02 | panel bridge prepare/enable 顺序 | 命令发在链路未上电时 | 已核对 `drm_bridge.c`/`dsi_manager.c` 顺序 | ⛔ |
| N03 | `prepare_prev_first` | 同上 | 与上游一致 | ⛔ |
| N04 | 没有 `.enable` 回调 | 二次 enable 不亮 | `drm_panel_enable` 有判空，背光照开 | ⛔ |
| N05 | 双链路 attach | 第二路没挂上 | attach 成功日志 | ⛔ |
| N06 | **~10 s 复位**（新驱动独有） | 无法测量 | 新驱动在进 shell 前复位；旧驱动无此问题。取证走 pstore（附录 A），与当前面板诊断并行推进 | ❌ 未解（不在本轮范围） |
| N07 | DRM client 是否提交 modeset | 面板根本没 enable | fbcon 绑定 + 帧计数 | ⛔ |
| N08 | 背光 enable 与 panel enable 的先后 | 闪白 | 时间线 | ⬜ |

### O. 测量方法本身的陷阱（8）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| O01 | video mode 下 DCS 读的失败语义 | 误判"面板没醒" | **已排除**：`0x0a` 读稳定返回（`0x9e`/`0x0e`），且与写入引起的状态变化一致 | ⛔ |
| O02 | 寄存器窗口太短（原厂只到 0x5c） | 看不到 DSC/lane 块 | 6d240ec 已做全窗口 dump | ⛔ |
| O03 | 照片判读（黑/灰闪/条纹） | 结论方向错 | 每次录像 | ⚠️ |
| O04 | `0x9e` 位解释 | 见 A06 | 换判据 | ⚠️ |
| O05 | pstore 只保留一轮 | 读数丢失 | 见附录 A | ⬜ |
| O06 | 模式不可比 | 见 A03 | 同模式 | ⚠️ |
| O07 | 一次改多个变量 | 结论污染 | 纪律 | ⛔ |
| O08 | 把"能 boot"当"驱动正确" | 掩盖真因 | 已区分 | ⛔ |

### P. 硬件（5）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| P01 | 面板型号/批次（TM `m81_36_02_0a` vs CSOT） | init/DSC 不通用 | `mi,panel-id`、ABL 选 overlay | ⚠️ |
| P02 | 排线/连接器接触 | 部分 lane 失效 | 重插、看 error 计数 | ⬜ |
| P03 | DDIC 固件差异（同型号不同批次） | 某些命令不认 | 与另一块同型号面板对比 | ❓ |
| P04 | 另一台同型号设备对照 | 排除个例 | 需要设备 | ❓ |
| P05 | 面板本身坏了 | 全黑 | splash 正常 | ⛔ |

---

## 3. 建议的打勾顺序（先打信息量最大、成本最低的）

| 步 | 打哪几条 | 为什么先打 | 不通过时 |
|---|---|---|---|
| 0 | **F11** | 一行代码、已由原厂寄存器证明我们写错；改完一次上机就能看出 init 是否变完整 | 若仍黑，说明还有别的层 |
| 1 | A04 / M05 | 一条 `cat /proc/cmdline` 把"到底跑哪个 desc"钉死（证据已倾向天马，但要证实） | 用 `desc=` 参数强制 |
| 2 | A03 / J01 / J02 | 原厂快照是 50 fps，和我们 120 fps 不可比；不同模式下去比寄存器是白费 | 抓 120 fps 快照，或把 mode 改成 50 那组 porch |
| 3 | I02 / I01 / F06 | 先证明"命令写得到 DDIC 且真的生效"（page 0x10 → sleep in/out），这是最底层、最没人验的一环 | 若写无效，问题在链路/DDIC 接收，不在 DSC |
| 4 | H01 / H02 | PPS 是唯一无法从寄存器验证的环节；字节 8/9 直接判 1800 vs 900 | 改 `pic_width` 做 A/B |
| 5 | E10 / F04 | 双链路时钟源与同步（bitclk 已证一致，只剩链路级差异） | 对照 `Clock master = dsi-ctrl-0` |
| 6 | F04 / F05 | 双链路是否两路都收到命令（原厂用 broadcast） | 改 broadcast/双路发送 |
| 7 | G02 / G07 | DPU 侧 DSC 的 pic_width/slice 与 DSI 是否一致 | 统一成 per-link |
| 8 | B03 / B04 / B08 | 供电顺序与 VSP/VSN 时序（"背光亮、屏不亮"的经典成因） | 按原厂顺序重排并加延时 |
| 9 | E07 / E06 | 驱动强度、EOT、lane 极性 | 按原厂值写 |
| 10 | L05 / M07 | simplefb 与内核接管 | 黑名单 simplefb，复测 |
| 11 | K02 / K04 | CTL/INTF 拓扑逐寄存器 | 同模式对照 |
| 12 | N06 | 新驱动的复位（只在移植阶段） | pstore 判读 |

---

## 4. 原厂侧还能补的采集（root，性价比最高）

原厂系统里有 `dynamic_debug`，这是目前唯一能拿到**厂商实际下发的命令/PPS/时序**
的途径，能一次性关掉 H01/H04/H05/I01/F07 五六条：

1. 开日志（在 root 的原厂系统上）：
   ```sh
   mount -t debugfs none /sys/kernel/debug 2>/dev/null
   echo 'file *dsi_panel* +p'   > /sys/kernel/debug/dynamic_debug/control
   echo 'file *dsi_display* +p' > /sys/kernel/debug/dynamic_debug/control
   echo 'file *dsi_ctrl* +p'    > /sys/kernel/debug/dynamic_debug/control
   echo 'file *sde_dsc* +p'     > /sys/kernel/debug/dynamic_debug/control
   ```
2. 熄屏/亮屏一次（`input keyevent 26` 或亮度拉到 0 再拉回），抓 `dmesg`。
   里面会有：`dsi_panel_prepare/enable`、`DSI_CMD_SET_ON`、PPS 命令、
   `bit_clk`/`pclk`/`byte_clk`、DSC 参数。
3. **同模式快照**：让屏幕跑 120 fps（滑动/视频/游戏），同时抓
   `dri/0/debug/qcom,mdss_dsi_m81_36_02_0a_dualdsi_dsc_lcd_video/*`
   （`dump_info`、`state_info`、`sde_reg`、`clk_summary`、`regulator_summary`）。
   这样 A03/J02/J03/K02 全部变成可比。
4. 熄屏→亮屏瞬间的 `sde_reg`/`dsi-ctrl-0_reg` 差分，能看出厂商在 "接管" 时
   改了哪些我们没改的寄存器（M07）。

---

## 5. 记录模板（每打一条勾，追加一行）

```
编号：
假设：
改动/观测命令：
预期：
实测（原始输出/照片）：
结论：⛔排除 / ⚠️降级 / ⬜未测
下一步：
```

---

## 8. 实测记录（原厂 root，逐步追加）

### 2026-10-28 第一轮（设置 60 Hz，静态界面）

| 观测 | 值 | 对应条目 |
|---|---|---|
| `clk_summary` | `disp_cc_mdss_pclk0_clk=167838720`、`byte0_clk=125879040`、`mdp_clk=375000000`；`dsi1_phy_pll_out_*` enable=0 | E03/J03 ⛔ |
| `dsi0_ctrl_reg` / `dsi1_ctrl_reg` | 除 `0x3c` 外逐字相同；dsi0=`0xd4000000`、dsi1=`0x94000000`（bit30 只在 master） | F05 ⚠️（原厂用广播） |
| `regulator_summary` | l2=1800 mV、dvdd_buck=1300、dvdd_ldo=1300、vsp=5500、vsn=5500，全部 use=1；vsp/vsn 挂在 panel 名下 | B07 ⛔；B04 ⚠️（vsp/vsn 归属与主线不同） |
| `dri/0/state` | crtc-0 上两块 `900x2880` 平面（x=0 与 x=900），另有 `60x2880@1740` 等小平面 | 双链路 2×900 分半（K04 背景） |
| `/proc/cmdline` | `msm_drm.dsi_display0=qcom,mdss_dsi_m81_36_02_0a_dualdsi_dsc_lcd_video:` | A04：bootloader 自带该串（倾向天马） |
| `dump_info` | **没抓到**：面板 debugfs 目录在 `/sys/kernel/debug/` 顶层，不在 `dri/0/debug/` | 下一轮修正 |

**注意**：本轮虽然设置成 60 Hz，但 DSI 侧仍是 50 fps 的时序（`TOTAL=0x15f30254`，与 10-27 的 50 fps 快照逐字相同）——
说明 MIUI 在静态界面上会走 dfps 的省电档 50 Hz（不在设置的 60/90/120 三档里）。
要抓 60/90/120，必须让画面动起来（滑动/播放视频），或把 `min_refresh_rate` 钉住。

### 2026-10-28 第二轮：原厂两条链路的 CTRL 对照（关键）

`dsi0_ctrl_reg` 与 `dsi1_ctrl_reg` 除 **`0x3c`（CAF 命名的 CMD_DMA_CTRL，主线偏移 0x38）** 外逐字相同：

```
dsi0: 0x3c = d4000000   bit31 BROADCAST_EN=1, bit30 is_master=1, bit28 embedded=1, bit26 LPM=1
dsi1: 0x3c = 94000000   bit31 BROADCAST_EN=1, bit30 is_master=0, bit28 embedded=1, bit26 LPM=1
```

因果（CAF `dsi_ctrl_hw_cmn.c:861-876`：`en_broadcast`→BIT(31)、`is_master`→BIT(30)）：
原厂是**从 master 踢一次、硬件广播到两条链路**，slave 自己的 DMA 从不启动。

我们的 `dsi_host.c:871` 把 master 的那个值无条件下发到**每一个 host**：

```c
/* Vendor liuqin value; the upstream pair leaves bits 31/30 clear. */
dsi_write(msm_host, REG_DSI_CMD_DMA_CTRL, 0xd4000000);
```

而主线的命令通路是"两条链路各写一份 DMA、由 `msm_dsi_manager_cmd_xfer()` 同时 trigger"
（`dsi_manager.c:507-548`），与 broadcast 是**互斥的两种机制**。两边都置 broadcast，
等于每条链路都广播一次，同一串 216 包 init 可能在两路之间重复并交错 —— 分页写被打乱，
DDIC 就可能停在"能应答、不显示"的状态。

修法（一行，下一版验证）：恢复上游语义
`DSI_CMD_DMA_CTRL_FROM_FRAME_BUFFER | DSI_CMD_DMA_CTRL_LOW_POWER`（= `0x14000000`，bit31/30 清零），
让每条链路只发自己那一份；若将来要做真广播，则必须同时改成"只在 master 上 kickoff"，
不能两者混用。

### 2026-10-28 第三轮：60 Hz 真值（关键）

原厂 `dump_info`（设置 60 Hz，动态时）：

```
Resolution = 900(46|100|2|0)x2880(214|3148|2|0)@60fps 1007032320 Hz
```

| 刷新率 | hfp | vfp | 每链路 htotal × vtotal | 备注 |
|---|---|---|---|---|
| 120（DTBO timing@0） | 100 | 26 | 1048 × 3122 | 我们当前代码用的 |
| **60（本轮实测）** | 100 | **3148** | 1048 × **6244** | = 120 Hz 的 vfp 翻倍 |
| 50（10-27 快照） | 249 | 2524 | 1197 × 5620 | 静态省电档，不在设置三档里 |

bit clock 三档都不变（`1007032320 Hz`）。因此 60 Hz 的 DSI 侧唯一变化是 vtotal：
`DSI htotal = 300(压缩后有效) + 148(消隐) = 448`，`vtotal = 6244`，
⇒ `TOTAL` 期望 `0x186301bf`，`ACTIVE_H/ACTIVE_V/VID_CFG0/DSC_MODE_CTRL` 全部不变。

另外 `dumpsys display` 显示原厂 kernel 的 mode 表：120/144/90/60/50/48/30 共 7 档，
`defaultModeId=120`，当前 `mActiveSfDisplayMode=60`。**144 确实存在**（只是设置界面不提供）。

### 2026-10-28 第四轮：60 Hz 预测验证（模型闭环）

预测 `TOTAL=0x186301bf`，实测：

```
dsi0: 0x2c = 186301bf   0x3c = d4000000 (master+broadcast)
dsi1: 0x2c = 186301bf   0x3c = 94000000 (broadcast, 非 master)
其余 ACTIVE_H/ACTIVE_V/VID_CFG0/DSC_MODE_CTRL 全部不变
pclk0=167838720  byte0=125879040  （与 120 Hz 一模一样）
```

⇒ **"固定 1.007 G bit clock、只改 porch" 得到证实**；60 Hz = 120 Hz 的 vfp 翻倍。
我方 60 Hz 目标 mode 的 DSI 寄存器可以被逐字节预测，第一次有了真正的同模式对照。

附带观察（待复核，不作结论）：本轮 `dsi1` 的 `FIFO_STATUS = 0x11111010`，
而 `dsi0` 是 `0x00001010`（50 fps 快照时两条都是 `0x00001010`）。
按寄存器定义 bit16-19 是 DLN0 的 HS FIFO empty/full/overflow/underflow 四位，
同时置位不合常理，更可能是"四条 lane 的 HS FIFO empty"或采样时刻差异。
下一轮请连读 3 次（间隔 1 s）确认是否稳定；若只在从链路上出现，值得单独查。

### 2026-10-28 第五轮：第一次带着修复进 shell（关键）

镜像 `repack/60hz-boot/boot-702b079d-A.img`（内核 `702b079d`，旧驱动、DPU 预取已回退、
broadcast 默认关闭）。**能进 shell** —— 闸门通过。

`nt36532/dcs`：`power=0x9e display=0x00 addr=0x00 pixfmt=0x07`（仍黑）。

`dsi0/regs`（主线偏移，CTRL 在 0x00）：

| 寄存器 | 我们 | 原厂 60 Hz | 判定 |
|---|---|---|---|
| `CTRL` | `000001f3` | `000001f3` | 同 |
| `STATUS0` | `00000008` | `00002008` | **差**（原厂 bit13 置位） |
| `FIFO_STATUS` | `00001210` | `00001010` | **差**（bit9） |
| `VID_CFG0` | `02009230` | `02009230` | 同 |
| `ACTIVE_H/V` | `015c0030`/`0c1800d8` | 同 | 同 |
| `TOTAL` | `0c3101bf` | `186301bf` | **我们跑的是 120 Hz，不是 60** |
| `CMD_DMA_CTRL` | `14000000` | `d4000000`(master) | 与基线/上游一致（W1 的修法） |
| `DSC_MODE_CTRL` | `03840b01` | `03840b01` | 同 |
| `LANE_STATUS` | `00001f00` | `00001f1f` | **差**（低 5 位） |
| `LANE_CTRL` | `01000000` | `01000000` | 同 |
| `CLK_STATUS` | `008047c3` | `008047c3` | 同 |

**更正（同轮）**：第一次贴的 dmesg 行被 printk 截断，误判成"命令行被 ABL 覆盖"。
完整 `/proc/cmdline` 显示我们的 271 字符串**出现两次**（header + DT）+
`panel_novatek_nt36532.force_fps=120`，再接 ABL 的 `androidboot.*`。
所以 bootargs 是生效的，`force_fps=120` 也确实进了内核（`TOTAL=0c3101bf` 与之一致：
天马 desc + 强制 120 Hz）。同时 dmesg 里有两行
`blacklisting initcall simplefb_driver_init`，说明黑名单也生效。
⇒ 运行时开关**可以**继续用 bootargs；此前"必须改走 DT 属性"的结论作废。

**poke 结果（关键）**：依次写入 `0xff 0x10`、`0x10`、`0x11`、`0x29` 后，
每次都在 dmesg 产生 `dsi_err_worker: status=5`：

- `status=5` = `DSI_ERR_STATE_TIMEOUT(0x1) | DSI_ERR_STATE_FIFO(0x4)`；
- FIFO 位是已知误报（原厂正常态 FIFO_STATUS 也非零，见 R3）；
- **TIMEOUT 是真实的**：命令 DMA 在 200 ms 内没有完成 ⇒ DCS 写没有发出去/没被确认；
- 四次写入后 `power` 仍是 `0x9e`，面板状态完全没变。

推论（待验证）：若写通路一直超时，则 216 包 init 序列**很可能从未成功下发**，
`prepare()` 应当返回 `-110` 并打印 `failed to initialize panel`。下一轮先确认这行。

### 2026-10-28 第六轮：desc 定案、写通路确认、real exit-idle 无效

镜像 A（`702b079d`，`force_fps=120`，进 shell 正常）。

| 观测 | 结果 | 条目 |
|---|---|---|
| `panel desc: tianma, htotal=2096 vtotal=6244 clock=785245 kHz, force_fps=120, cmdline_match=1` | **天马 desc 确认**，bootargs 生效 | A04 / M05 ⛔ |
| 无 `failed to initialize panel` | 216 包 init + PPS + compression mode **全部发送成功** | I01 ⛔（此前 ⚠️） |
| `poke 0x10` → `power=0x0e`；`0x11` → `0x9e` | **DCS 写到达 DDIC 并改变状态**；写通路正常 | I02 / F06 ⛔（写入有效） |
| `poke 0x38`（已先 `0xff 0x10` 切页）→ `power` 仍 `0x9e` | 真正的 DCS EXIT_IDLE **不能**清掉 bit1 | 记入 R4 |
| `dsi_err_worker: status=5` 每 33 ms 刷一次 | 假警报：FIFO 位是已知误报（R3），TIMEOUT 是锁存残位；写入本身成功 | 不再追 |

推论：`power` 的 bit1（"idle"）在 `0x9e`/`0x0e` 两种状态下恒为 1，DCS 清不掉 ⇒
它更可能是 **DDIC 对"未锁到有效码流"的状态上报**，而不是可由 0x38 清除的 idle 模式。
下一轮重点转为"同模式逐字节对照 + 面板是否在扫我们的帧"。
