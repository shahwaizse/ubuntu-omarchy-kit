#!/bin/bash
# ubuntu-omarchy-kit installer — Omarchy-style Hyprland next to GNOME on Ubuntu.
# Safe to re-run. Never edits GNOME's own config. See AGENTS.md for the full playbook.
#
#   ./install.sh                 full install
#   ./install.sh --skip-packages  files only (packages already installed)
#   ./install.sh --check          preflight only, change nothing
#
# Testing with a throwaway HOME? Also set KIT_SANDBOX=1: systemctl --user and gsettings talk to
# your LIVE session (not files under $HOME), so without it a test run changes your real setup.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OL="$HOME/.local/share/omarchy-lite"
STATE="$HOME/.local/state/ubuntu-omarchy-kit"
MANIFEST="$STATE/manifest"
OMARCHY_REF="v3.8.4"           # last Omarchy release with hyprland.conf + Waybar (v4+ needs Lua Hyprland)
DEFAULT_THEME="tokyo-night"

PACKAGES=(
  hyprland xdg-desktop-portal-hyprland hyprlock hypridle hyprpicker hyprpolkitagent
  waybar mako-notifier swaybg swayosd fuzzel rofi ghostty
  grim slurp wl-clipboard brightnessctl playerctl pamixer pavucontrol blueman
  jq ffmpeg webp-pixbuf-loader libnotify-bin curl git python3
)

SKIP_PACKAGES=0; CHECK_ONLY=0
for a in "$@"; do
  case $a in
    --skip-packages) SKIP_PACKAGES=1 ;;
    --check) CHECK_ONLY=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 64 ;;
  esac
done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------ preflight
preflight() {
  [[ $EUID -ne 0 ]] || die "run as your normal user, not root (it installs into your home folder)"
  . /etc/os-release
  [[ ${ID:-} == ubuntu ]] || warn "this kit targets Ubuntu; detected '${ID:-unknown}' — expect differences"
  say "System: ${PRETTY_NAME:-unknown}"

  local hv; hv=$(apt-cache policy hyprland 2>/dev/null | awk '/Candidate:/{print $2}')
  [[ -n $hv && $hv != "(none)" ]] || die "no 'hyprland' package in apt (needs Ubuntu 26.04+ with universe enabled)"
  say "Hyprland in apt: $hv"
  case $hv in
    0.53.*) ;;
    *) warn "configs were tested on Hyprland 0.53.x; $hv may need changes — run ./verify.sh after installing" ;;
  esac

  if lspci 2>/dev/null | grep -qi 'vga.*nvidia\|3d.*nvidia'; then
    warn "NVIDIA GPU detected: Hyprland needs extra setup on NVIDIA (see AGENTS.md → NVIDIA). Continuing."
  fi
  [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] || warn "no graphical session detected; package install will need sudo in a terminal"
}

# ------------------------------------------------------------------ packages
install_packages() {
  local missing=() p
  for p in "${PACKAGES[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if ((${#missing[@]} == 0)); then say "All packages already installed"; return; fi
  say "Installing: ${missing[*]}"
  local cmd=(env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}")
  if sudo -n true 2>/dev/null; then sudo "${cmd[@]}"
  elif [[ -t 0 ]]; then sudo "${cmd[@]}"
  elif [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] && command -v pkexec >/dev/null; then
    say "Asking for your password in a dialog (pkexec)…"; pkexec "${cmd[@]}"
  else
    die "can't ask for a password here. Run this yourself, then re-run with --skip-packages:
    sudo apt-get install -y ${missing[*]}"
  fi
}

# ------------------------------------------------------------------ file install with backups
backup_dir=""
track() { mkdir -p "$STATE"; grep -qxF "$1" "$MANIFEST" 2>/dev/null || echo "$1" >>"$MANIFEST"; }
ours()  { grep -qxF "$1" "$MANIFEST" 2>/dev/null; }

# install_file <src> <dest> [keep]   keep = don't overwrite once it exists (user-editable files)
install_file() {
  local src=$1 dest=$2 keep=${3:-}
  if [[ -e $dest || -L $dest ]]; then
    if ours "$dest"; then
      [[ $keep == keep ]] && return 0
    elif ! cmp -s "$src" "$dest"; then
      [[ -n $backup_dir ]] || { backup_dir="$STATE/backup-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$backup_dir"; }
      mkdir -p "$backup_dir/$(dirname "${dest#"$HOME"/}")"
      mv "$dest" "$backup_dir/${dest#"$HOME"/}"
      warn "backed up existing ${dest/#$HOME/\~} → ${backup_dir/#$HOME/\~}"
    fi
  fi
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
  track "$dest"
}

install_tree() {  # <src-dir> <dest-dir>
  local f
  while IFS= read -r -d '' f; do install_file "$f" "$2/${f#"$1"/}"; done < <(find "$1" -type f -print0)
}

install_files() {
  say "Installing kit files"
  install_tree "$KIT/files/share" "$OL"
  chmod +x "$OL"/bin/*
  local f
  for f in hyprland.conf hypridle.conf hyprlock.conf; do install_file "$KIT/files/config/hypr/$f" "$HOME/.config/hypr/$f"; done
  for f in bindings.conf looknfeel.conf autostart.conf; do install_file "$KIT/files/config/hypr/$f" "$HOME/.config/hypr/$f" keep; done
  install_tree "$KIT/files/config/waybar" "$HOME/.config/waybar"
  install_tree "$KIT/files/config/swayosd" "$HOME/.config/swayosd"
  install_file "$KIT/files/config/autostart/blueman.desktop" "$HOME/.config/autostart/blueman.desktop"
  mkdir -p "$HOME/.local/bin"; ln -sfn "$OL/bin/omarchy-lite-theme-set" "$HOME/.local/bin/omarchy-lite-theme-set"
  track "$HOME/.local/bin/omarchy-lite-theme-set"
}

# ------------------------------------------------------------------ per-machine settings (from GNOME)
gs() { gsettings get "$@" 2>/dev/null | tr -d "'" || true; }

machine_settings() {
  local tmp; tmp=$(mktemp -d)
  # Display scale: GNOME's monitors.xml, else let Hyprland pick
  local scale; scale=$(grep -m1 -oP '(?<=<scale>)[0-9.]+' "$HOME/.config/monitors.xml" 2>/dev/null || true)
  [[ -n $scale ]] || scale=auto
  cat >"$tmp/monitors.conf" <<EOF
# Generated by ubuntu-omarchy-kit from your GNOME display scale ($scale). Edit freely.
# See https://wiki.hypr.land/Configuring/Monitors/
monitor = , preferred, auto, $scale
EOF
  # Keyboard + touchpad: GNOME settings
  local layouts variants opts nat tap
  layouts=$(gs org.gnome.desktop.input-sources sources | grep -oP "\('xkb', '\K[^']+" | cut -d+ -f1 | paste -sd, || true)
  variants=$(gs org.gnome.desktop.input-sources sources | grep -oP "\('xkb', '\K[^']+" | awk -F+ '{print $2}' | paste -sd, || true)
  opts=$(gs org.gnome.desktop.input-sources xkb-options | tr -d '[]@as ' | sed 's/,$//')
  nat=$(gs org.gnome.desktop.peripherals.touchpad natural-scroll); tap=$(gs org.gnome.desktop.peripherals.touchpad tap-to-click)
  [[ -n $layouts ]] || layouts=us
  [[ -n $opts ]] || opts=compose:caps
  cat >"$tmp/input.conf" <<EOF
# Generated by ubuntu-omarchy-kit from your GNOME keyboard/touchpad settings. Edit freely.
input {
  kb_layout = $layouts
  kb_variant = ${variants//[[:space:]]/}
  kb_options = $opts
  touchpad {
    natural_scroll = ${nat:-false}
    tap-to-click = ${tap:-true}
  }
}
EOF
  install_file "$tmp/monitors.conf" "$HOME/.config/hypr/monitors.conf" keep
  install_file "$tmp/input.conf" "$HOME/.config/hypr/input.conf" keep
  rm -rf "$tmp"
  say "Display scale: $scale · keyboard: $layouts · natural scroll: ${nat:-false}"
}

# ------------------------------------------------------------------ fonts
install_font() {
  if fc-list | grep -q 'JetBrainsMono Nerd Font'; then say "JetBrainsMono Nerd Font already installed"; return; fi
  say "Installing JetBrainsMono Nerd Font"
  local tmp; tmp=$(mktemp -d); mkdir -p "$HOME/.local/share/fonts/JetBrainsMonoNerd"
  curl -fsSL -o "$tmp/f.tar.xz" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz
  tar -xJf "$tmp/f.tar.xz" -C "$HOME/.local/share/fonts/JetBrainsMonoNerd" --wildcards '*.ttf'
  fc-cache -f "$HOME/.local/share/fonts" >/dev/null; rm -rf "$tmp"
}

# ------------------------------------------------------------------ themes (downloaded, not redistributed)
install_themes() {
  if [[ -f $OL/themes/.ref ]] && [[ $(<"$OL/themes/.ref") == "$OMARCHY_REF" ]]; then say "Themes already downloaded"; return; fi
  say "Downloading Omarchy $OMARCHY_REF themes and wallpapers (~70 MB)"
  local tmp; tmp=$(mktemp -d)
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$OMARCHY_REF" --filter=blob:none --sparse https://github.com/basecamp/omarchy.git "$tmp/o"
  git -C "$tmp/o" sparse-checkout set themes
  local t name d
  mkdir -p "$OL/themes"
  for t in "$tmp"/o/themes/*/; do
    name=$(basename "$t"); d="$OL/themes/$name"
    rm -rf "$d"; mkdir -p "$d"
    find "$t" -maxdepth 1 -type f \( -name colors.toml -o -name '*.conf' -o -name '*.css' -o -name light.mode \
      -o -name icons.theme -o -name preview.png \) -exec cp {} "$d/" \;
    [[ -d $t/backgrounds ]] && cp -r "$t/backgrounds" "$d/backgrounds"
  done
  echo "$OMARCHY_REF" >"$OL/themes/.ref"
  rm -rf "$tmp"
  track "$OL/themes"
}

# ------------------------------------------------------------------ session-wide services Ubuntu auto-enables
# Ubuntu's packages enable these for EVERY graphical session (GNOME too). Mask them for this user;
# Hyprland starts them itself via exec-once.
fix_services() {
  if [[ -n ${KIT_SANDBOX:-} ]]; then say "KIT_SANDBOX: not masking services (systemctl --user is your live session)"; return; fi
  say "Masking session-wide waybar/mako/hypridle/hyprpolkitagent (Hyprland starts its own)"
  systemctl --user mask waybar.service mako.service hypridle.service hyprpolkitagent.service >/dev/null 2>&1 || true
  echo "masked" >"$STATE/services"
}

# ------------------------------------------------------------------ first theme
first_theme() {
  local cur="$HOME/.config/omarchy/current/theme/name" t=$DEFAULT_THEME
  [[ -f $cur && -d $OL/themes/$(<"$cur") ]] && t=$(<"$cur")
  "$OL/bin/omarchy-lite-theme-set" "$t" </dev/null >/dev/null
  say "Theme: $t"
}

# ------------------------------------------------------------------ remember GNOME-wide settings themes will change
save_gnome_settings() {
  [[ -f $STATE/gnome-orig ]] && return
  local prof; prof=$(gs org.gnome.Ptyxis default-profile-uuid)
  echo "icon_theme=$(gs org.gnome.desktop.interface icon-theme)" >"$STATE/gnome-orig.tmp"
  if [[ -n $prof ]]; then
    echo "ptyxis_profile=$prof" >>"$STATE/gnome-orig.tmp"
    echo "ptyxis_palette=$(gs "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$prof/" palette)" >>"$STATE/gnome-orig.tmp"
  fi
  mv "$STATE/gnome-orig.tmp" "$STATE/gnome-orig"   # only appears once complete
}

# ------------------------------------------------------------------ main
preflight
((CHECK_ONLY)) && { say "Preflight OK (nothing changed)"; exit 0; }
mkdir -p "$STATE"
save_gnome_settings
((SKIP_PACKAGES)) || install_packages
command -v Hyprland >/dev/null || die "Hyprland isn't installed — install packages first"
install_font
install_files
machine_settings
install_themes
fix_services
first_theme

if Hyprland --verify-config -c "$HOME/.config/hypr/hyprland.conf" 2>&1 | grep -q 'config ok'; then
  say "Hyprland config: OK"
else
  Hyprland --verify-config -c "$HOME/.config/hypr/hyprland.conf" 2>&1 | sed -n '/Config parsing result/,$p' >&2
  die "Hyprland rejected the config — see AGENTS.md → Troubleshooting"
fi

cat <<'EOF'

Done. Next:
  1. Log out, click the gear on the login screen, choose "Hyprland" (not "uwsm-managed").
  2. Press Super + K for every shortcut. Super + Space opens apps.
  3. Inside Hyprland, run ./verify.sh --live to check everything is running.
  To undo: ./uninstall.sh
EOF
