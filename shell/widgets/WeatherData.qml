import Quickshell
import Quickshell.Io
import QtQuick
import qs

// Open-Meteo for one city, typed in by hand; the last answer is kept on disk and shown offline, nothing is made up
Item {
    id: root

    property string city: ""
    // fetch only when shown for real; previews read the cache
    property bool fetch: false
    readonly property string slug: city.toLowerCase().replace(/[^a-z0-9]+/g, "_").slice(0, 60)
    readonly property var info: {
        try {
            const d = JSON.parse(cache.text());
            return d && d.city === city.toLowerCase() ? d : null;
        } catch (e) {
            return null;
        }
    }
    property bool failed: false
    // the test points these at a local fake
    readonly property string geoUrl: Quickshell.env("PHONE_WEATHER_GEO") || "https://geocoding-api.open-meteo.com"
    readonly property string apiUrl: Quickshell.env("PHONE_WEATHER_API") || "https://api.open-meteo.com"

    FileView {
        id: cache
        path: root.slug ? Phone.stateDir + "/weather-" + root.slug + ".json" : ""
        blockLoading: true
        printErrors: false
        watchChanges: true
        atomicWrites: true
        onFileChanged: reload()
    }

    function get(url, done) {
        const x = new XMLHttpRequest();
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE)
                return;
            let j = null;
            try { j = x.status === 200 ? JSON.parse(x.responseText) : null; } catch (e) {}
            if (j) done(j); else root.failed = true;
        };
        x.open("GET", url);
        x.send();
    }
    function refresh() {
        if (!fetch || !city.trim())
            return;
        if (info && Date.now() - info.time < 25 * 60000)
            return;
        failed = false;
        const want = city.toLowerCase();
        get(geoUrl + "/v1/search?count=1&name=" + encodeURIComponent(city.trim()), g => {
            const p = g.results && g.results[0];
            if (!p) { root.failed = true; return; }
            get(apiUrl + "/v1/forecast?latitude=" + p.latitude + "&longitude=" + p.longitude
                + "&current=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=5", f => {
                if (!f.current || !f.daily || want !== root.city.toLowerCase())
                    return;
                const days = (f.daily.time || []).map((d, i) => ({ day: d, code: f.daily.weather_code[i],
                    hi: Math.round(f.daily.temperature_2m_max[i]), lo: Math.round(f.daily.temperature_2m_min[i]) }));
                cache.setText(JSON.stringify({ city: want, name: p.name || root.city, time: Date.now(),
                    temp: Math.round(f.current.temperature_2m), code: f.current.weather_code, days: days }) + "\n");
            });
        });
    }
    onCityChanged: Qt.callLater(refresh)
    onFetchChanged: Qt.callLater(refresh)
    Timer { running: root.fetch; repeat: true; interval: 30 * 60000; onTriggered: root.refresh() }

    // WMO weather codes as the dot icons of DotText
    function icon(code) {
        if (code === 0) return "☀";
        if (code <= 2) return "⛅";
        if (code === 3) return "☁";
        if (code === 45 || code === 48) return "≡";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "❄";
        if (code >= 95) return "⚡";
        return "☂";
    }
    function words(code) {
        if (code === 0) return "Clear";
        if (code <= 2) return "Partly cloudy";
        if (code === 3) return "Cloudy";
        if (code === 45 || code === 48) return "Fog";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "Snow";
        if (code >= 95) return "Storm";
        if (code >= 51 && code <= 57) return "Drizzle";
        return "Rain";
    }
}
