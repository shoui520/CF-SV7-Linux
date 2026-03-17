# Linux install for PANASONIC (パナソニック) Let's Note (レッツノート) CF-SV7
Documenting my linux setup for the CF-SV7. **Single boot!**— will not go into dual boot details.  
Let's Note circular scrolling (くるくるスクロール) only works on X11, it does not work on Wayland, so we will NOT be using Wayland.  
We will be using *Arch Linux* for the best performance, software support, firmware support, update availability and modularity.   
This setup is focused on Japanese support (日本語化), maximizing performance out of the hardware, and making sure everything works as intended by Panasonic just like it would on Windows.  

My system information for brevity, but all CF-SV7's should be the same and this should work for all CF-SV7's:
* 型番: CF-SV7RDAVS
* Host: CF-SV7-3
* Processor: Intel(R) Core(TM) i5-8350U @ 1.70GHz
* Memory: 8GB
* Disk: 256GB M.2 SATA

As for the CF-SV8, it's the Whiskey Lake refresh of the CF-SV7. It looks otherwise identical hardware-wise other than a more recent CPU (i5-8350U vs. i5-8365U) and chipset. I have not tested it, but I expect this guide to work just as well for the CF-SV8 too (not a guarantee).  
## Arch Install

Boot into an Arch installation media (Archiso).  

### Load the Japanese 106-key 日本語配列 layout the Let's Note uses:  
```
loadkeys jp106
```
### Make the font bigger:
```
setfont ter-132b
```
### Connect to WiFi:
```
iwctl
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "YOUR_SSID"
```
Then type `exit` to exit iwctl.  
### Verify internet connection:
```
ping -c 3 1.1.1.1
```
### Sync system clock:  
```
timedatectl set-ntp true
```
### Partitioning
Now, partition. First identify if your drive is SATA or NVMe (CF-SV7 supports both with its M.2 slot)  
```
lsblk
```
if it's SATA (like mine) then:
```
gdisk /dev/sda
```
Use `d` to delete the old partitions. (We're only keeping Arch Linux here.) Then make new ones:  
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
Write and exit:  
```
Command: w
```
### Format
```
mkfs.fat -F 32 /dev/sda1
mkfs.ext4 /dev/sda2
```
I use Ext4 over Btrfs because Ext4 is just more predictable and reliable.  
### Mount  
```
mount /dev/sda2 /mnt
mount --mkdir /dev/sda1 /mnt/boot
```
### Pacman mirrors 
Set the pacman mirror to the most reliable mirror:  
Edit `/etc/pacman.d/mirrorlist`
Put this as the first server:
```
Server = https://mirror.osbeck.com/archlinux/$repo/os/$arch
```
This is the server with the highest uptime.  
### Base system install (Linux-zen):  
``` 
pacstrap -K /mnt base linux-zen linux-zen-headers linux-firmware intel-ucode sof-firmware fwupd base-devel networkmanager nano man-db man-pages terminus-font iwd
```
Generate fstab: 
```
genfstab -U /mnt >> /mnt/etc/fstab
```
### Chroot: 
```
arch-chroot /mnt
```
### Set Timezone
(Change Asia/Tokyo to your timezone): 
```
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc
```

### Locale (ja_JP.UTF-8):  
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
### Console (TTY) setup
Edit this file: `/etc/vconsole.conf`
Add:
```
KEYMAP=jp106
FONT=ter-132b
```
We will set up 日本語表示 support in the TTY later.  
### Set hostname & user
 (change "SV7" to the hostname of your liking):  
```
echo "SV7" > /etc/hostname
```
Root password
```
passwd
```
Create your user. Change `<USER>` to your desired username.
```
useradd -m -G wheel -s /bin/bash <USER>
passwd <USER>
```
Allow your user to use sudo:
```
EDITOR=nano visudo
```
Uncomment this line:
```
%wheel ALL=(ALL:ALL) ALL
```

### Install a bootloader (GRUB): 
```
pacman -S grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
```

Edit GRUB config `/etc/default/grub`:
1. Set `GRUB_DEFAULT=saved`.
2. In `GRUB_CMDLINE_LINUX_DEFAULT`: remove `quiet` and add `mitigations=off` for a free performance boost.

Generate grub config:
```
grub-mkconfig -o /boot/grub/grub.cfg
```
### Enable services: 
```
systemctl enable NetworkManager
systemctl enable fstrim.timer
```
### zram
Set up zram compression, allows for more usable RAM in memory constrained situations without swapping to disk:  
```
pacman -S zram-generator
```
Edit `/etc/systemd/zram-generator.conf`: 
Note: You can change the compression-algorithm to `zstd` for more usable compressed memory, but it uses more CPU. I use `lz4` to allow the CPU more room to breathe.  
```
[zram0]
zram-size = ram
compression-algorithm = lz4
swap-priority = 100
fs-type = swap
```
Edit `/etc/sysctl.d/99-zram.conf`:
```
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
```
### Reboot
Reboot into the installed base system:
```
exit
umount -R /mnt
reboot
```

### Desktop environment
Log into your user. We will finish installation on your user account.  
You will need to reconnect to the internet. The package `iwd` was installed with pacstrap for this reason. You can also use nmcli with an Ethernet cable too (`nmcli device connect enp0s31f6`)  
The TTY wants to display in 日本語, but we will only see 文字化け in the form of squares because we have not set up Japanese fonts for the TTY yet. We will do that after getting a working desktop environment.  

### Install Yay (AUR helper)
```
sudo pacman -S git
cd /tmp
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si
``` 
### Install KDE (X11)
The Let's Note circular scrolling feature is very useful, but it **does not work on Wayland**. We will be using X11 instead.  
```
sudo pacman -S plasma-x11-session xorg-server xorg-xinit xorg-xrandr plasma-desktop sddm sddm-kcm kscreen kde-gtk-config breeze-gtk plasma-pa plasma-nm plasma-systemmonitor bluedevil powerdevil konsole dolphin kate spectacle ark systemsettings xdg-desktop-portal xdg-desktop-portal-kde xdg-user-dirs power-profiles-daemon fastfetch partitionmanager ntfs-3g dosfstools exfatprogs btrfs-progs intel-gpu-tools intel-media-driver libva-intel-driver vulkan-intel usbutils
```
### PipeWire for audio
```
sudo pacman -S pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
```
### Enable SDDM
```
sudo systemctl enable sddm
```
### Japanese fonts
```
sudo pacman -S noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
```
Then install 源ノゴシック Code JP, it's a way better terminal and code font than Noto Sans Mono CJK JP.  
```
yay -S otf-source-han-code-jp
```

### Japanese IME installation (日本語入力)
```
sudo pacman -S fcitx5 fcitx5-mozc fcitx5-gtk fcitx5-qt fcitx5-configtool
```
Edit `/etc/environment`: 
```
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=ibus
```
Make it autostart:
```
mkdir -p ~/.config/autostart
cp /usr/share/applications/org.fcitx.Fcitx5.desktop ~/.config/autostart/
```
### Disable KDE Wallet annoyance:

The kwallet config file is: `~/.config/kwalletrc`
```
[Wallet]
Enabled=false
First Use=false
```

### Reboot
```
xdg-user-dirs-update
sudo pacman -Syu
reboot
```

In SDDM, ensure the **X11** session of Plasma is selected in the top-left, not Wayland.  

Login.  

### Japanese IME installation (continuation)

In KDE, the IME requires a little setup to work as expected.

By default, KDE thinks your hardware layout is the generic English 102/104 key keyboard. It will also tell this to Mozc, so as a result, the 半角 key to toggle the IME will not work (which is fine for people with English keyboards, since you can just use Ctrl-Space). To fix this, you will need to set the keyboard layout to Japanese (日本語) once again because KDE's setting for this is separate from `loadkeys jp106`

Set the hardware layout to Japanese:
1. Open KDE System Settings
2. Under **Input/Output Devices (入力/出力デバイス)**, click **Keyboard/キーボード**
3. Set the Model/モデル to Generic | Japanese 106-key
4. Enable Layouts, and add the "日本語" (Japanese) keyboard under "日本語" (Japanese).
5. Click **Apply/適用** to finish.

We are not quite done yet, now we need to set the IME in **Input Method**.

1. Open KDE System Settings
2. Under **Language & Time (言語と時刻)**, click **Input Method (入力メソッド)**
3. You should see "Mozc" here by default. **If you don't**:, click "**Add input method/入力メソッドを追加**", uncheck "Show only current languages" in the bottom-left, search for "Mozc" and add it.
4. Remove any English keyboards/non-Japanese keyboards you see.
5. click "**Add input method/入力メソッドを追加**", add the Japanese keyboard: キーボード - 日本語 / Keyboard - Japanese
6. Use the thing on the left to drag the Japanese keyboard: キーボード - 日本語 / Keyboard - Japanese to "Input Method Off/入力メソッドオフ".
7. Ensure Mozc is in "Input Method On/入力メソッドオン"
8. Click **Apply/適用** to finish.

### Circular scrolling

Use the Synaptics driver instead of libinput. This will also mean the touchpad will no longer be manageable by KDE- which is fine since I have already figured out the best Synaptics settings for the CF-SV7 touchpad.
```
sudo pacman -S xf86-input-synaptics
```
Create a file:
```
sudo nano /etc/X11/xorg.conf.d/70-synaptics.conf
```
Paste:
```
Section "InputClass"
        Identifier "touchpad catchall"
        Driver "synaptics"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Option "TapButton1" "1"
        Option "TapButton2" "3"
        Option "TapButton3" "2"
        Option "CircularScrolling" "on"
        Option "CircScrollTrigger" "0"
        Option "CircularPad" "on"
        Option "LeftEdge" "1574"
        Option "RightEdge" "5416"
        Option "TopEdge" "1535"
        Option "BottomEdge" "4395"
        Option "VertScrollDelta" "-200"
EndSection
```
A bug in whatever reads the config file hates decimals on my LC_NUMERIC, so we'll just use `synclient` to set the decimal values through an autostart script:
```
mkdir -p ~/.config/autostart-scripts
```
```
cat > ~/.config/autostart-scripts/touchpad.sh << 'EOF'
#!/bin/bash
synclient MinSpeed=0.1
synclient MaxSpeed=1.3
synclient AccelFactor=0.01
synclient CircScrollDelta=0.4
EOF
chmod +x ~/.config/autostart-scripts/touchpad.sh
```
Log out and log back in and you're done!  

### Wireless switch

The wireless toggle switch on the left of the laptop is not a hardware switch for the WiFi- all it does is physically disconnect Bluetooth then tell the driver on Windows to also disable WiFi. So by default on Linux, all it does is disable Bluetooth, which only does half of what we want.  
I got it working with a bit of reverse engineering of the DSDT and made a script to make it "just work"

Install:  
```
sudo modprobe ec_sys
git clone https://github.com/shoui520/CF-SV7-Linux && cd CF-SV7-Linux/wireless-switch/
chmod +x install.sh
sudo ./install.sh
```

How it works:  
```
- **EC register `0xA6`, bit 0**: `1` = switch ON, `0` = switch OFF
- **ACPI event `0x0050`**: Fired by EC query `_Q93` via the `panasonic-laptop` kernel module whenever the switch is toggled (logged as "Unknown hotkey event: 0x0050" in journald)
- On each event (and at service start), the daemon reads `0xA6` and calls `rfkill` to match```
The wireless switch state was traced through the DSDT:
EC query _Q93 → TRDF() → WLSW.NOTF() → HIND(0x50) + Notify
WLSW.WSST() → HKEY.SGET(0x0B) → EC0.G6F0() → reads EC register 0xA6 bit 0

The switch also physically cuts USB power to the Bluetooth controller (typically on bus 1-7), which is an EC-level behaviour independent of this daemon. This script only handles the Wi-Fi rfkill side, since Bluetooth is already handled by the hardware.
```
### KDE Performance Optimization:
#### Disable file indexer:
```
balooctl6 disable
```
