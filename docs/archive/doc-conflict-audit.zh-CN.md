> 结构更新（2026-11-18）：`linux/` 独立 checkout 已删除；主线改由内核仓
> `linux-sm8450-liuqin` 的 `linux` remote（torvalds/linux）直接同步。本文中
> 出现的 `linux/` 只描述审计当时的结构。

# 文档矛盾审计与精简方案（2026-11-18）

> 基准：根 `AGENTS.md`（用户指定为正确）＋ `xiaomipad-6pro-mainline/docs/STATUS.zh-CN.md`
> （AGENTS 指定的唯一状态源）。
> 范围：工作区 43 篇非归档 md。已排除 `docs/archive/`、`repack/archive-7.0-notes/`、
> `linux/`、`linux-sm8450-liuqin/`（上游源码文档）、`.agents/skills/`（技能库）、
> `device/fingerprint/`、`device/gnome-control-center/`（第三方组件文档）。
> 取证：git 状态、`kernel/source.json`、workflow、`install-liuqin.py`、
> `device/firmware/` 清单、`repack/` 产物、ramdisk 哈希。
> 注意：工作树当前有未提交改动（`STATUS.zh-CN.md`、`display.md` 已改，
> `userspace-port.md` 未跟踪），本报告按磁盘上的版本审计。

---

## 1. 结论速览

| 类别 | 条数 | 说明 |
|---|---:|---|
| A. 有硬证据、可直接改文档 | 7 | 文件内容/代码即可判定，不需要你裁决策略 |
| B. 必须由你裁决 | 12 | 涉及"设备到底怎么装的/哪些能力算数/资产去留" |
| C. 同一文档内部自相矛盾 | 5 | banner 补丁式修补留下的裂缝 |
| D. 统计、命名、双语不同步 | 5 | 不影响结论但会误导后续文档 |

> 本版已并入子审计（install-docs）的补充发现：新增 A5–A7、C4、D4、D5，并加强 B1/B7 的证据。
> 其"FLASHING 扇区换算 16 GiB vs 128 GiB"经复核**不成立**（见 §7）；
> "A/B 轮换方案归属参考项目"因参考项目源码不在工作区、证据不足，未单列。

最严重的两处不是数字错误，而是**两套世界观同时存在**：

1. **"A 槽单系统、无 Android"（AGENTS/STATUS）** vs
   **"B 槽安装、Android 双系统、KernelSU 回切"（INSTALL-TESTING / FLASHING / STAGE2 / ksu README）**。
   后者不是零星残留，而是三篇安装文档的正文和树里的实际资产。
2. **"用户态停在参考项目 v0.6.0，还没有自己的发布包"（STATUS）** vs
   **双语 README 和 BUILD 仍把 `yzddmr6` 的 Releases 当作本项目安装包入口**。

---

## 2. 同一事实的不同取值（核心对照表）

| 事实 | AGENTS / STATUS（基准） | 其他文档的取值 | 证据 |
|---|---|---|---|
| 设备容量 | **128G**（AGENTS:10、STATUS:26、display.md:10） | **256 GB**：README.zh-CN:16/39/41/81、README.md:17/40/42/82、FLASHING.zh-CN:13、FLASHING.md:13、INSTALL-TESTING.zh-CN:5/9/12、INSTALL-TESTING.md:3/8/13、FINGERPRINT.zh-CN:11 | 文档互相冲突，硬件事实待你确认 |
| 启动槽 | **A 槽直启**（AGENTS:12/168、STATUS:28） | **单系统写 B 槽**：INSTALL-TESTING.zh-CN:27/164-165、STAGE2:49、install-liuqin.py:36；README.zh-CN:39 自己承认代码是 B | 代码与文档一致地"错"，实机是 A |
| 产品锁 `kernel/source.json` | 实际 `c03e1015c71d…`（source.json:6，提交 866df81） | **仍是 `db08160915e3`**：STAGE2:13/46/57 | 硬证据 |
| 安装是否在真机完成 | 设备**已经**装好并在跑（AGENTS:10-13） | **"单系统布局尚未在真机上安装"**：INSTALL-TESTING.zh-CN:13；**"从 A 槽启动……尚未测试"**：INSTALL-TESTING.zh-CN:279-280；**STAGE2:322 "S2-3 单系统布局未真机验证"** | 与设备现状直接冲突 |
| 安装器面向的容量 | 设备 128G（AGENTS:10） | **代码按 256GB 出厂表写死**：`tools/lib/liuqin_layout.py:70-71` "factory partition table of the 256 GB liuqin ... from a real tablet"（`STOCK_TOTAL_SECTORS=61731840`×4096≈252.9 GB） | 不只是文档：安装器整套是按 256GB 机器写的 |
| Android 双系统 | **没有 Android**（AGENTS:12、STATUS:27） | 提供"重启到 Android"、KernelSU 模块、`boot_b` 回退：FLASHING.zh-CN:57-60、INSTALL-TESTING.zh-CN:197-312/353、ksu README:3/10 | 树里确有 `liuqin-switch` 等资产 |
| 固件来源 ROM | **V14.0.9.0.TMYCNXM**（AGENTS:79、STATUS:15/137、STAGE2:48/70-77） | **OS2.0.6.0.VMYCNXM**：device/firmware/README.md:14/37 | 文档对同一批 blob 的来源说法不同 |
| 构建方式 | **只允许 CI**（AGENTS:28-38） | **本机交叉编译**：BUILD.zh-CN:24-25/32、BUILD.md:24-25/31 | 硬规则冲突 |
| 内核 CI workflow | `linux-sm8450-liuqin/.github/workflows/liuqin.yml`（AGENTS:34-36） | **`build.yml`**：STAGE2:28（同文 204 行又写 `liuqin.yml`） | 硬证据 |
| 指纹 | 未在 7.3 重测（FINGERPRINT:15-19） | **✅ 可用**（README.zh-CN:86） | 需要你定"✅ 的依据" |
| 相机 | 未验证、暂不优先（STATUS:99） | **🟡 部分支持、可预览拍照录像**（README.zh-CN:114）；CAMERA 自己说完整镜像未带相机启动 | 证据等级之争 |
| `boot_b` | **B 槽不参与**（STATUS:28） | **保存 Ubuntu boot 回退副本**：FLASHING.zh-CN:59、INSTALL-TESTING.zh-CN:210、ksu README:30 | 设计事实待确认 |
| 触控型号 | `nt36523` 驱动（STATUS:83） | **Novatek NT36532**（README.zh-CN:84、kernel-v73-divergence:159） | 命名/型号需统一 |
| 镜像状态 | c03e10 **已点亮**（STATUS:31、repack/README:10） | **"待刷"**：repack/c03e10-boot/README:1/74、17abc-boot/README:1、730fix-boot/README:1 | 硬证据（STATUS 有上机记录） |

---

## 3. A 组：有硬证据，建议直接改文档（只需你点头）

### A1. 产品锁仍写着旧提交
- `xiaomipad-6pro-mainline/docs/STAGE2-PERSISTENT.zh-CN.md:46`：
  "`kernel/source.json` **当前仍是 `liuqin-7.3 @ db08160915e3`**"；`:57` 同义重复。
- 实际 `kernel/source.json:6`：`"commit": "c03e1015c71d73ebc7ea9b323495e45fa6c00a0f"`，
  且提交 `866df81` 的信息就是"advance the product lock to the lit c03e1015c71d tip"。
- 处置：STAGE2 两处改为 c03e1015，并删掉"换内核前必须同步推进锁"的整段警告（已完成）。

### A2. repack 三篇 README 的状态是旧的
- `repack/c03e10-boot/README.md:1` "回到 17abc 基线（待刷）"、`:74` "本镜像，待刷"；
  `repack/17abc-boot/README.md:1`、`repack/730fix-boot/README.md:1` 同样标"待刷"。
- 反证：`STATUS.zh-CN.md:31` "已上机点亮、电量正常"；`repack/README.md:10` "当前运行"。
- 处置：把标题/表格里的"待刷"删掉；17abc 的 `:59`"最近一次已确认点亮：730fix"也应改为 c03e10。

### A3. BUILD 教人在本机编译，违反第一铁律
- `docs/BUILD.zh-CN.md:24-25` 要求 `apt-get install ... gcc-aarch64-linux-gnu ...`，
  `:32` 直接 `python3 tools/build-liuqin-kernel.py --jobs 12`；`docs/BUILD.md:24-31` 同。
- `AGENTS.md:28-38`：禁止 `make` / `build-liuqin-kernel.py` / 任何交叉编译器，唯一通道是 CI。
- 处置：删除"内核"章的本地编译步骤，改为"看 CI artifact + 本机只装配"；BUILD 与 CI 合并（见 §5）。

### A4. STAGE2 把内核 CI 写成了 `build.yml`
- `STAGE2:28`："推 `liuqin-7.3` 到 GitHub 触发 `build.yml`"。
- 实际推内核仓分支触发 `linux-sm8450-liuqin/.github/workflows/liuqin.yml`（push branches 含 `liuqin-7.3`，
  `runs-on: ubuntu-24.04-arm`）；`build.yml` 是集成仓自己的 workflow，靠 `kernel/source.json` 触发。
- 同文 `STAGE2:204` 已经正确写成"内核仓的 `liuqin.yml` 与集成仓的 `build.yml`"，说明是前言口误。
- 处置：`:28` 改为 `liuqin.yml`（或直接引用 AGENTS §0.1，不重复 workflow 名）。

### A5. 文档声称"安装器校验 A 槽活动"，代码没有这项校验
- `FLASHING.zh-CN.md:17`："程序要求 Bootloader 已解锁且 **A 槽活动**"；
  `:27`："型号、**槽位**或会话身份无法确认时，安装器必须停止"。
- 实际 `tools/install-liuqin.py:411-417` 只校验 `product: liuqin` 与 `unlocked: yes`，
  全文没有读取 `current-slot`；真正决定槽位的是 `:642-647` 的 `boot_slots()`。
- 处置：要么代码补校验，要么删掉"槽位"这项承诺。

### A6. STAGE2 说"硬 die"的 68/197 计数，代码其实是"警告"
- `STAGE2:166-167`："仍会硬 `die` 的是结构性防错：……DSP 恰好 68 个文件、
  固件树恰好 197 个文件"。
- 实际 `tools/build-liuqin-firmware-prep.sh:114` 与 `:194`：
  `[ "$dsp_count" = 68 ] || say "note: ... historical pin was 68"`、
  `[ "$file_count" = 197 ] || say "note: ... historical pin was 197"`——只打印，不退出。
- 处置：把这两项从"硬 die"清单移到"信息打印"。

### A7. STAGE2 的代码锚点指错位置
- `STAGE2:49` 证据列："`tools/lib/liuqin_layout.py:340-360`；`install-liuqin.py:36`"。
- 实际 `liuqin_layout.py:340-360` 是 `_feasible()`/`plan_layout()` 的尺寸计算；
  槽位在 `liuqin_layout.py:6-9` 注释与 `install-liuqin.py:642-647`。
- 处置：改锚点或删掉具体行号（只写函数名）。

---

## 4. B 组：需要你裁决的 12 项

> 每项给出选项；"证据倾向"只是我的判断，不是替你决定。

### B1. 设备容量到底是 128G 还是 256GB？
- 选项 A：**128G 正确**。则安装/刷机/指纹文档里的 "256 GB 机型/开发机/布局" 全部要改，
  安装文档的可信度也要重估（它描述的很可能不是这台机器）。
- 选项 B：**256GB 正确**（AGENTS/STATUS/display 写错）。则要改 3 篇基准文档，影响面更小但
  与 `AGENTS.md:10` 冲突。
- 证据倾向：设备是你手上之物，只能由你确认；文档层面 128G 只在 3 篇里出现，256GB 在 9 篇里出现，
  但 AGENTS 是权威，所以更像"安装文档整批继承了参考项目的 256GB 开发机"。
  **新增硬证据**：`tools/lib/liuqin_layout.py:70-71` 明写"factory partition table of the 256 GB
  liuqin, taken from a read-only inventory of a real tablet"，且 `STOCK_TOTAL_SECTORS=61731840`，
  按 4096 B/扇区约 252.9 GB。也就是说**安装器代码本身是按 256GB 机器写的**。
  如果本机真是 128G，那么这套安装器从一开始就不可能用于本机，"安装文档为何与实机不符"就有了统一解释。

### B2. 槽位：安装器/文档要不要整体改成 A 槽？
- 选项 A：**A 槽是唯一事实**，安装器代码、INSTALL-TESTING、FLASHING、STAGE2 全改 A。
  （STATUS §5 #11 已把它登记为代码缺口。）
- 选项 B：**保留 B 槽方案**，只在文档写明"本机是手动 A 槽安装，安装器仅供新装"。
- 证据倾向：A。但改代码属于工程任务，不在本次文档整理范围，可先改文档、代码另开一项。

### B3. 本机当初是怎么装的？（决定安装文档是"改写"还是"归档"）
- 选项 A：**用这套安装器装的**。那"单系统未在真机安装"（INSTALL-TESTING:13）就是错的，
  必须改成"已在 128G 单系统 A 槽完成"。
- 选项 B：**手工/另一套流程装的**。则 INSTALL-TESTING/FLASHING/STAGE2 描述的是参考项目安装器，
  应整体进 `docs/archive/`，另写一份本机恢复/重装简册。
- 证据倾向：文档内部证据偏向 B——安装器代码只写 B 槽（`install-liuqin.py:36`），
  而设备在 A 槽；且文档自己说单系统布局从未上机。

### B4. "A 槽启动组合尚未测试"这句要不要删？
- `INSTALL-TESTING.zh-CN:279-280`："早先版本中 Ubuntu 曾从 B 槽启动；从 A 槽启动时 Bootloader
  会搭配 A 槽的原厂 `dtbo_a` 与 `vbmeta_a`，这一组合尚未测试。"
- 与 AGENTS/STATUS（A 槽已点亮、当前运行）直接冲突。选项 A：删/改成"已实测"；
  选项 B：承认这句话成立，即"当前 A 槽运行的不是这套安装器产物"（回到 B3 选项 B）。

### B5. 树里的 Android/双系统资产留不留？
- 现状：`device/gnome-overlay/usr/local/sbin/liuqin-switch`、`liuqin-reboot-to-android.desktop`、
  `device/android/ksu-boot-ubuntu/` 都在树内，`build-liuqin-debs.sh:276-291` 还强制校验它们存在；
  INSTALL-TESTING:197-312 有整章"双系统切换"，`:353` 说完整包附 `liuqin_boot_ubuntu-v0.3.zip`。
- 与 AGENTS/STATUS "无 Android"、userspace-port:58 "明确不取 liuqin-switch/KSU" 冲突。
- 选项 A：**移除/停止打包**这些资产，文档删除 Android/双系统章，只留一句"历史资产在 git 历史/v0.6.0"。
- 选项 B：**保留资产但标"未使用"**，文档改成"本机不使用，仅历史/他机参考"。
- 证据倾向：B 成本最低；若目标用户态还要精简，A 更干净。

### B6. README 与 BUILD 里的 `yzddmr6` Releases 入口
- `README.zh-CN.md:16/50`、`README.md:17/51`、`BUILD.zh-CN.md:68`、`BUILD.md:72`
  都把 `github.com/yzddmr6/xiaomipad-6pro-mainline/releases` 当成本项目安装包来源。
- 但 STATUS §2 说我们停在 v0.6.0、没有自己的发布包；AGENTS 说参考项目不是上游。
- 选项 A：**重写双语 README 为本项目自己的 1 页首页**（导航＋状态指针＋构建/恢复入口），
  不再引用参考项目发布包；BUILD 里改成"本项目暂无公开发布包"。
- 选项 B：**把双语 README 整体归档**，根 `README.md` 作为唯一导航，`docs/` 从零写。
- 证据倾向：A（保留用户可见说明，但去掉"我们的发布包=他的发布包"的暗示）。

### B7. 固件池到底以哪个 ROM 为准？
- `device/firmware/README.md:14/37`："extracted ... from `OS2.0.6.0.VMYCNXM`"、
  "The pinned set is the validated OS2.0.6.0 baseline"。
- `STAGE2:48/70-77`：ROM 输入"全部用 V14.0.9.0.TMYCNXM"，OS2 只是"钉扎默认仍是 OS2 值"待替换；
  `AGENTS:79` 设备在装 V14；`tools/prepare-image-inputs.py:66` 等默认路径已是 V14。
- 选项 A：**V14 是唯一输入**，改 firmware README 的来源说明（并核对 197 个 blob 是否真的来自 V14）。
- 选项 B：**OS2 blob 是已验证基线**，保留现状，但在 STATUS 写明"固件池=OS2 基线，设备 ROM=V14"。
- 新增硬证据：`tools/lib/liuqin-rom-images.json:17-18` 仍钉 OS2：
  `"rom": "OS2.0.6.0.VMYCNXM"`、`"package": "liuqin_images_OS2.0.6.0.VMYCNXM_…_15.0_cn"`；
  而 `build-liuqin-sensors-stack.sh:14`、`build-liuqin-firmware-prep.sh:15` 的默认路径已是
  `V14.0.9.0.TMYCNXM`。**同一管线里两套默认值并存**，不只是文档措辞问题。
- 证据倾向：需要看 `firmware.manifest` 的生成记录；纯文档无法判定，这正是要你裁的点。

### B8. 指纹能不能标 ✅？
- README.zh-CN:86 标 ✅ 并引用 v0.6.0 时代验证；FINGERPRINT.zh-CN:15-19 明确"没有在 7.3 内核上重测过"。
- 选项 A：保持 ✅，但备注"证据来自 v0.6.0 时代，7.3 未重测"。
- 选项 B：降为 🧪 未验证，直到上机重测。
- 证据倾向：B 更符合 STATUS 的"先取证"纪律；A 需要用一次冷启动实测来支撑。

### B9. 相机标 🟡 还是 🧪？
- README.zh-CN:114 标 🟡；STATUS:99 说"未验证，暂不优先"；CAMERA 说验证是 `fastboot boot`
  临时内核、项目完整镜像未带相机启动。
- 选项 A：🟡 + 括注"仅临时内核验证，产品镜像未验证"。
- 选项 B：🧪，等完整镜像验证后再升级。

### B10. `boot_b` 到底有没有 Ubuntu 副本？
- STATUS:28 "B 槽不参与"；FLASHING.zh-CN:59 / INSTALL-TESTING:210 / ksu README:30 说
  `boot_b` 保存 Ubuntu boot 镜像供 Bootloader 回退。
- 选项 A：本机确实没有，删掉所有 `boot_b` 回退描述。
- 选项 B：本机有（安装时写入），STATUS 的"不参与"只指"不从 B 启动"，需改写措辞。
- 证据倾向：需要你在设备上 `fastboot getvar`/读分区确认；文档无法自证。

### B11. 触控/面板型号写法
- STATUS:83 用 `nt36523` 驱动；README.zh-CN:82/84 与 kernel-v73-divergence:159 写 "Novatek NT36532"。
- 选项 A：统一为"触控 IC/驱动 `nt36523`，面板驱动文件 `panel-novatek-nt36532.c`"（两者分开写）。
- 选项 B：以 NT36532 为准，改 STATUS。
- 证据倾向：A（内核里确实是 `input/touchscreen/nt36523/` 与 `panel-novatek-nt36532.c` 两个名字）。

### B12. "唯一上游" 与 "based on sm8450-mainline" 的表述
- AGENTS:58 "唯一上游是 Linux 主线源码仓 `linux/`"；BUILD.zh-CN:16 / BUILD.md:16 写
  "内核仓库基于 `sm8450-mainline/linux`"；`kernel/source.json:4` 也记 `upstream_url=sm8450-mainline`。
- 选项 A：统一为"上游=主线 `linux/`；sm8450-mainline 只是历史来源，不再作为上游"。
- 选项 B：保留 sm8450 作为"内核仓来源"，但明确它不是合并上游。
- 证据倾向：A（与 AGENTS §1 一致），并在 source.json 里把 `upstream_url` 改成主线仓或加注释。

---

## 5. C 组：文档内部自相矛盾（banner 修补的后遗症）

### C1. INSTALL-TESTING 同时说"已装好"和"从未装过"
- `:5` 首次安装已在 256GB 机型验证；`:9-12` v0.6.0 双系统完整安装成功；
- `:13` "单系统布局……尚未在真机上安装"；`:279-280` "从 A 槽启动……尚未测试"；
- 但 `:165` 自己加了一句"**本机实际是 A 槽直启，单系统也不在 B 槽**"。
- 结论：文档描述的是"参考项目安装器的验证史"，却用"本机"口吻写；这正是 B3 要裁决的根。

### C2. FLASHING 的 banner 与正文打架
- `:31-33` banner："本文的'双系统'一节与本机无关……没有切换存储区"；
- `:55-60` 正文仍完整保留"双系统""Ubuntu 提供重启到 Android 入口""`boot_b` 保存副本"。
- 处置：要么删节，要么把 banner 升级为"整节作废"并把正文移入 archive。

### C3. STAGE2 的锁与 workflow 前后矛盾
- `:13/:46/:57` 说锁是 db0816；`:45` 说当前 tip 是 c03e1015；`:204` 又说内核仓用 `liuqin.yml`；
  **`:247` 却写"产物锁（kernel/source.json）已推进到同一 commit，commit 门已通"**。
- 同一篇里锁的状态出现"仍落后"与"已推进"两种互斥说法（相隔约 190 行）。

### C4. STAGE2 对"ROM 哈希默认值"给出两种相反说法
- `:163-164`（§4 正文）："ROM/固件的**内容哈希已全部按本机 V14.0.9.0 实测值设为默认**，
  并且只作信息打印"。
- `:322`（§7 缺口表 S2-5）："ROM 内容钉扎默认仍是 OS2 值，V14 提取物的真实哈希待填"。
- 加上 `:48` 表格："ROM 内容哈希钉扎默认仍是 OS2 值"——同一篇里
  "已全部改成 V14"与"仍是 OS2、待填"并存。

### C5. 双语 README 的自我定位与正文矛盾
- 开头 `README.zh-CN.md:6-12`："本文是参考项目 v0.6.0 的版本说明……'最新版本'指那个项目"；
- 正文 `:16` "v0.6.0 正式版已发布"、`:22` "提供保留 Android 的安装布局"、`:50` "请从 GitHub Releases 下载"。
- 读者只会看到"这个项目发布了 v0.6.0，去下载"，banner 拦不住。

---

## 6. D 组：统计、双语、措辞

| # | 现象 | 位置 | 处置建议 |
|---|---|---|---|
| D1 | XM 引用数 **148 vs 139** | STATUS:76 "148 处 XM 引用"；repack/c03e10-boot/README:16 "17abc 里 XM 协议本来就完整（139 处引用）" | 两者是不同 tip 的计数，但文档没写口径；统一成"c03e1015 树 148 处"或删数字 |
| D2 | 中英 README 入口不同步 | 中文 README.zh-CN:57 有 Stage2 入口，英文 README.md:53-58 没有 | 决定"只维护中文设备文档"后，英文 README 只留导航，不再逐项翻译 |
| D3 | "云端 2 核/11G" vs "本机 2 核/11GB" | STATUS:34 vs AGENTS:33 | 同一台机器两种叫法；STATUS 改为"本机（2 核/11 GB）" |
| D4 | 中英 INSTALL 不同步（不只是排版） | 中文 INSTALL-TESTING.zh-CN:165 有内联更正"本机实际是 A 槽直启，单系统也不在 B 槽"；英文 INSTALL-TESTING.md:202-206 没有。英文另有中文没有的结论：`:411-412` "Release images leave it disabled by default."、`:216-217` 控制通道失败即停止 | 以中文为源重写英文，或删英文版 |
| D5 | `--layout` 被称为"默认" | INSTALL-TESTING.zh-CN:17 "默认把 Ubuntu 写 B 槽（`--layout linux-only`）"；`install-liuqin.py:199-201` 无 `default=`，`:384` 缺省直接 `parser.error`（必填） | 改成"指定 `--layout linux-only` 时" |

另外：`STATUS:34` 把工作机叫"构建主机"，容易被读成"可以在上面构建内核"，
与 AGENTS 0.1 的"不具备构建能力"字面冲突，建议改成"工作机（只做装配/打包）"。

---

## 7. 已核查、判定为"假阳性"的项（避免误改）

- **`v7.3` 的提交号**：`git rev-parse v7.3` 返回 `091b0638…`（annotated tag 对象），
  其 peeled commit 是 `c03c1a14507d`，与 `kernel-v73-divergence.md:3` 一致，不是矛盾。
- **divergence 计数**：AGENTS:117、STATUS:143、kernel-v73-divergence:6 都是 174/63/0，一致。
- **firmware 文件数**：AGENTS:173 说 203，`find device/firmware -not -type d` 也是 203
  （197 blob + 4 符号链接 + README + manifest）；firmware README:3 的"197 binary files"是另一口径。
- **ramdisk**：`out/ramdisk` 40,326,354 B / `a04d2b25…`，重建版 30,930,155 B / `1690e9ec…`，
  与 AGENTS/STATUS/out README 全部一致。
- **FLASHING 的"16 GiB"不是换算错误**：`FLASHING.zh-CN.md:18` 已声明容量按 **512 字节扇区**计，
  `33554432 × 512 B = 16 GiB`，与同表"逻辑块大小 4096"并不冲突（4096 是文件系统/设备块大小，
  不是该列的计数单位）。子审计曾据 4096 判为 128 GiB，复核后不成立。
- **`build-info.json` 的双 commit 不是矛盾**：c03e1015 的 artifact 里
  `commit=c03e1015…`、`product_kernel_commit=db0816…`，后者是**构建当时的锁值**；
  锁在提交 866df81 才推进，所以这是历史元数据，不是文档冲突。
- **repack 产物大小**：50,065,408 / 50,061,312 / 59,457,536 与各 README 一致。
- **内部链接**：43 篇文档的所有相对链接与图片路径均可解析，无死链。
- **中英 BUILD**：结构不同（英文分段更细），但事实陈述同源，未发现互相矛盾；
  中英 INSTALL 的实质差异见 D4。

---

## 8. 精简方案

### 8.1 目标：43 篇 → 14 篇 + 6 个数据/组件登记

| 保留/新建 | 内容 | 来源 |
|---|---|---|
| `AGENTS.md` | 只留 agent 操作规则、禁区、装配流程；状态全部指向 STATUS | 原文删去重复状态 |
| `README.md`（根） | 1 页导航：目录地图、铁律、指针 | 原文已接近，微调 |
| `docs/STATUS.zh-CN.md` | **唯一事实源**：设备表、已工作、待办、决策记录 | 保留，补"决策记录"章 |
| `docs/kernel-v73-divergence.md` | 偏离清单 + 7.4 决策 | 保留 |
| `docs/userspace-port.md` | 用户态取舍提案 | 决策后并入 STATUS 或删除 |
| `docs/INSTALL.zh-CN.md`（新） | 本机实际安装/恢复/重装（A 槽单系统） | 合并 INSTALL-TESTING + FLASHING + STAGE2 的有效部分 |
| `docs/BUILD.zh-CN.md` | CI-only 构建 + 本机装配 + 发布 | 合并 BUILD + CI |
| `docs/display.md` | 显示结论与陷阱 | 保留 |
| `docs/AUDIO.zh-CN.md` | 外放 TDM | 保留 |
| `docs/FEATURES.zh-CN.md`（新） | 相机/指纹/快充/Waydroid 的设备特定细节 | 合并 4 篇中文 |
| `ci/README.md`、`out/README.md`、`repack/README.md` | 本机数据登记 | 保留；镜像 README 降级为构建日志 |
| `CONTRIBUTING.md` | 贡献入口 | 保留 |
| 组件文档 | `device/firmware/README.md`（改来源与口径）、`device/android/ksu-boot-ubuntu/README.md`（标"本机不使用"） | 保留但纠偏 |

**归档/删除**：`INSTALL-TESTING.zh-CN.md`、`FLASHING.zh-CN.md`、`STAGE2-PERSISTENT.zh-CN.md`
（正文进 archive，有效部分进 INSTALL）；4 篇中文功能文档（内容进 FEATURES）；
4 篇英文功能文档（不做双语维护则删，或与中文同源生成）；
`README.zh-CN.md`/`README.md`（重写为项目首页，原文进 archive）。

### 8.2 五条长期规则

1. **单一事实源**：提交号、镜像哈希、槽位、容量、ROM 版本、文件数只在 STATUS 写一次；
   其他文档只能链接，不得复述数字。
2. **文档头元数据**：每篇前 3 行写明"适用设备 / 内核 tip / 最后核对日期 / 状态（现行|提案|历史）"，
   取代现在这种"正文不动、顶部加 banner"的修补方式。
3. **双语策略**：面向用户的 `README`、`BUILD` 保留中英；设备取证类（INSTALL/display/AUDIO/
   FEATURES/divergence）只维护中文，英文版直接删，避免 8 篇一起漂移。
4. **归档即冻结**：过时文档移入 `docs/archive/` 并从索引与 grep 范围移除；
   archive 里的"下一步/未解决"永远不再当任务。
5. **数字可复核**：容量/文件数/冲突数由脚本或命令生成，并在文档里写明测量口径与时间点。

### 8.3 执行顺序（建议）

1. 你先裁决 §4 的 B1–B12（可只回编号+选项）。
2. 把裁决结果写进 STATUS 新增的"事实基线与决策记录"表。
3. 修 A1–A7（纯文档，约 1 小时）。
4. 重写双语 README 为项目首页；原 README 归档。
5. 合并安装三篇 → `INSTALL.zh-CN.md`；旧三篇归档。
6. 合并 BUILD+CI → `BUILD.zh-CN.md`，删除本地编译章。
7. 合并 4 篇功能文档 → `FEATURES.zh-CN.md`；修 firmware/ksu 组件文档。
8. 统一 `repack/README.md` 为唯一镜像登记；三篇镜像 README 去掉"待刷"，保留构建记录。
9. 跑链接检查（现有做法：解析全部相对链接）＋ 全文 grep 关键数字，最后更新 STATUS 索引。

预计文档量从 43 降到 14＋6，重复事实从 ~30 处降到 1 处；之后每次内核升级只需改 STATUS 与
divergence 两篇。

---

## 9. 需要你回答的决策清单

按此格式回复即可（示例：`B1=A, B2=A, B3=B ...`）：

| 编号 | 问题 | 选项 |
|---|---|---|
| B1 | 设备容量 | A=128G（改安装文档） / B=256GB（改 AGENTS/STATUS/display） |
| B2 | 槽位 | A=全面改 A 槽（含安装器代码另立项） / B=文档注明本机手动 A 槽、安装器保留 B |
| B3 | 本机安装方式 | A=安装器装的（改"未在真机安装"） / B=手工装的（安装三篇整体归档） |
| B4 | "A 槽组合尚未测试" | A=删/改为已实测 / B=保留（承认当前系统不是该安装器产物） |
| B5 | Android/双系统资产 | A=移除并停打包 / B=保留但标"未使用" |
| B6 | 双语 README | A=重写为本项目首页 / B=整体归档，根 README 唯一导航 |
| B7 | 固件来源 ROM | A=V14 为唯一输入（改 firmware README） / B=OS2 为已验证基线（STATUS 说明并用） |
| B8 | 指纹状态 | A=✅+备注未在 7.3 重测 / B=🧪 未验证 |
| B9 | 相机状态 | A=🟡+备注仅临时内核验证 / B=🧪 |
| B10 | `boot_b` 角色 | A=本机没有副本，删描述 / B=有副本，改 STATUS 措辞 |
| B11 | 触控/面板型号 | A=分开写 nt36523 驱动 + panel-nt36532 文件 / B=统一 NT36532 |
| B12 | 上游表述 | A=只认主线 `linux/`，sm8450 仅历史 / B=保留 sm8450 作为来源说明 |

A1–A7 属于硬证据修正，若无异议我会在精简时一并改掉（可回复"A 组照改"）。
