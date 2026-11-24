# xiaomipad-6pro-mainline（liuqin-install 分支）

Xiaomi Pad 6 Pro（liuqin，128G）上的 Ubuntu 26.04 arm64 单系统：本工作区自建的
Linux 7.3 内核加设备驱动，没有 Android，从 A 槽直接启动。

分区保持原厂：`boot_a` 换成我们的 boot.img，`userdata` 是唯一的数据分区
（根和 `/home` 都在这一块 ext4 上）；没有单独的 `/boot` 分区，也不建
`linux_root`/`linux_home`。

## 一个内核分支，两个可刷产物

```
内核仓 linux-sm8450-liuqin（liuqin-7.3 分支）
        │ push
        ▼
GitHub Actions ──▶ ci/liuqin-kernel-<commit>/
                      │
        ┌─────────────┴──────────────┐
        ▼                            ▼
  装配 boot.img                构建机装配 rootfs
  Image + DTB + initramfs      Ubuntu + 设备/内核 deb
  + ABL overlay                      │
        │                            ▼
        │                      rootfs.tar.gz
        │                            │ 刷机主机转换
        │                            ▼
        │                      rootfs.img
        ▼                            ▼
  fastboot flash boot_a     fastboot flash userdata
        └───────────────┬────────────┘
             第一次启动 → 从 persist 取校准 → 桌面
```

boot.img 里带一份 rootfs 设备文件的哈希清单，启动时核对；清单不符就不挂载
这个根。因此：

- **只换内核**：刷新的 boot.img，再装新的内核 deb；rootfs 不动。
- **动了用户态**（device-support、固件等）：boot.img 和 rootfs 一起换。

## 命令

```sh
# 开发机：从 ci/ 里的内核产物装配 boot.img（加 --deb 同时出内核 deb）
sh tools/build-liuqin-boot.sh

# 构建机（另一台 arm64，root，≥40 GB）：装配整机 rootfs，产出 out/image/bundle
sudo sh tools/build-liuqin-rootfs.sh

# 刷机主机：把 bundle 里的 rootfs.tar.gz 变成 ext4，然后刷入
sudo sh tools/build-liuqin-rootfs-image.sh --rootfs <bundle>/rootfs.tar.gz --out out/dist
fastboot flash boot_a    <bundle>/boot.img
fastboot flash userdata out/dist/rootfs.img
```

平时只有第一条（约 15 秒，不编译内核）。第一次启动后要做一次校准导入，
见 [`docs/INSTALL.zh-CN.md`](docs/INSTALL.zh-CN.md)。

## 文档

| 文档 | 内容 |
|---|---|
| [`docs/STATUS.zh-CN.md`](docs/STATUS.zh-CN.md) | 设备现状、已验证/未验证、已知问题 |
| [`docs/INSTALL.zh-CN.md`](docs/INSTALL.zh-CN.md) | 刷机、更新、回滚 |
| [`docs/BUILD.zh-CN.md`](docs/BUILD.zh-CN.md) | 从源码到可刷产物 |
| [`docs/archive/`](docs/archive/) | 历史记录，不再维护 |

## 规则

1. 内核只在 GitHub Actions 编译；开发机不做 `make`。
2. 不执行 `git push`；本地提交后把提交号和命令交给维护者。
3. ROM 只用 `V14.0.9.0.TMYCNXM`。
4. 文档只维护中文。
