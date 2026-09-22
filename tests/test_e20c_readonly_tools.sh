#!/usr/bin/env bash
set -Eeuo pipefail

[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    echo 'This test requires root on Linux and busybox-static.' >&2
    exit 1
}
repo="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d)"
root="${fixture}/root"
cleanup() {
    if mountpoint -q "${root}"; then umount "${root}" || return 1; fi
    rm -rf -- "${fixture}"
}
trap cleanup EXIT
mkdir -p "${root}/bin" "${root}/usr/sbin" "${root}/dev"
cp "$(command -v busybox)" "${root}/bin/busybox"
ln -s busybox "${root}/bin/sh"
# These executable stand-ins test command discovery, not disk operations.
for tool in findmnt parted fdisk partprobe blkid mountpoint mkfs.ext4 wipefs uci; do
    ln -s /bin/busybox "${root}/usr/sbin/${tool}"
done
mount --bind "${root}" "${root}"
mount -o remount,bind,ro "${root}"

# Reproduce the old failure: /dev exists but /dev/null has not been created.
if chroot "${root}" /bin/sh -c 'command -v sh >/dev/null' 2>"${fixture}/old.error"; then
    echo 'Expected the old check to fail in an unbooted read-only rootfs.' >&2
    exit 1
fi
grep -q '/dev/null' "${fixture}/old.error"
bash "${repo}/files/verify_first_boot_tools.sh" "${root}"
[[ ! -e "${root}/dev/null" ]]

umount "${root}"
rm "${root}/usr/sbin/fdisk" "${root}/usr/sbin/blkid" "${root}/usr/sbin/wipefs"
mount --bind "${root}" "${root}"
mount -o remount,bind,ro "${root}"
if output="$(bash "${repo}/files/verify_first_boot_tools.sh" "${root}" 2>&1)"; then
    echo 'Tool validation accepted missing tools.' >&2
    exit 1
fi
[[ "${output}" == *'fdisk'* && "${output}" == *'blkid wipefs'* ]] || {
    echo "Expected all three missing tools to be reported: ${output}" >&2
    exit 1
}
echo 'E20C read-only chroot checks passed.'
