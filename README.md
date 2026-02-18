# waterfox-deb

Build a `.deb` package from the official [Waterfox](https://www.waterfox.com/) Linux tarball.

## Features

- Downloads the upstream Waterfox binary tarball and packages it as a proper `.deb`
- Auto-detects the latest version from GitHub — skips if already up-to-date
- Installs the `.deb` automatically after building
- Desktop entry, icons, and AppStream metadata included
- Compatible with **Debian 12 (Bookworm)** and newer (auto-detects `t64` library naming)

## Usage

```bash
# Install/update to the latest version:
./build-waterfox-deb.sh

# Build a specific version:
./build-waterfox-deb.sh 6.7.0
```

### Requirements

- Debian 12+ (x86_64)
- `wget`, `curl`, `dpkg-deb` (all standard on Debian)
- `sudo` access (for `apt install`)

## How it works

1. Queries the [BrowserWorks/Waterfox](https://github.com/BrowserWorks/Waterfox) GitHub releases API for the latest version
2. Compares against the currently installed version (via `dpkg-query`)
3. Downloads the tarball from `cdn.waterfox.com` (skips if already cached locally)
4. Builds a `.deb` with files in `/opt/waterfox`, a symlink in `/usr/local/bin`, a `.desktop` entry, and icons
5. Installs the package via `sudo apt install`

## Uninstall

```bash
sudo apt remove waterfox
```

## License

MIT
