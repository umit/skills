#!/usr/bin/env bash
# Install async-profiler for the current platform.
# Downloads the latest stable release and unpacks into $PREFIX (default ~/.local/share/async-profiler).
# Adds asprof and jfrconv to PATH via $PREFIX/bin symlinks.

set -euo pipefail

PREFIX="${ASYNC_PROFILER_PREFIX:-$HOME/.local/share/async-profiler}"
VERSION="${ASYNC_PROFILER_VERSION:-latest}"

detect_platform() {
    local os arch
    case "$(uname -s)" in
        Linux)  os="linux" ;;
        Darwin) os="macos" ;;
        *)      echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64) arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) echo "Unsupported arch: $(uname -m)" >&2; exit 1 ;;
    esac

    if [[ "$os" == "linux" ]] && ldd --version 2>&1 | grep -qi musl; then
        echo "${os}-musl-${arch}"
    elif [[ "$os" == "macos" ]]; then
        echo "${os}"
    else
        echo "${os}-${arch}"
    fi
}

resolve_version() {
    if [[ "$VERSION" != "latest" ]]; then
        echo "$VERSION"
        return
    fi
    curl -fsSL https://api.github.com/repos/async-profiler/async-profiler/releases/latest \
        | grep -m1 '"tag_name"' \
        | sed 's/.*"tag_name": *"v\?\([^"]*\)".*/\1/'
}

main() {
    local platform version url tmp
    platform=$(detect_platform)
    version=$(resolve_version)

    case "$platform" in
        macos) url="https://github.com/async-profiler/async-profiler/releases/download/v${version}/async-profiler-${version}-macos.zip" ;;
        *)     url="https://github.com/async-profiler/async-profiler/releases/download/v${version}/async-profiler-${version}-${platform}.tar.gz" ;;
    esac

    echo "Installing async-profiler ${version} for ${platform}"
    echo "Source: ${url}"
    echo "Target: ${PREFIX}"

    mkdir -p "$PREFIX" "$PREFIX/bin"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    if [[ "$url" == *.zip ]]; then
        curl -fsSL "$url" -o "$tmp/ap.zip"
        unzip -q "$tmp/ap.zip" -d "$tmp"
    else
        curl -fsSL "$url" | tar -xz -C "$tmp"
    fi

    local extracted
    extracted=$(find "$tmp" -maxdepth 1 -type d -name 'async-profiler-*' | head -1)
    if [[ -z "$extracted" ]]; then
        echo "Could not locate extracted directory" >&2
        exit 1
    fi

    rm -rf "$PREFIX/current"
    cp -R "$extracted" "$PREFIX/current"

    ln -sf "$PREFIX/current/bin/asprof" "$PREFIX/bin/asprof"
    if [[ -f "$PREFIX/current/bin/jfrconv" ]]; then
        ln -sf "$PREFIX/current/bin/jfrconv" "$PREFIX/bin/jfrconv"
    fi

    echo
    echo "Installed."
    echo "  asprof:   $PREFIX/bin/asprof"
    [[ -f "$PREFIX/bin/jfrconv" ]] && echo "  jfrconv:  $PREFIX/bin/jfrconv"
    echo "  lib dir:  $PREFIX/current/lib"
    echo
    echo "Add to PATH:"
    echo "  export PATH=\"$PREFIX/bin:\$PATH\""
    echo
    echo "Verify:"
    echo "  asprof version"
}

main "$@"
