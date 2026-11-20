# MouseTalk 0.6.1 待上线候选

状态：**尚未公开发布**。官网当前仍提供 0.5.3。本版在 [0.6.0 候选](RELEASE-0.6.0.md) 基础上只修一个问题；0.6.0 中「上线前仍需完成」的各项仍然有效。

## 本版变化

- 修复：用鼠标键触发豆包语音时，常常要按好几下才有反应。
  - 原因：妙语发出的修饰键事件只带通用标记（例如「有个 Option 被按下」），缺少真实键盘会带的左右区分标记。豆包设为「右 Option」时要靠这个标记分辨左右，于是时灵时不灵。
  - 现在发出的 Fn / Control / Option / Command 事件和真实键盘一致：带左右区分标记和非合并标记，也不再把会话里无关的状态位复制进来。
  - 实测：Logitech 鼠标侧键 → 右 Option（兼容模式）→ 豆包，在 Claude 桌面 App 输入框中连续多次，每次按一下就触发。

## 已完成的候选包检查

在干净的 `main` 上运行：

```bash
./package-release.sh
./scripts/verify-release.sh 0.6.1
```

- 生成 Apple Silicon + Intel 通用二进制。
- 校验 Info.plist、代码签名完整性、ZIP 完整性、源码归档和 SHA-256。

输出位于 `dist/`，该目录不提交到 Git。默认候选包是 ad-hoc 签名，未公证，Gatekeeper 会拒绝直接打开。

## 尚未覆盖

- 只验证了右 Option。左 Option、左右 Control、左右 Command 和 Fn 按同样规则发出，但没有逐个和豆包实测。
- 没有自动化测试覆盖按键事件的标记。
