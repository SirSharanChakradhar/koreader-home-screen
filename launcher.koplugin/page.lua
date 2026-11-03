--[[--
A simple full-screen page for the mini apps: a title bar with a close (×)
button, then rows or custom content. Taps are hit-tested by us (no Buttons).

    Page:new{ title = "Weather", rows = { { left = "Mon", right = "31° / 19°", sub = "Rain 40%" }, ... } }
    Page:new{ title = "...", content_func = function(page, w, h) return widget, register(x, y) end }
--]]--
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local GRAY = Blitbuffer.COLOR_DARK_GRAY

local Page = InputContainer:extend{
    name = "launcher_page",
    covers_fullscreen = true,
    title = "",
    rows = nil,           -- list of { left, right, sub, face, bold, callback }
    content_func = nil,   -- function(page, width, height) -> widget, register(x, y)
    on_swipe = nil,       -- function(page, direction)
    on_close = nil,
}

Page.GRAY = GRAY

function Page.text(str, size, opts)
    opts = opts or {}
    return TextWidget:new{ text = str or "", face = opts.face or Font:getFace(opts.font or "cfont", size),
        bold = opts.bold, fgcolor = opts.color or Blitbuffer.COLOR_BLACK, max_width = opts.max_width }
end

function Page.box(str, size, width, opts)
    opts = opts or {}
    return TextBoxWidget:new{ text = (str and str ~= "") and str or " ",
        face = opts.face or Font:getFace(opts.font or "cfont", size), width = width,
        alignment = opts.align or "left", bold = opts.bold, fgcolor = opts.color or Blitbuffer.COLOR_BLACK,
        height = opts.height, height_overflow_show_ellipsis = opts.height and true or nil }
end

-- a rounded cell with centered content, for keypads and buttons
function Page.cell(content, w, h, opts)
    opts = opts or {}
    return FrameContainer:new{
        width = w, height = h, padding = 0, margin = 0,
        bordersize = opts.border or Screen:scaleBySize(1), radius = Screen:scaleBySize(12),
        color = opts.border_color or Blitbuffer.COLOR_LIGHT_GRAY,
        background = opts.background or Blitbuffer.COLOR_WHITE,
        CenterContainer:new{ dimen = Geom:new{ w = w - 2, h = h - 2 }, content },
    }
end

function Page:init()
    self.W, self.H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.W, h = self.H }
    self:build()
end

function Page:addHit(x, y, w, h, fn)
    table.insert(self.hit, { x = x, y = y, w = w, h = h, fn = fn })
end

function Page:refresh(mode)
    self:build()
    UIManager:setDirty(self, mode or "ui")
end

function Page:close()
    UIManager:close(self, "full")
end

function Page:onCloseWidget()
    if self.on_close then pcall(self.on_close, self) end
end

function Page:build()
    local W, H = self.W, self.H
    local margin = Screen:scaleBySize(30)
    local inner = W - 2 * margin
    self.hit = {}
    local body = VerticalGroup:new{ align = "left" }
    local y = 0
    local function put(w) table.insert(body, w); y = y + w:getSize().h end

    -- title bar
    local bar_h = Screen:scaleBySize(64)
    local close = Page.text("\u{F00D}", 26)
    local title = Page.text(self.title, 28, { bold = true, face = self.title_face,
        max_width = inner - close:getSize().w - Screen:scaleBySize(20) })
    put(VerticalSpan:new{ width = Screen:scaleBySize(8) })
    put(CenterContainer:new{ dimen = Geom:new{ w = inner, h = bar_h },
        HorizontalGroup:new{ align = "center", title,
            HorizontalSpan:new{ width = inner - title:getSize().w - close:getSize().w }, close } })
    self:addHit(margin + inner - Screen:scaleBySize(90), 0, Screen:scaleBySize(90) + margin, bar_h + Screen:scaleBySize(8),
        function() self:close() end)
    put(LineWidget:new{ dimen = Geom:new{ w = inner, h = Screen:scaleBySize(1) }, background = Blitbuffer.COLOR_LIGHT_GRAY })
    put(VerticalSpan:new{ width = Screen:scaleBySize(10) })

    if self.content_func then
        local w, reg = self.content_func(self, inner, H - y - Screen:scaleBySize(20))
        if reg then reg(margin, y) end
        put(w)
    elseif self.rows then
        for _, r in ipairs(self.rows) do
            local row_y = y
            if r.heading then
                put(VerticalSpan:new{ width = Screen:scaleBySize(10) })
                put(Page.text(r.heading_face and r.heading or r.heading:upper(), 15, { color = GRAY, face = r.heading_face }))
                put(VerticalSpan:new{ width = Screen:scaleBySize(6) })
            else
                local left = Page.box(r.left, r.size or 22, math.floor(inner * 0.55),
                    { bold = r.bold, face = r.face })
                local right = Page.box(r.right or "", r.size or 22, inner - math.floor(inner * 0.55),
                    { align = "right", bold = r.bold_right, face = r.face_right or r.face })
                put(HorizontalGroup:new{ align = "top", left, right })
                if r.sub then
                    put(Page.box(r.sub, 17, inner, { color = GRAY, face = r.sub_face }))
                end
                put(VerticalSpan:new{ width = Screen:scaleBySize(10) })
                if r.callback then
                    self:addHit(margin, row_y, inner, y - row_y, r.callback)
                end
            end
            if y > H - Screen:scaleBySize(40) then break end
        end
    end

    self[1] = FrameContainer:new{
        width = W, height = H, padding = 0, margin = 0, bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = margin }, body },
    }
end

function Page:onGesture(ev)
    if ev.ges == "swipe" then
        if self.on_swipe then self.on_swipe(self, ev.direction) end
        return true
    end
    if ev.ges ~= "tap" then return InputContainer.onGesture(self, ev) end
    for _, h in ipairs(self.hit) do
        if ev.pos.x >= h.x and ev.pos.x < h.x + h.w and ev.pos.y >= h.y and ev.pos.y < h.y + h.h then
            UIManager:nextTick(h.fn)
            return true
        end
    end
    return true
end

return Page
