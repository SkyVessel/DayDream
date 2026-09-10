# DayDream 大更新执行记录

需求来源：用户提供的《大更新提示词.md》，路径 `/Users/ty/Library/Application Support/DayDream/Library/Work and learn/大更新提示词.md`。

约束：不使用 Computer Use，不启动软件进行视觉/功能验证；用户负责交互验收，交付测试清单；未经用户测试确认不推送 GitHub。保留上一轮未提交改动。

## 完整范围
- [x] 删除线文字淡化，取消删除线恢复。
- [x] 导入与导出支持选择 Dark/Light 模式。
- [x] PDF 默认预览留边，支持 Command -/+ 缩放。
- [x] Finder Open With / 拖入应用图标正确显示 MD 和 PDF；独立窗口无侧栏，标题居中，关闭保存。
- [x] 多窗口切换后快捷键恢复正确目标，不互相抢占。
- [x] 笔记左上角前进/后退按钮，历史最多 5 条；快捷键。
- [x] 翻译设置：首批 9 种语言、双向语言对及自动方向识别、可实际执行的翻译引擎。
- [x] Translation Block：/ 命令与 `!! ` 语法，Enter 触发翻译，保存与重新加载。
- [x] MD/PDF 原文旁译注：左侧对齐，无边框，默认低对比，悬停高亮；原文对应圆角淡背景；超出内容渐隐，悬停纵向展开，遮挡的其他译注模糊。
- [x] 双栏全文翻译：左原文右译文，短竖线分隔，可拖动宽度。
- [x] 参考功能：侧栏文档右键“在侧栏中打开”，左编辑右参考。
- [x] 参考窗格具备独立文档侧栏、三点菜单、导出及正常编辑功能。
- [x] 左右窗格聚焦快捷键与快速光标飞入动画。
- [x] Command W 关闭当前笔记窗格，不关闭应用窗口。
- [x] 更新用户测试清单，构建交付但不启动应用、不推送。

## 待确认
1. 已确认使用 Apple Translation，无需 API Key；不支持系统显示说明。
2. 已确认历史 Control Option 左右，窗格聚焦 Option Command 左右。

## 当前证据
- 上一轮 PDFView 使用 autoScales=true，无留边比例和缩放快捷键处理。
- 独立窗口使用无尺寸约束的 NSHostingView，需明确内容视图填满窗口并复核文档绑定。
- ShortcutCenter.shared 保存唯一主窗口与动作闭包，多窗口/分栏需要按实际焦点路由，不能继续依赖最后注册的窗口。

## 实现核对（交互验收由用户执行）

- 删除线淡化：Theme.swift、DocumentTransferService.swift；取消时由语义重建恢复原色。
- 外观导入/导出：DocumentAppearance.swift、SidebarView.swift、DocumentTransferService.swift；Markdown 保留文本内容，外观为本机偏好；PDF/Word 渲染采用选择的模式。
- PDF 预览：PDFDocumentView.swift、PDFTranslations.swift；初始适配留边、当前窗格缩放、独立旁注层。
- 文件打开：DayDreamApp.swift 同时处理文件打开与 SwiftUI URL 事件；ExternalDocumentWindow.swift 明确内容尺寸、独立控制器与关闭保存。
- 多窗口/窗格：PaneShortcutRouting.swift、ShortcutCenter.swift、WorkspaceHost.swift；按键盘窗口及点击位置路由，每个 WorkspaceView 有独立状态。
- 历史：NoteHistory.swift、DocumentController.swift；最多 5 条，前进分支替换，失败打开不前移索引。
- 翻译：TranslationSupport.swift、SettingsView.swift；Apple Translation 的系统支持门槛与下载准备；九种语言设置、自动识别方向、排队与取消。
- 翻译块：MarkdownDocument.swift、MarkdownEditingController.swift、SlashCommandPanel.swift、EditorTranslation.swift；!! 语法、Enter、异步锚点与原文校验。
- MD/PDF 旁注：TranslationAnnotations.swift、EditorTranslation.swift、PDFTranslations.swift；独立持久化、对齐、渐隐、悬停展开与对应原文背景。
- 译文/参考双栏：WorkspaceView.swift、WorkspaceHost.swift；拖动分隔线、独立历史、焦点动画、当前笔记关闭。
- 本轮编译源码及测试目标，但不执行功能测试；没有启动应用或使用 Computer Use。
- 用户验收清单：docs/大更新测试清单-2026-09-09.md。

上方复选框表示代码实现已接入，不表示用户已完成交互验收。尚未推送 GitHub。
