#!/usr/bin/env bash
set -Eeuo pipefail

root="${1:?rootfs mount is required}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
lock="${repo}/files/mariadb/SHA256SUMS"
cache="${repo}/src1/mariadb"
feed_root='https://mirrors.tencent.com/lede/releases/24.10.3/packages/aarch64_generic'
stage="${root}/tmp/e20c-mariadb-packages"
offline_conf="${stage}/opkg.conf"

[[ "$(uname -m)" == aarch64 && "$(id -u)" == 0 ]] || {
    echo 'MariaDB packaging requires a root ARM64 Linux host.' >&2
    exit 1
}
[[ -x "${root}/bin/opkg" && -f "${root}/usr/lib/opkg/status" && -f "${root}/etc/opkg.conf" ]] || {
    echo 'Target rootfs is missing opkg or its package database.' >&2
    exit 1
}

mkdir -p "${cache}" "${stage}" "${root}/dev" "${root}/proc"
mounted_dev=0
mounted_proc=0
cleanup() {
    if ((mounted_proc)); then umount "${root}/proc"; fi
    if ((mounted_dev)); then umount "${root}/dev"; fi
    rm -rf -- "${stage}"
}
trap cleanup EXIT

count=0
declare -A seen=()
while read -r checksum filename; do
    [[ "${checksum}" =~ ^[0-9a-f]{64}$ && "${filename}" == *_aarch64_generic.ipk ]] || {
        echo "Invalid package lock entry: ${filename}" >&2
        exit 1
    }
    case "${filename}" in
        mariadb-client_11.4.8-r2_*|mariadb-server-base_11.4.8-r2_*|mariadb-server_11.4.8-r2_*|\
        libaio_0.3.113-r3_*|libedit_20250104.3.1-r1_*|libfmt_11.0.2-r1_*|sudo_1.9.17_p2-r1_*) feed="${feed_root}/packages" ;;
        wipefs_2.40.2-r1_*) feed="${feed_root}/base" ;;
        *) echo "Unexpected package in lock: ${filename}" >&2; exit 1 ;;
    esac
    [[ -z "${seen[${filename}]+x}" ]] || { echo "Duplicate package lock: ${filename}" >&2; exit 1; }
    seen["${filename}"]=1
    ((count+=1))
    if [[ ! -s "${cache}/${filename}" ]] ||
        ! (cd "${cache}" && printf '%s  %s\n' "${checksum}" "${filename}" | sha256sum -c --status 2>/dev/null); then
        curl --fail --location --retry 5 --retry-all-errors --retry-delay 5 \
            --output "${cache}/${filename}.part" "${feed}/${filename}"
        mv -f "${cache}/${filename}.part" "${cache}/${filename}"
    fi
    (cd "${cache}" && printf '%s  %s\n' "${checksum}" "${filename}" | sha256sum -c --status) || {
        echo "MariaDB package checksum mismatch: ${filename}" >&2
        exit 1
    }
    cp "${cache}/${filename}" "${stage}/${filename}"
done < "${lock}"
[[ "${count}" -eq 8 ]] || { echo 'Expected eight locked database and first-boot packages.' >&2; exit 1; }

mount --bind /dev "${root}/dev"
mounted_dev=1
mount -t proc proc "${root}/proc"
mounted_proc=1
grep -vE '^[[:space:]]*src([[:space:]]|/)' "${root}/etc/opkg.conf" > "${offline_conf}"
chroot "${root}" /bin/sh -c \
    'mkdir -p /var/lock &&
     opkg -f /tmp/e20c-mariadb-packages/opkg.conf install /tmp/e20c-mariadb-packages/*.ipk &&
     /usr/bin/mysqld --version && /usr/bin/mysql --version'
chroot "${root}" /usr/sbin/wipefs --version | grep -F '2.40.2' || {
    echo 'Pinned wipefs binary did not run correctly in the rootfs.' >&2
    exit 1
}
while read -r checksum filename; do
    package="${filename%%_*}"
    version="${filename#*_}"
    version="${version%_aarch64_generic.ipk}"
    chroot "${root}" /bin/opkg status "${package}" | grep -qx "Version: ${version}" || {
        echo "Installed package version mismatch: ${package}" >&2
        exit 1
    }
    chroot "${root}" /bin/opkg status "${package}" | grep -q '^Status: .* installed$' || {
        echo "Package is not installed: ${package}" >&2
        exit 1
    }
done < "${lock}"

umount "${root}/proc"
mounted_proc=0
umount "${root}/dev"
mounted_dev=0
rm -rf -- "${stage}"
trap - EXIT
