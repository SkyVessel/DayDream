# Lossless Markdown Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve every unedited Markdown line exactly while retaining DayDream's WYSIWYG editing model.

**Architecture:** Capture original source lines and the editor's canonical baseline when a document loads. At export, use a stable collection difference to substitute original source for unchanged baseline lines and canonical Markdown for changed or inserted lines.

**Tech Stack:** Swift 6, AppKit `NSTextView`, SwiftPM/XCTest

**Spec:** `docs/superpowers/specs/2026-09-04-lossless-markdown-editor-design.md`

## Global Constraints

- macOS 14 or newer.
- Disk files remain UTF-8 `.md` files and the source of truth.
- Existing uncommitted work must be preserved.
- Unknown Markdown is preserved instead of guessed or rewritten.

---

### Task 1: Source-preserving merge model

**Files:**
- Create: `Sources/DayDream/SourcePreservingMarkdown.swift`
- Create: `Tests/DayDreamTests/SourcePreservingMarkdownTests.swift`

**Interfaces:**
- Produces: `SourcePreservingMarkdown.init(original:canonicalBaseline:)`
- Produces: `SourcePreservingMarkdown.merge(canonicalCurrent:) -> String`

- [ ] Write tests proving unchanged, edited, inserted, deleted, duplicate, and trailing-empty lines are handled.
- [ ] Run the focused tests and verify they fail because the model is missing.
- [ ] Implement stable line-difference merging without changing Markdown semantics.
- [ ] Run the focused tests and verify they pass.

### Task 2: Editor integration

**Files:**
- Modify: `Sources/DayDream/DayDreamTextView.swift`
- Modify: `Tests/DayDreamTests/EditorViewTests.swift`

**Interfaces:**
- Consumes: `SourcePreservingMarkdown.merge(canonicalCurrent:)`
- Preserves: `DayDreamTextView.load(markdown:)` and `exportMarkdown()`

- [ ] Write tests proving an unedited noncanonical document exports identically and one edited line does not rewrite neighbors.
- [ ] Run the focused tests and verify the current whole-document serializer fails them.
- [ ] Capture the source snapshot after parsing and merge it during export.
- [ ] Run editor and document tests.

### Task 3: Compatibility fixtures

**Files:**
- Modify: `Tests/DayDreamTests/SourcePreservingMarkdownTests.swift`
- Modify: `Tests/DayDreamTests/InlineMarkdownTests.swift`

**Interfaces:**
- Exercises the public load/export path with unsupported Markdown fixtures.

- [ ] Add fixtures for blockquotes, fenced code, HTML, alternative list markers, custom numbering, and trailing blank lines.
- [ ] Verify open/export identity and local-edit isolation.
- [ ] Run the complete test suite.

### Task 4: Package and runtime verification

**Files:**
- Verify: `Scripts/package-app.sh`

**Interfaces:**
- Produces: `DayDream.app`

- [ ] Run `swift test` and confirm zero failures.
- [ ] Run a release build and check the worktree diff for whitespace errors.
- [ ] Quit the existing DayDream process, package the app, and verify a new process is running.
