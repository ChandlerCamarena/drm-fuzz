#!/usr/bin/env bash
# Full environment setup, in order. Run from inside `nix develop`.
# Each step is independently runnable (see scripts/) — this just chains them.
set -euo pipefail

echo "=== [1/4] Kernel: clone + configure ==="
bash scripts/setup.sh

echo "=== [2/4] Kernel: build ==="
bash scripts/build.sh

echo "=== [3/4] Rootfs: build + patch ==="
bash scripts/build-rootfs.sh

echo "=== Done ==="
echo "Boot with:"
echo "  qemu-system-x86_64 \\"
echo "    -kernel linux/arch/x86/boot/bzImage \\"
echo "    -drive file=syzkaller/tools/trixie.img,format=raw \\"
echo "    -append \"console=ttyS0 root=/dev/sda earlyprintk=serial net.ifnames=0 selinux=0\" \\"
echo "    -netdev user,id=net0,hostfwd=tcp::10021-:22 \\"
echo "    -device e1000,netdev=net0 \\"
echo "    -nographic -m 2G -smp 2 -enable-kvm"
