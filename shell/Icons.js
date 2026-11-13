// the status icons as SVG on a 24 grid, one colour and optional level, returned as a data URL
.pragma library

function line(c, d, w) {
    return `<path fill="none" stroke="${c}" stroke-width="${w || 2}" stroke-linecap="round" stroke-linejoin="round" d="${d}"/>`;
}
function wedge(r) {
    const k = (r * Math.SQRT1_2).toFixed(2);
    return `M12 20L${12 - k} ${20 - k}A${r} ${r} 0 0 1 ${+k + 12} ${20 - k}Z`;
}
function bars(level) {
    let out = "";
    for (let i = 0; i < 4; i++)
        out += `<rect x="${3 + i * 4.8}" y="${15 - i * 4}" width="3.4" height="${6 + i * 4}" rx="1" opacity="${i < level ? 1 : 0.3}"/>`;
    return out;
}
function speaker(c, rest) {
    return `<path d="M3 9.5v5h4l5 5v-15l-5 5z"/>` + rest;
}
function battery(c, level, charging) {
    const h = 14.6 * Math.max(4, Math.min(100, level)) / 100;
    return `<rect x="9.5" y="1.5" width="5" height="2.5" rx="1"/>`
        + `<rect x="6.8" y="3.8" width="10.4" height="18.4" rx="2.4" fill="none" stroke="${c}" stroke-width="1.6"/>`
        + `<rect x="8.7" y="${20.3 - h}" width="6.6" height="${h}" rx="0.8"/>`
        + (charging ? `<path fill="#000000" stroke="#000000" stroke-width="0.6" d="M12.8 7.5l-3.3 6h2l-.6 4.5 3.6-6.2h-2.2z"/>` : "");
}

const PHONE = "M6.600 3.200l2.400-.6c.6-.1 1.200.2 1.400.8l1 2.700c.2.5 0 1-.4 1.300L9 9c1 2.200 2.900 4.100 5.100 5.100l1.500-1.500c.3-.4.8-.6 1.300-.4l2.700 1c.6.2.9.8.8 1.400l-.6 2.400c-.2.700-.8 1.100-1.500 1.100C10.200 18.100 3.900 11.800 5.100 4.700c.1-.7.700-1.300 1.500-1.500z";

function body(name, c, level) {
    switch (name) {
    case "wifi": return `<path opacity="0.3" d="${wedge(16)}"/>` + (level > 0 ? `<path d="${wedge([0, 7.5, 11.5, 16][level])}"/>` : "");
    case "cell": return bars(level);
    // wide loops keep the full stroke open; a thinner stroke broke up at laptop scale
    case "bt": return line(c, "M6.25 7.25l11.5 9.5-6.5 5V2.25l6.5 5-11.5 9.5");
    case "vol0": return speaker(c, "");
    case "vol1": return speaker(c, line(c, "M15.5 9a4 4 0 0 1 0 6"));
    case "vol2": return speaker(c, line(c, "M15.5 9a4 4 0 0 1 0 6M18 6a8 8 0 0 1 0 12"));
    case "volx": return speaker(c, line(c, "M16 9.5l5 5M21 9.5l-5 5"));
    case "battery": return battery(c, level, false);
    case "charging": return battery(c, level, true);
    case "back": return line(c, "M15 5l-7 7 7 7");
    case "sun": return `<circle cx="12" cy="12" r="4.5"/>` + line(c, "M12 2.5v2.5M12 19v2.5M2.5 12H5M19 12h2.5M5.3 5.3l1.8 1.8M16.9 16.9l1.8 1.8M5.3 18.7l1.8-1.8M16.9 7.1l1.8-1.8");
    case "gear": return `<circle cx="12" cy="12" r="8.2" fill="none" stroke="${c}" stroke-width="3" stroke-dasharray="3.22 3.22"/><circle cx="12" cy="12" r="5.6" fill="none" stroke="${c}" stroke-width="2.6"/>`;
    case "torch": return `<path d="M7 2h10v4l-3 5v11h-4V11L7 6z"/>`;
    case "dataoff": return line(c, "M6 6l12 12M18 6L6 18");
    case "data": return line(c, "M8 20V4M4 8l4-4 4 4M16 4v16M12 16l4 4 4-4");
    case "lock": return `<rect x="5" y="10.5" width="14" height="11" rx="2"/>` + line(c, "M8 10.5V7a4 4 0 0 1 8 0v3.5");
    case "plane": return `<path d="M21.5 15.5v-2l-8-5V3.8a1.5 1.5 0 0 0-3 0v4.7l-8 5v2l8-2.5v5l-2 1.5V21l3.5-1 3.5 1v-1.5l-2-1.5v-5z"/>`;
    case "hotspot": return `<circle cx="12" cy="12" r="2.4"/>` + line(c, "M8.2 15.8a5.4 5.4 0 0 1 0-7.6M15.8 8.2a5.4 5.4 0 0 1 0 7.6M5.3 18.7a9.5 9.5 0 0 1 0-13.4M18.7 5.3a9.5 9.5 0 0 1 0 13.4");
    case "nfc": return line(c, "M6 8a8 8 0 0 1 0 8M10 5.5a13 13 0 0 1 0 13M14 3a18 18 0 0 1 0 18");
    case "pin": return `<path fill-rule="evenodd" d="M12 2a7.5 7.5 0 0 0-7.5 7.5C4.5 15 12 22 12 22s7.5-7 7.5-12.5A7.5 7.5 0 0 0 12 2zm0 5a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5z"/>`;
    case "bell": return `<path d="M12 2.5a1.5 1.5 0 0 0-1.5 1.5v.7A6 6 0 0 0 6 10.5v4L4 17.5v1h16v-1l-2-3v-4a6 6 0 0 0-4.5-5.8V4A1.5 1.5 0 0 0 12 2.5zM9.8 19.5a2.3 2.3 0 0 0 4.4 0z"/>`;
    case "vibrate": return `<rect x="8" y="3" width="8" height="18" rx="2"/>` + line(c, "M4.5 8v8M19.5 8v8M1.8 10v4M22.2 10v4");
    case "silent": return `<path d="M12 2.5a1.5 1.5 0 0 0-1.5 1.5v.7A6 6 0 0 0 6 10.5v4L4 17.5v1h16v-1l-2-3v-4a6 6 0 0 0-4.5-5.8V4A1.5 1.5 0 0 0 12 2.5zM9.8 19.5a2.3 2.3 0 0 0 4.4 0z"/>` + line("#000000", "M3 2l18 19", 4.5) + line(c, "M3.5 2.5l17 18");
    case "dnd": return `<path fill-rule="evenodd" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM6.5 10.5h11v3h-11z"/>`;
    case "dark": return `<path fill-rule="evenodd" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 2v16a8 8 0 0 0 0-16z"/>`;
    case "night": return `<path d="M20.5 14.5A8.7 8.7 0 0 1 9.5 3.5a8.7 8.7 0 1 0 11 11z"/>`;
    case "record": return `<circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="9.5" fill="none" stroke="${c}" stroke-width="2"/>`;
    case "shot": return line(c, "M3.5 8V5.5a2 2 0 0 1 2-2H8M16 3.5h2.5a2 2 0 0 1 2 2V8M20.5 16v2.5a2 2 0 0 1-2 2H16M8 20.5H5.5a2 2 0 0 1-2-2V16") + `<circle cx="12" cy="12" r="3"/>`;
    case "saver": return `<path d="M20.5 3.5C11 3.5 4.5 7.5 4.5 14c0 1.7.5 3.2 1.3 4.4L3.5 20.5 5 22l2.3-2.3A7.8 7.8 0 0 0 11 20.5c6.5 0 9.5-7.5 9.5-17z"/>`;
    case "glyph": return line(c, "M12 3v3M12 18v3M3 12h3M18 12h3M5.600 5.600l2.100 2.100M16.3 16.3l2.100 2.100M5.600 18.4l2.100-2.100M16.3 7.7l2.100-2.100") + `<circle cx="12" cy="12" r="2.5"/>`;
    case "calc": return `<path fill-rule="evenodd" d="M6.5 2h11A2.5 2.5 0 0 1 20 4.5v15a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2zM7 5v3.5h10V5zm0 6.5V14h2.5v-2.5zm3.8 0V14h2.5v-2.5zm3.7 0V14H17v-2.5zM7 16v2.5h2.5V16zm3.8 0v2.5h2.5V16zm3.7 0v2.5H17V16z"/>`;
    case "clock": return `<circle cx="12" cy="12" r="9" fill="none" stroke="${c}" stroke-width="2"/>` + line(c, "M12 6.5V12l3.5 2");
    case "camera": return `<path fill-rule="evenodd" d="M9 4L7.5 6.5H4.5A2.5 2.5 0 0 0 2 9v9a2.5 2.5 0 0 0 2.5 2.5h15A2.5 2.5 0 0 0 22 18V9a2.5 2.5 0 0 0-2.5-2.5h-3L15 4zm3 5.5a4 4 0 1 1 0 8 4 4 0 0 1 0-8z"/>`;
    case "qr": return `<path fill-rule="evenodd" d="M3 3h8v8H3zm2 2v4h4V5zM13 3h8v8h-8zm2 2v4h4V5zM3 13h8v8H3zm2 2v4h4v-4z"/><rect x="6" y="6" width="2" height="2"/><rect x="16" y="6" width="2" height="2"/><rect x="6" y="16" width="2" height="2"/><rect x="13" y="13" width="3" height="3"/><rect x="18" y="13" width="3" height="3"/><rect x="13" y="18" width="3" height="3"/><rect x="18" y="18" width="3" height="3"/>`;
    case "note": return `<path fill-rule="evenodd" d="M6 2.5h12A2.5 2.5 0 0 1 20.5 5v14a2.5 2.5 0 0 1-2.5 2.5H6A2.5 2.5 0 0 1 3.5 19V5A2.5 2.5 0 0 1 6 2.5zM7 7v2h10V7zm0 4v2h10v-2zm0 4v2h6v-2z"/>`;
    case "share": return `<circle cx="6" cy="12" r="3"/><circle cx="18" cy="5.5" r="3"/><circle cx="18" cy="18.5" r="3"/>` + line(c, "M8.5 10.7l7-3.900M8.5 13.3l7 3.900");
    case "mic": return `<rect x="8.5" y="2.5" width="7" height="12" rx="3.5"/>` + line(c, "M5 11.5a7 7 0 0 0 14 0M12 18.5v3");
    case "pencil": return `<path d="M3 21l1.2-5L15.5 4.7a2 2 0 0 1 2.8 0l1 1a2 2 0 0 1 0 2.8L8 19.8z"/>`;
    case "chevron": return line(c, "M6 9.5l6 6 6-6", 2.4);
    case "search": return `<circle cx="10.5" cy="10.5" r="6.5" fill="none" stroke="${c}" stroke-width="2.2"/>` + line(c, "M15.3 15.3L20.5 20.5", 2.4);
    case "music": return `<circle cx="6.5" cy="17.5" r="2.8"/><circle cx="17.5" cy="15.5" r="2.8"/>` + line(c, "M9.2 17.5V6.5l11-2.5v11.5");
    case "play": return `<path d="M8 5.5v13a1 1 0 0 0 1.5.9l10.5-6.5a1 1 0 0 0 0-1.8L9.5 4.600A1 1 0 0 0 8 5.5z"/>`;
    case "pause": return `<rect x="6.5" y="5" width="4" height="14" rx="1.2"/><rect x="13.5" y="5" width="4" height="14" rx="1.2"/>`;
    case "prev": return `<rect x="5" y="5.5" width="2.4" height="13" rx="1"/><path d="M19 6.3v11.4a.8.8 0 0 1-1.2.7L9 12.7a.8.8 0 0 1 0-1.4l8.8-5.7a.8.8 0 0 1 1.2.7z"/>`;
    case "next": return `<rect x="16.600" y="5.5" width="2.4" height="13" rx="1"/><path d="M5 6.3v11.4a.8.8 0 0 0 1.2.7l8.8-5.7a.8.8 0 0 0 0-1.4L6.2 5.600A.8.8 0 0 0 5 6.3z"/>`;
    case "dock": return `<rect x="3" y="14" width="18" height="7" rx="3.5"/><rect x="6" y="4" width="5" height="5" rx="1.5"/><rect x="13" y="4" width="5" height="5" rx="1.5"/>`;
    case "plus": return line(c, "M12 5v14M5 12h14", 3);
    case "info": return `<circle cx="12" cy="12" r="9" fill="none" stroke="${c}" stroke-width="2"/><rect x="11" y="10.500" width="2" height="6.500" rx="1"/><circle cx="12" cy="7.500" r="1.300"/>`;
    case "power": return line(c, "M12 3.500v8M7 6.200a8 8 0 1 0 10 0", 2.4);
    case "minus": return line(c, "M5 12h14", 3);
    case "trash": return line(c, "M4 7h16M9 7V4h6v3M6 7l1 14h10l1-14M10 11v6M14 11v6");
    case "image": return `<rect x="3" y="4" width="18" height="16" rx="3" fill="none" stroke="${c}" stroke-width="2"/><circle cx="8.5" cy="9.5" r="1.8"/><path d="M5 18l5-6 3.5 4 2.5-3 3.5 5z"/>`;
    case "output": return `<path d="M3 13a9 9 0 0 1 18 0v5a2.5 2.5 0 0 1-2.5 2.5H17a1 1 0 0 1-1-1V14a1 1 0 0 1 1-1h2a7 7 0 0 0-14 0h2a1 1 0 0 1 1 1v5.5a1 1 0 0 1-1 1H5.5A2.5 2.5 0 0 1 3 18z"/>`;
    case "phone": return `<path d="${PHONE}"/>`;
    case "hangup": return `<path transform="rotate(135 12 12)" d="${PHONE}"/>`;
    case "unlock": return `<rect x="5" y="10.5" width="14" height="11" rx="2"/>` + line(c, "M8 10.5V6.5a4 4 0 0 1 7.6-1.7");
    case "timer": return `<circle cx="12" cy="13.5" r="8" fill="none" stroke="${c}" stroke-width="2"/>` + line(c, "M9.500 2.500h5M12 9v4.500l2.500 1.500");
    case "stopwatch": return `<circle cx="12" cy="13.5" r="8" fill="none" stroke="${c}" stroke-width="2"/>` + line(c, "M12 2.500v3M18.500 6l1.500 1.500M12 9.500v4");
    case "navl": return line(c, "M19 21v-7a4 4 0 0 0-4-4H5M10 4.500L4.500 10l5.500 5.500", 2.6);
    case "navr": return line(c, "M5 21v-7a4 4 0 0 1 4-4h10M14 4.500l5.500 5.500-5.500 5.500", 2.6);
    case "navs": return line(c, "M12 21V4M6 9.500L12 3.500l6 6", 2.6);
    case "transfer": return line(c, "M12 3v12.500M6.500 10.500L12 16l5.500-5.500M4.500 20.500h15", 2.4);
    case "vpn": return `<path d="M12 2l8 3v6.500c0 5-3.400 8.700-8 10.500-4.600-1.800-8-5.500-8-10.500V5z"/>`;
    case "speaker": return speaker(c, line(c, "M15.500 9a4 4 0 0 1 0 6M18 6a8 8 0 0 1 0 12"));
    case "micoff": return `<rect x="8.500" y="2.500" width="7" height="12" rx="3.500"/>` + line(c, "M5 11.500a7 7 0 0 0 14 0M12 18.500v3") + line("#000000", "M3 3l18 18", 4.500) + line(c, "M3.500 3.500l17 17");
    case "stop": return `<rect x="6" y="6" width="12" height="12" rx="2"/>`;
    case "battlow": return battery(c, 12, false);
    case "dot": return `<circle cx="12" cy="12" r="5"/>`;
    case "bolt": return `<path d="M13.5 2L5 14h5.5L9.5 22 19 9.5h-6z"/>`;
    case "finger": return line(c, "M6.5 5a9 9 0 0 1 11 0M4 10a8.5 8.5 0 0 1 16 0M7 19c1.2-2.2 1.6-4.6 1.6-7a3.4 3.4 0 0 1 6.8 0c0 2.4-.4 4.8-1.2 7M12 12c0 3.3-.8 6.4-2.6 9M18.6 14.5c-.1 2-.5 3.8-1.2 5.5", 1.6);
    case "backspace": return line(c, "M8.5 5H20a1.5 1.5 0 0 1 1.5 1.5v11A1.5 1.5 0 0 1 20 19H8.5L2.5 12zM11.5 9.5l5 5M16.5 9.5l-5 5", 1.8);
    case "rotate": return line(c, "M19.5 12a7.5 7.5 0 1 1-2.2-5.3M19.5 4v4.5H15");
    }
    return "";
}

function has(name) { return body(name, "#000", 0) !== ""; }

function url(name, color, level) {
    const c = String(color);
    return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(
        `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="${c}">${body(name, c, level)}</svg>`);
}
