#!/usr/bin/env bash
# voicemod-linux uninstaller.
#
# One-line uninstall:
#   curl -fsSL https://raw.githubusercontent.com/brunos3d/voicemod-linux/main/uninstall.sh | bash
#   wget -qO-  https://raw.githubusercontent.com/brunos3d/voicemod-linux/main/uninstall.sh | bash
#
# Removes everything the installer created in your home directory. It does not
# touch your Voicemod account or a GE-Proton you installed through Steam.
set -euo pipefail

PREFIX="${VML_PREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/voicemod-linux}"
BIN_LINK="$HOME/.local/bin/voicemod-linux"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
ASSUME_YES=0

c_red=$'\e[31m'; c_green=$'\e[32m'; c_off=$'\e[0m'; [[ -t 1 ]] || { c_red=; c_green=; c_off=; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        -h|--help) sed -n '3,11p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

ask() {
    [[ "$ASSUME_YES" == 1 ]] && return 0
    [[ -t 0 ]] || return 0
    local r; read -r -p "$1 [y/N] " r </dev/tty || return 1
    [[ "$r" =~ ^[Yy] ]]
}

# Stop a running instance and drop the audio devices first.
if [[ -x "$PREFIX/bin/voicemod-linux" ]]; then
    VML_HOME="$PREFIX" "$PREFIX/bin/voicemod-linux" kill 2>/dev/null || true
    VML_HOME="$PREFIX" "$PREFIX/bin/voicemod-linux" teardown-audio 2>/dev/null || true
fi

echo "This removes:"
echo "  $PREFIX  (launcher, bridge, Proton prefix, downloaded Voicemod and GE-Proton)"
echo "  $BIN_LINK"
echo "  $APPS/voicemod-linux.desktop"
echo "  $ICONS/voicemod-linux.png"
echo "Your Voicemod account and any Steam GE-Proton are left untouched."
ask "Proceed?" || { echo "Aborted."; exit 0; }

rm -rf "$PREFIX"
rm -f "$BIN_LINK" "$APPS/voicemod-linux.desktop" "$ICONS/voicemod-linux.png"
update-desktop-database "$APPS" 2>/dev/null || true
if [[ "$(xdg-mime query default x-scheme-handler/voicemod 2>/dev/null)" == voicemod-linux.desktop ]]; then
    xdg-mime default '' x-scheme-handler/voicemod 2>/dev/null || true
fi

printf '%sRemoved.%s\n' "$c_green" "$c_off"
