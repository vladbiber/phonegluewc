import QtQuick

Page {
    id: root
    readonly property string layout: S.config.xkb_layout || "us"
    property bool cleared: false
    property bool clipCleared: false
    property bool emojiCleared: false
    property var installed: []
    // the keyboard reads on/off and true/false; anything else is the default
    function isOn(key, def) {
        const v = S.kbd[key];
        return v === "on" || v === "true" ? true : v === "off" || v === "false" ? false : def !== false;
    }
    function flip(key, def) { S.save(["set", "kbd", key, isOn(key, def) ? "off" : "on"]); }
    function pick(key, options, def) { return options.some(o => o.value === S.kbd[key]) ? S.kbd[key] : def; }
    // no line means English plus every installed pack; an empty line means none
    readonly property var predicting: S.kbd.predict_languages === undefined ? ["en"].concat(installed)
                                      : S.kbd.predict_languages.split(" ").filter(c => c !== "")
    function togglePredict(code) {
        const on = predicting.indexOf(code) >= 0;
        const next = ["en"].concat(installed).filter(c => c === code ? !on : predicting.indexOf(c) >= 0);
        S.save(["set", "kbd", "predict_languages", next.join(" ")]);
    }
    function nameOf(code) {
        const n = code === "en" ? "English" : Qt.locale(code).nativeLanguageName;
        return n && Qt.locale(code).name !== "C" ? n[0].toUpperCase() + n.slice(1) : code;
    }
    Cmd { id: langs; onDone: root.installed = S.lines(out).filter(c => LangJob.valid(c)) }
    Component.onCompleted: langs.run([S.pset, "kbd-langs"])

    Section { text: "On-screen keyboard" }
    RowItem {
        label: "Word suggestions"
        sub: "Suggests words while you type"
        onTapped: root.flip("predict")
        Toggle { on: root.isOn("predict") }
    }
    RowItem {
        label: "Autocorrect"
        sub: "Fixes likely typos when you finish a word"
        onTapped: root.flip("autocorrect")
        Toggle { on: root.isOn("autocorrect") }
    }
    RowItem {
        label: "Learn my words"
        sub: "Remembers new words you type, on this phone only"
        onTapped: root.flip("learn")
        Toggle { on: root.isOn("learn") }
    }
    Cmd { id: emojiClearer; onDone: code => { if (code !== 0) S.saveError = "Could not delete the recent emoji."; } }
    RowItem {
        label: "Emoji history"
        sub: root.isOn("learn") ? "Keeps recent emoji on this phone. Turning it off deletes them"
                                : "Not recording: Learn my words is off. Turning this off deletes recent emoji"
        onTapped: {
            const wasOn = root.isOn("emoji_history");
            root.flip("emoji_history");
            if (wasOn && S.has("phonekbd"))
                emojiClearer.run(["phonekbd", "--clear-emoji-history"]);
        }
        Toggle { on: root.isOn("emoji_history") }
    }
    RowItem {
        label: "Clipboard history"
        sub: "Recent copies, in memory only, never on disk"
        onTapped: root.flip("clipboard_history")
        Toggle { on: root.isOn("clipboard_history") }
    }
    Cmd {
        id: clipClearer
        onDone: code => {
            if (code === 0)
                root.clipCleared = true;
            else
                S.saveError = "Could not clear the clipboard history.";
        }
    }
    RowItem {
        visible: S.has("phonekbd")
        label: "Clear clipboard history"
        sub: (root.clipCleared ? "Will empty" : "Empties") + " the next time the keyboard appears or sees a copy"
        tappable: false
        Btn {
            text: "Clear"
            confirm: true
            enabled_: root.isOn("clipboard_history")
            onTapped: clipClearer.run(["phonekbd", "--clear-clipboard-history"])
        }
    }
    RowItem {
        label: "Laptop layout"
        sub: "Wider, with a number row"
        onTapped: S.save(["kbd-layout", S.kbdLayout === "laptop" ? "normal" : "laptop"])
        Toggle { on: S.kbdLayout === "laptop" }
    }
    Cmd {
        id: clearer
        onDone: code => {
            if (code === 0)
                root.cleared = true;
            else
                S.saveError = "Could not clear the learned words.";
        }
    }
    RowItem {
        visible: S.has("phonekbd")
        label: "Learned words"
        sub: root.cleared ? "Cleared" : "Removes learned words, word pairs and recent emoji"
        tappable: false
        Btn { text: "Clear"; confirm: true; onTapped: clearer.run(["phonekbd", "--clear-learned"]) }
    }
    Note {
        visible: S.toolsReady && !S.has("phonekbd")
        problem: true
        text: "Clearing keyboard data needs the phonekbd keyboard, and it is not installed."
    }

    Cmd {
        id: emojiNow
        onDone: code => {
            if (code === 0)
                root.emojiCleared = true;
            else
                S.saveError = "Could not delete the recent emoji.";
        }
    }
    RowItem {
        visible: S.has("phonekbd")
        label: "Recent emoji"
        sub: root.emojiCleared ? "Deleted" : "Deletes the recent emoji list"
        tappable: false
        Btn { text: "Clear"; confirm: true; onTapped: emojiNow.run(["phonekbd", "--clear-emoji-history"]) }
    }
    RowItem {
        label: "Languages"
        sub: "Download typing and translation languages"
        chevron: true
        onTapped: S.open("languages")
    }

    Section { text: "Suggestions and corrections in" }
    Repeater {
        model: ["en"].concat(root.installed)
        delegate: RowItem {
            required property string modelData
            label: root.nameOf(modelData)
            onTapped: root.togglePredict(modelData)
            Toggle { on: root.predicting.indexOf(modelData) >= 0 }
        }
    }
    Note {
        visible: root.predicting.length === 0
        text: "No suggestions or corrections. Holding a letter still shows its accents."
    }

    Section { text: "Typing" }
    RowItem {
        label: "Capitals after a full stop"
        sub: "Starts sentences with a capital letter"
        onTapped: root.flip("autocap")
        Toggle { on: root.isOn("autocap") }
    }
    RowItem {
        label: "Double space for a full stop"
        onTapped: root.flip("double_space")
        Toggle { on: root.isOn("double_space") }
    }
    RowItem {
        label: "Move the cursor with the space bar"
        sub: "Drag along the space bar"
        onTapped: root.flip("space_cursor")
        Toggle { on: root.isOn("space_cursor") }
    }
    Section { text: "Hold a key for its symbol after" }
    Chips {
        readonly property var opts: [{ value: "short", label: "Short" }, { value: "normal", label: "Normal" }, { value: "long", label: "Long" }]
        options: opts
        current: root.pick("long_press", opts, "normal")
        onPicked: v => S.save(["set", "kbd", "long_press", v])
    }

    Section { text: "Look" }
    Chips {
        readonly property var opts: [{ value: "small", label: "Small" }, { value: "normal", label: "Normal" }, { value: "large", label: "Large" }]
        options: opts
        current: root.pick("height", opts, "normal")
        onPicked: v => S.save(["set", "kbd", "height", v])
    }
    Section { text: "Theme" }
    Chips {
        readonly property var opts: [{ value: "phone", label: "Like the phone" }, { value: "dark", label: "Dark" }, { value: "light", label: "Light" }, { value: "system", label: "Like the system" },
                                     { value: "contrast", label: "High contrast" }, { value: "red", label: "Red" }]
        options: opts
        current: S.kbd.theme === "nothing" ? "dark" : root.pick("theme", opts, "phone")
        onPicked: v => S.save(["set", "kbd", "theme", v])
    }
    Section { text: "Key colour" }
    Chips {
        // shortcut: "theme" is no colour, so the keyboard falls back to the theme's own; ask for a real value if it starts refusing it
        readonly property var opts: [{ value: "theme", label: "Like the phone" }, { value: "red", label: "Red" }, { value: "orange", label: "Orange" },
                                     { value: "yellow", label: "Yellow" }, { value: "green", label: "Green" }, { value: "blue", label: "Blue" }, { value: "purple", label: "Purple" }]
        options: opts
        current: root.pick("accent", opts, "theme")
        onPicked: v => S.save(["set", "kbd", "accent", v])
    }
    RowItem {
        label: "Number row"
        onTapped: root.flip("number_row", false)
        Toggle { on: root.isOn("number_row", false) }
    }
    RowItem {
        label: "Key borders"
        onTapped: root.flip("key_borders")
        Toggle { on: root.isOn("key_borders") }
    }
    RowItem {
        label: "Symbol hints"
        sub: "Shows the held symbol in the corner of a key"
        onTapped: root.flip("corner_hints")
        Toggle { on: root.isOn("corner_hints") }
    }
    RowItem {
        label: "Key preview"
        sub: "A bubble over the pressed key, never on password fields"
        onTapped: root.flip("key_preview")
        Toggle { on: root.isOn("key_preview") }
    }

    Section { text: "Sound and vibration" }
    RowItem {
        label: "Key sound"
        sub: "Quiet while the ringer is on vibrate or silent"
        onTapped: root.flip("sound", false)
        Toggle { on: root.isOn("sound", false) }
    }
    RowItem {
        visible: S.has("fbcli")
        label: "Vibrate on keys"
        onTapped: root.flip("vibrate", false)
        Toggle { on: root.isOn("vibrate", false) }
    }
    Note { text: "Changes apply the next time the keyboard appears." }

    Section { text: "Language of a connected hardware keyboard" }
    Chips {
        options: [{ value: "us", label: "English US" }, { value: "gb", label: "English UK" }, { value: "ro", label: "Romanian" },
                  { value: "de", label: "German" }, { value: "fr", label: "French" }, { value: "es", label: "Spanish" }, { value: "it", label: "Italian" }]
        current: root.layout
        onPicked: v => S.save(["set", "config", "xkb_layout", v])
    }
}
