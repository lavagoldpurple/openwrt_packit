# E20C 复合 Action

仓库根目录的 `action.yml` 仅打包 Radxa E20C。工作流在检出仓库并安装依赖后，
可通过 `uses: ./` 调用；本仓库的工作流就是完整示例，产物上传为 Actions 附件。

不提供型号、rootfs 或内核版本输入。固定下载地址与 rootfs 校验值位于
`openwrt_flippy.sh`；打包前还会校验内核包内的 `sha256sums` 和 E20C DTB。
本 Action 不编译 OpenWrt 源码，也不创建 Release。
