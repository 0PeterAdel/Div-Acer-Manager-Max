#!/usr/bin/env bash
# Build the complete stack from the owner's forks, using main by default.
set -Eeuo pipefail

case "${1:-}" in
    --help|-h)
        printf 'Usage: %s [--build-only]\n' "$0"
        printf 'Clone/update both 0PeterAdel forks on main, then rebuild and install.\n'
        printf 'Requires git, .NET 9 SDK, Python with venv/pip, make and running-kernel headers.\n'
        printf 'Overrides: DAMX_SOURCE_DIR, DAMX_APP_REPO, DAMX_DRIVER_REPO, DAMX_APP_REF, DAMX_DRIVER_REF.\n'
        exit 0 ;;
    --build-only|"") ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { printf 'Too many arguments\n' >&2; exit 2; }

SOURCE_DIR="${DAMX_SOURCE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/damx/sources}"
APP_REPO="${DAMX_APP_REPO:-https://github.com/0PeterAdel/Div-Acer-Manager-Max.git}"
DRIVER_REPO="${DAMX_DRIVER_REPO:-https://github.com/0PeterAdel/Div-Linuwu-Sense.git}"
APP_REF="${DAMX_APP_REF:-main}"
DRIVER_REF="${DAMX_DRIVER_REF:-main}"
command -v git >/dev/null || { printf 'git is required\n' >&2; exit 1; }
mkdir -p "$SOURCE_DIR"

update_source() {
    local path=$1 repo=$2 ref=$3
    if [[ ! -e "$path" ]]; then
        git clone --single-branch --branch "$ref" -- "$repo" "$path"
        return
    fi
    [[ -d "$path/.git" ]] || { printf 'Not a managed Git clone: %s\n' "$path" >&2; return 1; }
    [[ "$(git -C "$path" remote get-url origin)" == "$repo" ]] || {
        printf 'Unexpected origin in %s; use a separate DAMX_SOURCE_DIR.\n' "$path" >&2; return 1;
    }
    [[ "$(git -C "$path" branch --show-current)" == "$ref" ]] || {
        printf 'Expected branch %s in %s; use a separate DAMX_SOURCE_DIR.\n' "$ref" "$path" >&2; return 1;
    }
    [[ -z "$(git -C "$path" status --porcelain)" ]] || {
        printf 'Local changes found in %s; preserve them before updating.\n' "$path" >&2; return 1;
    }
    git -C "$path" fetch origin "$ref"
    git -C "$path" merge --ff-only FETCH_HEAD
}

update_source "$SOURCE_DIR/Div-Acer-Manager-Max" "$APP_REPO" "$APP_REF"
update_source "$SOURCE_DIR/Div-Linuwu-Sense" "$DRIVER_REPO" "$DRIVER_REF"
[[ -f "$SOURCE_DIR/Div-Acer-Manager-Max/scripts/reinstall-damx.sh" ]] &&
    grep -q 'u8 four_zone_static;' "$SOURCE_DIR/Div-Linuwu-Sense/src/linuwu_sense.c" || {
        printf 'Merge the complete lighting PRs into both fork branches before installing.\n' >&2
        exit 1
    }
export DAMX_APP_SOURCE="$SOURCE_DIR/Div-Acer-Manager-Max"
export DAMX_DRIVER_SOURCE="$SOURCE_DIR/Div-Linuwu-Sense"
exec bash "$DAMX_APP_SOURCE/scripts/reinstall-damx.sh" "$@"
