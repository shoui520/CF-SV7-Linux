#!/bin/bash
# =============================================================================
# CF-SV7 Arch Linux — Phase 1 (run from Archiso)
# =============================================================================
# Connect to WiFi first (iwctl), then run this script.
# After it finishes, reboot and run phase2-postinstall.sh as your user.
# =============================================================================
set -euo pipefail
trap 'echo "ERROR on line $LINENO. Aborting."; exit 1' ERR

# ── Configuration ────────────────────────────────────────────────────────────
HOSTNAME="SV7"
USERNAME="shoui"
TIMEZONE="Asia/Tokyo"
LOCALE="ja_JP.UTF-8"
KEYMAP="jp106"
FONT="ter-132b"
MIRROR="https://mirror.osbeck.com/archlinux/\$repo/os/\$arch"

# Disk — set to your drive. Use "auto" to detect the first non-USB disk.
DISK="auto"

# Partition sizes
EFI_SIZE="1G"
# Root uses remaining space

# ── Helpers ──────────────────────────────────────────────────────────────────
info()  { printf '\033[1;34m:: %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m:: %s\033[0m\n' "$*"; }
err()   { printf '\033[1;31m:: %s\033[0m\n' "$*"; exit 1; }

confirm() {
    echo ""
    info "Configuration summary:"
    echo "  Hostname:  $HOSTNAME"
    echo "  Username:  $USERNAME"
    echo "  Timezone:  $TIMEZONE"
    echo "  Locale:    $LOCALE"
    echo "  Keymap:    $KEYMAP"
    echo "  Disk:      $DISK"
    echo ""
    warn "This will WIPE $DISK. Press Enter to continue, Ctrl-C to abort."
    read -r
}

# ── Detect disk ──────────────────────────────────────────────────────────────
if [[ "$DISK" == "auto" ]]; then
    # Pick the first non-removable, non-loop block device
    DISK=$(lsblk -dnpo NAME,TYPE,RM | awk '$2=="disk" && $3=="0" {print $1; exit}')
    [[ -n "$DISK" ]] || err "Could not auto-detect disk. Set DISK= manually."
    info "Auto-detected disk: $DISK"
fi

# Determine partition naming (nvme uses p1/p2, sata uses 1/2)
if [[ "$DISK" == *nvme* ]]; then
    PART1="${DISK}p1"
    PART2="${DISK}p2"
else
    PART1="${DISK}1"
    PART2="${DISK}2"
fi

confirm

# ── Pre-flight ───────────────────────────────────────────────────────────────
info "Setting console font and keymap"
loadkeys "$KEYMAP"
setfont "$FONT" 2>/dev/null || true

info "Syncing clock"
timedatectl set-ntp true

info "Verifying internet"
ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1 || err "No internet. Connect with iwctl first."

# ── Partitioning ─────────────────────────────────────────────────────────────
info "Partitioning $DISK"
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+"$EFI_SIZE" -t 1:EF00 "$DISK"
sgdisk -n 2:0:0           -t 2:8304 "$DISK"
partprobe "$DISK"
sleep 1

# ── Format ───────────────────────────────────────────────────────────────────
info "Formatting partitions"
mkfs.fat -F 32 "$PART1"
mkfs.ext4 -F "$PART2"

# ── Mount ────────────────────────────────────────────────────────────────────
info "Mounting"
mount "$PART2" /mnt
mount --mkdir "$PART1" /mnt/boot

# ── Mirrors ──────────────────────────────────────────────────────────────────
info "Setting pacman mirror"
cat > /etc/pacman.d/mirrorlist <<EOF
Server = $MIRROR
EOF

# ── Pacstrap ─────────────────────────────────────────────────────────────────
info "Installing base system (linux-zen)"
pacstrap -K /mnt \
    base linux-zen linux-zen-headers linux-firmware intel-ucode sof-firmware \
    fwupd base-devel networkmanager nano man-db man-pages terminus-font iwd git

# ── Fstab ────────────────────────────────────────────────────────────────────
info "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# ── Chroot setup (written as a heredoc script) ───────────────────────────────
info "Entering chroot to configure the system"

cat > /mnt/tmp/chroot-setup.sh <<'CHROOT_SCRIPT'
#!/bin/bash
set -euo pipefail

HOSTNAME="@@HOSTNAME@@"
USERNAME="@@USERNAME@@"
TIMEZONE="@@TIMEZONE@@"
LOCALE="@@LOCALE@@"
KEYMAP="@@KEYMAP@@"
FONT="@@FONT@@"
PART2="@@PART2@@"

info()  { printf '\033[1;34m:: %s\033[0m\n' "$*"; }

# Timezone
info "Setting timezone: $TIMEZONE"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

# Locale
info "Setting locale: $LOCALE"
sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen
locale-gen
cat > /etc/locale.conf <<EOF
LANG=${LOCALE}
LC_COLLATE=${LOCALE}
LC_MESSAGES=${LOCALE}
EOF

# Console
info "Setting console keymap and font"
cat > /etc/vconsole.conf <<EOF
KEYMAP=${KEYMAP}
FONT=${FONT}
EOF

# Hostname
info "Setting hostname: $HOSTNAME"
echo "$HOSTNAME" > /etc/hostname

# Root password
info "Set root password:"
passwd

# User
info "Creating user: $USERNAME"
useradd -m -G wheel -s /bin/bash "$USERNAME"
info "Set password for $USERNAME:"
passwd "$USERNAME"

# Sudo
info "Enabling wheel group sudo"
sed -i 's/^# *%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# GRUB
info "Installing GRUB"
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
# Set kernel params: remove quiet, add mitigations=off and mem_sleep_default=deep
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 mitigations=off mem_sleep_default=deep"/' /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg

# Services
info "Enabling services"
systemctl enable NetworkManager
systemctl enable fstrim.timer

# zram
info "Setting up zram"
pacman -S --noconfirm zram-generator

cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = ram
compression-algorithm = lz4
swap-priority = 100
fs-type = swap
EOF

mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-zram.conf <<EOF
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF

info "Chroot setup complete."
CHROOT_SCRIPT

# Substitute variables into the chroot script
sed -i "s|@@HOSTNAME@@|$HOSTNAME|g"  /mnt/tmp/chroot-setup.sh
sed -i "s|@@USERNAME@@|$USERNAME|g"  /mnt/tmp/chroot-setup.sh
sed -i "s|@@TIMEZONE@@|$TIMEZONE|g"  /mnt/tmp/chroot-setup.sh
sed -i "s|@@LOCALE@@|$LOCALE|g"      /mnt/tmp/chroot-setup.sh
sed -i "s|@@KEYMAP@@|$KEYMAP|g"      /mnt/tmp/chroot-setup.sh
sed -i "s|@@FONT@@|$FONT|g"          /mnt/tmp/chroot-setup.sh
sed -i "s|@@PART2@@|$PART2|g"        /mnt/tmp/chroot-setup.sh

chmod +x /mnt/tmp/chroot-setup.sh
arch-chroot /mnt /tmp/chroot-setup.sh
rm /mnt/tmp/chroot-setup.sh

# ── Plant Phase 2 into the new system ────────────────────────────────────────
info "Copying phase 2 script into new system"
if [[ -f "$(dirname "$0")/phase2-postinstall.sh" ]]; then
    cp "$(dirname "$0")/phase2-postinstall.sh" "/mnt/home/$USERNAME/phase2-postinstall.sh"
    arch-chroot /mnt chown "$USERNAME:$USERNAME" "/home/$USERNAME/phase2-postinstall.sh"
    arch-chroot /mnt chmod +x "/home/$USERNAME/phase2-postinstall.sh"
    info "Phase 2 script placed at /home/$USERNAME/phase2-postinstall.sh"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
info "Phase 1 complete!"
echo ""
echo "  Next steps:"
echo "    1. umount -R /mnt"
echo "    2. reboot"
echo "    3. Log in as $USERNAME"
echo "    4. Connect to WiFi:  nmcli device wifi connect \"SSID\" password \"PASS\""
echo "       Or with iwd:      iwctl station wlan0 connect \"SSID\""
echo "    5. Run:  ./phase2-postinstall.sh"
echo ""
