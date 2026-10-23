# Yelt Files

A fast, good-looking file manager built with **Qt 6** and **QML**.
Cream-and-amber by day, ink-black by night. Tabs, split panes,
drag-and-drop, and a real undo/redo history for every file operation.

![status](https://img.shields.io/badge/status-work%20in%20progress-yellow)
![Qt](https://img.shields.io/badge/Qt-6.5%2B-41CD52?logo=qt&logoColor=white)
![C++](https://img.shields.io/badge/C%2B%2B-17-00599C?logo=cplusplus&logoColor=white)
![QML](https://img.shields.io/badge/QML-41CD52)
![License](https://img.shields.io/badge/license-MIT-blue)

## What is Yelt Files?

Yelt Files is a native desktop file manager written in C++17 and QML on top
of Qt 6. It is small, it starts fast, and it looks like something you would
actually want to use — no web engine, no Electron, no 200 MB bundle just to
open a folder of PDFs.

The "yelt" is the name. Everything else is what a file manager should be.

## Features

- **Grid and list views** with folder, document, image, archive and media
  icons, colored per file type.
- **Full file operations**: copy, cut, paste, duplicate, rename, new folder,
  new file, move to trash, permanent delete.
- **Undo / redo** (`Ctrl+Z` / `Ctrl+Y`) for every operation — including
  restoring items you just sent to the trash.
- **Drag and drop** onto folders, list rows, or sidebar shortcuts. Hold
  `Ctrl` while dragging to copy instead of move.
- **Sidebar** with Home, Desktop, Documents, Downloads, Pictures, plus
  pinned folders you choose.
- **Live theme switcher** (`Ctrl+P`) with instant palette preview as you
  arrow through the list. Cream and Midnight ship by default.
- **Details panel** with size, dates, location and kind — plus a summary
  (folder count, file count, total size) when multiple items are selected.
- **Search** (`Ctrl+F`) filters the current folder by name.
- **Sorting** by name, size, modified date or type — click the same column
  again to reverse direction.
- **Hidden files** toggle (`Ctrl+H`): hidden entries show in a visibly
  darker color so you can tell them apart without hiding them.
- **Disk usage** indicator in the status bar.
- **Keyboard-first**: every common action has a shortcut, and arrow keys
  navigate the grid directly.

### In progress

- Multiple **tabs** (`Ctrl+T` / `Ctrl+W`)
- **Split view** within a tab (`Ctrl+\`)
- Windows hidden-file attribute support (dot-prefixed hidden files already
  work everywhere)

## Design

Two carefully tuned themes — **Cream** (light, warm, paper-like) and
**Midnight** (dark, ink-black) — defined entirely in `Themes.qml`. Adding a
new theme is a single entry in a list; the live switcher updates the whole
window instantly and remembers your choice between runs.

Every file icon is drawn declaratively with QML primitives (`Shape`,
gradients, repeaters) instead of loaded from image assets. That means they
stay crisp at any scale and pick up theme colors automatically.

## Architecture

| File               | Role |
|--------------------|------|
| `main.cpp`         | Bootstraps the `QGuiApplication` and loads the QML module. |
| `filemodel.h/.cpp` | The entire filesystem layer, exposed to QML as `FileModel`. |
| `Main.qml`         | Window, layout, interactions, drag-and-drop, dialogs. |
| `Themes.qml`       | Palettes and the live theme machinery. |
| `CMakeLists.txt`   | `qt_add_qml_module` build. Qt 6.5 minimum. |

`FileModel` is a `QAbstractListModel` exposing `name`, `path`, `isDir`,
`size`, `ext`, `items` and `modified` per entry. It also owns:

- Navigation — `openPath`, `back`, `forward`, `up`, `activate`
- File operations — `copyItems`, `cutItems`, `paste`, `transfer`,
  `trashItems`, `removeItems`, `rename`, `newFolder`, `newFile`
- A scoped **undo/redo stack** with human-readable labels
- A `QFileSystemWatcher` + debounced reload timer so the view updates when
  something changes on disk
- Pinned folders and settings, persisted via `QSettings`
- Disk usage summary for the status bar

The model is stateless with respect to the UI. QML can create several
instances safely — which is what makes tabs and split panes possible without
touching the C++ side.

## Keyboard shortcuts

| Shortcut                      | Action |
|-------------------------------|--------|
| `Ctrl+T` / `Ctrl+W`           | New tab / close tab |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Cycle tabs |
| `Ctrl+\`                      | Toggle split view |
| `Ctrl+F`                      | Focus search |
| `Ctrl+P`                      | Theme palette |
| `Ctrl+H`                      | Toggle hidden files |
| `Ctrl+Shift+N`                | New folder |
| `Ctrl+C` / `X` / `V`          | Copy / cut / paste |
| `Ctrl+D`                      | Duplicate |
| `Ctrl+Z` / `Ctrl+Y`           | Undo / redo |
| `F2`                          | Rename |
| `Delete`                      | Move to trash |
| `Shift+Delete`                | Delete permanently |
| `Backspace` / `Alt+↑`         | Go up one folder |
| `Enter` / double-click        | Open |
| Arrow keys / `Shift`+arrow    | Move cursor / extend selection |
| `Ctrl+A`                      | Select all |
| `Esc`                         | Clear selection |

## Building

Requires **Qt 6.5+** with `QtQuick`, a C++17 compiler and CMake 3.21 or newer.

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/appFiles
