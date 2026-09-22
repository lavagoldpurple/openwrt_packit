# E20C OpenWrt 镜像打包

本项目仅支持 Radxa E20C（RK3528）。它将预编译的 ARMv8 OpenWrt rootfs 和 rk35xx
内核打包为可刷写镜像，不从源码编译 OpenWrt 或内核，也不支持其他板卡。

## GitHub Actions

进入 **Actions > Package E20C OpenWrt image > Run workflow** 手动触发。构建成功后，
从该次运行下载 `openwrt-e20c` 附件，其中包含 `.img.gz` 镜像和 `SHA256SUMS`。
解压附件后可运行 `sha256sum -c SHA256SUMS` 校验。无需 Release 写入权限或个人令牌。

打包入口 `openwrt_flippy.sh` 固定使用 `OpenWrt_armv8_save_2026.08` 的 rootfs，以及
`6.1.141-rk35xx-flippy-2603a` 内核。下载地址与 rootfs SHA-256 集中定义在脚本开头；
更新版本时需同步核对内核清单和 `rk3528-radxa-e20c.dtb`。默认 LAN 地址为
`192.168.1.1`。

## 本地打包

需要有 root 权限和 loop 设备的 Linux 主机、足够容纳约 2.6 GiB 原始镜像及临时文件的
空间，以及工作流中列出的系统依赖。在仓库根目录运行 `sudo ./openwrt_flippy.sh`。
脚本将依赖下载至 `src1/` 和 `/opt/kernel/`，校验后调用 `mk_rk3528_e20c.sh`，
最终产物位于 `output/`。

刷写前请核对镜像分区与引导文件；启动、网口和升级功能仍需在 E20C 实机验证。
