#!/bin/bash
# =============================================================================
# CF-SV7 Arch Linux — Phase 2 (run as your user after first reboot)
# =============================================================================
# Connect to WiFi first, then run this from your user account.
# This installs the full desktop environment, Japanese support, hardware
# quirk fixes, and all configuration.
# =============================================================================
set -euo pipefail
trap 'echo "ERROR on line $LINENO. Aborting."; exit 1' ERR

# ── Configuration ────────────────────────────────────────────────────────────
# Set these if you want hibernate support (requires on-disk swap)
HIBERNATE=true
SWAP_SIZE_MB=8192            # 8192 for 8GB RAM, 16384 for 16GB
RESUME_DEVICE=""             # auto-detected from /swapfile if left empty

# Optional: compile mozc-ut (takes a long time, but much better 予測変換)
INSTALL_MOZC_UT=false

# Optional: install the zsh migration
INSTALL_ZSH=true

# CF-SV7-Linux repo — will be cloned for config files
REPO_URL="https://github.com/shoui520/CF-SV7-Linux"

# ── Helpers ──────────────────────────────────────────────────────────────────
info()  { printf '\033[1;34m:: %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m:: %s\033[0m\n' "$*"; }
err()   { printf '\033[1;31m:: %s\033[0m\n' "$*"; exit 1; }
ask()   { read -rp "$(printf '\033[1;33m:: %s [y/N] \033[0m' "$*")" ans; [[ "$ans" =~ ^[Yy] ]]; }

# Check we're not root
[[ $EUID -ne 0 ]] || err "Run this as your normal user, not root."

# Check internet
ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1 || err "No internet. Connect first."

# ── Clone config repo ────────────────────────────────────────────────────────
info "Cloning CF-SV7-Linux config repo"
REPO_DIR="$(mktemp -d)"
git clone "$REPO_URL" "$REPO_DIR" 2>/dev/null || {
    warn "Could not clone repo. Falling back to local configs if available."
    REPO_DIR=""
}

# =============================================================================
# SECTION 1: Package manager setup
# =============================================================================

info "Installing yay (AUR helper)"
cd /tmp
rm -rf yay-bin
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si --noconfirm
cd ~

info "Disabling -debug packages in makepkg"
sudo sed -i "s/^OPTIONS=(\(.*\) debug \(.*\))/OPTIONS=(\1 !debug \2)/" /etc/makepkg.conf

# =============================================================================
# SECTION 2: KDE Plasma (X11) + desktop packages
# =============================================================================

info "Installing KDE Plasma (X11) and desktop packages"
sudo pacman -S --noconfirm --needed \
    plasma-x11-session xorg-server xorg-xinit xorg-xrandr \
    plasma-desktop sddm sddm-kcm kscreen kde-gtk-config breeze-gtk \
    plasma-pa plasma-nm plasma-systemmonitor bluedevil powerdevil \
    konsole dolphin kate spectacle ark systemsettings \
    xdg-desktop-portal xdg-desktop-portal-kde xdg-user-dirs \
    power-profiles-daemon fastfetch partitionmanager \
    ntfs-3g dosfstools exfatprogs btrfs-progs \
    intel-gpu-tools intel-media-driver libva-intel-driver vulkan-intel \
    usbutils kdeplasma-addons

info "Installing PipeWire audio stack"
sudo pacman -S --noconfirm --needed \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber

info "Enabling SDDM"
sudo systemctl enable sddm

# =============================================================================
# SECTION 3: Japanese fonts
# =============================================================================

info "Installing Japanese fonts"
sudo pacman -S --noconfirm --needed \
    noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra

info "Installing 源ノ角ゴシック Code JP"
yay -S --noconfirm otf-source-han-code-jp

info "Deploying fontconfig (prefer JP glyphs)"
mkdir -p ~/.config/fontconfig
if [[ -n "$REPO_DIR" ]]; then
    cp "$REPO_DIR/config/fontconfig/fonts.conf" ~/.config/fontconfig/fonts.conf
else
    # Inline fallback
    cat > ~/.config/fontconfig/fonts.conf <<'FONTCONF'
<?xml version='1.0'?>
<!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
<fontconfig>
 <match>
  <test compare="contains" name="lang"><string>ja</string></test>
  <edit mode="prepend" name="family"><string>Noto Sans CJK JP</string></edit>
 </match>
 <alias>
  <family>sans-serif</family>
  <prefer><family>Noto Sans CJK JP</family><family>Noto Color Emoji</family></prefer>
 </alias>
 <alias>
  <family>serif</family>
  <prefer><family>Noto Serif CJK JP</family><family>Noto Color Emoji</family></prefer>
 </alias>
 <alias>
  <family>monospace</family>
  <prefer><family>Source Han Code JP</family><family>Noto Color Emoji</family></prefer>
 </alias>
 <match target="pattern">
  <edit mode="append" name="family"><string>Noto Color Emoji</string></edit>
 </match>
 <dir>~/.local/share/fonts</dir>
</fontconfig>
FONTCONF
fi
fc-cache -fv

# =============================================================================
# SECTION 4: Japanese IME (fcitx5 + mozc)
# =============================================================================

info "Installing fcitx5 + Mozc"
sudo pacman -S --noconfirm --needed \
    fcitx5 fcitx5-mozc fcitx5-gtk fcitx5-qt fcitx5-configtool

info "Setting IME environment variables"
sudo tee /etc/environment > /dev/null <<'EOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=ibus
EOF

info "Setting fcitx5 autostart"
mkdir -p ~/.config/autostart
cp /usr/share/applications/org.fcitx.Fcitx5.desktop ~/.config/autostart/

info "Deploying fcitx5 profile (Mozc + JP keyboard)"
mkdir -p ~/.config/fcitx5
if [[ -n "$REPO_DIR" ]]; then
    cp "$REPO_DIR/config/fcitx5/profile" ~/.config/fcitx5/profile
else
    cat > ~/.config/fcitx5/profile <<'FCITX'
[Groups/0]
Name=デフォルト
Default Layout=jp
DefaultIM=mozc

[Groups/0/Items/0]
Name=keyboard-jp
Layout=

[Groups/0/Items/1]
Name=mozc
Layout=jp

[GroupOrder]
0=デフォルト
FCITX
fi

if $INSTALL_MOZC_UT; then
    info "Installing mozc-ut (this will compile from source — go get coffee)"
    warn "Running sudo keepalive so it doesn't time out during compile"
    # Background sudo refresh
    while true; do sudo -v; sleep 55; done &
    SUDO_KEEPALIVE_PID=$!
    yay -S --noconfirm mozc-ut fcitx5-mozc-ut || warn "mozc-ut build failed, continuing with stock mozc"
    kill $SUDO_KEEPALIVE_PID 2>/dev/null || true
fi

# =============================================================================
# SECTION 5: keyd (カタカナひらがな key fix)
# =============================================================================

info "Installing and configuring keyd"
sudo pacman -S --noconfirm --needed keyd
sudo systemctl enable --now keyd

sudo tee /etc/keyd/default.conf > /dev/null <<'EOF'
[ids]
*
-0001:0001

[main]
katakanahiragana = hiragana

[shift]
katakanahiragana = katakana
EOF
sudo keyd reload

# =============================================================================
# SECTION 6: KDE Wallet disable
# =============================================================================

info "Disabling KDE Wallet"
mkdir -p ~/.config
cat > ~/.config/kwalletrc <<'EOF'
[Wallet]
Enabled=false
First Use=false
EOF

# =============================================================================
# SECTION 7: Circular scrolling (Synaptics)
# =============================================================================

info "Installing Synaptics touchpad driver"
sudo pacman -S --noconfirm --needed xf86-input-synaptics

info "Deploying synaptics config"
sudo mkdir -p /etc/X11/xorg.conf.d
if [[ -n "$REPO_DIR" ]]; then
    sudo cp "$REPO_DIR/touchpad/70-synaptics.conf" /etc/X11/xorg.conf.d/70-synaptics.conf
else
    sudo tee /etc/X11/xorg.conf.d/70-synaptics.conf > /dev/null <<'XORG'
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
XORG
fi

info "Deploying touchpad autostart script (decimal values via synclient)"
mkdir -p ~/.config/autostart-scripts
cat > ~/.config/autostart-scripts/touchpad.sh <<'EOF'
#!/bin/bash
synclient MinSpeed=0.1
synclient MaxSpeed=1.3
synclient AccelFactor=0.01
synclient CircScrollDelta=0.4
EOF
chmod +x ~/.config/autostart-scripts/touchpad.sh

# =============================================================================
# SECTION 8: Wireless switch daemon
# =============================================================================

info "Installing wireless switch daemon"
sudo modprobe ec_sys 2>/dev/null || true

if [[ -n "$REPO_DIR" ]]; then
    cd "$REPO_DIR/wireless-switch"
    sudo chmod +x install.sh
    sudo ./install.sh
    cd ~
else
    # Inline install
    sudo tee /usr/local/bin/letsnote-wireless-switch.sh > /dev/null <<'WSCRIPT'
#!/bin/bash
EC_IO="/sys/kernel/debug/ec/ec0/io"
EC_OFFSET=$((0xA6))

read_switch() {
    local val
    val=$(dd if="$EC_IO" bs=1 skip="$EC_OFFSET" count=1 2>/dev/null | od -An -tu1 | tr -d ' ')
    echo $(( val & 1 ))
}

apply_state() {
    local state
    state=$(read_switch)
    if [[ "$state" == "1" ]]; then
        rfkill unblock wlan
        echo "Wireless switch ON — wlan unblocked"
    else
        rfkill block wlan
        echo "Wireless switch OFF — wlan blocked"
    fi
}

apply_state
journalctl -k -f --no-pager -g "Unknown hotkey event: 0x0050" | while read -r _; do
    apply_state
done
WSCRIPT
    sudo chmod 755 /usr/local/bin/letsnote-wireless-switch.sh

    sudo tee /etc/systemd/system/letsnote-wireless-switch.service > /dev/null <<'WSERVICE'
[Unit]
Description=Panasonic Let's Note Wireless Switch Daemon
After=multi-user.target
Wants=modprobe@ec_sys.service

[Service]
Type=simple
ExecStart=/usr/local/bin/letsnote-wireless-switch.sh
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
WSERVICE

    echo "ec_sys" | sudo tee /etc/modules-load.d/ec_sys.conf > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable --now letsnote-wireless-switch.service
fi

# =============================================================================
# SECTION 9: kmscon (Japanese TTY)
# =============================================================================

info "Installing kmscon (Japanese TTY support)"
yay -S --noconfirm kmscon

sudo tee /etc/systemd/system/kmsconvt@.service > /dev/null <<'EOF'
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

sudo systemctl disable getty@tty3 2>/dev/null || true
sudo systemctl enable --now kmsconvt@tty3

# =============================================================================
# SECTION 10: Function keys
# =============================================================================

info "Setting up function key scripts"
sudo pacman -S --noconfirm --needed autorandr kdialog

mkdir -p ~/.local/bin

if [[ -n "$REPO_DIR" ]]; then
    cp "$REPO_DIR/function-keys/fn-f8.sh" ~/.local/bin/fn-f8.sh
    cp "$REPO_DIR/function-keys/fn-f9.sh" ~/.local/bin/fn-f9.sh
else
    # fn-f8: autorandr profile loader
    cat > ~/.local/bin/fn-f8.sh <<'FN8'
#!/bin/sh
profiles=$(autorandr --list 2>/dev/null)
if [ -z "$profiles" ]; then
    notify-send -a "Save & Load Display Settings" "No autorandr profiles found" \
        "Save one first with: autorandr --save <n>"
    exit 1
fi
choice=$(echo "$profiles" | kdialog --menu "Restore display profile" \
    $(echo "$profiles" | awk '{print $1, $1}') \
    --title "Load Display Settings" 2>/dev/null)
[ -z "$choice" ] && exit 0
output=$(autorandr --load "$choice" --force 2>&1)
if [ $? -eq 0 ]; then
    notify-send -a "Load Display Settings" "Display profile restored" "Using profile: $choice"
else
    notify-send -a "Load Display Settings" "Failed to restore profile" "$output"
fi
FN8

    # fn-f9: battery display
    cat > ~/.local/bin/fn-f9.sh <<'FN9'
#!/bin/sh
found=0
for bat in /sys/class/power_supply/BAT*; do
    [ -d "$bat" ] || continue
    found=1
    capacity=$(cat "$bat/capacity" 2>/dev/null || echo "??")
    status=$(cat "$bat/status" 2>/dev/null || echo "Unknown")
    model=$(cat "$bat/model_name" 2>/dev/null || echo "Unknown")
    manufacturer=$(cat "$bat/manufacturer" 2>/dev/null)
    if [ "$status" = "Charging" ]; then icon="battery-charging"
    elif [ "$capacity" -ge 80 ] 2>/dev/null; then icon="battery-100"
    elif [ "$capacity" -ge 50 ] 2>/dev/null; then icon="battery-060"
    elif [ "$capacity" -ge 20 ] 2>/dev/null; then icon="battery-040"
    else icon="battery-low"; fi
    label="${manufacturer:+$manufacturer }$model"
    notify-send -i "$icon" -a "Battery" "Battery ${capacity}% — ${status}" "$label"
done
[ "$found" -eq 0 ] && notify-send -a "Battery" "No battery found" ""
FN9
fi
chmod +x ~/.local/bin/fn-f8.sh ~/.local/bin/fn-f9.sh

# Save default autorandr profile
info "Saving default autorandr profile (will be populated properly after first GUI boot)"

# =============================================================================
# SECTION 11: Hibernate
# =============================================================================

if $HIBERNATE; then
    info "Setting up hibernate (swapfile)"

    sudo dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_SIZE_MB" status=progress
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile

    # Add to fstab if not already there
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap defaults,pri=10 0 0' | sudo tee -a /etc/fstab > /dev/null
    fi
    sudo swapon -a

    # Detect resume device
    if [[ -z "$RESUME_DEVICE" ]]; then
        RESUME_DEVICE=$(df /swapfile --output=source | tail -1)
    fi

    # Get physical offset
    RESUME_OFFSET=$(sudo filefrag -v /swapfile | awk 'NR==4 {print $4}' | sed 's/\.\.//')

    info "Resume device: $RESUME_DEVICE, offset: $RESUME_OFFSET"

    # Update GRUB with resume parameters
    CURRENT_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | sed 's/.*="\(.*\)"/\1/')
    NEW_CMDLINE="$CURRENT_CMDLINE resume=$RESUME_DEVICE resume_offset=$RESUME_OFFSET"
    sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_CMDLINE\"|" /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    # Add resume hook to mkinitcpio
    if ! grep -q 'resume' /etc/mkinitcpio.conf; then
        sudo sed -i 's/filesystems/filesystems resume/' /etc/mkinitcpio.conf
    fi
    sudo mkinitcpio -P
fi

# =============================================================================
# SECTION 12: Sleep fixes
# =============================================================================

info "Deploying sleep fix (lock before suspend, hide last screen)"
sudo mkdir -p /etc/systemd/system-sleep
sudo tee /etc/systemd/system-sleep/lock-first.sh > /dev/null <<'SLEEPFIX'
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
SLEEPFIX
sudo chmod +x /etc/systemd/system-sleep/lock-first.sh

# =============================================================================
# SECTION 13: Power button wake + acpi_call
# =============================================================================

info "Setting up power button wake support"
sudo pacman -S --noconfirm --needed acpi_call-dkms
sudo modprobe acpi_call 2>/dev/null || true
echo "acpi_call" | sudo tee /etc/modules-load.d/acpi_call.conf > /dev/null

sudo tee /usr/lib/systemd/system-sleep/wake-fix.sh > /dev/null <<'EOF'
#!/bin/bash
if [ "$1" = "pre" ]; then
    echo '\_SB.PCI0.LPCB.EC0.EC43 1' > /proc/acpi/call
fi
EOF
sudo chmod +x /usr/lib/systemd/system-sleep/wake-fix.sh

# =============================================================================
# SECTION 14: KDE performance and configuration
# =============================================================================

info "Disabling Baloo file indexer"
balooctl6 disable 2>/dev/null || true

info "Deploying KDE configuration"

# KDE font settings
mkdir -p ~/.config
cat > ~/.config/kdeglobals.new <<'KDEGLOBALS'
[General]
font=Noto Sans CJK JP,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
fixed=Source Han Code JP Regular,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
menuFont=Noto Sans CJK JP,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
smallestReadableFont=Noto Sans CJK JP,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
toolBarFont=Noto Sans CJK JP,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1

[WM]
activeFont=Noto Sans CJK JP,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
KDEGLOBALS

# Merge into kdeglobals if it exists, otherwise just use ours
if [[ -f ~/.config/kdeglobals ]]; then
    # kwriteconfig approach for safety
    kwriteconfig6 --file kdeglobals --group General --key font "Noto Sans CJK JP,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" 2>/dev/null || true
    kwriteconfig6 --file kdeglobals --group General --key fixed "Source Han Code JP Regular,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" 2>/dev/null || true
    kwriteconfig6 --file kdeglobals --group General --key menuFont "Noto Sans CJK JP,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" 2>/dev/null || true
    kwriteconfig6 --file kdeglobals --group General --key smallestReadableFont "Noto Sans CJK JP,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" 2>/dev/null || true
    kwriteconfig6 --file kdeglobals --group General --key toolBarFont "Noto Sans CJK JP,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" 2>/dev/null || true
    kwriteconfig6 --file kdeglobals --group WM --key activeFont "Noto Sans CJK JP,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" 2>/dev/null || true
    rm ~/.config/kdeglobals.new
else
    mv ~/.config/kdeglobals.new ~/.config/kdeglobals
fi

# KDE animation speed → instant
kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 0 2>/dev/null || true

# SDDM theme → Breeze
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/theme.conf > /dev/null <<'EOF'
[Theme]
Current=breeze
EOF

# Display scaling → 125%
kwriteconfig6 --file kwinrc --group Xwayland --key Scale 1.25 2>/dev/null || true
# For X11, scale factor is set via kdeglobals
kwriteconfig6 --file kdeglobals --group KScreen --key ScaleFactor 1.25 2>/dev/null || true
# Also set the X11 DPI for SDDM
sudo tee -a /etc/sddm.conf.d/theme.conf > /dev/null <<'EOF'

[X11]
ServerArguments=-nolisten tcp -dpi 120
EOF

# KDE keyboard hardware model → Japanese 106-key
mkdir -p ~/.config
cat > ~/.config/kxkbrc <<'KXKB'
[Layout]
DisplayNames=
LayoutList=jp
Model=jp106
Use=true
KXKB

# =============================================================================
# SECTION 15: fcitx5-plasma-theme-generator kill + pacman hook
# =============================================================================

info "Disabling fcitx5-plasma-theme-generator (saves ~220MB RAM)"
if [[ -f /usr/bin/fcitx5-plasma-theme-generator ]]; then
    sudo mv /usr/bin/fcitx5-plasma-theme-generator /usr/bin/fcitx5-plasma-theme-generator.bak
fi

sudo mkdir -p /etc/pacman.d/hooks
sudo tee /etc/pacman.d/hooks/fcitx5-theme-generator.hook > /dev/null <<'EOF'
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

# =============================================================================
# SECTION 16: malloc tuning
# =============================================================================

info "Setting MALLOC_ARENA_MAX=2"
mkdir -p ~/.config/environment.d
echo "MALLOC_ARENA_MAX=2" > ~/.config/environment.d/malloc.conf

# =============================================================================
# SECTION 17: xdg-user-dirs
# =============================================================================

info "Generating XDG user directories"
xdg-user-dirs-update

# =============================================================================
# SECTION 18: zsh (optional)
# =============================================================================

if $INSTALL_ZSH; then
    info "Migrating to zsh"
    if [[ -n "$REPO_DIR" && -f "$REPO_DIR/migrate-to-zsh.sh" ]]; then
        chmod +x "$REPO_DIR/migrate-to-zsh.sh"
        "$REPO_DIR/migrate-to-zsh.sh"
    else
        # Inline zsh setup
        sudo pacman -S --noconfirm --needed zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting

        if [[ -f ~/.bash_history ]]; then
            ts=$(date +%s)
            awk -v ts="$ts" '!seen[$0]++ { printf ": %d:0;%s\n", ts++, $0 }' \
                ~/.bash_history > ~/.zsh_history
        fi

        cat > ~/.zshrc <<'ZSHRC'
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS
setopt SHARE_HISTORY INC_APPEND_HISTORY
PS1='[%n@%m %1~]%# '
setopt CORRECT
autoload -Uz compinit; compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' rehash true
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search; zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search; bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search; bindkey '^[OB' down-line-or-beginning-search
bindkey '^R' history-incremental-search-backward
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
bindkey '^F' forward-word
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
setopt AUTO_CD INTERACTIVE_COMMENTS
ZSHRC

        chsh -s /usr/bin/zsh
        sudo cp ~/.zshrc /root/.zshrc
        sudo chsh -s /usr/bin/zsh root
    fi
fi

# =============================================================================
# SECTION 19: Final system update
# =============================================================================

info "Running full system update"
sudo pacman -Syu --noconfirm

# ── Cleanup ──────────────────────────────────────────────────────────────────
[[ -n "$REPO_DIR" ]] && rm -rf "$REPO_DIR"

# =============================================================================
# Done
# =============================================================================
echo ""
info "Phase 2 complete!"
echo ""
echo "  Reboot now. In SDDM, select the X11 session (top-left), then log in."
echo ""
echo "  Manual steps remaining after first GUI login:"
echo "    1. Display scaling — verify 125% in System Settings → Display"
echo "    2. KDE Shortcuts — bind Fn+F8 to ~/.local/bin/fn-f8.sh"
echo "                        bind Fn+F9 to ~/.local/bin/fn-f9.sh"
echo "                        bind Fn+F10 to Hibernate (Power Management)"
echo "    3. KDE Effects — disable unneeded effects in Desktop Effects"
echo "    4. KRunner — slim down enabled plugins in System Settings → Search"
echo "    5. System tray — disable unneeded entries"
echo "    6. KDE Services — disable unneeded background services"
echo "    7. autorandr — save your display profile: autorandr --save default"
echo ""
echo "  Optional:"
echo "    - Install Helium Browser: yay -S helium-browser-bin"
echo "    - CachyOS kernel: see README for build instructions"
echo ""
