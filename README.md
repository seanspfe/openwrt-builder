# openwrt-builder — `daed` branch

Reproducible OpenWrt firmware built by GitHub Actions from pinned upstream
commits. This branch is the **daed variant**: where `main` carries **honk**,
this branch carries **daed** (the eBPF transparent proxy with a built-in web
dashboard) plus the **Vantage** LuCI theme. Only two targets are built on
this branch:

| Target | Image | Device |
| --- | --- | --- |
| `x86_64` | `openwrt-x86-64-generic-squashfs-combined-efi.img.gz` (BIOS + UEFI) | generic PC / VM |
| `gl-mt3000` | `openwrt-mediatek-filogic-glinet_gl-mt3000-squashfs-sysupgrade.bin` | GL.iNet GL-MT3000 (MediaTek MT7981) |

`configs/hc5962.config` is kept in the tree for reference but is **not
built** on this branch (the HiWiFi HC5962 is MIPS; dae/daed do not support
it). `main` remains the honk branch and is untouched.

Nothing is built automatically on ordinary commits: the workflow runs from
the **Run workflow** button / API dispatch with an explicit `ref` of this
branch and a single target per run.

## Pinned versions

Every pin is checked out and verified against its commit at build time, so
a moved tag fails the build instead of silently changing the firmware.

| Component | Version | Commit |
| --- | --- | --- |
| OpenWrt | tag `v25.12.6` | `64900e756efa667774214f9c6b17c113222e01f7` |
| Linux kernel | `6.12.112` | — (`target/linux/generic/kernel-6.12`) |
| daed feed (`daed`, `luci-app-daede`) | commit | `bc6fb7ca997b1de42ae3b8d67574ce5717816995` (`kenzok8/openwrt-daede`) |
| daed package | `2026.11.09` snapshot | source tarball SHA-256 pinned in the feed's `daed/Makefile` (`a25f8d76…`) |
| Vantage theme | tag `v1.0.14` | `cddbfb262b7a67a0d3762039e4af66fc0ac92000` |

The daed package is a dated snapshot assembled by the feed maintainer's CI
from `daeuniverse/daed` + `dae-wing` + the dae core, with additional
performance and fix patches — it is not an official daed release tag. The
feed checkout and the source tarball hash are both pinned, so the build is
still reproducible.

## What is in the images

Both targets, as `=y` in the rootfs:

- `daed` with the `luci-app-daede` LuCI front end (daed backend selected),
  its runtime dependencies (`kmod-veth`, `kmod-sched-core`, `kmod-sched-bpf`,
  `ca-bundle`, `v2ray-geoip`, `v2ray-geosite`, …), and
  `luci-theme-vantage` with its zh-cn translation.
- Kernel BTF is switched on explicitly in the seed configs
  (`CONFIG_KERNEL_DEBUG_INFO_BTF=y`, REDUCED off): OpenWrt only defaults it
  on for its own buildbot. daed uses the kernel's own BTF
  (`DAED_USE_KERNEL_BTF`, the package default), so the feed's detached
  `vmlinux-btf` package is not in the image.
- No honk, no `luci-app-honk`, no UA3F anywhere.
- `x86_64` additionally pins the wired NIC drivers (`kmod-e1000e`, `kmod-igc`,
  `kmod-r8169`, `kmod-ixgbe`, …) so no NIC is left without a driver;
  virtio-net is built into the x86/64 kernel.
- `gl-mt3000` keeps the device profile's packages (`kmod-mt7915e`,
  `kmod-mt7981-firmware`, `mt7981-wo-firmware`, `kmod-usb3`, …).

## Build with GitHub Actions

1. Dispatch the **Build firmware** workflow with `ref` set to this branch
   (`daed`) and `target` set to `x86_64` or `gl-mt3000` (one run per target).
2. Each target produces two artifacts:
   - `openwrt-25.12.6-<target>` — images, `*.manifest`, `*.buildinfo`,
     `sha256sums`, `profiles.json`;
   - `openwrt-25.12.6-<target>-config-log` — the resolved diffconfig and
     the full build log.

The workflow frees ~40 GB on the runner, installs the host build
dependencies, prepares the tree with `scripts/prepare-tree.sh` (pinned
checkouts, feed wiring), merges `configs/<target>.config`, verifies the
resolved config with `scripts/verify-config.sh`, builds (daed compiles
with Go + clang — no Rust toolchain on this branch), and verifies the
image manifest with `scripts/verify-manifest.sh`.

## Repository layout

```
.github/workflows/build.yml     manual builds (dispatch with ref = this branch)
configs/x86_64.config           seed config for x86/64 (squashfs + combined-EFI)
configs/gl-mt3000.config        seed config for mediatek/filogic GL-MT3000
configs/hc5962.config           kept for reference; not built on this branch
scripts/prepare-tree.sh         pinned checkouts, feeds
scripts/verify-config.sh        asserts the merged .config before compiling
scripts/verify-manifest.sh      asserts the built image after compiling
```

## Roll-forward checklist

To move a pin: change it in `.github/workflows/build.yml` **and** in the
defaults at the top of `scripts/prepare-tree.sh`, then update the table
above. When the daed feed moves, re-check `daed/Makefile`'s `PKG_VERSION`
and source hash in the new checkout before dispatching.
