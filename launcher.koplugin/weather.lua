--[[--
Current weather, today's high/low and sunrise/sunset from Open-Meteo
(https://open-meteo.com, free, no account). Cached for 30 minutes.
--]]--
local http = require("socket.http")
local JSON = require("json")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")

local Weather = { data = nil, fetched_at = 0, TTL = 30 * 60 }

-- WMO weather codes -> { icon, text }
local SUN, MOON, CLOUD, RAIN, BOLT, SNOW = "\u{F185}", "\u{F186}", "\u{F0C2}", "\u{F0E9}", "\u{F0E7}", "\u{F2DC}"
local function describe(code, is_day)
    code = tonumber(code) or -1
    local clear = (is_day == 0) and MOON or SUN
    if code == 0 then return clear, "Clear" end
    if code == 1 then return clear, "Mostly clear" end
    if code == 2 then return CLOUD, "Partly cloudy" end
    if code == 3 then return CLOUD, "Cloudy" end
    if code == 45 or code == 48 then return CLOUD, "Fog" end
    if code >= 51 and code <= 57 then return RAIN, "Drizzle" end
    if code >= 61 and code <= 67 then return RAIN, "Rain" end
    if code >= 71 and code <= 77 then return SNOW, "Snow" end
    if code >= 80 and code <= 82 then return RAIN, "Showers" end
    if code == 85 or code == 86 then return SNOW, "Snow showers" end
    if code >= 95 then return BOLT, "Thunderstorm" end
    return CLOUD, ""
end

function Weather:get(lat, lon, force)
    if not lat or not lon then return nil end
    local now = os.time()
    if not force and self.data and now - self.fetched_at < self.TTL then
        return self.data
    end
    local url = string.format("https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
        .. "&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset"
        .. "&timezone=auto&timeformat=unixtime&forecast_days=1", lat, lon)
    local sink = {}
    socketutil:set_timeout(6, 12)
    local ok, code = pcall(function()
        return socket.skip(1, http.request{ url = url, sink = ltn12.sink.table(sink) })
    end)
    socketutil:reset_timeout()
    if not ok or code ~= 200 then
        logger.warn("launcher: weather fetch failed", ok, code)
        return self.data -- keep showing the last good data
    end
    local okj, j = pcall(JSON.decode, table.concat(sink))
    if not okj or type(j) ~= "table" or not j.current then return self.data end
    local icon, text = describe(j.current.weather_code, j.current.is_day)
    local d = j.daily or {}
    self.data = {
        temp = j.current.temperature_2m,
        icon = icon, text = text,
        high = d.temperature_2m_max and d.temperature_2m_max[1],
        low = d.temperature_2m_min and d.temperature_2m_min[1],
        sunrise = d.sunrise and d.sunrise[1],
        sunset = d.sunset and d.sunset[1],
    }
    self.fetched_at = now
    return self.data
end

return Weather
