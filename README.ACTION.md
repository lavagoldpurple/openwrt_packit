# E20C 复合 Action

仓库根目录的 `action.yml` 仅打包 Radxa E20C。工作流在检出仓库并安装依赖后，
可通过 `uses: ./` 调用；本仓库的工作流就是完整示例，产物上传为 Actions 附件。

不提供型号、rootfs 或内核版本输入。固定下载地址与 rootfs 校验值位于
`openwrt_flippy.sh`；打包前还会校验内核包内的 `sha256sums` 和 E20C DTB。
本 Action 不编译 OpenWrt 源码，也不创建 Release。

还会预装锁定在 `files/mariadb/SHA256SUMS` 的 MariaDB `11.4.8-r2` 及缺少的依赖，
并检查包安装记录、二进制与镜像仅有的 `/boot`、`/` 两个分区。设备首次启动时在
已确认的 eMMC 上创建 ext4 `/data` 并初始化数据库。MariaDB 只允许本机访问。

**产物用于离线整盘刷写：每次重刷均可能清空 `/data/mysql`、Docker 和共享文件。**
量产或更新前必须导出需要保留的数据；不提供在线 A/B 系统或内核升级。
