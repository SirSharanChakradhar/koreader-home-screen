--[[--
The home screen: clock and weather, panchang, a now-playing card, continue
reading, recent books and app tiles.

Everything is drawn as plain widgets and hit-tested in onGesture (no KOReader
Buttons: they crash when tapped after a rebuild but before their first paint,
and this screen rebuilds every minute).
--]]--
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local NetworkMgr = require("ui/network/manager")
local Apps = require("apps")
local Panchang = require("panchang")
local ProgressWidget = require("ui/widget/progresswidget")
local RenderImage = require("ui/renderimage")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Weather = require("weather")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

local CONFIG_FILE = DataStorage:getSettingsDir() .. "/launcher.lua"

local I = {
    prev = "\u{F048}", play = "\u{F04B}", pause = "\u{F04C}", next = "\u{F051}", music = "\u{F001}",
    folder = "\u{F07B}", globe = "\u{F0AC}", history = "\u{F1DA}", heart = "\u{F004}", bulb = "\u{F0EB}",
    moon = "\u{F186}", wifi = "\u{F1EB}", power = "\u{F011}", signout = "\u{F08B}", book = "\u{F02D}",
    headphones = "\u{F025}", bolt = "\u{F0E7}",
}

-- optional: the Navidrome music plugin
local function optional(name)
    local ok, m = pcall(require, name)
    if ok and type(m) == "table" then return m end
end

local Home = InputContainer:extend{
    name = "launcher_home",
    covers_fullscreen = true,
    ui = nil, -- the FileManager we sit on
}

function Home.config()
    return LuaSettings:open(CONFIG_FILE)
end

function Home:init()
    self.W, self.H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.W, h = self.H }
    self.cfg = Home.config()
    self.page = self.page or self.cfg:readSetting("start_page") or 1
    self.Engine = optional("npengine")
    self.Api = optional("npapi")
    self.covers = {}        -- file -> blitbuffer
    self.music_cover, self.music_cover_id = nil, nil
    self.remote = nil
    self.hit = {}
    if self.Engine then
        self.listener = function() self:refresh("ui") end
        self.Engine:addListener(self.listener)
    end
    self.tick = function() self:onTick() end
    self.poll = function() self:pollRemote() end
    self:build()
    UIManager:scheduleIn(1, self.tick)
    UIManager:scheduleIn(2, self.poll)
    -- testing aid: open an app straight away (settings key start_app = "<app id>")
    local start_app = self.cfg:readSetting("start_app")
    if start_app then
        UIManager:scheduleIn(2, function()
            local a = Apps.byId(self.ui, start_app)
            if a then a.run(self) end
        end)
    end
    -- fetch the weather after the first paint
    UIManager:scheduleIn(1, function()
        if Weather:get(self.cfg:readSetting("lat"), self.cfg:readSetting("lon")) then self:refresh("ui") end
    end)
end

function Home:onCloseWidget()
    UIManager:unschedule(self.tick)
    UIManager:unschedule(self.poll)
    if self.Engine and self.listener then self.Engine:removeListener(self.listener) end
    for _, bb in pairs(self.covers) do if bb then bb:free() end end
    self.covers = {}
    if self.music_cover then self.music_cover:free(); self.music_cover = nil end
end

function Home:close()
    UIManager:close(self, "full")
end

function Home:refresh(mode)
    self:build()
    UIManager:setDirty(self, mode or "ui")
end

function Home:onTick()
    local minute = os.date("%H:%M")
    if minute ~= self.last_minute then
        self.last_minute = minute
        Weather:get(self.cfg:readSetting("lat"), self.cfg:readSetting("lon")) -- cached, refetches every 30 min
        self:refresh("ui")
    elseif self.Engine and self.Engine.state == "playing" then
        -- keep the mini progress moving (every 5 s)
        local p = math.floor(self.Engine:position() / 5)
        if p ~= self.last_p then self.last_p = p; self:refresh("ui") end
    end
    UIManager:scheduleIn(1, self.tick)
end

----------------------------------------------------------------- data
function Home:musicTrack()
    local E = self.Engine
    if E and E:isActive() and E:current() then return E:current(), "local" end
    if self.remote then return self.remote, "remote" end
end

-- what is playing on other Navidrome clients (when the Kobo is idle)
function Home:pollRemote()
    UIManager:unschedule(self.poll)
    local E, A = self.Engine, self.Api
    if A and not (E and E:isActive()) then
        local api = A.fromConfig()
        if api:isConfigured() then
            local r = api:call("getNowPlaying")
            local best
            for _, e in ipairs(r and r.nowPlaying and r.nowPlaying.entry or {}) do
                local own = e.playerName and e.playerName:match("^kobo%-")
                if not own and (not best or (e.minutesAgo or 0) < (best.minutesAgo or 0)) then best = e end
            end
            local changed = (best and best.id) ~= (self.remote and self.remote.id)
            self.remote = best
            if changed then self:refresh("ui") end
        end
    end
    UIManager:scheduleIn(15, self.poll)
end

function Home:musicCover(track, size)
    if not track or not track.coverArt or not self.Api then return nil end
    if self.music_cover_id == track.coverArt then return self.music_cover end
    if self.music_cover then self.music_cover:free(); self.music_cover = nil end
    self.music_cover_id = track.coverArt
    local data = self.Api.fromConfig():raw("getCoverArt", { id = track.coverArt, size = size })
    if data and #data > 100 then
        local ok, bb
        if data:sub(1, 3) == "\255\216\255" then
            ok, bb = pcall(require("ffi/jpeg").openDocumentFromMem, data, false, #data)
        else
            ok, bb = pcall(RenderImage.renderImageData, RenderImage, data, #data, false)
            if ok and bb then bb = bb:copy() end
        end
        if ok and bb then self.music_cover = bb end
    end
    return self.music_cover
end

-- title, authors, percent and a cover for a book file (cached per screen)
function Home:bookInfo(file, cw, ch)
    local key = file .. "@" .. cw
    if self.infos and self.infos[key] then return self.infos[key] end
    self.infos = self.infos or {}
    local info = { file = file, title = file:match("([^/]+)%.[^.]+$") or file }
    local ok, ds = pcall(DocSettings.open, DocSettings, file)
    if ok and ds then
        info.percent = ds:readSetting("percent_finished")
        local props = ds:readSetting("doc_props") or {}
        if props.title and props.title ~= "" then info.title = props.title end
        info.authors = props.authors
    end
    local BIM = optional("bookinfomanager")
    if BIM then
        local okb, bi = pcall(BIM.getBookInfo, BIM, file, true)
        if okb and bi then
            if bi.title and bi.title ~= "" then info.title = bi.title end
            if bi.authors and bi.authors ~= "" then info.authors = info.authors or bi.authors end
            if bi.cover_bb then
                local sc = math.min(cw / bi.cover_w, ch / bi.cover_h)
                local okc, bb = pcall(RenderImage.scaleBlitBuffer, RenderImage, bi.cover_bb,
                    math.max(1, math.floor(bi.cover_w * sc)), math.max(1, math.floor(bi.cover_h * sc)), true)
                if okc and bb then
                    self.covers[key] = bb
                    info.cover = bb
                end
            end
        end
    end
    if info.authors then info.authors = info.authors:gsub("\n", ", ") end
    self.infos[key] = info
    return info
end

function Home:recentFiles(n)
    local out = {}
    local ok, RH = pcall(require, "readhistory")
    if not ok then return out end
    pcall(RH.reload, RH)
    for _, item in ipairs(RH.hist or {}) do
        if item.file and not item.dim and not item.file:find("/koreader/help/", 1, true)
            and lfs.attributes(item.file, "mode") == "file" then
            table.insert(out, item.file)
            if #out >= n then break end
        end
    end
    return out
end

----------------------------------------------------------------- actions
-- run a KOReader action: call the handler of whichever module provides it
-- (the file browser itself or one of its plugins), else broadcast the event
function Home:send(ev)
    local ui = self.ui
    if not ui then return end
    local h = "on" .. ev
    if type(ui[h]) == "function" then return ui[h](ui) end
    for _, m in ipairs(ui) do
        if type(m) == "table" and type(m[h]) == "function" then return m[h](m) end
    end
    for k, m in pairs(ui) do
        if type(k) == "string" and type(m) == "table" and type(m[h]) == "function" then return m[h](m) end
    end
    logger.dbg("launcher: no handler for", ev, "- broadcasting")
    UIManager:broadcastEvent(Event:new(ev))
end

function Home:openBook(file)
    self:close()
    UIManager:nextTick(function()
        require("apps/reader/readerui"):showReader(file)
    end)
end

function Home:openMusic(library)
    local Browse = optional("npbrowse")
    if library and Browse then Browse:showLibrary() return end
    self:send("ShowNowPlaying")
end

function Home:openLibrary()
    self:close()
    -- open the home folder without coming back here (unlike the home icon)
    local fc = self.ui and self.ui.file_chooser
    if fc and fc.goHome then pcall(fc.goHome, fc) end
end

function Home:dockApps()
    local ids = self.cfg:readSetting("dock") or Apps.DEFAULT_DOCK
    local out = {}
    for _, id in ipairs(ids) do
        local a = Apps.byId(self.ui, id)
        if a then table.insert(out, a) end
    end
    table.insert(out, { id = "apps", icon = Apps.ICON.th, label = _("Apps"), run = function(h) h:setPage(2) end })
    return out
end

function Home:setPage(n)
    self.page = n
    self:refresh("full")
end

-- today's reading time and pages from the statistics plugin's database
function Home:readingToday()
    local now = os.time()
    if self._today and now - self._today.at < 300 then return self._today end
    local t = os.date("*t", now)
    local midnight = os.time{ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 }
    local res = { at = now }
    local ok = pcall(function()
        local SQ3 = require("lua-ljsqlite3/init")
        local db = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
        if lfs.attributes(db, "mode") ~= "file" then return end
        local conn = SQ3.open(db)
        local row = conn:exec(string.format(
            "SELECT count(*), sum(duration) FROM page_stat_data WHERE start_time >= %d", midnight))
        if row and row[1] then
            res.pages = tonumber(row[1][1]) or 0
            res.seconds = tonumber(row[2] and row[2][1]) or 0
        end
        conn:close()
    end)
    if not ok then logger.dbg("launcher: no reading stats") end
    self._today = res
    return res
end

----------------------------------------------------------------- layout helpers
local GRAY = Blitbuffer.COLOR_DARK_GRAY
local function tb(str, size, width, opts)
    opts = opts or {}
    return TextBoxWidget:new{
        text = (str and str ~= "") and str or " ",
        face = opts.face or Font:getFace(opts.font or "cfont", size),
        width = width, alignment = opts.align or "left",
        bold = opts.bold, fgcolor = opts.color or Blitbuffer.COLOR_BLACK,
        height = opts.height, height_overflow_show_ellipsis = opts.height and true or nil,
    }
end

local function tw(str, size, opts)
    opts = opts or {}
    return TextWidget:new{ text = str, face = Font:getFace(opts.font or "cfont", size),
        bold = opts.bold, fgcolor = opts.color or Blitbuffer.COLOR_BLACK, max_width = opts.max_width }
end

function Home:card(content, w)
    local b, p = Screen:scaleBySize(1), Screen:scaleBySize(14)
    return FrameContainer:new{
        width = w, padding = p, margin = 0, bordersize = b, radius = Screen:scaleBySize(14),
        color = Blitbuffer.COLOR_LIGHT_GRAY, background = Blitbuffer.COLOR_WHITE,
        content,
    }, b + p
end

function Home:addHit(x, y, w, h, fn)
    table.insert(self.hit, { x = x, y = y, w = w, h = h, fn = fn })
end

----------------------------------------------------------------- sections
function Home:header(inner)
    local cfg = self.cfg
    local left = VerticalGroup:new{ align = "left",
        tw(os.date("%H:%M"), 88, { font = "ffont", bold = true }),
        tw(os.date("%A, %d %B"), 26),
    }
    local right = VerticalGroup:new{ align = "right" }
    local w = Weather.data
    if w and w.temp then
        table.insert(right, tw(w.icon .. "  " .. string.format("%d°", math.floor(w.temp + 0.5)), 46, { bold = true }))
        local hl = (w.high and w.low) and string.format("H %d°  ·  L %d°", math.floor(w.high + 0.5), math.floor(w.low + 0.5)) or ""
        table.insert(right, tw(hl, 20))
        table.insert(right, tw((w.text or "") .. ((cfg:readSetting("place") and ("  ·  " .. cfg:readSetting("place"))) or ""), 18, { color = GRAY }))
    end
    local gap = math.max(0, inner - left:getSize().w - right:getSize().w)
    return HorizontalGroup:new{ align = "center", left, HorizontalSpan:new{ width = gap }, right }
end

function Home:statusBar(inner)
    local power = Device:getPowerDevice()
    local batt = ""
    if power then batt = (power:isCharging() and (I.bolt .. " ") or "") .. power:getCapacity() .. "%" end
    local wifi = NetworkMgr:isWifiOn() and (I.wifi .. "  ") or ""
    local right = tw(wifi .. batt, 18)
    local left = tw(" ", 18)
    return HorizontalGroup:new{ left, HorizontalSpan:new{ width = inner - left:getSize().w - right:getSize().w }, right }
end

function Home:panchangLine(inner)
    if self.cfg:isFalse("panchang") then return nil end
    local lang = self.cfg:readSetting("panchang_lang") or "te"
    local now = os.time()
    local parts = { Panchang.tithi(now, lang), Panchang.nakshatra(now, lang) }
    local w = Weather.data
    if w and w.sunrise and w.sunset then
        local s, e = Panchang.rahuKalam(w.sunrise, w.sunset)
        if s then
            table.insert(parts, Panchang.LABEL[lang].rahu .. " " .. os.date("%H:%M", s) .. "–" .. os.date("%H:%M", e))
        end
    end
    local face = lang == "te" and Font:getFace("noto/NotoSansTelugu-Regular.ttf", 21) or Font:getFace("cfont", 20)
    return tb(table.concat(parts, "   ·   "), 21, inner, { face = face, color = GRAY })
end

-- returns widget, and a function(y) that registers hit areas once we know where it sits
function Home:musicCard(inner)
    local track, mode = self:musicTrack()
    local card_inner = inner - 2 * (Screen:scaleBySize(15))
    local cs = Screen:scaleBySize(118)
    local regs = {}
    local content = VerticalGroup:new{ align = "left" }
    local info_h = cs
    local label, title, sub
    if track then
        label = mode == "local" and _("NOW PLAYING") or (I.headphones .. "  " .. (track.playerName or _("Playing elsewhere")))
        title, sub = track.title or "", track.artist or ""
    else
        label, title, sub = _("MUSIC"), _("Nothing playing"), _("Tap to open your music library")
    end
    local cover = track and self:musicCover(track, cs)
    local text_w = card_inner - cs - Screen:scaleBySize(18)
    local info = HorizontalGroup:new{ align = "center",
        CenterContainer:new{ dimen = Geom:new{ w = cs, h = cs },
            cover and ImageWidget:new{ image = cover, image_disposable = false, width = cs, height = cs, scale_factor = 0 }
            or tw(I.music, 70) },
        HorizontalSpan:new{ width = Screen:scaleBySize(18) },
        VerticalGroup:new{ align = "left",
            tw(label, 15, { color = GRAY, max_width = text_w }),
            VerticalSpan:new{ width = Screen:scaleBySize(6) },
            tb(title, 24, text_w, { bold = true, height = Screen:scaleBySize(36) }),
            tb(sub, 19, text_w, { color = GRAY, height = Screen:scaleBySize(28) }),
        },
    }
    table.insert(content, info)
    local controls_h = 0
    if mode == "local" then
        local E = self.Engine
        local dur = tonumber(track.duration) or 0
        table.insert(content, VerticalSpan:new{ width = Screen:scaleBySize(10) })
        table.insert(content, ProgressWidget:new{ width = card_inner, height = Screen:scaleBySize(6),
            percentage = dur > 0 and math.min(1, E:position() / dur) or 0, fillcolor = Blitbuffer.COLOR_BLACK })
        table.insert(content, VerticalSpan:new{ width = Screen:scaleBySize(10) })
        local ch = Screen:scaleBySize(56)
        local gap = Screen:scaleBySize(10)
        local cw = math.floor((card_inner - 2 * gap) / 3)
        local row = HorizontalGroup:new{}
        local acts = {
            { I.prev, function() E:prev() end },
            { E.state == "playing" and I.pause or I.play, function() E:toggle() end },
            { I.next, function() E:next() end },
        }
        for i, a in ipairs(acts) do
            table.insert(row, FrameContainer:new{ width = cw, height = ch, padding = 0, bordersize = Screen:scaleBySize(1),
                radius = Screen:scaleBySize(10), color = Blitbuffer.COLOR_LIGHT_GRAY,
                CenterContainer:new{ dimen = Geom:new{ w = cw - 2, h = ch - 2 }, tw(a[1], 26) } })
            if i < 3 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        end
        table.insert(content, row)
        controls_h = ch
        local before = info:getSize().h + Screen:scaleBySize(10) + Screen:scaleBySize(6) + Screen:scaleBySize(10)
        for i, a in ipairs(acts) do
            table.insert(regs, { dx = (i - 1) * (cw + gap), dy = before, w = cw, h = ch, fn = a[2] })
        end
    end
    local card, off = self:card(content, inner)
    local open = function() self:openMusic(not track) end
    return card, function(x, y)
        for _, r in ipairs(regs) do self:addHit(x + off + r.dx, y + off + r.dy, r.w, r.h, r.fn) end
        self:addHit(x, y, inner, card:getSize().h, open)
    end
end

function Home:readingCard(inner, file)
    local cw, ch = Screen:scaleBySize(100), Screen:scaleBySize(142)
    local b = self:bookInfo(file, cw, ch)
    local card_inner = inner - 2 * Screen:scaleBySize(15)
    local text_w = card_inner - cw - Screen:scaleBySize(18)
    local pct = b.percent and math.floor(b.percent * 100 + 0.5) or nil
    local right = VerticalGroup:new{ align = "left",
        tw(_("CONTINUE READING"), 15, { color = GRAY }),
        VerticalSpan:new{ width = Screen:scaleBySize(6) },
        tb(b.title, 24, text_w, { bold = true, height = Screen:scaleBySize(36) }),
        tb(b.authors or "", 19, text_w, { color = GRAY, height = Screen:scaleBySize(28) }),
        VerticalSpan:new{ width = Screen:scaleBySize(10) },
        ProgressWidget:new{ width = text_w, height = Screen:scaleBySize(8),
            percentage = b.percent or 0, fillcolor = Blitbuffer.COLOR_BLACK },
        VerticalSpan:new{ width = Screen:scaleBySize(6) },
        tw(self:progressLine(pct), 17, { color = GRAY, max_width = text_w }),
    }
    local content = HorizontalGroup:new{ align = "center",
        CenterContainer:new{ dimen = Geom:new{ w = cw, h = ch },
            b.cover and ImageWidget:new{ image = b.cover, image_disposable = false } or tw(I.book, 70) },
        HorizontalSpan:new{ width = Screen:scaleBySize(18) },
        right,
    }
    local card = self:card(content, inner)
    return card, function(x, y) self:addHit(x, y, inner, card:getSize().h, function() self:openBook(file) end) end
end

function Home:progressLine(pct)
    local line = pct and (pct .. "% " .. _("read")) or _("Not started")
    local t = self:readingToday()
    if t.seconds and t.seconds > 0 then
        local m = math.floor(t.seconds / 60 + 0.5)
        local dur = m >= 60 and string.format("%dh %02dm", math.floor(m / 60), m % 60) or (m .. " min")
        line = line .. "   ·   " .. _("Today: ") .. dur .. ", " .. (t.pages or 0) .. " " .. _("pages")
    end
    return line
end

function Home:recentRow(inner, files, max_h)
    local n = 4
    local gap = Screen:scaleBySize(16)
    local label_h = Screen:scaleBySize(30)
    local cw = math.floor((inner - gap * (n - 1)) / n)
    local ch = math.floor(cw * 1.4)
    if max_h and ch > max_h - label_h then
        ch = max_h - label_h
        cw = math.floor(ch / 1.4)
    end
    local row = HorizontalGroup:new{ align = "top" }
    local items = {}
    for i, f in ipairs(files) do
        if i > n then break end
        local b = self:bookInfo(f, cw, ch)
        table.insert(row, VerticalGroup:new{ align = "center",
            CenterContainer:new{ dimen = Geom:new{ w = cw, h = ch },
                b.cover and ImageWidget:new{ image = b.cover, image_disposable = false }
                or FrameContainer:new{ width = cw, height = ch, bordersize = Screen:scaleBySize(1), padding = Screen:scaleBySize(8),
                    color = Blitbuffer.COLOR_LIGHT_GRAY,
                    CenterContainer:new{ dimen = Geom:new{ w = cw - Screen:scaleBySize(18), h = ch - Screen:scaleBySize(18) },
                        tb(b.title, 17, cw - Screen:scaleBySize(18), { align = "center" }) } } },
        })
        table.insert(items, f)
        if i < n then table.insert(row, HorizontalSpan:new{ width = gap }) end
    end
    local block = VerticalGroup:new{ align = "left",
        tw(_("RECENT"), 15, { color = GRAY }),
        VerticalSpan:new{ width = Screen:scaleBySize(8) },
        row,
    }
    label_h = block[1]:getSize().h + Screen:scaleBySize(8)
    return block, function(x, y)
        for i, f in ipairs(items) do
            self:addHit(x + (i - 1) * (cw + gap), y + label_h, cw, ch, function() self:openBook(f) end)
        end
    end
end

-- a grid of app tiles; returns widget and register(x, y)
function Home:grid(inner, apps, cols, th, icon_size, label_size)
    local gap = Screen:scaleBySize(12)
    local tw_ = math.floor((inner - gap * (cols - 1)) / cols)
    local grid = VerticalGroup:new{ align = "left" }
    local regs = {}
    local row
    for i, a in ipairs(apps) do
        local c = (i - 1) % cols
        if c == 0 then
            row = HorizontalGroup:new{}
            if i > 1 then table.insert(grid, VerticalSpan:new{ width = gap }) end
            table.insert(grid, row)
        end
        table.insert(row, FrameContainer:new{ width = tw_, height = th, padding = 0,
            bordersize = Screen:scaleBySize(1), radius = Screen:scaleBySize(14), color = Blitbuffer.COLOR_LIGHT_GRAY,
            CenterContainer:new{ dimen = Geom:new{ w = tw_ - 2, h = th - 2 },
                VerticalGroup:new{ align = "center", tw(a.icon, icon_size or 30),
                    VerticalSpan:new{ width = Screen:scaleBySize(4) },
                    tw(a.label, label_size or 16, { max_width = tw_ - Screen:scaleBySize(8) }) } } })
        if c < cols - 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        local r = math.floor((i - 1) / cols)
        table.insert(regs, { dx = c * (tw_ + gap), dy = r * (th + gap), a = a })
    end
    return grid, function(x, y)
        for _, r in ipairs(regs) do
            self:addHit(x + r.dx, y + r.dy, tw_, th, function() r.a.run(self) end)
        end
    end
end

function Home:pageDots()
    local parts = {}
    for i = 1, self:pageCount() do
        table.insert(parts, (i == (self.page or 1)) and "\u{F111}" or "\u{F10C}")
    end
    local dots = table.concat(parts, "   ")
    return CenterContainer:new{ dimen = Geom:new{ w = self.W - 2 * Screen:scaleBySize(30), h = Screen:scaleBySize(22) },
        tw(dots, 12, { color = GRAY }) }
end

----------------------------------------------------------------- build
function Home:build()
    if (self.page or 1) >= 2 then return self:buildApps() end
    local W, H = self.W, self.H
    local margin = Screen:scaleBySize(30)
    local inner = W - 2 * margin
    local gap = Screen:scaleBySize(14)
    self.hit = {}

    -- sections, each { widget, register(x, y) or nil }
    local sections = {}
    local function add(w, reg) if w then table.insert(sections, { w, reg }) end end
    add(self:statusBar(inner))
    add(self:header(inner))
    add(self:panchangLine(inner))
    add(self:musicCard(inner))
    local files = self:recentFiles(5)
    if files[1] then add(self:readingCard(inner, files[1])) end
    local dock_apps = self:dockApps()
    local grid, grid_reg = self:grid(inner, dock_apps, #dock_apps, Screen:scaleBySize(88))
    -- recent books only if they fit above the tiles
    local used = 0
    for _, s in ipairs(sections) do used = used + s[1]:getSize().h + gap end
    if #files > 1 then
        local others = {}
        for i = 2, #files do table.insert(others, files[i]) end
        -- size the covers to whatever room is left above the tiles
        local room = H - Screen:scaleBySize(10) - used - grid:getSize().h - Screen:scaleBySize(30) - gap
        if room >= Screen:scaleBySize(120) then
            local row, row_reg = self:recentRow(inner, others, room)
            add(row, row_reg)
            used = used + row:getSize().h + gap
        end
    end

    -- never let the tiles fall off the bottom: shrink the gaps if needed
    local total = Screen:scaleBySize(10) + grid:getSize().h + Screen:scaleBySize(30)
    for _, sct in ipairs(sections) do total = total + sct[1]:getSize().h end
    local free = H - total
    if free < gap * #sections then gap = math.max(0, math.floor(free / math.max(1, #sections))) end
    logger.dbg("launcher: layout H", H, "content", total, "gap", gap)

    local body = VerticalGroup:new{ align = "left" }
    local y = Screen:scaleBySize(10)
    table.insert(body, VerticalSpan:new{ width = y })
    for _, s in ipairs(sections) do
        table.insert(body, s[1])
        if s[2] then s[2](margin, y) end
        y = y + s[1]:getSize().h
        table.insert(body, VerticalSpan:new{ width = gap })
        y = y + gap
    end
    -- tiles pinned to the bottom
    local grid_y = H - grid:getSize().h - Screen:scaleBySize(30)
    if grid_y > y then
        table.insert(body, VerticalSpan:new{ width = grid_y - y })
        y = grid_y
    end
    table.insert(body, grid)
    grid_reg(margin, y)
    table.insert(body, self:pageDots())

    self[1] = FrameContainer:new{
        width = W, height = H, padding = 0, margin = 0, bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = margin }, body },
    }
end

-- split the app groups into pages that fit the screen
function Home:appPages()
    if self._app_pages then return self._app_pages end
    local groups = Apps.available(self.ui)
    local th = Screen:scaleBySize(80)
    local gap = Screen:scaleBySize(12)
    local head_h = Screen:scaleBySize(34) + Screen:scaleBySize(6)
    local top = Screen:scaleBySize(10) + Screen:scaleBySize(36) + Screen:scaleBySize(60) + Screen:scaleBySize(6)
    local avail = self.H - top - Screen:scaleBySize(40)
    local pages, cur, used = {}, {}, 0
    for _, g in ipairs(groups) do
        local rows = math.ceil(#g.apps / 5)
        local h = head_h + rows * th + (rows - 1) * gap + Screen:scaleBySize(6)
        if used + h > avail and #cur > 0 then
            table.insert(pages, cur); cur, used = {}, 0
        end
        table.insert(cur, g); used = used + h
    end
    if #cur > 0 then table.insert(pages, cur) end
    self._app_pages, self._tile_h = pages, th
    return pages
end

function Home:pageCount()
    return 1 + #self:appPages()
end

function Home:buildApps()
    local W, H = self.W, self.H
    local margin = Screen:scaleBySize(30)
    local inner = W - 2 * margin
    self.hit = {}
    local pages = self:appPages()
    local groups = pages[self.page - 1] or pages[1] or {}
    local body = VerticalGroup:new{ align = "left" }
    local y = 0
    local function put(w)
        table.insert(body, w); y = y + w:getSize().h
    end
    put(VerticalSpan:new{ width = Screen:scaleBySize(10) })
    put(self:statusBar(inner))
    local title = _("Apps")
    if #pages > 1 then title = title .. "  " .. (self.page - 1) .. "/" .. #pages end
    put(CenterContainer:new{ dimen = Geom:new{ w = inner, h = Screen:scaleBySize(60) },
        HorizontalGroup:new{ align = "center", tw(title, 32, { bold = true }),
            HorizontalSpan:new{ width = inner - tw(title, 32, { bold = true }):getSize().w - tw(os.date("%H:%M"), 22):getSize().w },
            tw(os.date("%H:%M"), 22, { color = GRAY }) } })
    put(VerticalSpan:new{ width = Screen:scaleBySize(6) })
    local head_h = Screen:scaleBySize(34)
    for _, g in ipairs(groups) do
        put(CenterContainer:new{ dimen = Geom:new{ w = inner, h = head_h },
            HorizontalGroup:new{ tw(g.title:upper(), 15, { color = GRAY }),
                HorizontalSpan:new{ width = inner - tw(g.title:upper(), 15):getSize().w } } })
        put(VerticalSpan:new{ width = Screen:scaleBySize(6) })
        local grid, reg = self:grid(inner, g.apps, 5, self._tile_h, 26, 15)
        reg(margin, y)
        put(grid)
        put(VerticalSpan:new{ width = Screen:scaleBySize(6) })
    end
    local dots = self:pageDots()
    local spare = H - y - dots:getSize().h - Screen:scaleBySize(8)
    if spare > 0 then put(VerticalSpan:new{ width = spare }) end
    put(dots)
    self[1] = FrameContainer:new{
        width = W, height = H, padding = 0, margin = 0, bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = margin }, body },
    }
end

function Home:onGesture(ev)
    if ev.ges == "swipe" then
        local p = self.page or 1
        if ev.direction == "west" and p < self:pageCount() then self:setPage(p + 1) return true end
        if ev.direction == "east" and p > 1 then self:setPage(p - 1) return true end
        return true
    end
    if ev.ges ~= "tap" then return InputContainer.onGesture(self, ev) end
    local x, y = ev.pos.x, ev.pos.y
    for _, h in ipairs(self.hit) do
        if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then
            UIManager:nextTick(h.fn)
            return true
        end
    end
    return true
end

return Home
