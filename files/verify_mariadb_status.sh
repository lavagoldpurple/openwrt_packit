#!/usr/bin/env bash
set -Eeuo pipefail

status="${1:?opkg status file is required}"
lock="${2:?MariaDB package lock is required}"
[[ -s "${status}" && -s "${lock}" ]] || {
    echo 'MariaDB validation: package status or lock file is missing.' >&2
    exit 1
}

count=0
while read -r checksum filename; do
    [[ "${checksum}" =~ ^[0-9a-f]{64}$ && "${filename}" == *_aarch64_generic.ipk ]] || {
        echo "MariaDB validation: invalid package lock entry: ${filename}" >&2
        exit 1
    }
    package="${filename%%_*}"
    version="${filename#*_}"
    version="${version%_aarch64_generic.ipk}"
    awk -v expected_package="${package}" -v expected_version="${version}" '
        BEGIN { RS = ""; FS = "\n"; matches = 0 }
        {
            package = version = status = ""
            for (i = 1; i <= NF; i++) {
                if (index($i, "Package: ") == 1) package = substr($i, 10)
                if (index($i, "Version: ") == 1) version = substr($i, 10)
                if (index($i, "Status: ") == 1) status = substr($i, 9)
            }
            if (package == expected_package && version == expected_version && status ~ / installed$/) matches++
        }
        END { exit matches == 1 ? 0 : 1 }
    ' "${status}" || {
        echo "MariaDB validation: installed package mismatch: ${package} ${version}" >&2
        exit 1
    }
    ((count += 1))
done < "${lock}"
[[ "${count}" -eq 7 ]] || { echo 'MariaDB validation: expected seven locked packages.' >&2; exit 1; }
