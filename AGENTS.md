# AGENTS.md — playbook for setting up ubuntu-omarchy-kit

You are an agent asked to give this user an Omarchy-style Hyprland desktop on Ubuntu. This file is everything you need to do it in one pass. Every item in **Pitfalls** was a real bug hit while building this kit. Read the whole file before acting.

## What this kit is

- A Hyprland session that sits **next to** GNOME. It is a separate choice on the login screen. GNOME keeps working, and the user can switch back at any time.
- The look, layout, keybindings and 19 themes come from [Omarchy](https://github.com/basecamp/omarchy) **v3.8.4**, adapted to the tools Ubuntu packages. This kit is unofficial and not affiliated with Omarchy or Basecamp.
- Everything lives in the user's home folder:

| Path | What | Who edits it |
|---|---|---|
| `~/.local/share/omarchy-lite/` | defaults, scripts (`bin/`), theme templates (`themed/`), themes | the kit (overwritten on reinstall) |
| `~/.config/hypr/hyprland.conf`, `hypridle.conf`, `hyprlock.conf` | entry points | the kit |
| `~/.config/hypr/{bindings,monitors,input,looknfeel,autostart}.conf` | the user's own layer | the user (the installer only creates them if they're missing) |
| `~/.config/omarchy/current/` | the generated current theme + `background` link | `omarchy-lite-theme-set` |
| `~/.local/state/ubuntu-omarchy-kit/` | manifest, backups, original GNOME settings | the installer |

## The procedure

1. **Talk to the user first.** Confirm they want a Hyprland session alongside GNOME. Tell them three things up front:
   - Packages need their password. The installer opens a graphical prompt if it can't ask in the terminal.
   - Trying the session means logging out, so they should save their work.
   - Anything the kit would overwrite gets backed up, and `./uninstall.sh` undoes everything.
2. **Preflight:** run `./install.sh --check`. It changes nothing. Stop and tell the user if:
   - **There's no `hyprland` package.** That means they're on an Ubuntu older than 26.04, or the universe repository is disabled.
   - **The Hyprland version isn't 0.53.x.** Read **Hyprland versions** below before continuing.
   - **They have an NVIDIA GPU.** Read **NVIDIA** below.
3. **Look for existing setups.** Check whether `~/.config/hypr`, `~/.config/waybar`, `~/.config/mako` or `~/.config/swayosd` already exist. Tell the user they'll be backed up to `~/.local/state/ubuntu-omarchy-kit/backup-*`. If they have another compositor or shell installed (niri, sway, DankMaterialShell, Quickshell…), that's fine; these files don't conflict with them.
4. **Install:** run `./install.sh`. If a password prompt can't be shown (no terminal and no graphical session), it prints the exact `sudo apt-get install …` command. Ask the user to run it themselves (in Claude Code they can type `! <command>`), then run `./install.sh --skip-packages`.
5. **Verify statically:** run `./verify.sh`. Every check must pass. Fix any failures before going on.
6. **Hand over to the user.** Ask them to log out and pick **Hyprland** on the login screen (gear icon), **not "Hyprland (uwsm-managed)"**. Then, from inside the session:
   - run `./verify.sh --live`;
   - optionally run `./verify.sh --freeze-test`. It flips workspaces 9 and 8 for about 20 seconds, so warn them first.
7. **Personalise:** offer to edit `~/.config/hypr/bindings.conf` for their apps (web apps, editor), and `monitors.conf` if they have several displays. These files belong to the user, so edit them rather than the defaults.

The installer reads three things from GNOME so the session feels the same:
- **Display scale**, from `~/.config/monitors.xml`.
- **Keyboard layout and options**, from `org.gnome.desktop.input-sources`.
- **Touchpad natural scroll and tap-to-click**, from `org.gnome.desktop.peripherals.touchpad`.

Check the generated `~/.config/hypr/monitors.conf` and `input.conf` match what the user expects.

## Pitfalls (each one bit us; don't reintroduce them)

**Versions and packaging**
- **Current Omarchy (v4+) can't run on Ubuntu's Hyprland 0.53.** Omarchy v4 moved its Hyprland config to Lua and replaced Waybar with a Quickshell shell, and 0.53 can't read Lua configs. That's why this kit is based on v3.8.4, the last release with `hyprland.conf` and Waybar. Don't "upgrade" to Omarchy main.
- **Hyprland 0.53 has no `scrolling` layout options.** Omarchy's `scrolling { column_width }` is rejected; it's already removed here. After any config edit, run `Hyprland --verify-config -c ~/.config/hypr/hyprland.conf`.
- **`hyprland-guiutils` isn't packaged on Ubuntu.** It only provides a few Hyprland dialogs. `misc:disable_hyprland_guiutils_check = true` silences the warning.
- **Walker (Omarchy's launcher) isn't packaged.** The kit uses **fuzzel** for the launcher, power menu and keybinding list, and **rofi 2.0** for the image pickers. Fuzzel can't show images.

**Services Ubuntu turns on for every session**
- **Installing `waybar`, `mako-notifier`, `hypridle` and `hyprpolkitagent` enables user services for every graphical session**, GNOME and niri included. Under GNOME that meant Hyprland's idle locker locking GNOME, and duplicate notification and password daemons. The installer runs `systemctl --user mask` on all four, and Hyprland starts its own copies via `exec-once`. **Never unmask them while the kit is installed.**
- **Blueman's tray applet autostarts in every session too.** `~/.config/autostart/blueman.desktop` with `Hidden=true` turns it off.

**Desktop name and portals**
- **Keep `XDG_CURRENT_DESKTOP` exactly `Hyprland` for the session.**
  - The problem: Chromium and Electron apps (Chrome, VS Code, Slack, Claude desktop) only use GNOME Keyring when they see `GNOME` in that name. Otherwise they show "no system keyring" and lose saved logins.
  - **The tempting fix breaks the session.** Setting `Hyprland:GNOME` session-wide made xdg-desktop-portal try GNOME's backend, and xdg-desktop-portal-hyprland logged "Not running on hyprland" and crashed. The result was **no bar and app windows that never appeared**. Silencing Hyprland's warning about it (`misc:disable_xdg_env_checks`) hides the symptom, so don't.
  - **The kit's fix is scoped to app launches.** Only apps started from the launcher get the extra name (`fuzzel --launch-prefix="env XDG_CURRENT_DESKTOP=Hyprland:GNOME"`, plus the `$browser`/`$webapp` binds). Apps started from a terminal don't get it.
- **Qt apps ignore GNOME's dark mode under Hyprland.** The polkit password dialog was a bright white box. `QT_QPA_PLATFORMTHEME=gtk3` makes Qt follow the GTK theme.

**Hardware keys**
- **Brightness needs logind.** Normal users can't write to `/sys/class/backlight`, so `brightnessctl` and `swayosd --brightness` both fail without root. `omarchy-lite-brightness` calls logind's `Session.SetBrightness` over D-Bus (what GNOME does), then shows the OSD with `--custom-progress`. Don't "fix" this with udev rules or the video group.
- **The swayosd server can end up running but unreachable.** If a new `swayosd-server` starts before the old one has exited, the new one never claims `org.erikreider.swayosd-server`. Every volume key then fails with "Could not connect to SwayOSD Server". `restart_osd` in `omarchy-lite-lib` waits for the old process to exit, checks the D-Bus name, and retries.
- **swayosd spells it `--playerctl prev`**, not `previous`.

**Rendering**
- **GTK4 windows freeze after switching workspaces (Hyprland 0.53 bug).** This affects Ghostty, Ptyxis and other GTK4 apps.
  - Symptom: the border shows the window as focused, but it doesn't redraw. Typing arrives but isn't shown, and Super + F (a resize) suddenly shows it.
  - Cause: 0.53 sends each toplevel state change immediately as its own configure. On return to a workspace a stale `suspended` state can arrive last, and the app stops requesting frames.
  - Fixed upstream by [Hyprland PR #14227](https://github.com/hyprwm/Hyprland/pull/14227) (0.55.0).
  - Workaround here: `omarchy-lite-wake` listens on Hyprland's event socket and re-focuses the active window after each workspace switch. Without it about 1 in 3 switches froze; with it, 0 in 12. It only wakes the focused window.
  - Ruled out: `misc:vfr`, workspace animations and `debug:damage_tracking` don't help.
- **The `.webp` wallpapers need `webp-pixbuf-loader`**, for swaybg and for rofi's thumbnails.

**Writing scripts and configs**
- **Never paste Nerd Font icons as literal text.** They live in Unicode's private-use areas and were silently saved as **empty strings**, which left invisible Bluetooth and volume icons and blank menu icons. Write them with escapes (`""`, `"\U000f00b2"`). `verify.sh` checks the bar icons aren't blank.
- **Don't let background programs inherit a lock.**
  - The bug: the live theme preview took a `flock`, and the theme switch restarted `swaybg` and `swayosd-server` while holding it. Those long-lived daemons inherited the lock, it was never released, and about 25 previews piled up waiting. rofi also hung, because it waits for the processes it spawned, and those held its output pipe.
  - The fix, in `apply_theme`: run `theme-set` with `9>&-` (the lock closed), apply only the latest selection, and redirect the hooks' stdio.
- **Watch for `set -e` in scripts.** A function or `{ … }` group whose last command is `[[ cond ]] && cmd` returns failure when `cond` is false, and `set -e` then quietly exits the script. This hit `install.sh` for users without Ptyxis. Use `if … fi`.
- **`pkill -f <pattern>` can kill your own shell**, because your command line contains the pattern. Match on `/proc/<pid>/cmdline` of the target process name instead (`pgrep -x name`).
- **Under zsh, `$VAR` with spaces isn't word-split.** Use bash or arrays for things like `grim -g "$geo"`.

**Testing**
- **A throwaway `HOME` doesn't isolate `systemctl --user` or `gsettings`.** Both act on the live session. Testing the uninstaller with a fake `HOME` once unmasked the real services and reset the real icon theme. Always set `KIT_SANDBOX=1` for sandbox runs:
  `env -u HYPRLAND_INSTANCE_SIGNATURE HOME=/tmp/kit-test KIT_SANDBOX=1 ./install.sh --skip-packages`
- **Also unset `HYPRLAND_INSTANCE_SIGNATURE` when testing inside a running Hyprland.** Otherwise `theme-set` reloads the live desktop.
- **Don't test Hyprland nested inside GNOME.** Its autostart runs `dbus-update-activation-environment`, which overwrites GNOME's session environment.

**Effects on GNOME**
- **The icon set and Ptyxis palette are GNOME-wide settings.**
  - Themes set both: each theme's `icons.theme` picks a Yaru colour, and each theme generates a Ptyxis palette.
  - When it happens: only during theme switches made **inside Hyprland**, never at install.
  - What carries over: the last Hyprland theme's icons and palette then show in GNOME too.
  - Undo: `uninstall.sh` restores the originals recorded at install.
  - Gaps: `Yaru-gray`/`Yaru-grey` (used by vantablack and white) aren't shipped on Ubuntu, so those two themes leave the icons alone.

## Hyprland versions

The configs were tested on **0.53.3** (Ubuntu 26.04).

**On a newer Hyprland (0.55+):**
- PR #14227 should fix the freeze. `omarchy-lite-wake` is then unnecessary but harmless.
- Some config keys may have changed. Run `Hyprland --verify-config` and fix what it reports.
- Don't switch to Lua configs unless you're rewriting the whole kit.

**On an older one:**
- The `windowrule = … match:…` syntax needs 0.53+, so the configs won't load. Stop and tell the user.

## NVIDIA

This kit was tested on AMD graphics. On NVIDIA:
- **Kernel modesetting must be on.** Confirm `nvidia-drm.modeset=1`.
- **Driver 555 or newer is needed** for explicit sync.
- **Extra environment variables go in `~/.config/hypr/autostart.conf`**, or a new file sourced from `hyprland.conf`: `env = LIBVA_DRIVER_NAME,nvidia`, `env = __GLX_VENDOR_LIBRARY_NAME,nvidia`, `env = NVD_BACKEND,direct`. Follow <https://wiki.hypr.land/Nvidia/>.

Tell the user this part is less tested.

## Troubleshooting

| Symptom | Check / fix |
|---|---|
| Bar missing, apps don't appear | `systemctl --user show-environment \| grep XDG_CURRENT_DESKTOP` must be `Hyprland`; `journalctl --user -b \| grep -i portal` |
| "XDG_CURRENT_DESKTOP managed externally" banner | the desktop name was changed session-wide; revert to plain `Hyprland` (see Pitfalls) |
| Volume/brightness keys do nothing | `busctl --user status org.erikreider.swayosd-server`; restart with `source ~/.local/share/omarchy-lite/bin/omarchy-lite-lib; restart_osd` |
| Wallpaper black | `readlink -f ~/.config/omarchy/current/background` exists? `pgrep -a swaybg`; run `swaybg -i <file>` by hand to see errors |
| Theme picker hangs | `pgrep -a flock`, `pgrep -af omarchy-lite-pick`; stale waiters mean something inherited the lock |
| Window frozen after workspace switch | `pgrep -af omarchy-lite-wake`; Super + F unfreezes it in the meantime |
| "No system keyring" in Chrome/Electron app | launch it from Super + Space (not a terminal) |
| Hyprland logs | `$XDG_RUNTIME_DIR/hypr/*/hyprland.log` (verbose logging is off by default: `debug:disable_logs = false`) |

## Key scripts (`~/.local/share/omarchy-lite/bin/`)

| Script | Does |
|---|---|
| `omarchy-lite-theme-set <theme>` | generates every app's theme file from `themes/<t>/colors.toml` + `themed/*.tpl`, sets wallpaper, reloads everything |
| `omarchy-lite-pick theme\|wallpaper` | rofi grid with thumbnails and **live preview** (`-on-selection-changed`, debounced, latest-wins; Esc reverts) |
| `omarchy-lite-menu launcher\|power\|keys` | fuzzel menus |
| `omarchy-lite-brightness ±N\|N` | brightness via logind + OSD |
| `omarchy-lite-wake` | GTK4 freeze workaround (see Pitfalls) |
| `omarchy-lite-lib` | shared helpers: `theme_backgrounds`, `set_background`, `show_background`, `restart_osd` |

To add an app to theming, add `themed/<file>.tpl` using `{{ key }}`, `{{ key_strip }}` (no `#`) or `{{ key_rgb }}` (`r,g,b`) for keys in `colors.toml`. Then make `theme-set` copy or reload it.
