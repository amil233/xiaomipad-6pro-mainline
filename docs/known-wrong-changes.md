# liuqin 显示：已知错误改动与误判登记表

> 目的：把**已经确认是错的**改动和**已经吃过亏的判读方式**集中记下来，避免再犯。
> 每条都写清：当初怎么想的、实际错在哪、证据、现状、以后怎么防。
> 新增条目只追加、不删除；改回之后也要留着。
> 相关文档：`docs/diff-308065ef-vs-head.md`、`docs/display-panel-checklist.md`、
> `docs/display-driver-plan.md`、工作区 `AGENTS.md`。

---

## 1. 代码改动类

### W1 `CMD_DMA_CTRL` 把厂商 master 值写到了每一条链路

| 项 | 内容 |
|---|---|
| 位置 | `drivers/gpu/drm/msm/dsi/dsi_host.c` `dsi_ctrl_enable()` |
| 提交 | 引入 `f5e92f4`；修正 `cec2a7b5` |
| 当初的想法 | 原厂快照 `dsi0 0x3c = 0xd4000000`，于是把 `0xd4000000`（BROADCAST_EN\|MASTER）写到每个 host |
| 实际错在 | 原厂 **dsi1 是 `0x94000000`**（只有 BROADCAST_EN，没有 MASTER）：厂商是"master 踢一次、硬件广播"；而主线是"两条链路各写一份 DMA、同时 trigger"，两种机制互斥。两条都置 broadcast+master，会让同一串 DCS 在两路重复/交错，分页写被打乱 |
| 证据 | 原厂 `dsi0_ctrl_reg` / `dsi1_ctrl_reg` 的 `0x3c` 行；CAF `dsi_ctrl_hw_cmn.c:861-876`（`en_broadcast→BIT31`、`is_master→BIT30`） |
| 现状 | 默认恢复上游 `0x14000000`；旧行为留在 `msm.dsi_cmd_broadcast=1` |
| 以后怎么防 | 对照厂商寄存器时**必须逐链路比**，不能只看 master；看到一个"厂商值"先问"这个值是按哪条链路、哪个上下文写的" |

### W2 `INTF_CONFIG` bit31 单独置位，没有配对写 `INTF_PROG_FETCH_START`

| 项 | 内容 |
|---|---|
| 位置 | `dpu_encoder_phys_vid.c` `programmable_fetch_config()` |
| 提交 | 引入 `f5e92f4`；回退 `702b079dbeb3` |
| 当初的想法 | 厂商 `INTF_CONFIG = 0x80800000`（bit31 置位），我们也把 bit31 打开 |
| 实际错在 | bit31 与 `PROG_FETCH_START` 是**成对**的，起点由同一结构体的 `fetch_start` 写入。本机 `vbp+vsw = 216 ≥ worst_case 24`，`programmable_fetch_get_num_lines()` 恒返回 0（"prefetch is not needed"）；把 `f.enable=1` 挪出 `if` 之后，就变成"开关打开、起点写 0"，即把预取放在第 0 行（有效区内），`dpu_hw_intf.c` 注释明说这是 undefined |
| 证据 | `dpu_8_1_sm8450.h:318`（worst case 24）；`dpu_hw_intf.c:287-290` 的注释；基线镜像 `308065ef` 不启用该特性且能进 shell |
| 现状 | 已回退成上游写法（`f.enable` 只在算出真实起点时才置位） |
| 以后怎么防 | **一对比对**：任何"对照厂商某个 bit"的改动，先找出这个 bit 的配对寄存器/字段，两个一起比、一起写 |

### W3 `CLKOUT_TIMING_CTRL` 里硬编码 `0x13e0391f`，仅按 `mode->clock` 匹配

| 项 | 内容 |
|---|---|
| 位置 | `dsi_host.c` |
| 提交 | `f5e92f4`（保留至今） |
| 当初的想法 | 厂商 144 Hz 下该寄存器是 `0x13e0391f`，我们只写了 `T_CLK_POST|T_CLK_PRE` 两个字段 |
| 风险 | 用"`mode->clock == 1937416`"这种魔法数当开关；只要将来出现另一个 1937416 的模式或 porch 被改动，就会静默命中/失配。60/120 Hz（785245 kHz）目前不受影响 |
| 证据 | `grep '0x13e0391f'`；原厂快照只有 50/60 两条实采，144 的这份值来自文档叙述，未在 `out/vendor-display` 原始文件里找到 |
| 现状 | 保留但**未验证**；60/120 路径不生效 |
| 以后怎么防 | 不用魔法数匹配模式；若确需厂商值，用 desc 字段或 DT 属性表达，并且**先采到同模式的原始寄存器** |

### W4 写 `DSI DSC` 的 `0x2a4..0x33c`（39 个影子寄存器）

| 项 | 内容 |
|---|---|
| 提交 | 引入 `f5e92f4`；回退 `210577a1e188` |
| 当初的想法 | 认为厂商在这些偏移上有值，我们也照写 |
| 实际错在 | 官方只写 `0x2a0`（`VIDEO_COMPRESSION_MODE_CTRL`），其余是 PPS/编码器的 shadow，写它们没有意义，还可能覆盖硬件自算值 |
| 现状 | 已回退 |
| 以后怎么防 | 寄存器块"照抄"之前，先确认它是**编程寄存器**还是 **shadow/镜像**；只写文档/官方驱动里明确写的那几个 |

### W5 天马 desc 默认 144 Hz

| 项 | 内容 |
|---|---|
| 提交 | 引入 `d27563567362`；改 60 Hz `c4ba514b` |
| 当初的想法 | 原厂 Android 运行态是 144 Hz（`dri-state` 也见过 50 Hz），就用 144 |
| 实际错在 | 厂商 **init 序列自己编的是 120 Hz 的 porch 组**（`b3 40 b2 91`、`3b 03 d8 1a 0a 0a 00`），144 需要运行时再发 `b3 00 b2 00`。把 144 当默认，等于让"面板被初始化成 120 Hz 的模式"和"主机送 144 Hz 的时序"不一致；而且 144 的 porch 数字从未在 DTBO 或原始快照里出现过 |
| 证据 | `repack/e15.dts:11087-11221`（只有一个 `timing@0` = 120 Hz）；原厂 60 Hz 实测能对上 `TOTAL=0x186301bf` |
| 现状 | 天马默认 60 Hz；144/120 由 `force_fps` 选 |
| 以后怎么防 | **init 序列里编进去的模式，才是面板的默认模式**；运行时 dfps 的档位不能当默认 |

### W6 删掉旧驱动，换上一个还看不见的新驱动

| 项 | 内容 |
|---|---|
| 提交 | `5fa8a9a`（删 `panel-novatek-nt36532.c`）→ `68c7cfa5`（加回） |
| 当初的想法 | 上游化，直接切到 `panel-novatek-nt36523.c` |
| 代价 | 新驱动在能进 shell 之前就复位，于是 debugfs、poke、`no_dsc`、`skip_panel_init` 全部失去；此后所有实验都只能盲做，直到把旧驱动加回来 |
| 现状 | 两个驱动都在树里，配置选旧驱动做诊断，新驱动是产品目标 |
| 以后怎么防 | **换掉一个能观测的实现之前，先确认新实现能被观测**；"能编译 + 能 probe"不等于"能观测" |

### W7 `CONFIG_CMDLINE_FORCE` 强行接管命令行

| 项 | 内容 |
|---|---|
| 提交 | 引入 `1245c30`；去掉 `30771ea` |
| 当初的想法 | `fastboot boot` 有时只给 bootloader 的命令行，拿不到 `console=drm_log`，于是把整条串编进内核强制覆盖 |
| 实际错在 | 强制串是 DTB 串的**子集**，丢了 `initcall_debug ignore_loglevel rootwait panic=15 mtdoops.dump_oops=1 qcom_q6v5_pas.slpi_auto_boot=0`；而两张开了 FORCE 的镜像（`3b7bf64` 新驱动、`c4ba514b` 旧驱动）都在 shell 之前复位，所有不开 FORCE 的镜像都能进 shell |
| 证据 | 见 `docs/diff-308065ef-vs-head.md` 与 `repack/60hz-boot/README.md` |
| 现状 | 已去掉；命令行回到"DTB 写 + ABL 追加"，也因此可以在装配镜像时逐张改模块参数 |
| 以后怎么防 | **不要用"强制覆盖"来绕过一个偶发的命令行丢失**；先保留原有全部参数，再加需要的；并且每张镜像都把 `/proc/cmdline` 留证 |

---

## 2. 实验设计类（做过但结论无效）

| 编号 | 实验 | 为什么无效 |
|---|---|---|
| E1 | `no_dsc=1`（第一轮） | `enable()` 里仍无条件发 PPS：DSI 关了压缩、面板还被要求按 DSC 解码。缺陷后来才修（`308065ef`），那一轮作废 |
| E2 | `vendor_phy_timing=1` / link flags / clock lane LP | 现象完全不变，已排除并 revert（`df4055832`、`2848bd5b`），不要重跑 |
| E3 | `skip_panel_init=1` | 同上，仍黑；只能说明"单独跳过 init 不足以点亮"，不能证明 init 无关 |
| E4 | 「6.17 + 天马 desc 同样黑」 | 那次运行用的是哪个 desc **没有日志证据**；ABL 串里带模块名，命令行的来源也不确定 |
| E5 | 用 50 fps 的原厂快照和 120 fps 的主线寄存器逐项比 | 模式不同，`TOTAL`/`CLKOUT` 天然不同，比出来的"差异"是噪声 |
| E6 | 用 144 Hz 运行态数字当初值 | 144 的 porch 从未在任何原始快照里出现；DTBO 只有 120 |

---

## 3. 判读陷阱（这次踩过的）

| 编号 | 错误判读 | 正确做法 |
|---|---|---|
| R1 | 把 `CMD_DMA_CTRL` 的 bit30 当成 broadcast | bit31 = BROADCAST_EN，**bit30 = is_master**（CAF `dsi_ctrl_hw_cmn.c:861-876`）；先读定义再解释 |
| R2 | 把 DRM 的 `mode->clock`（785245 kHz）当成 DSI bit clock | 实际 bit clock 是 1,007,032,320 Hz：由 `dsi_get_pclk_rate()` 折半 + DSC 压缩后算出的 pclk 167,838,720 / byteclk 125,879,040 ⇒ ×8 |
| R3 | `FIFO_STATUS` 非零就当错误 | 原厂正常显示时也是 `00001010`（bit12 = DLN0 LP FIFO empty）；主线对任何非零都报 error，属误报 |
| R4 | `0x0a` 的 bit0/bit1 当"booster/idle"定论 | 厂商期望值 `0x9d` 与我们读到的 `0x9e` 只差这两位，语义不可靠；用 `0x45` 扫描行 + 画面作判据 |
| R5 | "init 序列逐字节一致 ⇒ 运行时没问题" | 静态比对只证明**该发什么**，不证明**发了、被接受**；必须有运行时日志/寄存器证据 |
| R6 | "能 boot ⇒ 驱动/时序正确" | 能 boot 只说明内核没死；面板可以完全没被初始化 |
| R7 | 厂商快照里的值，在任何原始文件里 grep 不到却当事实引用 | 每条厂商值必须能指到 `out/vendor-display/` 的某个文件某一行；找不到就标"文档叙述，需重采" |
| R10 | **在厂商页里读 DCS 寄存器**：`0xff 0x27` 之后读 `0x0a` 得到 `0xe4`，误以为"面板状态变了" | 每读一次 DCS 前先确认当前页码（`0xff 0x10` 才是标准 DCS 页）；换页后的寄存器含义完全变了 |
| R9 | **量了 `intf_1` 的帧计数就宣布"DPU 在出帧"**——而编码器实际用的是 `intf_2`（boot 日志 `DIAG vid_enable: intf2 state=1 -> ENABLING`） | 读计数器前先确认"这个块是不是当前路径上的那个"：`state` 里的 sspp/crtc、`DIAG vid_enable` 的 intf 编号、`INTF_MUX` 指向的 PP，三者要对得上 |
| R8 | **把 `caf-display/` 当厂商驱动**（它是社区实现，与设备实际 `msm_drm.ko` 未必同源） | `caf-display` 只能提出假设（B 级证据），结论必须由本机原厂运行态/DTBO/实测确认；PPS 字节、RC 字段、`h_active` 这类"厂商会怎么做"的推断都要标明是参考 |

---

## 4. 每次改动前的自检清单

1. 这个值的**来源**是哪个文件的哪一行？（不是"文档里写过"）
2. 它是不是**成对寄存器**的一半？（bit31↔FETCH_START；PPS↔compression；PPS↔pic_width/slice）
3. 对照的厂商快照是不是**同一模式**？（60/120/144/50 的 `TOTAL`/`CLKOUT` 天然不同）
4. 改动是**逐链路**的吗？（master/slave 可能不同）
5. 生效条件是"永远成立"还是"永远不会成立"？（`vfp_fetch_lines==0` 这种恒假/恒真分支最容易埋雷）
6. 有没有把**能观测的实现**换掉，换成观测不到的？
7. 这次改动能不能在**一次启动内**被观测到？观测手段是什么？
8. 命令行/配置改动是否保留了原有全部参数？（不要"强制覆盖"）
