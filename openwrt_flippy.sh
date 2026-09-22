#!/usr/bin/env bash
set -Eeuo pipefail

ROOTFS_URL="https://github.com/ophub/flippy-openwrt-actions/releases/download/OpenWrt_armv8_save_2026.08/openwrt-armsr-armv8-generic-rootfs.tar.gz"
ROOTFS_SHA256="35ea000b2cca9ac4efb1c5143a0ea8bc496d365c8c926781dfdcbcf4fefbfae9"
KERNEL_VERSION="6.1.141-rk35xx-flippy-2603a"
KERNEL_URL="https://github.com/ophub/kernel/releases/download/kernel_rk35xx/${KERNEL_VERSION}.tar.gz"

PACKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS_NAME="openwrt-armsr-armv8-generic-rootfs.tar.gz"
ROOTFS_DIR="${PACKIT_DIR}/src1"
KERNEL_PKG_HOME="/opt/kernel"
KERNEL_ARCHIVE="${KERNEL_PKG_HOME}/${KERNEL_VERSION}.tar.gz"
KERNEL_EXTRACT_DIR="${KERNEL_PKG_HOME}/rk35xx"
OUTPUT_DIR="${PACKIT_DIR}/output"

fail() { echo "E20C packaging: $*" >&2; exit 1; }

[[ "$(uname -s)" == Linux ]] || fail "Linux is required."
[[ "$(id -u)" -eq 0 ]] || fail "Run as root (sudo)."
cd "${PACKIT_DIR}"
mkdir -p "${ROOTFS_DIR}" "${KERNEL_EXTRACT_DIR}" "${OUTPUT_DIR}"

download() {
    local url="$1" destination="$2"
    curl --fail --location --retry 5 --retry-all-errors --retry-delay 5 \
        --continue-at - --output "${destination}.part" "${url}"
    mv -f "${destination}.part" "${destination}"
}

rootfs="${ROOTFS_DIR}/${ROOTFS_NAME}"
[[ -s "${rootfs}" ]] || download "${ROOTFS_URL}" "${rootfs}"

[[ -s "${KERNEL_ARCHIVE}" ]] || download "${KERNEL_URL}" "${KERNEL_ARCHIVE}"
tar -tzf "${KERNEL_ARCHIVE}" >/dev/null || fail "Kernel archive is invalid."
tar -xzf "${KERNEL_ARCHIVE}" -C "${KERNEL_EXTRACT_DIR}"
kernel_dir="${KERNEL_EXTRACT_DIR}/${KERNEL_VERSION}"
bash "${PACKIT_DIR}/files/verify_e20c_assets.sh" "${rootfs}" "${ROOTFS_SHA256}" \
    "${kernel_dir}" "${KERNEL_VERSION}" "${PACKIT_DIR}/files/rk3528/e20c" \
    "${PACKIT_DIR}/files/bootfiles/rockchip/rk3528/e20c"

for asset in "boot-${KERNEL_VERSION}.tar.gz" "modules-${KERNEL_VERSION}.tar.gz" "dtb-rockchip-${KERNEL_VERSION}.tar.gz"; do
    cp -f "${kernel_dir}/${asset}" "${KERNEL_PKG_HOME}/${asset}"
done

export KERNEL_VERSION KERNEL_PKG_HOME
./mk_rk3528_e20c.sh

shopt -s nullglob
images=("${OUTPUT_DIR}"/openwrt_rk3528_e20c_*.img)
[[ "${#images[@]}" -eq 1 && -s "${images[0]}" ]] || fail "Expected exactly one non-empty E20C image."
parted -s "${images[0]}" print >/dev/null || fail "E20C image partition table is invalid."

verify_dir="$(mktemp -d)"
mkdir -p "${verify_dir}/boot" "${verify_dir}/root"
loopdev="$(losetup --find --show --partscan --read-only "${images[0]}")"
cleanup_verify() {
    if mountpoint -q "${verify_dir}/root"; then umount "${verify_dir}/root"; fi
    if mountpoint -q "${verify_dir}/boot"; then umount "${verify_dir}/boot"; fi
    losetup -d "${loopdev}"
    rmdir "${verify_dir}/boot" "${verify_dir}/root" "${verify_dir}" 2>/dev/null || true
}
trap cleanup_verify EXIT
mount -o ro "${loopdev}p1" "${verify_dir}/boot"
mount -o ro "${loopdev}p2" "${verify_dir}/root"
[[ -s "${verify_dir}/boot/Image" && -s "${verify_dir}/boot/uInitrd" ]] || fail "Kernel boot files are missing from the image."
[[ -s "${verify_dir}/boot/dtb/rockchip/rk3528-radxa-e20c.dtb" ]] || fail "E20C DTB is missing from the image."
[[ -s "${verify_dir}/root/etc/board.d/00_model" ]] || fail "E20C board configuration is missing from the image."
grep -q 'radxa,e20c' "${verify_dir}/root/etc/board.d/00_model" || fail "Unexpected board configuration."
for specification in 'idbloader.img:64' 'u-boot.itb:16384'; do
    file="${specification%:*}"
    offset="${specification#*:}"
    size="$(stat -c '%s' "files/rk3528/e20c/${file}")"
    count="$(( (size + 511) / 512 ))"
    cmp -n "${size}" "files/rk3528/e20c/${file}" \
        <(dd if="${images[0]}" bs=512 skip="${offset}" count="${count}" status=none) || fail "Bootloader verification failed: ${file}"
done
cleanup_verify
trap - EXIT

pigz -f "${images[0]}"
(cd "${OUTPUT_DIR}" && sha256sum ./*.img.gz > SHA256SUMS)
echo "E20C image and SHA256SUMS are in ${OUTPUT_DIR}."
