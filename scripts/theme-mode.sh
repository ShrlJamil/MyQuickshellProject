#!/bin/bash
# theme-mode - system GTK bridge for the shell's Dark Mode toggle.
#
# Usage: theme-mode dark|light
#
# Three layers, in order:
#   1. The freedesktop color-scheme (prefer-dark / prefer-light) and
#      the GTK prefer-dark flag. Theme-agnostic: libadwaita/GTK4 and
#      portal-aware apps follow these regardless of the theme in use.
#   2. If the currently active GTK theme has an installed dark/light
#      counterpart, switch gtk-theme to it everywhere the setting
#      lives (gsettings, GTK3/GTK4 settings.ini, GTK4 css symlinks).
#      The counterpart is derived from the theme's own name by
#      swapping its Dark/Light name token (WhiteSur-Dark-solid ->
#      WhiteSur-Light-solid, Catppuccin-Dark -> Catppuccin-Light),
#      with fallbacks of dropping the token (Adwaita-dark -> Adwaita)
#      or appending it (Adwaita -> Adwaita-dark). A derived name is
#      only used when a matching theme directory is actually
#      installed; otherwise the theme name is left untouched and
#      only layer 1 applies. No theme name is hardcoded.
#
#   3. Kvantum (Qt), when a Kvantum setup is detected (its state
#      file exists): swap the selected Kvantum theme for its
#      dark/light counterpart - Kvantum pairs themes as a base name
#      plus a trailing Dark on the dark variant (Colloid /
#      ColloidDark, KvArc / KvArcDark). Qt apps pick the new theme
#      up on their next start.
#
# Exit status: 0 on success (including the no-counterpart case),
# 2 on usage error. Individual step failures are non-fatal.

mode="${1:-}"
case "$mode" in
  dark)  scheme="prefer-dark";  prefdark=1 ;;
  light) scheme="prefer-light"; prefdark=0 ;;
  *) echo "usage: theme-mode dark|light" >&2; exit 2 ;;
esac

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"

# Theme lookup roots follow the XDG base directory spec: the legacy
# ~/.themes, then every data dir's themes/ subdirectory.
theme_dirs=("$HOME/.themes" "$data_home/themes")
IFS=':' read -ra _data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for d in "${_data_dirs[@]}"; do theme_dirs+=("$d/themes"); done
gtk3_ini="$config_home/gtk-3.0/settings.ini"
gtk4_ini="$config_home/gtk-4.0/settings.ini"
gtk4_dir="$config_home/gtk-4.0"

# Print the root dir containing theme $1, or nothing when not installed.
theme_root() {
  local d
  for d in "${theme_dirs[@]}"; do
    if [ -d "$d/$1" ]; then echo "$d"; return 0; fi
  done
  return 1
}

# Print the installed $mode counterpart of theme name $1, if any.
counterpart() {
  local name="$1" c
  local -a candidates=()
  case "$mode" in
    light)
      candidates+=("${name/Dark/Light}" "${name/dark/light}")
      candidates+=("${name%-Dark}" "${name%-dark}")
      ;;
    dark)
      candidates+=("${name/Light/Dark}" "${name/light/dark}")
      candidates+=("${name%-Light}" "${name%-light}")
      candidates+=("$name-Dark" "$name-dark")
      ;;
  esac
  for c in "${candidates[@]}"; do
    [ -n "$c" ] && [ "$c" != "$name" ] || continue
    if theme_root "$c" >/dev/null; then echo "$c"; return 0; fi
  done
  return 1
}

current="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'\" ")"
if [ -z "$current" ] && [ -f "$gtk3_ini" ]; then
  current="$(sed -n 's/^gtk-theme-name=//p' "$gtk3_ini" | head -1)"
fi

# Layer 1: mode signals that work with any theme.
gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null
for ini in "$gtk3_ini" "$gtk4_ini"; do
  if [ -f "$ini" ]; then
    sed -i "s/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=$prefdark/" "$ini"
  fi
done

# Layer 2: swap the theme itself when a counterpart is installed.
target="$current"
if [ -n "$current" ] && derived="$(counterpart "$current")"; then
  target="$derived"
fi

if [ -n "$target" ]; then
  gsettings set org.gnome.desktop.interface gtk-theme "$target" 2>/dev/null
  for ini in "$gtk3_ini" "$gtk4_ini"; do
    if [ -f "$ini" ]; then
      sed -i "s/^gtk-theme-name=.*/gtk-theme-name=$target/" "$ini"
    fi
  done
  # GTK4 css symlinks follow the active theme when it ships them.
  if root="$(theme_root "$target")" && [ -f "$root/$target/gtk-4.0/gtk.css" ] && [ -d "$gtk4_dir" ]; then
    ln -sf "$root/$target/gtk-4.0/gtk.css" "$gtk4_dir/gtk.css"
    if [ -f "$root/$target/gtk-4.0/gtk-dark.css" ]; then
      ln -sf "$root/$target/gtk-4.0/gtk-dark.css" "$gtk4_dir/gtk-dark.css"
    fi
  fi
fi

# --- Layer 3: Kvantum (Qt), when present -------------------------------
kv_config="$config_home/Kvantum/kvantum.kvconfig"
kv_roots=("$config_home/Kvantum" "$data_home/Kvantum")
for d in "${_data_dirs[@]}"; do kv_roots+=("$d/Kvantum"); done

# True when a <name>.kvconfig exists under any Kvantum theme root.
kv_installed() {
  local root
  for root in "${kv_roots[@]}"; do
    [ -d "$root" ] || continue
    if compgen -G "$root/*/$1.kvconfig" >/dev/null; then return 0; fi
  done
  return 1
}

# Print the installed $mode counterpart of Kvantum theme name $1.
kv_counterpart() {
  local name="$1" c
  local -a candidates=()
  case "$mode" in
    light) candidates+=("${name%Dark}" "${name%-Dark}" "${name/Dark/Light}") ;;
    dark)  candidates+=("${name/Light/Dark}" "$name-Dark" "${name}Dark") ;;
  esac
  for c in "${candidates[@]}"; do
    [ -n "$c" ] && [ "$c" != "$name" ] || continue
    if kv_installed "$c"; then echo "$c"; return 0; fi
  done
  return 1
}

if [ -f "$kv_config" ]; then
  kv_current="$(sed -n 's/^theme=//p' "$kv_config" | head -1)"
  if [ -n "$kv_current" ] && kv_target="$(kv_counterpart "$kv_current")"; then
    if command -v kvantummanager >/dev/null 2>&1; then
      kvantummanager --set "$kv_target" >/dev/null 2>&1 || true
    fi
    # Guarantee the state file reflects the target even when the
    # manager is unavailable or declines to run headlessly.
    if grep -q '^theme=' "$kv_config"; then
      sed -i "s/^theme=.*/theme=$kv_target/" "$kv_config"
    else
      sed -i "/^\[General\]/a theme=$kv_target" "$kv_config"
    fi
  fi
fi

exit 0
