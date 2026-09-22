#!/bin/sh
set -eu

fail() { echo "E20C first boot: $*" >&2; exit 1; }

[ -f /etc/part_size ] || fail 'Missing partition layout marker.'
read -r skip_mib boot_mib root_mib < /etc/part_size
[ "$skip_mib:$boot_mib:$root_mib" = '16:512:4096' ] || fail 'Unexpected partition layout.'

root_device="$(findmnt -n -o SOURCE /)"
case "$root_device" in
    /dev/mmcblk[0-9]*p2) disk="${root_device%p2}" ;;
    *) fail "Unexpected root device: $root_device" ;;
esac
[ "$(findmnt -n -o SOURCE /boot)" = "${disk}p1" ] || fail 'Boot is not on the root disk.'
[ "$(findmnt -n -o FSTYPE /)" = btrfs ] || fail 'Root filesystem is not Btrfs.'
[ "$(findmnt -n -o FSTYPE /boot)" = ext4 ] || fail 'Boot filesystem is not ext4.'
[ "$(cat "/sys/class/block/${disk##*/}/device/type")" = MMC ] || fail 'Root disk is not eMMC.'
tr -d '\000' < /proc/device-tree/model | grep -qi E20C || fail 'This is not an E20C board.'
[ -x /usr/libexec/e20c-data-mounted ] || fail 'Missing data mount guard.'

# Repair the backup GPT after an image is written to larger eMMC.
parted -s -f "$disk" print >/dev/null || fail 'Cannot inspect or repair the GPT.'
table="$(parted -m -s "$disk" unit s print)" || fail 'Cannot read the partition table.'
numbers="$(printf '%s\n' "$table" | awk -F: '$1 ~ /^[0-9]+$/ { printf "%s%s", sep, $1; sep="," }')"
case "$numbers" in 1,2|1,2,3) ;; *) fail "Unexpected partitions: $numbers" ;; esac

partition_start() { printf '%s\n' "$table" | awk -F: -v number="$1" '$1 == number { gsub(/s/, "", $2); print $2 }'; }
partition_size() { printf '%s\n' "$table" | awk -F: -v number="$1" '$1 == number { gsub(/s/, "", $4); print $4 }'; }
partition_end() { printf '%s\n' "$table" | awk -F: -v number="$1" '$1 == number { gsub(/s/, "", $3); print $3 }'; }
[ "$(partition_start 1):$(partition_size 1)" = '32768:1048576' ] || fail 'Unexpected boot partition geometry.'
[ "$(partition_start 2):$(partition_size 2)" = '1081344:8388608' ] || fail 'Unexpected root partition geometry.'
data_start=9469952
# The kernel exports whole-disk capacity in 512-byte sectors.
read -r disk_sectors < "/sys/class/block/${disk##*/}/size" || fail 'Cannot read eMMC capacity.'
case "$disk_sectors" in ''|*[!0-9]*) fail 'Invalid eMMC sector count.' ;; esac
[ "$((disk_sectors - data_start))" -ge 2097152 ] || fail 'Less than 1 GiB remains for data.'

data_device="${disk}p3"
if [ -z "$(partition_start 3)" ]; then
    touch /etc/e20c-data-create-pending
    sync
    parted -s -f "$disk" mkpart primary ext4 "${data_start}s" 100% || fail 'Cannot create p3.'
    partprobe "$disk" || true
    table="$(parted -m -s "$disk" unit s print)" || fail 'Cannot reread GPT.'
fi
[ "$(partition_start 3)" = "$data_start" ] || fail 'Unexpected p3 start; refusing to format.'
[ "$(partition_end 3)" -ge "$((disk_sectors - 4096))" ] || fail 'p3 does not occupy the remaining eMMC space.'
attempt=0
until [ -b "$data_device" ]; do
    attempt=$((attempt + 1))
    [ "$attempt" -le 10 ] || fail 'p3 block device did not appear.'
    sleep 1
done

type="$(blkid -s TYPE -o value "$data_device" 2>/dev/null || true)"
label="$(blkid -s LABEL -o value "$data_device" 2>/dev/null || true)"
case "$type:$label" in
    :) mkfs.ext4 -F -L E20C_DATA "$data_device" || fail 'Cannot format p3.' ;;
    ext4:E20C_DATA) ;;
    *)
        [ -f /etc/e20c-data-create-pending ] || fail "Existing p3 contains unexpected filesystem ($type, $label)."
        wipefs --all --force "$data_device" || fail 'Cannot clear old data signature on newly created p3.'
        mkfs.ext4 -F -L E20C_DATA "$data_device" || fail 'Cannot format p3.'
        ;;
esac
mkdir -p /data
if ! mountpoint -q /data; then mount -t ext4 "$data_device" /data || fail 'Cannot mount /data.'; fi
/usr/libexec/e20c-data-mounted || fail 'Mounted data partition did not pass validation.'
uuid="$(blkid -s UUID -o value "$data_device")"
[ -n "$uuid" ] || fail 'p3 has no filesystem UUID.'
uci set fstab.data=mount
uci set fstab.data.target='/data'
uci set fstab.data.uuid="$uuid"
uci set fstab.data.fstype='ext4'
uci set fstab.data.enabled='1'
uci commit fstab

mkdir -p /data/mysql /data/mysql-logs /data/docker /data/AdGuardHome/data
chown -R mariadb:mariadb /data/mysql /data/mysql-logs
chmod 750 /data/mysql /data/mysql-logs

if [ -e /opt/docker ] && [ ! -L /opt/docker ]; then
    rmdir /opt/docker || fail '/opt/docker contains data; refusing to replace it.'
fi
ln -sfn /data/docker /opt/docker
if [ -f /etc/config/dockerd ]; then
    uci set dockerd.globals=globals
    uci set dockerd.globals.data_root='/data/docker'
    uci set dockerd.globals.auto_start='1'
    uci commit dockerd
fi

if [ -f /etc/config/AdGuardHome ]; then
    if [ -e /usr/bin/AdGuardHome ] && [ ! -L /usr/bin/AdGuardHome ]; then
        [ -d /usr/bin/AdGuardHome ] || fail 'Unexpected AdGuardHome binary path.'
        cp -a /usr/bin/AdGuardHome/. /data/AdGuardHome/ || fail 'Cannot migrate AdGuardHome files.'
        mv /usr/bin/AdGuardHome /usr/bin/AdGuardHome.e20c-staged
    fi
    ln -sfn /data/AdGuardHome /usr/bin/AdGuardHome
fi

uci set mysqld.general.enabled='1'
uci commit mysqld
/etc/init.d/mysqld enable
/etc/init.d/mysqld start || fail 'MariaDB did not start; first boot will retry.'
attempt=0
until mysql --protocol=socket -uroot -e 'SELECT VERSION()' >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    [ "$attempt" -le 30 ] || fail 'MariaDB local connection failed; first boot will retry.'
    sleep 1
done

if [ -f /etc/init.d/dockerd ]; then
    /etc/init.d/dockerd enable
    /etc/init.d/dockerd start || fail 'Docker did not start; first boot will retry.'
fi

for service in AdGuardHome nfsd; do
    if [ -x "/etc/init.d/$service" ] && "/etc/init.d/$service" enabled; then
        "/etc/init.d/$service" start || echo "E20C first boot: optional $service did not start." >&2
    fi
done

[ -f /etc/rc.local.orig ] || fail 'Missing original rc.local.'
mv /etc/rc.local.orig /etc/rc.local
rm -f /etc/part_size /etc/e20c-data-create-pending /etc/first_run.sh
sync
echo 'E20C first boot: /data and local MariaDB are ready.'
