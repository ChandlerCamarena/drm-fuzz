#!/usr/bin/env bash
# Applies required post-create-image.sh patches to the syzkaller rootfs image.
# Run once after tools/create-image.sh generates a fresh trixie.img.
set -euo pipefail

IMG="syzkaller/tools/trixie.img"
MNT="/mnt/trixie-edit"
KERNEL_SRC="/home/computationz/Projects/drm-fuzz/linux"

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

sudo make -C "$KERNEL_SRC" INSTALL_MOD_PATH="$MNT" modules_install
sudo sed -i '/^vkms$/d' "$MNT/etc/modules"
echo vkms | sudo tee -a "$MNT/etc/modules" > /dev/null

sudo umount "$MNT"
echo "Patched $IMG: removed configfs fstab entry, disabled SELinux, enabled ssh.service, installed kernel modules, enabled vkms autoload"
