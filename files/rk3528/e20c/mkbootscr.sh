#!/usr/bin/env bash
set -e
script_dir="$(cd "$(dirname "$0")" && pwd)"
boot_dir="${script_dir}/../../bootfiles/rockchip/rk3528/e20c"
mkimage -C none -A arm -T script -n 'E20C boot script' -d "${boot_dir}/boot.cmd" "${boot_dir}/boot.scr"
