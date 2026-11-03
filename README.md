# 塞尔达 · iPadOS 适配档案

保存《塞尔达传说：旷野之息》1.6.0 在 **11 英寸 iPad Pro M5 / iPadOS 27.0.1** 上的适配过程、自编适配源码、纯更新模块和验收结果。归档日期：2026-11-03，最终日常界面构建：**2026110310（v10）**。

已在真机进入场景并控制林克；全屏、背包自动兼容、iPad 体感瞄准、可编辑虚拟手柄和统一设置已按用户反馈验收。Xbox 手柄尚未实测，长时间游玩及所有游戏场景尚未覆盖。

这次工作复用了用户已有的 **MacNativeGames iOS ARM64 宿主与预编译着色器**，完成资源恢复、分体安装、权限签名和 iPad 专项适配。没有从零重新编译完整游戏，也没有在 iPad 内运行 macOS、Windows 或完整 Switch 系统。

## 归档内容

| 目录 | 内容 |
| --- | --- |
| `src/` | 最终 v10 的 15 个适配源文件，与实际安装版本对应 |
| `compat/` | 固定宿主的 UUID、地址和短指令签名防误调用信息 |
| `tests/` | 背包识别、状态机、体感数学、触控几何、限帧及 ARC 所有权检查源码 |
| `tools/` | 离线构建、纯 C 回归检查、受版本约束的更新打包和发布审计工具 |
| `update-kit-v10/` | 三个自编无个人签名 dylib、共享设置及 SHA-256 清单 |
| `verification/` | 脱敏构建记录、真机验收及本次归档工具验证结果 |
| `docs/` | 流程、版本沿革、iPad 适配原理、恢复更新及已知问题 |
| `licenses/` | 上游 MIT 许可副本 |

**不提供可直接安装的游戏 IPA。** 游戏主程序、RomFS、DLC、着色器库、游戏图片音频、存档、Apple SDK、签名证书、描述文件、配对记录、Apple 账号及认证日志均不在仓库内。纯模块压缩包位于 `packages/`，不能单独运行游戏。仓库无需登录 Apple 账号，也没有游戏下载器。

## 已实现的体验

- 应用显示名称统一为「塞尔达」，游戏内入口集中为「设置」。系统设置可隐藏该入口。
- 兼容低分辨率、1080p、1080p 普通放大到屏幕、1080p MetalFX Spatial 放大四档。
- 16:9 黑边 / 2420×1668 全屏取景；主场景全屏、背包自动切回 16:9，退出后恢复。
- iPad CoreMotion 接入宿主已有六轴融合，支持体感瞄准开关和重新校准。
- 虚拟按键与摇杆拖动、大小和透明度调整、固定/浮动摇杆、保存/取消/恢复默认、显示开关。
- 30 / 60 / 跟随游戏上限；修复显式 60 上限叠加旧呈现间隔导致的固定 30 帧问题。
- 默认关闭测试 HUD 和诊断；需要时可开启本地记录。

屏幕输出分辨率不等于内部 3D 分辨率。当前最高已配置的场景为 **1920×1080**；2420×1668 为屏幕输出。接入的是 Apple **MetalFX Spatial**，未接入 Temporal、机器学习重建或插帧。不能据此承诺所有场景稳定 60 帧。

## 从这里恢复工作

1. 先读 [成功流程](docs/PROCESS.md) 和 [恢复与更新](docs/RESTORE_AND_UPDATE.md)，确认自己的私有游戏/宿主备份仍在。
2. 用 Python 3.11+ 验证纯模块及文件清单：`python tools/audit_archive.py`。
3. 现成 v10 模块只支持清单固定的宿主。使用私下备份的原始无签名 v9 Documents 型 IPA：

   ```powershell
   python tools/apply_update.py --input "D:\PrivateBackup\v9-input.ipa" --output "D:\PrivateBuild\v10-unsigned.ipa"
   ```

4. 如需改源码，自备 Windows iOS Clang/LLD 工具链和有权使用的 iPhoneOS26.5 SDK：

   ```powershell
   python tools/run_checks.py --cc "D:\Toolchain\bin\clang.exe"
   python tools/build_overlays.py --toolchain-bin "D:\Toolchain\bin" --sdk "D:\SDK\iPhoneOS26.5.sdk" --host-ipa "D:\PrivateBackup\v9-input.ipa" --out "D:\PrivateBuild\rebuilt-v10"
   python tools/apply_update.py --input "D:\PrivateBackup\v9-input.ipa" --kit "D:\PrivateBuild\rebuilt-v10\update-kit-v10" --output "D:\PrivateBuild\rebuilt-unsigned.ipa"
   ```

这些命令只生成本地无签名更新输入，不安装、不操作账号。新编模块需要重新真机测试；保留原始档案模块用于回退。随后用自己的有效签名和内存权限覆盖更新，保持应用身份，勿删除旧 App。仓库不能替代私有宿主和游戏备份；也不能由 Switch ROM 或 Mac `.app` 直接生成 iOS 游戏。

## 阅读索引

- [全过程与工具](docs/PROCESS.md)
- [iPad 专项适配原理](docs/IPAD_ADAPTATIONS.md)
- [v1–v10 更新沿革](docs/UPDATES.md)
- [测试、性能结论与限制](docs/VALIDATION.md)
- [恢复、升级及备份要求](docs/RESTORE_AND_UPDATE.md)
- [USB 已知问题及排查记录](docs/USB_KNOWN_ISSUE.md)
- [软件版本、来源与许可证](docs/TOOLS_AND_SOURCES.md)

本仓库原创适配代码按 MIT 发布；上游归属见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。游戏和相关商标属于各自权利人，不属于本仓库许可范围。
