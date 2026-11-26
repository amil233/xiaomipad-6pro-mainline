# xiaomipad-6pro-mainline（liuqin-installer-fedora 分支）

Xiaomi Pad 6 Pro（liuqin，128G）上的 Fedora 45 KDE Plasma Mobile 单系统：本工作区
自建的 Linux 7.3 内核加设备驱动，没有 Android，从 A 槽直接启动。

分区保持原厂：`boot_a` 换成我们的 boot.img，`userdata` 是唯一的数据分区（根和
`/home` 都在这一块 ext4 上，卷标 `LIUQIN_ROOT`，树在 `native-root/` 下）；没有
单独的 `/boot` 分区。

这个分支只服务 Fedora。Ubuntu + GNOME 那条线在 `liuqin-install` 分支上，两边互不
引用。

## 产物从哪来

```
内核仓 linux-sm8450-liuqin（liuqin-7.3-fedora 分支）
        │ push
        ▼
内核 CI ──▶ ci/liuqin-kernel-<commit>/（Image、dtb、模块）
        │
        ▼
集成仓 fedora-rootfs 工作流
  1. 下 Live ISO，核对官方校验，解出 ext4 根
  2. 容器里（fedora:45）把内核产物打成一个 RPM 装进树
  3. 整理树：根标记、machine-id、SELinux permissive
  4. 装配 boot.img（内核 + 设备树 + initramfs + ABL overlay）
  5. 生成 ext4 镜像 → Android sparse → rootfs.tgz → 1900 MiB 分片
        │
        ▼
刷机主机：fastboot flash boot_a boot.img
          fastboot flash userdata rootfs.simg
```

boot.img 里钉着这次构建的内核版本号，启动时和根里的
`/usr/share/liuqin/kernel.release` 比对；不一致就不挂载这个根。所以 boot.img 和
rootfs 必须来自同一次构建、一起刷。

## 命令

```sh
# 刷机主机：合并分片、核对、解开
cat rootfs.tgz.part-* > rootfs.tgz
sha256sum -c SHA256SUMS
tar -xzf rootfs.tgz
fastboot flash boot_a   boot.img
fastboot flash userdata rootfs.simg
```

细节见 [`docs/INSTALL.zh-CN.md`](docs/INSTALL.zh-CN.md)，产物和构建过程见
[`docs/BUILD.zh-CN.md`](docs/BUILD.zh-CN.md)，当前状态见
[`docs/STATUS.zh-CN.md`](docs/STATUS.zh-CN.md)，换发行版的来龙去脉见
[`docs/FEDORA.zh-CN.md`](docs/FEDORA.zh-CN.md)。
