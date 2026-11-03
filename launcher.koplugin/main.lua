--[[--
Home screen launcher for KOReader.

Shows a launcher (clock, weather, panchang, now playing, continue reading,
recent books, app tiles) on top of the file browser whenever KOReader is at
its "home": on start and after closing a book.

Config: settings/launcher.lua (lat, lon, place, panchang, panchang_lang, as_home).
--]]--
local Dispatcher = require("dispatcher")
local Home = require("home")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local Weather = require("weather")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local Launcher = WidgetContainer:extend{
    name = "launcher",
    is_doc_only = false,
}

local current = nil

function Launcher:onDispatcherRegisterActions()
    Dispatcher:registerAction("launcher_show", {
        category = "none", event = "ShowLauncher", title = _("Home screen"), general = true,
    })
end

function Launcher:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    -- in the file browser (not in a book): show the home screen
    if not self.ui.document and not Home.config():isFalse("as_home") then
        UIManager:nextTick(function() self:onShowLauncher() end)
    end
end

function Launcher:onShowLauncher()
    -- the home screen needs the file browser underneath (for its actions)
    if self.ui.document then
        self.ui:handleEvent(require("ui/event"):new("Home"))
        return true
    end
    if current then UIManager:close(current) end
    local ok, home = pcall(Home.new, Home, { ui = self.ui })
    if not ok then
        logger.err("launcher: cannot build home screen:", home)
        UIManager:show(InfoMessage:new{ text = "Home screen failed to load:\n" .. tostring(home) })
        return true
    end
    local orig = home.onCloseWidget
    home.onCloseWidget = function(w)
        if current == w then current = nil end
        return orig(w)
    end
    current = home
    UIManager:show(home, "full")
    return true
end

function Launcher:editLocation()
    local cfg = Home.config()
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Weather location"),
        fields = {
            { text = tostring(cfg:readSetting("lat") or ""), hint = _("Latitude, e.g. 51.51") },
            { text = tostring(cfg:readSetting("lon") or ""), hint = _("Longitude, e.g. -0.13") },
            { text = cfg:readSetting("place") or "", hint = _("Place name (shown on screen)") },
        },
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local f = dialog:getFields()
                local lat, lon = tonumber(f[1]), tonumber(f[2])
                if not lat or not lon then
                    UIManager:show(InfoMessage:new{ text = _("Enter latitude and longitude as numbers.") })
                    return
                end
                cfg:saveSetting("lat", lat); cfg:saveSetting("lon", lon); cfg:saveSetting("place", f[3])
                cfg:flush()
                Weather.data = nil
                UIManager:close(dialog)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Launcher:addToMainMenu(menu_items)
    local function toggle(key, default_on)
        return {
            checked_func = function()
                local c = Home.config()
                if default_on then return not c:isFalse(key) end
                return c:isTrue(key)
            end,
            callback = function()
                local c = Home.config()
                local on = default_on and not c:isFalse(key) or (not default_on and c:isTrue(key))
                c:saveSetting(key, not on); c:flush()
            end,
        }
    end
    local home_item = toggle("as_home", true)
    home_item.text = _("Show home screen at start and after closing a book")
    local pan_item = toggle("panchang", true)
    pan_item.text = _("Show panchang")
    menu_items.launcher = {
        text = _("Home screen"),
        sorting_hint = "tools",
        sub_item_table = {
            { text = _("Open home screen"), callback = function() self:onShowLauncher() end },
            home_item,
            { text = _("Weather location"), keep_menu_open = true, callback = function() self:editLocation() end },
            pan_item,
            {
                text_func = function()
                    return _("Panchang language: ") .. ((Home.config():readSetting("panchang_lang") or "te") == "te" and "తెలుగు" or "English")
                end,
                keep_menu_open = true,
                callback = function(touchmenu)
                    local c = Home.config()
                    c:saveSetting("panchang_lang", (c:readSetting("panchang_lang") or "te") == "te" and "en" or "te")
                    c:flush()
                    if touchmenu then touchmenu:updateItems() end
                end,
            },
        },
    }
end

return Launcher
