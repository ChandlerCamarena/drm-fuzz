#!/usr/bin/env bash
# Builds the syzkaller guest rootfs and applies required patches.
# Single entry point for rootfs setup.
set -euo pipefail

if [ ! -d syzkaller ]; then
  echo "Cloning syzkaller..."
  git clone https://github.com/google/syzkaller.git
fi

cd syzkaller/tools
sudo ./create-image.sh
cd ../..

bash scripts/patch-rootfs.sh
