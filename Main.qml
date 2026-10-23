import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Files

ApplicationWindow {
    id: win
    visible: true
    width: 1240
    height: 720
    minimumWidth: 860
    minimumHeight: 520
    title: "Files"
    color: theme.bg

    readonly property color accent: theme.accent
    readonly property color ink: theme.ink
    readonly property color muted: theme.muted
    readonly property color line: theme.line

    // ---------- tabs and panes ----------
    // Every pane owns a FileModel and its own selection. The sidebar, menus, dialogs and the
    // details panel all act on `activePane` (the one you clicked last).
    property var activePane: null
    property int currentTab: 0
    readonly property var fm: activePane ? activePane.fileModel : homeModel
    readonly property var otherPane: activePane ? activePane.sibling : null
    readonly property bool currentSplit: otherPane !== null

    readonly property int selCount: activePane ? activePane.selCount : 0
    readonly property var selList: activePane ? activePane.selList : []
    readonly property string selectedPath: activePane ? activePane.selectedPath : ""
    readonly property var info: activePane ? activePane.info : ({})
    readonly property var multi: activePane ? activePane.multi : ({})
    readonly property int step: activePane ? activePane.step : 1
    readonly property bool selPinned: fm.pinned.indexOf(selectedPath) >= 0
    readonly property bool textFocused: activeFocusItem !== null
                                        && typeof activeFocusItem.cursorPosition !== "undefined"
    readonly property bool blocked: textFocused || nameDialog.visible || confirmDialog.visible
                                    || ctx.visible || sortMenu.visible || theme_palette.visible

    ListModel { id: tabsModel }          // { startPath, split, title }
    FileModel { id: homeModel }          // used by the sidebar before the first pane exists

    Themes {
        id: theme
        onApplied: (name) => homeModel.saveSetting("theme", name)
    }

    Component.onCompleted: {
        theme.saved = homeModel.loadSetting("theme", "Cream")
        tabsModel.append({ startPath: "", split: false, title: "" })
    }

    function newTab(path) {
        tabsModel.append({ startPath: path || fm.path, split: false, title: "" })
        currentTab = tabsModel.count - 1
    }
    function closeTab(i) {
        if (tabsModel.count <= 1) return
        const cur = currentTab
        tabsModel.remove(i)
        let n = cur > i ? cur - 1 : cur
        currentTab = Math.max(0, Math.min(n, tabsModel.count - 1))
        Qt.callLater(function () {
            const pg = tabRepeater.itemAt(win.currentTab)
            if (pg) win.activePane = pg.lastPane ? pg.lastPane : pg.leftPane
        })
    }
    function nextTab(d) {
        if (tabsModel.count > 1) currentTab = (currentTab + d + tabsModel.count) % tabsModel.count
    }
    function toggleSplit() {
        const i = currentTab
        if (i < 0 || i >= tabsModel.count) return
        const on = !tabsModel.get(i).split
        tabsModel.setProperty(i, "split", on)
        const pg = tabRepeater.itemAt(i)
        if (!pg) return
        if (on) {
            Qt.callLater(function () { if (pg.rightPane) pg.rightPane.activate() })
        } else {
            pg.leftPane.activate()
        }
    }
    function switchPane() { if (otherPane) otherPane.activate() }

    // ---------- selection (forwarded to the active pane) ----------
    function selectName(n) { if (activePane) activePane.selectName(n) }
    function selectAll() { if (activePane) activePane.selectAll() }
    function clearSel() { if (activePane) activePane.clearSel() }
    function moveSel(d, ext) { if (activePane) activePane.moveSel(d, ext) }

    // ---------- drag state (shared by all panes) ----------
    property bool dragging: false
    property bool dragCopy: false
    property var dragPaths: []
    property var dragPane: null
    property var dropItem: null          // drop target currently under the cursor

    function startDrag(pane, path) {
        dragPane = pane
        dragPaths = pane.selSet[path] === true ? pane.selList.slice() : [path]
        dragging = true
    }
    // Finds the deepest visible item under (x, y) that declares a non-empty `dropPath`
    // (folder cells, sidebar entries and pane backgrounds do). Every item under the pointer is
    // searched, so an item without a drop path can never hide one that has it.
    function dropTargetIn(item, x, y) {
        const kids = item.children
        for (let i = kids.length - 1; i >= 0; --i) {
            const c = kids[i]
            if (!c.visible) continue
            const cx = x - c.x
            const cy = y - c.y
            if (cx < 0 || cy < 0 || cx >= c.width || cy >= c.height) continue
            const r = dropTargetIn(c, cx, cy)
            if (r) return r
        }
        return (item.dropPath !== undefined && item.dropPath !== "") ? item : null
    }
    function dropTargetAt(x, y) { return dropTargetIn(win.contentItem, x, y) }
    function moveDrag(p, mods) {
        dragProxy.x = p.x
        dragProxy.y = p.y
        dragCopy = (mods & Qt.ControlModifier) !== 0
        dropItem = dropTargetAt(p.x, p.y)
    }
    function endDrag() {
        const t = dropItem
        dragging = false
        dropItem = null
        if (t) dropOn(t.dropPath)
    }
    function parentDir(p) { const i = p.lastIndexOf("/"); return i <= 0 ? "/" : p.substring(0, i) }
    function dropOn(dest) {
        const paths = dragPaths
        if (!paths.length || !dragPane || paths.indexOf(dest) >= 0) return
        if (!dragCopy && paths.every(p => parentDir(p) === dest)) return
        const n = dragPane.fileModel.transfer(paths, dest, dragCopy)
        if (n !== "")
            toast.show((dragCopy ? "Copied " : "Moved ") + paths.length + (paths.length === 1 ? " item" : " items"))
    }

    // ---------- actions ----------
    function doOpen() {
        if (selCount === 1) { fm.activate(fm.indexOfPath(selectedPath)); return }
        for (let i = 0; i < selList.length; ++i) {
            const idx = fm.indexOfPath(selList[i])
            if (!fm.details(idx).isDir) fm.activate(idx)
        }
    }
    function doCopy() { if (selCount > 0) fm.copyItems(selList) }
    function doCut()  { if (selCount > 0) fm.cutItems(selList) }
    function doPaste() { const n = fm.paste(); if (n !== "") selectName(n) }
    function doDuplicate() {
        if (selCount === 0) return
        const n = fm.transfer(selList, fm.path, true)
        if (n !== "") selectName(n)
    }
    function doTrash() {
        if (selCount === 0) return
        const c = selCount
        if (fm.trashItems(selList.slice()))
            toast.show("Moved " + c + (c === 1 ? " item" : " items") + " to Trash — Ctrl+Z to undo")
    }
    function sendToOther(move) {
        if (!otherPane || selCount === 0) return
        const c = selCount
        const n = fm.transfer(selList.slice(), otherPane.fileModel.path, !move)
        if (n !== "")
            toast.show((move ? "Moved " : "Copied ") + c + (c === 1 ? " item" : " items") + " to the other pane")
    }
    function doUndo() { if (!fm.canUndo) return; const l = fm.undo(); if (l !== "") toast.show("Undid " + l) }
    function doRedo() { if (!fm.canRedo) return; const l = fm.redo(); if (l !== "") toast.show("Redid " + l) }
    function askRename() { if (selCount === 1) nameDialog.openFor("rename", "Rename", info.name, selectedPath) }
    function askNew(kind) {
        nameDialog.openFor(kind, kind === "folder" ? "New folder" : "New file",
                           kind === "folder" ? "New Folder" : "untitled.txt", "")
    }
    function askDelete() {
        if (selCount > 0)
            confirmDialog.openFor(selList.slice(), selCount === 1 ? info.name : selCount + " items")
    }
    function sortLabel(k, n) { return (fm.sortKey === k ? (fm.descending ? "↓   " : "↑   ") : "      ") + n }

    function badgeColor(e) {
        const m = {
            PDF: "#D9534F", DOC: "#3B6FD4", DOCX: "#3B6FD4", ODT: "#3B6FD4",
            TXT: "#7A7468", RTF: "#7A7468", MD: "#6B6558",
            XLS: "#3FA066", XLSX: "#3FA066", CSV: "#3FA066", ODS: "#3FA066",
            PPT: "#E8922A", PPTX: "#E8922A", KEY: "#E8922A",
            CPP: "#4A6FD9", C: "#4A6FD9", H: "#4A6FD9", HPP: "#4A6FD9",
            PY: "#3B82C4", JS: "#D9B124", TS: "#3B6FD4", HTML: "#E5673A", CSS: "#8E5BD6",
            QML: "#41B883", JSON: "#B8A02B", SH: "#4D5A6A", GO: "#00ADD8",
            RS: "#C2562E", JAVA: "#C2562E", CS: "#7A4FC4",
            SVG: "#8E5BD6",
            ZIP: "#B8862B", TAR: "#B8862B", GZ: "#B8862B", XZ: "#B8862B",
            "7Z": "#B8862B", RAR: "#B8862B", ISO: "#7A6A55",
            M4A: "#D6478A", MP3: "#D6478A", WAV: "#D6478A", FLAC: "#D6478A", OGG: "#D6478A",
            MP4: "#5B5BD6", MKV: "#5B5BD6", MOV: "#5B5BD6", AVI: "#5B5BD6", WEBM: "#5B5BD6"
        }
        return m[e] || "#8C8577"
    }
    function isImage(e) {
        return ["PNG", "JPG", "JPEG", "GIF", "WEBP", "BMP", "HEIC", "TIFF"].indexOf(e) >= 0
    }

    // ---------- shortcuts ----------
    Shortcut { sequences: [StandardKey.Back]; onActivated: fm.back() }
    Shortcut { sequences: [StandardKey.Forward]; onActivated: fm.forward() }
    Shortcut { sequence: "Alt+Up"; onActivated: fm.up() }
    Shortcut { sequence: "Ctrl+F"; onActivated: { if (win.activePane) win.activePane.focusSearch() } }
    Shortcut { sequence: "Ctrl+P"; onActivated: theme_palette.openPalette() }
    Shortcut { sequence: "Ctrl+T"; onActivated: win.newTab("") }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.closeTab(win.currentTab) }
    Shortcut { sequences: [StandardKey.NextChild]; onActivated: win.nextTab(1) }
    Shortcut { sequences: [StandardKey.PreviousChild]; onActivated: win.nextTab(-1) }
    Shortcut { sequences: ["Ctrl+\\", "F3"]; onActivated: win.toggleSplit() }
    Shortcut { sequence: "Tab";          enabled: !win.blocked; onActivated: win.switchPane() }
    Shortcut { sequence: "F5";           enabled: !win.blocked; onActivated: win.sendToOther(false) }
    Shortcut { sequence: "F6";           enabled: !win.blocked; onActivated: win.sendToOther(true) }
    Shortcut { sequences: [StandardKey.Copy];      enabled: !win.blocked; onActivated: win.doCopy() }
    Shortcut { sequences: [StandardKey.Cut];       enabled: !win.blocked; onActivated: win.doCut() }
    Shortcut { sequences: [StandardKey.Paste];     enabled: !win.blocked; onActivated: win.doPaste() }
    Shortcut { sequences: [StandardKey.SelectAll]; enabled: !win.blocked; onActivated: win.selectAll() }
    Shortcut { sequences: [StandardKey.Undo];      enabled: !win.blocked; onActivated: win.doUndo() }
    Shortcut { sequences: [StandardKey.Redo, "Ctrl+Y"]; enabled: !win.blocked; onActivated: win.doRedo() }
    Shortcut { sequence: "Ctrl+D";       enabled: !win.blocked; onActivated: win.doDuplicate() }
    Shortcut { sequence: "Delete";       enabled: !win.blocked; onActivated: win.doTrash() }
    Shortcut { sequence: "Shift+Delete"; enabled: !win.blocked; onActivated: win.askDelete() }
    Shortcut { sequence: "F2";           enabled: !win.blocked; onActivated: win.askRename() }
    Shortcut { sequence: "Ctrl+Shift+N"; enabled: !win.blocked; onActivated: win.askNew("folder") }
    Shortcut { sequence: "Ctrl+H";       enabled: !win.blocked; onActivated: fm.showHidden = !fm.showHidden }
    Shortcut { sequence: "Backspace";    enabled: !win.blocked; onActivated: fm.up() }
    Shortcut { sequence: "Escape";       enabled: !win.blocked; onActivated: win.clearSel() }
    Shortcut { sequences: ["Return", "Enter"]; enabled: !win.blocked; onActivated: win.doOpen() }
    Shortcut { sequence: "Left";        enabled: !win.blocked; onActivated: win.moveSel(-1, false) }
    Shortcut { sequence: "Right";       enabled: !win.blocked; onActivated: win.moveSel(1, false) }
    Shortcut { sequence: "Up";          enabled: !win.blocked; onActivated: win.moveSel(-win.step, false) }
    Shortcut { sequence: "Down";        enabled: !win.blocked; onActivated: win.moveSel(win.step, false) }
    Shortcut { sequence: "Shift+Left";  enabled: !win.blocked; onActivated: win.moveSel(-1, true) }
    Shortcut { sequence: "Shift+Right"; enabled: !win.blocked; onActivated: win.moveSel(1, true) }
    Shortcut { sequence: "Shift+Up";    enabled: !win.blocked; onActivated: win.moveSel(-win.step, true) }
    Shortcut { sequence: "Shift+Down";  enabled: !win.blocked; onActivated: win.moveSel(win.step, true) }

    // ---------- reusable pieces ----------
    component IconBtn: Rectangle {
        id: btn
        property alias text: t.text
        property bool active: false
        signal clicked()
        implicitWidth: 30
        implicitHeight: 28
        radius: 8
        color: active ? theme.btnActive : (ma.containsMouse && enabled ? theme.btnHover : "transparent")
        opacity: enabled ? 1 : 0.35
        Text { id: t; anchors.centerIn: parent; color: theme.ink; font.pixelSize: 15 }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: btn.clicked() }
    }

    component SoftShadow: Item {
        property real radius: 9
        property color tint: "#000000"
        property real strength: 0.06
        Repeater {
            model: 4
            delegate: Rectangle {
                required property int index
                x: -index
                y: 4 - index + 2
                width: parent.width + 2 * index
                height: parent.height + 2 * index
                radius: parent.radius + index
                color: Qt.alpha(parent.tint, parent.strength)
            }
        }
    }

    component FolderIcon: Item {
        id: folderIcon
        property real dim: 0            // 0 = normal, higher = darker (hidden / cut items)
        function d(c) { return dim > 0 ? Qt.darker(c, 1 + dim * 2.2) : c }
        implicitWidth: 84
        implicitHeight: 66
        SoftShadow { y: 8; width: parent.width; height: parent.height - 8; radius: 9; tint: "#B8741A"; strength: 0.07 }
        Rectangle { width: parent.width * 0.42; height: 20; radius: 6; color: folderIcon.d("#E08F25") }
        Rectangle { y: 8; width: parent.width; height: parent.height - 8; radius: 9; color: folderIcon.d("#E9983A") }
        Rectangle {
            y: 16; width: parent.width; height: parent.height - 16; radius: 9
            gradient: Gradient {
                GradientStop { position: 0; color: folderIcon.d("#FAC96E") }
                GradientStop { position: 1; color: folderIcon.d("#F0A53F") }
            }
            Rectangle {
                x: 6; y: 1; width: parent.width - 12; height: 1.5; radius: 1
                color: "white"; opacity: 0.45
            }
        }
    }

    component FileIcon: Item {
        id: fi
        property string ext: ""
        property color badge: "#8C8577"
        property real dim: 0            // 0 = normal, higher = darker (hidden / cut items)
        function d(c) { return dim > 0 ? Qt.darker(c, 1 + dim * 2.2) : c }
        readonly property real r: 7
        readonly property real f: 15
        implicitWidth: 52
        implicitHeight: 62
        SoftShadow { width: parent.width; height: parent.height; radius: 7 }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: fi.d(theme.fileCard)
                strokeColor: fi.d(theme.fileStroke)
                strokeWidth: 1
                startX: fi.r; startY: 0.5
                PathLine { x: fi.width - fi.f; y: 0.5 }
                PathLine { x: fi.width - 0.5; y: fi.f }
                PathLine { x: fi.width - 0.5; y: fi.height - fi.r }
                PathArc { x: fi.width - fi.r; y: fi.height - 0.5; radiusX: fi.r; radiusY: fi.r; direction: PathArc.Clockwise }
                PathLine { x: fi.r; y: fi.height - 0.5 }
                PathArc { x: 0.5; y: fi.height - fi.r; radiusX: fi.r; radiusY: fi.r; direction: PathArc.Clockwise }
                PathLine { x: 0.5; y: fi.r }
                PathArc { x: fi.r; y: 0.5; radiusX: fi.r; radiusY: fi.r; direction: PathArc.Clockwise }
            }
            ShapePath {
                fillColor: fi.d(theme.fileFlap)
                strokeColor: fi.d(theme.fileStroke)
                strokeWidth: 1
                startX: fi.width - fi.f; startY: 0.5
                PathLine { x: fi.width - fi.f; y: fi.f }
                PathLine { x: fi.width - 0.5; y: fi.f }
            }
        }
        Column {
            x: 10; y: 18; spacing: 4
            Rectangle { width: 22; height: 3; radius: 1.5; color: Qt.alpha(fi.d(fi.badge), 0.35) }
            Rectangle { width: 16; height: 3; radius: 1.5; color: Qt.alpha(fi.d(fi.badge), 0.18) }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 24
            width: 32; height: 14; radius: 5
            color: fi.d(fi.badge)
            Text {
                anchors.centerIn: parent
                text: fi.ext.slice(0, 4) || "FILE"
                color: "white"; font.pixelSize: 8; font.bold: true
            }
        }
    }

    component PhotoIcon: Item {
        id: photoIcon
        property real dim: 0            // 0 = normal, higher = darker (hidden / cut items)
        function d(c) { return dim > 0 ? Qt.darker(c, 1 + dim * 2.2) : c }
        implicitWidth: 58
        implicitHeight: 58
        SoftShadow { width: parent.width; height: parent.height; radius: 12 }
        Rectangle {
            anchors.fill: parent
            radius: 12
            gradient: Gradient {
                GradientStop { position: 0; color: photoIcon.d("#F6A65E") }
                GradientStop { position: 0.55; color: photoIcon.d("#D77A9A") }
                GradientStop { position: 1; color: photoIcon.d("#8B6FD1") }
            }
        }
        Rectangle { x: 11; y: 11; width: 15; height: 15; radius: 7.5; color: "white"; opacity: 0.9 }
        Rectangle {
            x: 28; y: 30; width: 20; height: 20; radius: 5
            rotation: 45
            color: photoIcon.d("#6B58B8"); opacity: 0.8
        }
    }

    component Pill: Rectangle {
        id: pill
        property alias text: pt.text
        property bool primary: false
        property bool danger: false
        signal clicked()
        implicitWidth: pt.implicitWidth + 32
        implicitHeight: 34
        radius: 10
        color: danger ? "#D9534F" : (primary ? theme.accent : theme.surface)
        border.color: (primary || danger) ? "transparent" : theme.line
        Text {
            id: pt
            anchors.centerIn: parent
            font.pixelSize: 13
            font.bold: pill.primary || pill.danger
            color: pill.danger ? "white" : (pill.primary ? theme.onAccent : theme.ink)
        }
        MouseArea { anchors.fill: parent; onClicked: pill.clicked() }
    }

    component TMenuItem: MenuItem {
        id: mi
        implicitHeight: 34
        contentItem: Text {
            text: mi.text
            color: theme.ink
            opacity: mi.enabled ? 1 : 0.4
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
            leftPadding: 8
        }
        background: Rectangle {
            radius: 8
            color: mi.highlighted && mi.enabled ? theme.surfaceAlt : "transparent"
        }
    }

    component TSep: MenuSeparator {
        topPadding: 4
        bottomPadding: 4
        contentItem: Rectangle { implicitHeight: 1; color: theme.line }
    }

    component InfoRow: RowLayout {
        property string label
        property string value
        Layout.fillWidth: true
        Text { text: parent.label; color: theme.muted; font.pixelSize: 12 }
        Item { Layout.fillWidth: true }
        Text {
            text: parent.value; color: theme.ink; font.pixelSize: 12
            elide: Text.ElideLeft; Layout.maximumWidth: 150
        }
    }

    component SideItem: Rectangle {
        id: si
        property string label
        property string key
        property string path: ""
        property bool pinnedItem: false
        property color dot: "#E8922A"
        readonly property string target: path !== "" ? path : fm.place(key)
        readonly property string dropPath: target
        width: parent ? parent.width : 0
        height: 32
        radius: 8
        color: fm.path === target ? theme.sideSelected : (sma.containsMouse || win.dropItem === si ? theme.sideHover : "transparent")
        border.color: win.dropItem === si ? theme.accent : "transparent"
        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 10; spacing: 10
            Rectangle { width: 16; height: 16; radius: 5; color: si.dot; anchors.verticalCenter: parent.verticalCenter }
            Text { text: si.label; color: theme.ink; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
            id: sma
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    if (si.pinnedItem) { pinMenu.targetPath = si.target; pinMenu.popup() }
                } else if (mouse.button === Qt.MiddleButton) {
                    win.newTab(si.target)
                } else {
                    fm.openPath(si.target)
                }
            }
        }
    }

    // ---------- one file pane (folder view + toolbar + status bar) ----------
    component Pane: Item {
        id: pane
        property alias fileModel: paneModel
        property string startPath: ""
        property bool showActive: false
        property bool gridMode: true
        property var sibling: null
        signal activated()

        readonly property bool isActive: win.activePane === pane
        readonly property string title: paneModel.crumbs.length ? paneModel.crumbs[paneModel.crumbs.length - 1].name : ""
        readonly property var disk: { paneModel.path; return paneModel.diskInfo() }

        // selection
        property var selSet: ({})
        property string anchorPath: ""
        property string cursorPath: ""
        readonly property var selList: Object.keys(selSet)
        readonly property int selCount: selList.length
        readonly property string selectedPath: selCount === 1 ? selList[0] : ""
        readonly property var info: selCount === 1 ? paneModel.details(paneModel.indexOfPath(selList[0])) : ({})
        readonly property var multi: selCount > 1 ? paneModel.summarize(selList) : ({})
        readonly property int step: gridMode ? Math.max(1, Math.floor(grid.width / grid.cellWidth)) : 1

        function markActive() { win.activePane = pane; pane.activated() }
        function activate() { markActive(); pane.forceActiveFocus() }
        function focusSearch() { markActive(); search.forceActiveFocus() }

        function setSel(list) {
            const o = {}
            for (let i = 0; i < list.length; ++i) o[list[i]] = true
            selSet = o
        }
        function selectPathOnly(p) { setSel([p]); anchorPath = p; cursorPath = p }
        function selectIndex(i) { const p = paneModel.pathAt(i); if (p) selectPathOnly(p) }
        function selectName(n) { const r = paneModel.indexOf(n); if (r >= 0) selectIndex(r) }
        function toggleSel(p) {
            const l = selList.slice()
            const k = l.indexOf(p)
            if (k >= 0) l.splice(k, 1); else l.push(p)
            setSel(l); anchorPath = p; cursorPath = p
        }
        function selectRange(toIdx) {
            let a = paneModel.indexOfPath(anchorPath)
            if (a < 0) a = toIdx
            const l = []
            for (let i = Math.min(a, toIdx); i <= Math.max(a, toIdx); ++i) l.push(paneModel.pathAt(i))
            setSel(l); cursorPath = paneModel.pathAt(toIdx)
        }
        function selectAll() {
            const l = []
            for (let i = 0; i < paneModel.count; ++i) l.push(paneModel.pathAt(i))
            setSel(l)
        }
        function clearSel() { setSel([]); anchorPath = ""; cursorPath = "" }
        function moveSel(delta, extend) {
            if (paneModel.count === 0) return
            const cur = paneModel.indexOfPath(cursorPath)
            const n = cur < 0 ? (delta > 0 ? 0 : paneModel.count - 1)
                              : Math.max(0, Math.min(paneModel.count - 1, cur + delta))
            if (extend) selectRange(n); else selectIndex(n)
            if (gridMode) grid.positionViewAtIndex(n, GridView.Contain)
            else list.positionViewAtIndex(n, ListView.Contain)
        }

        function itemPressed(path, mods) {
            activate()
            const additive = (mods & Qt.ControlModifier) !== 0 || (mods & Qt.ShiftModifier) !== 0
            if (!additive && selSet[path] !== true) selectPathOnly(path)
        }
        function itemClicked(path, index, button, mods) {
            if (button === Qt.RightButton) { ctx.onItem = true; ctx.popup(); return }
            if ((mods & Qt.ShiftModifier) !== 0) selectRange(index)
            else if ((mods & Qt.ControlModifier) !== 0) toggleSel(path)
            else selectPathOnly(path)
        }

        FileModel { id: paneModel }
        Connections {
            target: paneModel
            function onCountChanged() { pane.setSel(pane.selList.filter(p => paneModel.indexOfPath(p) >= 0)) }
            function onFailed(message) { toast.show(message) }
        }
        Component.onCompleted: {
            if (startPath !== "") paneModel.jumpTo(startPath)
            if (win.activePane === null) win.activePane = pane
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Toolbar
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                spacing: 8

                IconBtn { text: "‹"; enabled: paneModel.canGoBack; onClicked: { pane.activate(); paneModel.back() } }
                IconBtn { text: "›"; enabled: paneModel.canGoForward; onClicked: { pane.activate(); paneModel.forward() } }
                IconBtn { text: "↑"; onClicked: { pane.activate(); paneModel.up() } }
                Text {
                    visible: pane.width > 560
                    text: pane.title
                    color: theme.ink; font.bold: true; font.pixelSize: 16
                    elide: Text.ElideRight
                    Layout.maximumWidth: 180
                }
                Item { Layout.fillWidth: true }

                Rectangle {
                    visible: pane.width > 500
                    implicitWidth: 92; implicitHeight: 34; radius: 10; color: theme.surfaceAlt
                    Row {
                        anchors.centerIn: parent; spacing: 4
                        IconBtn { text: "▦"; active: pane.gridMode;  onClicked: { pane.activate(); pane.gridMode = true } }
                        IconBtn { text: "☰"; active: !pane.gridMode; onClicked: { pane.activate(); pane.gridMode = false } }
                    }
                }
                IconBtn { text: "⇅"; onClicked: { pane.activate(); sortMenu.popup() } }
                IconBtn { text: "+"; onClicked: { pane.activate(); ctx.onItem = false; ctx.popup() } }

                TextField {
                    id: search
                    Layout.preferredWidth: pane.width > 700 ? 210 : (pane.width > 480 ? 140 : 100)
                    placeholderText: pane.width > 480 ? "Search (Ctrl+F)" : "Search"
                    placeholderTextColor: win.muted
                    font.pixelSize: 13
                    color: theme.ink
                    leftPadding: 14
                    background: Rectangle { radius: 14; color: theme.surfaceAlt; border.color: search.activeFocus ? win.accent : "transparent" }
                    onTextChanged: paneModel.filter = text
                    onActiveFocusChanged: { if (activeFocus) pane.markActive() }
                }
            }

            // Breadcrumbs
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.preferredHeight: 26
                Row {
                    spacing: 5
                    Repeater {
                        model: paneModel.crumbs
                        delegate: Row {
                            required property var modelData
                            required property int index
                            spacing: 5
                            Text {
                                text: modelData.name; font.pixelSize: 12
                                color: index === paneModel.crumbs.length - 1 ? win.ink : win.muted
                                MouseArea { anchors.fill: parent; onClicked: { pane.activate(); paneModel.openPath(modelData.path) } }
                            }
                            Text { text: "›"; color: win.muted; font.pixelSize: 12; visible: index < paneModel.crumbs.length - 1 }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Text { text: paneModel.count + " items"; color: win.muted; font.pixelSize: 12 }
            }

            // Content
            Item {
                id: content
                Layout.fillWidth: true
                Layout.fillHeight: true
                // dropping on empty space moves/copies into this pane's folder
                readonly property string dropPath: paneModel.path

                GridView {
                    id: grid
                    anchors { fill: parent; margins: 12 }
                    visible: pane.gridMode
                    reuseItems: true
                    clip: true
                    model: paneModel
                    cellWidth: 132
                    cellHeight: 132
                    ScrollBar.vertical: ScrollBar {}

                    delegate: Item {
                        id: cell
                        required property int index
                        required property string name
                        required property string path
                        required property bool isDir
                        required property string size
                        required property string ext
                        required property int items
                        readonly property bool isSel: pane.selSet[path] === true
                        readonly property string dropPath: isDir ? path : ""
                        readonly property bool isHidden: name.charAt(0) === "."
                        readonly property bool isCut: paneModel.cutPaths.indexOf(path) >= 0
                        readonly property real dim: (isHidden ? 0.35 : 0) + (isCut ? 0.2 : 0)
                        width: grid.cellWidth
                        height: grid.cellHeight

                        Rectangle {
                            anchors { fill: parent; margins: 5 }
                            radius: 14
                            color: cell.isSel ? theme.selected : ((cma.containsMouse || win.dropItem === cell) ? theme.hover : "transparent")
                            border.width: win.dropItem === cell ? 2 : 1
                            border.color: win.dropItem === cell ? win.accent : (cell.isSel ? theme.selectedBorder : "transparent")
                        }
                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            spacing: 6
                            Item {
                                width: parent.width; height: 66
                                FolderIcon { anchors.centerIn: parent; visible: cell.isDir; dim: cell.dim }
                                FileIcon {
                                    anchors.centerIn: parent
                                    visible: !cell.isDir && !win.isImage(cell.ext)
                                    ext: cell.ext
                                    dim: cell.dim
                                    badge: win.badgeColor(cell.ext)
                                }
                                PhotoIcon {
                                    anchors.centerIn: parent
                                    visible: !cell.isDir && win.isImage(cell.ext)
                                    dim: cell.dim
                                }
                            }
                            Text {
                                width: parent.width; text: cell.name
                                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle
                                color: win.ink; font.pixelSize: 12
                            }
                            Text {
                                width: parent.width
                                text: cell.isDir ? cell.items + " items" : cell.size
                                horizontalAlignment: Text.AlignHCenter
                                color: win.muted; font.pixelSize: 10
                            }
                        }
                        MouseArea {
                            id: cma
                            property real px: 0
                            property real py: 0
                            property bool suppress: false
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true      // keep the mouse while dragging files (the view would flick)
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            onPressed: (mouse) => {
                                px = mouse.x; py = mouse.y; suppress = false
                                pane.itemPressed(cell.path, mouse.modifiers)
                            }
                            onPositionChanged: (mouse) => {
                                if (!pressed || (mouse.buttons & Qt.LeftButton) === 0) return
                                if (!win.dragging && Math.abs(mouse.x - px) + Math.abs(mouse.y - py) > 14)
                                    win.startDrag(pane, cell.path)
                                if (win.dragging)
                                    win.moveDrag(cma.mapToItem(win.contentItem, mouse.x, mouse.y), mouse.modifiers)
                            }
                            onReleased: { if (win.dragging) { suppress = true; win.endDrag() } }
                            onClicked: (mouse) => {
                                if (suppress) { suppress = false; return }
                                if (mouse.button === Qt.MiddleButton) { if (cell.isDir) win.newTab(cell.path); return }
                                pane.itemClicked(cell.path, cell.index, mouse.button, mouse.modifiers)
                            }
                            onDoubleClicked: (mouse) => { if (mouse.button === Qt.LeftButton) paneModel.activate(cell.index) }
                        }
                    }
                }

                ListView {
                    id: list
                    anchors { fill: parent; margins: 12 }
                    visible: !pane.gridMode
                    reuseItems: true
                    clip: true
                    model: paneModel
                    ScrollBar.vertical: ScrollBar {}

                    delegate: Rectangle {
                        id: row
                        required property int index
                        required property string name
                        required property string path
                        required property bool isDir
                        required property string size
                        required property string ext
                        required property string modified
                        readonly property bool isSel: pane.selSet[path] === true
                        readonly property string dropPath: isDir ? path : ""
                        readonly property bool isHidden: name.charAt(0) === "."
                        readonly property bool isCut: paneModel.cutPaths.indexOf(path) >= 0
                        readonly property real dim: (isHidden ? 0.35 : 0) + (isCut ? 0.2 : 0)
                        width: list.width
                        height: 40
                        radius: 10
                        color: row.isSel ? theme.selected : ((rma.containsMouse || win.dropItem === row) ? theme.hover : "transparent")
                        border.width: win.dropItem === row ? 2 : 0
                        border.color: win.accent
                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            spacing: 12
                            Rectangle {
                                width: 22; height: 22; radius: 6
                                color: Qt.darker(row.isDir ? "#F0A23A" : (win.isImage(row.ext) ? "#C77BA8" : win.badgeColor(row.ext)), 1 + row.dim * 2.2)
                            }
                            Text { text: row.name; Layout.fillWidth: true; elide: Text.ElideRight; color: win.ink; font.pixelSize: 13 }
                            Text { visible: pane.width > 560; text: row.modified; color: win.muted; font.pixelSize: 12; Layout.preferredWidth: 140 }
                            Text { text: row.size; color: win.muted; font.pixelSize: 12; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                        }
                        MouseArea {
                            id: rma
                            property real px: 0
                            property real py: 0
                            property bool suppress: false
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true      // keep the mouse while dragging files (the view would flick)
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            onPressed: (mouse) => {
                                px = mouse.x; py = mouse.y; suppress = false
                                pane.itemPressed(row.path, mouse.modifiers)
                            }
                            onPositionChanged: (mouse) => {
                                if (!pressed || (mouse.buttons & Qt.LeftButton) === 0) return
                                if (!win.dragging && Math.abs(mouse.x - px) + Math.abs(mouse.y - py) > 14)
                                    win.startDrag(pane, row.path)
                                if (win.dragging)
                                    win.moveDrag(rma.mapToItem(win.contentItem, mouse.x, mouse.y), mouse.modifiers)
                            }
                            onReleased: { if (win.dragging) { suppress = true; win.endDrag() } }
                            onClicked: (mouse) => {
                                if (suppress) { suppress = false; return }
                                if (mouse.button === Qt.MiddleButton) { if (row.isDir) win.newTab(row.path); return }
                                pane.itemClicked(row.path, row.index, mouse.button, mouse.modifiers)
                            }
                            onDoubleClicked: (mouse) => { if (mouse.button === Qt.LeftButton) paneModel.activate(row.index) }
                        }
                    }
                }

                // empty-area clicks: clear selection / background context menu
                MouseArea {
                    anchors { fill: parent; margins: 12 }
                    visible: !win.dragging
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: (mouse) => {
                        const v = pane.gridMode ? grid : list
                        if (v.indexAt(mouse.x + v.contentX, mouse.y + v.contentY) >= 0) {
                            mouse.accepted = false      // let the item handle it
                            return
                        }
                        pane.activate()
                        pane.clearSel()
                        if (mouse.button === Qt.RightButton) { ctx.onItem = false; ctx.popup() }
                    }
                }

                // highlight shown while dragging files over this pane
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 12
                    color: "transparent"
                    border.width: 2
                    border.color: win.accent
                    visible: win.dropItem === content && win.dragPane !== pane
                }
            }

            // Status bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                color: theme.statusBar
                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    Text {
                        text: pane.selCount > 0 ? pane.selCount + " of " + paneModel.count + " selected" : paneModel.count + " items"
                        color: win.muted; font.pixelSize: 11
                    }
                    Item { Layout.fillWidth: true }
                    Text { visible: pane.width > 520; text: pane.disk.used + " of " + pane.disk.total; color: win.muted; font.pixelSize: 11 }
                    Rectangle {
                        visible: pane.width > 520
                        Layout.preferredWidth: 80; Layout.preferredHeight: 5; radius: 2.5; color: theme.track
                        Rectangle { width: parent.width * pane.disk.fraction; height: parent.height; radius: 2.5; color: win.accent }
                    }
                    Text { text: pane.disk.free + " free"; color: win.muted; font.pixelSize: 11 }
                }
            }
        }

        // marks the active pane while split view is on
        Rectangle {
            width: parent.width
            height: 2
            color: win.accent
            visible: pane.showActive && pane.isActive
        }
    }

    // ---------- one tab = one pane, or two panes side by side ----------
    component TabPage: Item {
        id: tabPage
        required property int index
        required property string startPath
        required property bool split
        property var lastPane: null
        readonly property alias leftPane: leftPaneItem
        readonly property var rightPane: rightLoader.item
        readonly property bool current: StackLayout.isCurrentItem

        onCurrentChanged: { if (current) win.activePane = (lastPane ? lastPane : leftPaneItem) }
        Component.onCompleted: tabsModel.setProperty(index, "title", leftPaneItem.title)

        Connections {
            target: leftPaneItem
            function onTitleChanged() { tabsModel.setProperty(tabPage.index, "title", leftPaneItem.title) }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            Pane {
                id: leftPaneItem
                Layout.fillWidth: true
                Layout.fillHeight: true
                startPath: tabPage.startPath
                showActive: tabPage.split
                sibling: rightLoader.item
                onActivated: tabPage.lastPane = leftPaneItem
            }
            Rectangle { visible: tabPage.split; Layout.fillHeight: true; Layout.preferredWidth: 1; color: theme.line }
            Loader {
                id: rightLoader
                active: tabPage.split
                visible: active
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: Component {
                    Pane {
                        id: rightPaneItem
                        startPath: leftPaneItem.fileModel.path
                        showActive: true
                        sibling: leftPaneItem
                        onActivated: tabPage.lastPane = rightPaneItem
                    }
                }
            }
        }
    }

    // ---------- menus ----------
    Menu {
        id: ctx
        property bool onItem: false
        background: Rectangle { implicitWidth: 240; radius: 12; color: theme.surface; border.color: win.line }

        TMenuItem { text: "Open"; enabled: ctx.onItem && win.selCount > 0; onTriggered: win.doOpen() }
        TMenuItem { text: "Open in new tab"; enabled: ctx.onItem && win.selCount === 1 && win.info.isDir === true; onTriggered: win.newTab(win.selectedPath) }
        TSep {}
        TMenuItem { text: "Cut";   enabled: ctx.onItem && win.selCount > 0; onTriggered: win.doCut() }
        TMenuItem { text: "Copy";  enabled: ctx.onItem && win.selCount > 0; onTriggered: win.doCopy() }
        TMenuItem { text: "Paste"; enabled: fm.canPaste; onTriggered: win.doPaste() }
        TMenuItem { text: "Duplicate"; enabled: ctx.onItem && win.selCount > 0; onTriggered: win.doDuplicate() }
        TSep {}
        TMenuItem { text: "Copy to other pane   F5"; enabled: ctx.onItem && win.selCount > 0 && win.currentSplit; onTriggered: win.sendToOther(false) }
        TMenuItem { text: "Move to other pane   F6"; enabled: ctx.onItem && win.selCount > 0 && win.currentSplit; onTriggered: win.sendToOther(true) }
        TSep {}
        TMenuItem { text: "Rename";        enabled: ctx.onItem && win.selCount === 1; onTriggered: win.askRename() }
        TMenuItem { text: "Move to Trash"; enabled: ctx.onItem && win.selCount > 0; onTriggered: win.doTrash() }
        TMenuItem { text: "Delete permanently…"; enabled: ctx.onItem && win.selCount > 0; onTriggered: win.askDelete() }
        TMenuItem {
            text: win.selPinned ? "Unpin from sidebar" : "Pin to sidebar"
            enabled: ctx.onItem && win.selCount === 1 && win.info.isDir === true
            onTriggered: win.selPinned ? fm.unpin(win.selectedPath) : fm.pin(win.selectedPath)
        }
        TSep {}
        TMenuItem { text: "New folder"; onTriggered: win.askNew("folder") }
        TMenuItem { text: "New file";   onTriggered: win.askNew("file") }
        TMenuItem { text: "New tab   Ctrl+T"; onTriggered: win.newTab("") }
        TMenuItem { text: win.currentSplit ? "Close split view   Ctrl+\\" : "Split view   Ctrl+\\"; onTriggered: win.toggleSplit() }
        TMenuItem { text: "Open terminal here"; onTriggered: fm.openTerminal() }
        TSep {}
        TMenuItem { text: "Undo"; enabled: fm.canUndo; onTriggered: win.doUndo() }
        TMenuItem { text: "Redo"; enabled: fm.canRedo; onTriggered: win.doRedo() }
        TMenuItem { text: "Select all"; onTriggered: win.selectAll() }
        TMenuItem {
            text: (fm.showHidden ? "Hide" : "Show") + " hidden files"
            onTriggered: fm.showHidden = !fm.showHidden
        }
    }

    Menu {
        id: sortMenu
        background: Rectangle { implicitWidth: 180; radius: 12; color: theme.surface; border.color: win.line }
        TMenuItem { text: win.sortLabel(0, "Name");     onTriggered: fm.setSort(0) }
        TMenuItem { text: win.sortLabel(1, "Size");     onTriggered: fm.setSort(1) }
        TMenuItem { text: win.sortLabel(2, "Modified"); onTriggered: fm.setSort(2) }
        TMenuItem { text: win.sortLabel(3, "Type");     onTriggered: fm.setSort(3) }
    }

    Menu {
        id: pinMenu
        property string targetPath: ""
        background: Rectangle { implicitWidth: 190; radius: 12; color: theme.surface; border.color: win.line }
        TMenuItem { text: "Open in new tab"; onTriggered: win.newTab(pinMenu.targetPath) }
        TMenuItem { text: "Unpin from sidebar"; onTriggered: fm.unpin(pinMenu.targetPath) }
    }

    // ---------- dialogs ----------
    Popup {
        id: nameDialog
        property string mode: "rename"       // rename | folder | file
        property string heading: ""
        property string target: ""
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        width: 340
        padding: 20
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: theme.overlay }
        background: Rectangle { radius: 16; color: theme.dialog; border.color: win.line }

        function openFor(m, h, text, t) {
            mode = m; heading = h; target = t
            nameField.text = text
            open()
        }
        function accept() {
            const v = nameField.text.trim()
            let created = ""
            if (mode === "rename")      created = fm.rename(target, v) ? v : ""
            else if (mode === "folder") created = fm.newFolder(v)
            else                        created = fm.newFile(v)
            close()
            if (created !== "") win.selectName(created)
        }
        onOpened: {
            nameField.forceActiveFocus()
            const t = nameField.text
            const dot = t.lastIndexOf(".")
            nameField.select(0, (mode === "rename" && dot > 0) ? dot : t.length)
        }

        contentItem: ColumnLayout {
            spacing: 14
            Text { text: nameDialog.heading; font.bold: true; font.pixelSize: 15; color: win.ink }
            TextField {
                id: nameField
                Layout.fillWidth: true
                font.pixelSize: 13
                color: win.ink
                leftPadding: 12
                background: Rectangle {
                    radius: 10; color: theme.input
                    border.color: nameField.activeFocus ? win.accent : win.line
                }
                onAccepted: nameDialog.accept()
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8
                Pill { text: "Cancel"; onClicked: nameDialog.close() }
                Pill { text: nameDialog.mode === "rename" ? "Rename" : "Create"; primary: true; onClicked: nameDialog.accept() }
            }
        }
    }

    Popup {
        id: confirmDialog
        property var targets: []
        property string label: ""
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        width: 340
        padding: 20
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: theme.overlay }
        background: Rectangle { radius: 16; color: theme.dialog; border.color: win.line }

        function openFor(t, l) { targets = t; label = l; open() }

        contentItem: ColumnLayout {
            spacing: 12
            Text { text: "Delete permanently?"; font.bold: true; font.pixelSize: 15; color: win.ink }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: win.muted; font.pixelSize: 13
                text: "“" + confirmDialog.label + "” will be deleted for good. This can't be undone."
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8
                Pill { text: "Cancel"; onClicked: confirmDialog.close() }
                Pill {
                    text: "Delete"; danger: true
                    onClicked: { fm.removeItems(confirmDialog.targets); confirmDialog.close() }
                }
            }
        }
    }

    // ---------- theme palette (Ctrl+P) ----------
    Popup {
        id: theme_palette
        property bool accepted: false
        property var shown: []
        parent: Overlay.overlay
        x: Math.round((Overlay.overlay.width - width) / 2)
        y: Math.round(Overlay.overlay.height * 0.14)
        width: 420
        padding: 14
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: theme.overlay }
        background: Rectangle { radius: 16; color: theme.dialog; border.color: theme.line }

        function refresh() {
            const q = tpField.text.trim().toLowerCase()
            shown = theme.names.filter(n => n.toLowerCase().indexOf(q) >= 0)
        }
        function openPalette() {
            if (visible) { close(); return }
            accepted = false
            tpField.text = ""
            refresh()
            tpList.currentIndex = Math.max(0, shown.indexOf(theme.active))
            open()
        }
        function choose(i) {
            if (i < 0 || i >= shown.length) return
            theme.apply(shown[i])
            accepted = true
            close()
        }
        onOpened: tpField.forceActiveFocus()
        onClosed: { if (!accepted) theme.cancelPreview() }

        contentItem: ColumnLayout {
            spacing: 10
            Text { text: "COLOR THEME"; color: theme.muted; font.pixelSize: 10; font.letterSpacing: 1 }
            TextField {
                id: tpField
                Layout.fillWidth: true
                placeholderText: "Search themes…"
                placeholderTextColor: theme.muted
                color: theme.ink
                font.pixelSize: 14
                leftPadding: 12
                background: Rectangle {
                    radius: 10; color: theme.input
                    border.color: tpField.activeFocus ? theme.accent : theme.line
                }
                onTextChanged: { theme_palette.refresh(); tpList.currentIndex = 0 }
                onAccepted: theme_palette.choose(tpList.currentIndex)
                Keys.onUpPressed: tpList.currentIndex = Math.max(0, tpList.currentIndex - 1)
                Keys.onDownPressed: tpList.currentIndex = Math.min(theme_palette.shown.length - 1, tpList.currentIndex + 1)
            }
            ListView {
                id: tpList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(1, count) * 48
                interactive: false
                model: theme_palette.shown
                onCurrentIndexChanged: {
                    if (theme_palette.visible && currentIndex >= 0 && currentIndex < theme_palette.shown.length)
                        theme.preview(theme_palette.shown[currentIndex])
                }
                delegate: Rectangle {
                    id: trow
                    required property string modelData
                    required property int index
                    readonly property var tc: theme.colorsOf(modelData)
                    width: tpList.width
                    height: 44
                    radius: 10
                    color: ListView.isCurrentItem ? theme.selected : "transparent"
                    border.color: ListView.isCurrentItem ? theme.selectedBorder : "transparent"
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12
                        Rectangle {
                            Layout.preferredWidth: 50; Layout.preferredHeight: 24
                            radius: 12; color: trow.tc.bg; border.color: trow.tc.line
                            Row {
                                anchors.centerIn: parent; spacing: 4
                                Rectangle { width: 10; height: 10; radius: 5; color: trow.tc.accent }
                                Rectangle { width: 10; height: 10; radius: 5; color: trow.tc.ink }
                                Rectangle { width: 10; height: 10; radius: 5; color: trow.tc.sidebar; border.color: trow.tc.line }
                            }
                        }
                        Text { text: trow.modelData; Layout.fillWidth: true; color: theme.ink; font.pixelSize: 14 }
                        Text { text: theme.find(trow.modelData).dark ? "Dark" : "Light"; color: theme.muted; font.pixelSize: 11 }
                        Text { text: "✓"; visible: trow.modelData === theme.saved; color: theme.accent; font.bold: true }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: { if (tpList.currentIndex !== trow.index) tpList.currentIndex = trow.index }
                        onClicked: theme_palette.choose(trow.index)
                    }
                }
            }
            Text {
                text: "↑ ↓ preview   ·   Enter apply   ·   Esc cancel"
                color: theme.muted; font.pixelSize: 11
            }
        }
    }

    // ---------- floating bits ----------
    Item {
        id: dragProxy
        width: 0
        height: 0
        z: 200
        visible: win.dragging
        Rectangle {
            x: 12; y: 12
            width: dragLabel.implicitWidth + 24
            height: 30
            radius: 15
            color: win.accent
            Text {
                id: dragLabel
                anchors.centerIn: parent
                color: theme.onAccent; font.pixelSize: 12; font.bold: true
                text: (win.dragCopy ? "Copy " : "Move ") + win.dragPaths.length
                      + (win.dragPaths.length === 1 ? " item" : " items")
            }
        }
    }

    Rectangle {
        id: toast
        property string msg: ""
        function show(m) { msg = m; opacity = 1; hideTimer.restart() }
        z: 100
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - 76
        width: toastText.implicitWidth + 36
        height: 38
        radius: 19
        color: theme.toastBg
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Text { id: toastText; anchors.centerIn: parent; text: toast.msg; color: theme.toastFg; font.pixelSize: 13 }
        Timer { id: hideTimer; interval: 3200; onTriggered: toast.opacity = 0 }
    }

    // ---------- layout ----------
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar
        Rectangle {
            Layout.preferredWidth: 210
            Layout.fillHeight: true
            color: theme.sidebar

            Column {
                anchors { fill: parent; margins: 14 }
                spacing: 3

                Row {
                    spacing: 10
                    Rectangle {
                        width: 28; height: 28; radius: 8; color: theme.logoBg
                        Text { anchors.centerIn: parent; text: "F"; color: win.accent; font.bold: true; font.pixelSize: 15 }
                    }
                    Text { text: "Files"; color: win.ink; font.bold: true; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
                }
                Item { width: 1; height: 16 }
                Text { text: "FAVORITES"; color: win.muted; font.pixelSize: 10; font.letterSpacing: 1; leftPadding: 4; bottomPadding: 4 }
                SideItem { label: "Home";        key: "home";      dot: "#E8922A" }
                SideItem { label: "Desktop";     key: "desktop";   dot: "#4A90D9" }
                SideItem { label: "Documents";   key: "documents"; dot: "#8E5BD6" }
                SideItem { label: "Downloads";   key: "downloads"; dot: "#3FA066" }
                SideItem { label: "Pictures";    key: "pictures";  dot: "#D6478A" }

                Item { width: 1; height: 16; visible: fm.pinned.length > 0 }
                Text {
                    text: "PINNED"; visible: fm.pinned.length > 0
                    color: win.muted; font.pixelSize: 10; font.letterSpacing: 1; leftPadding: 4; bottomPadding: 4
                }
                Repeater {
                    model: fm.pinned
                    delegate: SideItem {
                        required property string modelData
                        label: modelData.split("/").filter(x => x.length > 0).pop() || "/"
                        path: modelData
                        pinnedItem: true
                        dot: "#C9A227"
                    }
                }

                Item { width: 1; height: 16 }
                Text { text: "LOCATIONS"; color: win.muted; font.pixelSize: 10; font.letterSpacing: 1; leftPadding: 4; bottomPadding: 4 }
                SideItem { label: "Computer";    key: "root";      dot: "#8C8577" }
            }
        }

        // Center: tab bar + pages
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Tab bar
            Rectangle {
                id: tabBar
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                color: theme.sidebar

                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 6

                    Row {
                        spacing: 4
                        Repeater {
                            model: tabsModel
                            delegate: Rectangle {
                                id: tabChip
                                required property int index
                                required property string title
                                readonly property bool cur: index === win.currentTab
                                width: Math.max(96, Math.min(190, (tabBar.width - 190) / Math.max(1, tabsModel.count) - 4))
                                height: 32
                                radius: 9
                                color: cur ? theme.bg : (tcm.containsMouse ? theme.sideHover : "transparent")
                                border.color: cur ? theme.line : "transparent"

                                Text {
                                    anchors { left: parent.left; leftMargin: 12; right: closeBtn.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                    text: tabChip.title !== "" ? tabChip.title : "Files"
                                    elide: Text.ElideRight
                                    color: tabChip.cur ? theme.ink : theme.muted
                                    font.pixelSize: 12
                                    font.bold: tabChip.cur
                                }
                                MouseArea {
                                    id: tcm
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.MiddleButton) win.closeTab(tabChip.index)
                                        else win.currentTab = tabChip.index
                                    }
                                }
                                Rectangle {
                                    id: closeBtn
                                    visible: tabsModel.count > 1
                                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                    width: 20; height: 20; radius: 6
                                    color: cma2.containsMouse ? theme.btnHover : "transparent"
                                    Text { anchors.centerIn: parent; text: "×"; color: theme.muted; font.pixelSize: 14 }
                                    MouseArea {
                                        id: cma2
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: win.closeTab(tabChip.index)
                                    }
                                }
                            }
                        }
                    }
                    IconBtn { text: "+"; onClicked: win.newTab("") }
                    Item { Layout.fillWidth: true }
                    IconBtn { text: "◫"; active: win.currentSplit; onClicked: win.toggleSplit() }
                    IconBtn { text: "◐"; onClicked: theme_palette.openPalette() }
                }
            }

            StackLayout {
                id: tabStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.currentTab

                Repeater {
                    id: tabRepeater
                    model: tabsModel
                    delegate: TabPage {}
                }
            }
        }

        // Details panel (hidden in split view to give the panes room)
        Rectangle {
            visible: !win.currentSplit
            Layout.preferredWidth: 270
            Layout.fillHeight: true
            color: theme.bg
            Rectangle { width: 1; height: parent.height; color: win.line }

            Text {
                anchors.centerIn: parent
                visible: win.selCount === 0
                text: "Select an item to see details"
                color: win.muted; font.pixelSize: 12
            }

            ColumnLayout {
                visible: win.selCount > 0
                anchors { fill: parent; margins: 18 }
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 130
                    radius: 14
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#1E1B16" }
                        GradientStop { position: 1; color: "#3A2E1C" }
                    }
                    Rectangle {
                        width: 64; height: 64; radius: 32; color: win.accent
                        anchors { right: parent.right; top: parent.top; margins: 18 }
                    }
                    Column {
                        anchors { left: parent.left; bottom: parent.bottom; margins: 16 }
                        spacing: 4
                        Rectangle { width: 22; height: 2; color: win.accent }
                        Text {
                            text: win.selCount > 1 ? win.selCount + " items"
                                                   : (win.info.isDir ? "Folder" : (win.info.ext || "File"))
                            color: "white"; font.bold: true; font.pixelSize: 20
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: win.selCount > 1 ? win.selCount + " items selected" : (win.info.name || "")
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    color: win.ink; font.bold: true; font.pixelSize: 14
                }
                Text {
                    Layout.fillWidth: true
                    text: win.selCount > 1 ? win.multi.folders + " folders · " + win.multi.files + " files"
                                           : (win.info.kind || "") + " · " + (win.info.size || "")
                    horizontalAlignment: Text.AlignHCenter
                    color: win.muted; font.pixelSize: 11
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: win.line }

                Text { text: "Information"; color: win.ink; font.bold: true; font.pixelSize: 12 }
                InfoRow { visible: win.selCount === 1; label: "Created";  value: win.info.created || "" }
                InfoRow { visible: win.selCount === 1; label: "Modified"; value: win.info.modified || "" }
                InfoRow { visible: win.selCount === 1; label: "Where";    value: win.info.where || "" }
                InfoRow { visible: win.selCount > 1; label: "Folders";    value: "" + (win.multi.folders || 0) }
                InfoRow { visible: win.selCount > 1; label: "Files";      value: "" + (win.multi.files || 0) }
                InfoRow { visible: win.selCount > 1; label: "Files size"; value: win.multi.size || "" }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 38; radius: 12; color: win.accent
                        Text {
                            anchors.centerIn: parent
                            text: win.selCount === 1 ? "Open" : "Copy"
                            color: theme.onAccent; font.bold: true; font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: win.selCount === 1 ? win.doOpen() : win.doCopy()
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 38; radius: 12
                        color: theme.surface; border.color: win.line
                        Text {
                            anchors.centerIn: parent
                            text: win.selCount === 1 ? "Rename" : "Trash"
                            color: win.ink; font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: win.selCount === 1 ? win.askRename() : win.doTrash()
                        }
                    }
                }
            }
        }
    }
}
