#!/usr/bin/env bash
set -euo pipefail

KERNEL_TAG="v7.2"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$REPO_DIR"

if [ ! -d linux ]; then
  git clone --branch "$KERNEL_TAG" --depth=1 \
    https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
fi

cd linux

make defconfig
make kvm_guest.config
./scripts/kconfig/merge_config.sh -m .config "$REPO_DIR/scripts/kernel.config"
make olddefconfig

echo ""
echo "=== Verifying config ==="
grep -E "CONFIG_KASAN=|CONFIG_KASAN_GENERIC=|CONFIG_KASAN_INLINE=|CONFIG_DEBUG_INFO=|CONFIG_DEBUG_INFO_DWARF4=|CONFIG_KCOV=|CONFIG_KCOV_INSTRUMENT_ALL=|CONFIG_DRM_VKMS=|CONFIG_SECURITYFS=|CONFIG_DRM_I915=" .config
