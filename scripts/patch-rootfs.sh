#!/usr/bin/env bash
# Applies required post-create-image.sh patches to the syzkaller rootfs image.
# Run once after tools/create-image.sh generates a fresh trixie.img.
set -euo pipefail

IMG="syzkaller/tools/trixie.img"
MNT="/mnt/trixie-edit"

if [ ! -f "$IMG" ]; then
  echo "error: $IMG not found. Run syzkaller/tools/create-image.sh first." >&2
  exit 1
fi

sudo mkdir -p "$MNT"
sudo mount -o loop "$IMG" "$MNT"

sudo sed -i '/configfs/d' "$MNT/etc/fstab"
sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' "$MNT/etc/selinux/config"
sudo ln -sf /usr/lib/systemd/system/ssh.service \
  "$MNT/etc/systemd/system/multi-user.target.wants/ssh.service"

sudo umount "$MNT"
echo "Patched $IMG: removed configfs fstab entry, disabled SELinux, enabled ssh.service"
