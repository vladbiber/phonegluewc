// the three widget looks as plain colours; glass is the Apple look on the lock, over the wallpaper
.pragma library

const names = { "nothing-dark": "Nothing dark", "nothing-light": "Nothing light", "apple": "Apple" };

function of(style, glass) {
    if (style === "nothing-light")
        return { tile: "#ffffff", alt: "#111111", altInk: "#f5f5f5", ink: "#111111", dim: "#7a7a7a", accent: "#d71921",
            on: "#d71921", onInk: "#ffffff", track: "#e3e3e3", radius: 0.22, dots: true, weight: 400 };
    if (style === "apple") {
        if (glass)
            return { tile: Qt.rgba(1, 1, 1, 0.2), alt: Qt.rgba(1, 1, 1, 0.2), altInk: "#ffffff", ink: "#ffffff", dim: Qt.rgba(1, 1, 1, 0.7),
                accent: "#ffffff", on: "#ffffff", onInk: "#111111", track: Qt.rgba(1, 1, 1, 0.3), radius: 0.24, dots: false, weight: 700 };
        return { tile: "#ffffff", alt: "#ffffff", altInk: "#111111", ink: "#111111", dim: "#8a8a8e", accent: "#ff3b30",
            on: "#34c759", onInk: "#ffffff", track: "#e9e9ee", radius: 0.24, dots: false, weight: 700, ring: "#34c759" };
    }
    return { tile: "#1c1c1c", alt: "#f2f2f2", altInk: "#111111", ink: "#f2f2f2", dim: "#8c8c8c", accent: "#d71921",
        on: "#d71921", onInk: "#ffffff", track: "#333333", radius: 0.22, dots: true, weight: 400 };
}
