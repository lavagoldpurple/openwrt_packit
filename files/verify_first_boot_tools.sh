#!/usr/bin/env bash
set -Eeuo pipefail

root="${1:?rootfs mount is required}"
missing=()
for tool in findmnt parted partprobe blkid mountpoint mkfs.ext4 wipefs uci; do
    # Redirect on the host: an unbooted, read-only rootfs may have no /dev/null.
    if ! chroot "${root}" /bin/sh -c 'PATH=/usr/sbin:/usr/bin:/sbin:/bin; command -v "$1"' e20c-tool-check "${tool}" >/dev/null; then
        missing+=("${tool}")
    fi
done
if ((${#missing[@]})); then
    printf 'E20C packaging: missing first-boot tools in rootfs: %s\n' "${missing[*]}" >&2
    exit 1
fi
