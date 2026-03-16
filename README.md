# CF-SV7-Linux
Documenting my linux setup for the CF-SV7. Single boot. X11. Arch Linux. 完全日本語化.

## Arch Install

Load 日本語配列 layout
```
loadkeys jp106
```
Make the font bigger
```
setfont ter-132b
```
Connect to WiFi
```
iwctl
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "YOUR_SSID"
```
Verify:
```
ping -c 3 1.1.1.1
```
Sync system clock
```
timedatectl set-ntp true
```
Now, partition. First identify if your drive is SATA or NVMe (CF-SV7 supports both with its M.2 slot)  
```
lsblk
```
if it's SATA (like mine) then:
```
gdisk /dev/sda
```
Use `d` to delete old partitions. Then make new ones.
```
Command: n
Partition number: 1
First sector: (enter for default)
Last sector: +1G
Hex code: EF00
```
```
Command: n
Partition number: 2
First sector: (enter for default)
Last sector: (enter for default — uses remaining space)
Hex code: 8304
```
Write and exit
```
Command: w
```
Format:
```
mkfs.fat -F 32 /dev/sda1
mkfs.ext4 /dev/sda2
```
Mount
```
mount /dev/sda2 /mnt
mount --mkdir /dev/sda1 /mnt/boot
```
Set the pacman mirror to the most reliable mirror:  
Edit `/etc/pacman.d/mirrorlist`
Put this as the first server:
```
Server = https://mirror.osbeck.com/archlinux/$repo/os/$arch
```
Base system install (Linux zen)
``` 
pacstrap -K /mnt base linux-zen linux-zen-headers linux-firmware intel-ucode sof-firmware fwupd base-devel networkmanager nano man-db man-pages terminus-font
```
Generate fstab
```
genfstab -U /mnt >> /mnt/etc/fstab
```
Chroot
```
arch-chroot /mnt
```
Set Timezone
```
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc
```

Locale (ja_JP.UTF-8):  
Edit `/etc/locale.gen`. 
Uncomment this line:
```
ja_JP.UTF-8 UTF-8
```
Generate:
```
locale-gen
```
Set system locale. Edit this file `/etc/locale.conf`. 
Add this:  
```
LANG=ja_JP.UTF-8
LC_COLLATE=ja_JP.UTF-8
LC_MESSAGES=ja_JP.UTF-8
```
Console setup
Edit this file: `/etc/vconsole.conf`
Add:
```
KEYMAP=jp106
FONT=ter-132b
```

Set hostname
```
echo "SV7" > /etc/hostname
```
Root password
```
passwd
```
Create your user
```
useradd -m -G wheel -s /bin/bash <USER>
passwd <USER>
```
Add yourself to sudo:
```
EDITOR=nano visudo
```
Uncomment this line:
```
%wheel ALL=(ALL:ALL) ALL
```

Grub bootloader
```
pacman -S grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
```

Edit GRUB config `/etc/default/grub`
1. Set `GRUB_DEFAULT=saved`.
2. In GRUB_CMDLINE_LINUX_DEFAULT: remove `quiet` and add `mitigations=off` for a free performance boost.

Generate grub config
```
grub-mkconfig -o /boot/grub/grub.cfg
```
Enable services
```
systemctl enable NetworkManager
systemctl enable fstrim.timer
```
zram
```
pacman -S zram-generator
```
cat > /etc/systemd/zram-generator.conf << 'EOF'
[zram0]
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF
```
cat > /etc/sysctl.d/99-zram.conf << 'EOF'
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF
```

Install KDE (X11)

WIP
