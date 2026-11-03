--[[--
The app catalogue: every KOReader feature worth launching, grouped.

Each app is { id, icon, label, run = function(home) ..., needs = plugin name }.
Apps whose plugin isn't loaded are hidden. Plugins that only have a menu are
opened as a full-screen list built from their own main-menu entries.
--]]--
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Apps = {}

local function ev(name)
    return function(home) home:send(name) end
end

-- Open a plugin's main-menu entry as a list (recursing into sub-menus).
local dummy_touchmenu = { updateItems = function() end, closeMenu = function() end, item_table = {} }

local function itemText(it)
    local t = it.text
    if it.text_func then
        local ok, r = pcall(it.text_func, dummy_touchmenu); if ok then t = r end
    end
    return t
end

function Apps.showMenuItems(title, items)
    local list = {}
    for _, it in ipairs(items or {}) do
        local text = itemText(it)
        local enabled = true
        if it.enabled_func then
            local ok, r = pcall(it.enabled_func); enabled = not ok or r
        elseif it.enabled == false then
            enabled = false
        end
        if text and text ~= "" and enabled then
            local entry = { text = text }
            if it.checked_func then
                local ok, r = pcall(it.checked_func)
                if ok and r then entry.mandatory = "\u{F00C}" end
            end
            if it.sub_item_table or it.sub_item_table_func then
                entry.mandatory = entry.mandatory or "\u{F054}"
                entry.callback = function()
                    local sub = it.sub_item_table
                    if it.sub_item_table_func then
                        local ok, r = pcall(it.sub_item_table_func); if ok then sub = r end
                    end
                    Apps.showMenuItems(text, sub)
                end
            elseif it.callback then
                entry.callback = function()
                    local ok, err = pcall(it.callback, dummy_touchmenu)
                    if not ok then UIManager:show(InfoMessage:new{ text = tostring(err) }) end
                end
            end
            if entry.callback then table.insert(list, entry) end
        end
    end
    if #list == 0 then
        UIManager:show(InfoMessage:new{ text = _("Nothing to show here."), timeout = 2 })
        return
    end
    local menu
    menu = Menu:new{
        title = title, item_table = list,
        covers_fullscreen = true, is_borderless = true, is_popout = false,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

local function pluginMenu(name, title)
    return function(home)
        local p = home.ui and home.ui[name]
        if not p or not p.addToMainMenu then
            UIManager:show(InfoMessage:new{ text = title .. _(" is not available."), timeout = 2 })
            return
        end
        local items = {}
        pcall(p.addToMainMenu, p, items)
        local _k, entry = next(items)
        if not entry then return end
        local sub = entry.sub_item_table
        if entry.sub_item_table_func then
            local ok, r = pcall(entry.sub_item_table_func, p); if ok then sub = r end
        end
        if sub then
            Apps.showMenuItems(title, sub)
        elseif entry.callback then
            entry.callback(dummy_touchmenu)
        end
    end
end

local I = {
    folder = "\u{F07B}", search = "\u{F002}", history = "\u{F1DA}", list = "\u{F03A}", heart = "\u{F004}",
    chart = "\u{F080}", calendar = "\u{F073}", cap = "\u{F19D}", language = "\u{F1AB}", wiki = "\u{F266}",
    globe = "\u{F0AC}", database = "\u{F1C0}", cloud = "\u{F0C2}", news = "\u{F1EA}", bookmark = "\u{F02E}",
    sync = "\u{F021}", music = "\u{F001}", headphones = "\u{F025}", pencil = "\u{F040}", terminal = "\u{F120}",
    hourglass = "\u{F254}", battery = "\u{F240}", chip = "\u{F2DB}", camera = "\u{F030}", sitemap = "\u{F0E8}",
    key = "\u{F084}", bulb = "\u{F0EB}", moon = "\u{F186}", wifi = "\u{F1EB}", cog = "\u{F013}", th = "\u{F00A}",
    power = "\u{F011}", redo = "\u{F01E}", signout = "\u{F08B}",
}
Apps.ICON = I

Apps.groups = {
    { title = _("Reading"), apps = {
        { id = "library", icon = I.folder, label = _("Library"), run = function(h) h:openLibrary() end },
        { id = "search", icon = I.search, label = _("Search"), run = ev("ShowFileSearch") },
        { id = "history", icon = I.history, label = _("History"), run = ev("ShowHist") },
        { id = "collections", icon = I.list, label = _("Collections"), run = ev("ShowCollList") },
        { id = "favorites", icon = I.heart, label = _("Favorites"), run = ev("ShowColl") },
        { id = "stats", icon = I.chart, label = _("Statistics"), run = ev("ShowCalendarView"), needs = "statistics" },
        { id = "today", icon = I.calendar, label = _("Today"), run = ev("ShowCalendarDayView"), needs = "statistics" },
        { id = "vocab", icon = I.cap, label = _("Vocabulary"), run = ev("ShowVocabBuilder"), needs = "vocabbuilder" },
        { id = "dictionary", icon = I.language, label = _("Dictionary"), run = ev("ShowDictionaryLookup") },
        { id = "wikipedia", icon = I.wiki, label = _("Wikipedia"), run = ev("ShowWikipediaLookup") },
    } },
    { title = _("Online"), apps = {
        { id = "opds", icon = I.globe, label = _("Kavita"), run = ev("ShowOPDSCatalog"), needs = "opds" },
        { id = "calibre", icon = I.database, label = _("Calibre"), run = pluginMenu("calibre", _("Calibre")), needs = "calibre" },
        { id = "cloud", icon = I.cloud, label = _("Cloud"), run = ev("ShowCloudStorageList"), needs = "cloudstorage" },
        { id = "news", icon = I.news, label = _("News"), run = pluginMenu("newsdownloader", _("News")), needs = "newsdownloader" },
        { id = "wallabag", icon = I.bookmark, label = _("Wallabag"), run = pluginMenu("wallabag", _("Wallabag")), needs = "wallabag" },
        { id = "kosync", icon = I.sync, label = _("Sync"), run = pluginMenu("kosync", _("Progress sync")), needs = "kosync" },
        { id = "music", icon = I.music, label = _("Music"), run = function(h) h:openMusic(false) end, needs = "nowplaying" },
        { id = "musiclib", icon = I.headphones, label = _("Library ♪"), run = function(h) h:openMusic(true) end, needs = "nowplaying" },
    } },
    { title = _("Tools"), apps = {
        { id = "editor", icon = I.pencil, label = _("Editor"), run = pluginMenu("texteditor", _("Text editor")), needs = "texteditor" },
        { id = "terminal", icon = I.terminal, label = _("Terminal"), run = ev("TerminalStart"), needs = "terminal" },
        { id = "timer", icon = I.hourglass, label = _("Timer"), run = pluginMenu("readtimer", _("Read timer")), needs = "readtimer" },
        { id = "battery", icon = I.battery, label = _("Battery"), run = ev("ShowBatteryStatistics"), needs = "batterystat" },
        { id = "system", icon = I.chip, label = _("System"), run = ev("ShowSysStatistics"), needs = "systemstat" },
        { id = "screenshot", icon = I.camera, label = _("Screenshot"), run = function(h)
            UIManager:scheduleIn(0.5, function() h:send("Screenshot") end)
        end },
        { id = "network", icon = I.sitemap, label = _("Network"), run = ev("ShowNetworkInfo") },
        { id = "ssh", icon = I.key, label = _("SSH"), run = pluginMenu("SSH", _("SSH server")), needs = "SSH" },
    } },
    { title = _("Device"), apps = {
        { id = "light", icon = I.bulb, label = _("Light"), run = ev("ShowFlDialog") },
        { id = "night", icon = I.moon, label = _("Night"), run = function(h)
            h:send("ToggleNightMode")
            UIManager:nextTick(function() h:refresh("full") end)
        end },
        { id = "wifi", icon = I.wifi, label = _("Wi-Fi"), run = ev("ToggleWifi") },
        { id = "settings", icon = I.cog, label = _("Settings"), run = ev("ShowMenu") },
        { id = "homesettings", icon = I.th, label = _("Home"), run = pluginMenu("launcher", _("Home screen")), needs = "launcher" },
        { id = "sleep", icon = I.power, label = _("Sleep"), run = function() UIManager:suspend() end },
        { id = "restart", icon = I.redo, label = _("Restart"), run = function()
            if UIManager.restartKOReader then UIManager:restartKOReader()
            else UIManager:broadcastEvent(Event:new("Restart")) end
        end },
        { id = "exit", icon = I.signout, label = _("Kobo"), run = function() UIManager:broadcastEvent(Event:new("Exit")) end },
    } },
}

-- apps available on this device (plugin present)
function Apps.available(ui)
    local out = {}
    for _, g in ipairs(Apps.groups) do
        local apps = {}
        for _, a in ipairs(g.apps) do
            if not a.needs or (ui and ui[a.needs]) then table.insert(apps, a) end
        end
        if #apps > 0 then table.insert(out, { title = g.title, apps = apps }) end
    end
    return out
end

function Apps.byId(ui, id)
    for _, g in ipairs(Apps.available(ui)) do
        for _, a in ipairs(g.apps) do if a.id == id then return a end end
    end
end

Apps.DEFAULT_DOCK = { "library", "music", "opds", "settings" }

return Apps
