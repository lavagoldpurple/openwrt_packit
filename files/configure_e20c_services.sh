#!/usr/bin/env bash
set -Eeuo pipefail

root="${1:?rootfs mount is required}"
source_dir="$(cd "$(dirname "$0")" && pwd)"
install -D -m 755 "${source_dir}/e20c-data-mounted" "${root}/usr/libexec/e20c-data-mounted"

for service in mysqld dockerd; do
    init="${root}/etc/init.d/${service}"
    [[ -f "${init}" ]] || { echo "Missing ${service} init script." >&2; exit 1; }
    grep -q '^start_service() {' "${init}" || {
        echo "Cannot guard ${service}: start_service not found." >&2
        exit 1
    }
    if ! grep -q '/usr/libexec/e20c-data-mounted' "${init}"; then
        sed -i '/^start_service() {/a\	/usr/libexec/e20c-data-mounted || return 1' "${init}"
    fi
done

for service in AdGuardHome nfsd; do
    init="${root}/etc/init.d/${service}"
    [[ -f "${init}" ]] || continue
    if ! grep -q '/usr/libexec/e20c-data-mounted' "${init}"; then
        if grep -q '^start_service() {' "${init}"; then
            sed -i '/^start_service() {/a\	/usr/libexec/e20c-data-mounted || return 1' "${init}"
        elif grep -q '^start() {' "${init}"; then
            sed -i '/^start() {/a\	/usr/libexec/e20c-data-mounted || return 1' "${init}"
        else
            echo "Cannot guard ${service} startup." >&2
            exit 1
        fi
    fi
done

install -D -m 644 "${source_dir}/mariadb/e20c.cnf" \
    "${root}/etc/mysql/conf.d/90-e20c.cnf"
uci_config="${root}/etc/config/mysqld"
[[ -f "${uci_config}" ]] || { echo 'Missing MariaDB UCI config.' >&2; exit 1; }
sed -i "s/option enabled '1'/option enabled '0'/" "${uci_config}"
for obsolete in openwrt-update-rockchip openwrt-kernel openwrt-backup openwrt-ddbr flippy; do
    rm -f -- "${root}/usr/sbin/${obsolete}"
done
