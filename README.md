# Linux install for PANASONIC (パナソニック) Let's Note (レッツノート) CF-SV7
Documenting my Linux setup for the CF-SV7. **Single boot!**— will not go into dual boot details.  
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

Skip to:
* [Circular scrolling](?tab=readme-ov-file#circular-scrolling)
* [Wireless switch](?tab=readme-ov-file#wireless-switch)
* [Disable s2idle/modern standby](?tab=readme-ov-file#s2idle-issues---switch-to-suspend-deep)
* [Last screen showing on wake issue](?tab=readme-ov-file#stop-last-screen-from-showing)
* [Add support for power switch + keyboard to wake](?tab=readme-ov-file#enable-power-switch-to-wake-and-keyboard-for-s2idle)
* [Function keys](?tab=readme-ov-file#function-keys)

＊Install script is untested by me. But if you follow everything here sequentially, everything should just work.  
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
Edit `/etc/hosts` according to your hostname
```
127.0.0.1  localhost
::1        localhost
127.0.1.1  SV7.localdomain  SV7
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
### Disable installing `-debug` packages

Edit `/etc/makepkg.conf`, add `!` to `debug` in OPTIONS
```
OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug lto)
```

### Install KDE (X11)
The Let's Note circular scrolling feature is very useful, but it **does not work on Wayland**. We will be using X11 instead.  
```
sudo pacman -S plasma-x11-session xorg-server xorg-xinit xorg-xrandr plasma-desktop sddm sddm-kcm kscreen kde-gtk-config breeze-gtk plasma-pa plasma-nm plasma-systemmonitor bluedevil powerdevil konsole dolphin kate spectacle ark systemsettings xdg-desktop-portal xdg-desktop-portal-kde xdg-user-dirs power-profiles-daemon fastfetch partitionmanager ntfs-3g dosfstools exfatprogs btrfs-progs intel-gpu-tools intel-media-driver libva-intel-driver vulkan-intel usbutils kdeplasma-addons
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
Then install 源ノ角ゴシック Code JP, it's a way better terminal and code font than Noto Sans Mono CJK JP.  
```
yay -S otf-source-han-code-jp
```
We will set KDE fonts later, but you can import my fontconfig to prefer Japanese glyphs over other Han unification characters:
```
git clone https://github.com/shoui520/CF-SV7-Linux && cd CF-SV7-Linux/config/fontconfig
cp fonts.conf ~/.config/fontconfig/fonts.conf
fc-cache -fv
```

### Japanese IME installation (日本語入力) - part 1
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
### Set display scaling

The display scaling is set incorrectly. Right click the desktop and click Display Settings. Change the display scaling to 125%, or whatever you are comfortable with.  

### Set SDDM theme to Breeze
Make SDDM look KDE-native.  

1. Open KDE System Settings
2. Click "Colours & Themes" (色とテーマ)
3. Click Login Screen (SDDM)/ログイン画面 (SDDM)
4. Click "Breeze", then click Apply/適用
5. Enter the root password.

### Set KDE fonts

1. Open KDE System Settings
2. Click "Text & Fonts" (テキストとフォント)
3. Set the fonts to:
   * Noto Sans CJK JP
   * 源ノ角ゴシック Code JP Regular
   * Noto Sans CJK JP
   * Noto Sans CJK JP
   * Noto Sans CJK JP
   * Noto Sans CJK JP
4. Click Apply (適用).  
### Japanese IME installation - part 2

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

### Fix カタカナひらがな key not working on Mozc

```
sudo pacman -S keyd
```
```
sudo systemctl enable --now keyd
```
```
sudo tee /etc/keyd/default.conf << 'EOF'
[ids]
*
-0001:0001

[main]
katakanahiragana = hiragana

[shift]
katakanahiragana = katakana
EOF
sudo keyd reload
```

### Mozc UT dictionary

Highly optional as this requires compiling it yourself (no prebuilt binaries) but it vastly improves the Japanese IME 予測変換 experience on Linux.  
```
yay -S mozc-ut fcitx5-mozc-ut
```
This will compile them from source. You might want to do `watch -n 60 sudo -v` to refresh the sudo credential every 60 seconds so sudo doesn't time out while you're AFK and fail installing.  

After that, you need to re-configure Mozc in KDE:
KDE System Settings → Input Method → Add → Mozc. Ensure it's in "input method on". Ensure the layout is set properly so you can use your 半角 key.  

### KDE Ark plugins

The KDE unarchiver/archiver needs extra plugins for full functionality:
```
yay -S p7zip unzip zip lrzip lzop lz4 zstd xz bzip2 gzip libarchive unrar arj unar
```
### Japanese TTY (kmsconsole)
```
yay -S kmscon

sudo mkdir -p /etc/systemd/system/kmsconvt@.service.d
sudo tee /etc/systemd/system/kmsconvt@.service << 'EOF'
[Unit]
Description=KMSCon VT on %I
After=systemd-user-sessions.service
After=plymouth-quit-wait.service
Conflicts=getty@%i.service

[Service]
ExecStart=/usr/bin/kmscon "--vt=%I" --no-switchvt --font-name "Source Han Code JP Regular" --font-size 18 --login -- /usr/bin/login -p
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl disable getty@tty3
sudo systemctl enable --now kmsconvt@tty3
```
Now Ctrl-Alt-F3 should bring you to a TTY that supports Japanese text.  
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

### Function keys

All function keys work and produce scan codes, they can be mapped to anything you wish.   

These two Fn functions: Fn+F8 (restore display settings) and Fn+F10 (hibernate), don't do anything by default. The system receives the input, but doesn't know what to do with it. On Windows, Fn+F9 should just show the battery percentage, but on KDE it is mapped to switching the power plan.
If you wish to replicate the Panasonic intended Windows experience, follow the steps below.  

For Fn+F8, you need to install `autorandr`, it does the same thing as the Panasonic PC Utility "保存した情報で表示" feature. You can save display settings and load them on demand. Panasonic created this for business environments (e.g., Imagine having a display settings preset for your projector setup. You plug in the Let's Note to a projector, and press Fn+F8 and immediately have your projector display setup back.)  

```
sudo pacman -S autorandr
```
If you would like to save your current setup as the default profile, do the following:
```
autorandr --save default
autorandr -d default
```
Save a new profile:
```
autorandr --save <profile_name>
```
I created a shell script to let you easily load autorandr profiles. This requires `kdialog` as a dependency, get it now:
```
sudo pacman -S kdialog
```

Grab the script `fn-f8.sh` from the function-keys folder, put it in `~/.local/bin` or anywhere else you put your scripts.  
Make the script executable:
```
chmod +x fn-f8.sh
```

Now, set the script to execute with the Fn+F8 keyboard shortcut:  
KDE System Settings → Keyboard → Shortcuts → Add New → Command or script → select the fn-f8.sh script. Set Fn-F8 as the keyboard shortcut and click Apply.  


For Fn+F9, you can also replicate the Panasonic intended functionality with a shell script. 
Grab the script `fn-f9.sh` from the function-keys folder, put it in `~/.local/bin` or anywhere else you put your scripts.  
Make the script executable:
```
chmod +x fn-f9.sh
```

Now, set the script to execute with the Fn+F9 keyboard shortcut:  
KDE System Settings → Keyboard → Shortcuts → Add New → Command or script → select the fn-f9.sh script. Set Fn-F9 as the keyboard shortcut and click Apply.  

For Fn+F10, you need to set up hibernate (see below). After that's done, you can set the keyboard shortcut using KDE System Settings. Keyboard → Shortcuts → Power Management → Hibernate  

### Hibernate setup  
Since I opted for zram over swap initially, I didn't have an on-disk swapfile, but this is fine, we can still create one and use hibernate.  

NOTE: `count=8192` is for 8GB Let's Notes. If you have a 16GB one use `count=16384`
```
sudo dd if=/dev/zero of=/swapfile bs=1M count=8192 status=progress
sudo chmod 600 /swapfile
sudo mkswap /swapfile
```
Edit /etc/fstab:
```
/swapfile none swap defaults,pri=10 0 0
```
Enable it:
```
sudo swapon -a
```
Identify the partition the swapfile is on (for me, `/dev/sda2`)
```
df /swapfile
```

Find the resume offset. 
```
sudo filefrag -v /swapfile | head -n 4
```
The value you are looking for is the fourth number you see, under `physical_offset`. There are two numbers under `physical_offset`. This is a range. Use the first number of the range.  
Edit kernel parameters in `/etc/default/grub`, append "resume=/path/to/device resume_offset=<offset>` to your GRUB_CMDLINE_LINUX_DEFAULT.  
e.g.,:
```
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 mitigations=off mem_sleep_default=deep resume=/dev/sda2 resume_offset=59535360"
```
Regenerate grub config
```
sudo grub-mkconfig -o /boot/grub/grub.cfg
```
Add the resume hook to mkinitcpio. Edit `/etc/mkinitcpio.conf`. Add `resume` to the HOOKS array, AFTER `filesystems`
e.g.,:
```
HOOKS=(base systemd autodetect microcode modconf kms keyboard keymap sd-vconsole block filesystems resume fsck)
```
Now rebuild mkinitcpio:
```
sudo mkinitcpio -P
```
Reboot.  
### Sleep issues

#### Stop last screen from showing
When the laptop is waken up, it will show the last screen shown when the laptop was put to sleep. This means anyone will see your desktop before the KDE lock screen. You need to do some clever trickery to get around this:

Add this systemd script (save as a .sh file) to `/etc/systemd/system-sleep/` (mkdir it if it doesn't exist)
```
#!/bin/bash
BACKLIGHT=/sys/class/backlight/intel_backlight

if [ "$1" = "pre" ]; then
    cat "$BACKLIGHT/brightness" > /tmp/pre_suspend_brightness
    cat /sys/class/tty/tty0/active > /tmp/pre_suspend_vt
    loginctl lock-sessions
    chvt 3
fi

if [ "$1" = "post" ]; then
    systemd-run --no-block bash -c '
        VT=$(cat /tmp/pre_suspend_vt | grep -o "[0-9]*")
        chvt "$VT"
        echo 0 > /sys/class/backlight/intel_backlight/brightness
        sleep 3
        cat /tmp/pre_suspend_brightness > /sys/class/backlight/intel_backlight/brightness
    '
fi
```
Then run chmod +x on the file. e.g.:
```
sudo chmod +x /etc/systemd/system-sleep/lock-first.sh
```

This solution isn't perfect. You might need to further adjust the `sleep 2.5` line to wait for longer, depending on your experiences.  

#### S2idle issues - switch to suspend (deep)
The out of box sleep experience (using s2idle) is very poor in my opinion. In my experience, s2idle sleep on this laptop is just screen off with extra steps: the CPU stays on, the fan stays spinning and processes continue running. I've also encountered a kernel panic with s2idle before. I haven't been able to repro it but because of stability concerns like this and battery life disadvantages, I just don't see the point of s2idle. So, I opted to use deep/suspend-to-ram/S3 instead.  

Append `mem_sleep_default=deep` to your `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`
e.g.,:
```
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 mitigations=off mem_sleep_default=deep"
```
Then regenerate GRUB config: 
```
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

#### Enable power switch to wake (and keyboard for s2idle)

On Windows installs with the Panasonic drivers installed, you should be able to wake the laptop up from sleep with the internal keyboard, the power button, by opening the lid and with USB peripherals. On Linux, by default you can only wake up the laptop by opening the lid or using USB peripherals.  

Works on both s2idle and deep: You can add support for waking up with the power button by doing this:
```
sudo pacman -S acpi_call-dkms
sudo modprobe acpi_call
echo "acpi_call" | sudo tee /etc/modules-load.d/acpi_call.conf
sudo tee /usr/lib/systemd/system-sleep/wake-fix.sh << 'EOF'
#!/bin/bash
if [ "$1" = "pre" ]; then
    echo '\_SB.PCI0.LPCB.EC0.EC43 1' > /proc/acpi/call
fi
EOF
sudo chmod +x /usr/lib/systemd/system-sleep/wake-fix.sh
```

Works on only s2idle: For the internal keyboard, you can enable support by doing this:  
```
echo enabled | sudo tee /sys/devices/platform/i8042/serio0/power/wakeup
```

### KDE Performance Optimization:
#### Disable file indexer:
```
balooctl6 disable
```
#### Disable animations and effects

KDE System Settings → Animations → Global animation speed: **Instant** - disables all animations. 

KDE System Settings → Window Management → Desktop Effects. Disable unneeded effects here. I only have 3 enabled: Overview, Dialog Parent, Decrease saturation of non responding apps

You can also disable transparency for the bottom panel. right click > edit panel > transparency > opaque
#### KRunner plugins

KDE's search comes with a ton of plugins that all get loaded at every single keystroke. You can slim down the number of plugins you have enabled. 

KDE System Settings → Search → Plasma Search. Disable stuff you don't need. I have only 4 enabled: Power, Applications, System Settings, Global Shortcuts

### KDE applets and widgets

The more you have (on the bottom panel, desktop etc.) the more RAM it's using. 

You should:
1. Enter edit mode and remove widgets/applets you don't need.
2. Open the system tray settings and **disable** everything you don't need.

You can list currently active widgets with:
```
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
    var desktops = desktops();
    for (var i = 0; i < desktops.length; i++) {
        var widgets = desktops[i].widgets();
        print("Desktop " + i + ":");
        for (var j = 0; j < widgets.length; j++) {
            print("  " + widgets[j].type + " - " + widgets[j].id);
        }
    }
    var panels = panels();
    for (var i = 0; i < panels.length; i++) {
        var widgets = panels[i].widgets();
        print("Panel " + i + " (" + panels[i].location + "):");
        for (var j = 0; j < widgets.length; j++) {
            print("  " + widgets[j].type + " - " + widgets[j].id);
        }
    }
'
```

### KDE services

Search for "services" in the application launcher. Disable things you are certain you don't need.  
You can list enabled services with:
```
busctl --user call org.kde.kded6 /kded org.kde.kded6 loadedModules
```
You can search the name of the module in the Background Services GUI to find the friendly name. I only have the following loaded:
```
as 15 "desktopnotifier" "gtkconfig" "ktimezoned" "networkmanagement" "kameleon" "audioshortcutsservice" "kded_touchpad" "mprisservice" "plasma_accentcolor_service" "plasma-session-shortcuts" "keyboard" "bluedevil" "kscreen" "devicenotifications" "statusnotifierwatcher"
```

### Fcitx5 Plasma Theme Generator

This consumes 220MB of RAM doing nothing (for me) and can't be disabled. The only way to disable it is to rename the binary:
```
sudo mv /usr/bin/fcitx5-plasma-theme-generator /usr/bin/fcitx5-plasma-theme-generator.bak
```
If you want this to survive fcitx updates, add a pacman hook:
```
sudo mkdir -p /etc/pacman.d/hooks
sudo tee /etc/pacman.d/hooks/fcitx5-theme-generator.hook << 'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = fcitx5-configtool

[Action]
Description = Disabling fcitx5-plasma-theme-generator
When = PostTransaction
Exec = /usr/bin/mv /usr/bin/fcitx5-plasma-theme-generator /usr/bin/fcitx5-plasma-theme-generator.bak
EOF
```
Gives you back 220MB of RAM on idle.   

### Use simple themes and customizations.
Using default Breeze things is the best for performance. Avoid using themes and decorations that have complex effects such as blur and transparency to minimize memory and CPU usage. In general, the default Breeze stuff isn't hacked together with SVG and QML, it's native C++ so it's faster.  
### Misc tweaks 

malloc tuning: Qt apps respond well to MALLOC_ARENA_MAX=2 in your environment. glibc's default creates one arena per core which wastes virtual memory. On an 8-thread CPU that's 8 arenas × 64MB each of reserved address space that looks like memory usage in top even if it's not all resident. 
```
mkdir -p ~/.config/environment.d
echo "MALLOC_ARENA_MAX=2" > ~/.config/environment.d/malloc.conf
```

## CachyOS BORE Full-LTO Kernel for Panasonic Let's Note CF-SV7
Compile this kernel to squeeze as much performance out of the CF-SV7 as possible. It has been really stable for me so far, which was a pleasant surprise. 

* CachyOS with BORE scheduler
* Clang/LLVM Full LTO (whole-program link-time optimisation)
* -O3 aggressive optimisation
* Native Skylake CPU target (AVX2, BMI2, AES-NI, FMA)
* 1000Hz tick rate, full tickless, full preempt
* BBR3 TCP congestion control
* Transparent hugepages always-on
* NUMA disabled (single-socket laptop)

Intended environment:
* Arch Linux
* GRUB bootloader

Build deps
```
sudo pacman -S --needed base-devel bc cpio gettext initramfs libelf pahole perl \
  python rust rust-bindgen rust-src tar xz zstd clang llvm lld
```  

Clone repo  
```
mkdir -p ~/kernel-build && cd ~/kernel-build
git clone https://github.com/CachyOS/linux-cachyos.git
cd linux-cachyos/linux-cachyos
```

Edit the PKGBUILD
```
# BEFORE:
: "${_use_llvm_lto:=thin}"
# AFTER:
: "${_use_llvm_lto:=full}"
```
```
# BEFORE:
: "${_tcp_bbr3:=no}"
# AFTER:
: "${_tcp_bbr3:=yes}"
```
add this block in the prepare() function, right after the USER_NS line (~line 466):
```
    scripts/config -d NUMA
```

Will use march=X86_NATIVE_CPU by default, which will be the right one for your CPU. 

Create a temporary 32G swap file (full LTO uses a lot of memory)
```
sudo fallocate -l 32G /tempswap
sudo chmod 600 /tempswap
sudo mkswap /tempswap
sudo swapon /tempswap
```
Start the build (ETA: 4 hours)
```
cd ~/kernel-build/linux-cachyos/linux-cachyos
makepkg -s --cleanbuild 2>&1 | tee build.log
```

Install after build is complete:
```
sudo pacman -U linux-cachyos-*-x86_64.pkg.tar.zst
```
Regenerate GRUB
```
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

Clean up the swapfile
```
sudo swapoff /tempswap
sudo rm /tempswap
```

Reboot and pick linux-cachyos from GRUB
```
reboot
```

GRUB Tips:
To make it easier to pick kernels from GRUB, add these to `/etc/default/grub`:
```
GRUB_TIMEOUT=5
GRUB_DEFAULT=saved
GRUB_SAVEDEFAULT=true
GRUB_DISABLE_SUBMENU=true
```

### zsh

I recommend switching to zsh, since it makes it easier to use the terminal. Here's the braindead painless setup:

```
chmod +x migrate-to-zsh.sh
./migrate-to-zsh.sh
```

Now edit your Konsole profile to use `/usr/bin/zsh`.  

### Fastest browsers

All were tested with extensions disabled. All tests were done at least twice to make sure it's not a fluke. 


Speedometer 3.1 results:

* `google-chrome-dev`, version 	148.0.7730.2-1: **13.2**
* `google-chrome`, version 146.0.7680.153-1: **13.2**
* `helium-browser-bin`: version 0.10.5.1-1: **13.1**
* `brave-bin`, version 1:1.88.132-1: **12.7**¹
* `vivaldi`, version 	7.8.3925.81-1: **12.5**
* `firefox-developer-edition`, version 149.0b8-1: **11.7** 
* `zen-browser-bin`, version 1.19.3b-1: **11.5**
* `firefox`, version 	148.0.2-1: **11.4**
* `ungoogled-chromium-bin`, version 145.0.7632.116-1: **10.4**
* `microsoft-edge-stable-bin`, version 	146.0.3856.62-1: **10.3**²
* `floorp-bin`, version 12.11.0-1: **8.81**

¹ - Brave Shields disabled.  
² - While Microsoft Edge gives you the best Speedometer 3.1 results on Windows, it is unclear why it is slower on Linux and tasks the CPU harder than other browsers on Linux.   

The overall best experience is Helium Browser. It's just as fast as Chrome while using less memory than Chrome, supports uBlock Origin and GPU-accelerated video decoding should just work out of the box if you have `intel-media-driver` `libva-intel-driver` `vulkan-intel` installed. For 60 FPS video, YouTube serves these in the AV1 format, which the i5-8350U has no hardware decoding support for, so you need to use **enhanced-h264ify** with the "Block AV1" option.  

### DVD playback
The best way to playback DVDs on Linux is to just use VLC. You can install VLC plus everything it needs with the following command:

```
sudo pacman -S vlc ffmpeg vlc-plugins-all
```
