# Installing the combined fork

This fork combines the PHN16-72 back logo/lightbar controls, true Static
keyboard lighting, wallpaper color selection, fan write fix, and the latest
upstream fixes. The companion driver is in
[0PeterAdel/Div-Linuwu-Sense](https://github.com/0PeterAdel/Div-Linuwu-Sense).

Merge the complete lighting PR in **each fork** into its `main` branch first.
Then install or update from those two `main` branches:

```bash
git clone https://github.com/0PeterAdel/Div-Acer-Manager-Max.git
cd Div-Acer-Manager-Max
bash scripts/setup-fork.sh
```

Run as your desktop user; the installer requests sudo only for system
installation. It requires the .NET 9 SDK, Python with venv/pip, make, GCC
(or Clang for a Clang-built kernel), systemd, and matching running-kernel
headers. PyInstaller is installed automatically into a local virtual
environment. Secure Boot installations require an already enrolled DAMX
signing key under `/var/lib/damx/secureboot`.

The script keeps managed clones in `~/.local/share/damx/sources` (respecting
`XDG_DATA_HOME`). It updates only clean checkouts of the configured branches
with a fast-forward merge; it never switches branches or discards local edits.
Repeat the same command after merging future changes. Releases published by
the upstream repository do not include unmerged changes from this fork.
The packaging workflow also selects the driver's `main` branch from the same
GitHub owner. The legacy release installers point to `0PeterAdel` and require
a release published in this fork; the source installer does not require one.

For local development, build and reinstall your own source trees directly:

```bash
DAMX_DRIVER_SOURCE=/path/to/Div-Linuwu-Sense bash scripts/reinstall-damx.sh
```

Both entry points accept `--build-only` to build the GUI, daemon and module
without installing. The full installer backs up replaced files, records
source commits and binary hashes in `/opt/damx/build-info.json`, verifies the
loaded module and daemon, and preserves keyboard and back logo colors across
the module reload. Saved GUI presets stay in the user's existing settings.

Optional overrides: `DAMX_SOURCE_DIR`, `DAMX_APP_REPO`, `DAMX_DRIVER_REPO`,
`DAMX_APP_REF`, `DAMX_DRIVER_REF`, `DAMX_PRIVILEGE_TOOL` (`sudo` or `pkexec`).
The default repositories belong to `0PeterAdel`; both default branches are
`main`.
