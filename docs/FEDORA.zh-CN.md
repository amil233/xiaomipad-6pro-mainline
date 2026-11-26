# 把平板换成 Fedora KDE Plasma Mobile（进行中）

一句话：平板上的系统从 Ubuntu 26.04.1 + GNOME 换成 Fedora 45 的 KDE Plasma
Mobile，根文件系统仍然放在 `userdata` 的 ext4 上，启动方式不变。

这份文档写在这个分支（`liuqin-installer-fedora`）上。Ubuntu 那条线的东西
（`INSTALL.zh-CN.md`、`BUILD.zh-CN.md`、`STATUS.zh-CN.md` 以及原来的 workflow）
保持原样，不在这里改。

## 为什么要单独开两条分支

换发行版要动的东西不少：取根的方式、打包格式、桌面定制、安全模块。混在
Ubuntu 那条线上会把已经能用的文档和流程搅乱，也没法对比。所以：

| 仓库 | 分支 | 干什么 |
|---|---|---|
| 内核仓 `linux-sm8450-liuqin` | `liuqin-7.3-fedora` | 内核代码和驱动与 `liuqin-7.3` 完全一样；这个分支只是让 CI 也在这里构建，将来内核侧的 Fedora 改动也只落在这里 |
| 集成仓 `xiaomipad-6pro-mainline` | `liuqin-installer-fedora` | 取 Fedora 的根、把内核和设备文件打成 RPM、装配镜像、新的 workflow |

## 哪些东西不变

`boot.img` 的组成、initramfs（`initramfs/init`）、根文件的哈希清单、
分区表（`boot_a` + `userdata`）、`provision-liuqin-from-persist.sh`、
`resize2fs`、以及把镜像打成 tgz 分片再上传的方式。

## 换成什么

| 现在（Ubuntu 线） | Fedora 线 |
|---|---|
| 根来自 Ubuntu ISO 里的 casper | 根来自 Fedora Live ISO 里 ext4 的 `rootfs.img` |
| `dpkg-deb` 打 5 个 deb，chroot 里 `apt-get` + `dpkg -i` | `rpmbuild` 打 RPM，chroot 里 `dnf install` |
| 内核包是 `.deb` | 内核先打成**一个** RPM |
| 桌面是 GNOME，定制在 `device/gnome-overlay` | 桌面是 Plasma Mobile，定制要重写 |
| 内核里只有 AppArmor，SELinux 没编进去 | 内核编上 SELinux，先用 permissive |
| 根是 ext4 | 还是 ext4（不用 btrfs） |

## 分五步，每步的"算过"标准

1. **取出 Fedora 的根。** 下载 Live ISO、核对哈希、解开，得到一棵能 `chroot`
   进去的目录树，并记录清单。
   算过：`chroot` 里能执行 `rpm -qa`，`systemd` 在，树的大小能放进 8 GiB 镜像。
2. **内核配好并打成一个 RPM。** 内核里加 SELinux，把 Image 和模块打成一个
   RPM，装进第 1 步的树里。
   算过：装完后 `/usr/lib/modules/<版本>/modules.dep` 存在，现有的根目录检查
   （`systemd` 在、标记文件在、`kernel.release` 在）能通过。
3. **装配成镜像。** 生成 ext4 的 `rootfs.img`、配套 `boot.img`、哈希清单，
   打成 tgz 分片。
   算过：`e2fsck` 通过、卷标是 `LIUQIN_ROOT`、`rootfs.img` 里有 `native-root/`
   和内核模块。
4. **第一次上机。** 刷 `boot_a` 和 `userdata`，进 Plasma Mobile，能建用户。
   算过：冷启动三次都进桌面；`provision-liuqin-from-persist.sh` 和
   `resize2fs` 按 `INSTALL.zh-CN.md` 第 2 节走通。
5. **收尾。** 把 GNOME 那套定制换成 KDE 的等价物，SELinux 从 permissive 收紧，
   硬件逐项检查。
   算过：每项硬件有明确结论，能回滚到 Ubuntu 线。

前四步里前三步都在 CI 上做，不碰平板；第 4 步才需要平板。

## 现在做到哪里

- 分支已建好。内核分支多了一条 CI 触发规则（`liuqin-7.3-fedora` 也会构建），
  并且构建时会去取集成仓的 `liuqin-installer-fedora` 分支，这样用到的是这份
  配置（带 SELinux），不会取到 Ubuntu 线那份。
- 内核的 SELinux 开关写进了 `device/configs/liuqin-fedora.config`，并且加进了
  `kernel/source.json` 的配置列表，所以这个分支构建出来的内核带 SELinux。
- **第 1 步已跑通**（workflow 15 分钟）：Fedora 45 KDE Mobile 的根 6107 MiB、
  139,950 个文件、1719 个包；`plasma-mobile 6.8.1`、`plasma-workspace 6.8.1`、
  `plasma-setup 6.8.1`、`selinux-policy-targeted 45.23`、`systemd 262` 都在；
  SELinux 配置是 `enforcing`，策略已装好。自带内核是 7.2.11，`/boot` 占 515 MiB。
  这个根能直接放进 8 GiB 的 ext4 镜像。
- 第 2 步的打包脚本 `tools/build-liuqin-kernel-rpm.sh` 已写好，workflow 里也
  接上了，跑到装包这一步了。打出来的是一个 `kernel-liuqin` 包，版本形如
  `7.3.0-0.1.g<commit>`（RPM 的 Version/Release 里不能有 `-`，所以拆开写），
  真正的 `uname -r` 记在 `Provides: kernel-uname-r`。装包前会先删掉 Fedora
  自带的 `kernel*` 包和 `/boot` 内容。

## 还没确认的事

- Live ISO 里那个文件仍叫 `LiveOS/squashfs.img`，但从 Fedora 42 起是 EROFS
  （2.34 GB）。按日志确认：**这层 EROFS 解出来就是根**，里面没有
  `LiveOS/rootfs.img`，只有 `boot/`、`usr/` 这些正常目录。脚本已按这个改：
  只认 `LiveOS/rootfs.img` 这个固定位置，没有就把打开的树当根。
- 这棵树里的 `boot/`（515 MiB）和 7.2.11 的内核是用不上的：我们从 `boot_a`
  启动自己的内核，模块也由自己的包提供。第 2 步会把这些连同 Fedora 的内核包
  一起删掉。
- 树里没有 `sddm`，登录管理器应该是 `plasma-login-manager`（Fedora 45 的
  `kde-mobile` 包组带的是它）。第 4 步上机时确认。
- GitHub Actions 没有 Fedora 的 runner，也没有 aarch64 的 rpm 系环境，所以
  打包和装包都在 `fedora:45` 的 aarch64 容器里做（runner 本身就是 arm64，
  容器是原生执行，不用模拟）。统一走 `tools/fedora-container.sh`：它钉
  `--platform linux/arm64`，并在容器里再核对一次 `uname -m`，防止拉成 x86 镜像
  在模拟下打包。没有把整个 job 放进 `container:`，因为取根那一步要 loop 挂载、
  要 root、要用 apt 装的 7z/unsquashfs，这些是宿主机（Ubuntu）这一侧的事。
- 内核 RPM 的安装脚本会尝试往 `/boot` 写东西，要绕开。
- 桌面定制（原来的 `device/gnome-overlay`）几乎要重做，工作量最大。

## 怎么跑第 1 步

在 GitHub 上手动触发 `Fedora rootfs` 这个 workflow（只在这个分支上能跑）。
它会把 ISO 下载、解开、写出清单和一份报告，作为 artifact 上传。报告里有树的
大小、包数量、有没有 `plasma-mobile`、`selinux-policy-targeted`、`sddm`。
