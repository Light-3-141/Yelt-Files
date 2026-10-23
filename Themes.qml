import QtQuick

// All colours used by the UI live here. To add a theme, append one entry to `all`.
QtObject {
    id: root

    readonly property var all: [
        {   // the original look, kept as-is
            name: "Cream", dark: false,
            c: {
                bg: "#FBF9F4",        sidebar: "#F5F1E8",     statusBar: "#F8F5EE",
                surface: "#FFFFFF",   surfaceAlt: "#F3EEE3",  dialog: "#FBF9F4",   input: "#FFFFFF",
                ink: "#2A2620",       muted: "#9A9286",       line: "#EDE8DD",
                accent: "#E8922A",    onAccent: "#FFFFFF",
                hover: "#F6F2E9",     selected: "#FBEBD3",    selectedBorder: "#F2D4A6",
                sideHover: "#EFE9DC", sideSelected: "#F1E3CC",
                btnActive: "#FFFFFF", btnHover: "#F0EBE0",
                fileCard: "#FFFFFF",  fileStroke: "#E6E0D2",  fileFlap: "#F1ECE1",
                track: "#E8E2D4",     logoBg: "#1E1B16",
                toastBg: "#2A2620",   toastFg: "#FFFFFF",     overlay: "#33000000"
            }
        },
        {
            name: "Midnight", dark: true,
            c: {
                bg: "#1B1915",        sidebar: "#15130F",     statusBar: "#171511",
                surface: "#26231D",   surfaceAlt: "#322E27",  dialog: "#26231D",   input: "#1B1915",
                ink: "#F1ECE2",       muted: "#8F887B",       line: "#35312A",
                accent: "#F0A23A",    onAccent: "#1B1915",
                hover: "#25221C",     selected: "#3A2C18",    selectedBorder: "#6B4A1E",
                sideHover: "#201D17", sideSelected: "#3A2C18",
                btnActive: "#3A362E", btnHover: "#2B2822",
                fileCard: "#2E2A23",  fileStroke: "#443F35",  fileFlap: "#3B372F",
                track: "#35312A",     logoBg: "#2E2A23",
                toastBg: "#F1ECE2",   toastFg: "#1B1915",     overlay: "#99000000"
            }
        }
    ]

    readonly property var names: all.map(t => t.name)

    // `saved` is loaded/stored by Main.qml (through the C++ side); `previewName` is
    // only set while browsing the palette
    property string saved: "Cream"
    property string previewName: ""
    readonly property string active: previewName !== "" ? previewName : saved
    signal applied(string name)

    function find(name) {
        for (let i = 0; i < all.length; ++i)
            if (all[i].name === name) return all[i]
        return all[0]
    }
    function colorsOf(name) { return find(name).c }
    function preview(name) { previewName = name }
    function cancelPreview() { previewName = "" }
    function apply(name) { saved = name; previewName = ""; applied(name) }

    readonly property var cur: find(active).c
    readonly property bool dark: find(active).dark

    readonly property color bg: cur.bg
    readonly property color sidebar: cur.sidebar
    readonly property color statusBar: cur.statusBar
    readonly property color surface: cur.surface
    readonly property color surfaceAlt: cur.surfaceAlt
    readonly property color dialog: cur.dialog
    readonly property color input: cur.input
    readonly property color ink: cur.ink
    readonly property color muted: cur.muted
    readonly property color line: cur.line
    readonly property color accent: cur.accent
    readonly property color onAccent: cur.onAccent
    readonly property color hover: cur.hover
    readonly property color selected: cur.selected
    readonly property color selectedBorder: cur.selectedBorder
    readonly property color sideHover: cur.sideHover
    readonly property color sideSelected: cur.sideSelected
    readonly property color btnActive: cur.btnActive
    readonly property color btnHover: cur.btnHover
    readonly property color fileCard: cur.fileCard
    readonly property color fileStroke: cur.fileStroke
    readonly property color fileFlap: cur.fileFlap
    readonly property color track: cur.track
    readonly property color logoBg: cur.logoBg
    readonly property color toastBg: cur.toastBg
    readonly property color toastFg: cur.toastFg
    readonly property color overlay: cur.overlay
}
