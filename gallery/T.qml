import QtQuick

// plain text only: a network or device name must never be read as markup
Text {
    color: S.white
    font.family: S.font
    font.pixelSize: 17
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
}
