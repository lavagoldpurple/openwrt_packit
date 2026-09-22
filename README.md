# E20C OpenWrt 镜像打包

本项目仅支持 Radxa E20C（RK3528）。它将预编译的 ARMv8 OpenWrt rootfs 和 rk35xx
内核打包为可刷写镜像，不从源码编译 OpenWrt、内核或 MariaDB，也不支持其他板卡。

**整盘刷写会清空 eMMC 上的数据库及其他本地数据。量产刷机或重刷之前必须导出需要保留的数据。**
此固件不提供 A/B 切换或在线系统、内核更新；后续升级仅使用离线整盘刷写。

## GitHub Actions

进入 **Actions > Package E20C OpenWrt image > Run workflow** 手动触发。构建成功后，
从该次运行下载 `openwrt-e20c` 附件，其中包含 `.img.gz` 镜像和 `SHA256SUMS`。
解压附件后可运行 `sha256sum -c SHA256SUMS` 校验。无需 Release 写入权限或个人令牌。

打包入口 `openwrt_flippy.sh` 固定使用 `OpenWrt_armv8_save_2026.08` 的 rootfs，以及
`6.1.141-rk35xx-flippy-2603a` 内核。下载地址与 rootfs SHA-256 集中定义在脚本开头；
更新版本时需同步核对内核清单和 `rk3528-radxa-e20c.dtb`。默认 LAN 地址为
`192.168.1.1`。

打包时还从 LEDE 24.10.3 包源安装原生 MariaDB `11.4.8-r2`，不会在 Actions 中
编译数据库。MariaDB 与缺少的依赖版本及 SHA-256 锁定在
`files/mariadb/SHA256SUMS`；任一下载、校验、依赖安装或二进制检查失败，构建中止。

## 分区与首次启动

镜像预留前 16 MiB 给引导程序，只包含 `p1` 512 MiB ext4 `/boot` 和 `p2`
4 GiB Btrfs `/`。首次启动在**已验证的内置 eMMC 系统盘**上创建剩余空间的
`p3` ext4 `/data`（16 GiB eMMC 约 10.2 GiB），按文件系统 UUID 写入
`/etc/config/fstab`。新建 `p3` 时会清除该区域残留的旧文件系统签名（例如旧布局的
`p4`）；如果 `p3` 在本次启动前已存在且文件系统异常，则停止并保留待完成标记，
等待人工检查。不要使用不稳定的外接 SD 卡存放数据库。

MariaDB 数据在 `/data/mysql`、错误日志在 `/data/mysql-logs`，只监听
`127.0.0.1` 和本机 socket；不预置远程账号或密码。Docker、AdGuardHome 和 NFS
共享数据也使用 `/data`。`/data` 未从系统盘挂载时，数据库和 Docker 会拒绝启动。
首次启动成功后可通过 `mysql --protocol=socket -uroot -e 'SELECT VERSION()'`
在设备本机验证。数据库可用空间与 Docker、共享文件共同使用 `p3`。

## 本地打包

需要 ARM64 Linux、root 权限、loop 设备、足够容纳约 4.5 GiB 原始镜像及临时文件的
空间，以及工作流中列出的系统依赖。在仓库根目录运行 `sudo ./openwrt_flippy.sh`。
脚本将依赖下载至 `src1/` 和 `/opt/kernel/`，校验后调用 `mk_rk3528_e20c.sh`，
最终产物位于 `output/`。

刷写前请核对镜像分区与引导文件；首次启动、中断后重试、重启后持久化以及
离线重刷清空数据的行为仍需在 E20C 实机验证。
