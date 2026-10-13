# Changelog

## Unreleased

### ✨ Features
- **Link navigation**: links in a document are now followed.
  - `#section` links scroll precisely to the heading (GitHub-style anchors,
    repeated headings get `-1`, `-2`, … suffixes).
  - Relative, absolute and `file://` links to other Markdown files open in the
    same window, optionally at an anchor (`other.md#section`).
  - Web links, `mailto:` and other existing local files open in the default app.
  - Back / forward history (`Alt+Left` / `Alt+Right`, configurable as
    `navigate_back` / `navigate_forward` in `keybindings.json`; toolbar arrows;
    mouse side buttons) restores the previous scroll position.
  - Unreachable targets show a "Link target not found" notice.
  - The table of contents now scrolls precisely to each heading (undoable with Back).

---

## 1.0.11 - 2026-10-07

### ✨ Features
- **Mermaid Diagram PNG Export**:
  - Added a download button in the top-right corner of both inline and fullscreen Mermaid views to export diagrams as high-resolution PNG images.
  - Automatically captures the rendered SVG using an HTML5 canvas in the CEF runtime matching the document's theme and background.
  - Prompts with the native file picker to save diagrams cleanly and offline.

## 1.0.10 - 2026-09-25

### ✨ Features
- **Export to PDF**:
  - Added an Export to PDF button in the toolbar and `Ctrl+P` / `Ctrl+E` keyboard shortcuts to export the rendered Markdown document as a beautifully formatted PDF.
  - Full support for multi-page pagination across large code blocks, lists, blockquotes, and tables without height overflows.
  - Includes document title header, page numbers, and clickable repository link in the footer.

## 1.0.9 - 2026-09-22

### 🐛 Bug Fixes
- **Large Markdown Rendering & Freeze Fix**:
  - Replaced non-lazy `MarkdownBody` with virtualized `Markdown` (`ListView.builder`) in `MarkdownViewer` to render Markdown documents lazily and eliminate main UI thread hangs on large files.
  - Fixed `Isolate.run` error handling in `ViewerScreen` for large documents (>20,000 chars) to prevent unhandled isolate exception crashes from leaving the UI stuck on loading spinner.

## 1.0.8 - 2026-09-21

### ✨ Features
- **View Document Source (Ctrl+U)**:
  - Added ability to toggle between rendered Markdown and raw, unrendered document source text via `Ctrl+U` keyboard shortcut or the toolbar icon button.
  - Text selection, monospace typography, padding, and font scaling are fully supported in raw source mode.

## 1.0.7 - 2026-09-21

### ✨ Features
- **Code Block Copy Button**:
  - Added a copy-to-clipboard button on fenced code blocks for quick copying of code snippets with visual feedback.
- **Desktop Font Configuration**:
  - Automatically follow the desktop's system fonts (sans-serif and monospace) with optional configuration overrides.
- **Collaborator**:
  - Added Javier Bértoli as collaborator in About dialog.

## 1.0.6 - 2026-09-20

### 🐛 Bug Fixes
- **Selectable Render Blocks**:
  - Included a selectable syntax-highlighted code block for render blocks (Mermaid diagrams) so that all diagram source text can be selected and copied.

## 1.0.5 - 2026-08-25

### 🐛 Bug Fixes
- **Selectable Code Blocks**:
  - Fixed an issue where text within fenced code blocks (``` ```) could not be selected with the mouse to copy/paste. Replaced `HighlightView` with a custom `SelectableHighlightView` widget using `Text.rich`.

## 1.0.4 - 2026-08-25

### 🐛 Bug Fixes
- **File Chooser Stacking & Modal Focus (#21)**:
  - Fixed issue where opening files (including documents with Mermaid diagrams) minimized the application window or pushed it behind other open applications.
  - Implemented GTK native modal file chooser (`GtkFileChooserNative`) linked directly to the main GTK window on Linux via MethodChannel.
  - The native file selection dialog now stays strictly on top of VeloxMD while keeping the main window in place without minimizing or lowering its stacking order.

## 1.0.3 - 2026-08-24

### ⚡ Performance & Optimization
- **High-performance text parsing**: eliminated redundant memory allocations in `DocumentStats` and `TocEntry`.
- **Off-thread processing**: stats and Table of Contents calculation offloaded to isolates (`Isolate.run`) for large documents.
- **Instant search navigation**: prevented Markdown document AST re-parsing when navigating search matches.
- **Optimized CEF height polling**: reduced Chromium WebView polling overhead for Mermaid diagrams.

### 🐛 Bug Fixes
- **Code block zoom scaling**: fixed fenced code blocks (` ``` `) to scale dynamically with font size zoom shortcuts (`Ctrl++`, `Ctrl+-`, `Ctrl+0`).

## 1.0.2 - 2026-08-17

### ✨ Features
- **Dedicated search panel**: moved document search out of the AppBar into a
  side panel with query input, match count, next/previous navigation, and clear
  action. The search remains debounced and still highlights matches in the
  rendered document.
- **Mermaid diagram rendering**: ` ```mermaid ` fenced code blocks are now rendered
  as diagrams (flowchart, sequence, class, state, gantt, pie, etc.).
  - Rendered fully **offline** via a bundled Mermaid runtime inside an embedded
    Chromium view (`webview_cef`) — no network calls, no external services.
  - Follows the app's light/dark theme and resizes to fit the diagram.
  - Gracefully falls back to showing the raw diagram source if the Chromium
    engine is unavailable.

### 🔌 Offline
- **100% offline fonts**: removed the `google_fonts` dependency, which downloaded
  Inter and Fira Code at runtime on first use. The fonts are now bundled as local
  assets in `assets/fonts/` (Inter 400/600/700, Fira Code 400) with their SIL Open
  Font License, so typography is consistent and the app makes **no network requests**.
- Added an always-on Kiro steering rule (`.kiro/steering/offline.md`) documenting the
  offline requirement for future changes.

### 🔤 Fonts
- **Follow the desktop's fonts**: the app no longer always forces the bundled
  Inter/FiraCode fonts. By default it renders with the desktop's own
  sans-serif and monospace fonts (via `fc-match` on Linux, Segoe UI/Consolas
  on Windows), falling back to the bundled fonts if the desktop's font can't
  be determined. Override per-role via `$XDG_CONFIG_HOME/veloxmd/fonts.json`
  (`%APPDATA%\veloxmd\fonts.json` on Windows).

### ⌨️ Keyboard shortcuts
- **Configurable shortcuts**: key bindings (open file, reload, font size, quit,
  etc.) are no longer hardcoded. They're read from an XDG-compliant config file
  (`$XDG_CONFIG_HOME/veloxmd/keybindings.json`, `%APPDATA%\veloxmd\keybindings.json`
  on Windows), created with the previous defaults on first run and editable by hand.

### ⚡ Performance
- **Debounced search**: typing in the search box no longer re-parses and re-renders
  the whole document on every keystroke. The query is applied after a short pause
  (180 ms); pressing Enter flushes it immediately. Noticeably smoother on large files.

---

## 1.0.1 - 2026-08-17

### 🐛 Fixes
- Restored the table of contents, including empty-state display and improved ATX heading parsing.

---

## 0.4.5 - 2026-08-04

### 📦 Version Bump
- Patch version bump to 0.4.5

---

## 0.4.4 - 2026-08-04

### 📦 Version Bump
- Patch version bump to 0.4.4

---

## 0.4.3 - 2026-08-04

### 🔧 Build System
- Updated Android and Windows release workflows to work better with local `act` runs

---

## 0.4.2 - 2026-08-04

### ✨ Features
- **Android CI/CD Automation**: Added GitHub Actions workflow for automated Android builds
  - Automated APK (Android Package) build process
  - Automated AAB (Android App Bundle) build for Google Play Store
  - Multi-platform build configuration
  - Integrated GitHub Actions CI/CD pipeline

### 🔧 Build System
- Android Gradle build configuration
- Automated build triggers on releases
- Platform-specific build optimizations
- Continuous integration for mobile platform

### 📦 Deployment
- Ready for Google Play Store distribution
- APK distribution support
- Automated artifact generation

---

## 0.4.1 - 2026-08-04

### ✨ Features
- **Developer Information**: Added developer profile section to About dialog
  - Developer name: Lucas Bonomo
  - Website link: https://lucasbonomo.com
  - GitHub profile link: https://github.com/lbonomo
  - LinkedIn profile link: https://www.linkedin.com/in/lbonomo/
  - All links are clickable and open in default browser

### 🐛 Bug Fixes
- Fixed RenderFlex overflow in About dialog
- Added SingleChildScrollView for content scrolling
- Added maxHeight constraint for responsive design
- Prevents layout errors on smaller screens

### 📚 Content Updates
- Professional attribution to project creator
- Easy access to developer's professional profiles

---

## 0.4.0 - 2026-08-04

### ✨ Features
- **About Dialog**: Comprehensive project information dialog
  - Project goal and description
  - Complete feature list
  - Development stack details (Flutter, Dart, Material Design 3)
  - Getting started instructions
  - Quick access links to GitHub resources
  - License information (MIT)

### 🎨 UI Enhancements
- Added About button (info icon) in AppBar
- Modal dialog with responsive layout
- Clickable resource links (repository, issues, discussions)
- Full theme support (dark/light mode)

### 📚 Resources
- Direct access to GitHub repository
- Issue tracker link
- Community discussions link

---

## 0.3.0 - 2026-08-04

### ✨ Features
- **Document Footer**: Added a comprehensive footer bar displaying document statistics
  - Real-time statistics: words, lines, characters, headings, links, code blocks
  - **Token counter** using industry-standard OpenAI tokenization algorithm
  - Software version display
  - Automatic update on file reload/change
  - Footer only visible when a document is open

### 🔢 Token Calculation
- Implemented hybrid token estimation algorithm based on OpenAI's standard
- Formula: Average of character-based (1 token ≈ 4 chars) and word-based (1 token ≈ 0.75 words) methods
- Useful for estimating costs in LLM APIs

### 📊 Document Statistics
- Words count
- Lines count
- Total characters
- Heading count
- External links count
- Code blocks count

---

## 0.2.0 - 2026-07-30

- Minor version bump from 0.1.1 to 0.2.0.
- Aligned Linux CMake project version with pubspec version.
