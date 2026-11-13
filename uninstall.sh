#!/bin/bash
# ubuntu-omarchy-kit uninstaller: removes the kit's files, restores backups, unmasks services.
# Packages are left installed (the apt remove command is printed at the end).
set -uo pipefail
STATE="$HOME/.local/state/ubuntu-omarchy-kit"; MANIFEST="$STATE/manifest"
[[ -f $MANIFEST ]] || { echo "Nothing to uninstall (no manifest at $MANIFEST)."; exit 0; }

echo "==> Removing installed files"
while IFS= read -r p; do
  [[ $p == "$HOME"/* ]] || continue          # never touch anything outside $HOME
  rm -rf -- "$p"
done <"$MANIFEST"
rm -rf "$HOME/.local/share/omarchy-lite" "$HOME/.config/omarchy"
rmdir "$HOME/.config/hypr" "$HOME/.config/waybar" "$HOME/.config/swayosd" 2>/dev/null || true

latest=$(ls -d "$STATE"/backup-* 2>/dev/null | sort | head -1)   # oldest backup = your original files
if [[ -n $latest ]]; then
  echo "==> Restoring your original files from ${latest/#$HOME/\~}"
  cp -a "$latest"/. "$HOME"/
fi

if [[ -n ${KIT_SANDBOX:-} ]]; then
  echo "==> KIT_SANDBOX: skipping gsettings restore and service unmasking (they act on your live session)"
elif [[ -f $STATE/gnome-orig ]]; then
  echo "==> Restoring GNOME icon theme and Ptyxis palette"
  . "$STATE/gnome-orig"
  [[ -n ${icon_theme:-} ]] && gsettings set org.gnome.desktop.interface icon-theme "$icon_theme"
  [[ -n ${ptyxis_profile:-} && -n ${ptyxis_palette:-} ]] && \
    gsettings set "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$ptyxis_profile/" palette "$ptyxis_palette"
  rm -f "$HOME"/.local/share/org.gnome.Ptyxis/palettes/omarchy-*.palette
fi

if [[ -z ${KIT_SANDBOX:-} ]]; then
  echo "==> Unmasking session services"
  systemctl --user unmask waybar.service mako.service hypridle.service hyprpolkitagent.service >/dev/null 2>&1 || true
fi

mv "$STATE" "$STATE.removed-$(date +%Y%m%d-%H%M%S)"
cat <<'EOF'
Done. The Hyprland session is still on the login screen until you remove the packages:
  sudo apt remove hyprland xdg-desktop-portal-hyprland waybar mako-notifier swaybg swayosd hyprlock hypridle hyprpolkitagent
EOF
