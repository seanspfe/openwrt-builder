# openwrt-builder

Reproducible OpenWrt firmware for three machines, built by GitHub Actions
from pinned upstream commits. The `x86_64` and `gl-mt3000` images carry
**honk** (the eBPF transparent proxy) and the **Vantage** LuCI theme; the
`hc5962` image carries LuCI + Vantage only, because honk's build supports
just the x86_64 and aarch64 Rust targets and the HC5962 is MIPS (MT7621).

| Target | Image | Device |
| --- | --- | --- |
| `x86_64` | `openwrt-x86-64-generic-squashfs-combined-efi.img.gz` (BIOS + UEFI) | generic PC / VM |
| `gl-mt3000` | `openwrt-mediatek-filogic-glinet_gl-mt3000-squashfs-sysupgrade.bin` | GL.iNet GL-MT3000 (MediaTek MT7981) |
| `hc5962` | `openwrt-ramips-mt7621-hiwifi_hc5962-squashfs-sysupgrade.bin` (+ `factory.bin`) | HiWiFi HC5962 / 极路由4 (MediaTek MT7621) |

Nothing is built automatically on ordinary commits: the workflow runs from
the **Run workflow** button, or when a push to `main` touches
`.build-trigger` (that path builds every target). A full build takes
roughly 1.5–3 hours per honk target on a standard runner; hc5962 is faster.

## Pinned versions

Every pin is checked out and verified against its commit at build time, so
a moved tag fails the build instead of silently changing the firmware.

| Component | Version | Commit |
| --- | --- | --- |
| OpenWrt | tag `v25.12.6` | `64900e756efa667774214f9c6b17c113222e01f7` |
| Linux kernel | `6.12.112` | — (`target/linux/generic/kernel-6.12`; all three targets use `KERNEL_PATCHVER:=6.12`) |
| honk | tag `v0.1.0-beta.6` | `64848881b7304e250e7a25422f4f1d86a5975eca` |
| honk packages (LuCI app, `luci-lib-daeuniverse`, `vmlinux-btf*`) | commit | `6157f709f52cdbf34c39e5fb69f4b81f468c10e6` (`daeuniverse/openwrt-packages`) |
| doona panel (embedded in honk's native UI) | `0.1.0-rc.6` | pinned by honk's `.github/ci/pins.env` |
| Vantage theme | tag `v1.0.14` | `cddbfb262b7a67a0d3762039e4af66fc0ac92000` |
| bpf-linker | `v0.11.0` | prebuilt tarball, SHA-256 `10f62ba9ab7e544d538370552660efcb4f1a19153d5752bbf0f6b51f3bada450` |
| Rust (honk-core) | `1.99.1` | honk `rust-toolchain.toml` |
| Rust (eBPF object) | `nightly-2026-10-20` | honk `crates/honk-ebpf/rust-toolchain.toml` |

## What is in the images

`x86_64` and `gl-mt3000`, as `=y` in the rootfs:

- `honk` with the crate defaults plus `ebpf` and `native-ui` (embedded doona
  dashboard at `/ui`), `luci-app-honk`, `luci-lib-daeuniverse`,
  `vmlinux-btf-builtin` (the kernel carries its own BTF), honk's runtime
  dependencies (`kmod-veth`, `kmod-sched-bpf`, `kmod-nft-queue`,
  `kmod-nfnetlink-queue`, `v2ray-geoip`, `v2ray-geosite`, …), and
  `luci-theme-vantage` with its zh-cn translation.
- Kernel BTF is switched on explicitly in the seed configs
  (`CONFIG_KERNEL_DEBUG_INFO_BTF=y`, REDUCED off): OpenWrt only defaults it
  on for its own buildbot.
- `x86_64` additionally pins the wired NIC drivers (`kmod-e1000e`, `kmod-igc`,
  `kmod-r8169`, `kmod-ixgbe`, …) so no NIC is left without a driver;
  virtio-net is built into the x86/64 kernel.
- `gl-mt3000` keeps the device profile's packages (`kmod-mt7915e`,
  `kmod-mt7981-firmware`, `mt7981-wo-firmware`, `kmod-usb3`, …).

`hc5962`: LuCI + Vantage and the WiFi drivers of its device profile —
`kmod-mt7603` (MT7603EN, 2.4 GHz) and `kmod-mt76x2` (MT7612EN, 5 GHz), both
open mt76 drivers — plus `kmod-usb3`. No honk (unsupported architecture),
no UA3F anywhere.

## Build with GitHub Actions

1. Open the **Actions** tab → **Build firmware** → **Run workflow**
   (or push a change to `.build-trigger` on `main` to build all targets).
2. Pick `target`: `all`, `x86_64`, `gl-mt3000` or `hc5962`. `cargo_jobs`
   (default `2`) controls honk's cargo parallelism; lower it if the Rust
   link step runs out of memory.
3. Each target produces two artifacts:
   - `openwrt-25.12.6-<target>` — images, `*.manifest`, `*.buildinfo`,
     `sha256sums`, `profiles.json`;
   - `openwrt-25.12.6-<target>-config-log` — the resolved diffconfig and
     the full build log.

The workflow frees ~40 GB on the runner, installs the host build
dependencies plus the pinned Rust toolchains and bpf-linker, prepares the
tree with `scripts/prepare-tree.sh` (pinned checkouts, the honk packaging
patch, feed wiring), merges `configs/<target>.config`, verifies the
resolved config with `scripts/verify-config.sh`, builds, and verifies the
image manifest with `scripts/verify-manifest.sh`.

## Repository layout

```
.github/workflows/build.yml     manual / .build-trigger builds for 3 targets
configs/x86_64.config           seed config for x86/64 (squashfs + combined-EFI)
configs/gl-mt3000.config        seed config for mediatek/filogic GL-MT3000
configs/hc5962.config           seed config for ramips/mt7621 HiWiFi HC5962 (no honk)
patches/honk-package-build-env.patch
                                Rust build environment in honk's package Makefile
scripts/prepare-tree.sh         pinned checkouts, patches, feeds
scripts/verify-config.sh        asserts the merged .config before compiling
scripts/verify-manifest.sh      asserts the built image after compiling
```

## Roll-forward checklist

To move a pin: change it in `.github/workflows/build.yml` **and** in the
defaults at the top of `scripts/prepare-tree.sh`, then update the table
above. When honk moves, re-check its `rust-toolchain.toml`,
`crates/honk-ebpf/rust-toolchain.toml` and `.github/ci/pins.env`, and pick
the matching `daeuniverse/openwrt-packages` commit whose honk Makefile
defaults to the new tag.
