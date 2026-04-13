# MenuBarPilot

一款 macOS 菜单栏应用，用于管理第三方菜单栏图标和监控 Claude Code 会话。

## 功能

### 菜单栏图标管理
- 通过辅助功能 API（Accessibility API）发现所有第三方菜单栏图标
- 隐藏/显示图标（采用与 [Ice](https://github.com/jordanbaird/Ice) 相同的技术）
- 点击图标即可激活对应的应用

### Claude Code 会话监控
- 监控 `~/.claude/sessions/` 目录，自动发现正在运行的 Claude Code 会话
- 解析 JSONL 日志，实时检测会话状态
- 三种状态：
  - **空闲（Idle）** — 会话存活，但没有在执行任务
  - **运行中（Running）** — Claude 正在工作中（读文件、执行命令等）
  - **等待输入（Awaiting Input）** — Claude 弹出了选项（1、2、3）等待你选择
- **仅当 Claude 弹出 `AskUserQuestion` 选项时**才会发送 macOS 通知，不会误打扰
- 点击会话行可直接跳转到对应的终端窗口

### 动画菜单栏图标
- 一个小机器人在药丸里跑来跑去，腿部有奔跑动画
- 根据会话状态自动变色：绿色（空闲）→ 橙色（工作中）→ 红色（需要你操作）

## 系统要求

- macOS 14.0+
- Xcode 命令行工具
- 辅助功能权限（用于发现菜单栏图标）

## 构建

```bash
cd MenuBarPilot
bash build.sh
```

构建产物在 `build/MenuBarPilot.app`。

## 使用方法

1. 启动应用 — 它会常驻在菜单栏
2. 按提示授予辅助功能权限
3. 在任意终端中使用 Claude Code — 会话会自动出现在面板中
4. 点击药丸图标查看会话详情

## License

MIT
