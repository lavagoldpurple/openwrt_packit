#!/usr/bin/env bash
set -Eeuo pipefail

rootfs="$1"
rootfs_sha256="$2"
kernel_dir="$3"
kernel_version="$4"
board_dir="$5"
boot_dir="$6"

fail() { echo "E20C asset check: $*" >&2; exit 1; }

[[ -s "${rootfs}" ]] || fail "Rootfs archive is missing."
echo "${rootfs_sha256}  ${rootfs}" | sha256sum --check --status || fail "Rootfs SHA-256 mismatch."
tar -tzf "${rootfs}" >/dev/null || fail "Rootfs archive is invalid."

[[ -s "${kernel_dir}/sha256sums" ]] || fail "Kernel checksum manifest is missing."
for asset in "boot-${kernel_version}.tar.gz" "modules-${kernel_version}.tar.gz" "dtb-rockchip-${kernel_version}.tar.gz"; do
    [[ -s "${kernel_dir}/${asset}" ]] || fail "Required kernel asset is missing: ${asset}"
done
(cd "${kernel_dir}" && sha256sum --check --status sha256sums) || fail "Kernel checksum verification failed."
tar -tzf "${kernel_dir}/dtb-rockchip-${kernel_version}.tar.gz" |
    grep -E '(^|/)rk3528-radxa-e20c\.dtb$' >/dev/null || fail "E20C DTB is missing from the kernel archive."
for boot_file in "vmlinuz-${kernel_version}" "uInitrd-${kernel_version}"; do
    tar -tzf "${kernel_dir}/boot-${kernel_version}.tar.gz" |
        grep -Fx "${boot_file}" >/dev/null || fail "Kernel boot file is missing: ${boot_file}"
done
tar -tzf "${kernel_dir}/modules-${kernel_version}.tar.gz" |
    grep -E "(^|/)${kernel_version}/" >/dev/null || fail "Kernel modules directory is missing."

[[ -s "${board_dir}/idbloader.img" && -s "${board_dir}/u-boot.itb" ]] || fail "E20C bootloader files are missing."
[[ -s "${boot_dir}/boot.scr" ]] || fail "E20C boot script is missing."
