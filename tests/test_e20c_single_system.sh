#!/usr/bin/env bash
set -Eeuo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "${fixture}"' EXIT
mkdir -p "${fixture}/etc/init.d" "${fixture}/etc/config" "${fixture}/usr/sbin"

for service in mysqld dockerd AdGuardHome nfsd; do
    printf 'start_service() {\n\treturn 0\n}\n' > "${fixture}/etc/init.d/${service}"
done
printf "config mysqld 'general'\n\toption enabled '1'\n" > "${fixture}/etc/config/mysqld"
touch "${fixture}/usr/sbin/openwrt-update-rockchip"
(cd "${fixture}" && bash "${repo}/files/configure_e20c_services.sh" "${fixture}")
if grep -q 'bash "${PWD}/files/' "${repo}/mk_rk3528_e20c.sh"; then
    echo 'E20C packager resolves a helper against its changing working directory.' >&2
    exit 1
fi
for service in mysqld dockerd AdGuardHome nfsd; do
    grep -q 'e20c-data-mounted || return 1' "${fixture}/etc/init.d/${service}"
done
grep -q "option enabled '0'" "${fixture}/etc/config/mysqld"
[[ ! -e "${fixture}/usr/sbin/openwrt-update-rockchip" ]]
[[ -x "${fixture}/usr/libexec/e20c-data-mounted" ]]

[[ "$(wc -l < "${repo}/files/mariadb/SHA256SUMS")" -eq 7 ]]
[[ "$(awk '{print $2}' "${repo}/files/mariadb/SHA256SUMS" | sort -u | wc -l)" -eq 7 ]]
while read -r hash package; do
    [[ "${hash}" =~ ^[a-f0-9]{64}$ && "${package}" == *_aarch64_generic.ipk ]]
    name="${package%%_*}"
    version="${package#*_}"
    version="${version%_aarch64_generic.ipk}"
    [[ -n "${name}" && -n "${version}" ]]
    if [[ "${name}" == sudo ]]; then
        [[ "${version}" == '1.9.17_p2-r1' ]]
    fi
done < "${repo}/files/mariadb/SHA256SUMS"

if bash "${repo}/files/e20c-data-mounted" 2>/dev/null; then
    echo 'Data guard accepted a host without E20C /data.' >&2
    exit 1
fi
if grep -Eq 'mkpart.*p4|/mnt/mmcblk[0-9]+p4|ROOTFS2' "${repo}/files/first_run.sh"; then
    echo 'First boot still references the old A/B layout.' >&2
    exit 1
fi
echo 'E20C single-system checks passed.'
