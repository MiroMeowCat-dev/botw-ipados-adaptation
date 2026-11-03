# 使用的软件、来源与角色

下列版本是本次使用记录，不代表各项目最新版本。第三方工具不是 Apple 官方产品；不要把“上游正式发行”理解为 Apple 认证。

| 工具 | 本次角色 |
| --- | --- |
| [MacNativeGames](https://github.com/ly05010419/MacNativeGames) | 实际 BotW iOS 宿主、原有平台/图形兼容、预编译着色器与 Documents 数据路线；MIT |
| [nxnative](https://github.com/seedds/nxnative)、[Windows 分支](https://github.com/xbunax/nxnative) | 早期 Switch 适配研究与另一游戏路线；不是最终 BotW 全部源码来源 |
| [Sideloadly](https://sideloadly.io/) 0.72 | 初期个人签名/安装；遇连接与大包解包失败，不作为最终整包路线 |
| [iLoader](https://github.com/nab138/iloader) 2.4.1 | 成功的 Windows 签名/安装入口，使用用户自己的 Apple 账号与有效权限 |
| [GetMoreRAM](https://github.com/hugeBlack/GetMoreRam) 与社区修复 | 曾尝试注册内存能力，登录失败；最终不依赖它 |
| [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) 11.49.1 / Python 3.11.9 | 设备发现、应用安装/文档传输、备份和本地诊断读取 |
| [rcodesign](https://github.com/indygreg/apple-platform-rs) 0.29.0 | 后续使用已有个人签名材料生成同身份本地更新 |
| Clang / LLD，iPhoneOS26.5 SDK | Windows 编译自有 ARM64 iOS26.0 适配模块；工具链与 SDK 不随仓库分发 |
| [Apple iTunes](https://support.apple.com/downloads/itunes) 12.13.10.3 | Windows Apple 设备栈；Mobile Device Support 19.4.0.10 / USB driver 538.0.0.0 |
| [Apple Metal Developer Tools for Windows](https://developer.apple.com/download/all/?q=Metal%20Developer%20Tools%20for%20Windows) 6.2 | 早期工具准备；最终 BotW 复用既有库，未重新编译全部游戏着色器 |
| 7-Zip、Python zipfile / hashlib / plistlib，cryptography 等本地库 | 私有包检查/恢复、ZIP/哈希/设置及签名核对；公开构建脚本仅需标准库 |

本仓库原创源码未引入这些工具的完整发行文件。使用第三方工具前应自行从对应维护者来源核实；账号和验证码由本人输入，不能放入 GitHub 或聊天日志。GetMoreRAM 的旧认证调试记录未公开，也不应继续传播其中认证材料。

## 参考入口

- [上游安装文档](https://github.com/ly05010419/MacNativeGames/blob/main/docs/install.md)
- [上游 MIT 许可证](https://github.com/ly05010419/MacNativeGames/blob/main/LICENSE)
- [Apple MetalFX](https://developer.apple.com/documentation/metalfx)
- [Apple CoreMotion](https://developer.apple.com/documentation/coremotion)
- [Apple 增加内存权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit)
- [Apple 开发者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [11 英寸 iPad Pro M5 技术规格](https://www.apple.com/ipad-pro/specs/)

这些链接用于说明技术与工具来源；本仓库不保证外部服务长期可用，也不重新托管 Apple SDK、密钥或游戏。
