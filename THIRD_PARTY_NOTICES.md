# 第三方与版权范围

本仓库保存本项目编写的 iPad 适配层和文档。技术基础是用户已有的 MacNativeGames iOS 宿主；不声称拥有或重新实现其整套运行时。MacNativeGames 为 MIT，版权声明及完整条款保留在 `licenses/MacNativeGames-MIT.txt`。

此前研究过 seedds/nxnative（MIT，Copyright (c) 2026 seedds）及其 Windows 分支；本归档未复制整棵 nxnative 源码或第三方工具发行包。需要完整上游项目时请从文档指向的原仓库取得并遵守各自许可。

`compat/` 的 UUID 和短代码签名用于固定宿主 ABI 防误调用。UUID 是可执行文件构建标识，不是 iPad 设备 UDID。这里没有宿主可执行文件或能独立重建游戏的完整指令数据。自编 dylib 仅是适配模块，不包含 RomFS、DLC 或 shader seed。

《塞尔达传说：旷野之息》、Nintendo 及相关图像、音乐、商标和游戏内容属于其权利人。Apple、iPad、Metal、MetalFX、Xcode 等属于相应权利人。MIT 仅覆盖本仓库有权发布的代码与文档，不授予任何游戏、Apple SDK 或个人签名材料的分发权。
