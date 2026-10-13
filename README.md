<p align="center">
  <img src="assets/icon.png" width="120" alt="VeloxMD icon" />
</p>

<h1 align="center">VeloxMD</h1>

<p align="center">
  <b>A fast, beautiful way to read Markdown files on your desktop.</b>
</p>

---

## What is VeloxMD?

VeloxMD is a simple app for opening and reading **Markdown** files — the
lightweight text format used for notes, README files, documentation, and more.

Just open a file and VeloxMD turns it into a clean, easy-to-read page with
proper headings, tables, links, and even diagrams. No clutter, no waiting.

It works completely **offline** — you don't need an internet connection, and
nothing you open ever leaves your computer.

## Screenshots

Reading a document, with the table of contents, live search, and a diagram all
in one clean window:

![VeloxMD main window showing a document with table of contents, search, and a rendered diagram](docs/screenshots/screenshot-01.png)

Click any diagram to see it full screen, where you can zoom and pan freely:

![A Mermaid flowchart shown full screen in VeloxMD](docs/screenshots/screenshot-02.png)

## Why you'll like it

- ⚡ **Instant** — files open and display immediately, even large ones.
- 🌙 **Easy on the eyes** — switch between light and dark themes with one click.
- 📑 **Never lose your place** — an automatic table of contents lets you jump
  to any section.
- 🔎 **Find anything** — search the whole document and jump between matches.
- 🔄 **Always up to date** — edit the file in another app and VeloxMD refreshes
  the view for you automatically.
- 📈 **Diagrams that just work** — flowcharts and charts written as text
  (Mermaid) are drawn out as real diagrams.
- 🖱️ **Simple to use** — open files by drag-and-drop, a button, or a keyboard
  shortcut.
- 🔒 **Private & offline** — everything runs on your computer, with no internet
  required.

## Getting started

The easiest way to run VeloxMD is to download a ready-made version.

### Windows

1. Go to the [**Releases page**](https://github.com/lbonomo/VeloxMD/releases).
2. Download the file named `veloxmd-setup-windows-x64-v...exe`.
3. Run it and follow the installer.

### Linux

Prebuilt Linux packages (`.deb` / AppImage) are published on the
[**Releases page**](https://github.com/lbonomo/VeloxMD/releases) when available.
Otherwise, see [Building from source](#building-from-source) below.

## How to use it

- **Open a file:** click the open button, drag a `.md` file onto the window,
  or press `Ctrl+O`.
- **Show the table of contents:** press `Ctrl+T`.
- **Open the search panel:** press `Ctrl+F`.
- **Switch light / dark theme:** use the toggle in the toolbar.
- **View document source:** press `Ctrl+U` to toggle between raw Markdown and rendered view.
- **Reload a file:** press `Ctrl+R` or `F5`.
- **Change font size:** press `Ctrl++`, `Ctrl+-`, or `Ctrl+0`.
- **Follow links:** click a link to jump to a heading (`#section`), open another
  local Markdown file (`other.md`, `other.md#section`), or open web links and
  other files in your default app. Go back / forward with `Alt+Left` /
  `Alt+Right`, the toolbar arrows, or the mouse side buttons.

### Keyboard shortcuts

| Shortcut (default) | Action |
|----------|--------|
| `Ctrl+O` | Open a file |
| `Ctrl+T` | Show / hide the table of contents |
| `Ctrl+U` | Toggle raw document source / rendered view |
| `Ctrl+F` | Show / hide the search panel |
| `Ctrl++` / `Ctrl+-` / `Ctrl+0` | Increase / decrease / reset font size |
| `Ctrl+R` / `F5` | Reload the current file |
| `Alt+Left` / `Alt+Right` | Back / forward through followed links |
| `Ctrl+Q` | Quit |

These are defaults, not fixed key combinations — VeloxMD reads them from a
user-editable config file following the XDG Base Directory Specification:
`$XDG_CONFIG_HOME/veloxmd/keybindings.json` (falls back to
`~/.config/veloxmd/keybindings.json` on Linux/macOS; `%APPDATA%\veloxmd\keybindings.json`
on Windows). The file is created with the defaults above on first run — edit
it and restart VeloxMD to rebind any action. Each action accepts one or more
combos, e.g.:

`plus`, `equal`, `minus` and `zero` are aliases that match both the main-row
and numpad variant of a key (e.g. `plus` triggers the `+` key, whether it's
the main-row key or the numpad's), so you don't need to list both explicitly.

```json
{
  "open_file": ["ctrl+o"],
  "reload": ["ctrl+r", "f5"],
  "toggle_toc": ["ctrl+t"],
  "toggle_view_source": ["ctrl+u"],
  "focus_search": ["ctrl+f"],
  "increase_font_size": ["ctrl+plus"],
  "decrease_font_size": ["ctrl+minus"],
  "reset_font_size": ["ctrl+zero"],
  "navigate_back": ["alt+arrowleft"],
  "navigate_forward": ["alt+arrowright"],
  "quit": ["ctrl+q"]
}
```

Supported file types: `.md`, `.markdown`, `.mdc`, and `.txt`.

### Fonts

By default VeloxMD renders with your desktop's own fonts, not a fixed
bundled font: on Linux it asks fontconfig (`fc-match`) for the current
sans-serif and monospace fonts; on Windows it uses the system defaults
(Segoe UI / Consolas). If the desktop's font can't be determined (e.g.
`fc-match` isn't installed), it falls back to the bundled Inter / FiraCode.

To pin a specific font instead of following the desktop, edit
`$XDG_CONFIG_HOME/veloxmd/fonts.json` (falls back to
`~/.config/veloxmd/fonts.json` on Linux/macOS; `%APPDATA%\veloxmd\fonts.json`
on Windows), created empty on first run:

```json
{
  "ui_font": null,
  "mono_font": null
}
```

Set `ui_font` (body text + UI chrome) and/or `mono_font` (code blocks) to an
installed font family name, e.g. `"ui_font": "Noto Sans"`. Leave a value
`null` (or omit it) to keep following the desktop's font for that role.
Restart VeloxMD after editing.

---

<details>
<summary><b>Building from source</b> (for developers)</summary>

VeloxMD is built with [Flutter](https://flutter.dev) for the Linux and Windows
desktop.

### Linux (primary platform)

**Prerequisites**

- Flutter SDK ≥ 3.27 with Linux desktop support enabled
- GTK 3 development libraries (`libgtk-3-dev` on Debian/Ubuntu)
- A C++20 toolchain and CMake/Ninja (`clang`, `cmake`, `ninja-build`, `pkg-config`)
  — required by the embedded Chromium engine used for Mermaid diagrams

> ℹ️ The **first** Linux build downloads the Chromium Embedded Framework
> (CEF, ~330 MB) and compiles it, so the initial build takes noticeably longer.
> Subsequent builds are fast.

**Commands**

```bash
# Enable the Linux desktop target (once)
flutter config --enable-linux-desktop

# Fetch dependencies
flutter pub get

# Run in debug mode
flutter run -d linux

# Build a release binary
flutter build linux --release
# Output: build/linux/x64/release/bundle/veloxmd

# Open a specific file from the terminal
./veloxmd path/to/document.md
```

### Windows

```bash
# Build a Windows release binary
flutter build windows --release
```

To build the installer with Inno Setup, see
[windows/installer/README.md](windows/installer/README.md).

Windows installers are also built automatically and published as release assets
when a GitHub release is created (see `.github/workflows/build-windows.yml`).

### Running tests

```bash
flutter test
```

### Project structure

```
lib/
├── main.dart                – entry point, window manager initialisation
├── app.dart                 – MaterialApp, theme management
├── screens/
│   └── viewer_screen.dart   – main UI: toolbar, drag-drop, keyboard shortcuts
├── widgets/
│   ├── markdown_viewer.dart – flutter_markdown widget with custom styling
│   ├── mermaid_view.dart    – offline Mermaid diagram renderer (webview_cef)
│   ├── toc_panel.dart       – table of contents side panel
│   ├── document_footer.dart – document statistics footer with token counter
│   └── dialogs/
│       └── about_dialog.dart – about dialog with project and developer info
├── models/
│   ├── toc_entry.dart       – heading model, GitHub-style anchors
│   ├── navigation_history.dart – back/forward history of visited documents
│   └── document_stats.dart  – document statistics and token calculation
└── services/
    ├── file_service.dart    – async file reading with validation
    └── link_resolver.dart   – classifies link targets (anchor, document, external)
```

### Desktop integration (Linux)

A `.desktop` file is provided at `linux/runner/resources/veloxmd.desktop` so the
app can be registered as a handler for `text/markdown` files in any
XDG-compliant desktop environment:

```bash
cp linux/runner/resources/veloxmd.desktop ~/.local/share/applications/
update-desktop-database ~/.local/share/applications/
```

</details>

## License

See the repository for license details.
