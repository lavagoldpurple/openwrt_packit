#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "${repo_dir}/public_funcs"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT
WORK_DIR="${fixture}"
TEMP_DIR="${fixture}/work"
TGT_ROOT="${TEMP_DIR}/root"
TGT_BOOT="${TEMP_DIR}/boot"
TGT_DEV="/dev/loop-test"
mkdir -p "${TGT_ROOT}" "${TGT_BOOT}"

mountpoint() { [[ "$1" == -q ]]; }
umount() {
    [[ "$(pwd)" == "${WORK_DIR}" ]] || return 1
    [[ "${FAIL_UNMOUNT:-0}" == 0 ]]
}
losetup() {
    printf '%s\n' "$*" >> "${fixture}/losetup.calls"
    [[ "$1" == -d && "$2" == "${TGT_DEV}" ]]
}

FAIL_UNMOUNT=1
if (cd "${TGT_ROOT}" && detach_loopdev 2>/dev/null); then
    echo 'Cleanup should fail if a mount cannot be unmounted.' >&2
    exit 1
fi
[[ -d "${TGT_ROOT}" && -d "${TGT_BOOT}" ]] || exit 1
[[ ! -e "${fixture}/losetup.calls" ]] || exit 1

FAIL_UNMOUNT=0
(cd "${TGT_ROOT}" && detach_loopdev)
[[ ! -e "${TEMP_DIR}" ]] || exit 1
[[ "$(cat "${fixture}/losetup.calls")" == "-d ${TGT_DEV}" ]] || exit 1
echo 'E20C cleanup checks passed.'
