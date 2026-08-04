#!/usr/bin/env bash
#
# Removes what install-switchvn.sh added, and nothing else.
#
# The file lists written at install time are used rather than a wildcard sweep,
# so a component that was already present in /usr/local before SwitchVN is left
# alone.
#
# License: GPLv3

set -euo pipefail

STEAMROOT="$HOME/.local/share/Steam"
COMPATTOOLS="$STEAMROOT/compatibilitytools.d"
STATE_DIR="$STEAMROOT/SwitchVN"
LDSOCONF="/etc/ld.so.conf.d/switchvn.conf"

ASSUME_YES=0
case "${1:-}" in
    -y|--yes) ASSUME_YES=1 ;;
    '')       ;;
    *)        echo "Usage: uninstall-switchvn.sh [-y]" >&2; exit 1 ;;
esac

if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
else
    C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''
fi

step() { printf '\n%s==>%s %s%s%s\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
ok()   { printf '    %sok%s   %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '    %swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '\n%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    local reply
    printf '\n%s [y/N] ' "$1"
    read -r reply </dev/tty || reply=""
    case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

[ -d "$STATE_DIR" ] || die "no SwitchVN install found at $STATE_DIR"

confirm "Remove SwitchVN?" || exit 0

# ------------------------------------------------------------------- proton --

if [ -f "$STATE_DIR/proton_name" ]; then
    step "Removing Proton"
    name=$(cat "$STATE_DIR/proton_name")
    if [ -d "$COMPATTOOLS/$name" ]; then
        # The DXVK symlinks and their targets live inside this directory, so
        # removing it takes them with it.
        rm -rf "${COMPATTOOLS:?}/$name"
        ok "removed $name"
    else
        warn "$name was already gone"
    fi
fi

# --------------------------------------------------------- system libraries --

remove_listed() {
    local list="$1" label="$2"
    [ -f "$list" ] || return 0
    step "Removing $label from /usr/local"

    # Files first, then directories deepest-first, and only if empty - other
    # packages install into these same directories.
    local rel path
    while IFS= read -r rel; do
        case "$rel" in ''|./) continue ;; esac
        path="/usr/local/${rel#./}"
        if [ -f "$path" ] || [ -L "$path" ]; then
            sudo rm -f "$path"
        fi
    done < "$list"

    while IFS= read -r rel; do
        case "$rel" in ''|./) continue ;; esac
        path="/usr/local/${rel#./}"
        [ -d "$path" ] && sudo rmdir "$path" 2>/dev/null || true
    done < <(sort -r "$list")

    ok "$label removed"
}

if [ -f "$STATE_DIR/ffmpeg.files" ] || [ -f "$STATE_DIR/envideo.files" ]; then
    sudo -v || die "sudo is needed to remove the libraries from /usr/local"
    remove_listed "$STATE_DIR/ffmpeg.files"  "FFmpeg"
    remove_listed "$STATE_DIR/envideo.files" "envideo"

    if [ -f "$LDSOCONF" ]; then
        sudo rm -f "$LDSOCONF"
        ok "removed $LDSOCONF"
    fi
    sudo ldconfig
fi

# -------------------------------------------------------------------- state --

rm -rf "${STATE_DIR:?}"

step "Done"
cat <<'EOF'

SwitchVN is removed. The Proton build and system libraries are gone. The DXVK
copy in Switchdeck/DXVK was left in place: launch-steam.sh uses it to patch the
remaining Proton builds on every Steam launch, so removing it would leave them
without any DXVK source. Delete that folder manually if you want Switchdeck's
relink to have no DXVK at all.

If a game was set to use the SwitchVN Proton build, change it back in the
game's Properties -> Compatibility.
EOF
