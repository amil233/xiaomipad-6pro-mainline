# Stage 2: Persistent Single-System Ubuntu (arm64 Host Runbook)

This runbook installs the lit v7.3 kernel with the Ubuntu 26.04 LTS desktop
onto Xiaomi Pad 6 Pro (liuqin) as a single-system ARM PC:
**no Android, no dual boot**, the whole userdata tail goes to Ubuntu.

[中文](STAGE2-PERSISTENT.zh-CN.md) ｜ [Build overview](BUILD.md) ｜ [Installation steps](INSTALL-TESTING.md)

---

## 0. Scope

- **Who executes**: you, on an **AArch64-native** Linux host connected to the
  tablet over USB. Nothing here downloads, unpacks or flashes on its own.
- **Why AArch64-native**: the chroot stages (deb install, sensor stack,
  GNOME Settings build) execute natively on an arm64 host — no qemu/binfmt.
  The project's CI runner is `ubuntu-24.04-arm` for the same reason since
  2026-10-30. On an x86 host you must supply `qemu-aarch64` binfmt (P flag)
  and a cross toolchain yourself.
- **Single-system boundary**: `--layout linux-only`. The installer touches
  slot B and the tail partitions only: no ROM directory, no Android firmware
  restore, no `super`/`metadata` writes. See §6 and [Flashing](FLASHING.md).
- **Out of scope**: the RAM desktop image (the `LIUQIN_STORAGE_MODE=readonly`
  route), Kubuntu/KDE adaptation (no arm64 desktop ISO exists), and the
  display stack (v7.3 already lights, `docs/kernel-version-upgrade.md` §13).

## 1. State and prerequisites (read first)

| Item | Value | Evidence |
|---|---|---|
| Lit kernel | `liuqin-7.3` @ `db08160915e3` (`7.3.0-gdb08160915e3`) | `docs/kernel-version-upgrade.md` §13; CI run 41409689334 |
| Base system | Ubuntu Desktop 26.04 LTS arm64 (`ubuntu-26.04-desktop-arm64.iso`) | pinned in `tools/build-liuqin-ubuntu-desktop-rootfs.sh` |
| Product lock | `kernel/source.json` still pins `a322d592` (7.0 era) — **§4-1 must advance it to 7.3** | TD4, `docs/migration-7.0.md` |
| Single-system layout | deletes userdata, creates `linux_root`(36)+`linux_home`(37) in the tail, flashes `boot_b`, `--set-active b` | `tools/lib/liuqin_layout.py:340-360`; `install-liuqin.py:36` |
| Device gates | factory partition table, 4096-byte logical sectors, userdata last partition, unlocked bootloader, battery ≥30% | `FLASHING.md`; `liuqin_layout.py:274` |

**Hard constraints (not negotiable)**:

1. `build-liuqin-image.py` asserts the kernel artifact's `build-info.json.commit`
   equals the `kernel/source.json` pin. The lit 7.3 artifact reports
   `commit=db08160915e3` while the lock still pins `a322d592` ⇒ the image
   cannot be assembled until the lock advances.
2. The persistent boot image requires a **locally built** kernel tree
   (`native-boot.sh` reads `$KERNEL_OUT/scripts/dtc/dtc` and
   `include/config/kernel.release`). CI artifacts lack both, so one local
   kernel build on the arm64 host is mandatory. This is by design —
   `image.yml` runs `build-liuqin-kernel.py` in CI before assembly too.
3. ROM inputs are pinned to the **OS2.0.6.0.VMYCNXM** fastboot package. The
   V14.0.9.0 package on hand does **not** match (dtbo 44 vs 38 entries,
   `entry.15` differs byte-wise). Firmware pool and ABL overlay inputs must
   come from OS2.0.6.0.

## 2. Prerequisites

### 2.1 Host packages (apt)

```
curl, rsync, 7z (p7zip-full), squashfs-tools, cpio,
python3 (≥3.11) + pyelftools, util-linux (flock),
gcc (native arm64 is fine), git, fastboot (platform-tools),
dtc / fdtoverlay (device-tree-compiler), zstd
```

`build-liuqin-native-root.sh` and `build-liuqin-debs.sh` already accept an
AArch64-native host (the binfmt check is skipped when `uname -m` is aarch64;
the compiler falls back to `gcc`). On x86, install `qemu-aarch64` binfmt
(P flag) and `aarch64-linux-gnu-gcc` additionally.

### 2.2 Host disk

Kernel build tree + two desktop trees (extract + copy) + rootfs archive:
allow **≥ 60 GB** free. `out/` and `tools/local/` are gitignored — never
commit them.

### 2.3 Inputs you must supply yourself

| Input | Notes | Source |
|---|---|---|
| Ubuntu 26.04 desktop arm64 ISO | pinned `c2afd538…` / 4161089536 B | `tools/build-liuqin-ubuntu-desktop-rootfs.sh download`, or download yourself then `verify-iso` |
| OS2.0.6.0.VMYCNXM fastboot package | 7.7 GB `super.img` etc.; hashes in `tools/lib/liuqin-rom-images.json` | official Xiaomi fastboot package; **cannot** be substituted with V14.0.9.0 |
| Stock QCA6490 directory | `amss20.bin` / `m3.bin` / `regdb.bin` / `bd_m81gf.elf` | extracted from the OS2 modem/vendor partition |
| audioreach-topology source | pinned commit `2af1f1ebb8d…` | `git clone linux-msm/audioreach-topology`, next to the project |
| Fingerprint build input | `fingerprint-build-inputs.tar.gz` | downloaded and verified automatically by `prepare-image-inputs.py` |

The firmware pool (`tools/local/firmware-liuqin`) combines OS2
`vendor_a` (touch/GPU/VPU), `NON-HLOS.bin` (DSP), `BTFM.bin` (Bluetooth),
upstream `WCN6855` (WLAN) and upstream `regulatory.db`. Every member is
hash-asserted by `tools/build-liuqin-firmware-prep.sh`, so a mismatch fails
at build time, never on the device.

## 3. Preparing the inputs (a gate per step)

> Convention: `$INT` is the integration repo root; run everything under it.
> `sudo -v` first — several chroot stages need root.

### 3.1 Desktop root (ISO → rootfs)

```sh
sh tools/build-liuqin-ubuntu-desktop-rootfs.sh download   # or verify-iso after a manual download
sh tools/build-liuqin-ubuntu-desktop-rootfs.sh casper     # 7z extracts the two squashfs layers
sudo sh tools/build-liuqin-ubuntu-desktop-rootfs.sh extract
```

**Gates**: `download` verifies ISO size+sha256; `casper` verifies
`minimal.squashfs` (`82613d06…`) and `minimal.standard.squashfs`
(`fce0e244…`) and refuses the English-pruning layer; `extract` produces
`tools/local/ubuntu-desktop-26.04-arm64/rootfs` plus `rootfs.manifest`
(manifest hash `175ca229…`, re-verified by `native-root` in §5).

### 3.2 Split the stock ROM

```sh
# dtbo → 44 entries; vendor_boot → 14 base DTBs
python3 tools/extract-stock-dtbo-entries.py <OS2pkg>/dtbo.img \
  tools/local/roms/liuqin/OS2.0.6.0.VMYCNXM/analysis/dtbo
python3 tools/extract-stock-base-dtbs.py <OS2pkg>/vendor_boot.img \
  tools/local/roms/liuqin/OS2.0.6.0.VMYCNXM/analysis/vendor_boot/dtbs
```

**Gate**: at boot-image assembly, `build-bootimg.sh` enforces a triple count
assertion (44 entries / 14 base DTBs / 1781 symbols) plus an
`abl-symbols.py` symbol table comparison. A wrong split fails here.

Lay out the firmware pool and the `super` extracts following the directory
comment at the top of `tools/build-liuqin-firmware-prep.sh` (`FIRMWARE_POOL`
may point elsewhere). The sensor stack needs
`extracted/super-work/vendor-extract/etc/sensors` (with `config/` and
`sns_reg_config`); VPU needs `firmware/vpu20_4v.mbn`.

### 3.3 Fetches

```sh
sh tools/fetch-busybox-arm64.sh      # pinned busybox-static 1.36.1
sh tools/fetch-aosp-mkbootimg.sh     # mkbootimg/unpack_bootimg (file-level hashes)
sh tools/fetch-kernelsu-assets.sh    # unused in single-system, but bundled
```

### 3.4 Audio topology

```sh
AUDIOREACH_TOPOLOGY_DIR="$PWD/../audioreach-topology" \
  OUTPUT="$PWD/out/audio-topology/Xiaomi-Pad-6-Pro-tplg.bin" \
  sh tools/build-liuqin-audio-topology.sh
```

### 3.5 WLAN set (needs the stock QCA6490 directory)

```sh
python3 tools/build-liuqin-wlan.py \
  --vendor <stock-QCA6490-dir> \
  --base-board <bd_m81gf.elf> \
  --bdencoder tools/scripts/ath11k/ath11k-bdencoder \
  --out out/wlan-source-check
```

### 3.6 Aggregate prepared inputs

```sh
sudo -v
python3 tools/prepare-image-inputs.py check   # dry report first
python3 tools/prepare-image-inputs.py run     # sensor stack / Settings via sudo chroot
```

Writes `out/image-inputs.local.json` (the slow chroot builds are
fingerprint-cached under `tools/local/artifacts-cache/` and reused).
`--prepare-only` only unpacks the GNOME Settings source; the real build
needs sudo and runs in an isolated mount namespace that never modifies the
input tree.

## 4. Kernel and assembly

### 4.1 Advance the product lock to 7.3 (do this first)

Edit `kernel/source.json`:

```json
{
  "branch": "liuqin-7.3",
  "commit": "db08160915e3138748a45f9a3fa868ccfb536e8b",
  "config_sha256": "<actual value from §4-2 build-info.json>",
  ... config_fragments / dtb unchanged ...
}
```

Take `config_sha256` from the **local build's** own report (the CI artifact
says `d81ff750…`; if the local merge differs, keep the local one — the
builder only warns, the image assembler asserts). `upstream_base` is not
validated and may keep its 7.0 value.

> Risk note: this advances the product kernel from 7.0 to 7.3. Both v7.3
> display fixes (the ubwc `qcom,cape` machine alias `489807127e50` and the
> bonded-DSI PLL fix `db08160915e3`) are inside `db08160915e3` and ride
> along with the lock advance.

### 4.2 Build the kernel locally (arm64 native)

```sh
# kernel repo at $INT/../linux-sm8450-liuqin, checked out at liuqin-7.3 @ db08160915e3, clean tree
python3 tools/build-liuqin-kernel.py --jobs <cores>
```

**Gates**: the builder asserts source HEAD == lock pin and a clean tree,
picks the toolchain by host (native on arm64), and leaves
`out/kernel/` with `Image`,
`arch/arm64/boot/dts/qcom/sm8475-xiaomi-liuqin.dtb`,
`include/config/kernel.release`, `scripts/dtc/dtc`, `build-info.json`.
Backfill `config_sha256` into `kernel/source.json` if it differs from the
CI value.

### 4.3 Assemble the system image

```sh
sudo python3 tools/build-liuqin-image.py \
  --inputs out/image-inputs.local.json \
  --kernel-out "$PWD/out/kernel" \
  --stage all
```

Stage order: `modules → debs → copy → install → assemble → manifest →
boot → runtime → installer → pack → bundle`. Resume with `--stage <name>`
after an interruption. Output lands in `out/image/bundle/`: `boot.img`,
`installer.img`, `rootfs.tar.gz`, `bundle.json`, the installer scripts and
docs, and the KernelSU return module (unused in single-system but bundled).

**Gates**:
- `debs` asserts gdm3 / gnome-shell / gnome-initial-setup are in the tree,
  no gdm autologin survived, and snap admission is not on basic.target;
- `assemble` applies the BlueZ policy edit, unit links, the
  `/etc/liuqin-native-root` marker (hash `4fdae4f7…`), and asserts
  per-device private data is **absent**;
- `boot`/`installer` run `build-liuqin-native-boot.sh`, which requires
  kernel source HEAD, config and `kernel.release` to agree with the root's
  `/usr/share/liuqin/kernel.release`, and the boot image to fit the
  192 MiB boot partition (`build-bootimg.sh`).

### 4.4 Verify locally

```sh
python3 tools/install-liuqin.py --bundle out/image/bundle --check
python3 tools/install-liuqin.py --bundle out/image/bundle --layout linux-only \
  --serial <serial>   # --layout previews the partition plan, still no device access
```

Bundle self-verification (per-file sha256 from `bundle.json`), device
identity gates and the layout plan all run here. **Do not attach the tablet
before this passes.**

## 5. Installation (tablet connected)

### 5.1 Device preparation

- Bootloader unlocked; tablet in Fastboot; battery ≥30%.
- Personal files backed up off-tablet; installation erases the whole
  userdata (single-system deletes the partition).

### 5.2 Run the installer

```sh
sudo python3 tools/install-liuqin.py \
  --bundle out/image/bundle \
  --serial <device-serial> \
  --backup <private-dir-outside-the-bundle> \
  --erase-userdata --layout linux-only --allow-unverified
```

The single-system layout needs no `--rom-dir`. `--allow-unverified`
reflects that this bundle has not completed a device test (a first
installation is attended by definition; afterwards `--device-tested`
produces the release assets). In a non-interactive session add `--yes`.

**What the installer does** (`install-liuqin.py` + RAM installer):
`fastboot boot installer.img` → USB network (`192.168.7.2`) → back up
`boot_a`/`boot_b`/`persist` plus two partition-table copies into `--backup`
(verifiable with `--check`) → delete userdata, create `linux_root` (ext4, 36)
and `linux_home` (37) → download `rootfs.tar.gz` from the host over HTTP and
verify → unpack into `linux_root`, extract this unit's calibration and
addresses from the **persist partition** (mounted read-only: WLAN MAC,
Bluetooth address, cs35l41 calibration, sensor registry) → write `boot_b`
zero-filled to the whole partition, `fastboot --set-active=b`, reboot.

`persist` is never written, the bootloader is never relocked, and
`super`/`metadata`/slot-A partitions are untouched.

### 5.3 First-boot gates

1. Kernel log reaches systemd, no oops/panic;
2. `gdm` comes up → GNOME initial setup runs (the installer asserted no
   autologin survived);
3. Touch: nt36523 interrupts in `/proc/interrupts`, event nodes in
   `/dev/input`;
4. WLAN/Bluetooth: MAC and address provisioned from persist
   (`liuqin-wlan-mac` / `liuqin-bt-public-addr`); `ip link` and
   `bluetoothctl` respond;
5. Audio: `cs35l41` carries this unit's calibration
   (`/usr/lib/firmware/cirrus/`);
6. `/home` is a separate mount of `LABEL=LIUQIN_HOME` (fstab written by
   `install-root.sh`).

## 6. Rollback and recovery

| Situation | Recovery |
|---|---|
| installer.img does not boot | A failed `fastboot boot` writes nothing; check the USB network and `--serial` |
| Partition table miswritten | The installer re-reads and compares every entry after writing; otherwise `--restore-partition-table <backup-dir>` |
| Ubuntu does not boot | Backup is in `--backup`: `fastboot -s <serial> flash boot_b <backup>/boot_b.img`, then `fastboot --set-active=a` to boot stock Android again (slot A and `super` are untouched; userdata was deleted and can be reflashed from the OS2 package) |
| Full factory restore | Run the OS2.0.6.0 package's `flash_all`, restoring the partition table from the backup first |

## 7. Known gaps (registered as debt, not solved here)

| ID | Gap | Impact | Removal condition |
|---|---|---|---|
| S2-1 | No automation for firmware-pool / ROM extraction; directories are staged by hand | Long, error-prone preparation | Hash assertions catch errors; a future `tools/fetch-rom-inputs.sh` can automate it |
| S2-2 | Advancing `kernel/source.json` 7.0 → 7.3 is a product decision | Effective once the lock advances | Closes when the v7.3 persistent first boot passes (TD4) |
| S2-3 | The single-system layout is not yet device-tested (shares the layout engine with dual) | Partition/mount risk | This first installation is the test |
| S2-4 | Re-pinning ISO point releases (English-pruning layer, 26.04.1) is manual | Needed per point release | `tools/repin-ubuntu-release.sh` exists for this |

## 8. Retrospective checklist (fill in after first boot)

- [ ] Kernel: `uname -r` matches the bundle's `kernel_release`
- [ ] Display: GNOME desktop lit, 120 Hz mode selectable
- [ ] Touch / WLAN / BT / audio: §5.3 items
- [ ] Persistence: user data survives reboot (separate `linux_home` mount)
- [ ] Regression: `fastboot --set-active=a` still boots Android (slot A untouched)
