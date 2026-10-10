#!/usr/bin/env bash

# Rebuild and reinstall the customized DAMX stack from local source trees.
# Local, uncommitted source edits are intentionally included.
# Includes the GUI, daemon, and driver together: Static/per-zone lighting,
# back logo/lightbar controls, fan writes, and saved GUI presets.
# New GUI features such as wallpaper color extraction are built from the same sources.

set -Eeuo pipefail

BUILD_ONLY=0
case "${1:-}" in
    --build-only) BUILD_ONLY=1; shift ;;
    --help|-h)
        printf 'Usage: %s [--build-only]\n' "$0"
        printf 'Rebuild the complete customized DAMX stack from local sources.\n'
        printf 'Use --build-only to validate all builds without installing.\n'
        printf 'Overrides: DAMX_APP_SOURCE, DAMX_DRIVER_SOURCE, DAMX_PRIVILEGE_TOOL (sudo/pkexec).\n'
        exit 0
        ;;
esac
[[ $# == 0 ]] || { printf 'Unknown argument: %s\n' "$1" >&2; exit 2; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_SOURCE="${DAMX_APP_SOURCE:-$(dirname -- "$SCRIPT_DIR")}"
DRIVER_SOURCE="${DAMX_DRIVER_SOURCE:-$(dirname -- "$APP_SOURCE")/Div-Linuwu-Sense}"
KERNEL_RELEASE="${DAMX_KERNEL_RELEASE:-$(uname -r)}"
INSTALL_DIR="/opt/damx"
SERVICE_NAME="damx-daemon.service"
LOG_FILE="${DAMX_REINSTALL_LOG:-${APP_SOURCE}/reinstall-damx.log}"
KEEP_BUILD="${DAMX_KEEP_BUILD:-0}"
PRIVILEGE_TOOL="${DAMX_PRIVILEGE_TOOL:-sudo}"
[[ "$BUILD_ONLY" == "0" ]] || KEEP_BUILD=1

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/damx-reinstall.XXXXXX")"
INSTALL_STARTED=0

exec > >(tee -a "$LOG_FILE") 2>&1

log() {
    printf '\n==> %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    local exit_code=$?

    if (( exit_code != 0 && INSTALL_STARTED == 1 )); then
        printf '\nReinstall failed after installation began. Attempting to start %s again.\n' "$SERVICE_NAME" >&2
        "${ROOT_RUN[@]}" /usr/bin/systemctl start "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi

    if [[ "$KEEP_BUILD" == "1" ]]; then
        printf 'Build staging directory retained at: %s\n' "$STAGE_DIR"
    else
        rm -rf -- "$STAGE_DIR"
    fi

    exit "$exit_code"
}
trap cleanup EXIT

if (( EUID == 0 )); then
    ROOT_RUN=()
else
    case "$PRIVILEGE_TOOL" in
        sudo)
            command -v sudo >/dev/null 2>&1 || die "sudo is required for installation"
            ROOT_RUN=(sudo)
            ;;
        pkexec)
            command -v pkexec >/dev/null 2>&1 || die "pkexec is required for desktop authentication"
            ROOT_RUN=(pkexec)
            ;;
        *)
            die "DAMX_PRIVILEGE_TOOL must be either sudo or pkexec"
            ;;
    esac
fi

for command_name in dotnet make python3 systemctl modprobe depmod install cmp tee; do
    command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: ${command_name}"
done

[[ -f "$APP_SOURCE/DAMM-Daemon/DAMX-Daemon.py" ]] || die "DAMX daemon source not found under $APP_SOURCE"
[[ -f "$APP_SOURCE/DivAcerManagerMax/DivAcerManagerMax.csproj" ]] || die "DAMX GUI project not found under $APP_SOURCE"
[[ -f "$DRIVER_SOURCE/src/linuwu_sense.c" ]] || die "linuwu_sense source not found under $DRIVER_SOURCE"
[[ -d "/lib/modules/${KERNEL_RELEASE}/build" ]] || die "Kernel headers are missing for ${KERNEL_RELEASE}"
if [[ "$BUILD_ONLY" == "0" && "$KERNEL_RELEASE" != "$(uname -r)" ]]; then
    die "Installation requires the running kernel; use --build-only for another kernel"
fi

PYINSTALLER_PYTHON=""
for candidate in \
    "$APP_SOURCE/DAMM-Daemon/.venv/bin/python" \
    "$APP_SOURCE/DAMM-Daemon/venv/bin/python"; do
    if [[ -x "$candidate" ]] && "$candidate" -c 'import PyInstaller' >/dev/null 2>&1; then
        PYINSTALLER_PYTHON="$candidate"
        break
    fi
done
if [[ -z "$PYINSTALLER_PYTHON" ]]; then
    log "Preparing the daemon build virtual environment"
    python3 -m venv "$APP_SOURCE/DAMM-Daemon/.venv"
    PYINSTALLER_PYTHON="$APP_SOURCE/DAMM-Daemon/.venv/bin/python"
    "$PYINSTALLER_PYTHON" -m pip install -r "$APP_SOURCE/DAMM-Daemon/requirements-build.txt"
fi

TARGET_USER="${SUDO_USER:-${USER:-}}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    TARGET_USER="$(stat -c '%U' "$SCRIPT_DIR")"
fi

KERNEL_MAKE_ARGS=("KVER=${KERNEL_RELEASE}")
if grep -q '^CONFIG_CC_IS_CLANG=y' "/lib/modules/${KERNEL_RELEASE}/build/.config" 2>/dev/null; then
    command -v clang >/dev/null 2>&1 || die "This kernel requires clang, but clang is not installed"
    KERNEL_MAKE_ARGS+=("LLVM=1" "CC=clang")
fi

secure_boot_enabled() {
    if [[ -r /sys/module/module/parameters/sig_enforce ]] &&
       grep -qiE '^(1|y|yes)$' /sys/module/module/parameters/sig_enforce; then
        return 0
    fi

    if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
        return 0
    fi

    return 1
}

log "DAMX customized source reinstall"
printf 'App source:    %s\n' "$APP_SOURCE"
printf 'Driver source: %s\n' "$DRIVER_SOURCE"
printf 'Kernel:        %s\n' "$KERNEL_RELEASE"
printf 'Target user:   %s\n' "$TARGET_USER"
printf 'Log:           %s\n' "$LOG_FILE"

if command -v git >/dev/null 2>&1; then
    log "App working-tree changes included in this build"
    git -C "$APP_SOURCE" status --short || true
    log "Driver working-tree changes included in this build"
    git -C "$DRIVER_SOURCE" status --short || true
fi

log "Building customized DAMX daemon"
mkdir -p "$STAGE_DIR/daemon" "$STAGE_DIR/pyinstaller-build"
(
    cd "$APP_SOURCE/DAMM-Daemon"
    "$PYINSTALLER_PYTHON" -m PyInstaller \
        --onefile \
        --clean \
        --noconfirm \
        --distpath "$STAGE_DIR/daemon" \
        --workpath "$STAGE_DIR/pyinstaller-build" \
        --specpath "$STAGE_DIR" \
        DAMX-Daemon.py
)
[[ -x "$STAGE_DIR/daemon/DAMX-Daemon" ]] || die "Daemon build did not produce an executable"

log "Building customized DAMX GUI"
mkdir -p "$STAGE_DIR/gui"
dotnet publish "$APP_SOURCE/DivAcerManagerMax/DivAcerManagerMax.csproj" \
    -c Release \
    -f net9.0 \
    -r linux-x64 \
    --self-contained true \
    -o "$STAGE_DIR/gui" \
    -p:PublishSingleFile=true \
    -p:IncludeNativeLibrariesForSelfExtract=true \
    -p:IncludeAllContentForSelfExtract=true
[[ -x "$STAGE_DIR/gui/DivAcerManagerMax" ]] || die "GUI build did not produce an executable"

log "Building customized linuwu_sense module"
make -C "$DRIVER_SOURCE" "${KERNEL_MAKE_ARGS[@]}" clean
make -C "$DRIVER_SOURCE" "${KERNEL_MAKE_ARGS[@]}" -j"$(nproc)"
[[ -f "$DRIVER_SOURCE/src/linuwu_sense.ko" ]] || die "Driver build did not produce linuwu_sense.ko"
install -m 0644 "$DRIVER_SOURCE/src/linuwu_sense.ko" "$STAGE_DIR/linuwu_sense.ko"

log "Recording source versions and built artifacts"
python3 - "$APP_SOURCE" "$DRIVER_SOURCE" "$STAGE_DIR" "$KERNEL_RELEASE" <<'PY'
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

app, driver, stage, kernel = sys.argv[1:]
def version(path):
    def git(*args):
        result = subprocess.run(['git', '-C', path, *args], capture_output=True, text=True)
        return result.stdout.strip() if result.returncode == 0 else None
    return {'path': path, 'commit': git('rev-parse', 'HEAD'),
            'branch': git('branch', '--show-current'),
            'tracked_changes': git('status', '--short', '--untracked-files=no')}
artifacts = ['daemon/DAMX-Daemon', 'gui/DivAcerManagerMax', 'linuwu_sense.ko']
info = {'built_at': datetime.now(timezone.utc).isoformat(), 'kernel': kernel,
        'app': version(app), 'driver': version(driver),
        'sha256': {name: hashlib.sha256((Path(stage) / name).read_bytes()).hexdigest()
                   for name in artifacts}}
(Path(stage) / 'build-info.json').write_text(json.dumps(info, indent=2) + '\n')
print(json.dumps(info, indent=2))
PY

if [[ "$BUILD_ONLY" == "1" ]]; then
    log "All three builds passed; no installation requested"
    exit 0
fi

cat > "$STAGE_DIR/damx-daemon.service" <<'EOF'
[Unit]
Description=DAMX Daemon for Acer laptops
After=network.target

[Service]
Type=simple
ExecStart=/opt/damx/daemon/DAMX-Daemon
Restart=on-failure
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

cat > "$STAGE_DIR/DAMX" <<'EOF'
#!/usr/bin/env bash
exec /opt/damx/gui/DivAcerManagerMax "$@"
EOF

cat > "$STAGE_DIR/damx.desktop" <<'EOF'
[Desktop Entry]
Name=DAMX
Comment=Div Acer Manager Max
Exec=/opt/damx/gui/DivAcerManagerMax
Icon=damx
Terminal=false
Type=Application
Categories=Utility;System;
Keywords=acer;predator;laptop;fan;keyboard;
EOF

cat > "$STAGE_DIR/install-root.sh" <<'ROOT_INSTALL'
#!/usr/bin/env bash
set -Eeuo pipefail

stage_dir=$1
driver_source=$2
kernel_release=$3
install_dir=$4
target_user=$5
icon_source=$6
secure_boot_required=$7
module_name=linuwu_sense
module_dir="/lib/modules/${kernel_release}/kernel/drivers/platform/x86"

if [[ "$secure_boot_required" == "1" ]]; then
    sign_file="/lib/modules/${kernel_release}/build/scripts/sign-file"
    signing_key="/var/lib/damx/secureboot/DAMX-MOK.priv"
    signing_cert="/var/lib/damx/secureboot/DAMX-MOK.der"
    [[ -x "$sign_file" ]] || { echo "Secure Boot sign-file tool is missing" >&2; exit 1; }
    [[ -r "$signing_key" ]] || { echo "Secure Boot key is missing: $signing_key" >&2; exit 1; }
    [[ -r "$signing_cert" ]] || { echo "Secure Boot certificate is missing: $signing_cert" >&2; exit 1; }
    "$sign_file" sha256 "$signing_key" "$signing_cert" "$stage_dir/linuwu_sense.ko"
fi

# Preserve the lighting selected in DAMX across the module reload. Static
# uses zone colors; its global effect RGB registers are intentionally zero.
python3 - "$stage_dir/lighting-before.json" <<'PY'
import json
from pathlib import Path
import sys
base = Path('/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/four_zoned_kb')
state = {name: (base / name).read_text().strip()
         for name in ('four_zone_mode', 'per_zone_mode') if (base / name).exists()}
logo = base.parent / 'back_logo' / 'color'
if logo.exists():
    state['back_logo'] = logo.read_text().strip()
Path(sys.argv[1]).write_text(json.dumps(state))
PY

backup_dir=$(mktemp -d /var/tmp/damx-backup.XXXXXX)
paths=(
    "$module_dir/linuwu_sense.ko" "$install_dir/daemon/DAMX-Daemon"
    "$install_dir/gui/DivAcerManagerMax" "$install_dir/build-info.json"
    /etc/modprobe.d/blacklist-acer_wmi.conf /etc/modules-load.d/linuwu_sense.conf
    /etc/systemd/system/linuwu_sense.service /etc/systemd/system/damx-daemon.service
    /etc/tmpfiles.d/linuwu_sense.conf /usr/local/bin/DAMX
    /usr/share/applications/damx.desktop /usr/share/icons/hicolor/256x256/apps/damx.png
    /etc/four_zone_kb_state /etc/predator_state
)
for path in "${paths[@]}"; do
    if [[ -e "$path" ]]; then
        cp -a --parents "$path" "$backup_dir"
    fi
done
cp "$stage_dir/lighting-before.json" "$backup_dir/lighting-before.json"
printf 'Previous installation backed up at: %s\n' "$backup_dir"

rollback() {
    local exit_code=$?
    trap - ERR
    set +e
    printf 'Installation failed; restoring previous binaries and configuration.\n' >&2
    systemctl stop damx-daemon.service
    modprobe -r "$module_name"
    for path in "${paths[@]}"; do
        if [[ -e "$backup_dir$path" ]]; then
            cp -a "$backup_dir$path" "$path"
        else
            rm -f -- "$path"
        fi
    done
    depmod -a "$kernel_release"
    modprobe "$module_name"
    systemd-tmpfiles --create /etc/tmpfiles.d/linuwu_sense.conf
    systemctl daemon-reload
    systemctl start damx-daemon.service
    exit "$exit_code"
}
trap rollback ERR

systemctl stop damx-daemon.service
if grep -q '^linuwu_sense ' /proc/modules; then
    modprobe -r "$module_name"
fi
if grep -q '^acer_wmi ' /proc/modules; then
    modprobe -r acer_wmi
fi

install -d -m 0755 "$module_dir"
install -m 0644 "$stage_dir/linuwu_sense.ko" "$module_dir/linuwu_sense.ko"
printf 'blacklist acer_wmi\n' > /etc/modprobe.d/blacklist-acer_wmi.conf
printf 'linuwu_sense\n' > /etc/modules-load.d/linuwu_sense.conf
depmod -a "$kernel_release"
modprobe "$module_name"

install -m 0644 "$driver_source/linuwu_sense.service" /etc/systemd/system/linuwu_sense.service
if ! getent group linuwu_sense >/dev/null; then
    groupadd linuwu_sense
fi
if [[ -n "$target_user" && "$target_user" != "root" ]]; then
    usermod -aG linuwu_sense "$target_user"
fi

sysfs_base="/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi"
model_dir=""
for candidate in "$sysfs_base/predator_sense" "$sysfs_base/nitro_sense"; do
    if [[ -d "$candidate" ]]; then
        model_dir="$candidate"
        break
    fi
done

tmpfiles_conf=/etc/tmpfiles.d/linuwu_sense.conf
: > "$tmpfiles_conf"
if [[ -n "$model_dir" ]]; then
    for feature in backlight_timeout battery_calibration battery_limiter boot_animation_sound fan_speed lcd_override usb_charging; do
        if [[ -e "$model_dir/$feature" ]]; then
            printf 'f %s 0660 root linuwu_sense - -\n' "$model_dir/$feature" >> "$tmpfiles_conf"
        fi
    done
fi
for feature_path in \
    "$sysfs_base/four_zoned_kb/four_zone_mode" \
    "$sysfs_base/four_zoned_kb/per_zone_mode" \
    "$sysfs_base/back_logo/color"; do
    if [[ -e "$feature_path" ]]; then
        printf 'f %s 0660 root linuwu_sense - -\n' "$feature_path" >> "$tmpfiles_conf"
    fi
done
systemd-tmpfiles --create "$tmpfiles_conf"

python3 - "$stage_dir/lighting-before.json" <<'PY'
import json
from pathlib import Path
import sys
state = json.loads(Path(sys.argv[1]).read_text())
base = Path('/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/four_zoned_kb')
effect = state.get('four_zone_mode', '')
name = 'per_zone_mode' if effect.split(',')[0] == '0' and 'per_zone_mode' in state else 'four_zone_mode'
if name in state and (base / name).exists():
    (base / name).write_text(state[name] + '\n')
    actual = (base / name).read_text().strip()
    if actual != state[name]:
        raise SystemExit(f'Lighting restore mismatch: {actual} != {state[name]}')
    print('Keyboard lighting preserved:', actual)
logo = base.parent / 'back_logo' / 'color'
if 'back_logo' in state and logo.exists():
    logo.write_text(state['back_logo'] + '\n')
    actual = logo.read_text().strip()
    if actual != state['back_logo']:
        raise SystemExit(f'Back logo restore mismatch: {actual} != {state["back_logo"]}')
    print('Back logo lighting preserved:', actual)
PY

install -d -m 0755 "$install_dir/daemon" "$install_dir/gui"
install -m 0755 "$stage_dir/daemon/DAMX-Daemon" "$install_dir/daemon/DAMX-Daemon"
install -m 0755 "$stage_dir/gui/DivAcerManagerMax" "$install_dir/gui/DivAcerManagerMax"
install -m 0644 "$stage_dir/build-info.json" "$install_dir/build-info.json"

if [[ -f "$icon_source" ]]; then
    install -d -m 0755 /usr/share/icons/hicolor/256x256/apps
    install -m 0644 "$icon_source" /usr/share/icons/hicolor/256x256/apps/damx.png
fi

install -m 0644 "$stage_dir/damx-daemon.service" /etc/systemd/system/damx-daemon.service
install -m 0755 "$stage_dir/DAMX" /usr/local/bin/DAMX
install -m 0644 "$stage_dir/damx.desktop" /usr/share/applications/damx.desktop
systemctl daemon-reload
systemctl enable linuwu_sense.service
systemctl start linuwu_sense.service
systemctl enable --now damx-daemon.service
cmp -s "$stage_dir/linuwu_sense.ko" "$module_dir/linuwu_sense.ko"
trap - ERR
ROOT_INSTALL
chmod 0755 "$STAGE_DIR/install-root.sh"

SECURE_BOOT_REQUIRED=0
if secure_boot_enabled; then
    SECURE_BOOT_REQUIRED=1
fi

ICON_SOURCE="$APP_SOURCE/DivAcerManagerMax/icon.png"

log "All builds passed; beginning system installation"
INSTALL_STARTED=1
"${ROOT_RUN[@]}" /usr/bin/bash "$STAGE_DIR/install-root.sh" \
    "$STAGE_DIR" \
    "$DRIVER_SOURCE" \
    "$KERNEL_RELEASE" \
    "$INSTALL_DIR" \
    "$TARGET_USER" \
    "$ICON_SOURCE" \
    "$SECURE_BOOT_REQUIRED"

log "Verifying installed DAMX stack"
cmp -s "$STAGE_DIR/daemon/DAMX-Daemon" "$INSTALL_DIR/daemon/DAMX-Daemon" || die "Installed daemon differs from the new build"
cmp -s "$STAGE_DIR/gui/DivAcerManagerMax" "$INSTALL_DIR/gui/DivAcerManagerMax" || die "Installed GUI differs from the new build"
cmp -s "$STAGE_DIR/linuwu_sense.ko" "/lib/modules/${KERNEL_RELEASE}/kernel/drivers/platform/x86/linuwu_sense.ko" || die "Installed driver differs from the new build"
grep -q '^linuwu_sense ' /proc/modules || die "linuwu_sense is not loaded"
systemctl is-active --quiet "$SERVICE_NAME" || die "$SERVICE_NAME is not active"

for _ in {1..20}; do
    [[ -S /var/run/DAMX.sock ]] && break
    sleep 0.25
done
[[ -S /var/run/DAMX.sock ]] || die "DAMX daemon socket was not created"

python3 - <<'PY'
import json
import socket

client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.settimeout(5)
client.connect("/var/run/DAMX.sock")
client.sendall(json.dumps({"command": "get_supported_features", "params": {}}).encode())
response = json.loads(client.recv(65536).decode())
client.close()

if not response.get("success"):
    raise SystemExit(f"DAMX daemon health check failed: {response}")

features = response.get("data", {}).get("available_features", [])
if not features:
    raise SystemExit(f"DAMX daemon returned no hardware features: {response}")

print("Daemon health check passed. Features:", ", ".join(sorted(features)))
PY

INSTALL_STARTED=0
log "DAMX reinstall completed successfully"
printf 'Run the GUI with: DAMX\n'
printf 'Reinstall again with: %s\n' "$SCRIPT_DIR/reinstall-damx.sh"
printf 'Installed build provenance: %s/build-info.json\n' "$INSTALL_DIR"
