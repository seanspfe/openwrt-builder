#!/usr/bin/env bash
#
# Prepare the OpenWrt build tree for one target (daed branch):
#
#   * check out OpenWrt, kenzok8/openwrt-daede and the Vantage theme at the
#     commits pinned below (every pin can be overridden from the environment),
#   * remove `bridger` from the filogic target's default packages,
#   * wire both external feeds into feeds.conf.default and install all feeds.
#
# Run from anywhere; paths are resolved from this script's location.
#
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
src_root=${SRC_ROOT:-$repo_root/.src}
openwrt_dir=${OPENWRT_DIR:-$src_root/openwrt}
feeds_dir=${FEEDS_DIR:-$src_root/feeds}
daede_dir=$feeds_dir/openwrt-daede
vantage_dir=$feeds_dir/luci-theme-vantage

# Pins. The commits are what the tags resolve to; each checkout is verified
# against them, so a moved tag fails the build instead of silently drifting.
: "${OWRT_REPO:=https://github.com/openwrt/openwrt.git}"
: "${OWRT_TAG:=v25.12.6}"
: "${OWRT_COMMIT:=64900e756efa667774214f9c6b17c113222e01f7}"
: "${OWRT_KERNEL:=6.12.112}"
: "${DAEDE_REPO:=https://github.com/kenzok8/openwrt-daede.git}"
DAEDE_COMMIT="bc6fb7ca997b1de42ae3b8d67574ce5717816995"
DAED_VERSION="2026.11.09"
: "${VANTAGE_REPO:=https://github.com/anothaDev/luci-theme-vantage.git}"
: "${VANTAGE_TAG:=v1.0.14}"
: "${VANTAGE_COMMIT:=cddbfb262b7a67a0d3762039e4af66fc0ac92000}"

if [ -n "${GITHUB_ENV:-}" ]; then
	echo "DAEDE_COMMIT=$DAEDE_COMMIT" >> "$GITHUB_ENV"
	echo "DAED_VERSION=$DAED_VERSION" >> "$GITHUB_ENV"
fi

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_commit() {
	local dir=$1 expected=$2 name=$3 got
	got=$(git -C "$dir" rev-parse HEAD)
	[ "$got" = "$expected" ] || die "$name: HEAD is $got, expected $expected"
	printf '%s @ %s\n' "$name" "$got"
}

# clone_tag URL TAG DIR COMMIT NAME - shallow checkout of a tag, verified by commit.
# An existing checkout is reused: the tag is fetched again and checked out, so a
# second run moves the tree to the pin instead of needing a fresh clone.
clone_tag() {
	local url=$1 tag=$2 dir=$3 commit=$4 name=$5
	if [ -d "$dir/.git" ]; then
		git -C "$dir" fetch --quiet --depth 1 --force origin \
			"refs/tags/$tag:refs/tags/$tag"
		git -C "$dir" checkout --quiet --detach "refs/tags/$tag"
	else
		mkdir -p "$(dirname "$dir")"
		git clone --quiet --depth 1 --single-branch --branch "$tag" "$url" "$dir"
	fi
	require_commit "$dir" "$commit" "$name"
}

# clone_commit URL COMMIT DIR NAME - shallow checkout of a bare commit
clone_commit() {
	local url=$1 commit=$2 dir=$3 name=$4
	if [ ! -d "$dir/.git" ]; then
		mkdir -p "$dir"
		git -C "$dir" init --quiet
		git -C "$dir" remote add origin "$url"
	else
		git -C "$dir" remote set-url origin "$url"
	fi
	git -C "$dir" fetch --quiet --depth 1 --force origin "$commit"
	git -C "$dir" checkout --quiet --detach FETCH_HEAD
	require_commit "$dir" "$commit" "$name"
}

log "OpenWrt $OWRT_TAG"
clone_tag "$OWRT_REPO" "$OWRT_TAG" "$openwrt_dir" \
	"$OWRT_COMMIT" openwrt

kernel_version=$(sed -n 's/^LINUX_VERSION-6\.12 = \.//p' \
	"$openwrt_dir/target/linux/generic/kernel-6.12")
[ "$kernel_version" = "${OWRT_KERNEL#6.12.}" ] ||
	die "kernel is 6.12.$kernel_version, expected $OWRT_KERNEL"
printf 'kernel 6.12.%s\n' "$kernel_version"

log "kenzok8/openwrt-daede @ $DAEDE_COMMIT"
clone_commit "$DAEDE_REPO" "$DAEDE_COMMIT" "$daede_dir" openwrt-daede

log "Vantage theme $VANTAGE_TAG"
clone_tag "$VANTAGE_REPO" "$VANTAGE_TAG" "$vantage_dir" "$VANTAGE_COMMIT" \
	luci-theme-vantage

# Unsilence OpenWrt package compilation so any sub-make errors are printed
if [ -f "$openwrt_dir/include/verbose.mk" ]; then
	sed -i -E 's/SILENT:=>\/dev\/null.*/SILENT:=/' "$openwrt_dir/include/verbose.mk"
fi

# Some filogic trees add bridger to DEFAULT_PACKAGES, so a plain
# GL-MT3000 build would ship it. This build excludes bridger, and the exclusion
# lives in the target's default list, which is a make variable rather than a
# Kconfig symbol: `CONFIG_PACKAGE_bridger is not set` would not remove it.
filogic_target=$openwrt_dir/target/linux/mediatek/filogic/target.mk
if grep -qw bridger "$filogic_target"; then
	sed -i -E 's/[[:space:]]*bridger([[:space:]]|$)/\1/' "$filogic_target"
	echo "bridger removed from the filogic default packages"
fi
if grep -qw bridger "$filogic_target"; then
	die "bridger is still in $filogic_target"
fi

log "Wiring the external feeds"
feeds_conf=$openwrt_dir/feeds.conf.default
grep -q '^src-link openwrt_daede ' "$feeds_conf" ||
	printf 'src-link openwrt_daede %s\n' "$daede_dir" >>"$feeds_conf"
grep -q '^src-link luci_vantage ' "$feeds_conf" ||
	printf 'src-link luci_vantage %s\n' "$vantage_dir" >>"$feeds_conf"

log "Updating and installing feeds"
(
	cd "$openwrt_dir"
	./scripts/feeds update -a
	./scripts/feeds install -a
)

# The feeds are symlinked; check the daed packages are visible through the
# installed package directories.
installed_daed=$openwrt_dir/package/feeds/openwrt_daede/daed
[ -r "$installed_daed/Makefile" ] ||
	die "the daed package is not installed at $installed_daed"
installed_luci=$openwrt_dir/package/feeds/openwrt_daede/luci-app-daede
[ -r "$installed_luci/Makefile" ] ||
	die "the luci-app-daede package is not installed at $installed_luci"
# The daed source tarball is hash-pinned in the package Makefile; make sure the
# pin the build will use is the snapshot this branch was verified against.
grep -q "^PKG_VERSION:=$DAED_VERSION" "$installed_daed/Makefile" ||
	die "daed PKG_VERSION is not $DAED_VERSION at $installed_daed/Makefile"

# The feed's daed Makefile includes bpf.mk but never declares $(BPF_DEPENDS),
# so selecting daed does not select NEED_BPF_TOOLCHAIN, the BPF toolchain
# choice never produces a clang, and bpf.mk falls back to /invalid/clang:
# package/kernel/bpf-headers then fails with "LLVM/clang version too old".
# Declare the dependency the package actually has. With NEED_BPF_TOOLCHAIN
# selected, the toolchain choice defaults to building OpenWrt's own LLVM
# (CONFIG_USE_LLVM_BUILD), which is promptless and cannot be set from a seed
# config, so this patch is the only place the fix can live.
daed_makefile=$daede_dir/daed/Makefile
if ! grep -q 'BPF_DEPENDS' "$daed_makefile"; then
	sed -i 's|DEPENDS:=$(GO_ARCH_DEPENDS)|DEPENDS:=$(GO_ARCH_DEPENDS) $(BPF_DEPENDS)|' "$daed_makefile"
fi
grep -q 'BPF_DEPENDS' "$daed_makefile" ||
	die "failed to add BPF_DEPENDS to $daed_makefile"

log "Build tree ready: $openwrt_dir"
