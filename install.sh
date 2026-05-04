#!/bin/bash
set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${CYAN}::${NC} $1"; }
ok()   { echo -e "${GREEN}::${NC} $1"; }
warn() { echo -e "${YELLOW}::${NC} $1"; }
err()  { echo -e "${RED}::${NC} $1"; }

if [[ $EUID -eq 0 ]]; then
    err "Don't run as root. The script uses sudo when needed."
    exit 1
fi

if [[ ! -f /etc/debian_version ]]; then
    err "Debian only."
    exit 1
fi

echo -e "\n${BOLD}Debian Hyprland Installer${NC}\n"

# --- add sid repo for hyprland/hyprlock/hypridle ---
info "Adding unstable repo for Hyprland packages..."
if [[ ! -f /etc/apt/sources.list.d/unstable.list ]]; then
    echo "deb http://deb.debian.org/debian/ unstable main" | sudo tee /etc/apt/sources.list.d/unstable.list > /dev/null
fi
if [[ ! -f /etc/apt/preferences.d/99-default-stable ]]; then
    cat << 'EOF' | sudo tee /etc/apt/preferences.d/99-default-stable > /dev/null
Package: *
Pin: release a=stable
Pin-Priority: 700

Package: *
Pin: release a=unstable
Pin-Priority: 100
EOF
fi
ok "Unstable repo configured (pinned low priority)"

# --- packages ---
info "Updating package lists..."
sudo apt-get update -y

info "Installing core packages..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git build-essential cmake pkg-config gcc \
    curl wget \
    bluez \
    waybar wofi mako-notifier \
    cliphist \
    polkit-kde-agent-1 \
    grim slurp wl-clipboard \
    kitty thunar \
    pipewire pipewire-pulse wireplumber pipewire-alsa pipewire-jack \
    network-manager-gnome blueman pavucontrol \
    playerctl brightnessctl \
    power-profiles-daemon \
    mpv btop \
    fonts-jetbrains-mono fonts-font-awesome \
    rsync wlr-randr \
    libqt5quickcontrols2-5 libqt5svg5 \
    greetd tuigreet \
    zathura zathura-pdf-poppler pandoc \
    texlive-latex-base texlive-latex-extra texlive-fonts-recommended \
    wlogout

# hyprland + hyprlock + hypridle from sid
info "Installing Hyprland from unstable..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -t unstable \
    hyprland hyprlock hypridle

# Try to install xdg-desktop-portal-hyprland, but don't fail if dependencies conflict
info "Attempting to install xdg-desktop-portal-hyprland..."
if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -t unstable xdg-desktop-portal-hyprland 2>/dev/null; then
    ok "xdg-desktop-portal-hyprland installed"
else
    warn "xdg-desktop-portal-hyprland has dependency conflicts, installing fallback..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    ok "Using xdg-desktop-portal-wlr as fallback"
fi

ok "Packages installed"

# --- install Discord ---
if ! command -v discord &>/dev/null; then
    info "Installing Discord..."
    tmpdir=$(mktemp -d)
    curl -fsSL -o "$tmpdir/discord.deb" \
        "https://discord.com/api/download?platform=linux&format=deb" || {
        warn "Could not download Discord .deb"
        warn "Skipping Discord install"
        tmpdir=""
    }
    if [[ -n "$tmpdir" && -f "$tmpdir/discord.deb" ]]; then
        sudo dpkg -i "$tmpdir/discord.deb" || sudo apt-get install -f -y
        rm -rf "$tmpdir"
        ok "Discord installed"
    fi
else
    ok "Discord already installed"
fi

# --- install JetBrains Mono Nerd Font (not in debian repos) ---
if [[ ! -d /usr/share/fonts/JetBrainsMonoNerd ]]; then
    info "Installing JetBrains Mono Nerd Font..."
    tmpdir=$(mktemp -d)
    curl -fsSL -o "$tmpdir/jbmono.tar.xz" \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
    sudo mkdir -p /usr/share/fonts/JetBrainsMonoNerd
    sudo tar -xf "$tmpdir/jbmono.tar.xz" -C /usr/share/fonts/JetBrainsMonoNerd
    sudo fc-cache -f
    rm -rf "$tmpdir"
    ok "Nerd Font installed"
fi

# --- build avizo from source (not in debian) ---
if ! command -v avizo-service &>/dev/null; then
    info "Building avizo from source..."
    # Install build dependencies from unstable to match upgraded libraries
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -t unstable \
        meson ninja-build libgtk-layer-shell-dev libgtk-3-dev libdbus-1-dev
    tmpdir=$(mktemp -d)
    git clone https://github.com/misterdanb/avizo.git "$tmpdir/avizo"
    cd "$tmpdir/avizo"
    meson setup build
    ninja -C build
    sudo ninja -C build install
    cd -
    rm -rf "$tmpdir"
    ok "avizo installed"
else
    ok "avizo already installed"
fi

# --- install helium browser ---
if ! command -v helium &>/dev/null; then
    info "Installing Helium browser..."
    tmpdir=$(mktemp -d)
    curl -fsSL -o "$tmpdir/helium.deb" \
        "https://browser.nickvision.org/linux/helium-browser_current_amd64.deb" || {
        warn "Could not download Helium .deb — check https://browser.nickvision.org for the current URL"
        warn "Skipping Helium install"
        tmpdir=""
    }
    if [[ -n "$tmpdir" && -f "$tmpdir/helium.deb" ]]; then
        sudo dpkg -i "$tmpdir/helium.deb" || sudo apt-get install -f -y
        rm -rf "$tmpdir"
        ok "Helium browser installed"
    fi
else
    ok "Helium browser already installed"
fi

# --- config directories ---
info "Writing configs..."
mkdir -p ~/.config/{hypr,waybar,wofi,kitty,wallpapers,avizo}
touch ~/.config/hypr/monitors.conf
sudo mkdir -p /usr/share/backgrounds

if [[ ! -f ~/.config/wallpapers/current_wallpaper.jpg ]]; then
    info "Downloading wallpaper..."
    curl -fsSL -o ~/.config/wallpapers/current_wallpaper.jpg \
        "https://raw.githubusercontent.com/willuhmjs/archconfig/main/roles/workstation/files/placeholder_wallpaper.jpg"
    ok "Wallpaper downloaded"
fi

# --- hyprland.conf ---
cat > ~/.config/hypr/hyprland.conf << 'HYPREOF'
monitor=,preferred,auto,1.0
source = ~/.config/hypr/monitors.conf

env = XDG_SESSION_TYPE,wayland
env = ELECTRON_OZONE_PLATFORM_HINT,auto
env = GTK_THEME,adw-gtk3-dark

exec = gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
exec = gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'

input {
    kb_layout = us
}

general {
    gaps_in = 6
    gaps_out = 12
    border_size = 2
    col.active_border = rgba(555555aa) rgba(888888aa) 45deg
    col.inactive_border = rgba(222222aa)
    resize_on_border = true
    hover_icon_on_border = true
}

decoration {
    rounding = 12
    blur {
        enabled = true
        size = 12
        passes = 4
        new_optimizations = true
        ignore_opacity = true
        xray = true
    }
    shadow {
        enabled = true
        range = 20
        render_power = 3
        color = rgba(00000088)
    }
}

misc {
    vfr = true
}

animations {
    enabled = true
    bezier = overshot, 0.05, 0.9, 0.1, 1.05
    bezier = smoothOut, 0.36, 0, 0.66, -0.56
    bezier = smoothIn, 0.25, 1, 0.5, 1
    animation = windows, 1, 5, overshot, slide
    animation = windowsOut, 1, 4, smoothOut, slide
    animation = windowsMove, 1, 4, default
    animation = border, 1, 10, default
    animation = fade, 1, 10, smoothIn
    animation = fadeDim, 1, 10, smoothIn
    animation = workspaces, 1, 6, default
}

plugin {
    hyprwobbly { enabled = true; stiffness = 150; damping = 15 }
}

bindm = SUPER, mouse:272, movewindow
bindm = SUPER, mouse:273, resizewindow

bind = SUPER, RETURN, exec, kitty
bind = SUPER, Q, killactive,
bind = SUPER, SPACE, exec, wofi --show drun
bind = SUPER, E, exec, thunar
bind = SUPER, B, exec, helium
bind = SUPER, D, exec, discord
bind = SUPER, F, fullscreen,
bind = SUPER, V, togglefloating,
bind = SUPER SHIFT, S, exec, grim -g "$(slurp)" - | wl-copy
bind = SUPER, L, exec, hyprlock
bind = SUPER, C, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy
bind = SUPER, ESCAPE, exec, wlogout

bind = SUPER, 1, workspace, 1
bind = SUPER, 2, workspace, 2
bind = SUPER, 3, workspace, 3
bind = SUPER, 4, workspace, 4
bind = SUPER, 5, workspace, 5
bind = SUPER, 6, workspace, 6
bind = SUPER, 7, workspace, 7
bind = SUPER, 8, workspace, 8
bind = SUPER, 9, workspace, 9
bind = SUPER, 0, workspace, 10

bind = SUPER SHIFT, 1, movetoworkspace, 1
bind = SUPER SHIFT, 2, movetoworkspace, 2
bind = SUPER SHIFT, 3, movetoworkspace, 3
bind = SUPER SHIFT, 4, movetoworkspace, 4
bind = SUPER SHIFT, 5, movetoworkspace, 5
bind = SUPER SHIFT, 6, movetoworkspace, 6
bind = SUPER SHIFT, 7, movetoworkspace, 7
bind = SUPER SHIFT, 8, movetoworkspace, 8
bind = SUPER SHIFT, 9, movetoworkspace, 9
bind = SUPER SHIFT, 0, movetoworkspace, 10

bind = SUPER, left, movefocus, l
bind = SUPER, right, movefocus, r
bind = SUPER, up, movefocus, u
bind = SUPER, down, movefocus, d

bind = SUPER SHIFT, left, movewindow, l
bind = SUPER SHIFT, right, movewindow, r
bind = SUPER SHIFT, up, movewindow, u
bind = SUPER SHIFT, down, movewindow, d

bindle = , XF86AudioRaiseVolume, exec, volumectl -u up
bindle = , XF86AudioLowerVolume, exec, volumectl -u down
bindl = , XF86AudioMute, exec, volumectl toggle
bindl = , XF86AudioPlay, exec, volumectl -m toggle
bindl = , XF86AudioPause, exec, volumectl -m toggle
bindl = , XF86AudioMicMute, exec, volumectl -m toggle
bindle = , XF86MonBrightnessUp, exec, lightctl up
bindle = , XF86MonBrightnessDown, exec, lightctl down

exec-once = awww-daemon & sleep 1 && awww img ~/.config/wallpapers/current_wallpaper.jpg --transition-type simple
exec-once = waybar
exec-once = nm-applet --indicator
exec-once = avizo-service
exec-once = mako
exec-once = /usr/lib/polkit-kde-authentication-agent-1
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store
exec-once = hypridle
exec-once = discord

layerrule {
    name = avizo-layer-blur
    match:namespace = ^(avizo)$
    blur = true
}

windowrule {
    name = avizo-rules
    match:class = ^(avizo)$
    opacity = 0.90 0.90
}

windowrule {
    name = kitty-rules
    match:class = ^(kitty)$
    opacity = 0.90 0.90
}

windowrule {
    name = thunar-rules
    match:class = ^([Tt]hunar)$
    opacity = 0.90 0.90
}

windowrule {
    name = discord-workspace
    match:class = ^([Dd]iscord)$
    workspace = 3
}

windowrule {
    name = webcord-workspace
    match:class = ^([Ww]eb[Cc]ord)$
    workspace = 3
}

windowrule {
    name = vesktop-workspace
    match:class = ^([Vv]esktop)$
    workspace = 3
}
HYPREOF

# --- hyprlock.conf ---
cat > ~/.config/hypr/hyprlock.conf << 'EOF'
background {
    monitor =
    path = ~/.config/wallpapers/current_wallpaper.jpg
    blur_passes = 2
    contrast = 1
    brightness = 0.5
    vibrancy = 0.2
    vibrancy_darkness = 0.2
}

input-field {
    monitor =
    size = 250, 60
    outline_thickness = 2
    dots_size = 0.2
    dots_spacing = 0.35
    dots_center = true
    outer_color = rgba(0, 0, 0, 0)
    inner_color = rgba(0, 0, 0, 0.2)
    font_color = rgba(255, 255, 255, 1)
    fade_on_empty = false
    rounding = -1
    check_color = rgb(204, 136, 34)
    placeholder_text = <i><span foreground="##cdd6f4">Input Password...</span></i>
    hide_input = false
    position = 0, -200
    halign = center
    valign = center
}

label {
    monitor =
    text = cmd[update:1000] echo "$(date +"%H:%M")"
    color = rgba(255, 255, 255, 1)
    font_size = 90
    font_family = JetBrains Mono Nerd Font
    position = 0, 100
    halign = center
    valign = center
}
EOF

# --- hypridle.conf ---
cat > ~/.config/hypr/hypridle.conf << 'EOF'
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch dpms on
}

listener {
    timeout = 150
    on-timeout = brightnessctl set 10%
    on-resume = brightnessctl set 100%
}

listener {
    timeout = 150
    on-timeout = brightnessctl -sd rgb:kbd_backlight set 0
    on-resume = brightnessctl -rd rgb:kbd_backlight
}

listener {
    timeout = 300
    on-timeout = loginctl lock-session
}

listener {
    timeout = 330
    on-timeout = hyprctl dispatch dpms off
    on-resume = hyprctl dispatch dpms on
}

listener {
    timeout = 1800
    on-timeout = systemctl suspend
}
EOF

# --- waybar ---
cat > ~/.config/waybar/config << 'EOF'
{
    "reload_style_on_change": true,
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 8,
    "modules-left": ["hyprland/workspaces", "hyprland/window"],
    "modules-center": ["clock"],
    "modules-right": ["cpu", "memory", "temperature", "network", "pulseaudio", "battery", "tray", "group/settings", "power-profiles-daemon"],
    "group/settings": {
        "orientation": "inherit",
        "drawer": {
            "transition-duration": 500,
            "children-class": "settings-drawer",
            "transition-left-to-right": false
        },
        "modules": [
            "custom/settings-icon",
            "custom/nwg-displays",
            "custom/nwg-look",
            "custom/network",
            "custom/bluetooth",
            "custom/audio"
        ]
    },
    "custom/settings-icon": { "format": "", "tooltip": false },
    "custom/nwg-displays": { "format": "󰍹", "on-click": "nwg-displays", "tooltip-format": "Display Settings" },
    "custom/nwg-look": { "format": "󰏘", "on-click": "nwg-look", "tooltip-format": "Appearance Settings" },
    "custom/network": { "format": "󰤨", "on-click": "nm-connection-editor", "tooltip-format": "Network Settings" },
    "custom/bluetooth": { "format": "󰂯", "on-click": "blueman-manager", "tooltip-format": "Bluetooth Settings" },
    "custom/audio": { "format": "󰕾", "on-click": "pavucontrol", "tooltip-format": "Audio Settings" },
    "hyprland/workspaces": { "format": "{name}", "disable-scroll": true, "all-outputs": true },
    "hyprland/window": { "format": "{title}", "max-length": 40 },
    "clock": { "format": "  {:%H:%M  |    %A, %b %d}", "tooltip-format": "<tt><small>{calendar}</small></tt>" },
    "cpu": { "format": "  {usage}%", "tooltip": false },
    "memory": { "format": "  {}%" },
    "temperature": { "critical-threshold": 80, "format": "{icon} {temperatureC}°C", "format-icons": ["", "", ""] },
    "network": { "format-wifi": "  {essid} ({signalStrength}%)", "format-ethernet": "󰈀  {ipaddr}", "format-disconnected": "⚠  Offline", "tooltip-format": "{ifname} via {gwaddr}", "on-click": "nm-connection-editor" },
    "pulseaudio": { "format": "{icon}  {volume}%", "format-muted": "  Muted", "format-icons": { "default": ["", "", ""] }, "on-click": "pavucontrol" },
    "battery": { "states": { "warning": 30, "critical": 15 }, "format": "{icon}  {capacity}%", "format-charging": "  {capacity}%", "format-plugged": "  {capacity}%", "format-icons": ["", "", "", "", ""] },
    "tray": { "icon-size": 16, "spacing": 10 },
    "power-profiles-daemon": { "format": "{icon}", "tooltip-format": "Power profile: {profile}", "format-icons": { "default": "", "performance": "", "balanced": "", "power-saver": "" } }
}
EOF

cat > ~/.config/waybar/style.css << 'EOF'
* {
    border: none;
    border-radius: 0;
    font-family: "JetBrainsMono Nerd Font", "Font Awesome 6 Free";
    font-size: 13px;
    font-weight: 600;
}

window#waybar {
    background-color: rgba(15, 15, 15, 0.90);
    border-bottom: 1px solid rgba(255, 255, 255, 0.05);
    color: #cdd6f4;
}

#workspaces button {
    padding: 0 12px;
    color: #6c7086;
    background: transparent;
}

#workspaces button.active {
    color: #ffffff;
    border-bottom: 2px solid #ffffff;
}

#window {
    color: #a6adc8;
    padding-left: 15px;
}

#clock { color: #ffffff; }

#cpu, #memory, #temperature, #network, #pulseaudio, #battery, #tray, #power-profiles-daemon {
    padding: 0 12px;
    color: #bac2de;
}

#custom-settings-icon, #custom-nwg-displays, #custom-nwg-look,
#custom-network, #custom-bluetooth, #custom-audio {
    padding: 0 8px;
    color: #bac2de;
    background-color: transparent;
    transition: all 0.3s ease;
}

#custom-settings-icon:hover, #custom-nwg-displays:hover, #custom-nwg-look:hover,
#custom-network:hover, #custom-bluetooth:hover, #custom-audio:hover {
    color: #89b4fa;
}

#battery.warning { color: #f9e2af; }
#battery.critical { color: #f38ba8; }
#temperature.critical { color: #f38ba8; }
EOF

# --- wofi ---
cat > ~/.config/wofi/config << 'EOF'
show=drun
width=600
height=400
prompt=Search
normal_window=false
layer=overlay
hide_scroll=true
allow_images=true
image_size=32
term=kitty
exec_search=true
EOF

cat > ~/.config/wofi/style.css << 'EOF'
window {
    background-color: rgba(30, 30, 46, 0.85);
    border-radius: 12px;
    border: 1px solid rgba(255, 255, 255, 0.1);
}

#input {
    background-color: rgba(255, 255, 255, 0.05);
    border: none;
    border-radius: 8px;
    margin: 10px;
    padding: 10px;
    color: #cdd6f4;
    font-family: "JetBrainsMono Nerd Font";
    font-size: 16px;
}

#inner-box { margin: 10px; }
#outer-box { margin: 5px; }
#scroll { margin: 5px; border: none; }

#entry {
    padding: 10px;
    border-radius: 8px;
    color: #a6adc8;
}

#entry image { margin-right: 12px; }

#entry:selected {
    background-color: rgba(137, 180, 250, 0.3);
    border-radius: 8px;
    color: #ffffff;
}
EOF

# --- kitty ---
cat > ~/.config/kitty/kitty.conf << 'EOF'
font_family      JetBrainsMono Nerd Font
font_size        11.0
bold_font        auto
italic_font      auto
bold_italic_font auto
background_opacity 0.60
background_blur 32
foreground #c0caf5
background #1a1b26
confirm_os_window_close 0
window_padding_width 8
term xterm-256color
EOF

# --- avizo ---
cat > ~/.config/avizo/config.ini << 'EOF'
[default]
time = 2.0
y-offset = 0.85
padding = 16
width = 220
height = 200
border-radius = 20
block-height = 8
block-spacing = 0
block-count = 100
EOF

cat > ~/.config/avizo/style.css << 'EOF'
#avizo {
  background: rgba(26, 27, 38, 0.60);
  border-radius: 20px;
  border: 1px solid rgba(255, 255, 255, 0.1);
  box-shadow: 0px 8px 30px rgba(0, 0, 0, 0.5);
}

#avizo image {
  opacity: 1.0;
  color: #c0caf5;
}

#avizo progress {
  border-radius: 8px;
  background: rgba(192, 202, 245, 0.95);
}

#avizo progress trough {
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.15);
}
EOF

ok "Configs written"

# --- system config ---
info "Configuring system..."

sudo mkdir -p /etc/greetd
cat << 'EOF' | sudo tee /etc/greetd/config.toml > /dev/null
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-user-session --asterisks --cmd 'Hyprland'"
user = "greeter"
EOF

sudo systemctl disable sddm gdm lightdm 2>/dev/null || true
sudo rm -f /etc/systemd/system/display-manager.service

for svc in bluetooth power-profiles-daemon NetworkManager; do
    sudo systemctl enable --now "$svc" 2>/dev/null || true
done
sudo systemctl enable greetd 2>/dev/null || true

ok "System configured"

echo ""
ok "Done. Reboot and greetd will start Hyprland."
echo -e "   SUPER+RETURN  terminal"
echo -e "   SUPER+SPACE   launcher"
echo -e "   SUPER+B       helium browser"
echo -e "   SUPER+Q       close window"
echo -e "   SUPER+L       lock"
echo ""
