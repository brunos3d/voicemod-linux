#!/usr/bin/env bash
# voicemod-linux installer.
#
# One-line install (nothing to clone):
#   curl -fsSL https://raw.githubusercontent.com/BrunoS3D/voicemod-linux/main/install.sh | bash
#   wget -qO-  https://raw.githubusercontent.com/BrunoS3D/voicemod-linux/main/install.sh | bash
#
# This script sets up a tool that runs the official Windows build of Voicemod
# on Linux through Proton. It does NOT contain or distribute any Voicemod or
# Proton binary: Voicemod is downloaded from Voicemod's own servers and
# GE-Proton from its official GitHub release, both into your home directory.
# You need your own Voicemod account. Nothing here bypasses payment, login or
# copy protection.
#
# When run via curl|bash it downloads this project's release bundle into a
# temporary directory, installs from there, and deletes the temporary copy.
set -euo pipefail

REPO="BrunoS3D/voicemod-linux"
RELEASE_ASSET="voicemod-linux.tar.gz"
PREFIX="${VML_PREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/voicemod-linux}"
BIN_LINK="$HOME/.local/bin/voicemod-linux"
GE_PROTON_REPO="GloriousEggroll/proton-ge-custom"

ASSUME_YES=0; DO_DEPS=1; DO_PROTON=1; DO_APP=1

c_blue=$'\e[34m'; c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'; c_dim=$'\e[2m'; c_bold=$'\e[1m'; c_off=$'\e[0m'
[[ -t 1 ]] || { c_blue=; c_green=; c_yellow=; c_red=; c_dim=; c_bold=; c_off=; }
step() { printf '%s==>%s %s\n' "$c_blue" "$c_off" "$*"; }
ok()   { printf '%s ok %s %s\n' "$c_green" "$c_off" "$*"; }
warn() { printf '%swarn%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
die()  { printf '%sfail%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

ask() {
    [[ "$ASSUME_YES" == 1 ]] && return 0
    [[ -t 0 ]] || return 0   # non-interactive (piped) defaults to yes
    local r; read -r -p "$1 [Y/n] " r </dev/tty || return 1
    [[ -z "$r" || "$r" =~ ^[Yy] ]]
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)    PREFIX="$2"; shift 2 ;;
        --yes|-y)    ASSUME_YES=1; shift ;;
        --no-deps)   DO_DEPS=0; shift ;;
        --no-proton) DO_PROTON=0; shift ;;
        --no-app)    DO_APP=0; shift ;;
        --local)     FORCE_LOCAL=1; shift ;;
        -h|--help)   sed -n '3,16p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           die "unknown option: $1" ;;
    esac
done

# ------------------------------------------------- locate the payload --

SELF="${BASH_SOURCE[0]:-}"
SRC=""
if [[ -n "$SELF" && -f "$SELF" ]]; then
    SRC="$(cd "$(dirname "$SELF")" && pwd)"
fi

have_payload() { [[ -n "$SRC" && -f "$SRC/bin/voicemod-linux" && -f "$SRC/bridge/vadshim/avrt.dll" ]]; }
have_source()  { [[ -n "$SRC" && -f "$SRC/bridge/vadshim/Makefile" ]]; }

fetch() { # fetch URL OUTFILE
    if command -v curl >/dev/null; then curl -fL --progress-bar -o "$2" "$1"
    elif command -v wget >/dev/null; then wget -q --show-progress -O "$2" "$1"
    else return 1; fi
}
fetch_quiet() {
    if command -v curl >/dev/null; then curl -fsSL "$1"
    elif command -v wget >/dev/null; then wget -qO- "$1"
    else return 1; fi
}

build_shim_locally() {
    command -v clang >/dev/null && command -v lld-link >/dev/null || return 1
    [[ -d /usr/include/wine ]] || return 1
    step "Building the interoperability shim from source"
    make -C "$SRC/bridge/vadshim" >/dev/null 2>&1 || return 1
    [[ -f "$SRC/bridge/vadshim/avrt.dll" ]]
}

bootstrap() {
    # Download the release bundle into a temp dir and install from there.
    step "Downloading the voicemod-linux bundle"
    local url="https://github.com/$REPO/releases/latest/download/$RELEASE_ASSET"
    local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/voicemod-linux.XXXXXX")"
    # Run the bundled installer as a child (not exec) so this trap always
    # removes the temporary download, even on failure.
    trap 'rm -rf "$tmp"' EXIT
    fetch "$url" "$tmp/bundle.tar.gz" || die "could not download $url"
    mkdir -p "$tmp/payload"
    tar -xzf "$tmp/bundle.tar.gz" -C "$tmp/payload"
    local inner; inner="$(dirname "$(find "$tmp/payload" -name voicemod-linux -path '*/bin/*' | head -n1)")/.."
    [[ -f "$inner/install.sh" ]] || die "release bundle is malformed"
    ok "bundle ready"
    local -a args=(--local)
    [[ "$ASSUME_YES" == 1 ]] && args+=(--yes)
    [[ "$DO_DEPS"   == 0 ]] && args+=(--no-deps)
    [[ "$DO_PROTON" == 0 ]] && args+=(--no-proton)
    [[ "$DO_APP"    == 0 ]] && args+=(--no-app)
    VML_PREFIX="$PREFIX" bash "$inner/install.sh" "${args[@]}"
    exit $?
}

# -------------------------------------------------------------- banner --

banner() {
    cat <<BANNER
${c_bold}voicemod-linux${c_off} ${c_dim}(unofficial)${c_off}
Runs the official Windows build of Voicemod on Linux through Proton.
You need your own Voicemod account. This does not crack, pirate, or bypass
payment, login, or copy protection. Voicemod and GE-Proton are downloaded
from their official sources into your home directory.
BANNER
}

# ------------------------------------------------- 1. dependencies --

detect_pm() { for pm in pacman apt-get dnf zypper; do command -v "$pm" >/dev/null && { echo "$pm"; return; }; done; }

pkg_for() {
    case "$1:$2" in
        curl:*) echo curl ;; wget:*) echo wget ;; unzip:*) echo unzip ;; tar:*) echo tar ;;
        python3:pacman) echo python ;; python3:*) echo python3 ;;
        pactl:pacman) echo libpulse ;; pactl:*) echo pulseaudio-utils ;;
    esac
}

install_packages() {
    local pm="$1"; shift; local cmd
    case "$pm" in
        pacman)  cmd="sudo pacman -S --needed $*" ;;
        apt-get) cmd="sudo apt-get update && sudo apt-get install -y $*" ;;
        dnf)     cmd="sudo dnf install -y $*" ;;
        zypper)  cmd="sudo zypper install -y $*" ;;
        *) return 1 ;;
    esac
    printf '    %s%s%s\n' "$c_dim" "$cmd" "$c_off"
    ask "Run this?" || return 1
    eval "$cmd"
}

check_deps() {
    step "Checking dependencies"
    local required=(curl unzip python3 pactl) missing=() cmd
    command -v curl >/dev/null || command -v wget >/dev/null || missing+=(curl)
    for cmd in unzip python3 pactl; do command -v "$cmd" >/dev/null || missing+=("$cmd"); done
    if [[ ${#missing[@]} -eq 0 ]]; then ok "all required tools present"; return; fi
    warn "missing: ${missing[*]}"
    [[ "$DO_DEPS" == 1 ]] || die "install them manually, or drop --no-deps"
    local pm; pm="$(detect_pm)"
    [[ -n "$pm" ]] || die "no supported package manager; install manually: ${missing[*]}"
    local pkgs=() p
    for cmd in "${missing[@]}"; do p="$(pkg_for "$cmd" "$pm")"; [[ -n "$p" ]] && pkgs+=("$p"); done
    install_packages "$pm" "${pkgs[@]}" || die "dependencies not installed"
    for cmd in "${missing[@]}"; do command -v "$cmd" >/dev/null || die "$cmd still missing"; done
    ok "dependencies installed"
}

# ------------------------------------------------- 2. copy project --

copy_project() {
    step "Installing to $PREFIX"
    if ! have_payload && have_source; then
        build_shim_locally || die "the shim is not built. Install clang, lld and the Wine headers and run 'make -C bridge/vadshim', or use the curl install method."
    fi
    have_payload || die "no payload found next to this script"
    mkdir -p "$PREFIX"
    local d
    for d in bin bridge share; do rm -rf "$PREFIX/$d"; cp -r "$SRC/$d" "$PREFIX/$d"; done
    for d in README.md README.pt-BR.md LICENSE NOTICE uninstall.sh; do
        [[ -f "$SRC/$d" ]] && cp "$SRC/$d" "$PREFIX/$d"
    done
    [[ -d "$SRC/docs" ]] && { rm -rf "$PREFIX/docs"; cp -r "$SRC/docs" "$PREFIX/docs"; }
    chmod +x "$PREFIX/bin/voicemod-linux" "$PREFIX/bin/voicemod-open-url"
    [[ -f "$PREFIX/uninstall.sh" ]] && chmod +x "$PREFIX/uninstall.sh"
    ok "project files in place"
}

# ------------------------------------------------- 3. GE-Proton --

have_ge_proton() {
    local d
    for d in "$PREFIX"/proton/GE-Proton* \
             "$HOME"/.steam/steam/compatibilitytools.d/GE-Proton* \
             "$HOME"/.local/share/Steam/compatibilitytools.d/GE-Proton* \
             "$HOME"/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d/GE-Proton*; do
        [[ -x "$d/proton" ]] && return 0
    done
    return 1
}

install_proton() {
    step "GE-Proton"
    if have_ge_proton; then ok "a GE-Proton build is already available, reusing it"; return; fi
    [[ "$DO_PROTON" == 1 ]] || die "no GE-Proton found and --no-proton was given"
    command -v tar >/dev/null || die "tar is required to unpack GE-Proton"
    step "Finding the latest GE-Proton release"
    local tag tgz sha
    read -r tag tgz sha < <(fetch_quiet "https://api.github.com/repos/$GE_PROTON_REPO/releases/latest" | python3 -c '
import json,sys
d=json.load(sys.stdin); tag=d["tag_name"]; a=b=""
for x in d["assets"]:
    n=x["name"]
    if n.endswith(".tar.gz"): a=x["browser_download_url"]
    elif n.endswith(".sha512sum"): b=x["browser_download_url"]
print(tag,a,b)') || die "could not query GitHub for GE-Proton"
    [[ -n "$tgz" ]] || die "no .tar.gz asset in the latest release"
    step "Downloading $tag (about 400 MB)"
    local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
    fetch "$tgz" "$tmp/ge.tar.gz" || die "download failed"
    if [[ -n "$sha" ]] && fetch_quiet "$sha" > "$tmp/ge.sha512sum" 2>/dev/null; then
        step "Verifying checksum"
        ( cd "$tmp" && sed "s#  .*/#  #; s#  [^ ]*\$#  ge.tar.gz#" ge.sha512sum > ge.local \
          && sha512sum -c ge.local >/dev/null ) || die "checksum mismatch; aborting"
        ok "checksum verified"
    else
        warn "no checksum for $tag; skipping verification"
    fi
    mkdir -p "$PREFIX/proton"
    tar -xzf "$tmp/ge.tar.gz" -C "$PREFIX/proton"
    have_ge_proton || die "GE-Proton did not unpack correctly"
    ok "$tag installed in $PREFIX/proton"
}

# ------------------------------------------------- 4. Voicemod --

install_app() {
    step "Downloading Voicemod from voicemod.net"
    if [[ "$DO_APP" == 0 ]]; then warn "skipped (run 'voicemod-linux update' later)"; return; fi
    VML_HOME="$PREFIX" "$PREFIX/bin/voicemod-linux" update || die "Voicemod download failed"
    ok "Voicemod downloaded"
}

# ------------------------------------------------- 5. desktop + PATH --

extract_icon() {
    local exe="$PREFIX/app/core/Voicemod.exe" out="$PREFIX/share/voicemod-linux.png"
    [[ -f "$exe" ]] || return 1
    command -v wrestool >/dev/null && command -v icotool >/dev/null || return 1
    local tmp; tmp="$(mktemp -d)"
    if wrestool -x -t 14 "$exe" -o "$tmp/i.ico" 2>/dev/null \
       && icotool -x --width=256 -o "$tmp/i.png" "$tmp/i.ico" 2>/dev/null; then
        cp "$(ls "$tmp"/i*.png | head -n1)" "$out" && { rm -rf "$tmp"; return 0; }
    fi
    rm -rf "$tmp"; return 1
}

install_desktop() {
    step "Desktop integration"
    local apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    local icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
    mkdir -p "$apps" "$icons" "$(dirname "$BIN_LINK")"
    local icon="audio-input-microphone"
    if extract_icon; then cp "$PREFIX/share/voicemod-linux.png" "$icons/voicemod-linux.png"; icon="voicemod-linux"; ok "icon extracted from Voicemod.exe"
    else warn "icoutils not installed; using a generic microphone icon"; fi
    sed -e "s#@EXEC@#$PREFIX/bin/voicemod-linux#g" -e "s#@ICON@#$icon#g" \
        "$PREFIX/share/voicemod-linux.desktop.in" > "$apps/voicemod-linux.desktop"
    update-desktop-database "$apps" 2>/dev/null || true
    xdg-mime default voicemod-linux.desktop x-scheme-handler/voicemod 2>/dev/null || true
    ln -sfn "$PREFIX/bin/voicemod-linux" "$BIN_LINK"
    ok "menu entry, voicemod: handler and $BIN_LINK installed"
    case ":$PATH:" in *":$(dirname "$BIN_LINK"):"*) ;; *) warn "$(dirname "$BIN_LINK") is not in PATH; add it or run $BIN_LINK directly" ;; esac
}

# ------------------------------------------------------------- main --

banner
if ! have_payload && [[ "${FORCE_LOCAL:-0}" != 1 ]] && ! have_source; then
    ask "Continue?" || exit 0
    bootstrap   # downloads the release bundle and re-execs --local
fi
ask "Continue?" || exit 0

check_deps
copy_project
install_proton
install_app
install_desktop

cat <<DONE

${c_green}${c_bold}Done.${c_off}
Launch Voicemod from your application menu, or run:  ${c_bold}voicemod-linux${c_off}

First run:
  - pick your real microphone and headphones in the onboarding;
  - in Discord, OBS or games choose the input "Voicemod Virtual Audio Device (WDM)";
  - if a dialog offers to install the Voicemod driver, choose No.

Commands:  voicemod-linux {doctor|update|kill|logs}
Uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash
DONE
