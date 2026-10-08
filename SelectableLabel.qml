import QtQuick 2.15

TextEdit {
    readOnly: true
    selectByMouse: true
    selectByKeyboard: true
    cursorVisible: false
    textMargin: 0
    property int elide: Text.ElideNone
}
