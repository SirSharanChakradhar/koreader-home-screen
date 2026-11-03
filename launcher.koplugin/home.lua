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
        if item.file and not item.dim and lfs.attributes(item.file, "mode") == "file" then
            table.insert(out, item.file)
            if #out >= n then break end
        end
    end
    return out
end

----------------------------------------------------------------- actions
function Home:send(ev)
    if self.ui then self.ui:handleEvent(Event:new(ev)) end
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

function Home:tiles()
    return {
        { I.folder, _("Library"), function()
            self:close()
            -- open the home folder without coming back here (unlike the home icon)
            local fc = self.ui and self.ui.file_chooser
            if fc and fc.goHome then pcall(fc.goHome, fc) end
        end },
        { I.music, _("Music"), function() self:openMusic(false) end },
        { I.globe, _("Kavita"), function() self:send("ShowOPDSCatalog") end },
        { I.history, _("History"), function() self:send("ShowHist") end },
        { I.heart, _("Favorites"), function() self:send("ShowColl") end },
        { I.bulb, _("Light"), function() self:send("ShowFlDialog") end },
        { I.moon, _("Night"), function() self:send("ToggleNightMode"); UIManager:nextTick(function() self:refresh("full") end) end },
        { I.wifi, _("Wi-Fi"), function() self:send("ToggleWifi") end },
        { I.power, _("Sleep"), function() UIManager:suspend() end },
        { I.signout, _("Kobo"), function() UIManager:broadcastEvent(Event:new("Exit")) end },
    }
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
        tw(os.date("%H:%M"), 100, { font = "ffont", bold = true }),
        tw(os.date("%A, %d %B"), 26),
    }
    local right = VerticalGroup:new{ align = "right" }
    local w = Weather.data
    if w and w.temp then
        table.insert(right, tw(w.icon .. "  " .. string.format("%d°", math.floor(w.temp + 0.5)), 52, { bold = true }))
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
    local cs = Screen:scaleBySize(150)
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
            tb(title, 26, text_w, { bold = true, height = Screen:scaleBySize(70) }),
            tb(sub, 20, text_w, { color = GRAY, height = Screen:scaleBySize(30) }),
        },
    }
    table.insert(content, info)
    local controls_h = 0
    if mode == "local" then
        local E = self.Engine
        local dur = tonumber(track.duration) or 0
        table.insert(content, VerticalSpan:new{ width = Screen:scaleBySize(12) })
        table.insert(content, ProgressWidget:new{ width = card_inner, height = Screen:scaleBySize(8),
            percentage = dur > 0 and math.min(1, E:position() / dur) or 0, fillcolor = Blitbuffer.COLOR_BLACK })
        table.insert(content, VerticalSpan:new{ width = Screen:scaleBySize(12) })
        local ch = Screen:scaleBySize(74)
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
                CenterContainer:new{ dimen = Geom:new{ w = cw - 2, h = ch - 2 }, tw(a[1], 32) } })
            if i < 3 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        end
        table.insert(content, row)
        controls_h = ch
        local before = info_h + Screen:scaleBySize(32) -- info + spacing + progress + spacing
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
    local cw, ch = Screen:scaleBySize(130), Screen:scaleBySize(185)
    local b = self:bookInfo(file, cw, ch)
    local card_inner = inner - 2 * Screen:scaleBySize(15)
    local text_w = card_inner - cw - Screen:scaleBySize(18)
    local pct = b.percent and math.floor(b.percent * 100 + 0.5) or nil
    local right = VerticalGroup:new{ align = "left",
        tw(_("CONTINUE READING"), 15, { color = GRAY }),
        VerticalSpan:new{ width = Screen:scaleBySize(6) },
        tb(b.title, 26, text_w, { bold = true, height = Screen:scaleBySize(70) }),
        tb(b.authors or "", 20, text_w, { color = GRAY, height = Screen:scaleBySize(30) }),
        VerticalSpan:new{ width = Screen:scaleBySize(14) },
        ProgressWidget:new{ width = text_w, height = Screen:scaleBySize(8),
            percentage = b.percent or 0, fillcolor = Blitbuffer.COLOR_BLACK },
        VerticalSpan:new{ width = Screen:scaleBySize(6) },
        tw(pct and (pct .. "% " .. _("read")) or _("Not started"), 17, { color = GRAY }),
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

function Home:recentRow(inner, files)
    local n = 4
    local gap = Screen:scaleBySize(16)
    local cw = math.floor((inner - gap * (n - 1)) / n)
    local ch = math.floor(cw * 1.4)
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
    local label_h = block[1]:getSize().h + Screen:scaleBySize(8)
    return block, function(x, y)
        for i, f in ipairs(items) do
            self:addHit(x + (i - 1) * (cw + gap), y + label_h, cw, ch, function() self:openBook(f) end)
        end
    end
end

function Home:tileGrid(inner)
    local tiles = self:tiles()
    local cols = 5
    local gap = Screen:scaleBySize(12)
    local tw_ = math.floor((inner - gap * (cols - 1)) / cols)
    local th = Screen:scaleBySize(108)
    local grid = VerticalGroup:new{ align = "left" }
    local regs = {}
    local row
    for i, t in ipairs(tiles) do
        local c = (i - 1) % cols
        if c == 0 then
            row = HorizontalGroup:new{}
            if i > 1 then table.insert(grid, VerticalSpan:new{ width = gap }) end
            table.insert(grid, row)
        end
        table.insert(row, FrameContainer:new{ width = tw_, height = th, padding = 0,
            bordersize = Screen:scaleBySize(1), radius = Screen:scaleBySize(14), color = Blitbuffer.COLOR_LIGHT_GRAY,
            CenterContainer:new{ dimen = Geom:new{ w = tw_ - 2, h = th - 2 },
                VerticalGroup:new{ align = "center", tw(t[1], 34), VerticalSpan:new{ width = Screen:scaleBySize(6) }, tw(t[2], 17) } } })
        if c < cols - 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        local r = math.floor((i - 1) / cols)
        table.insert(regs, { dx = c * (tw_ + gap), dy = r * (th + gap), fn = t[3] })
    end
    return grid, function(x, y)
        for _, r in ipairs(regs) do self:addHit(x + r.dx, y + r.dy, tw_, th, r.fn) end
    end
end

----------------------------------------------------------------- build
function Home:build()
    local W, H = self.W, self.H
    local margin = Screen:scaleBySize(30)
    local inner = W - 2 * margin
    local gap = Screen:scaleBySize(22)
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
    local grid, grid_reg = self:tileGrid(inner)
    -- recent books only if they fit above the tiles
    local used = 0
    for _, s in ipairs(sections) do used = used + s[1]:getSize().h + gap end
    if #files > 1 then
        local others = {}
        for i = 2, #files do table.insert(others, files[i]) end
        local row, row_reg = self:recentRow(inner, others)
        if used + row:getSize().h + gap + grid:getSize().h + Screen:scaleBySize(20) <= H then
            add(row, row_reg)
            used = used + row:getSize().h + gap
        end
    end

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
    local grid_y = H - grid:getSize().h - Screen:scaleBySize(24)
    if grid_y > y then
        table.insert(body, VerticalSpan:new{ width = grid_y - y })
        y = grid_y
    end
    table.insert(body, grid)
    grid_reg(margin, y)

    self[1] = FrameContainer:new{
        width = W, height = H, padding = 0, margin = 0, bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = margin }, body },
    }
end

function Home:onGesture(ev)
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
