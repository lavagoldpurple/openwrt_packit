#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
verify="${repo_dir}/files/verify_e20c_assets.sh"
board_dir="${repo_dir}/files/rk3528/e20c"
boot_dir="${repo_dir}/files/bootfiles/rockchip/rk3528/e20c"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT
version="6.1.141-test"

mkdir -p "${fixture}/rootfs/etc" "${fixture}/boot" "${fixture}/dtb" \
    "${fixture}/modules/${version}" "${fixture}/kernel"
printf 'OpenWrt\n' > "${fixture}/rootfs/etc/release"
printf 'kernel\n' > "${fixture}/boot/vmlinuz-${version}"
printf 'initrd\n' > "${fixture}/boot/uInitrd-${version}"
printf 'e20c\n' > "${fixture}/dtb/rk3528-radxa-e20c.dtb"
printf 'module\n' > "${fixture}/modules/${version}/module.ko"
tar -czf "${fixture}/rootfs.tar.gz" -C "${fixture}/rootfs" .
tar -czf "${fixture}/kernel/boot-${version}.tar.gz" -C "${fixture}/boot" \
    "vmlinuz-${version}" "uInitrd-${version}"
tar -czf "${fixture}/kernel/dtb-rockchip-${version}.tar.gz" -C "${fixture}/dtb" \
    rk3528-radxa-e20c.dtb
tar -czf "${fixture}/kernel/modules-${version}.tar.gz" -C "${fixture}/modules" "${version}"
(cd "${fixture}/kernel" && sha256sum ./*.tar.gz > sha256sums)
hash="$(sha256sum "${fixture}/rootfs.tar.gz" | cut -d ' ' -f 1)"

check() {
    bash "${verify}" "$1" "$2" "${fixture}/kernel" "${version}" "${board_dir}" "${boot_dir}"
}
expect_failure() {
    local expected="$1" output
    shift
    if output="$(check "$@" 2>&1)"; then
        echo "Expected validation to fail: ${expected}" >&2
        exit 1
    fi
    [[ "${output}" == *"${expected}"* ]] || {
        echo "Unexpected validation error: ${output}" >&2
        exit 1
    }
}

check "${fixture}/rootfs.tar.gz" "${hash}"
expect_failure 'Rootfs archive is missing' "${fixture}/missing.tar.gz" "${hash}"
expect_failure 'Rootfs SHA-256 mismatch' "${fixture}/rootfs.tar.gz" "$(printf '%064d' 0)"
mv "${fixture}/kernel/boot-${version}.tar.gz" "${fixture}/boot.tar.gz.saved"
expect_failure 'Required kernel asset is missing' "${fixture}/rootfs.tar.gz" "${hash}"
mv "${fixture}/boot.tar.gz.saved" "${fixture}/kernel/boot-${version}.tar.gz"
printf 'corrupt\n' >> "${fixture}/kernel/boot-${version}.tar.gz"
expect_failure 'Kernel checksum verification failed' "${fixture}/rootfs.tar.gz" "${hash}"
tar -czf "${fixture}/kernel/boot-${version}.tar.gz" -C "${fixture}/boot" \
    "vmlinuz-${version}" "uInitrd-${version}"
printf 'other\n' > "${fixture}/dtb/rk3528-other.dtb"
tar -czf "${fixture}/kernel/dtb-rockchip-${version}.tar.gz" -C "${fixture}/dtb" rk3528-other.dtb
(cd "${fixture}/kernel" && sha256sum ./*.tar.gz > sha256sums)
expect_failure 'E20C DTB is missing' "${fixture}/rootfs.tar.gz" "${hash}"
echo 'E20C asset checks passed.'
