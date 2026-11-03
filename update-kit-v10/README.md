# v10 纯更新模块

只包含三个自编 ARM64 iOS 动态库、共享设置与校验清单。模块无个人签名，不能独立启动或安装游戏。

适用于清单中固定宿主及原始 v9 Documents 型无签名输入。使用仓库 `tools/apply_update.py` 离线生成私人 IPA，再用自己的有效签名覆盖更新；详见 `docs/RESTORE_AND_UPDATE.md`。所有地址和 guard 只对应该宿主，不能强行跳过版本检查。

模块源码保存在 `src/`，构建工具为 `tools/build_overlays.py`。MIT 与上游归属见仓库 LICENSE 和 THIRD_PARTY_NOTICES。这里没有游戏主程序、DLC、主镜像、Metal 库、存档或任何个人账号材料。
