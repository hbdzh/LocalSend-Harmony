# LocalSend Harmony

LocalSend Harmony 是面向鸿蒙手机和 PC 的局域网传输应用，可以和兼容 LocalSend 协议的设备互传文件和消息。

目前项目处于开发阶段：ARM64 调试包已能构建，设备发现、传输和鸿蒙系统功能还需要实机测试。

## 功能

- 在同一局域网内发现设备，发送文件或消息；支持 HTTPS 加密。
- 通过文件选择器、剪贴板或系统分享添加内容，并将接收的文件导出。
- 适配手机与 PC 窗口；PC 端支持拖放文件、快捷键和窗口置顶。
- 恢复中断的发送任务并重新传输，暂不支持断点续传。

## 使用

两台设备连接同一个局域网，打开应用，在发送端选择文件或输入消息，再选择接收设备并确认接收。如果找不到设备，可检查路由器的设备隔离、VPN 和防火墙设置，默认使用 TCP 和 UDP 的 `53317` 端口。

目前需要自行构建和签名鸿蒙安装包。

## 构建

准备 Flutter 3.41.10-ohos-1.0.1、DevEco SDK 和支持 `aarch64-unknown-linux-ohos` 的 Rust 工具链，配置 `DEVECO_SDK_HOME` 后，在仓库根目录执行：

```bash
bash support/scripts/build_harmony.sh
```

构建结果位于 `app/build/harmony/`。未配置本地签名时，脚本生成未签名的调试 HAP，安装前需要签名。完整的工具链、签名配置和待验证事项见[鸿蒙移植说明](app/ohos/PORTING.md)。

## 参与开发

Flutter 界面位于 `app/`，鸿蒙原生代码位于 `app/ohos/`，Rust 协议核心位于 `packages/core/`。问题反馈和开发说明见[贡献指南](CONTRIBUTING.md)。

## 来源与许可证

本项目基于 [LocalSend](https://github.com/localsend/localsend) 开发，采用 [Apache License 2.0](LICENSE)。第三方依赖保留各自的许可证和版权声明；部分依赖的来源见[鸿蒙移植说明](app/ohos/PORTING.md#vendored-dependencies)。
