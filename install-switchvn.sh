#!/usr/bin/env bash
#
# SwitchVN installer - hardware video decoding for visual novels under Proton
# on a Nintendo Switch running switchroot Ubuntu.
#
# Installs four prebuilt components:
#   envideo + FFmpeg  -> /usr/local          (native aarch64, used via Box64)
#   Proton            -> compatibilitytools.d
#   DXVK              -> inside the Proton directory + Switchdeck/DXVK (the
#                        relink source launch-steam.sh patches other Protons from)
#
# Run it after Switchdeck is installed and has started Steam at least once.
#
# License: GPLv3

set -euo pipefail

# ---------------------------------------------------------------- constants --

# Component versions come from switchvn.lock rather than from each repository's
# latest release: "latest of each" is a combination nobody has run.
#
# The lock ships as a release asset. GitHub redirects these two paths, so no
# API call is involved - no rate limit, and no window where a release published
# mid-install changes the answer. It also leaves main free to move: what users
# get is whatever was last tagged, not the tip of the branch.
RELEASES="https://github.com/BandiFee/SwitchVN/releases"
LOCK_LATEST_URL="$RELEASES/latest/download/switchvn.lock"

# SWITCHVN_LOCK takes a path or a URL and wins over everything: it is how a
# candidate combination gets tested before it is tagged.
LOCK_FILE="${SWITCHVN_LOCK:-}"
WANT_VERSION="${SWITCHVN_VERSION:-}"

STEAMROOT="$HOME/.local/share/Steam"
SWITCHDECK_DIR="$STEAMROOT/Switchdeck"
COMPATTOOLS="$STEAMROOT/compatibilitytools.d"
STATE_DIR="$STEAMROOT/SwitchVN"

LDSOCONF="/etc/ld.so.conf.d/switchvn.conf"
FFMPEG_LIBDIR="/usr/local/lib/aarch64-linux-gnu"

ASSUME_YES=0
SKIP_SYSTEM=0
SKIP_PROTON=0
SKIP_DXVK=0

# ------------------------------------------------------------------ helpers --

if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
    C_RED=$'\033[31m';  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
else
    C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''
fi

step() { printf '\n%s==>%s %s%s%s\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %sok%s   %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '    %swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '\n%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: install-switchvn.sh [options]

  -y, --yes           Do not ask for confirmation.
      --version VER   Install a specific SwitchVN version instead of the
                      latest one, e.g. --version 1.0.
      --skip-system   Do not touch /usr/local (no envideo/FFmpeg install).
      --skip-proton   Do not install Proton.
      --skip-dxvk     Do not install DXVK into Proton.
  -h, --help          Show this message.

Environment:
  SWITCHVN_VERSION    Same as --version.
  SWITCHVN_LOCK       Path or URL of a switchvn.lock to use instead of a
                      published one. This is how a candidate combination is
                      tested before it gets tagged.

Without --skip-system the script needs sudo to write to /usr/local.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)      ASSUME_YES=1 ;;
        --version)     [ $# -ge 2 ] || die "--version needs a version, e.g. --version 1.0"
                       WANT_VERSION="$2"; shift ;;
        --version=*)   WANT_VERSION="${1#*=}" ;;
        --skip-system) SKIP_SYSTEM=1 ;;
        --skip-proton) SKIP_PROTON=1 ;;
        --skip-dxvk)   SKIP_DXVK=1 ;;
        -h|--help)     usage; exit 0 ;;
        *)             usage >&2; die "unknown option: $1" ;;
    esac
    shift
done

confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    local reply
    printf '\n%s [Y/n] ' "$1"
    read -r reply </dev/tty || reply=""
    case "$reply" in ''|y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# Reads one field of one component out of the lock file.
#   lock_field ffmpeg tag  ->  switchvn-ffmpeg-8.1.1-1
lock_field() {
    local name="$1" field="$2" col
    case "$field" in
        repo)  col=2 ;;
        tag)   col=3 ;;
        asset) col=4 ;;
        *)     die "internal: unknown lock field '$field'" ;;
    esac
    awk -v n="$name" -v c="$col" \
        '$1 == n && NF >= 4 { print $c; found = 1; exit } END { exit !found }' \
        "$LOCK_FILE" || die "no '$name' entry in the lock file"
}

# Release download URLs are stable and predictable, so pinning a tag means the
# GitHub API is not involved at all - no rate limit, and no chance of picking
# up a release that was published after this combination was tested.
asset_url() {
    local name="$1" repo tag asset
    # Assign and check separately: die() inside a command substitution only
    # exits that subshell, so building the URL inline would happily splice the
    # error message into it and carry on.
    repo=$(lock_field "$name" repo)   || exit 1
    tag=$(lock_field "$name" tag)     || exit 1
    asset=$(lock_field "$name" asset) || exit 1
    printf 'https://github.com/%s/releases/download/%s/%s\n' "$repo" "$tag" "$asset"
}

fetch() {
    local url="$1" dest="$2"
    info "downloading ${url##*/}"
    wget -q --show-progress -c -t 5 -O "$dest" "$url" \
        || die "download failed: $url"
}

# ---------------------------------------------------------------- preflight --

step "Checking the system"

[ "$(uname -m)" = "aarch64" ] \
    || die "this installer is for aarch64 (the Switch); found $(uname -m)"

for cmd in wget tar sed grep; do
    command -v "$cmd" >/dev/null || die "'$cmd' is required but not installed"
done
ok "aarch64, required tools present"

[ -d "$SWITCHDECK_DIR" ] \
    || die "Switchdeck was not found at $SWITCHDECK_DIR.
    Install Switchdeck first (https://github.com/SildurFX/Switchdeck) and start
    Steam once, then run this again."
ok "Switchdeck found"

# Box64 runs the x86 Proton and is what loads the native FFmpeg libraries.
command -v box64 >/dev/null || [ -x /usr/local/bin/box64 ] \
    || die "box64 was not found. Switchdeck installs it; if you removed it, the
    x86 Proton build cannot run at all."
ok "box64 found"

# The decoder talks to the Tegra multimedia engines through these nodes.
missing_nodes=""
for node in /dev/nvhost-nvdec /dev/nvmap; do
    [ -e "$node" ] || missing_nodes="$missing_nodes $node"
done
[ -z "$missing_nodes" ] \
    || die "missing device node(s):$missing_nodes
    These come from the switchroot L4T kernel. Without them there is no
    hardware decoding to enable."

if ! id -nG | tr ' ' '\n' | grep -qx video; then
    warn "you are not in the 'video' group, so opening the nvhost nodes may fail"
    warn "fix with: sudo usermod -aG video $USER   (then log out and back in)"
else
    ok "device nodes present, user is in the 'video' group"
fi

if [ "$SKIP_SYSTEM" -eq 0 ]; then
    sudo -v || die "sudo is needed to install envideo and FFmpeg into /usr/local"
fi

# ----------------------------------------------------------------- download --

step "Reading the component lock"

TMPDIR_SWITCHVN=$(mktemp -d)
trap 'rm -rf "$TMPDIR_SWITCHVN"' EXIT

fetch_lock() {
    local url="$1" what="$2" dest="$TMPDIR_SWITCHVN/switchvn.lock"
    wget -qO "$dest" "$url" \
        || die "cannot fetch $what from
    $url
    Check the network connection, or pass --version for one that exists."
    # An empty file here would sail through every later check and produce a
    # confusing 'no envideo entry' instead of naming the real problem.
    [ -s "$dest" ] || die "$what came back empty from $url"
    printf '%s\n' "$dest"
}

if [ -n "$LOCK_FILE" ]; then
    case "$LOCK_FILE" in
        http://*|https://*)
            src="$LOCK_FILE"
            LOCK_FILE=$(fetch_lock "$src" "the lock at $src")
            ok "using $src" ;;
        *)
            [ -f "$LOCK_FILE" ] || die "SWITCHVN_LOCK points at $LOCK_FILE, which does not exist"
            ok "using $LOCK_FILE" ;;
    esac
    [ -z "$WANT_VERSION" ] || warn "SWITCHVN_LOCK overrides --version"
elif [ -n "$WANT_VERSION" ]; then
    url="$RELEASES/download/v$WANT_VERSION/switchvn.lock"
    LOCK_FILE=$(fetch_lock "$url" "SwitchVN $WANT_VERSION")
    ok "pinned to SwitchVN $WANT_VERSION"
else
    LOCK_FILE=$(fetch_lock "$LOCK_LATEST_URL" "the latest SwitchVN release")
fi

SWITCHVN_VERSION=$(awk '$1 == "SWITCHVN_VERSION" { print $2; exit }' "$LOCK_FILE")
[ -n "$SWITCHVN_VERSION" ] || die "the lock file has no SWITCHVN_VERSION"
ok "SwitchVN $SWITCHVN_VERSION"

# Compare against what is already installed, so a reinstall says what it is
# about to change instead of silently swapping components underneath.
PREV_LOCK="$STATE_DIR/switchvn.lock"
if [ -r "$PREV_LOCK" ]; then
    prev_version=$(awk '$1 == "SWITCHVN_VERSION" { print $2; exit }' "$PREV_LOCK")
    if [ "$prev_version" = "$SWITCHVN_VERSION" ]; then
        info "SwitchVN $SWITCHVN_VERSION is already installed; reinstalling it"
    else
        info "upgrading from SwitchVN ${prev_version:-unknown}"
    fi

    changed=""
    for c in envideo ffmpeg dxvk box64 proton; do
        old=$(awk -v n="$c" '$1 == n && NF >= 4 { print $3; exit }' "$PREV_LOCK")
        new=$(awk -v n="$c" '$1 == n && NF >= 4 { print $3; exit }' "$LOCK_FILE")
        [ -n "$old" ] && [ "$old" != "$new" ] || continue
        info "  $c: $old -> $new"
        changed="$changed $c"
    done
    [ -n "$changed" ] || info "  no component changes"

    # libavcodec links libenvideo.so, whose SONAME carries no version, so the
    # loader accepts any copy and a mismatched pair misdecodes rather than
    # failing to link. The two only ever move together.
    case "$changed" in
        *envideo*ffmpeg*|*ffmpeg*envideo*) ;;
        *envideo*|*ffmpeg*)
            die "this lock moves only one of envideo and FFmpeg.
    They are built against each other and have to move together; installing
    them apart produces bad decoding with no error message." ;;
    esac
fi

if [ "$SKIP_SYSTEM" -eq 0 ]; then
    URL_ENVIDEO=$(asset_url envideo)
    URL_FFMPEG=$(asset_url ffmpeg)
    ok "envideo: $(lock_field envideo tag)"
    ok "ffmpeg:  $(lock_field ffmpeg tag)"
fi
if [ "$SKIP_PROTON" -eq 0 ]; then
    URL_PROTON=$(asset_url proton)
    PROTON_NAME=$(basename "$(lock_field proton asset)" .tar.gz)
    ok "proton:  $PROTON_NAME"
    # launch-steam.sh only applies its vertex-explosion patch to directories
    # whose name starts with GE-Proton11 (or Proton 11 / Experimental / Hotfix).
    # A rename here would silently cost 32-bit games their geometry.
    case "$PROTON_NAME" in
        GE-Proton11*) ;;
        *) die "the Proton build is named '$PROTON_NAME', which Switchdeck's
    launch script will not recognise. It must start with 'GE-Proton11'." ;;
    esac
fi
if [ "$SKIP_DXVK" -eq 0 ]; then
    URL_DXVK=$(asset_url dxvk)
    ok "dxvk:    $(lock_field dxvk tag)"
fi

step "Downloading"
if [ "$SKIP_SYSTEM" -eq 0 ]; then
    fetch "$URL_ENVIDEO" "$TMPDIR_SWITCHVN/envideo.tar.gz"
    fetch "$URL_FFMPEG"  "$TMPDIR_SWITCHVN/ffmpeg.tar.gz"
fi
if [ "$SKIP_PROTON" -eq 0 ]; then
    fetch "$URL_PROTON" "$TMPDIR_SWITCHVN/proton.tar.gz"
fi
if [ "$SKIP_DXVK" -eq 0 ]; then
    fetch "$URL_DXVK" "$TMPDIR_SWITCHVN/dxvk.tar.gz"
fi

confirm "Install now?" || die "aborted"

mkdir -p "$STATE_DIR"
# Keep the exact combination that was installed, so a bug report only has to
# quote one version and the uninstaller knows what it is removing.
printf '%s\n' "$SWITCHVN_VERSION" > "$STATE_DIR/version"
cp "$LOCK_FILE" "$STATE_DIR/switchvn.lock"

# --------------------------------------------------------- system libraries --

if [ "$SKIP_SYSTEM" -eq 0 ]; then
    step "Installing envideo and FFmpeg into /usr/local"

    # An older envideo left in /usr/lib or a second copy in /usr/local would be
    # picked up ahead of this one and produce black video with no error, so the
    # duplicate check below is not cosmetic.
    tar -tzf "$TMPDIR_SWITCHVN/envideo.tar.gz" > "$STATE_DIR/envideo.files"
    tar -tzf "$TMPDIR_SWITCHVN/ffmpeg.tar.gz"  > "$STATE_DIR/ffmpeg.files"

    sudo tar -xzf "$TMPDIR_SWITCHVN/envideo.tar.gz" -C /usr/local
    sudo tar -xzf "$TMPDIR_SWITCHVN/ffmpeg.tar.gz"  -C /usr/local
    ok "unpacked"

    # Ubuntu's default ld.so config covers /usr/local/lib but not the
    # multiarch subdirectory FFmpeg installs into.
    printf '/usr/local/lib\n%s\n' "$FFMPEG_LIBDIR" | sudo tee "$LDSOCONF" >/dev/null
    sudo ldconfig
    ok "ldconfig updated"

    step "Verifying the native libraries"

    ver=$(PKG_CONFIG_PATH=/usr/local/lib/pkgconfig pkg-config --modversion envideo 2>/dev/null || true)
    [ -n "$ver" ] && ok "envideo $ver" || warn "pkg-config cannot see envideo (only matters when rebuilding)"

    n=$(ldconfig -p | grep -c 'libenvideo\.so' || true)
    case "$n" in
        0) die "libenvideo.so is not in the linker cache after install" ;;
        1) ok "exactly one libenvideo.so in the cache" ;;
        *) warn "$n copies of libenvideo.so are in the linker cache:"
           ldconfig -p | grep 'libenvideo\.so' | sed 's/^/         /' >&2
           warn "remove the stale one, or the wrong version may be loaded" ;;
    esac

    # Box64's ffmpeg8 wrapper binds these two by soname. If either is missing it
    # falls back to emulating the x86 libraries without saying so, which looks
    # exactly like hardware decoding being unavailable.
    for soname in libavcodec.so.62 libavutil.so.60; do
        ldconfig -p | grep -q "$soname" \
            || die "$soname is not in the linker cache; Box64 will not use the
    native FFmpeg and there will be no hardware decoding"
    done
    ok "libavcodec.so.62 and libavutil.so.60 visible to Box64"

    # libenvideo.so has no version in its SONAME, so libavcodec loads whatever
    # copy is on the system regardless of what it was compiled against. A
    # mismatch produces wrong decoding rather than a link error, and the two
    # releases can move independently. Both builds record their commit; compare
    # them, because nothing at runtime will.
    stamp_installed="/usr/local/share/switchvn/envideo-commit"
    stamp_expected="/usr/local/share/switchvn/ffmpeg-envideo-commit"
    if [ -r "$stamp_installed" ] && [ -r "$stamp_expected" ]; then
        if [ "$(cat "$stamp_installed")" = "$(cat "$stamp_expected")" ]; then
            ok "FFmpeg was built against this exact envideo"
        else
            warn "version skew between the two releases:"
            warn "  envideo installed:        $(cat "$stamp_installed")"
            warn "  FFmpeg was built against: $(cat "$stamp_expected")"
            warn "Decoding may misbehave in ways that produce no error message."
            warn "Reinstall once both releases have been rebuilt from the same commit."
        fi
    else
        # Releases published before the stamps existed simply have no file.
        info "no build stamps to compare (older releases do not carry them)"
    fi
fi

# ------------------------------------------------------------------- proton --

PROTON_DIR=""
if [ "$SKIP_PROTON" -eq 0 ]; then
    step "Installing Proton"

    mkdir -p "$COMPATTOOLS"
    PROTON_DIR="$COMPATTOOLS/$PROTON_NAME"

    if [ -e "$PROTON_DIR" ]; then
        confirm "$PROTON_NAME already exists. Replace it?" || die "aborted"
        rm -rf "$PROTON_DIR"
    fi

    tar -xzf "$TMPDIR_SWITCHVN/proton.tar.gz" -C "$COMPATTOOLS"
    [ -d "$PROTON_DIR/files" ] \
        || die "the Proton archive did not unpack to $PROTON_DIR as expected"
    ok "installed to $PROTON_DIR"
    printf '%s\n' "$PROTON_NAME" > "$STATE_DIR/proton_name"
elif [ -f "$STATE_DIR/proton_name" ]; then
    PROTON_NAME=$(cat "$STATE_DIR/proton_name")
    PROTON_DIR="$COMPATTOOLS/$PROTON_NAME"
fi

# --------------------------------------------------------------------- dxvk --

if [ "$SKIP_DXVK" -eq 0 ]; then
    step "Installing DXVK into Proton"

    [ -n "$PROTON_DIR" ] && [ -d "$PROTON_DIR/files" ] \
        || die "no Proton installation to patch; run without --skip-proton first"

    P="$PROTON_DIR/files"
    DX_STORE="$P/lib/switchvn-dxvk"
    VK_STORE="$P/lib/switchvn-vkd3d"

    rm -rf "$DX_STORE"
    mkdir -p "$DX_STORE"
    tar -xzf "$TMPDIR_SWITCHVN/dxvk.tar.gz" -C "$DX_STORE" --strip-components=1
    [ -f "$DX_STORE/x64/d3d9.dll" ] \
        || die "the DXVK archive does not contain x64/d3d9.dll"
    ok "DXVK unpacked into the Proton tree"

    # The same archive also feeds Switchdeck's launch script: it relinks every
    # Proton's wine/dxvk from Switchdeck/DXVK on each Steam launch, so this
    # copy makes the SwitchVN DXVK available to any other Proton as well.
    DX_SWITCHDECK="$SWITCHDECK_DIR/DXVK"
    rm -rf "$DX_SWITCHDECK"
    mkdir -p "$DX_SWITCHDECK"
    tar -xzf "$TMPDIR_SWITCHVN/dxvk.tar.gz" -C "$DX_SWITCHDECK" --strip-components=1
    [ -f "$DX_SWITCHDECK/x64/d3d9.dll" ] \
        || die "the DXVK archive did not unpack to $DX_SWITCHDECK as expected"
    ok "Switchdeck/DXVK populated (launch-steam.sh relinks other Protons from it)"

    # Switchdeck's launch script relinks DXVK and VKD3D unless *both* d3d11.dll
    # and d3d12.dll are already symlinks. Pointing them at copies kept inside
    # the Proton directory satisfies that test, so the relink leaves this
    # Proton alone instead of re-pointing it at Switchdeck/DXVK.
    if [ ! -d "$VK_STORE" ]; then
        mkdir -p "$VK_STORE/x64" "$VK_STORE/x32"
        if [ -f "$SWITCHDECK_DIR/VKD3D/x64/d3d12.dll" ]; then
            cp "$SWITCHDECK_DIR/VKD3D/x64/d3d12.dll" "$VK_STORE/x64/"
            if [ -f "$SWITCHDECK_DIR/VKD3D/x86/d3d12.dll" ]; then
                cp "$SWITCHDECK_DIR/VKD3D/x86/d3d12.dll" "$VK_STORE/x32/"
            fi
            ok "took VKD3D 2.3.1 from Switchdeck"
        else
            # Fall back to whatever this Proton build shipped, so the symlink
            # invariant still holds.
            for arch_pair in "x86_64-windows:x64" "i386-windows:x32"; do
                src="$P/lib/wine/vkd3d-proton/${arch_pair%%:*}/d3d12.dll"
                if [ -f "$src" ] && [ ! -L "$src" ]; then
                    cp "$src" "$VK_STORE/${arch_pair##*:}/"
                fi
            done
            warn "Switchdeck's VKD3D folder is missing; using Proton's own copy"
        fi
    fi

    link_dir() {
        local src="$1" dst="$2"
        [ -d "$src" ] || return 0
        mkdir -p "$dst"
        local f
        for f in "$src"/*.dll; do
            [ -e "$f" ] || continue
            ln -sf "$f" "$dst/${f##*/}"
        done
    }

    link_dir "$DX_STORE/x64" "$P/lib/wine/dxvk/x86_64-windows"
    link_dir "$DX_STORE/x32" "$P/lib/wine/dxvk/i386-windows"

    # vkd3d-proton loads d3d12core.dll alongside d3d12.dll; both names point at
    # the same binary, which is how Switchdeck sets it up too.
    for arch_pair in "x64:x86_64-windows" "x32:i386-windows"; do
        src="$VK_STORE/${arch_pair%%:*}/d3d12.dll"
        dst="$P/lib/wine/vkd3d-proton/${arch_pair##*:}"
        [ -f "$src" ] || continue
        mkdir -p "$dst"
        ln -sf "$src" "$dst/d3d12.dll"
        ln -sf "$src" "$dst/d3d12core.dll"
    done

    [ -L "$P/lib/wine/dxvk/x86_64-windows/d3d11.dll" ] \
        && [ -L "$P/lib/wine/vkd3d-proton/x86_64-windows/d3d12.dll" ] \
        || die "the DXVK/VKD3D symlinks were not created; Switchdeck would
    overwrite this install on the next Steam launch"
    ok "symlinks in place, Switchdeck will leave this Proton's DXVK alone"
fi

# ------------------------------------------------------------------ summary --

step "Done"

cat <<EOF

Next steps:

  1. Restart Steam through Switchdeck's launcher:

       $STEAMROOT/launch-steam.sh

  2. In the game's Properties -> Compatibility, tick "Force the use of a
     specific Steam Play compatibility tool" and choose:

       ${PROTON_NAME:-the SwitchVN Proton build}

  3. Play a video. To confirm hardware decoding is actually being used, set the
     game's launch options to:

       WINEDEBUG=+dmo PROTON_LOG=1 %command%

     then after the video plays:

       grep -E 'envideo|decoding in software' ~/steam-*.log

     A line reading "trying envideo decoding for <codec>" with no fallback
     underneath it means it worked.

To remove everything again, run uninstall-switchvn.sh.
EOF
