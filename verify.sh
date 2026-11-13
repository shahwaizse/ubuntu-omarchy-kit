#!/bin/bash
# ubuntu-omarchy-kit verification. Exit code = number of failed checks.
#   ./verify.sh          static checks (work from GNOME or a TTY)
#   ./verify.sh --live   + checks that need a running Hyprland session
#   ./verify.sh --live --freeze-test   + the GTK4 workspace-freeze regression test (flips workspaces 9/8)
set -uo pipefail
OL="$HOME/.local/share/omarchy-lite"; CUR="$HOME/.config/omarchy/current"
LIVE=0; FREEZE=0
for a in "$@"; do case $a in --live) LIVE=1 ;; --freeze-test) LIVE=1; FREEZE=1 ;; esac; done

fails=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; fails=$((fails + 1)); }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

echo "Static checks"
check "Hyprland accepts the config" bash -c "Hyprland --verify-config -c '$HOME/.config/hypr/hyprland.conf' 2>&1 | grep -q 'config ok'"
for f in "$OL"/bin/*; do
  case $f in *-wake) check "python syntax: ${f##*/}" python3 -I -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" ;;
             *)      check "bash syntax: ${f##*/}" bash -n "$f" ;; esac
done
check "Waybar config is valid JSON" python3 -I -c "
import json,re,sys; s=open(sys.argv[1]).read(); json.loads(re.sub(r'^\s*//.*$','',s,flags=re.M))" "$HOME/.config/waybar/config.jsonc"
# Nerd Font glyphs live in Unicode private-use areas; copying them as text has silently blanked them before.
check "Waybar icons are present (not blank strings)" python3 -I -c "
import json,re,sys
c=json.loads(re.sub(r'^\s*//.*\$','',open(sys.argv[1]).read(),flags=re.M))
need={'bluetooth':'format','custom/logo':'format','custom/expand-icon':'format','battery':'format-plugged','pulseaudio':'format-muted'}
sys.exit(any(not c[m][k].strip() for m,k in need.items()) or any(not i.strip() for i in c['pulseaudio']['format-icons']['default']))" "$HOME/.config/waybar/config.jsonc"
check "JetBrainsMono Nerd Font installed" bash -c "fc-list | grep -q 'JetBrainsMono Nerd Font'"
check "Themes downloaded (≥15 with colors)" bash -c "[ \$(ls '$OL'/themes/*/colors.toml 2>/dev/null | wc -l) -ge 15 ]"
check "Every theme has wallpapers" bash -c "for d in '$OL'/themes/*/; do ls \"\$d\"backgrounds/* >/dev/null 2>&1 || exit 1; done"
check "Current theme generated, no unfilled {{ }}" bash -c "[ -f '$CUR/theme/name' ] && ! grep -lI '{{' '$CUR'/theme/* 2>/dev/null | grep -q ."
check "Wallpaper link resolves" test -f "$CUR/background"
for s in waybar mako hypridle hyprpolkitagent; do
  check "$s.service masked for this user (won't start in GNOME)" bash -c "[ \"\$(systemctl --user is-enabled $s.service 2>/dev/null)\" = masked ]"
done
check "Blueman tray applet hidden from other sessions" grep -q '^Hidden=true' "$HOME/.config/autostart/blueman.desktop"
check "Session XDG_CURRENT_DESKTOP is plain Hyprland in config" grep -qx 'env = XDG_CURRENT_DESKTOP,Hyprland' "$OL/default/hypr/envs.conf"

if ((LIVE)); then
  echo "Live checks (Hyprland session)"
  if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then bad "not running inside Hyprland — log into the Hyprland session and re-run"; exit $fails; fi
  for p in waybar mako swaybg swayosd-server hypridle hyprpolkitagent; do check "$p running" pgrep -x "$p"; done
  check "workspace-freeze helper running" pgrep -f omarchy-lite-wake
  check "OSD server reachable on D-Bus (volume/brightness keys)" busctl --user status org.erikreider.swayosd-server
  check "xdg-desktop-portal-hyprland running" pgrep -f xdg-desktop-portal-hyprland
  check "systemd session env has XDG_CURRENT_DESKTOP=Hyprland" bash -c "systemctl --user show-environment | grep -qx 'XDG_CURRENT_DESKTOP=Hyprland'"
  check "GNOME Keyring secrets service available" busctl --user status org.freedesktop.secrets
  dev=$(ls /sys/class/backlight 2>/dev/null | head -1)
  if [[ -n $dev ]]; then
    check "brightness writable via logind" busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto \
      org.freedesktop.login1.Session SetBrightness ssu backlight "$dev" "$(<"/sys/class/backlight/$dev/brightness")"
  fi
fi

if ((FREEZE)); then
  echo "Freeze regression test (watch: workspaces 9/8 will flip for ~20s)"
  tmp=$(mktemp -d); back=$(hyprctl activeworkspace -j | jq -r .id)
  hyprctl dispatch workspace 9 >/dev/null; sleep 0.3
  setsid -f ghostty --class=kit.freeze.test -e bash -c 'while :; do date +%T.%N; sleep 0.1; done' >/dev/null 2>&1
  sleep 2
  read -r x y w h < <(hyprctl clients -j | jq -r '[.[]|select(.class=="kit.freeze.test")][0]|"\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"')
  frozen=0
  for r in $(seq 10); do
    hyprctl dispatch workspace 8 >/dev/null; sleep 0.8; hyprctl dispatch workspace 9 >/dev/null; sleep 0.6
    grim -g "$x,$y ${w}x$h" "$tmp/a.png"; sleep 0.7; grim -g "$x,$y ${w}x$h" "$tmp/b.png"
    cmp -s "$tmp/a.png" "$tmp/b.png" && frozen=$((frozen + 1))
  done
  hyprctl clients -j | jq -r '.[]|select(.class=="kit.freeze.test")|.address' | while read -r a; do hyprctl dispatch closewindow "address:$a" >/dev/null; done
  hyprctl dispatch workspace "$back" >/dev/null; rm -rf "$tmp"
  ((frozen == 0)) && ok "terminal kept redrawing through 10 workspace round trips" || bad "terminal froze in $frozen/10 round trips"
fi

echo; ((fails == 0)) && echo "All checks passed." || echo "$fails check(s) failed — see AGENTS.md → Troubleshooting."
exit $fails
