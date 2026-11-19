pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Weather - current conditions plus today's range from Open-Meteo (no
// API key), fetched once at startup and then on a slow 30-minute timer.
// Between fetches the service is completely idle: no polling loops, and
// consumers render static text, so the desktop widget built on this
// costs no GPU work and near-zero CPU/RAM.
//
// Location: automatic by default, resolved from the machine's public
// IP (ipwho.is, ip-api.com as fallback), never hardcoded - no default
// city is baked in and nothing is written to the repo. The user can
// override the detected place from the widget's location picker; the
// choice is stored per machine in Quickshell.statePath(
// "weather-location.json"), outside the repo, and can be cleared back
// to automatic at any time. If every lookup fails, weather stays
// unavailable until the next cycle instead of silently showing some
// other place.
//
// City search (Open-Meteo Geocoding) and nearby places (Photon
// reverse) run only on demand, when the picker asks for them.
Item {
    id: root

    // Effective location: what the weather is shown for.
    property string locationName: ""
    property real latitude: 0
    property real longitude: 0
    property bool _locationReady: false

    // Selection: "auto" (from IP) or "manual" (user-picked place).
    property string locationMode: "auto"
    property string detectedName: ""
    property bool _selLoaded: false

    property bool available: false
    property int temperature: 0
    property int feelsLike: 0
    property int humidity: 0
    property int windSpeed: 0
    property int highToday: 0
    property int lowToday: 0
    property int rainChance: 0
    property string condition: ""
    property string iconName: ""
    property string updatedAt: ""

    // Picker data, filled on demand only.
    property var searchResults: []
    property bool searchBusy: false
    property bool searchDone: false
    property var nearbyPlaces: []
    property bool nearbyBusy: false

    function refresh() {
        if (!root._selLoaded)
            return
        if (root.locationMode === "manual") {
            root._fetchWeather()
            return
        }
        if (locProc.running || locFallbackProc.running || fetchProc.running)
            return
        locProc.running = true
    }

    function useAuto() {
        selAdapter.selection = ({ mode: "auto" })
        root.locationMode = "auto"
        root._locationReady = false
        console.info("[WeatherService] automatic location selected")
        root.refresh()
    }

    function usePlace(name, lat, lon) {
        selAdapter.selection = ({ mode: "manual", name: name, latitude: lat, longitude: lon })
        root.locationMode = "manual"
        root.locationName = name
        root.latitude = lat
        root.longitude = lon
        root._locationReady = true
        console.info("[WeatherService] manual location selected")
        root._fetchWeather()
    }

    function searchCities(query) {
        const q = (query || "").trim()
        root.searchDone = false
        if (q.length < 2) {
            root.searchResults = []
            root.searchBusy = false
            return
        }
        if (searchProc.running)
            searchProc.running = false
        const lang = (Qt.locale().name || "en").substring(0, 2)
        const url = "https://geocoding-api.open-meteo.com/v1/search?name="
            + encodeURIComponent(q) + "&count=6&language=" + lang + "&format=json"
        searchProc.command = ["curl", "-sf", "--max-time", "10", url]
        root.searchBusy = true
        searchProc.running = true
    }

    function refreshNearby() {
        if (!root._locationReady || nearbyProc.running)
            return
        const url = "https://photon.komoot.io/reverse?lon=" + root.longitude
            + "&lat=" + root.latitude + "&limit=12"
        nearbyProc.command = ["curl", "-sf", "--max-time", "10", url]
        root.nearbyBusy = true
        nearbyProc.running = true
    }

    function _setLocation(name, lat, lon) {
        root.detectedName = name || ""
        root.locationName = root.detectedName
        root.latitude = lat
        root.longitude = lon
        root._locationReady = true
        console.info("[WeatherService] location resolved from IP")
        root._fetchWeather()
    }

    function _fetchWeather() {
        if (!root._locationReady || fetchProc.running)
            return
        const url = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + root.latitude + "&longitude=" + root.longitude
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"
            + "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            + "&timezone=auto&forecast_days=1"
        fetchProc.command = ["curl", "-sf", "--max-time", "15", url]
        fetchProc.running = true
    }

    // WMO weather codes (Open-Meteo) -> [label, icon file base name].
    // Day and night share labels; clear and partly-cloudy have separate
    // day / night icons.
    function _describe(code, isDay) {
        const clear = isDay ? "weather-clear-day" : "weather-clear-night"
        const partly = isDay ? "weather-partly-day" : "weather-partly-night"
        if (code === 0) return ["Clear sky", clear]
        if (code === 1) return ["Mainly clear", clear]
        if (code === 2) return ["Partly cloudy", partly]
        if (code === 3) return ["Overcast", "weather-cloudy"]
        if (code === 45 || code === 48) return ["Fog", "weather-fog"]
        if (code >= 51 && code <= 57) return ["Drizzle", "weather-rain"]
        if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return ["Rain", "weather-rain"]
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return ["Snow", "weather-snow"]
        if (code >= 95) return ["Thunderstorm", "weather-storm"]
        return ["", "weather-cloudy"]
    }

    function _apply(json) {
        try {
            const data = JSON.parse(json)
            const cur = data.current
            const day = data.daily
            const described = root._describe(cur.weather_code, cur.is_day === 1)
            root.temperature = Math.round(cur.temperature_2m)
            root.feelsLike = Math.round(cur.apparent_temperature)
            root.humidity = Math.round(cur.relative_humidity_2m)
            root.windSpeed = Math.round(cur.wind_speed_10m)
            root.highToday = Math.round(day.temperature_2m_max[0])
            root.lowToday = Math.round(day.temperature_2m_min[0])
            const prob = day.precipitation_probability_max
            root.rainChance = prob && prob[0] !== null && prob[0] !== undefined ? Math.round(prob[0]) : 0
            root.condition = described[0]
            root.iconName = described[1]
            root.updatedAt = String(cur.time).slice(11, 16)
            root.available = true
        } catch (e) {
            console.warn("[WeatherService] parse failed:", e)
        }
    }

    function _applyIpWho(json) {
        try {
            const data = JSON.parse(json)
            if (data.success !== true || typeof data.latitude !== "number" || typeof data.longitude !== "number")
                return false
            root._setLocation(data.city || data.region || "", data.latitude, data.longitude)
            return true
        } catch (e) {
            return false
        }
    }

    function _applyIpApi(json) {
        try {
            const data = JSON.parse(json)
            if (data.status !== "success" || typeof data.lat !== "number" || typeof data.lon !== "number")
                return false
            root._setLocation(data.city || "", data.lat, data.lon)
            return true
        } catch (e) {
            return false
        }
    }

    function _applySearch(json) {
        root.searchBusy = false
        root.searchDone = true
        try {
            const data = JSON.parse(json)
            const out = []
            const results = data.results || []
            for (let i = 0; i < results.length; i++) {
                const r = results[i]
                out.push({
                    name: r.name || "",
                    region: r.admin1 || r.country || "",
                    latitude: r.latitude,
                    longitude: r.longitude
                })
            }
            root.searchResults = out
        } catch (e) {
            root.searchResults = []
        }
    }

    function _applyNearby(json) {
        root.nearbyBusy = false
        try {
            const data = JSON.parse(json)
            const out = []
            const seen = ({})
            const features = data.features || []
            for (let i = 0; i < features.length && out.length < 4; i++) {
                const p = features[i].properties || {}
                const isPlace = (p.osm_key === "place" && ["city", "town", "village"].includes(p.osm_value))
                    || ["city", "town", "village"].includes(p.type)
                if (!isPlace || !p.name || seen[p.name])
                    continue
                if (p.name === root.locationName)
                    continue
                seen[p.name] = true
                const coords = (features[i].geometry || {}).coordinates || []
                if (typeof coords[0] !== "number" || typeof coords[1] !== "number")
                    continue
                out.push({
                    name: p.name,
                    region: p.state || p.country || "",
                    latitude: coords[1],
                    longitude: coords[0]
                })
            }
            root.nearbyPlaces = out
        } catch (e) {
            root.nearbyPlaces = []
        }
    }

    // Single funnel, run once, whichever way the load went: a missing
    // or unreadable file leaves the selection at its default (auto).
    function _onSelLoaded() {
        if (root._selLoaded)
            return
        root._selLoaded = true
        const s = (selAdapter.selection && typeof selAdapter.selection === "object")
            ? selAdapter.selection : {}
        if (s.mode === "manual" && typeof s.latitude === "number"
                && typeof s.longitude === "number" && s.name) {
            root.locationMode = "manual"
            root.locationName = s.name
            root.latitude = s.latitude
            root.longitude = s.longitude
            root._locationReady = true
        }
        root.refresh()
    }

    FileView {
        id: selFile

        path: Quickshell.statePath("weather-location.json")
        printErrors: false
        atomicWrites: true

        onLoaded: root._onSelLoaded()
        onLoadFailed: (error) => root._onSelLoaded()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: selAdapter

            property var selection: ({ mode: "auto" })
        }
    }

    Process {
        id: locProc

        command: ["curl", "-sf", "--max-time", "10", "https://ipwho.is/"]
        stdout: StdioCollector { id: locOut; waitForEnd: true }

        onExited: (code) => {
            if (code === 0 && root._applyIpWho(locOut.text))
                return
            locFallbackProc.running = true
        }
    }

    Process {
        id: locFallbackProc

        command: ["curl", "-sf", "--max-time", "10", "http://ip-api.com/json/?fields=status,city,lat,lon"]
        stdout: StdioCollector { id: locFallbackOut; waitForEnd: true }

        onExited: (code) => {
            if (code === 0 && root._applyIpApi(locFallbackOut.text))
                return
            console.warn("[WeatherService] IP location lookup failed; weather unavailable until next cycle")
        }
    }

    Process {
        id: fetchProc

        stdout: StdioCollector { id: fetchOut; waitForEnd: true }

        onExited: (code) => {
            if (code === 0)
                root._apply(fetchOut.text)
        }
    }

    Process {
        id: searchProc

        stdout: StdioCollector { id: searchOut; waitForEnd: true }

        onExited: (code) => {
            if (code === 0) {
                root._applySearch(searchOut.text)
            } else {
                root.searchBusy = false
                root.searchDone = true
                root.searchResults = []
            }
        }
    }

    Process {
        id: nearbyProc

        stdout: StdioCollector { id: nearbyOut; waitForEnd: true }

        onExited: (code) => {
            if (code === 0) {
                root._applyNearby(nearbyOut.text)
            } else {
                root.nearbyBusy = false
                root.nearbyPlaces = []
            }
        }
    }

    // The only timer in the weather stack: resolve location (unless a
    // manual place is selected), then fetch weather, every 30 minutes.
    Timer {
        interval: 30 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true

        onTriggered: root.refresh()
    }
}
