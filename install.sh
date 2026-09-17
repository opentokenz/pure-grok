#!/bin/bash
#
# Grok CLI installer for the pure-grok builds.
# Downloads a release binary from this repository's GitHub Releases and
# installs it as `grok`.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/opentokenz/pure-grok/main/install.sh | bash            # latest release
#   curl -fsSL https://raw.githubusercontent.com/opentokenz/pure-grok/main/install.sh | bash -s v0.1.0  # specific tag
#   GH_TOKEN=<token> bash install.sh                                                                   # private repo / high rate limits
#
# Env:
#   GROK_BIN_DIR   install directory (default: ~/.local/bin)
#   GH_TOKEN       GitHub token; only required for private repositories

set -e

REPO="opentokenz/pure-grok"
API_BASE="https://api.github.com/repos/${REPO}"
RELEASE_BASE="https://github.com/${REPO}/releases/download"

TARGET="$1"

# --- platform detection (matches the CI build matrix) ---
uname_s="$(uname -s)"
os="$(printf '%s' "$uname_s" | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
case "$uname_s" in
    Linux)                    os="linux" ;;
    Darwin)                   os="macos" ;;
    MINGW*|MSYS*|CYGWIN*)     os="windows" ;;
    *)
        echo "Unsupported OS: ${uname_s} (prebuilt binaries target Linux, macOS, and Windows)" >&2
        exit 1
        ;;
esac
case "$arch" in
    x86_64 | amd64 | AMD64)  arch="x86_64" ;;
    arm64 | aarch64 | ARM64) arch="arm64" ;;
    *)
        echo "Unsupported architecture: ${arch}" >&2
        exit 1
        ;;
esac

asset="grok-${os}-${arch}"
exe=""
if [ "$os" = "windows" ]; then
    asset="${asset}.exe"
    exe=".exe"
fi
case "$asset" in
    grok-linux-x86_64 | grok-macos-arm64 | grok-windows-x86_64.exe) : ;;
    *)
        echo "No prebuilt binary for ${os}-${arch} (available: linux-x86_64, macos-arm64, windows-x86_64)." >&2
        echo "Build from source instead: cargo build -p xai-grok-pager-bin --release" >&2
        exit 1
        ;;
esac

# --- downloader ---
if command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget"
else
    echo "Either curl or wget is required but neither is installed" >&2
    exit 1
fi

auth_args() {
    if [ -n "$GH_TOKEN" ]; then
        if [ "$DOWNLOADER" = "curl" ]; then
            echo "-H Authorization:Bearer\\ ${GH_TOKEN}"
        else
            echo "--header=Authorization:\\ Bearer\\ ${GH_TOKEN}"
        fi
    fi
}

download_stdout() {  # url -> stdout
    if [ "$DOWNLOADER" = "curl" ]; then
        # shellcheck disable=SC2046
        curl -fsSL $(auth_args) "$1"
    else
        # shellcheck disable=SC2046
        wget -q -O - $(auth_args) "$1"
    fi
}

download_to() {  # url output
    if [ "$DOWNLOADER" = "curl" ]; then
        # shellcheck disable=SC2046
        curl -fsSL $(auth_args) -o "$2" "$1"
    else
        # shellcheck disable=SC2046
        wget -q -O "$2" $(auth_args) "$1"
    fi
}

# --- resolve version ---
if [ -n "$TARGET" ]; then
    version="$TARGET"
else
    echo "Fetching latest release..." >&2
    version=$(
        download_stdout "${API_BASE}/releases/latest" 2>/dev/null \
            | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
            | head -n1 \
            | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/'
    )
    if [ -z "$version" ]; then
        echo "Error: failed to fetch the latest release tag." >&2
        echo "  Check that a release exists (https://github.com/${REPO}/releases)" >&2
        echo "  and that you are not rate-limited by api.github.com; set GH_TOKEN for higher limits." >&2
        exit 1
    fi
fi

# --- install ---
DOWNLOAD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pure-grok/downloads"
BIN_DIR="${GROK_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$DOWNLOAD_DIR" "$BIN_DIR"

binary_path="$DOWNLOAD_DIR/$asset"
binary_tmp="${binary_path}.tmp.$$"
rm -f "$binary_tmp"

echo "  Downloading grok ${version} (${asset})..." >&2
if ! download_to "${RELEASE_BASE}/${version}/${asset}" "$binary_tmp"; then
    rm -f "$binary_tmp"
    echo "Error: failed to download ${RELEASE_BASE}/${version}/${asset}" >&2
    echo "  Make sure the release exists and, for private repos, GH_TOKEN is set." >&2
    exit 1
fi

chmod +x "$binary_tmp"
if ! "$binary_tmp" --version </dev/null >/dev/null 2>&1; then
    echo "Error: downloaded binary failed to run; keeping the existing install." >&2
    rm -f "$binary_tmp"
    exit 1
fi

mv -f "$binary_tmp" "$binary_path"
dest="$BIN_DIR/grok${exe}"
if [ -f "$dest" ]; then
    mv -f "$dest" "${dest}.old" 2>/dev/null || true
fi
if ! cp -f "$binary_path" "$dest"; then
    mv -f "${dest}.old" "$dest" 2>/dev/null || true
    echo "Error: failed to install $dest" >&2
    exit 1
fi
rm -f "${dest}.old"
chmod +x "$dest"
echo "  Installed grok ${version} to ${dest}" >&2

case ":$PATH:" in
    *":${BIN_DIR}:"*) : ;;
    *) echo "  Note: ${BIN_DIR} is not on your PATH. Add it, e.g. export PATH=\"${BIN_DIR}:\$PATH\"" >&2 ;;
esac
