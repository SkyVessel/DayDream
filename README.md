# DayDream

DayDream 是一款 macOS 原生 Markdown 编辑器，专注于安静的写作体验。

## v1.0.0

- Markdown 标题、列表、任务清单、引用、代码块和分隔线；支持 `/` 检索样式。
- 可配置的键盘工具条：字体、颜色、高光和段落样式，作用于选区或后续输入。
- 弹性显现与 Falling Text 打字特效，可切换和调整。
- 图片、视频卡片支持拖动排版与等比缩放；网页链接以带站点图标的行内链接显示。
- Focus、Ultra Focus 与 Retype 写作模式。
- Markdown / Word 导入导出、笔记与文件夹管理、字数统计、可导入字体。
- 样式撤销与重做；默认关闭拼写修正。

需要 macOS 14 或更新版本。首发安装包面向 Apple Silicon（arm64）。

## 安装

下载 DMG 后，将 DayDream 拖到 Applications；也可解压 ZIP 后移动应用。
当前发行包使用本地临时签名，未使用 Developer ID 签名或经过 Apple 公证。系统可能要求在“系统设置 → 隐私与安全性”中确认允许打开；仅在确认下载来源和校验值后操作。

## 常用快捷键

- `⌘1` / `⌘2`：按住 ⌘、重复按数字预选工具，松开 ⌘ 应用。
- `⌘3`：恢复默认打字样式。已有自定义快捷键会保留。
- `⌥⌘↑` / `⌥⌘↓`：进入 / 退出 Ultra Focus。
- `⌃⌥R`：开启 / 退出 Retype。

工具和快捷键可在 Settings 中调整。已有用户偏好不会被新默认值覆盖。

## 文档格式

笔记保存为 UTF-8 Markdown。字体、颜色、高光及媒体使用 HTML 后备表示；不同 Markdown 阅读器对 CSS 和视频的支持有所不同。媒体资源保存在笔记旁的 `.daydream-assets` 文件夹，移动或备份笔记时请一并保留。

## 本地开发与打包

```bash
swift run
swift test --filter ToolbarPolishTests
./Scripts/package-app.sh --no-launch
```

`package-app.sh` 不带参数时会在打包后启动应用；`--no-launch` 只打包。
