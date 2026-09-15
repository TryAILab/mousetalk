# MouseTalk 0.5.3

- 在设置页和菜单栏增加 GitHub 源码与“提供反馈”按钮。
- 外部链接由浏览器打开，不自动发送应用设置或诊断信息。
- 提供通用 Mac App ZIP，支持 Apple Silicon、Intel 和 macOS 13 及以上版本。
- 增加可复现的通用架构打包脚本与 SHA-256 校验文件。

## 安装

解压 ZIP，把 MouseTalk.app 拖入“应用程序”，打开后按界面提示授予输入监控和辅助功能权限。应用不包含语音识别，需要已有的语音输入软件。

当前版本使用临时签名，尚未经过 Apple 公证。首次打开可能被 macOS 阻止；确认下载来源后参照 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。更新后可能需要重新授权。

验证：Swift 自动化测试通过；arm64 和 x86_64 构建通过；通用二进制架构、Info.plist 与代码签名完整性已检查。未在 Intel 实机或所有支持的 macOS 版本完成运行测试。
