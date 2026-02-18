#!/usr/bin/env bash
#
# build-waterfox-deb.sh — Download Waterfox and package it as a .deb
# Compatible with Debian 12 (Bookworm) and newer, x86_64
#
# Written on 2026-02-18 by GitHub Copilot (Claude Opus 4.6)
#
# Usage:
#   ./build-waterfox-deb.sh          # auto-detect latest, skip if up-to-date
#   ./build-waterfox-deb.sh 6.7.0    # build a specific version
#
# ── Changelog ────────────────────────────────────────────────────────────────
# 2026-02-18  v1.0  Initial release. Debian 13 (Trixie) only.
# 2026-02-18  v1.1  Auto-detect latest version from GitHub; skip if up-to-date.
# 2026-02-18  v1.2  Auto-install .deb after build; added Copilot instructions.
# 2026-02-18  v1.3  Debian 12+ support (auto-detect t64 library names);
#                    added credits, changelog.
#
# ── Copilot Instructions ─────────────────────────────────────────────────────
# • Target: Debian 12 (Bookworm) and newer, x86_64.
# • Source: upstream tarball from cdn.waterfox.com, version tracked via
#   GitHub API (BrowserWorks/Waterfox).
# • The tarball extracts to a folder named "waterfox" — installed to /opt/waterfox.
# • Symlink goes to /usr/local/bin/waterfox.
# • DEPENDS are built at runtime: Debian ≥13 uses t64-suffixed library
#   package names; Debian 12 uses the classic names. The get_depends()
#   function handles this. If Waterfox adds new library deps, update
#   both lists (check dependentlibs.list inside the tarball).
# • Version auto-detection uses the GitHub releases API; tag format may or
#   may not have a "G" prefix — the regex handles both.
# • After building the .deb, the script auto-installs it via `sudo apt install`.
# • The script is idempotent: re-running without args when already up-to-date
#   exits early with code 0.
# • Keep all paths POSIX-compatible; avoid bashisms outside [[ ]].
# • When modifying DEBIAN/control fields, keep the Description field's
#   continuation lines indented with exactly one leading space.
# • postinst/postrm refresh the desktop database and icon cache.
# ─────────────────────────────────────────────────────────────────────────────
#
set -euo pipefail

# ── Fetch latest version from GitHub releases ────────────────────────────────
get_latest_version() {
    local tag
    tag=$(curl -fsSL "https://api.github.com/repos/BrowserWorks/Waterfox/releases/latest" \
        | grep -oP '"tag_name"\s*:\s*"G?\K[0-9][^"]*')
    if [[ -z "$tag" ]]; then
        echo "ERROR: Could not determine latest Waterfox version from GitHub." >&2
        exit 1
    fi
    echo "$tag"
}

# ── Get currently installed version (empty if not installed) ─────────────────
get_installed_version() {
    dpkg-query -W -f='${Version}' waterfox 2>/dev/null || true
}

# ── Compare versions: returns 0 if $1 > $2 ──────────────────────────────────
version_gt() {
    [[ "$(printf '%s\n%s' "$1" "$2" | sort -V | tail -n1)" != "$2" ]]
}

# ── Detect Debian major version ──────────────────────────────────────────────
get_debian_major() {
    local ver
    if [[ -f /etc/debian_version ]]; then
        ver=$(cut -d. -f1 < /etc/debian_version)
        # Testing/unstable may say "trixie/sid" — map to 13
        if ! [[ "$ver" =~ ^[0-9]+$ ]]; then
            ver=13
        fi
    else
        echo "WARNING: /etc/debian_version not found, assuming Debian 13." >&2
        ver=13
    fi
    echo "$ver"
}

# ── Build dependency list based on Debian version ────────────────────────────
# Debian 13+ (Trixie) renamed several libraries with a t64 suffix as part of
# the 64-bit time_t transition. Debian 12 (Bookworm) uses the classic names.
get_depends() {
    local deb_major="$1"
    # Libraries that were renamed with t64 suffix in Debian 13
    local libasound libatk libglib libgtk
    if (( deb_major >= 13 )); then
        libasound="libasound2t64"
        libatk="libatk1.0-0t64"
        libglib="libglib2.0-0t64"
        libgtk="libgtk-3-0t64"
    else
        libasound="libasound2"
        libatk="libatk1.0-0"
        libglib="libglib2.0-0"
        libgtk="libgtk-3-0"
    fi
    echo "${libasound}, ${libatk}, libc6, libcairo-gobject2, libcairo2, libdbus-1-3, libfontconfig1, libfreetype6, libgcc-s1, libgdk-pixbuf-2.0-0, ${libglib}, ${libgtk}, libpango-1.0-0, libpangocairo-1.0-0, libstdc++6, libx11-6, libx11-xcb1, libxcb-shm0, libxcb1, libxcomposite1, libxcursor1, libxdamage1, libxext6, libxfixes3, libxi6, libxrandr2, libxrender1, libxtst6"
}

# ── Configuration ────────────────────────────────────────────────────────────
if [[ -n "${1:-}" ]]; then
    VERSION="$1"
else
    echo "==> No version specified, detecting latest …"
    VERSION=$(get_latest_version)
    echo "    Latest upstream version: ${VERSION}"

    INSTALLED=$(get_installed_version)
    if [[ -n "$INSTALLED" ]]; then
        echo "    Installed version:       ${INSTALLED}"
        if ! version_gt "$VERSION" "$INSTALLED"; then
            echo "==> Already up-to-date (${INSTALLED}). Nothing to do."
            exit 0
        fi
        echo "==> Newer version available, upgrading ${INSTALLED} → ${VERSION}"
    else
        echo "    Waterfox is not currently installed."
    fi
fi

ARCH="amd64"
PKG_NAME="waterfox"
MAINTAINER="Local Builder <nobody@localhost>"
DESCRIPTION="Waterfox — privacy-focused web browser (upstream binary)"
HOMEPAGE="https://www.waterfox.com"
SECTION="web"
PRIORITY="optional"

DEBIAN_MAJOR=$(get_debian_major)
if (( DEBIAN_MAJOR < 12 )); then
    echo "ERROR: This script requires Debian 12 or newer (detected: ${DEBIAN_MAJOR})." >&2
    exit 1
fi
echo "    Detected Debian:         ${DEBIAN_MAJOR}"
DEPENDS=$(get_depends "$DEBIAN_MAJOR")

DOWNLOAD_URL="https://cdn.waterfox.com/waterfox/releases/${VERSION}/Linux_x86_64/waterfox-${VERSION}.tar.bz2"
TARBALL="waterfox-${VERSION}.tar.bz2"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

DEB_ROOT="${WORK_DIR}/${PKG_NAME}_${VERSION}_${ARCH}"

echo "==> Building waterfox ${VERSION} .deb package"
echo "    Work directory: ${WORK_DIR}"

# ── Download ─────────────────────────────────────────────────────────────────
if [[ -f "$TARBALL" ]]; then
    echo "==> Tarball already present, skipping download"
else
    echo "==> Downloading ${DOWNLOAD_URL} …"
    wget -q --show-progress -O "$TARBALL" "$DOWNLOAD_URL"
fi

# ── Extract ──────────────────────────────────────────────────────────────────
echo "==> Extracting tarball …"
mkdir -p "${DEB_ROOT}/opt"
tar xjf "$TARBALL" -C "${DEB_ROOT}/opt"
# The tarball extracts to a directory called "waterfox"

# ── Symlink in /usr/local/bin ────────────────────────────────────────────────
mkdir -p "${DEB_ROOT}/usr/local/bin"
ln -sf /opt/waterfox/waterfox "${DEB_ROOT}/usr/local/bin/waterfox"

# ── Desktop entry ────────────────────────────────────────────────────────────
mkdir -p "${DEB_ROOT}/usr/share/applications"
cat > "${DEB_ROOT}/usr/share/applications/waterfox.desktop" <<'DESKTOP'
[Desktop Entry]
Version=1.0
Name=Waterfox
GenericName=Web Browser
Comment=Privacy-focused web browser
Exec=/opt/waterfox/waterfox %u
Icon=waterfox
Terminal=false
Type=Application
MimeType=text/html;text/xml;application/xhtml+xml;application/vnd.mozilla.xul+xml;text/mml;x-scheme-handler/http;x-scheme-handler/https;
Categories=Network;WebBrowser;
StartupNotify=true
StartupWMClass=waterfox
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=Open a New Window
Exec=/opt/waterfox/waterfox --new-window %u

[Desktop Action new-private-window]
Name=Open a New Private Window
Exec=/opt/waterfox/waterfox --private-window %u
DESKTOP

# ── Icons ────────────────────────────────────────────────────────────────────
# Install the bundled icon at standard sizes if available, and fall back to the
# main browser icon.
for size in 16 32 48 64 128; do
    icon_src="${DEB_ROOT}/opt/waterfox/browser/chrome/icons/default/default${size}.png"
    if [[ -f "$icon_src" ]]; then
        icon_dir="${DEB_ROOT}/usr/share/icons/hicolor/${size}x${size}/apps"
        mkdir -p "$icon_dir"
        cp "$icon_src" "${icon_dir}/waterfox.png"
    fi
done

# ── AppStream metadata (optional but nice) ───────────────────────────────────
mkdir -p "${DEB_ROOT}/usr/share/metainfo"
cat > "${DEB_ROOT}/usr/share/metainfo/waterfox.appdata.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>waterfox</id>
  <name>Waterfox</name>
  <summary>Privacy-focused web browser</summary>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>MPL-2.0</project_license>
  <url type="homepage">https://www.waterfox.com</url>
  <launchable type="desktop-id">waterfox.desktop</launchable>
</component>
XML

# ── DEBIAN control files ─────────────────────────────────────────────────────
mkdir -p "${DEB_ROOT}/DEBIAN"

# Compute installed size in KiB
INSTALLED_SIZE=$(du -sk "${DEB_ROOT}" | awk '{print $1}')

cat > "${DEB_ROOT}/DEBIAN/control" <<CTRL
Package: ${PKG_NAME}
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Installed-Size: ${INSTALLED_SIZE}
Depends: ${DEPENDS}
Section: ${SECTION}
Priority: ${PRIORITY}
Homepage: ${HOMEPAGE}
Description: ${DESCRIPTION}
 Waterfox is a free and open-source web browser based on Firefox,
 focused on privacy, customisation, and user choice.
CTRL

# postinst: update icon cache & desktop database
cat > "${DEB_ROOT}/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor || true
fi
POSTINST
chmod 0755 "${DEB_ROOT}/DEBIAN/postinst"

# postrm: clean up on removal
cat > "${DEB_ROOT}/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor || true
fi
POSTRM
chmod 0755 "${DEB_ROOT}/DEBIAN/postrm"

# ── Build .deb ───────────────────────────────────────────────────────────────
OUTPUT="${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo "==> Building ${OUTPUT} …"
dpkg-deb --build --root-owner-group "${DEB_ROOT}" "${OUTPUT}"

echo ""
echo "✔ Package built: $(pwd)/${OUTPUT}"

# ── Install .deb ─────────────────────────────────────────────────────────────
echo "==> Installing ${OUTPUT} …"
sudo apt install -y "./${OUTPUT}"
echo ""
echo "✔ Waterfox ${VERSION} installed successfully."
