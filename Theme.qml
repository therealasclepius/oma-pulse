import QtQuick
import qs.Commons

QtObject {
    readonly property color background: Color.background
    readonly property color text: Color.foreground
    readonly property color accent: Color.accent
    readonly property color muted: blend(Color.background, Color.foreground, 0.66)
    readonly property color urgent: Color.urgent
    readonly property color border: blend(Color.background, Color.accent, 0.4)
    readonly property color surface: blend(Color.background, Color.foreground, 0.065)
    readonly property color raised: blend(Color.background, Color.foreground, 0.11)
    readonly property color hover: blend(Color.background, Color.accent, 0.2)
    readonly property color tasks: blend(Color.background, Color.accent, 0.10)
    readonly property color focus: blend(Color.background, Color.accent, 0.16)
    readonly property color notes: blend(Color.background, Color.foreground, 0.075)
    readonly property color events: blend(Color.background, Color.accent, 0.065)
    readonly property color mail: blend(Color.background, Color.accent, 0.12)
    readonly property string font: Style.font.family
    function blend(base, tint, amount) { return Qt.rgba(base.r * (1-amount) + tint.r * amount, base.g * (1-amount) + tint.g * amount, base.b * (1-amount) + tint.b * amount, 1); }
    function alpha(color, amount) { return Qt.rgba(color.r, color.g, color.b, amount); }
}
