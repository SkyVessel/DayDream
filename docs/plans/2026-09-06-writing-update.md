# 2026-09-06 更新执行与验收

完整目标按本次用户的 12 项要求保留。当前工作树含上一轮尚未提交的修改，不能重置。

- [x] 1 Falling Text：设置可选、可调；默认保持弹性显现；副本弹射、落下、半空淡出，正文不移动。
- [x] 2 多图片拖动：拖动期间布局刷新不覆盖位置，第二张同样可拖。
- [x] 3 Divider：解析、输入、菜单、显示、保存。
- [x] 4 图片保持比例、悬停名称、等比缩放；网页行内蓝色无下划线，带站点图标；图片/视频网址仍支持媒体。
- [x] 5 三点菜单移除字体颜色设置。
- [x] 6 新用户拼写检查默认关闭，保留用户已有偏好。
- [x] 7 粗体更明显。
- [x] 8 工具条高光，作用于后续文字。
- [x] 9 动态工具目录，包括全部可用/导入字体、样式、Markdown。
- [x] 10 工具条可作用于选中文字，移除自动选区工具栏。
- [x] 11 样式修改支持撤销与重做。
- [x] 12 检查 Markdown 互操作输出；仅标准 Markdown 无法表达的字体/颜色用兼容 HTML，不丢失语义。若完整兼容工程量过大可按用户授权说明延期项。

验证包括针对性自动测试、Release 构建与实际界面检查，不以构建成功替代交互验收。

## 验收证据（2026-09-06）

用户已明确确认全部功能测试通过，并指定后续四项微调只做轻量测试，视觉验收由用户负责。

- Falling Text：TypingAnimation.swift、EditorSettings.swift、SettingsView.swift；运动轨迹和正文不变自动测试、此前实际窗口确认副本弹落。
- 媒体：MediaCards.swift、EditorMediaFeatures.swift；第二张图片拖动、首张等比缩放已实际确认，比例/拖动刷新/宽度保存自动测试通过。
- Divider、链接：MarkdownDocument.swift、BlockDecorationLayout.swift、InlineLinks.swift；解析/保存/输入边界和图标附件自动测试通过，实际窗口已确认分隔线及行内站点图标。
- 菜单、默认拼写、粗体：WorkspaceView.swift 删除文字颜色入口；EditorSettings.swift 新默认关闭拼写；Theme.swift 加强字重。用户确认功能验收。
- 高光、字体目录、选区、撤销：WritingFeatures.swift、WritingToolPicker.swift、EditorStyleTransactions.swift；动态字体及导入字体目录已检索确认，选区高光/撤销/重做实际验证。
- Markdown：修复强调标记内首尾空格，用独立 Foundation Markdown 解析器确认粗体。字体、颜色、高光及媒体沿用标准 HTML 后备表示；不承诺所有第三方软件保留 CSS 外观，未扩展为跨渲染器兼容项目。

## 最后四项微调

1. 高光统一跟随 Settings.highlightPreset，旧的 highlight:颜色 配置同样跟随设置，目录改为单一高光工具。
2. 选区已完整持有所选样式时再次应用会取消；混合选区先统一样式，取消时保留其他属性。段落样式再次应用恢复正文。
3. 站点图标附件保持正方形，间距改为独立 kern，不拉伸图像。
4. 重置默认快捷键改为 ⌘3，保留已有自定义绑定；恢复默认会使用新快捷键。

ToolbarPolishTests：6 项无窗口轻量测试全部通过。Release 构建与 --no-launch 打包通过，未启动软件或使用 computer use。生成 DayDream.app。
