--[[--
Built-in mini apps: Calendar, Panchang, Weather, World clock, Calculator,
Stopwatch & timer, and Notes (Memos).
--]]--
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Page = require("page")
local Panchang = require("panchang")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local http = require("socket.http")
local JSON = require("json")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local _ = require("gettext")
local Screen = Device.screen

local T, BOX, CELL, GRAY = Page.text, Page.box, Page.cell, Page.GRAY
local Mini = {}

local function lang(cfg) return cfg:readSetting("panchang_lang") or "te" end
local function pface(cfg, size)
    if lang(cfg) == "te" then return Font:getFace("noto/NotoSansTelugu-Regular.ttf", size) end
    return Font:getFace("cfont", size)
end
local function hm(t) return t and os.date("%H:%M", t) or "–" end
local function range(a, b) return (a and b) and (hm(a) .. "–" .. hm(b)) or "–" end

local function getJSON(url, headers)
    local sink = {}
    socketutil:set_timeout(8, 15)
    local ok, code = pcall(function()
        return socket.skip(1, http.request{ url = url, headers = headers, sink = ltn12.sink.table(sink) })
    end)
    socketutil:reset_timeout()
    if not ok or code ~= 200 then return nil, code end
    local okj, data = pcall(JSON.decode, table.concat(sink))
    if okj then return data end
end

local function busy(text, fn)
    local note = InfoMessage:new{ text = text }
    UIManager:show(note)
    UIManager:forceRePaint()
    local ok, a, b = pcall(fn)
    UIManager:close(note)
    if not ok then UIManager:show(InfoMessage:new{ text = tostring(a) }) return end
    return a, b
end

----------------------------------------------------------------- calendar
-- Month grid; each day shows its tithi at 06:00 (around sunrise). Swipe to change month.
function Mini.calendar(home)
    local cfg = home.cfg
    local now = os.date("*t")
    local state = { year = now.year, month = now.month }
    local page
    local function content(p, inner, avail)
        local first = os.time{ year = state.year, month = state.month, day = 1, hour = 6 }
        local ndays = os.date("*t", os.time{ year = state.year, month = state.month + 1, day = 0, hour = 12 }).day
        local wfirst = (tonumber(os.date("%w", first)) + 6) % 7 -- Monday = 0
        local gap = Screen:scaleBySize(6)
        local cw = math.floor((inner - 6 * gap) / 7)
        local rows = math.ceil((wfirst + ndays) / 7)
        local head_h = Screen:scaleBySize(60)
        local ch = math.min(Screen:scaleBySize(150), math.floor((avail - head_h - Screen:scaleBySize(40) - rows * gap) / rows))
        local g = VerticalGroup:new{ align = "left" }
        -- month name + arrows
        local title = T(os.date("%B %Y", first), 28, { bold = true })
        local prev, nxt = T("\u{F053}", 26), T("\u{F054}", 26)
        table.insert(g, CenterContainer:new{ dimen = Geom:new{ w = inner, h = head_h },
            HorizontalGroup:new{ align = "center", prev, HorizontalSpan:new{ width = Screen:scaleBySize(40) }, title,
                HorizontalSpan:new{ width = Screen:scaleBySize(40) }, nxt } })
        local wd = HorizontalGroup:new{}
        for i, n in ipairs({ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }) do
            table.insert(wd, CenterContainer:new{ dimen = Geom:new{ w = cw, h = Screen:scaleBySize(34) }, T(_(n), 16, { color = GRAY }) })
            if i < 7 then table.insert(wd, HorizontalSpan:new{ width = gap }) end
        end
        table.insert(g, wd)
        local today = os.date("*t")
        local day = 1
        for r = 1, rows do
            local row = HorizontalGroup:new{}
            for c = 0, 6 do
                local idx = (r - 1) * 7 + c
                local cell
                if idx >= wfirst and day <= ndays then
                    local t = os.time{ year = state.year, month = state.month, day = day, hour = 6 }
                    local ti = Panchang.tithiIndex(t)
                    local is_today = today.year == state.year and today.month == state.month and today.day == day
                    local mark = (ti == 14 and " \u{F111}") or (ti == 29 and " \u{F10C}") or ""
                    cell = CELL(VerticalGroup:new{ align = "center",
                        T(tostring(day) .. mark, 24, { bold = is_today }),
                        VerticalSpan:new{ width = Screen:scaleBySize(4) },
                        T(Panchang.tithiShort(ti, lang(cfg)), 14, { face = pface(cfg, 14), color = GRAY, max_width = cw - 6 }),
                    }, cw, ch, { border = is_today and Screen:scaleBySize(4) or Screen:scaleBySize(1),
                        border_color = is_today and Blitbuffer.COLOR_BLACK or nil })
                    day = day + 1
                else
                    cell = HorizontalSpan:new{ width = cw }
                end
                table.insert(row, cell)
                if c < 6 then table.insert(row, HorizontalSpan:new{ width = gap }) end
            end
            table.insert(g, VerticalSpan:new{ width = gap })
            table.insert(g, row)
        end
        table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(14) })
        table.insert(g, T("\u{F111} " .. Panchang.tithiShort(14, lang(cfg)) .. "     \u{F10C} " .. Panchang.tithiShort(29, lang(cfg))
            .. "     " .. _("Swipe for other months"), 15, { face = pface(cfg, 15), color = GRAY }))
        return g, function(x, y)
            p:addHit(x, y, math.floor(inner / 3), head_h, function() state.month = state.month - 1; page:refresh("full") end)
            p:addHit(x + inner - math.floor(inner / 3), y, math.floor(inner / 3), head_h,
                function() state.month = state.month + 1; page:refresh("full") end)
        end
    end
    page = Page:new{ title = _("Calendar"), content_func = content,
        on_swipe = function(p, dir)
            if dir == "west" then state.month = state.month + 1 elseif dir == "east" then state.month = state.month - 1 else return end
            -- normalise
            local t = os.date("*t", os.time{ year = state.year, month = state.month, day = 1, hour = 12 })
            state.year, state.month = t.year, t.month
            p:refresh("full")
        end }
    UIManager:show(page, "full")
end

----------------------------------------------------------------- panchang
function Mini.panchang(home)
    local cfg = home.cfg
    local L = lang(cfg)
    local lab = Panchang.LABEL[L]
    local Weather = require("weather")
    local w = Weather:get(cfg:readSetting("lat"), cfg:readSetting("lon")) or {}
    local now = os.time()
    local ti, ni = Panchang.tithiIndex(now), Panchang.nakshatraIndex(now)
    local tend, nend = Panchang.tithiEnds(now), Panchang.nakshatraEnds(now)
    local face = pface(cfg, 22)
    local function untilText(t)
        if not t then return "" end
        local fmt = os.date("%d", t) == os.date("%d", now) and "%H:%M" or "%a %H:%M"
        return L == "te" and (os.date(fmt, t) .. " " .. lab["until"]) or (lab["until"] .. " " .. os.date(fmt, t))
    end
    local rows = {
        { heading = os.date("%A, %d %B %Y") },
        { left = lab.tithi, right = Panchang.tithiName(ti, L), face = face, bold_right = true,
          sub = untilText(tend) .. (tend and ("  →  " .. Panchang.tithiName((ti + 1) % 30, L)) or ""), sub_face = pface(cfg, 17) },
        { left = lab.nakshatra, right = Panchang.nakshatraName(ni, L), face = face, bold_right = true,
          sub = untilText(nend) .. (nend and ("  →  " .. Panchang.nakshatraName((ni + 1) % 27, L)) or ""), sub_face = pface(cfg, 17) },
        { heading = L == "te" and "సమయాలు" or "Timings", heading_face = pface(cfg, 15) },
        { left = lab.sunrise, right = hm(w.sunrise), face = face },
        { left = lab.sunset, right = hm(w.sunset), face = face },
        { left = lab.rahu, right = range(Panchang.rahuKalam(w.sunrise, w.sunset)), face = face },
        { left = lab.yama, right = range(Panchang.yamaganda(w.sunrise, w.sunset)), face = face },
        { left = lab.gulika, right = range(Panchang.gulika(w.sunrise, w.sunset)), face = face },
        { left = lab.brahma, right = range(Panchang.brahmaMuhurta(w.sunrise)), face = face },
        { left = lab.abhijit, right = range(Panchang.abhijit(w.sunrise, w.sunset)), face = face },
    }
    if not w.sunrise then
        table.insert(rows, { heading = _("Set a weather location to get sunrise-based timings") })
    end
    UIManager:show(Page:new{ title = L == "te" and "పంచాంగం" or _("Panchang"), title_face = pface(cfg, 28), rows = rows }, "full")
end

----------------------------------------------------------------- weather
local WMO = {
    [0] = { "\u{F185}", "Clear" }, [1] = { "\u{F185}", "Mostly clear" }, [2] = { "\u{F0C2}", "Partly cloudy" },
    [3] = { "\u{F0C2}", "Cloudy" }, [45] = { "\u{F0C2}", "Fog" }, [48] = { "\u{F0C2}", "Fog" },
}
local function wmo(code)
    code = tonumber(code) or -1
    if WMO[code] then return WMO[code][1], WMO[code][2] end
    if code >= 51 and code <= 67 then return "\u{F0E9}", code <= 57 and "Drizzle" or "Rain" end
    if code >= 71 and code <= 77 then return "\u{F2DC}", "Snow" end
    if code >= 80 and code <= 82 then return "\u{F0E9}", "Showers" end
    if code >= 95 then return "\u{F0E7}", "Thunderstorm" end
    return "\u{F0C2}", ""
end

function Mini.weather(home)
    local cfg = home.cfg
    local lat, lon = cfg:readSetting("lat"), cfg:readSetting("lon")
    if not lat then
        UIManager:show(InfoMessage:new{ text = _("Set your location first: Apps → Home → Weather location.") })
        return
    end
    local j = busy(_("Getting the forecast…"), function()
        return getJSON(string.format("https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
            .. "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code"
            .. "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max"
            .. "&timezone=auto&timeformat=unixtime&forecast_days=7", lat, lon))
    end)
    if not j or not j.daily then
        UIManager:show(InfoMessage:new{ text = _("Couldn't get the forecast. Check Wi-Fi.") })
        return
    end
    local c = j.current or {}
    local icon, text = wmo(c.weather_code)
    local rows = {
        { heading = (cfg:readSetting("place") or "") .. "  ·  " .. _("now") },
        { left = icon .. "  " .. string.format("%d°", math.floor((c.temperature_2m or 0) + 0.5)) .. "  " .. _(text),
          right = string.format(_("feels %d°"), math.floor((c.apparent_temperature or 0) + 0.5)), size = 28, bold = true,
          sub = string.format(_("Humidity %d%%  ·  Wind %d km/h"), c.relative_humidity_2m or 0, math.floor((c.wind_speed_10m or 0) + 0.5)) },
        { heading = _("Next 7 days") },
    }
    local d = j.daily
    for i = 1, #(d.time or {}) do
        local di, dt = wmo(d.weather_code[i])
        local day = i == 1 and _("Today") or os.date("%A", d.time[i])
        table.insert(rows, {
            left = di .. "   " .. day,
            right = string.format("%d° / %d°", math.floor(d.temperature_2m_max[i] + 0.5), math.floor(d.temperature_2m_min[i] + 0.5)),
            bold_right = true,
            sub = _(dt) .. string.format(_("  ·  Rain %d%%"), d.precipitation_probability_max[i] or 0)
                .. "  ·  \u{F185} " .. hm(d.sunrise[i]) .. " – " .. hm(d.sunset[i])
                .. (d.uv_index_max and d.uv_index_max[i] and string.format("  ·  UV %d", math.floor(d.uv_index_max[i] + 0.5)) or ""),
        })
    end
    UIManager:show(Page:new{ title = _("Weather"), rows = rows }, "full")
end

----------------------------------------------------------------- world clock
local DEFAULT_ZONES = {
    { "India", "Asia/Kolkata" }, { "Brisbane", "Australia/Brisbane" }, { "Sydney", "Australia/Sydney" },
    { "Dubai", "Asia/Dubai" }, { "London", "Europe/London" }, { "New York", "America/New_York" },
    { "San Francisco", "America/Los_Angeles" }, { "Tokyo", "Asia/Tokyo" },
}
local ZONEDIR
local function zoneTime(tz)
    if not ZONEDIR then
        local lfs = require("libs/libkoreader-lfs")
        ZONEDIR = lfs.attributes("/usr/share/zoneinfo", "mode") == "directory" and "/usr/share/zoneinfo" or "/etc/zoneinfo"
    end
    local p = io.popen("TZ=':" .. ZONEDIR .. "/" .. tz:gsub("[^%w/_%-+]", "") .. "' date '+%H:%M|%a %d %b|%Z'")
    if not p then return nil end
    local out = p:read("*l"); p:close()
    if not out then return nil end
    return out:match("([^|]*)|([^|]*)|(.*)")
end

function Mini.worldclock(home)
    local zones = home.cfg:readSetting("world_zones") or DEFAULT_ZONES
    local page
    local function rows()
        local r = { { heading = _("Local") .. "  ·  " .. os.date("%H:%M  %a %d %b") } }
        for _, z in ipairs(zones) do
            local t, d, abbr = zoneTime(z[2])
            if t then table.insert(r, { left = z[1], right = t, size = 26, bold_right = true, sub = d .. "  ·  " .. (abbr or "") }) end
        end
        return r
    end
    page = Page:new{ title = _("World clock"), rows = rows() }
    -- refresh every minute while open
    local function tick()
        if not page._closed then
            page.rows = rows(); page:refresh("ui")
            UIManager:scheduleIn(60 - tonumber(os.date("%S")), tick)
        end
    end
    page.on_close = function(p) p._closed = true; UIManager:unschedule(tick) end
    UIManager:scheduleIn(60 - tonumber(os.date("%S")), tick)
    UIManager:show(page, "full")
end

----------------------------------------------------------------- calculator
function Mini.calculator()
    local state = { expr = "", result = "" }
    local page
    local keys = {
        { "C", "(", ")", "÷" },
        { "7", "8", "9", "×" },
        { "4", "5", "6", "−" },
        { "1", "2", "3", "+" },
        { "0", ".", "⌫", "=" },
    }
    local function evaluate(e)
        local s = e:gsub("×", "*"):gsub("÷", "/"):gsub("−", "-")
        if s == "" or s:find("[^%d%+%-%*/%.%(%)%s]") then return nil end
        local f = load("return " .. s, "calc", "t", {})
        if not f then return nil end
        local ok, v = pcall(f)
        if not ok or type(v) ~= "number" or v ~= v then return nil end
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        return (string.format("%.10g", v))
    end
    local function press(k)
        if k == "C" then state.expr, state.result = "", ""
        elseif k == "⌫" then state.expr = state.expr:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
        elseif k == "=" then
            local v = evaluate(state.expr)
            if v then state.result = ""; state.expr = v else state.result = _("Error") end
        else
            state.expr = state.expr .. k
            state.result = evaluate(state.expr) or ""
        end
        page:refresh("ui")
    end
    local function content(p, inner, avail)
        local g = VerticalGroup:new{ align = "right" }
        local disp_h = Screen:scaleBySize(190)
        table.insert(g, CenterContainer:new{ dimen = Geom:new{ w = inner, h = disp_h },
            VerticalGroup:new{ align = "right",
                BOX(state.expr ~= "" and state.expr or "0", 48, inner, { align = "right", bold = true }),
                BOX(state.result ~= "" and ("= " .. state.result) or " ", 28, inner, { align = "right", color = GRAY }) } })
        local gap = Screen:scaleBySize(12)
        local kw = math.floor((inner - 3 * gap) / 4)
        local kh = math.min(Screen:scaleBySize(140), math.floor((avail - disp_h - 5 * gap) / 5))
        local regs = {}
        for r, row in ipairs(keys) do
            local hg = HorizontalGroup:new{}
            for c, k in ipairs(row) do
                local op = k:find("[^%d%.]") and k ~= "." and true
                table.insert(hg, CELL(T(k, op and 34 or 38, { bold = (k == "=") }), kw, kh,
                    { background = (k == "=") and Blitbuffer.COLOR_LIGHT_GRAY or nil }))
                if c < 4 then table.insert(hg, HorizontalSpan:new{ width = gap }) end
                table.insert(regs, { dx = (c - 1) * (kw + gap), dy = disp_h + gap + (r - 1) * (kh + gap), k = k })
            end
            table.insert(g, VerticalSpan:new{ width = gap })
            table.insert(g, hg)
        end
        return g, function(x, y)
            for _, rg in ipairs(regs) do p:addHit(x + rg.dx, y + rg.dy, kw, kh, function() press(rg.k) end) end
        end
    end
    page = Page:new{ title = _("Calculator"), content_func = content }
    UIManager:show(page, "full")
end

----------------------------------------------------------------- stopwatch & timer
function Mini.stopwatch()
    local s = { mode = "stopwatch", running = false, base = 0, start = nil, target = 0, laps = {} }
    local page
    local function elapsed()
        return s.base + (s.running and (socket.gettime() - s.start) or 0)
    end
    local function fmt(sec, tenths)
        sec = math.max(0, sec)
        local h = math.floor(sec / 3600); local m = math.floor(sec % 3600 / 60); local x = sec % 60
        if tenths then
            return h > 0 and string.format("%d:%02d:%04.1f", h, m, x) or string.format("%02d:%04.1f", m, x)
        end
        return h > 0 and string.format("%d:%02d:%02d", h, m, math.floor(x)) or string.format("%02d:%02d", m, math.floor(x))
    end
    local tick
    local function stopTicking()
        if tick then UIManager:unschedule(tick) end
        if s.awake then UIManager:allowStandby(); s.awake = false end
    end
    tick = function()
        if not s.running then return end
        if s.mode == "timer" and elapsed() >= s.target then
            s.running = false; s.base = s.target
            stopTicking()
            page:refresh("full")
            UIManager:show(InfoMessage:new{ text = "\u{F0F3}  " .. _("Time's up!") })
            return
        end
        page:refresh("fast")
        UIManager:scheduleIn(1, tick)
    end
    local function start()
        if s.mode == "timer" and s.target <= 0 then return end
        s.running = true; s.start = socket.gettime()
        if not s.awake then UIManager:preventStandby(); s.awake = true end
        UIManager:scheduleIn(1, tick)
    end
    local function stop() s.base = elapsed(); s.running = false; stopTicking() end
    local function content(p, inner, avail)
        local g = VerticalGroup:new{ align = "center" }
        local gap = Screen:scaleBySize(12)
        local regs = {}
        -- mode switch
        local half = math.floor((inner - gap) / 2)
        local mh = Screen:scaleBySize(64)
        table.insert(g, HorizontalGroup:new{
            CELL(T(_("Stopwatch"), 20, { bold = s.mode == "stopwatch" }), half, mh, { border = s.mode == "stopwatch" and 3 or 1,
                border_color = s.mode == "stopwatch" and Blitbuffer.COLOR_BLACK or nil }),
            HorizontalSpan:new{ width = gap },
            CELL(T(_("Timer"), 20, { bold = s.mode == "timer" }), half, mh, { border = s.mode == "timer" and 3 or 1,
                border_color = s.mode == "timer" and Blitbuffer.COLOR_BLACK or nil }),
        })
        table.insert(regs, { dx = 0, dy = 0, w = half, h = mh, fn = function() if not s.running then s.mode = "stopwatch"; s.base = 0; s.laps = {} end end })
        table.insert(regs, { dx = half + gap, dy = 0, w = half, h = mh, fn = function() if not s.running then s.mode = "timer"; s.base = 0 end end })
        local y = mh
        -- big time
        local shown = s.mode == "timer" and (s.target - elapsed()) or elapsed()
        local big_h = Screen:scaleBySize(260)
        table.insert(g, CenterContainer:new{ dimen = Geom:new{ w = inner, h = big_h },
            T(fmt(shown, s.mode == "stopwatch" and not s.running), 110, { font = "ffont", bold = true }) })
        y = y + big_h
        local bw = math.floor((inner - 3 * gap) / 4)
        local bh = Screen:scaleBySize(96)
        if s.mode == "timer" and not s.running then
            local adds = { { "+1 min", 60 }, { "+5 min", 300 }, { "+15 min", 900 }, { _("Clear"), 0 } }
            local hg = HorizontalGroup:new{}
            for i, a in ipairs(adds) do
                table.insert(hg, CELL(T(a[1], 20), bw, bh))
                if i < 4 then table.insert(hg, HorizontalSpan:new{ width = gap }) end
                table.insert(regs, { dx = (i - 1) * (bw + gap), dy = y, w = bw, h = bh, fn = function()
                    if a[2] == 0 then s.target = 0 else s.target = s.target + a[2] end; s.base = 0 end })
            end
            table.insert(g, hg)
            table.insert(g, VerticalSpan:new{ width = gap })
            y = y + bh + gap
        end
        local w2 = math.floor((inner - gap) / 2)
        local main = s.running and _("Pause") or ((elapsed() > 0) and _("Resume") or _("Start"))
        local second = (s.mode == "stopwatch" and s.running) and _("Lap") or _("Reset")
        table.insert(g, HorizontalGroup:new{
            CELL(T(main, 28, { bold = true }), w2, bh, { background = Blitbuffer.COLOR_LIGHT_GRAY }),
            HorizontalSpan:new{ width = gap },
            CELL(T(second, 28), w2, bh),
        })
        table.insert(regs, { dx = 0, dy = y, w = w2, h = bh, fn = function() if s.running then stop() else start() end end })
        table.insert(regs, { dx = w2 + gap, dy = y, w = w2, h = bh, fn = function()
            if s.mode == "stopwatch" and s.running then
                table.insert(s.laps, 1, elapsed())
            else
                stop(); s.base = 0; s.laps = {}
            end
        end })
        y = y + bh
        if s.mode == "stopwatch" and #s.laps > 0 then
            table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(20) })
            for i, l in ipairs(s.laps) do
                if i > 8 then break end
                table.insert(g, BOX(string.format(_("Lap %d   %s"), #s.laps - i + 1, fmt(l, true)), 22, inner, { align = "center", color = GRAY }))
            end
        end
        return g, function(x, yy)
            for _, r in ipairs(regs) do p:addHit(x + r.dx, yy + r.dy, r.w, r.h, function() r.fn(); page:refresh("ui") end) end
        end
    end
    page = Page:new{ title = _("Stopwatch & timer"), content_func = content,
        on_close = function() s.running = false; stopTicking() end }
    UIManager:show(page, "full")
end

----------------------------------------------------------------- notes (Memos)
function Mini.notes(home)
    -- read the settings fresh: they may have changed since the home screen opened
    local cfg = require("luasettings"):open(require("datastorage"):getSettingsDir() .. "/launcher.lua")
    local url, token = cfg:readSetting("memos_url"), cfg:readSetting("memos_token")
    if not url or not token then
        local MultiInputDialog = require("ui/widget/multiinputdialog")
        local dialog
        dialog = MultiInputDialog:new{
            title = _("Connect Notes to Memos"),
            fields = {
                { text = url or "", hint = _("Memos address, e.g. https://memos.example.com") },
                { text = "", hint = _("Access token (Memos → Settings → Access tokens)"), text_type = "password" },
            },
            buttons = {{
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                { text = _("Save"), is_enter_default = true, callback = function()
                    local f = dialog:getFields()
                    if f[1] == "" or f[2] == "" then return end
                    cfg:saveSetting("memos_url", f[1]); cfg:saveSetting("memos_token", f[2]); cfg:flush()
                    UIManager:close(dialog)
                    Mini.notes(home)
                end },
            }},
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
        return
    end
    url = url:gsub("/+$", "")
    local headers = { ["Authorization"] = "Bearer " .. token }
    local page
    local function load()
        local j = busy(_("Loading notes…"), function()
            return getJSON(url .. "/api/v1/memos?pageSize=30", headers)
        end)
        return j and j.memos or nil
    end
    local function newNote()
        local dialog
        dialog = InputDialog:new{
            title = _("New note"), input = "", allow_newline = true, input_height = 8,
            buttons = {{
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                { text = _("Save"), is_enter_default = false, callback = function()
                    local text = dialog:getInputText()
                    UIManager:close(dialog)
                    if text == "" then return end
                    local body = JSON.encode({ content = text, visibility = "PRIVATE" })
                    local h = { ["Authorization"] = headers.Authorization, ["Content-Type"] = "application/json",
                        ["Content-Length"] = tostring(#body) }
                    local okp, code = pcall(function()
                        return socket.skip(1, http.request{ url = url .. "/api/v1/memos", method = "POST", headers = h,
                            source = ltn12.source.string(body), sink = ltn12.sink.null() })
                    end)
                    if okp and code == 200 then
                        UIManager:show(InfoMessage:new{ text = _("Saved to Memos."), timeout = 2 })
                        if page then UIManager:close(page) end
                        Mini.notes(home)
                    else
                        UIManager:show(InfoMessage:new{ text = _("Couldn't save the note.") })
                    end
                end },
            }},
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end
    local memos = load()
    if not memos then
        UIManager:show(InfoMessage:new{ text = _("Couldn't reach Memos. Check Wi-Fi.") })
        return
    end
    local rows = { { left = "\u{F067}  " .. _("New note"), bold = true, callback = newNote } }
    for _, m in ipairs(memos) do
        local text = (m.content or ""):gsub("\r", "")
        local first = text:match("^[^\n]*") or ""
        local rest = text:sub(#first + 2):gsub("\n+", " ")
        local when = m.displayTime or m.createTime or ""
        local y, mo, d, hh, mm = when:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
        local stamp = y and os.date("%d %b %H:%M", os.time{ year = y, month = mo, day = d, hour = hh, min = mm } + (os.time() - os.time(os.date("!*t")))) or ""
        table.insert(rows, {
            left = first ~= "" and first or _("(empty)"), right = stamp, size = 20,
            sub = rest ~= "" and (rest:sub(1, 140)) or nil,
            callback = function()
                UIManager:show(TextViewer:new{ title = stamp, text = text, justified = false })
            end,
        })
    end
    page = Page:new{ title = _("Notes"), rows = rows }
    UIManager:show(page, "full")
end

return Mini
