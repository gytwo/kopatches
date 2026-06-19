-- 2-quickactions.lua - Quick Actions Panel for KOReader
-- QA standalone patch: integrated menu recording, system actions (5 action types), custom button icons, KOReader system icon replacement, KOReader system UI font replacement
-- Installation: place in koreader/patches/ directory
-- Uninstallation: delete this file, and optionally delete koreader/settings/quickactions.lua (configuration file)

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local BD = require("ui/bidi")
local _ = require("gettext")
local datetime = require("datetime")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Dispatcher = require("dispatcher")

local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputText = require("ui/widget/inputtext")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Menu = require("ui/widget/menu")
local PathChooser = require("ui/widget/pathchooser")
local Size = require("ui/size")
local SortWidget = require("ui/widget/sortwidget")
local SpinWidget = require("ui/widget/spinwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Math = require("optmath")
local Notification = require("ui/widget/notification")
local ffiUtil = require("ffi/util")
local util = require("util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local Event = require("ui/event")
local IconWidget = require("ui/widget/iconwidget")
local FontList = require("fontlist")

logger.info("[QuickActions] Loading...")

-- ============================================================
-- Global variable declarations
-- ============================================================

local openDispatcherPicker = nil
local _settings_dialog = nil
local sub_dialog = nil
local CONFIG_PATH = nil
local CONFIG_DATA = nil
local DEFAULT_CONFIG = nil
local MAX_SLOTS = 66

-- ============================================================
-- ButtonDialog global patch
-- ============================================================

local _orig_ButtonDialog_new = ButtonDialog.new
function ButtonDialog.new(_, ...)
    local args = ... or {}
    if type(args) == "table" and args.rows_per_page == nil then
        args.rows_per_page = 10
    end
    return _orig_ButtonDialog_new(_, args)
end

-- ============================================================
-- Default configuration
-- ============================================================

DEFAULT_CONFIG = {
    qa_tab_icon = "star.empty",
    qa_enabled = true,
    qa_slots = { "wifi", "night", "rotate", "screenshot", "continue", "fontlist", "restart", "search","qa_settings","qa_add_button","qa_new"},
    qa_frontlight = true,
    qa_warmth = true,
    qa_shape = "round",
    qa_bg = "flat",
    qa_labels = false,
    qa_label_scale_pct = 90,
    qa_settings_on_hold = true,
    qa_button_size_pct = 100,
    custom_list = {},
    custom = {},
    builtin_overrides = {},
    qa_context_filter = true,
    qa_auto_add_to_panel = true,
    qa_button_hold_edit = true,
    qa_slider_show_value = false,
    qa_filter_initialized = false,
    qa_icon_overrides = {},
    ui_font_overrides = {},
    version = 1,
}

-- ============================================================
-- Standalone storage (global functions)
-- ============================================================

local function getConfigPath()
    if CONFIG_PATH then return CONFIG_PATH end
    local ok, DataStorage = pcall(require, "datastorage")
    if ok and DataStorage then
        CONFIG_PATH = DataStorage:getSettingsDir() .. "/quickactions.lua"
    else
        CONFIG_PATH = "quickactions.lua"
    end
    return CONFIG_PATH
end

local function serializeTable(t, indent)
    indent = indent or ""
    local lines = {}
    lines[#lines+1] = "{\n"
    
    local keys = {}
    for k in pairs(t) do
        table.insert(keys, k)
    end
    table.sort(keys)
    
    for i, k in ipairs(keys) do
        local v = t[k]
        local key_str
        if type(k) == "string" then
            key_str = string.format('["%s"]', k)
        else
            key_str = string.format('[%s]', tostring(k))
        end
        
        if type(v) == "table" then
            lines[#lines+1] = string.format('%s  %s = %s,', indent, key_str, serializeTable(v, indent .. "  "))
        elseif type(v) == "string" then
            local escaped = v:gsub('"', '\\"'):gsub("\n", "\\n")
            lines[#lines+1] = string.format('%s  %s = "%s",', indent, key_str, escaped)
        elseif type(v) == "number" then
            lines[#lines+1] = string.format('%s  %s = %s,', indent, key_str, tostring(v))
        elseif type(v) == "boolean" then
            lines[#lines+1] = string.format('%s  %s = %s,', indent, key_str, v and "true" or "false")
        end
    end
    
    lines[#lines+1] = indent .. "}"
    return table.concat(lines, "\n")
end

local function saveConfig()
    if not CONFIG_DATA then return end
    local f = io.open(CONFIG_PATH, "w")
    if f then
        f:write("return " .. serializeTable(CONFIG_DATA))
        f:close()
    end
end

local function loadConfig()
    if CONFIG_DATA then return CONFIG_DATA end
    local path = getConfigPath()
    local f = io.open(path, "r")
    if f then
        local content = f:read("*all")
        f:close()
        if content and content ~= "" then
            content = content:gsub("^\239\187\191", "")
            local chunk, err = load(content)
            if chunk then
                local ok, data = pcall(chunk)
                if ok and type(data) == "table" then
                    CONFIG_DATA = data
                    logger.info("[QuickActions] Configuration loaded successfully")
                    return CONFIG_DATA
                else
                    logger.warn("[QuickActions] pcall failed:", err)
                end
            else
                logger.warn("[QuickActions] load failed:", err)
            end
        end
        logger.warn("[QuickActions] Configuration file corrupted, overwriting with default")
        CONFIG_DATA = DEFAULT_CONFIG
        saveConfig()
        return CONFIG_DATA
    end
    
    logger.info("[QuickActions] Configuration file does not exist, creating default")
    CONFIG_DATA = DEFAULT_CONFIG
    saveConfig()
    return CONFIG_DATA
end

-- ============================================================
-- Configuration access functions (global)
-- ============================================================

local function getSetting(key)
    local cfg = loadConfig()
    local val = cfg[key]
    if val ~= nil then return val end
    return DEFAULT_CONFIG[key]
end

local function setSetting(key, value)
    local cfg = loadConfig()
    cfg[key] = value
    saveConfig()
end

local function getBool(key)
    local val = getSetting(key)
    if type(val) == "boolean" then return val end
    return DEFAULT_CONFIG[key] == true
end

local function setBool(key, value)
    setSetting(key, value == true)
end

local function getString(key)
    local val = getSetting(key)
    if type(val) == "string" then return val end
    return DEFAULT_CONFIG[key] or ""
end

local function setString(key, value)
    setSetting(key, value)
end

local function getNumber(key)
    local val = getSetting(key)
    if type(val) == "number" then return val end
    return DEFAULT_CONFIG[key] or 0
end

local function setNumber(key, value)
    setSetting(key, value)
end

local function getTable(key)
    local cfg = loadConfig()
    local val = cfg[key]
    if type(val) == "table" then return val end
    return DEFAULT_CONFIG[key] or {}
end

local function setTable(key, value)
    local cfg = loadConfig()
    local json = require("json")
    local value_copy = json.decode(json.encode(value))
    cfg[key] = value_copy
    saveConfig()
end

-- ============================================================
-- Dialog management functions (global)
-- ============================================================

local function closeSettingsDialog()
    if _settings_dialog then
        UIManager:close(_settings_dialog)
        _settings_dialog = nil
    end
end

local function refreshQuickPanel(touch_menu)
    if touch_menu and touch_menu.updateItems then
        touch_menu:updateItems()
    end
end

-- ============================================================
-- Convenience configuration access functions (global)
-- ============================================================

local function isQAEnabled()
    return getBool("qa_enabled")
end

local function getQASlots()
    local slots = getSetting("qa_slots")
    if type(slots) == "table" then return slots end
    return DEFAULT_CONFIG.qa_slots
end

local function saveQASlots(slots)
    setSetting("qa_slots", slots)
end

local function showFrontlight()
    return getBool("qa_frontlight")
end

local function showWarmth()
    return getBool("qa_warmth")
end

local function showSliderValue()
    return getBool("qa_slider_show_value")
end

local function getShape()
    return getString("qa_shape")
end

local function getBg()
    return getString("qa_bg")
end

local function showLabels()
    return getBool("qa_labels")
end

local function getLabelScalePct()
    local n = getNumber("qa_label_scale_pct")
    return math.max(50, math.min(200, math.floor(n)))
end

local function getLabelScale()
    return getLabelScalePct() / 100
end

local function buttonHoldEdit()
    return getBool("qa_button_hold_edit")
end

local function settingsOnHold()
    return getBool("qa_settings_on_hold")
end

local function getButtonSizePct()
    local n = getNumber("qa_button_size_pct")
    return math.max(60, math.min(150, math.floor(n)))
end

-- ============================================================
-- UI font switching functionality (three font types, automatically replaces all corresponding keys)
-- ============================================================

-- Declare functions first to resolve circular references
local showFontPickerForUIKey
local showUIFontSwitcher

-- Track dialogs
local _font_picker_dialog = nil
local _font_main_dialog = nil

-- Get all available fonts
local function getAvailableFonts()
    local fonts = FontList:getFontList()
    local result = {}
    for idx, path in ipairs(fonts) do
        local fname, name = util.splitFilePathName(path)
        if name then
            if name:match("%.ttf$") or name:match("%.otf$") then
                local display = name:gsub("%.ttf$", ""):gsub("%.otf$", ""):gsub("_", " ")
                result[#result + 1] = {
                    name = name,
                    display = display,
                }
            end
        end
    end
    table.sort(result, function(a, b) return a.display:lower() < b.display:lower() end)
    return result
end

-- UI font configuration list (three font types)
local UI_FONT_ITEMS = {
    { key = "regular", label = _("Regular font"), default = "NotoSans-Regular.ttf" },
    { key = "bold", label = _("Bold font"), default = "NotoSans-Bold.ttf" },
    { key = "mono", label = _("Monospace font"), default = "DroidSansMono.ttf" },
}

-- Font type to fontmap key mapping
local FONT_TYPE_MAP = {
    regular = {"cfont", "ffont", "smallffont", "largeffont", "rifont", "pgfont", "hfont", "infofont", "smallinfofont", "x_smallinfofont", "xx_smallinfofont"},
    bold = {"tfont", "smalltfont", "x_smalltfont", "smallinfofontbold"},
    mono = {"scfont", "hpkfont", "infont", "smallinfont"},
}

-- Get current font
local function getCurrentUIFont(key)
    local Font = require("ui/font")
    return Font.fontmap[key] or ""
end

-- Get user font override
local function getUIFontOverride(key)
    local overrides = getTable("ui_font_overrides") or {}
    return overrides[key]
end

-- Apply font changes
local function applyUIFontChanges()
    local Font = require("ui/font")
    
    local overrides = getTable("ui_font_overrides") or {}
    
    local font_exists = {}
    local fonts = FontList:getFontList()
    for idx, path in ipairs(fonts) do
        local fname, name = util.splitFilePathName(path)
        if name then
            font_exists[name] = true
        end
    end
    
    local regular_font = overrides.regular or "NotoSans-Regular.ttf"
    local bold_font = overrides.bold or "NotoSans-Bold.ttf"
    local mono_font = overrides.mono or "DroidSansMono.ttf"
    
    if font_exists[regular_font] then
        for _, k in ipairs(FONT_TYPE_MAP.regular) do
            Font.fontmap[k] = regular_font
        end
    end
    
    if font_exists[bold_font] then
        for _, k in ipairs(FONT_TYPE_MAP.bold) do
            Font.fontmap[k] = bold_font
        end
    end
    
    if font_exists[mono_font] then
        for _, k in ipairs(FONT_TYPE_MAP.mono) do
            Font.fontmap[k] = mono_font
        end
    end
    
    Font.faces = {}
    
    -- Refresh loaded Widget classes
    local ok, Button = pcall(require, "ui/widget/button")
    if ok and Button then
        Button.text_font_face = regular_font
    end
    
    local ok, TouchMenu = pcall(require, "ui/widget/touchmenu")
    if ok and TouchMenu and TouchMenu.fface then
        local orig_size = TouchMenu.fface.orig_size or 24
        TouchMenu.fface = Font:getFace("cfont", orig_size)
    end
    
    local ok, ConfirmBox = pcall(require, "ui/widget/confirmbox")
    if ok and ConfirmBox and ConfirmBox.face then
        local orig_size = ConfirmBox.face.orig_size or 22
        ConfirmBox.face = Font:getFace("cfont", orig_size)
    end
    
    local ok, InfoMessage = pcall(require, "ui/widget/infomessage")
    if ok and InfoMessage then
        local def_face = Font:getFace("infofont")
        local orig_size = def_face.orig_size or 22
        InfoMessage.face = Font:getFace("infofont", orig_size)
    end
    
    -- Notification
    local ok, Notification = pcall(require, "ui/widget/notification")
    if ok and Notification then
        local orig_size = Notification.face.orig_size or 18
        Notification.face = Font:getFace("x_smallinfofont", orig_size)
    end
    
    local ok, ButtonDialog = pcall(require, "ui/widget/buttondialog")
    if ok and ButtonDialog then
        if ButtonDialog.title_face then
            local orig_size = ButtonDialog.title_face.orig_size or 20
            ButtonDialog.title_face = Font:getFace("tfont", orig_size)
        end
        if ButtonDialog.info_face then
            local orig_size = ButtonDialog.info_face.orig_size or 22
            ButtonDialog.info_face = Font:getFace("infofont", orig_size)
        end
    end
    
    local ok, InputDialog = pcall(require, "ui/widget/inputdialog")
    if ok and InputDialog and InputDialog.input_face then
        local orig_size = InputDialog.input_face.orig_size or 16
        InputDialog.input_face = Font:getFace("infont", orig_size)
    end
    
    local ok, MultiInputDialog = pcall(require, "ui/widget/multiinputdialog")
    if ok and MultiInputDialog then
        if MultiInputDialog.title_face then
            local orig_size = MultiInputDialog.title_face.orig_size or 20
            MultiInputDialog.title_face = Font:getFace("tfont", orig_size)
        end
        if MultiInputDialog.info_face then
            local orig_size = MultiInputDialog.info_face.orig_size or 22
            MultiInputDialog.info_face = Font:getFace("infofont", orig_size)
        end
    end
    
    -- Refresh Menu and TouchMenu item rendering
    local ok, Menu = pcall(require, "ui/widget/menu")
    if ok and Menu and Menu.updateItems then
        local orig_update = Menu.updateItems
        Menu.updateItems = function(self, ...)
            if not self._font_patched then
                for i = 1, #self.item_group do
                    local widget = self.item_group[i]
                    if widget and widget.face then
                        local cls = getmetatable(widget)
                        if cls then
                            cls.font = regular_font
                            cls.infont = regular_font
                        end
                    end
                end
                self._font_patched = true
            end
            return orig_update(self, ...)
        end
    end
    
    local ok, TouchMenu2 = pcall(require, "ui/widget/touchmenu")
    if ok and TouchMenu2 and TouchMenu2.updateItems then
        local orig_update = TouchMenu2.updateItems
        TouchMenu2.updateItems = function(self, ...)
            if not self._font_patched then
                for i = 1, #self.item_group do
                    local widget = self.item_group[i]
                    if widget and widget.face then
                        local cls = getmetatable(widget)
                        if cls then
                            cls.font = regular_font
                            cls.infont = regular_font
                        end
                    end
                end
                self._font_patched = true
            end
            return orig_update(self, ...)
        end
    end
end

-- Set UI font override
local function setUIFontOverride(key, font_name)
    local overrides = getTable("ui_font_overrides") or {}
    if font_name then
        overrides[key] = font_name
    else
        overrides[key] = nil
    end
    setTable("ui_font_overrides", overrides)
    applyUIFontChanges()
    UIManager:setDirty("all", "full")
end

-- Reset all UI fonts
local function resetAllUIFonts()
    setTable("ui_font_overrides", {})
    UIManager:show(Notification:new{
        text = _("All UI fonts reset, restart required"),
        timeout = 2,
    })
    UIManager:show(ConfirmBox:new{
        text = _("Restart required. Restart now?"),
        ok_text = _("Restart"),
        cancel_text = _("Later"),
        ok_callback = function()
            UIManager:restartKOReader()
        end,
    })
end

-- Font picker
function showFontPickerForUIKey(ui_key, ui_label, on_select, on_cancel)
    if _font_picker_dialog then
        UIManager:close(_font_picker_dialog)
        _font_picker_dialog = nil
    end
    
    local all_fonts = getAvailableFonts()
    local current = getUIFontOverride(ui_key) or ""
    
    local buttons = {}
    
    table.insert(buttons, {{
        text = _("Apply default"),
        callback = function()
            if _font_picker_dialog then
                UIManager:close(_font_picker_dialog)
                _font_picker_dialog = nil
            end
            if on_select then on_select(nil) end
        end,
    }})
    table.insert(buttons, {{
        text = _("Back"),
        callback = function()
            if _font_picker_dialog then
                UIManager:close(_font_picker_dialog)
                _font_picker_dialog = nil
            end
            if on_cancel then on_cancel() end
        end,
    }})
    table.insert(buttons, {})
    
    if #all_fonts == 0 then
        table.insert(buttons, {{
            text = _("No font files available"),
            enabled = false,
        }})
        local dialog = ButtonDialog:new{
            title = string.format(_("Select %s font"), ui_label),
            title_align = "center",
            buttons = buttons,
            width = math.floor(Screen:getWidth() * 0.7),
        }
        _font_picker_dialog = dialog
        UIManager:show(dialog)
        return
    end
    
    for i, font in ipairs(all_fonts) do
        local is_current = (font.name == current)
        table.insert(buttons, {{
            text = (is_current and "✓ " or "  ") .. font.display,
            callback = function()
                if _font_picker_dialog then
                    UIManager:close(_font_picker_dialog)
                    _font_picker_dialog = nil
                end
                if on_select then on_select(font.name) end
            end,
        }})
    end
    
    local dialog = ButtonDialog:new{
        title = string.format(_("Select %s font"), ui_label),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    _font_picker_dialog = dialog
    UIManager:show(dialog)
end

-- Show UI font switcher main interface
function showUIFontSwitcher()
    if _font_main_dialog then
        UIManager:close(_font_main_dialog)
        _font_main_dialog = nil
    end
    if _font_picker_dialog then
        UIManager:close(_font_picker_dialog)
        _font_picker_dialog = nil
    end
    
    local buttons = {}
    
    local overrides = getTable("ui_font_overrides") or {}
    local replaced_count = 0
    for i, item in ipairs(UI_FONT_ITEMS) do
        if overrides[item.key] then
            replaced_count = replaced_count + 1
        end
    end
    local total_count = #UI_FONT_ITEMS
    
    table.insert(buttons, {{
        text = string.format(_("Reset all (%d/%d)"), replaced_count, total_count),
        callback = function()
            if _font_main_dialog then
                UIManager:close(_font_main_dialog)
                _font_main_dialog = nil
            end
            resetAllUIFonts()
        end,
    }})
    table.insert(buttons, {})
    
    for i, item in ipairs(UI_FONT_ITEMS) do
        local override = overrides[item.key]
        local display_name = override or item.default
        local display = display_name:gsub("%.ttf$", ""):gsub("%.otf$", ""):gsub("_", " ")
        
        local text = item.label .. ": " .. display
        if override then
            local default_display = item.default:gsub("%.ttf$", ""):gsub("%.otf$", ""):gsub("_", " ")
            text = item.label .. ": " .. default_display .. " → " .. display
        end
        
        table.insert(buttons, {{
            text = text,
            callback = function()
                if _font_main_dialog then
                    UIManager:close(_font_main_dialog)
                    _font_main_dialog = nil
                end
                showFontPickerForUIKey(
                    item.key, 
                    item.label,
                    function(new_font)
                        if new_font then
                            setUIFontOverride(item.key, new_font)
                            UIManager:show(Notification:new{
                                text = string.format(_("%s set to %s"), item.label, new_font),
                                timeout = 2,
                            })
                        else
                            setUIFontOverride(item.key, nil)
                            UIManager:show(Notification:new{
                                text = string.format(_("%s reset to default"), item.label),
                                timeout = 2,
                            })
                        end
                        showUIFontSwitcher()
                    end,
                    function()
                        showUIFontSwitcher()
                    end
                )
            end,
        }})
    end
    
    local dialog = ButtonDialog:new{
        title = _("UI Font Switcher"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    _font_main_dialog = dialog
    UIManager:show(dialog)
end

-- Execute once on file load
applyUIFontChanges()

-- ============================================================
-- Nerd Font support (global functions)
-- ============================================================

function nerdIconChar(icon_value)
    if type(icon_value) ~= "string" then return nil end
    local hex = icon_value:match("^nerd:([0-9A-Fa-f]+)$")
    if not hex then return nil end
    local cp = tonumber(hex, 16)
    if not cp or cp < 0 or cp > 0x10FFFF then return nil end
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor((cp % 0x1000) / 0x40), 0x80 + (cp % 0x40))
    else
        return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor((cp % 0x40000) / 0x1000), 
                         0x80 + math.floor((cp % 0x1000) / 0x40), 0x80 + (cp % 0x40))
    end
end

local function isNerdIcon(icon_value)
    return nerdIconChar(icon_value) ~= nil
end

-- ============================================================
-- Icon directory (global functions)
-- ============================================================

local function getIconsDir()
    local ok, DataStorage = pcall(require, "datastorage")
    if ok and DataStorage then
        return DataStorage:getDataDir() .. "/icons"
    end
    return "./icons"
end

local function getIconFile(icon_name)
    if not icon_name then return nil end
    if isNerdIcon(icon_name) then return icon_name end
    
    -- 1. If it's a full path, check directly
    if icon_name:sub(1,1) == "/" then
        if lfs.attributes(icon_name, "mode") == "file" then
            return icon_name
        end
    end
    
    -- 2. Get koreader root directory
    local ok, DataStorage = pcall(require, "datastorage")
    local base_dir = ""
    if ok and DataStorage then
        base_dir = DataStorage:getDataDir()
    end
    
    -- 3. Treat as relative path (relative to koreader/ directory)
    if base_dir ~= "" then
        local full_path = base_dir .. "/" .. icon_name
        full_path = full_path:gsub("/%.", ""):gsub("/+", "/")
        if lfs.attributes(full_path, "mode") == "file" then
            return full_path
        end
    end
    
    -- 4. Finally, strip all paths, keep only filename, search all icon directories (same as IconWidget)
    local filename = icon_name:match("([^/]+)$") or icon_name
    local dirs_to_check = {
        getIconsDir(),                      -- koreader/icons/
        "resources/icons/mdlight",
        "resources/icons",
        "resources",
    }
    for _, dir in ipairs(dirs_to_check) do
        local path = dir .. "/" .. filename
        if lfs.attributes(path, "mode") == "file" then
            return path
        end
    end
    
    return nil
end

local function getIconWidget(icon_path, size)
    size = size or Screen:scaleBySize(24)
    local is_nerd = isNerdIcon(icon_path)
    if is_nerd then
        local nerd_char = nerdIconChar(icon_path)
        if nerd_char then
            return TextWidget:new{
                text = nerd_char,
                face = Font:getFace("symbols", math.floor(size * 0.6)),
                fgcolor = Blitbuffer.COLOR_BLACK,
                padding = 0,
            }
        end
    end
    local file_path = getIconFile(icon_path)
    if file_path and lfs.attributes(file_path, "mode") == "file" then
        local iw = ImageWidget:new{
            file = file_path,
            width = size,
            height = size,
            alpha = true,
            is_icon = true, 
        }
        local ok_render = pcall(function() iw:_render() end)
        if ok_render then
            return iw
        else
            iw:free()
        end
    end
    return nil
end

-- ============================================================
-- Icon file browser
-- ============================================================

local THUMB_SIZE = Screen:scaleBySize(32)
local THUMB_GAP = Screen:scaleBySize(6)

local _InnerIconChooser = PathChooser:extend{
    select_directory = false,
    select_file = true,
    state_w = THUMB_SIZE + THUMB_GAP,
    path = getIconsDir(),
    onConfirm = nil,
    _filter_text = "",
    _all_items = nil,
    stop_events_propagation = true,
}

function _InnerIconChooser:init()
    self.title = _('Select icon')
    self.file_filter = function(filename)
        local ext = filename:lower()
        return ext:match('%.svg$') ~= nil or ext:match('%.png$') ~= nil
    end
    self.state_w = THUMB_SIZE + THUMB_GAP
    PathChooser.init(self)
    if not self._all_items then
        self:refreshPath()
    end
end

function _InnerIconChooser:getCollate()
    return self.collates.strcoll, "strcoll"
end

function _InnerIconChooser:refreshPath()
    local _, folder_name = util.splitFilePathName(self.path)
    Screen:setWindowTitle(folder_name)
    self._all_items = self:genItemTableFromPath(self.path)
    self:_applyCurrentFilter()
end

function _InnerIconChooser:_applyCurrentFilter()
    local filter_text = self._filter_text or ""
    local items
    if filter_text == "" then
        items = self._all_items
    else
        items = {}
        local pattern = filter_text:lower()
        for _, item in ipairs(self._all_items) do
            if item.is_go_up or (item.text and item.text:lower():find(pattern, 1, true)) then
                table.insert(items, item)
            end
        end
    end
    local itemmatch
    if self.focused_path then
        itemmatch = {path = self.focused_path}
        self.focused_path = nil
    end
    local subtitle = BD.directory(filemanagerutil.abbreviate(self.path))
    self:switchItemTable(nil, items, filter_text == "" and self.path_items[self.path] or 1, itemmatch, subtitle)
end

function _InnerIconChooser:applyFilter(text)
    self._filter_text = text or ""
    if self._all_items then
        self:_applyCurrentFilter()
    end
end

function _InnerIconChooser:_recalculateDimen(no_recalculate_dimen)
    Menu._recalculateDimen(self, no_recalculate_dimen)
    if not self.item_dimen then return end
    if self._filter_bar_height and self._filter_bar_height > 0 and not no_recalculate_dimen then
        self.available_height = self.available_height - self._filter_bar_height
        self.item_dimen.h = math.floor(self.available_height / self.perpage)
    end
    local content_w = math.max(0, self.item_dimen.w - 2 * Size.padding.fullscreen)
    local max_state_w = math.max(1, math.floor(content_w / 4))
    local ts = THUMB_SIZE
    local tg = THUMB_GAP
    self.state_w = math.min(ts + tg, max_state_w)
    self._thumb_size = math.max(0, math.min(ts, self.state_w - tg))
end

function _InnerIconChooser:updateItems(select_number, no_recalculate_dimen)
    Menu.updateItems(self, select_number, no_recalculate_dimen)
    self.path_items[self.path] = (self.page - 1) * self.perpage + (select_number or 1)
    local eff_thumb = self._thumb_size or 0
    if eff_thumb <= 0 then return end
    local item_h = self.item_dimen and self.item_dimen.h or eff_thumb
    local center_y = math.max(0, math.floor((item_h - eff_thumb) / 2))
    for _, item_widget in ipairs(self.item_group) do
        local entry = item_widget.entry
        if not entry then goto continue end
        local filepath = entry.path or ""
        local ext = filepath:lower()
        if not (ext:match("%.svg$") or ext:match("%.png$")) then goto continue end
        local uc = item_widget._underline_container
        if not uc then goto continue end
        local hg = uc[1]
        if not hg then goto continue end
        local og = hg[1]
        if not og then goto continue end
        table.insert(og, 1, ImageWidget:new{
            file = filepath,
            width = eff_thumb,
            height = eff_thumb,
            alpha = true,
            overlap_offset = { 0, center_y },
        })
        og._size = nil
        ::continue::
    end
end

function _InnerIconChooser:onMenuSelect(item)
    local path = item.path or ""
    local ext = path:lower()
    if ext:match("%.svg$") or ext:match("%.png$") then
        if self.show_parent then
            self.show_parent:onClose()
        end
        if self.onConfirm then
            self.onConfirm(path)
        end
        return true
    end
    return PathChooser.onMenuSelect(self, item)
end

function _InnerIconChooser:onMenuHold(item)
    local path = item.path or ""
    local ext = path:lower()
    if ext:match("%.svg$") or ext:match("%.png$") then
        return true
    end
    return PathChooser.onMenuHold(self, item)
end

local IconBrowser = WidgetContainer:extend{
    path = getIconsDir(),
    onConfirm = nil,
    is_always_active = true,
}

function IconBrowser:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    local paths_to_check = { self.path, "./resources/icons/mdlight", "./" }
    local final_path = nil
    for _, path in ipairs(paths_to_check) do
        if lfs.attributes(path, "mode") == "directory" then
            final_path = path
            logger.info("[QuickActions] Using icon directory:", final_path)
            break
        end
    end
    if not final_path then
        logger.warn("[QuickActions] No available directory found")
        UIManager:show(InfoMessage:new{
            text = _("Icon directory not found, cannot open icon browser"),
            timeout = 3,
        })
        return
    end
    self.path = final_path
    self._filter_input = InputText:new{
        text = "",
        hint = _("Filter by name…"),
        width = self.dimen.w - 4 * Size.padding.default,
        height = nil,
        face = Font:getFace("smallinfofont"),
        padding = Size.padding.small,
        margin = 0,
        bordersize = Size.border.inputtext,
        parent = self,
        scroll = false,
        focused = false,
        edit_callback = function()
            self:_applyFilter()
        end,
    }
    self._filter_input.addChars = function(inp, chars)
        if chars == "\n" then
            inp:onCloseKeyboard()
            return
        end
        InputText.addChars(inp, chars)
    end
    self._filter_bar = FrameContainer:new{
        padding = Size.padding.default,
        padding_top = Size.padding.small,
        padding_bottom = Size.padding.small,
        bordersize = 0,
        self._filter_input,
    }
    local filter_h = self._filter_bar:getSize().h
    self._chooser = _InnerIconChooser:new{
        show_parent = self,
        path = self.path,
        onConfirm = self.onConfirm,
        height = self.dimen.h,
        close_callback = function() self:onClose() end,
    }
    table.insert(self._chooser.content_group, 2, self._filter_bar)
    self._chooser._filter_bar_height = filter_h
    self._chooser:refreshPath()
    self[1] = self._chooser
end

function IconBrowser:_applyFilter()
    if not self._chooser then return end
    local text = self._filter_input and self._filter_input:getText() or ""
    self._chooser:applyFilter(text)
end

function IconBrowser:getFocusableWidgetXY()
    return nil, nil
end

function IconBrowser:onClose()
    if self._filter_input then
        self._filter_input:onCloseKeyboard()
    end
    UIManager:close(self)
end

local function showNerdIconPreview(sentinel, on_select, on_cancel)
    local hex = sentinel:match("nerd:(.+)")
    UIManager:show(ConfirmBox:new{
        text = ("U+%s  %s"):format(hex, nerdIconChar(sentinel)) .. "\n\n" .. _("Use this Nerd Font icon?"),
        ok_text = _("OK"),
        cancel_text = _("Back"),
        ok_callback = function() 
            if on_select then on_select(sentinel) end
        end,
        cancel_callback = function() 
            if on_cancel then on_cancel() end
        end,
    })
end

local function showNerdIconInput(current_icon, on_select, saved_icon)
    local current_hex = ""
    if current_icon then
        current_hex = current_icon:match("^nerd:([0-9A-Fa-f]+)$") or ""
    end
    local dlg
    local function openInputDlg()
        dlg = InputDialog:new{
            title = _("Nerd Font Icon"),
            input = current_hex:upper(),
            input_hint = _("Hexadecimal codepoint, e.g., E001"),
            description = _("Enter the Unicode codepoint (hexadecimal) for Nerd Fonts symbols.\nLeave empty and confirm to remove the Nerd Font icon."),
            buttons = {{
                {
                    text = _("Back"),
                    callback = function()
                        UIManager:close(dlg)
                        if on_select then on_select(saved_icon) end
                    end,
                },
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dlg)
                    end,
                },
                {
                    text = _("OK"),
                    is_enter_default = true,
                    callback = function()
                        local raw = dlg:getInputText()
                        if raw:match("^%s*$") then
                            UIManager:close(dlg)
                            if on_select then on_select(nil) end
                            return
                        end
                        local hex = raw:match("^%s*([0-9A-Fa-f]+)%s*$")
                        if hex and #hex >= 1 and #hex <= 6 then
                            local sentinel = "nerd:" .. hex:upper()
                            if nerdIconChar(sentinel) then
                                UIManager:close(dlg)
                                showNerdIconPreview(sentinel, on_select, function()
                                    UIManager:nextTick(openInputDlg)
                                end)
                            else
                                UIManager:show(InfoMessage:new{
                                    text = _("Invalid Unicode codepoint"),
                                    timeout = 3,
                                })
                            end
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Please enter 1-6 hexadecimal digits (0-9, A-F)"),
                                timeout = 3,
                            })
                        end
                    end,
                },
            }},
        }
        UIManager:show(dlg)
    end
    openInputDlg()
end

-- ============================================================
-- Scan icon directory for SVG/PNG files
-- ============================================================

local function scanAllIconDirs(mode)
    -- mode: nil scans all directories, "system" only scans resources/icons/mdlight/
    local all_files = {}
    local seen = {}
    
    local dirs_to_scan
    if mode == "system" then
        dirs_to_scan = { "resources/icons/mdlight" }
    else
        dirs_to_scan = {
            getIconsDir(),                      -- koreader/icons/
            "resources/icons/mdlight",          -- KOReader default icons
            "resources/icons",                  -- fallback
            "resources",                        -- resource root
        }
    end
    
    for _, dir in ipairs(dirs_to_scan) do
        if lfs.attributes(dir, "mode") == "directory" then
            for file in lfs.dir(dir) do
                if file ~= "." and file ~= ".." then
                    local ext = file:lower()
                    if ext:match("%.svg$") or ext:match("%.png$") then
                        local name = file:gsub("%.[^%.]+$", "")
                        if not seen[name] then
                            seen[name] = true
                            local path = dir .. "/" .. file
                            table.insert(all_files, {
                                path = path,
                                name = name,
                                display_name = name:gsub("_", " "),
                                ext = ext,
                                type = "file",
                            })
                        end
                    end
                end
            end
        end
    end
    
    return all_files
end

-- ============================================================
-- File icon cache (normal mode uses this to avoid repeated scanning)
-- ============================================================

local cached_file_icons = nil

local function getFileIcons()
    if cached_file_icons == nil then
        cached_file_icons = scanAllIconDirs()
    end
    return cached_file_icons
end

local function clearFileIconsCache()
    picker_cache = {} 
    cached_file_icons = nil
end

-- ============================================================
-- System icon temporary override table (preview only, not saved to config)
-- ============================================================

local system_temp_overrides = nil

local function getSystemTempOverrides()
    if system_temp_overrides == nil then
        system_temp_overrides = {}
        local saved = getTable("qa_icon_overrides")
        for k, v in pairs(saved) do
            system_temp_overrides[k] = v
        end
    end
    return system_temp_overrides
end

local function resetSystemTempOverrides()
    system_temp_overrides = nil
end

-- ============================================================
-- Icon picker (with grid filtering, auto-recalculates layout on screen resize)
-- ============================================================

local picker_cache = {}

local function showIconPicker(on_select, saved_icon, filter, mode, parent_mode)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local pad = Screen:scaleBySize(24)
    local brd = Screen:scaleBySize(1)

    local cache_key = (filter or "all") .. "_" .. (mode or "normal")
    local use_cache = picker_cache[cache_key] ~= nil

    local icons_list, page_widgets, total_pages
    local frame_x, frame_y, frame_w, frame_h
    local content_w, title_bar_h, button_bar_h, footer_h
    local cols, rows, per_page, h_gap, v_gap
    local cell_w, cell_h, icon_sz, font_size, cell_pad, grid_w, grid_h

    -- Declare dialog and cur_page early
    local dialog = nil
    local cur_page = 1

    -- Filter related variables
    local filter_keyword = ""
    local filtered_icons_list = nil
    local search_dialog = nil

    -- Get display list (filtered by keyword)
    local function getDisplayList()
        if filter_keyword == "" then
            return icons_list
        end
        if filtered_icons_list == nil then
            filtered_icons_list = {}
            local pattern = filter_keyword:lower()
            for _, icon in ipairs(icons_list) do
                local match = false
                if icon.type == "nerd" then
                    if icon.hex:lower():find(pattern, 1, true) then
                        match = true
                    end
                else
                    if icon.display_name and icon.display_name:lower():find(pattern, 1, true) then
                        match = true
                    elseif icon.name and icon.name:lower():find(pattern, 1, true) then
                        match = true
                    end
                end
                if match then
                    table.insert(filtered_icons_list, icon)
                end
            end
        end
        return filtered_icons_list
    end

    -- Rebuild grid
    local function rebuildPicker()
        filtered_icons_list = nil
        local display_list = getDisplayList()
        local new_total_pages = math.max(1, math.ceil(#display_list / per_page))

        local new_page_widgets = {}
        for p = 1, new_total_pages do
            local page_vg = VerticalGroup:new{ align = "left" }
            local start_idx = (p - 1) * per_page + 1
            for row = 0, rows - 1 do
                local row_hg = HorizontalGroup:new{ align = "top" }
                for col = 0, cols - 1 do
                    local idx = start_idx + row * cols + col
                    if idx <= #display_list then
                        local icon = display_list[idx]

                        local icon_widget
                        if icon.type == "nerd" then
                            local nerd_char = nerdIconChar(icon.value)
                            icon_widget = TextWidget:new{
                                text = nerd_char or "?",
                                face = Font:getFace("symbols", font_size),
                                fgcolor = Blitbuffer.COLOR_BLACK,
                            }
                        else
                            local icon_path = icon.path
                            if mode == "system" and icon.is_overridden and icon.override_path then
                                icon_path = icon.override_path
                            end
                            icon_widget = IconWidget:new{
                                file = icon_path,
                                width = icon_sz,
                                height = icon_sz,
                                alpha = true,
                            }
                            pcall(function() icon_widget:_render() end)
                        end

                        local cell_content = CenterContainer:new{
                            dimen = Geom:new{ w = cell_w - cell_pad*2 - 2, h = cell_h - cell_pad*2 - 2 },
                            icon_widget,
                        }

                        local border_color = Blitbuffer.COLOR_LIGHT_GRAY
                        local border_size = 1
                        if mode == "system" and icon.is_overridden then
                            border_color = Blitbuffer.COLOR_BLACK
                            border_size = 2
                        end

                        local cell = FrameContainer:new{
                            width = cell_w,
                            height = cell_h,
                            bordersize = border_size,
                            color = border_color,
                            background = Blitbuffer.COLOR_WHITE,
                            radius = Screen:scaleBySize(4),
                            padding = cell_pad,
                            cell_content,
                        }
                        table.insert(row_hg, cell)
                        if col < cols - 1 then
                            table.insert(row_hg, HorizontalSpan:new{ width = h_gap })
                        end
                    end
                end
                table.insert(page_vg, row_hg)
                if row < rows - 1 then
                    table.insert(page_vg, VerticalSpan:new{ width = v_gap })
                end
            end
            new_page_widgets[p] = page_vg
        end

        page_widgets = new_page_widgets
        total_pages = new_total_pages
        if cur_page > total_pages then
            cur_page = 1
        end
        if dialog then
            UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
        end
    end

    -- Show search dialog
    local function showSearchDialog()
        if search_dialog then
            UIManager:close(search_dialog)
            search_dialog = nil
        end
        search_dialog = InputDialog:new{
            title = _("Filter icons"),
            input = filter_keyword,
            input_hint = _("Enter name or codepoint..."),
            buttons = {
                {
                    {
                        text = _("Clear"),
                        callback = function()
                            UIManager:close(search_dialog)
                            search_dialog = nil
                            filter_keyword = ""
                            rebuildPicker()
                        end,
                    },
                    {
                        text = _("Cancel"),
                        callback = function()
                            UIManager:close(search_dialog)
                            search_dialog = nil
                        end,
                    },
                    {
                        text = _("OK"),
                        is_enter_default = true,
                        callback = function()
                            local input = search_dialog:getInputText() or ""
                            filter_keyword = input
                            UIManager:close(search_dialog)
                            search_dialog = nil
                            rebuildPicker()
                        end,
                    },
                }
            },
        }
        UIManager:show(search_dialog)
        pcall(function() search_dialog:onShowKeyboard() end)
    end

    local temp_overrides = {}
    if mode == "system" then
        temp_overrides = getSystemTempOverrides()
    end

    -- Check if cache is valid (screen size unchanged)
    local cache_valid = false
    if use_cache and mode ~= "system" then
        local cached = picker_cache[cache_key]
        if cached.sw == sw and cached.sh == sh then
            cache_valid = true
            icons_list = cached.icons_list
            page_widgets = cached.page_widgets
            total_pages = cached.total_pages
            frame_x = cached.frame_x
            frame_y = cached.frame_y
            frame_w = cached.frame_w
            frame_h = cached.frame_h
            content_w = cached.content_w
            title_bar_h = cached.title_bar_h
            button_bar_h = cached.button_bar_h
            footer_h = cached.footer_h
            cols = cached.cols
            rows = cached.rows
            per_page = cached.per_page
            h_gap = cached.h_gap
            v_gap = cached.v_gap
            cell_w = cached.cell_w
            cell_h = cached.cell_h
            icon_sz = cached.icon_sz
            font_size = cached.font_size
            cell_pad = cached.cell_pad
            grid_w = cached.grid_w
            grid_h = cached.grid_h
        end
    end

    -- Cache invalid or size changed, need to rebuild
    if not cache_valid then
        -- If cache exists but size changed, reuse icons_list
        if use_cache and mode ~= "system" then
            icons_list = picker_cache[cache_key].icons_list
        else
            -- Build icons_list
            icons_list = {}

            if (not filter or filter == "nerd") and mode ~= "system" then
                local nerd_icons = {
                    { hex = "002B" }, { hex = "0041" }, { hex = "2328" }, { hex = "2610" },
                    { hex = "2611" }, { hex = "270D" }, { hex = "5B57" }, { hex = "6587" },
                    { hex = "E001" }, { hex = "E002" }, { hex = "E003" }, { hex = "E008" },
                    { hex = "E20E" }, { hex = "E22B" }, { hex = "E22C" }, { hex = "E22F" },
                    { hex = "E24B" }, { hex = "E256" }, { hex = "E26E" }, { hex = "E2A8" },
                    { hex = "E310" }, { hex = "E312" }, { hex = "E33A" }, { hex = "E33B" },
                    { hex = "E33C" }, { hex = "E33D" }, { hex = "E615" }, { hex = "E6AD" },
                    { hex = "E70C" }, { hex = "E70F" }, { hex = "E708" }, { hex = "E73C" },
                    { hex = "E795" }, { hex = "E7B8" }, { hex = "E83C" }, { hex = "E83D" },
                    { hex = "E87B" }, { hex = "EAC2" }, { hex = "EAC3" }, { hex = "EB5C" },
                    { hex = "EBB0" }, { hex = "ECA8" }, { hex = "ECA9" }, { hex = "ED14" },
                    { hex = "EDE2" }, { hex = "EEB1" }, { hex = "F002" }, { hex = "F004" },
                    { hex = "F005" }, { hex = "F006" }, { hex = "F007" }, { hex = "F008" },
                    { hex = "F00A" }, { hex = "F00B" }, { hex = "F00C" }, { hex = "F00D" },
                    { hex = "F011" }, { hex = "F013" }, { hex = "F015" }, { hex = "F017" },
                    { hex = "F019" }, { hex = "F01D" }, { hex = "F01E" }, { hex = "F021" },
                    { hex = "F023" }, { hex = "F026" }, { hex = "F027" }, { hex = "F028" },
                    { hex = "F029" }, { hex = "F02A" }, { hex = "F02B" }, { hex = "F02C" },
                    { hex = "F02D" }, { hex = "F02E" }, { hex = "F030" }, { hex = "F031" },
                    { hex = "F03D" }, { hex = "F03E" }, { hex = "F040" }, { hex = "F044" },
                    { hex = "F048" }, { hex = "F04B" }, { hex = "F04C" }, { hex = "F059" },
                    { hex = "F05A" }, { hex = "F060" }, { hex = "F061" }, { hex = "F062" },
                    { hex = "F063" }, { hex = "F067" }, { hex = "F068" }, { hex = "F06A" },
                    { hex = "F06E" }, { hex = "F070" }, { hex = "F071" }, { hex = "F072" },
                    { hex = "F073" }, { hex = "F074" }, { hex = "F079" }, { hex = "F07A" },
                    { hex = "F07B" }, { hex = "F07C" }, { hex = "F085" }, { hex = "F086" },
                    { hex = "F08A" }, { hex = "F08B" }, { hex = "F08E" }, { hex = "F093" },
                    { hex = "F095" }, { hex = "F09C" }, { hex = "F09E" }, { hex = "F0A0" },
                    { hex = "F0A9" }, { hex = "F0AA" }, { hex = "F0AB" }, { hex = "F0AC" },
                    { hex = "F0AD" }, { hex = "F0B0" }, { hex = "F0B2" }, { hex = "F0C0" },
                    { hex = "F0C1" }, { hex = "F0C2" }, { hex = "F0C5" }, { hex = "F0CA" },
                    { hex = "F0CE" }, { hex = "F0D0" }, { hex = "F0D2" }, { hex = "F0DE" },
                    { hex = "F0E0" }, { hex = "F0E2" }, { hex = "F0EA" }, { hex = "F0EB" },
                    { hex = "F0EC" }, { hex = "F0ED" }, { hex = "F0EE" }, { hex = "F0F2" },
                    { hex = "F0F3" }, { hex = "F0F6" }, { hex = "F0FE" }, { hex = "F104" },
                    { hex = "F105" }, { hex = "F106" }, { hex = "F107" }, { hex = "F108" },
                    { hex = "F109" }, { hex = "F10B" }, { hex = "F112" }, { hex = "F115" },
                    { hex = "F11B" }, { hex = "F11C" }, { hex = "F120" }, { hex = "F121" },
                    { hex = "F122" }, { hex = "F123" }, { hex = "F125" }, { hex = "F126" },
                    { hex = "F127" }, { hex = "F12E" }, { hex = "F130" }, { hex = "F131" },
                    { hex = "F135" }, { hex = "F13E" }, { hex = "F140" }, { hex = "F142" },
                    { hex = "F143" }, { hex = "F14A" }, { hex = "F14C" }, { hex = "F15B" },
                    { hex = "F16C" }, { hex = "F185" }, { hex = "F186" }, { hex = "F187" },
                    { hex = "F18C" }, { hex = "F19B" }, { hex = "F19C" }, { hex = "F1AC" },
                    { hex = "F1B2" }, { hex = "F1B8" }, { hex = "F1C0" }, { hex = "F1C1" },
                    { hex = "F1C2" }, { hex = "F1C3" }, { hex = "F1C4" }, { hex = "F1C5" },
                    { hex = "F1C6" }, { hex = "F1C7" }, { hex = "F1C8" }, { hex = "F1C9" },
                    { hex = "F1CA" }, { hex = "F1CD" }, { hex = "F1CE" }, { hex = "F1D8" },
                    { hex = "F1D9" }, { hex = "F1DA" }, { hex = "F1DC" }, { hex = "F1E4" },
                    { hex = "F1E6" }, { hex = "F1E7" }, { hex = "F1F4" }, { hex = "F1F8" },
                    { hex = "F1FC" }, { hex = "F233" }, { hex = "F236" }, { hex = "F240" },
                    { hex = "F245" }, { hex = "F25A" }, { hex = "F282" }, { hex = "F287" },
                    { hex = "F28B" }, { hex = "F28D" }, { hex = "F291" }, { hex = "F29C" },
                    { hex = "F2A9" }, { hex = "F2B9" }, { hex = "F2BE" }, { hex = "F2DB" },
                    { hex = "F303" }, { hex = "F405" }, { hex = "F435" }, { hex = "F44C" },
                    { hex = "F45D" }, { hex = "F45E" }, { hex = "F45F" }, { hex = "F46B" },
                    { hex = "F46D" }, { hex = "F46E" }, { hex = "F487" }, { hex = "F492" },
                }
                for _, icon in ipairs(nerd_icons) do
                    table.insert(icons_list, {
                        type = "nerd",
                        hex = icon.hex,
                        value = "nerd:" .. icon.hex,
                    })
                end
            end

            if not filter or filter == "file" then
                local file_icons
                if mode == "system" then
                    file_icons = scanAllIconDirs("system")
                else
                    file_icons = getFileIcons()
                end
                for _, file in ipairs(file_icons) do
                    local item = {
                        type = "file",
                        path = file.path,
                        name = file.name,
                        display_name = file.display_name,
                        value = file.path,
                    }
                    if mode == "system" then
                        local override_icon = temp_overrides[file.name]
                        item.is_overridden = override_icon ~= nil
                        if override_icon then
                            local override_path = getIconsDir() .. "/" .. override_icon
                            if lfs.attributes(override_path, "mode") == "file" then
                                item.override_path = override_path
                            end
                        end
                    end
                    table.insert(icons_list, item)
                end
            end
        end

        -- Recalculate layout
        -- Choose different row/column counts based on orientation
        if sw > sh then
            -- Landscape
            cols = 9
            rows = 4
            frame_h = math.floor(sh * 0.85)
        else
            -- Portrait
            cols = 7
            rows = 5
            frame_h = math.floor(sh * 0.70)
        end
        per_page = cols * rows
        h_gap = Screen:scaleBySize(15)
        v_gap = Screen:scaleBySize(15)
        frame_w = math.floor(sw * 0.90)
        content_w = frame_w - 2 * pad - 2 * brd
        title_bar_h = Screen:scaleBySize(50)
        button_bar_h = Screen:scaleBySize(50)
        footer_h = Screen:scaleBySize(40)
        cell_w = math.floor((content_w - (cols - 1) * h_gap) / cols)
        local available_h = frame_h - pad - title_bar_h - button_bar_h - footer_h - pad
        cell_h = math.max(44, math.floor((available_h - (rows - 1) * v_gap) / rows))
        icon_sz = math.floor(cell_h * 0.55)
        font_size = math.floor(icon_sz * 0.85)
        cell_pad = math.max(4, math.floor(cell_h * 0.2))
        grid_w = cols * cell_w + (cols - 1) * h_gap
        grid_h = cell_h * rows + (rows - 1) * v_gap
        frame_x = math.floor((sw - frame_w) / 2)
        frame_y = math.max(0, math.floor((sh - frame_h) / 2))

        -- Rebuild page_widgets
        local display_list = getDisplayList()
        total_pages = math.max(1, math.ceil(#display_list / per_page))
        page_widgets = {}

        for p = 1, total_pages do
            local page_vg = VerticalGroup:new{ align = "left" }
            local start_idx = (p - 1) * per_page + 1
            for row = 0, rows - 1 do
                local row_hg = HorizontalGroup:new{ align = "top" }
                for col = 0, cols - 1 do
                    local idx = start_idx + row * cols + col
                    if idx <= #display_list then
                        local icon = display_list[idx]

                        local icon_widget
                        if icon.type == "nerd" then
                            local nerd_char = nerdIconChar(icon.value)
                            icon_widget = TextWidget:new{
                                text = nerd_char or "?",
                                face = Font:getFace("symbols", font_size),
                                fgcolor = Blitbuffer.COLOR_BLACK,
                            }
                        else
                            local icon_path = icon.path
                            if mode == "system" and icon.is_overridden and icon.override_path then
                                icon_path = icon.override_path
                            end
                            icon_widget = IconWidget:new{
                                file = icon_path,
                                width = icon_sz,
                                height = icon_sz,
                                alpha = true,
                            }
                            pcall(function() icon_widget:_render() end)
                        end

                        local cell_content = CenterContainer:new{
                            dimen = Geom:new{ w = cell_w - cell_pad*2 - 2, h = cell_h - cell_pad*2 - 2 },
                            icon_widget,
                        }

                        local border_color = Blitbuffer.COLOR_LIGHT_GRAY
                        local border_size = 1
                        if mode == "system" and icon.is_overridden then
                            border_color = Blitbuffer.COLOR_BLACK
                            border_size = 2
                        end

                        local cell = FrameContainer:new{
                            width = cell_w,
                            height = cell_h,
                            bordersize = border_size,
                            color = border_color,
                            background = Blitbuffer.COLOR_WHITE,
                            radius = Screen:scaleBySize(4),
                            padding = cell_pad,
                            cell_content,
                        }
                        table.insert(row_hg, cell)
                        if col < cols - 1 then
                            table.insert(row_hg, HorizontalSpan:new{ width = h_gap })
                        end
                    end
                end
                table.insert(page_vg, row_hg)
                if row < rows - 1 then
                    table.insert(page_vg, VerticalSpan:new{ width = v_gap })
                end
            end
            page_widgets[p] = page_vg
        end

        -- Cache full data (including screen size and layout)
        if mode ~= "system" then
            picker_cache[cache_key] = {
                icons_list = icons_list,
                page_widgets = page_widgets,
                total_pages = total_pages,
                sw = sw,
                sh = sh,
                frame_x = frame_x,
                frame_y = frame_y,
                frame_w = frame_w,
                frame_h = frame_h,
                content_w = content_w,
                title_bar_h = title_bar_h,
                button_bar_h = button_bar_h,
                footer_h = footer_h,
                cols = cols,
                rows = rows,
                per_page = per_page,
                h_gap = h_gap,
                v_gap = v_gap,
                cell_w = cell_w,
                cell_h = cell_h,
                icon_sz = icon_sz,
                font_size = font_size,
                cell_pad = cell_pad,
                grid_w = grid_w,
                grid_h = grid_h,
            }
        end
    end

    -- ===== Button row =====
    local btn_row
    if mode == "system" then
        local all_overrides = getTable("qa_icon_overrides")
        local replaced = 0
        for _, item in ipairs(icons_list) do
            if temp_overrides[item.name] then
                replaced = replaced + 1
            end
        end

        local reset_all_btn = Button:new{
            text = string.format(_("Reset all (%d)"), replaced),
            width = math.floor(content_w / 2) - 4,
            show_parent = nil,
            callback = function()
                if replaced == 0 then
                    UIManager:show(InfoMessage:new{
                        text = _("No replaced icons to reset"),
                        timeout = 2,
                    })
                    return
                end
                resetSystemTempOverrides()
                setTable("qa_icon_overrides", {})
                picker_cache = {}
                UIManager:show(Notification:new{
                    text = _("All icons reset, restart required"),
                    timeout = 2,
                })
                UIManager:show(ConfirmBox:new{
                    text = _("Restart required. Restart now?"),
                    ok_text = _("Restart"),
                    cancel_text = _("Later"),
                    ok_callback = function()
                        UIManager:restartKOReader()
                    end,
                })
            end,
        }

        local apply_btn = Button:new{
            text = string.format(_("Apply replacements (%d)"), replaced),
            width = math.floor(content_w / 2) - 4,
            show_parent = nil,
            callback = function()
                if replaced == 0 then
                    UIManager:show(InfoMessage:new{
                        text = _("No replaced icons to apply"),
                        timeout = 2,
                    })
                    return
                end
                local overrides = getTable("qa_icon_overrides")
                for k, _ in pairs(overrides) do
                    overrides[k] = nil
                end
                for k, v in pairs(temp_overrides) do
                    if v then
                        overrides[k] = v
                    end
                end
                setTable("qa_icon_overrides", overrides)
                resetSystemTempOverrides()
                picker_cache = {}
                UIManager:show(Notification:new{
                    text = string.format(_("Applied %d icon replacements"), replaced),
                    timeout = 2,
                })
                UIManager:show(ConfirmBox:new{
                    text = _("Restart required. Restart now?"),
                    ok_text = _("Restart"),
                    cancel_text = _("Later"),
                    ok_callback = function()
                        UIManager:restartKOReader()
                    end,
                })
            end,
        }

        btn_row = HorizontalGroup:new{
            align = "center",
            reset_all_btn,
            HorizontalSpan:new{ width = 8 },
            apply_btn,
        }
    else
        local btn_width = math.floor(content_w / 4) - 5
        local show_more_btn = not filter or filter == "nerd"
        local show_browse_btn = not filter or filter == "file"

        local apply_default_btn = Button:new{
            text = _("Apply default"),
            width = btn_width,
            show_parent = nil,
            callback = function()
                UIManager:close(dialog)
                UIManager:setDirty("all", "full")
                if on_select then on_select(nil) end
            end,
        }

        local refresh_btn = Button:new{
            text = "Refresh↻",
            width = btn_width,
            show_parent = nil,
            callback = function()
                clearFileIconsCache()
                picker_cache = {}
                UIManager:close(dialog)
                UIManager:setDirty("all", "full")
                showIconPicker(on_select, saved_icon, filter, mode, parent_mode)
            end,
        }

        local more_btn
        if show_more_btn then
            more_btn = Button:new{
                text = _("More Nerd Fonts"),
                width = btn_width,
                show_parent = nil,
                callback = function()
                    UIManager:close(dialog)
                    UIManager:setDirty("all", "full")
                    showNerdIconInput(nil, on_select, saved_icon)
                end,
            }
        end

        local browse_btn
        if show_browse_btn then
            browse_btn = Button:new{
                text = _("Browse files"),
                width = btn_width,
                show_parent = nil,
                callback = function()
                    UIManager:close(dialog)
                    UIManager:setDirty("all", "full")
                    clearFileIconsCache()
                    UIManager:show(IconBrowser:new{
                        path = getIconsDir(),
                        onConfirm = function(file_path)
                            if on_select then on_select(file_path) end
                        end,
                    })
                end,
            }
        end

        local btn_row_children = { apply_default_btn }
        table.insert(btn_row_children, HorizontalSpan:new{ width = 8 })
        table.insert(btn_row_children, refresh_btn)
        if show_more_btn then
            table.insert(btn_row_children, HorizontalSpan:new{ width = 8 })
            table.insert(btn_row_children, more_btn)
        end
        if show_browse_btn then
            table.insert(btn_row_children, HorizontalSpan:new{ width = 8 })
            table.insert(btn_row_children, browse_btn)
        end
        btn_row = HorizontalGroup:new{
            align = "center",
            unpack(btn_row_children),
        }
    end

    local inner_frame = FrameContainer:new{
        width = frame_w,
        height = frame_h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = brd,
        radius = Screen:scaleBySize(8),
        padding = pad,
        VerticalGroup:new{ align = "center" },
    }

    local PickerDlg = InputContainer:extend{}
    function PickerDlg:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        self:registerTouchZones({
            {
                id = "picker_tap",
                ges = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function(ges)
                    local fd = inner_frame.dimen
                    if not fd or not ges.pos:intersectWith(fd) then
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        return true
                    end
                    local gx, gy = ges.pos.x, ges.pos.y
                    local btn_hit = 80

                    -- Top-left back button
                    if gx >= frame_x + pad and gx < frame_x + pad + btn_hit
                            and gy >= frame_y + pad and gy < frame_y + pad + btn_hit then
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        if parent_mode == "system" then
                            showIconPicker(nil, nil, nil, "system")
                        else
                            if on_select then on_select(saved_icon) end
                        end
                        return true
                    end

                    -- Top-right search button
                    if gx >= frame_x + frame_w - pad - btn_hit and gx < frame_x + frame_w - pad
                            and gy >= frame_y + pad and gy < frame_y + pad + btn_hit then
                        showSearchDialog()
                        return true
                    end

                    -- Button row tap
                    local btn_y = frame_y + pad + title_bar_h
                    if gy >= btn_y and gy < btn_y + button_bar_h then
                        if mode == "system" then
                            local btn_width = math.floor(content_w / 2) - 4
                            local btn_x_start = frame_x + pad
                            if gx >= btn_x_start and gx < btn_x_start + btn_width then
                                local all_overrides = getTable("qa_icon_overrides")
                                local replaced = 0
                                for _, item in ipairs(icons_list) do
                                    if temp_overrides[item.name] then
                                        replaced = replaced + 1
                                    end
                                end
                                if replaced == 0 then
                                    UIManager:show(InfoMessage:new{
                                        text = _("No replaced icons to reset"),
                                        timeout = 2,
                                    })
                                    return true
                                end
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                resetSystemTempOverrides()
                                setTable("qa_icon_overrides", {})
                                picker_cache = {}
                                UIManager:show(Notification:new{
                                    text = _("All icons reset, restart required"),
                                    timeout = 2,
                                })
                                UIManager:show(ConfirmBox:new{
                                    text = _("Restart required. Restart now?"),
                                    ok_text = _("Restart"),
                                    cancel_text = _("Later"),
                                    ok_callback = function()
                                        UIManager:restartKOReader()
                                    end,
                                })
                                return true
                            end
                            if gx >= btn_x_start + btn_width + 8 and gx < btn_x_start + (btn_width + 8) * 2 then
                                local all_overrides = getTable("qa_icon_overrides")
                                local replaced = 0
                                for _, item in ipairs(icons_list) do
                                    if temp_overrides[item.name] then
                                        replaced = replaced + 1
                                    end
                                end
                                if replaced == 0 then
                                    UIManager:show(InfoMessage:new{
                                        text = _("No replaced icons to apply"),
                                        timeout = 2,
                                    })
                                    return true
                                end
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                local overrides = getTable("qa_icon_overrides")
                                for k, _ in pairs(overrides) do
                                    overrides[k] = nil
                                end
                                for k, v in pairs(temp_overrides) do
                                    if v then
                                        overrides[k] = v
                                    end
                                end
                                setTable("qa_icon_overrides", overrides)
                                resetSystemTempOverrides()
                                picker_cache = {}
                                UIManager:show(Notification:new{
                                    text = string.format(_("Applied %d icon replacements"), replaced),
                                    timeout = 2,
                                })
                                UIManager:show(ConfirmBox:new{
                                    text = _("Restart required. Restart now?"),
                                    ok_text = _("Restart"),
                                    cancel_text = _("Later"),
                                    ok_callback = function()
                                        UIManager:restartKOReader()
                                    end,
                                })
                                return true
                            end
                            return true
                        else
                            local btn_x_start = frame_x + pad
                            local current_btn_width = math.floor(content_w / 4) - 5
                            local btn_index = 0

                            if gx >= btn_x_start and gx < btn_x_start + current_btn_width then
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                if on_select then on_select(nil) end
                                return true
                            end
                            btn_index = btn_index + 1

                            local x_start = btn_x_start + (current_btn_width + 8) * btn_index
                            if gx >= x_start and gx < x_start + current_btn_width then
                                clearFileIconsCache()
                                picker_cache = {}
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                showIconPicker(on_select, saved_icon, filter, mode, parent_mode)
                                return true
                            end
                            btn_index = btn_index + 1

                            if not filter or filter == "nerd" then
                                local x_start = btn_x_start + (current_btn_width + 8) * btn_index
                                if gx >= x_start and gx < x_start + current_btn_width then
                                    UIManager:close(self)
                                    UIManager:setDirty("all", "full")
                                    showNerdIconInput(nil, on_select, saved_icon)
                                    return true
                                end
                                btn_index = btn_index + 1
                            end

                            if not filter or filter == "file" then
                                local x_start = btn_x_start + (current_btn_width + 8) * btn_index
                                if gx >= x_start and gx < x_start + current_btn_width then
                                    UIManager:close(self)
                                    UIManager:setDirty("all", "full")
                                    clearFileIconsCache()
                                    UIManager:show(IconBrowser:new{
                                        path = getIconsDir(),
                                        onConfirm = function(file_path)
                                            if on_select then on_select(file_path) end
                                        end,
                                    })
                                    return true
                                end
                            end
                            return true
                        end
                    end

                    -- Bottom pagination
                    local bar_y = frame_y + pad + title_bar_h + button_bar_h + grid_h
                    if gy >= bar_y and gy < bar_y + footer_h then
                        local chev_w = 80
                        if gx < frame_x + pad + chev_w then
                            if cur_page > 1 then
                                cur_page = cur_page - 1
                                UIManager:setDirty(self, function() return "ui", self.dimen end)
                            end
                            return true
                        elseif gx > frame_x + frame_w - pad - chev_w then
                            if cur_page < total_pages then
                                cur_page = cur_page + 1
                                UIManager:setDirty(self, function() return "ui", self.dimen end)
                            end
                            return true
                        end
                        return true
                    end

                    -- Grid tap
                    local grid_start_x = frame_x + pad + (content_w - grid_w) / 2
                    local grid_y = frame_y + pad + title_bar_h + button_bar_h
                    if gx >= grid_start_x and gx < grid_start_x + grid_w
                            and gy >= grid_y and gy < grid_y + grid_h then
                        local col = math.floor((gx - grid_start_x) / (cell_w + h_gap))
                        local row = math.floor((gy - grid_y) / (cell_h + v_gap))
                        local display_list = getDisplayList()
                        local idx = (cur_page - 1) * per_page + row * cols + col + 1
                        if idx >= 1 and idx <= #display_list then
                            local selected_icon = display_list[idx]
                            if mode == "system" then
                                local system_icon_name = selected_icon.name
                                local current = temp_overrides[system_icon_name]
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                showIconPicker(
                                    function(selected)
                                        if selected == current then
                                            return
                                        end
                                        if selected then
                                            local filename = selected:match("([^/]+)$") or selected
                                            temp_overrides[system_icon_name] = filename
                                        else
                                            temp_overrides[system_icon_name] = nil
                                        end
                                        picker_cache = {}
                                        showIconPicker(nil, nil, nil, "system")
                                    end,
                                    current,
                                    "file",
                                    nil,
                                    "system"
                                )
                                return true
                            else
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                if on_select then
                                    on_select(selected_icon.value)
                                end
                                return true
                            end
                        end
                    end
                    return true
                end,
            },
            {
                id = "picker_swipe",
                ges = "swipe",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function(ges)
                    local dir = ges.direction
                    if dir == "west" then
                        if cur_page < total_pages then
                            cur_page = cur_page + 1
                            UIManager:setDirty(self, function() return "ui", self.dimen end)
                        end
                    elseif dir == "east" then
                        if cur_page > 1 then
                            cur_page = cur_page - 1
                            UIManager:setDirty(self, function() return "ui", self.dimen end)
                        end
                    else
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        return true
                    end
                    return true
                end,
            },
        })
    end

    function PickerDlg:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        inner_frame.dimen = Geom:new{ x = frame_x, y = frame_y, w = frame_w, h = frame_h }
        inner_frame:paintTo(bb, frame_x, frame_y)
        local content_x = frame_x + pad
        local content_y = frame_y + pad

        -- Title
        local title_text
        if mode == "system" then
            title_text = _("System Icon Preview")
        elseif filter == "file" then
            title_text = _("Select icon file")
        else
            title_text = _("Select icon")
        end
        if filter_keyword ~= "" then
            title_text = title_text .. " [" .. _("Filter") .. ": \"" .. filter_keyword .. "\"]"
        end
        local title_tw = TextWidget:new{
            text = title_text,
            face = Font:getFace("smallinfofont"),
            bold = true,
        }
        local title_w = title_tw:getSize().w
        title_tw:paintTo(bb, content_x + (content_w - title_w) / 2, content_y + 12)

        -- Top-left back
        local back_tw = TextWidget:new{
            text = "↶",
            face = Font:getFace("cfont", 24),
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        back_tw:paintTo(bb, content_x, content_y + 5)

        -- Top-right search icon (Nerd Font)
        local search_char = nerdIconChar("nerd:F002") or "?"
        local search_tw = TextWidget:new{
            text = search_char,
            face = Font:getFace("symbols", 22),
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        search_tw:paintTo(bb, content_x + content_w - 35, content_y + 5)

        -- Button row
        local btn_y = content_y + title_bar_h
        btn_row:paintTo(bb, content_x, btn_y)

        -- Grid
        local grid_start_x = content_x + (content_w - grid_w) / 2
        local grid_start_y = content_y + title_bar_h + button_bar_h
        local display_list = getDisplayList()
        if #display_list == 0 then
            local empty_tw = TextWidget:new{
                text = _("No matching icons"),
                face = Font:getFace("cfont"),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            }
            local empty_w = empty_tw:getSize().w
            empty_tw:paintTo(bb, grid_start_x + (grid_w - empty_w) / 2, grid_start_y + grid_h / 2 - 20)
        else
            page_widgets[cur_page]:paintTo(bb, grid_start_x, grid_start_y)
        end

        -- Pagination
        if total_pages > 1 then
            local bar_y = grid_start_y + grid_h + (footer_h - 20) / 2
            local left_arrow = TextWidget:new{
                text = "◀",
                face = Font:getFace("cfont", 20),
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
            left_arrow:paintTo(bb, content_x + 10, bar_y)
            local right_arrow = TextWidget:new{
                text = "▶",
                face = Font:getFace("cfont", 20),
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
            right_arrow:paintTo(bb, frame_x + frame_w - pad - 50, bar_y)
            local page_text = TextWidget:new{
                text = string.format("%d / %d", cur_page, total_pages),
                face = Font:getFace("cfont", 14),
                fgcolor = Blitbuffer.gray(0.5),
            }
            local text_w = page_text:getSize().w
            page_text:paintTo(bb, frame_x + (frame_w - text_w) / 2, bar_y)
        end
    end

    dialog = PickerDlg:new{}
    UIManager:show(dialog, "full")
end

-- ============================================================
-- Menu path recorder
-- ============================================================

local _pick_state = {
    active = false,
    menu = nil,
    nav_path = {},
    tab_index = 1,
    on_done = nil,
    on_cancel = nil,
}

local _orig_onMenuSelect = nil
local _orig_backToUpperMenu = nil
local _orig_switchMenuTab = nil
local _orig_closeMenu = nil
local _orig_updateItems = nil

local function _itemText(item)
    local t = item.text
    if type(t) == "function" then t = t() end
    if not t and item.text_func then t = item.text_func() end
    return type(t) == "string" and t or ""
end

local function _snapshotMenuState(menu)
    local item_table_stack = {}
    for i, item_table in ipairs(menu.item_table_stack or {}) do
        item_table_stack[i] = item_table
    end
    return {
        cur_tab = menu.cur_tab,
        item_table = menu.item_table,
        item_table_stack = item_table_stack,
        page = menu.page,
    }
end

local function _restoreMenuState(menu, state)
    if not menu or not state then return end
    menu.cur_tab = state.cur_tab
    menu.item_table = state.item_table
    menu.item_table_stack = {}
    for i, tbl in ipairs(state.item_table_stack or {}) do
        menu.item_table_stack[i] = tbl
    end
    menu.parent_id = nil
    menu.page = state.page or 1
    menu:updateItems(menu.page)
end

local function _stopPicking()
    local menu = _pick_state.menu
    local action_bar = _pick_state.action_bar
    local bars_span = _pick_state.bars_span
    _pick_state.action_bar = nil
    _pick_state.bars_span = nil
    _pick_state.active = false
    _pick_state.menu = nil
    _pick_state.on_done = nil
    _pick_state.on_cancel = nil
    _pick_state.tab_index = nil
    _pick_state.nav_path = nil
    _pick_state.view = nil
    if menu and action_bar then
        local ig = menu.item_group
        for i = #ig, 1, -1 do
            if ig[i] == action_bar or ig[i] == bars_span then
                table.remove(ig, i)
            end
        end
        ig:resetLayout()
        menu.dimen.h = ig:getSize().h + menu.bordersize * 2 + menu.padding
        UIManager:setDirty(menu.show_parent, function()
            return "ui", menu.dimen
        end)
    end
    UIManager:setDirty("all", "flashui")
    local TouchMenu = require("ui/widget/touchmenu")
    if _orig_onMenuSelect then
        TouchMenu.onMenuSelect = _orig_onMenuSelect
        TouchMenu.backToUpperMenu = _orig_backToUpperMenu
        TouchMenu.switchMenuTab = _orig_switchMenuTab
        TouchMenu.closeMenu = _orig_closeMenu
        TouchMenu.updateItems = _orig_updateItems
        _orig_onMenuSelect = nil
        _orig_backToUpperMenu = nil
        _orig_switchMenuTab = nil
        _orig_closeMenu = nil
        _orig_updateItems = nil
    end
end

local function _makeActionBar(menu)
    local buttons = {}
    table.insert(buttons, Button:new{
        text = _("Save recording as quick action"),
        width = menu.item_width,
        text_font_bold = true,
        bordersize = Size.border.thin,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        show_parent = menu.show_parent,
        callback = function()
            if _pick_state.active then
                local index_path = {}
                for _, step in ipairs(_pick_state.nav_path) do
                    table.insert(index_path, step.index)
                end
                local path_record = {
                    tab_index = _pick_state.tab_index,
                    display_label = _pick_state.nav_path[#_pick_state.nav_path] and _pick_state.nav_path[#_pick_state.nav_path].text or _("Menu action"),
                    index_path = index_path,
                    view = _pick_state.view,
                    is_leaf = false,
                }
                local cb = _pick_state.on_done
                _stopPicking()
                if cb then cb(path_record) end
            end
        end,
    })
    table.insert(buttons, Button:new{
        text = _("Cancel"),
        width = menu.item_width,
        text_font_bold = true,
        bordersize = Size.border.thin,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        show_parent = menu.show_parent,
        callback = function()
            if _pick_state.active then
                local cb = _pick_state.on_cancel
                _stopPicking()
                if cb then cb() end
            end
        end,
    })
    local vg = VerticalGroup:new{ align = "center" }
    for _, btn in ipairs(buttons) do
        table.insert(vg, btn)
        table.insert(vg, VerticalSpan:new{ width = Size.padding.small })
    end
    return vg
end

local function startPicking(menu, on_done, on_cancel, view)
    local TouchMenu = require("ui/widget/touchmenu")
    if _pick_state.active then
        _stopPicking()
    end
    if not _orig_onMenuSelect then
        _orig_onMenuSelect = TouchMenu.onMenuSelect
        _orig_backToUpperMenu = TouchMenu.backToUpperMenu
        _orig_switchMenuTab = TouchMenu.switchMenuTab
        _orig_closeMenu = TouchMenu.closeMenu
        _orig_updateItems = TouchMenu.updateItems
    end
    _pick_state.active = true
    _pick_state.menu = menu
    _pick_state.tab_index = 1
    _pick_state.nav_path = {}
    _pick_state.view = view or "common"
    _pick_state.on_done = on_done
    _pick_state.on_cancel = on_cancel
    TouchMenu.updateItems = function(self, ...)
        local result = _orig_updateItems(self, ...)
        if _pick_state.active and self == menu then
            if not _pick_state.action_bar then
                _pick_state.action_bar = _makeActionBar(self)
            end
            if not _pick_state.bars_span then
                _pick_state.bars_span = VerticalSpan:new{ width = Size.padding.default }
            end
            table.insert(self.item_group, _pick_state.bars_span)
            table.insert(self.item_group, _pick_state.action_bar)
            self.item_group:resetLayout()
            self.dimen.h = self.item_group:getSize().h + self.bordersize * 2 + self.padding
            UIManager:setDirty(self.show_parent, function()
                return "ui", self.dimen
            end)
        end
        return result
    end
    TouchMenu.closeMenu = function(self, ...)
        if _pick_state.active and self == menu then
            local cb = _pick_state.on_cancel
            _stopPicking()
            if cb then cb() end
        end
        return _orig_closeMenu(self, ...)
    end
    TouchMenu.onMenuSelect = function(self, item, tap_on_checkmark)
        if not _pick_state.active then
            return _orig_onMenuSelect(self, item, tap_on_checkmark)
        end
        local sub = (item.sub_item_table_func and item.sub_item_table_func())
                 or item.sub_item_table
        local item_index
        for i, it in ipairs(self.item_table or {}) do
            if it == item then item_index = i; break end
        end
        if sub then
            table.insert(_pick_state.nav_path, {
                index = item_index,
                text = _itemText(item),
            })
            return _orig_onMenuSelect(self, item, tap_on_checkmark)
        end
        local label = _itemText(item)
        local index_path = {}
        for _, step in ipairs(_pick_state.nav_path) do
            table.insert(index_path, step.index)
        end
        table.insert(index_path, item_index)
        local path_record = {
            tab_index = _pick_state.tab_index,
            display_label = label,
            index_path = index_path,
            view = _pick_state.view,
            is_leaf = true,
        }
        local cb = _pick_state.on_done
        _stopPicking()
        if cb then cb(path_record) end
        return true
    end
    TouchMenu.backToUpperMenu = function(self, no_close)
        if _pick_state.active and self == menu then
            if #self.item_table_stack ~= 0 then
                if #_pick_state.nav_path > 0 then
                    table.remove(_pick_state.nav_path)
                end
            else
                local cb = _pick_state.on_cancel
                _stopPicking()
                if cb then cb() end
            end
        end
        return _orig_backToUpperMenu(self, no_close)
    end
    TouchMenu.switchMenuTab = function(self, tab_num)
        if _pick_state.active and self == menu then
            _pick_state.tab_index = tab_num
            _pick_state.nav_path = {}
        end
        return _orig_switchMenuTab(self, tab_num)
    end
    menu.cur_tab = nil
    if menu.bar and menu.bar.switchToTab then
        menu.bar:switchToTab(1)
    end
    UIManager:show(Notification:new{
        text = _("Tap any menu item to record as quick action"),
        timeout = 2,
    })
end

local function replayPath(menu, path_record)
    if not path_record or not path_record.index_path then return false end
    local TouchMenu = require("ui/widget/touchmenu")
    local _orig_switchMenuTab = TouchMenu.switchMenuTab
    if path_record.tab_index then
        local switch = _orig_switchMenuTab or TouchMenu.switchMenuTab
        switch(menu, path_record.tab_index)
    end
    local saved_state = _snapshotMenuState(menu)
    local current_menu = menu
    local current_item = nil
    local function ensurePageForIndex(target_idx)
        if not current_menu.perpage then return end
        local target_page = math.ceil(target_idx / current_menu.perpage)
        if target_page > 1 and target_page ~= current_menu.page then
            if current_menu.onGotoPage then
                current_menu:onGotoPage(target_page)
            end
        end
    end
    for i, idx in ipairs(path_record.index_path) do
        ensurePageForIndex(idx)
        if not current_menu.item_table or not current_menu.item_table[idx] then
            _restoreMenuState(menu, saved_state)
            return false
        end
        current_item = current_menu.item_table[idx]
        local should_enter_submenu = (i < #path_record.index_path) or (i == #path_record.index_path and not path_record.is_leaf)
        if should_enter_submenu then
            local sub = (current_item.sub_item_table_func and current_item.sub_item_table_func())
                     or current_item.sub_item_table
            if not sub or #sub == 0 then
                _restoreMenuState(menu, saved_state)
                return false
            end
            table.insert(current_menu.item_table_stack, current_menu.item_table)
            current_menu.item_table = sub
            current_menu.page = 1
            if current_menu.updateItems then
              current_menu:updateItems()
            end
        end
    end
    if path_record.is_leaf then
        local callback = (current_item.callback_func and current_item.callback_func()) or current_item.callback
        if callback then
            pcall(callback, current_menu)
        end
        _restoreMenuState(menu, saved_state)
        menu:closeMenu()
    end
    return true
end

-- ============================================================
-- Action execution
-- ============================================================

local ACTION_REGISTRY = {}
local ACTION_ORDER = {}
local _wifi_optimistic = nil 

local function getNetworkMgr()
    local ok, nm = pcall(require, "ui/network/manager")
    return ok and nm or nil
end

local function executePluginAction(plugin_key, plugin_method)
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    
    local plugin_inst = nil
    local source = "fm"
    
    -- 1. Check FM first
    if fm and fm[plugin_key] then
        plugin_inst = fm[plugin_key]
        source = "fm"
    end
    
    -- 2. If not in FM, check ReaderUI
    if not plugin_inst and reader and reader[plugin_key] then
        plugin_inst = reader[plugin_key]
        source = "reader"
    end
    
    if not plugin_inst then
        UIManager:show(InfoMessage:new{
            text = string.format(_("Plugin unavailable: %s"), plugin_key),
            timeout = 2,
        })
        return
    end
    
    -- 3. Support _qa_launch (callback extracted via addToMainMenu)
    if plugin_method == "_qa_launch" and type(plugin_inst._qa_launch) == "function" then
        pcall(plugin_inst._qa_launch, plugin_inst)
    elseif type(plugin_inst[plugin_method]) == "function" then
        pcall(plugin_inst[plugin_method], plugin_inst)
    else
        UIManager:show(InfoMessage:new{
            text = string.format(_("Plugin method unavailable: %s.%s"), plugin_key, plugin_method),
            timeout = 2,
        })
    end
end

local function executeDispatcherAction(action_id, action_value, ctx)
    if ctx and ctx.touch_menu then
        ctx.touch_menu:onClose()
    end
    local ok_disp, DispatcherMod = pcall(require, "dispatcher")
    if ok_disp and DispatcherMod then
        DispatcherMod:execute({ [action_id] = action_value })
    end
end

local function executeFolderAction(folder_path, ctx)
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local rui = RUI and RUI.instance
    if ctx and ctx.touch_menu then
        ctx.touch_menu:onClose()
    end
    if fm and fm.file_chooser then
        fm.file_chooser:changeToPath(folder_path)
    elseif rui then
        rui:onClose()
        FM:showFiles()
        local fm2 = FM.instance
        if fm2 and fm2.file_chooser then
            fm2.file_chooser:changeToPath(folder_path)
        end
    end
end

local function executeCollectionAction(collection_name)
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local rui = RUI and RUI.instance
    if fm and fm.collections then
        pcall(fm.collections.onShowColl, fm.collections, collection_name)
    elseif rui then
        rui.tearing_down = true
        rui:onClose()
        FM:showFiles()
        local fm2 = FM.instance
        if fm2 and fm2.collections then
            pcall(fm2.collections.onShowColl, fm2.collections, collection_name)
        end
    end
end

local function executeMenuAction(menu_path, ctx)
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local rui = RUI and RUI.instance
    local recorded_view = menu_path.view or "common"
    local current_view = nil
    if rui and rui.instance and not rui.instance.tearing_down then
        current_view = "reader"
    elseif fm and fm.instance then
        current_view = "filemanager"
    end
    if recorded_view == "common" or recorded_view == current_view then
        local target_menu = nil
        if recorded_view == "reader" or current_view == "reader" then
            if rui and rui.menu then
                if not rui.menu.menu_container or not rui.menu.menu_container[1] then
                    rui.menu:onShowMenu()
                end
                local mc = rui.menu.menu_container
                if mc and mc[1] then
                    target_menu = mc[1]
                else
                    target_menu = rui.menu
                end
            end
        else
            if fm and fm.menu then
                if not fm.menu.menu_container or not fm.menu.menu_container[1] then
                    fm.menu:onShowMenu(menu_path.tab_index or 1)
                end
                local mc = fm.menu.menu_container
                if mc and mc[1] then
                    target_menu = mc[1]
                else
                    target_menu = fm.menu
                end
            end
        end
        if target_menu then
            replayPath(target_menu, menu_path)
        else
            UIManager:show(InfoMessage:new{
                text = _("Unable to open menu"),
                timeout = 2,
            })
        end
    else
        local msg = (recorded_view == "reader") 
            and _("This quick action can only be executed in the reader. Please open a book first.")
            or _("This quick action can only be executed in the file browser.")
        UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
        return
    end
end

-- ============================================================
-- Action retrieval and registration
-- ============================================================

local function getAction(id)
    local builtin_overrides = getTable("builtin_overrides")
    if builtin_overrides[id] then
        return {
            label = builtin_overrides[id].label or (ACTION_REGISTRY[id] and ACTION_REGISTRY[id].label) or id,
            icon = builtin_overrides[id].icon or (ACTION_REGISTRY[id] and ACTION_REGISTRY[id].icon),
            is_in_place = ACTION_REGISTRY[id] and ACTION_REGISTRY[id].is_in_place or false,
            view = builtin_overrides[id].view or (ACTION_REGISTRY[id] and ACTION_REGISTRY[id].view) or "common",
            execute = ACTION_REGISTRY[id] and ACTION_REGISTRY[id].execute,
        }
    end
    if ACTION_REGISTRY[id] then 
        local action = ACTION_REGISTRY[id]
        return {
            label = action.label,
            icon = action.icon,
            is_in_place = action.is_in_place,
            view = action.view or "common",
            execute = action.execute,
        }
    end
    local custom = getTable("custom")
    local cfg = custom[id]
    if type(cfg) == "table" and cfg.label then
        local view = cfg.view or "common"
        if cfg.action_type == "menu" and cfg.menu_path and cfg.menu_path.view then
            view = cfg.menu_path.view
        end
        return {
            label = cfg.label,
            icon = cfg.icon,
            is_in_place = cfg.is_in_place or false,
            view = view,
            execute = function(ctx)
                if cfg.action_type == "folder" and cfg.action_value then
                    executeFolderAction(cfg.action_value, ctx)
                elseif cfg.action_type == "collection" and cfg.action_value then
                    executeCollectionAction(cfg.action_value)
                elseif cfg.action_type == "plugin" and cfg.plugin_key then
                    executePluginAction(cfg.plugin_key, cfg.plugin_method)
                elseif cfg.action_type == "dispatcher" and cfg.dispatcher_action then
                    executeDispatcherAction(cfg.dispatcher_action, cfg.dispatcher_value or true, ctx)
                elseif cfg.action_type == "menu" and cfg.menu_path then
                    executeMenuAction(cfg.menu_path, ctx)
                end
            end,
        }
    end
    return nil
end

local function executeAction(id, ctx)
    local action = getAction(id)
    if action and action.execute then
        action.execute(ctx or {})
    end
end

local function isInPlace(id)
    local action = getAction(id)
    return action and action.is_in_place or false
end

local function getLabelForAction(id)
    local builtin_overrides = getTable("builtin_overrides")
    if builtin_overrides[id] and builtin_overrides[id].label then
        return builtin_overrides[id].label
    end
    local action = getAction(id)
    if action then return action.label end
    return id
end

local function getIconForAction(id)
    local builtin_overrides = getTable("builtin_overrides")
    if builtin_overrides[id] and builtin_overrides[id].icon then
        return builtin_overrides[id].icon
    end
    if id == "wifi" then
        if _wifi_optimistic ~= nil then
            return _wifi_optimistic and "nerd:ECA8" or "nerd:ECA9"
        end
        local NetworkMgr = getNetworkMgr()
        if NetworkMgr then
            local ok, is_on = pcall(function() return NetworkMgr:isWifiOn() end)
            if ok and is_on then
                return "nerd:ECA8"
            else
                return "nerd:ECA9"
            end
        end
        return "nerd:ECA8"
    end

if id == "toggle_cloze_mode" then
    -- Check if currently covered
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    if reader and reader.highlight then
        local has_covered = false
        local annotations = reader.highlight.ui.annotation.annotations
        if annotations then
            for idx, item in ipairs(annotations) do
                if item.drawer and reader.highlight._temp_covered and reader.highlight._temp_covered[idx] then
                    has_covered = true
                    break
                end
            end
        end
        if has_covered then
            return "nerd:F070"  -- Covered (locked)
        else
            return "nerd:F06E"  -- Not covered (unlocked)
        end
    end
    return "nerd:F06E"  -- Default unlocked
end

    local action = getAction(id)
    if action then return action.icon end
    return nil
end

local function registerAction(id, label, icon, is_in_place, view, execute_fn)
    ACTION_REGISTRY[id] = {
        label = label,
        icon = icon,
        is_in_place = is_in_place,
        view = view or "common",
        execute = execute_fn,
    }
    ACTION_ORDER[#ACTION_ORDER + 1] = id
end

-- ============================================================
-- Register built-in actions (to delete, simply remove the corresponding registration code)
-- ============================================================

-- Built-in system quick actions
registerAction("wifi", _("Wi-Fi"), "net-wifi.svg", true, "common", function(ctx)
    local NetworkMgr = getNetworkMgr()
    if not NetworkMgr then
        UIManager:show(InfoMessage:new{ text = _("WiFi not available"), timeout = 2 })
        return
    end
    local is_on = NetworkMgr:isWifiOn()
    _wifi_optimistic = not is_on
    if ctx.touch_menu then
        ctx.touch_menu:updateItems()
    end
    if is_on then
        NetworkMgr:turnOffWifi()
    else
        NetworkMgr:turnOnWifi()
    end
    UIManager:scheduleIn(2, function()
        _wifi_optimistic = nil
        if ctx.touch_menu then
            ctx.touch_menu:updateItems()
        end
    end)
end)

registerAction("night", _("Night mode"), "nerd:F186", true, "common", function(ctx)
    local G = rawget(_G, "G_reader_settings")
    local night_mode = G and G:isTrue("night_mode") or false
    Screen:toggleNightMode()
    UIManager:ToggleNightMode(not night_mode)
    if G then G:saveSetting("night_mode", not night_mode) end
    UIManager:setDirty("all", "full")
end)

registerAction("rotate", _("Rotate"), "nerd:EB4D", true, "common", function(ctx)
    UIManager:broadcastEvent(require("ui/event"):new("SwapRotation"))
end)

registerAction("screenshot", _("Screenshot (4s delay)"), "nerd:F030", false, "common", function(ctx)
    local function showCountdown(num)
        UIManager:show(Notification:new{
            text = tostring(num),
            timeout = 1,
        })
    end
    showCountdown(3)
    UIManager:scheduleIn(1, function()
        showCountdown(2)
        UIManager:scheduleIn(1, function()
            UIManager:scheduleIn(1, function()
                local ui = require("apps/reader/readerui").instance
                if not ui then
                    local FM = require("apps/filemanager/filemanager")
                    ui = FM.instance
                end
                if ui and ui.screenshoter then
                    ui.screenshoter:onScreenshot()
                else
                    local Screenshoter = require("ui/widget/screenshoter")
                    local temp = Screenshoter:new{ ui = ui }
                    temp:onScreenshot()
                end
            end)
        end)
    end)
end)

registerAction("continue", _("Continue reading"), "nerd:F405", false, "common", function(ctx)
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    local RH = require("readhistory")
    local target_file = nil
    if reader and reader.document then
        local current_file = reader.document.file
        target_file = RH:getPreviousFile(current_file)
    else
        target_file = RH and RH.hist and RH.hist[1] and RH.hist[1].file
    end
    if target_file then
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(target_file)
    else
        UIManager:show(InfoMessage:new{
            text = _("No recently read book found"),
            timeout = 2,
        })
    end
end)

registerAction("search", _("Search"), "nerd:F002", false, "common", function(ctx)
    local ReaderUI = require("apps/reader/readerui")
    local reader = ReaderUI.instance
    if reader and reader.search then
        reader.search:onShowFulltextSearchInput()
    else
        local FM = require("apps/filemanager/filemanager")
        local fm = FM.instance
        if fm and fm.filesearcher then
            fm.filesearcher:onShowFileSearch()
        end
    end
end)

registerAction("quit", _("Quit"), "nerd:F08B", false, "common", function(ctx)
    UIManager:quit()
end)

registerAction("restart", _("Restart"), "nerd:F01E", false, "common", function(ctx)
    UIManager:restartKOReader()
end)

registerAction("power", _("Power"), "nerd:F011", true, "common", function(ctx)
    local buttons = {}
    if Device:canRestart() then
        buttons[#buttons + 1] = {{ text = _("Restart"), callback = function()
            UIManager:restartKOReader()
        end }}
    end
    if Device:canSuspend() then
        buttons[#buttons + 1] = {{ text = _("Sleep"), callback = function()
            UIManager:suspend()
        end }}
    end
    buttons[#buttons + 1] = {{ text = _("Quit"), callback = function()
        UIManager:quit()
    end }}
    UIManager:show(ButtonDialog:new{ width = math.floor(Screen:getWidth() * 0.42), buttons = buttons })
end)

registerAction("httpinspector", _("HTTP server"), "nerd:F44C", true, "common", function()
    local ui = require("apps/reader/readerui").instance
    if not ui then
        local FM = require("apps/filemanager/filemanager")
        ui = FM.instance
    end
    if ui and ui.httpinspector then
        if ui.httpinspector:isRunning() then
            ui.httpinspector:stop()
            UIManager:show(Notification:new{
                text = _("HTTP server stopped"),
                timeout = 2,
            })
        else
            ui.httpinspector:start()
            UIManager:show(Notification:new{
                text = _("HTTP server started"),
                timeout = 2,
            })
        end
    else
        UIManager:show(InfoMessage:new{
            text = _("httpinspector plugin instance not found. Please check if the plugin is installed or modify the action registration to accommodate the updated plugin."),
            timeout = 2,
        })
    end
end)

-- Font list
registerAction("fontlist", _("Font list"), "nerd:F031", false, "reader", function(ctx)
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    local UIManager = require("ui/uimanager")
    local ButtonDialog = require("ui/widget/buttondialog")
    local FontList = require("fontlist")
    local Event = require("ui/event")
    local Screen = require("device").screen
    local cre = require("document/credocument"):engineInit()
    
    if not reader then
        UIManager:show(InfoMessage:new{
            text = _("Please open a book first"),
            timeout = 2,
        })
        return
    end
    
    if ctx and ctx.touch_menu then
        ctx.touch_menu:onClose()
    end
    
    local face_list = cre.getFontFaces()
    local buttons = {}
    
    table.sort(face_list, function(a, b)
        return a:lower() < b:lower()
    end)
    
    local current_font = reader.view.font_face or G_reader_settings:readSetting("cre_font")
    
    -- Create font_dialog variable first
    local font_dialog = nil
    
    for idx, face in ipairs(face_list) do
        local font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(face)
        if not font_filename then
            font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(face, nil, true)
        end
        local display_name = face
        if font_filename and font_faceindex then
            display_name = FontList:getLocalizedFontName(font_filename, font_faceindex) or face
        end
        local is_checked = (face == current_font)
        table.insert(buttons, {{
            text = display_name .. (is_checked and "  ✓" or ""),
            callback = function()
                -- Close font list dialog first
                if font_dialog then
                    UIManager:close(font_dialog)
                    font_dialog = nil
                end
                
                if reader and reader.view then
                    reader.view.font_face = face
                    reader.view.ui.document:setFontFace(face)
                    reader.view.ui:handleEvent(Event:new("UpdatePos"))
                    if reader.view.ui.doc_settings then
                        reader.view.ui.doc_settings:saveSetting("font_face", face)
                    end
                    UIManager:show(Notification:new{
                        text = string.format(_("Font set to: %s"), display_name),
                        timeout = 2,
                    })
                end
            end,
        }})
    end
    
    font_dialog = ButtonDialog:new{
        title = _("Select font"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
        rows_per_page = 10,
    }
    UIManager:show(font_dialog)
end)

registerAction("qa_settings", _("Quick Actions Settings"), "nerd:F0CA", false, "common", function(ctx)
    showSettingsMenu()
end)

registerAction("qa_new", _("New quick action"), "nerd:F067", false, "common", function()
    showCustomQADialog(nil, function()
        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        if fm and fm.menu and fm.menu.menu_container and fm.menu.menu_container[1] then
            fm.menu.menu_container[1]:updateItems()
        end
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance
        if reader and reader.menu and reader.menu.menu_container and reader.menu.menu_container[1] then
            reader.menu.menu_container[1]:updateItems()
        end
    end)
end)

-- UI font switcher
registerAction("ui_font_switch", _("Switch UI font"), "nerd:5B57", true, "common", function(ctx)
    showUIFontSwitcher()
end)

registerAction("qa_add_button", _("Add button"), "nerd:F055", false, "common", function()
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local touch_menu = nil
    if fm and fm.menu and fm.menu.menu_container and fm.menu.menu_container[1] then
        touch_menu = fm.menu.menu_container[1]
    else
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance
        if reader and reader.menu and reader.menu.menu_container and reader.menu.menu_container[1] then
            touch_menu = reader.menu.menu_container[1]
        end
    end
    showAddButtonMenu(touch_menu)
end)

-- Built-in external plugin and patch quick actions

-- Patch: 2-fm-cover.lua (cover visual settings)
registerAction("fmcoversettings", _("Cover visual settings"), "nerd:E22F", false, "filemanager", function()
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    if reader then
        UIManager:show(InfoMessage:new{
            text = _("This feature is only available in the file manager"),
            timeout = 2,
        })
    else
        local UIManager = require("ui/uimanager")
        local Event = require("ui/event")
        UIManager:broadcastEvent(Event:new("FMCoverSettings"))
    end
end)

-- Patch: 2-reader-clozemode.lua (cloze mode)
registerAction("toggle_cloze_mode", _("Cloze mode"), "nerd:F040", false, "reader", function(ctx)
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    
    if reader then
        -- Broadcast event for clozemode patch to handle
        UIManager:broadcastEvent(Event:new("Toggleclozemode"))
        -- Refresh panel to update icon
        if ctx and ctx.touch_menu then
            ctx.touch_menu:updateItems()
        end
    else
        UIManager:show(InfoMessage:new{
            text = _("Please open a book first"),
            timeout = 2,
        })
    end
end)

-- Patch: 2-reading-insights-dashboard-v2 (statistics)
registerAction("reading_insights", _("Reading Insights"), "nerd:F073", false, "common", function(ctx)
    UIManager:broadcastEvent(Event:new("ShowReadingInsightsPopup"))
end)

-- Plugin: filebrowserplus.koplugin
registerAction("filebrowserplus", _("FilebrowserPlus"), "nerd:F029", true, "common", function()
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    local plugin = nil
    if fm and fm.filebrowserplus then
        plugin = fm.filebrowserplus
    elseif reader and reader.filebrowserplus then
        plugin = reader.filebrowserplus
    end
    if plugin then
        if plugin:isRunning() then
            plugin:stop()
        else
            plugin:start()
        end
    else
        UIManager:show(InfoMessage:new{
            text = _("filebrowserplus plugin instance or method not found. Please check if the plugin is installed or modify the action registration to accommodate the updated plugin."),
            timeout = 2,
        })
    end
end)

-- Plugin: zlibrary.koplugin
registerAction("zlibrary_search", _("ZLibrary search"), "nerd:005A", false, "common", function()
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    local plugin = nil
    if fm and fm.zlibrary then
        plugin = fm.zlibrary
    elseif reader and reader.zlibrary then
        plugin = reader.zlibrary
    end
    if plugin and plugin.onZlibrarySearch then
        plugin:onZlibrarySearch()
    else
        UIManager:show(InfoMessage:new{
            text = _("zlibrary plugin instance or method not found. Please check if the plugin is installed or modify the action registration to accommodate the updated plugin."),
            timeout = 2,
        })
    end
end)

-- Plugin: cloudlibrary.koplugin
registerAction("cloudlibrary_autosync", _("CloudLibrary - Auto sync"), "nerd:E33B", false, "common", function()
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    local plugin = nil
    if fm and fm.CloudLibrary then
        plugin = fm.CloudLibrary
    elseif reader and reader.CloudLibrary then
        plugin = reader.CloudLibrary
    end
    if plugin then
        plugin:toggleAutoSyncQuick()
    else
        UIManager:show(InfoMessage:new{
            text = _("cloudLibrary plugin instance or method not found. Please check if the plugin is installed or modify the action registration to accommodate the updated plugin."),
            timeout = 2,
        })
    end
end)

-- Plugin: cloudlibrary.koplugin
registerAction("cloudlibrary_batch_download_books", _("CloudLibrary - Batch download/delete"), "nerd:E33A", false, "common", function()
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    local plugin = nil
    if fm and fm.CloudLibrary then
        plugin = fm.CloudLibrary
    elseif reader and reader.CloudLibrary then
        plugin = reader.CloudLibrary
    end
    if plugin then
        plugin:batchDownloadBooks()
    else
        UIManager:show(InfoMessage:new{
            text = _("cloudLibrary plugin instance or method not found. Please check if the plugin is installed or modify the action registration to accommodate the updated plugin."),
            timeout = 2,
        })
    end
end)

-- Plugin: cloudlibrary.koplugin
registerAction("cloudlibrary_settings", _("CloudLibrary - Settings"), "nerd:E33D", false, "common", function()
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    local plugin = nil
    if fm and fm.CloudLibrary then
        plugin = fm.CloudLibrary
    elseif reader and reader.CloudLibrary then
        plugin = reader.CloudLibrary
    end
    if plugin then
        if reader then
            plugin:onCloudLibrarySettingsReader()
        else
            plugin:onCloudLibrarySettingsFileManager()
        end
    else
        UIManager:show(InfoMessage:new{
            text = _("cloudLibrary plugin instance or method not found. Please check if the plugin is installed or modify the action registration to accommodate the updated plugin."),
            timeout = 2,
        })
    end
end)

-- Plugin: annotationsviewer.koplugin
registerAction("annotations_viewer", _("Annotations Viewer"), "nerd:F040", false, "common", function()
    local UIManager = require("ui/uimanager")
    local Event = require("ui/event")
    local RUI = require("apps/reader/readerui")
    local FM = require("apps/filemanager/filemanager")
    
    local reader = RUI and RUI.instance
    local fm = FM and FM.instance
    
    -- Check if plugin is installed
    local has_plugin = false
    if reader and reader.annotationsviewer then
        has_plugin = true
    elseif fm and fm.annotationsviewer then
        has_plugin = true
    end
    
    if not has_plugin then
        UIManager:show(InfoMessage:new{
            text = _("annotationsviewer plugin not installed"),
            timeout = 2,
        })
        return
    end
    
    -- Execute action
    if reader then
        UIManager:broadcastEvent(Event:new("ShowCurrentBookAnnotations"))
    else
        UIManager:broadcastEvent(Event:new("ShowAllAnnotations"))
    end
end)

-- ============================================================
-- Interface-specific configuration (view management)
-- ============================================================

local function isMenuAction(action_id)
    local custom = getTable("custom")
    local cfg = custom and custom[action_id]
    return cfg and cfg.action_type == "menu"
end

local function getActionViewFinal(action_id)
    if not action_id then return "common" end
    local overrides = getTable("builtin_overrides")
    if overrides and overrides[action_id] and overrides[action_id].view then
        return overrides[action_id].view
    end
    local custom = getTable("custom")
    local cfg = custom and custom[action_id]
    if cfg then
        if cfg.action_type == "menu" and cfg.menu_path and cfg.menu_path.view then
            return cfg.menu_path.view
        end
        if cfg.view then
            return cfg.view
        end
    end
    if ACTION_REGISTRY and ACTION_REGISTRY[action_id] then
        return ACTION_REGISTRY[action_id].view or "common"
    end
    return "common"
end

local function setCustomActionView(action_id, view)
    local custom = getTable("custom")
    local cfg = custom[action_id]
    if not cfg then return end
    cfg.view = view
    setTable("custom", custom)
end

local function toggleDedicated(action_id, target_view)
    if isMenuAction(action_id) then
        return
    end
    local current_view = getActionViewFinal(action_id)
    local is_builtin = ACTION_REGISTRY and ACTION_REGISTRY[action_id] ~= nil
    if current_view == target_view then
        if is_builtin then
            local overrides = getTable("builtin_overrides")
            if not overrides[action_id] then
                overrides[action_id] = {}
            end
            overrides[action_id].view = "common"
            setTable("builtin_overrides", overrides)
        else
            setCustomActionView(action_id, "common")
        end
    else
        if is_builtin then
            local overrides = getTable("builtin_overrides")
            if not overrides[action_id] then
                overrides[action_id] = {}
            end
            overrides[action_id].view = target_view
            setTable("builtin_overrides", overrides)
        else
            setCustomActionView(action_id, target_view)
        end
    end
end

local function getActionSymbol(id)
    local is_builtin = false
    if ACTION_ORDER then
        for _, builtin_id in ipairs(ACTION_ORDER) do
            if builtin_id == id then
                is_builtin = true
                break
            end
        end
    end
    if is_builtin then
        local circle_char = nerdIconChar("nerd:E002") or "○"
        return circle_char .. " "
    end
    local cfg = getTable("custom")[id]
    if cfg then
        if cfg.action_type == "dispatcher" then
            return "⊕ "
        elseif cfg.action_type == "plugin" then
            return "⬡ "
        elseif cfg.action_type == "collection" then
            return "⊞ "
        elseif cfg.action_type == "menu" then
            return "⊚ "
        elseif cfg.action_type == "folder" then
            return "◇ "
        else
            return "● "
        end
    end
    return "● "
end

local function getTypePriority(id)
    local cfg = getTable("custom")[id]
    if cfg then
        if cfg.action_type == "menu" then
            return 1
        elseif cfg.action_type == "dispatcher" then
            return 2
        elseif cfg.action_type == "plugin" then
            return 3
        elseif cfg.action_type == "folder" then
            return 4
        elseif cfg.action_type == "collection" then
            return 5
        else
            return 6
        end
    end
    if ACTION_ORDER then
        for _, builtin_id in ipairs(ACTION_ORDER) do
            if builtin_id == id then
                return 7
            end
        end
    end
    return 8
end

local function getAllActionsForFilter()
    local all = {}
    if ACTION_ORDER then
        for i = 1, #ACTION_ORDER do
            local id = ACTION_ORDER[i]
            if id then
                local action = getAction(id)
                all[#all + 1] = {
                    id = id,
                    label = getLabelForAction(id),
                    view = getActionViewFinal(id),
                    is_builtin = true,
                }
            end
        end
    end
    local custom_list = getSetting("custom_list")
    if type(custom_list) == "table" then
        for i = 1, #custom_list do
            local id = custom_list[i]
            local cfg = getTable("custom")[id]
            if cfg then
                local view = cfg.view or "common"
                if cfg.action_type == "menu" and cfg.menu_path and cfg.menu_path.view then
                    view = cfg.menu_path.view
                end
                all[#all + 1] = {
                    id = id,
                    label = cfg.label,
                    view = view,
                    is_builtin = false,
                }
            end
        end
    end
    return all
end

local function getAllAvailableActions()
    local available = {}
    if ACTION_ORDER then
        for i = 1, #ACTION_ORDER do
            local id = ACTION_ORDER[i]
            if id then
                available[#available + 1] = {
                    id = id,
                    label = getLabelForAction(id),
                    is_builtin = true,
                    view = getActionViewFinal(id),
                }
            end
        end
    end
    local custom_list = getSetting("custom_list")
    if type(custom_list) == "table" then
        for i = 1, #custom_list do
            local id = custom_list[i]
            local cfg = getTable("custom")[id]
            if cfg then
                local view = cfg.view or "common"
                if cfg.action_type == "menu" and cfg.menu_path and cfg.menu_path.view then
                    view = cfg.menu_path.view
                end
                available[#available + 1] = {
                    id = id,
                    label = cfg.label,
                    is_builtin = false,
                    view = view,
                }
            end
        end
    end
    return available
end

local function isActionVisible(action_id, current_view)
    if not getBool("qa_context_filter") then return true end
    local view = getActionViewFinal(action_id)
    if current_view == "filemanager" then
        return view == "filemanager" or view == "common"
    elseif current_view == "reader" then
        return view == "reader" or view == "common"
    end
    return true
end

local function getDefaultViewForActionType(action_type, action_value)
    if action_type == "folder" or action_type == "collection" then
        return "filemanager"
    elseif action_type == "plugin" then
        return "common"
    elseif action_type == "dispatcher" then
        if not action_value then return "common" end
        local ok, DispatcherMod = pcall(require, "dispatcher")
        if ok and DispatcherMod then
            local settingsList
            local fn_idx = 1
            while true do
                local name, val = debug.getupvalue(DispatcherMod.registerAction, fn_idx)
                if not name then break end
                if name == "settingsList" then settingsList = val end
                fn_idx = fn_idx + 1
            end
            local def = settingsList and settingsList[action_value]
            if def then
                if def.filemanager then return "filemanager" end
                if def.reader or def.rolling or def.paging then return "reader" end
            end
        end
        return "common"
    elseif action_type == "menu" then
        if not action_value or type(action_value) ~= "table" then return "common" end
        return action_value.view or "common"
    end
    return "common"
end

-- ============================================================
-- Utility functions
-- ============================================================

local function getCollectionsList()
    local ok, RC = pcall(require, "readcollection")
    if not ok or not RC then return {} end
    pcall(RC._read, RC)
    local collections = {}
    if RC.coll then
        for name in pairs(RC.coll) do
            if name ~= RC.default_collection_name then
                collections[#collections + 1] = name
            end
        end
    end
    table.sort(collections, function(a, b) return a:lower() < b:lower() end)
    return collections
end

-- ============================================================
-- Plugin discovery helper functions (defined before getPluginsList)
-- ============================================================

-- Detect plugin call method
local function _detectPluginMethod(val, key)
    -- Try common method names
    for _, pfx in ipairs({"onShow","show","open","launch","onOpen"}) do
        if type(val[pfx]) == "function" then return pfx end
    end
    
    -- Try on + capitalized first letter
    local cap = "on" .. key:sub(1,1):upper() .. key:sub(2)
    if type(val[cap]) == "function" then return cap end
    
    -- Extract callback via addToMainMenu
    if type(val.addToMainMenu) == "function" then
        local probe = {}
        local ok = pcall(function() val:addToMainMenu(probe) end)
        if ok then
            local entry = probe[key] or probe[val.name]
            if entry and type(entry.callback) == "function" then
                val._qa_launch = function() entry.callback() end
                return "_qa_launch"
            end
        end
    end
    
    return nil
end

-- Get plugin display name
local function _getPluginDisplayName(val, key)
    local raw = (val.name or key):gsub("^filemanager", ""):gsub("^reader", "")
    local display = raw:sub(1,1):upper() .. raw:sub(2)
    if display == "" or display == key then
        display = key:gsub("^filemanager", ""):gsub("^reader", "")
        display = display:sub(1,1):upper() .. display:sub(2)
    end
    
    -- Try to get better display name from addToMainMenu
    if type(val.addToMainMenu) == "function" then
        local probe = {}
        local ok = pcall(function() val:addToMainMenu(probe) end)
        if ok then
            local entry = probe[key] or probe[val.name]
            if entry and type(entry.text) == "string" and entry.text ~= "" then
                display = entry.text
            end
        end
    end
    
    return display
end

-- ============================================================
-- Plugin list (defined after helper functions)
-- ============================================================

local function getPluginsList()
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    
    local results = {}
    local seen = {}
    
    -- 1. Predefined known plugins (fallback)
    local known = {
        -- FM plugins
        { key = "history", method = "onShowHist", title = _("History"), source = "fm" },
        { key = "collections", method = "onShowCollList", title = _("Collections list"), source = "fm" },
        { key = "filesearcher", method = "onShowFileSearch", title = _("File search"), source = "fm" },
        { key = "dictionary", method = "onShowDictionaryLookup", title = _("Dictionary"), source = "fm" },
        { key = "folder_shortcuts", method = "onShowFolderShortcutsDialog", title = _("Folder shortcuts"), source = "fm" },
        { key = "bookinfo", method = "onShowBookInfo", title = _("Book info"), source = "fm" },
        { key = "wikipedia", method = "onShowWikipediaLookup", title = _("Wikipedia lookup"), source = "fm" },
        -- ReaderUI plugins
        { key = "bookmark", method = "onShowBookmarks", title = _("Bookmarks"), source = "reader" },
        { key = "highlight", method = "onShowHighlights", title = _("Highlights"), source = "reader" },
        { key = "search", method = "onShowSearch", title = _("Search"), source = "reader" },
    }
    
    for _, entry in ipairs(known) do
        local target = (entry.source == "reader") and reader or fm
        if target then
            local mod = target[entry.key]
            if mod and type(mod[entry.method]) == "function" then
                results[#results + 1] = {
                    key = entry.key,
                    method = entry.method,
                    title = entry.title,
                    source = entry.source,
                }
                seen[entry.key] = true
            end
        end
    end
    
    -- 2. Dynamically scan FM plugins
    if fm then
        local native_keys = {
            screenshot=true, menu=true, history=true, bookinfo=true, collections=true,
            filesearcher=true, folder_shortcuts=true, languagesupport=true,
            dictionary=true, wikipedia=true, devicestatus=true, devicelistener=true,
            networklistener=true,
        }
        local fm_val_to_key = {}
        for k, v in pairs(fm) do
            if type(k) == "string" and type(v) == "table" then fm_val_to_key[v] = k end
        end
        
        for i = 1, #fm do
            local val = fm[i]
            if type(val) ~= "table" or type(val.name) ~= "string" then goto continue_fm end
            
            local fm_key = fm_val_to_key[val]
            if not fm_key or native_keys[fm_key] or seen[fm_key] then goto continue_fm end
            
            seen[fm_key] = true
            local method = _detectPluginMethod(val, fm_key)
            if method then
                results[#results + 1] = {
                    key = fm_key,
                    method = method,
                    title = _getPluginDisplayName(val, fm_key),
                    source = "fm",
                }
            end
            ::continue_fm::
        end
    end
    
    -- 3. Dynamically scan ReaderUI plugins
    if reader then
        local reader_native_keys = {
            menu=true, bookmark=true, highlight=true, search=true,
            progress=true, dictionary=true, wikipedia=true,
        }
        local reader_val_to_key = {}
        for k, v in pairs(reader) do
            if type(k) == "string" and type(v) == "table" then reader_val_to_key[v] = k end
        end
        
        for i = 1, #reader do
            local val = reader[i]
            if type(val) ~= "table" or type(val.name) ~= "string" then goto continue_reader end
            
            local r_key = reader_val_to_key[val]
            if not r_key or reader_native_keys[r_key] or seen[r_key] then goto continue_reader end
            
            seen[r_key] = true
            local method = _detectPluginMethod(val, r_key)
            if method then
                results[#results + 1] = {
                    key = r_key,
                    method = method,
                    title = _getPluginDisplayName(val, r_key),
                    source = "reader",
                }
            end
            ::continue_reader::
        end
    end
    
    table.sort(results, function(a, b) return a.title:lower() < b.title:lower() end)
    return results
end

local function getDispatcherActions()
    local ok, DispatcherMod = pcall(require, "dispatcher")
    if not ok or not DispatcherMod then return {} end
    pcall(DispatcherMod.init, DispatcherMod)
    local settingsList, dispatcher_menu_order
    local fn_idx = 1
    while true do
        local name, val = debug.getupvalue(DispatcherMod.registerAction, fn_idx)
        if not name then break end
        if name == "settingsList" then settingsList = val end
        if name == "dispatcher_menu_order" then dispatcher_menu_order = val end
        fn_idx = fn_idx + 1
    end
    if type(settingsList) ~= "table" then return {} end
    local order = (type(dispatcher_menu_order) == "table" and dispatcher_menu_order)
        or (function()
            local keys = {}
            for key in pairs(settingsList) do keys[#keys + 1] = key end
            table.sort(keys)
            return keys
        end)()
    local sections = {
        { key = "general",     title = _("General") },
        { key = "device",      title = _("Device") },
        { key = "screen",      title = _("Screen and lighting") },
        { key = "filemanager", title = _("File browser") },
        { key = "reader",      title = _("Reader") },
        { key = "rolling",     title = _("Re-flowable documents (epub, fb2, txt…)") },
        { key = "paging",      title = _("Fixed-layout documents (pdf, djvu, images…)") },
    }
    local sections_map = {}
    for _, sec in ipairs(sections) do
        sections_map[sec.key] = { title = sec.title, items = {} }
    end
    for _, action_id in ipairs(order) do
        local def = settingsList[action_id]
        if type(def) == "table" and def.title and def.category
                and (def.condition == nil or def.condition == true) then
            local section_key = "general"
            for _, sec in ipairs(sections) do
                if def[sec.key] == true then
                    section_key = sec.key
                    break
                end
            end
            table.insert(sections_map[section_key].items, {
                id = action_id,
                title = tostring(def.title),
                category = def.category,
            })
        end
    end
    local result = {}
    for _, sec in ipairs(sections) do
        for _, item in ipairs(sections_map[sec.key].items) do
            item.section = sec.title
            table.insert(result, item)
        end
    end
    return result
end

-- ============================================================
-- Delete and remove functions
-- ============================================================

local function deleteCustomQA(qa_id)
    CONFIG_DATA = nil
    loadConfig()
    local custom = getTable("custom")
    custom[qa_id] = nil
    setTable("custom", custom)
    local list = getSetting("custom_list")
    if type(list) ~= "table" then list = {} end
    local new_list = {}
    for _, id in ipairs(list) do
        if id ~= qa_id then new_list[#new_list + 1] = id end
    end
    setSetting("custom_list", new_list)
end

function removeFromPanel(action_id, touch_menu)
    local slots = getQASlots()
    local found = false
    local new_slots = {}
    for _, sid in ipairs(slots) do
        if sid == action_id then
            found = true
        else
            new_slots[#new_slots + 1] = sid
        end
    end
    if not found then
        UIManager:show(Notification:new{
            text = _("Button not found in quick actions tab"),
            timeout = 2,
        })
        return false
    end
    saveQASlots(new_slots)
    if touch_menu then
        touch_menu:updateItems()
    end
    return true
end

-- ============================================================
-- Generic menu display framework
-- ============================================================

local function showMenu(items, title, parent_stack, touch_menu, root_items)
    local buttons = {}
    if parent_stack and #parent_stack > 0 then
        if #parent_stack > 1 then
            table.insert(buttons, {
                {
                    text = "◂◂ " .. _("Return to root menu"),
                    callback = function()
                        closeSettingsDialog()
                        showMenu(root_items, _("Quick Actions Settings"), nil, touch_menu, root_items)
                    end
                }
            })
        end
        table.insert(buttons, {
            {
                text = "◂ " .. _("Back"),
                callback = function()
                    local parent = parent_stack[#parent_stack]
                    closeSettingsDialog()
                    showMenu(parent.items, parent.title, parent.parent_stack, touch_menu, root_items)
                end
            }
        })
        table.insert(buttons, {})
    end
    for i = 1, #items do
        local item = items[i]
        local sub_table = item.sub_item_table
        if type(sub_table) == "function" then
            sub_table = sub_table()
        end
        if sub_table and type(sub_table) == "table" and #sub_table > 0 then
            local display_text = item.text
            if type(display_text) == "function" then
                display_text = display_text()
            end
            table.insert(buttons, {
                {
                    text = display_text .. " ▸",
                    callback = function()
                        if _settings_dialog then
                            UIManager:close(_settings_dialog)
                            _settings_dialog = nil
                        end
                        local new_stack = {}
                        if parent_stack then
                            for _, v in ipairs(parent_stack) do
                                table.insert(new_stack, v)
                            end
                        end
                        table.insert(new_stack, {
                            items = items,
                            title = title,
                            parent_stack = parent_stack
                        })
                        showMenu(sub_table, display_text, new_stack, touch_menu, root_items)
                    end
                }
            })
        else
            local checked = item.checked_func and item.checked_func() or false
            local display_text = item.text
            if type(display_text) == "function" then
                display_text = display_text()
            end
            local prefix = (checked and "✓ " or "  ")
            local enabled = (item.enabled == nil) or (type(item.enabled) == "function" and item.enabled()) or item.enabled
            table.insert(buttons, {
                {
                    text = prefix .. display_text,
                    enabled = enabled,
                    callback = function()
                        if item.callback then
                            item.callback()
                        end
                        if item.close_on_click then
                            closeSettingsDialog()
                        else
                            closeSettingsDialog()
                            refreshQuickPanel(touch_menu)
                            showMenu(items, title, parent_stack, touch_menu, root_items)
                        end
                    end
                }
            })
        end
    end
    local dialog = ButtonDialog:new{
        title = title or _("Quick Actions Settings"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    _settings_dialog = dialog
    UIManager:show(dialog)
end

-- ============================================================
-- Settings menu
-- ============================================================

local function showEditActionDialog(action_id, on_done)
    local action = getAction(action_id)
    if not action then return end

    local current_label = action.label
    local current_icon = action.icon
    local current_view = getActionViewFinal(action_id)
    local active_dialog = nil

    local view_options = { "common", "filemanager", "reader" }
    local view_labels = {
        common = _("General"),
        filemanager = _("File manager"),
        reader = _("Reader"),
    }

    local function getCurrentPosition()
        local slots = getQASlots()
        for i, id in ipairs(slots) do
            if id == action_id then
                return i, #slots
            end
        end
        return nil, #slots
    end

    local function rebuildDialog()
        if active_dialog then
            UIManager:close(active_dialog)
            active_dialog = nil
        end

        local function iconButtonText()
            if not current_icon then return _("Icon: default (tap to change)") end
            local nerd_char = nerdIconChar(current_icon)
            if nerd_char then
                local hex = current_icon:match("nerd:(.+)")
                return _("Icon") .. ": " .. nerd_char .. " (" .. hex .. ")"
            end
            local fname = current_icon:match("([^/]+)$") or current_icon
            local stem = (fname:match("^(.+)%.[^%.]+$") or fname):gsub("_", " ")
            return _("Icon") .. ": " .. stem
        end

        local function viewButtonText()
            return _("Interface") .. ": " .. view_labels[current_view]
        end

        local fields = {
            { description = _("Name"), text = current_label, hint = _("Action name…") }
        }

        local pos, total = getCurrentPosition()

        -- Build last row
        local last_row = {
            { text = _("Cancel"), callback = function()
                UIManager:close(active_dialog)
                active_dialog = nil
            end },
        }

        -- Remove
        table.insert(last_row, { text = _("Remove"), callback = function()
            if active_dialog then
                local inputs = active_dialog:getFields()
                if inputs and inputs[1] then
                    current_label = inputs[1]
                end
                UIManager:close(active_dialog)
                active_dialog = nil
            end
            removeFromPanel(action_id, nil)
            if on_done then on_done() end
        end })

        -- Move left: show if pos exists, grayed out if pos=1
        if pos then
            table.insert(last_row, { text = "◀", enabled = (pos > 1), callback = function()
                if active_dialog then
                    local inputs = active_dialog:getFields()
                    if inputs and inputs[1] then
                        current_label = inputs[1]
                    end
                    UIManager:close(active_dialog)
                    active_dialog = nil
                end
                local slots = getQASlots()
                local idx = nil
                for i, id in ipairs(slots) do
                    if id == action_id then
                        idx = i
                        break
                    end
                end
                if idx and idx > 1 then
                    slots[idx], slots[idx-1] = slots[idx-1], slots[idx]
                    saveQASlots(slots)
                end
                rebuildDialog()
            end })
        end

        -- Position button: show if pos exists, tap to open reorder dialog
        if pos then
            table.insert(last_row, { text = pos .. "/" .. total, callback = function()
                UIManager:close(active_dialog)
                active_dialog = nil
                local slots = getQASlots()
                local sort_items = {}
                for i, id in ipairs(slots) do
                    sort_items[#sort_items + 1] = { text = getLabelForAction(id), orig_item = id }
                end
                local sort_dialog = SortWidget:new{
                    title = _("Reorder buttons"),
                    item_table = sort_items,
                    covers_fullscreen = true,
                    callback = function()
                        local new_slots = {}
                        for j = 1, #sort_items do
                            new_slots[#new_slots + 1] = sort_items[j].orig_item
                        end
                        saveQASlots(new_slots)
                        if on_done then on_done() end
                    end,
                }
                UIManager:show(sort_dialog)
            end })
        end

        -- Move right: show if pos exists, grayed out if pos=total
        if pos then
            table.insert(last_row, { text = "▶", enabled = (pos < total), callback = function()
                if active_dialog then
                    local inputs = active_dialog:getFields()
                    if inputs and inputs[1] then
                        current_label = inputs[1]
                    end
                    UIManager:close(active_dialog)
                    active_dialog = nil
                end
                local slots = getQASlots()
                local idx = nil
                for i, id in ipairs(slots) do
                    if id == action_id then
                        idx = i
                        break
                    end
                end
                if idx and idx < #slots then
                    slots[idx], slots[idx+1] = slots[idx+1], slots[idx]
                    saveQASlots(slots)
                end
                rebuildDialog()
            end })
        end

        table.insert(last_row, { text = _("Save"), is_enter_default = true, callback = function()
            if not active_dialog then return end
            local inputs = active_dialog:getFields()
            local new_label = inputs[1] or ""
            if new_label == "" then
                UIManager:show(InfoMessage:new{ text = _("Please enter a name"), timeout = 2 })
                return
            end
            UIManager:close(active_dialog)
            active_dialog = nil
            local builtin_overrides = getTable("builtin_overrides")
            if not builtin_overrides[action_id] then
                builtin_overrides[action_id] = {}
            end
            builtin_overrides[action_id].label = new_label
            builtin_overrides[action_id].icon = current_icon
            builtin_overrides[action_id].view = current_view
            setTable("builtin_overrides", builtin_overrides)
            if on_done then on_done() end
        end })

        local buttons = {
            { { text = iconButtonText(), callback = function()
                if active_dialog then
                    local inputs = active_dialog:getFields()
                    if inputs and inputs[1] then
                        current_label = inputs[1]
                    end
                    UIManager:close(active_dialog)
                    active_dialog = nil
                end
                showIconPicker(function(new_icon)
                    current_icon = new_icon
                    rebuildDialog()
                end, current_icon)
            end } },
            { { text = viewButtonText(), callback = function()
                if active_dialog then
                    local inputs = active_dialog:getFields()
                    if inputs and inputs[1] then
                        current_label = inputs[1]
                    end
                    UIManager:close(active_dialog)
                    active_dialog = nil
                end
                local view_buttons = {}
                for _, v in ipairs(view_options) do
                    local _v = v
                    table.insert(view_buttons, {{
                        text = (current_view == _v and "✓ " or "  ") .. view_labels[_v],
                        callback = function()
                            UIManager:close(view_dialog)
                            current_view = _v
                            rebuildDialog()
                        end,
                    }})
                end
                table.insert(view_buttons, {{
                    text = _("Back"),
                    callback = function()
                        UIManager:close(view_dialog)
                        rebuildDialog()
                    end,
                }})
                view_dialog = ButtonDialog:new{
                    title = _("Select interface"),
                    title_align = "center",
                    buttons = view_buttons,
                }
                UIManager:show(view_dialog)
            end } },
            last_row,
        }

        active_dialog = MultiInputDialog:new{
            title = _("Edit quick action"),
            fields = fields,
            tap_close_callback = function()
                UIManager:close(active_dialog)
                active_dialog = nil
            end,
            buttons = buttons,
        }
        UIManager:show(active_dialog)
        pcall(function() active_dialog:onShowKeyboard() end)
    end

    rebuildDialog()
end

local function getCustomItems(touch_menu)
    local items = {}
    if ACTION_ORDER then
        for i = 1, #ACTION_ORDER do
            local id = ACTION_ORDER[i]
            if id then
                local label = getLabelForAction(id)
                local view_tag = " [" .. getActionViewFinal(id) .. "]"
                local symbol = getActionSymbol(id)
                items[#items + 1] = {
                    id = id,
                    text = symbol .. label .. view_tag,
                    is_builtin = true,
                    on_edit = function()
                        showEditActionDialog(id, function() 
                            refreshQuickPanel(touch_menu)
                        end)
                    end,
                    on_delete = nil,
                }
            end
        end
    end
    local custom_list = getSetting("custom_list")
    if type(custom_list) ~= "table" then custom_list = {} end
    for i = 1, #custom_list do
        local id = custom_list[i]
        local cfg = getTable("custom")[id]
        if cfg then
            local symbol = getActionSymbol(id)
            local view_tag = " [" .. (cfg.view or "common") .. "]"
            items[#items + 1] = {
                id = id,
                text = symbol .. cfg.label .. view_tag,
                is_builtin = false,
                on_edit = function()
                    showCustomQADialog(id, function() 
                        refreshQuickPanel(touch_menu)
                    end)
                end,
                on_delete = function()
                    deleteCustomQA(id)
                    refreshQuickPanel(touch_menu)
                end,
            }
        end
    end
    local result = {}
    for _, item in ipairs(items) do
        if not item.is_builtin then
            table.insert(result, item)
        end
    end
    table.sort(result, function(a, b) return a.text:lower() < b.text:lower() end)
    for _, item in ipairs(items) do
        if item.is_builtin then
            table.insert(result, 1, item)
        end
    end
    return result
end

-- ============================================================
-- Add button menu
-- ============================================================

function showAddButtonMenu(touch_menu, on_back)
    local current_dialog = nil
    local slots = getQASlots()
    local slot_set = {}
    for _, id in ipairs(slots) do
        slot_set[id] = true
    end
    local available = getAllAvailableActions()
    table.sort(available, function(a, b)
        local a_checked = slot_set[a.id] or false
        local b_checked = slot_set[b.id] or false
        if a_checked ~= b_checked then
            return a_checked
        end
        local a_prio = getTypePriority(a.id)
        local b_prio = getTypePriority(b.id)
        if a_prio ~= b_prio then
            return a_prio < b_prio
        end
        return a.label:lower() < b.label:lower()
    end)
    local buttons = {}
    
    if on_back then
        table.insert(buttons, {
            {
                text = "◂ " .. _("Back"),
                callback = function()
                    UIManager:close(current_dialog)
                    on_back()
                end
            }
        })
        table.insert(buttons, {})
    else
        table.insert(buttons, {
            {
                text = "⚙ " .. _("Open main menu"),
                callback = function()
                    UIManager:close(current_dialog)
                    showSettingsMenu(touch_menu)
                end
            }
        })
        table.insert(buttons, {})
    end
    
    local show_fl = showFrontlight()
    table.insert(buttons, {
        {
            text = (show_fl and "✓ " or "  ") .. _("Frontlight slider"),
            callback = function()
                setBool("qa_frontlight", not showFrontlight())
                if touch_menu then touch_menu:updateItems() end
                UIManager:close(current_dialog)
                showAddButtonMenu(touch_menu, on_back)
            end,
        }
    })
    if Device:hasNaturalLight() then
        local show_wl = showWarmth()
        table.insert(buttons, {
            {
                text = (show_wl and "✓ " or "  ") .. _("Warmth slider"),
                callback = function()
                    setBool("qa_warmth", not showWarmth())
                    if touch_menu then touch_menu:updateItems() end
                    UIManager:close(current_dialog)
                    showAddButtonMenu(touch_menu, on_back)
                end,
            }
        })
    end
    local show_slider_val = showSliderValue()
    table.insert(buttons, {
        {
            text = (show_slider_val and "✓ " or "  ") .. _("Show slider value"),
            callback = function()
                setBool("qa_slider_show_value", not showSliderValue())
                if touch_menu then touch_menu:updateItems() end
                UIManager:close(current_dialog)
                showAddButtonMenu(touch_menu, on_back)
            end,
        }
    })
    
    -- Select all / deselect all button
    local function getAllChecked()
        for _, action in ipairs(available) do
            if not slot_set[action.id] then
                return false
            end
        end
        return true
    end
    
    local all_checked = getAllChecked()
    table.insert(buttons, {
        {
            text = all_checked and "☑ " .. _("Deselect all") or "☐ " .. _("Select all"),
            callback = function()
                local is_all_checked = getAllChecked()
                local current_slots = getQASlots()
                local new_slots = {}
                
                if is_all_checked then
                    -- Deselect all: only keep buttons not in available (e.g., frontlight, warmth)
                    for _, id in ipairs(current_slots) do
                        local is_available = false
                        for _, action in ipairs(available) do
                            if action.id == id then
                                is_available = true
                                break
                            end
                        end
                        if not is_available then
                            table.insert(new_slots, id)
                        end
                    end
                else
                    -- Select all: keep existing buttons, add all unchecked
                    for _, id in ipairs(current_slots) do
                        table.insert(new_slots, id)
                    end
                    
                    for _, action in ipairs(available) do
                        if not slot_set[action.id] then
                            if #new_slots >= MAX_SLOTS then
                                UIManager:show(Notification:new{
                                    text = string.format(_("Maximum %d buttons"), MAX_SLOTS),
                                    timeout = 2,
                                })
                                return
                            end
                            table.insert(new_slots, action.id)
                        end
                    end
                end
                
                saveQASlots(new_slots)
                if touch_menu then touch_menu:updateItems() end
                UIManager:close(current_dialog)
                showAddButtonMenu(touch_menu, on_back)
            end,
        }
    })
    table.insert(buttons, {})  -- Separator
    
    for i = 1, #available do
        local action = available[i]
        local is_checked = slot_set[action.id] or false
        local symbol = getActionSymbol(action.id)
        local check_mark = is_checked and "✓ " or "  "
        local view_tag = " [" .. (action.view or "common") .. "]"
        local display_text = check_mark .. symbol .. action.label .. view_tag
        table.insert(buttons, {
            {
                text = display_text,
                callback = function()
                    local current_slots = getQASlots()
                    local found = false
                    for j = 1, #current_slots do
                        if current_slots[j] == action.id then
                            found = true
                            break
                        end
                    end
                    if found then
                        local new_slots = {}
                        for j = 1, #current_slots do
                            if current_slots[j] ~= action.id then
                                new_slots[#new_slots + 1] = current_slots[j]
                            end
                        end
                        saveQASlots(new_slots)
                    else
                        if #current_slots >= MAX_SLOTS then
                            UIManager:show(Notification:new{
                                text = string.format(_("Maximum %d buttons"), MAX_SLOTS),
                                timeout = 2,
                            })
                            return
                        end
                        current_slots[#current_slots + 1] = action.id
                        saveQASlots(current_slots)
                    end
                    if touch_menu then touch_menu:updateItems() end
                    UIManager:close(current_dialog)
                    showAddButtonMenu(touch_menu, on_back)
                end,
            }
        })
    end
    table.insert(buttons, {})
    table.insert(buttons, {
        { text = _("Close"), callback = function()
            UIManager:close(current_dialog)
        end }
    })
    local dialog = ButtonDialog:new{
        title = _("Add button"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    current_dialog = dialog
    UIManager:show(dialog)
end

-- ============================================================
-- Interface filter settings menu
-- ============================================================

function showInterfaceFilterMenu(touch_menu)
    local function buildDedicatedListItems(mode)
        local target_view = (mode == "fm") and "filemanager" or "reader"
        local items = {}
        local all_actions = getAllActionsForFilter()
        table.sort(all_actions, function(a, b)
            local a_checked = (a.view == target_view)
            local b_checked = (b.view == target_view)
            if a_checked ~= b_checked then
                return a_checked
            end
            local a_is_common = (a.view == "common")
            local b_is_common = (b.view == "common")
            if a_is_common ~= b_is_common then
                return a_is_common
            end
            local a_prio = getTypePriority(a.id)
            local b_prio = getTypePriority(b.id)
            if a_prio ~= b_prio then
                return a_prio < b_prio
            end
            return a.label:lower() < b.label:lower()
        end)
        table.insert(items, {
            text = function()
                local current_actions = getAllActionsForFilter()
                local all_checked = true
                local has_unlocked = false
                for __, action in ipairs(current_actions) do
                    if not isMenuAction(action.id) then
                        has_unlocked = true
                        if action.view ~= target_view then
                            all_checked = false
                            break
                        end
                    end
                end
                if not has_unlocked then
                    all_checked = true
                end
                return all_checked and "☑ " .. _("Deselect all") or "☐ " .. _("Make all dedicated")
            end,
            enabled = function()
                local current_actions = getAllActionsForFilter()
                for __, action in ipairs(current_actions) do
                    if not isMenuAction(action.id) then
                        return true
                    end
                end
                return false
            end,
            close_on_click = false,
            callback = function()
                local current_actions = getAllActionsForFilter()
                local all_checked = true
                for __, action in ipairs(current_actions) do
                    if not isMenuAction(action.id) and action.view ~= target_view then
                        all_checked = false
                        break
                    end
                end
                for __, action in ipairs(current_actions) do
                    if isMenuAction(action.id) then
                        goto continue
                    end
                    local current = getActionViewFinal(action.id)
                    if all_checked then
                        if current == target_view then
                            toggleDedicated(action.id, target_view)
                        end
                    else
                        if current ~= target_view then
                            toggleDedicated(action.id, target_view)
                        end
                    end
                    ::continue::
                end
                if touch_menu then
                    refreshQuickPanel(touch_menu)
                end
            end,
        })
        table.insert(items, { text = "----------------------------", enabled = false })
        for __action, action in ipairs(all_actions) do
            local is_locked = isMenuAction(action.id)
            local action_id = action.id
            table.insert(items, {
                text = function()
                    local is_checked = (getActionViewFinal(action_id) == target_view)
                    local prefix = is_checked and "✓ " or "  "
                    local symbol = getActionSymbol(action_id)
                    local view_tag = " [" .. getActionViewFinal(action_id) .. "]"
                    local label = getLabelForAction(action_id)
                    local display_text = prefix .. symbol .. label .. view_tag
                    if is_locked then
                        display_text = display_text .. " (" .. _("locked") .. ")"
                    end
                    return display_text
                end,
                enabled = not is_locked,
                close_on_click = false,
                callback = function()
                    if is_locked then return end
                    toggleDedicated(action_id, target_view)
                    if touch_menu then
                        refreshQuickPanel(touch_menu)
                    end
                end,
            })
        end
        return items
    end
    local function getMainItems()
        return {
            {
                text = function()
                    local enabled = getBool("qa_context_filter")
                    return (enabled and "✓ " or "  ") .. _("Enable interface filtering")
                end,
                close_on_click = false,
                callback = function()
                    local current = getBool("qa_context_filter")
                    setBool("qa_context_filter", not current)
                    refreshQuickPanel(touch_menu)
                end,
            },
            {
                text = function()
                    local actions = getAllActionsForFilter()
                    local fm = 0
                    for _, act in ipairs(actions) do
                        if act.view == "filemanager" then
                            fm = fm + 1
                        end
                    end
                    return string.format(_("File manager dedicated (%d)"), fm)
                end,
                close_on_click = true,
                sub_item_table = function()
                    return buildDedicatedListItems("fm")
                end,
            },
            {
                text = function()
                    local actions = getAllActionsForFilter()
                    local rd = 0
                    for _, act in ipairs(actions) do
                        if act.view == "reader" then
                            rd = rd + 1
                        end
                    end
                    return string.format(_("Reader dedicated (%d)"), rd)
                end,
                close_on_click = true,
                sub_item_table = function()
                    return buildDedicatedListItems("reader")
                end,
            },
            {
                text = _("Reset to default dedication"),
                close_on_click = true,
                callback = function()
                    local confirm = ConfirmBox:new{
                        text = _("Reset all dedicated settings to default?"),
                        ok_text = _("Reset"),
                        cancel_text = _("Cancel"),
                        ok_callback = function()
                            setTable("builtin_overrides", {})
                            local custom = getTable("custom")
                            for id, cfg in pairs(custom) do
                                if cfg.action_type == "menu" then
                                    cfg.view = cfg.menu_path.view or cfg.view
                                else
                                    local action_val = cfg.dispatcher_action or cfg.action_value
                                    local default_view = getDefaultViewForActionType(cfg.action_type, action_val)
                                    cfg.view = default_view
                                end
                            end
                            setTable("custom", custom)
                            refreshQuickPanel(touch_menu)
                            UIManager:show(Notification:new{
                                text = _("Reset to default dedication"),
                                timeout = 2,
                            })
                        end,
                    }
                    UIManager:show(confirm)
                end,
            },
        }
    end
    return getMainItems()
end

-- ============================================================
-- Dispatcher helper functions (extracted to reduce upvalues)
-- ============================================================

-- Close Dispatcher dialogs
local function closeDispatcherDialogs(disp_picker, sub_dialog, choice_dialog)
    if disp_picker then
        UIManager:close(disp_picker)
        disp_picker = nil
    end
    if sub_dialog then
        UIManager:close(sub_dialog)
        sub_dialog = nil
    end
    if choice_dialog then
        UIManager:close(choice_dialog)
        choice_dialog = nil
    end
    return disp_picker, sub_dialog, choice_dialog
end

-- Build configurable type submenu
local function buildConfigurableSubItems(item, def, touch_menu, buildSaveDialog, openDispatcherPickerFn, closeSettingsDialogFn, showSettingsMenuFn, getCurrentActionType, getCurrentActionVal1, getCurrentActionVal2, getCurrentActionTitle, getCurrentView, setCurrentActionType, setCurrentActionVal1, setCurrentActionVal2, setCurrentActionTitle, setCurrentView)
    return function()
        -- Close parent menu
        if sub_dialog then
            UIManager:close(sub_dialog)
            sub_dialog = nil
        end
        if disp_picker then UIManager:close(disp_picker); disp_picker = nil end
        
        local sub_items = {}
        local args = def.args
        local toggle = def.toggle
        if def.args_func then
            local ok, a, t = pcall(def.args_func)
            if ok then
                args = a
                toggle = t
            end
        end

        table.insert(sub_items, {{
            text = "⚙️ " .. _("Open main menu"),
            callback = function()
                if sub_dialog then
                    UIManager:close(sub_dialog)
                    sub_dialog = nil
                end
                if disp_picker then
                    UIManager:close(disp_picker)
                    disp_picker = nil
                end
                closeSettingsDialogFn()
                showSettingsMenuFn(touch_menu)
            end
        }})

        table.insert(sub_items, {{
            text = "◂◂ " .. _("Back to edit"),
            callback = function()
                if sub_dialog then
                    UIManager:close(sub_dialog)
                    sub_dialog = nil
                end
                if disp_picker then
                    UIManager:close(disp_picker)
                    disp_picker = nil
                end
                buildSaveDialog(false)
            end
        }})

        table.insert(sub_items, {{
            text = "◂ " .. _("Back"),
            callback = function()
                if sub_dialog then
                    UIManager:close(sub_dialog)
                    sub_dialog = nil
                end
                openDispatcherPickerFn(touch_menu)
            end
        }})

        table.insert(sub_items, {})

        if args and #args > 0 then
            for index, value in ipairs(args) do
                local display = toggle and toggle[index] or tostring(value)
                table.insert(sub_items, {{
                    text = display,
                    callback = function()
                        if sub_dialog then
                            UIManager:close(sub_dialog)
                            sub_dialog = nil
                        end
                        
                        setCurrentActionType("dispatcher")
                        setCurrentActionVal1(item.id)
                        setCurrentActionVal2(value)
                        setCurrentActionTitle(display)
                        if def and def.filemanager then
                            setCurrentView("filemanager")
                        elseif def and (def.reader or def.rolling or def.paging) then
                            setCurrentView("reader")
                        else
                            setCurrentView("common")
                        end
                        buildSaveDialog(true)
                    end,
                }})
            end
        end

        sub_dialog = ButtonDialog:new{
            title = item.title,
            title_align = "center",
            buttons = sub_items,
            width = math.floor(Screen:getWidth() * 0.7),
        }
        UIManager:show(sub_dialog)
    end
end

-- ============================================================
-- Custom action edit dialog
-- ============================================================

function showCustomQADialog(qa_id, on_done)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local InfoMessage = require("ui/widget/infomessage")
    local ButtonDialog = require("ui/widget/buttondialog")
    local SpinWidget = require("ui/widget/spinwidget")
    local ConfirmBox = require("ui/widget/confirmbox")

    local getNonFavColl = getCollectionsList
    local collections = getNonFavColl()
    table.sort(collections, function(a, b) return a:lower() < b:lower() end)

    local custom = getTable("custom")
    local cfg = qa_id and custom[qa_id] or {}
    local start_path = cfg.action_value or (G_reader_settings:readSetting("home_dir") or "/")
    local chosen_icon = cfg.icon
    local dlg_title = qa_id and _("Edit quick action") or _("New quick action")
    local existing_label = cfg.label or ""

    local current_action_type = nil
    local current_action_val1 = nil
    local current_action_val2 = nil
    local current_action_title = nil
    
    if cfg.action_type == "dispatcher" and cfg.dispatcher_action then
        current_action_type = "dispatcher"
        current_action_val1 = cfg.dispatcher_action
        current_action_val2 = cfg.dispatcher_value or true
        current_action_title = cfg.dispatcher_action 
    elseif cfg.action_type == "plugin" and cfg.plugin_key then
        current_action_type = "plugin"
        current_action_val1 = cfg.plugin_key
        current_action_val2 = cfg.plugin_method
        current_action_title = cfg.plugin_key  
    elseif cfg.action_type == "collection" and cfg.action_value then
        current_action_type = "collection"
        current_action_val1 = cfg.action_value
        current_action_title = cfg.action_value  
    elseif cfg.action_type == "folder" and cfg.action_value then
        current_action_type = "folder"
        current_action_val1 = cfg.action_value
        current_action_title = cfg.action_value:match("([^/]+)$") or cfg.action_value  
    elseif cfg.action_type == "menu" and cfg.menu_path then
        current_action_type = "menu"
        current_action_val1 = cfg.menu_path
        current_action_title = cfg.menu_path.display_label or _("Menu action")  
    end

    local active_dialog = nil
    local choice_dialog = nil
    local coll_picker = nil
    local plugin_picker = nil
    local disp_picker = nil
    local current_view = cfg.view or "common"
     
    local view_options = { "common", "filemanager", "reader" }
    local view_labels = {
        common = _("General"),
        filemanager = _("File manager"),
        reader = _("Reader"),
    }
    
    local buildSaveDialog
    local openActionPicker

    -- commitQA: menu type does not save view
    local function commitQA(final_label, path, collection, icon, plugin_key, plugin_method, dispatcher_action, dispatcher_value, menu_path, user_view)
        local list = getSetting("custom_list")
        if type(list) ~= "table" then list = {} end
        local max_n = 0
        for _, id in ipairs(list) do
            local n = tonumber(id:match("^custom_qa_(%d+)$"))
            if n and n > max_n then max_n = n end
        end
        local final_id = qa_id or ("custom_qa_" .. (max_n + 1))
        
        local custom_tbl = getTable("custom")
        local custom_list = getSetting("custom_list")
        if type(custom_list) ~= "table" then custom_list = {} end
        
        local action_type = nil
        local default_view = "common"
        
        if path and path ~= "" then
            action_type = "folder"
            default_view = "filemanager"
        elseif collection and collection ~= "" then
            action_type = "collection"
            default_view = "filemanager"
        elseif plugin_key and plugin_key ~= "" then
            action_type = "plugin"
            default_view = "common"
        elseif dispatcher_action and dispatcher_action ~= "" then
            action_type = "dispatcher"
            default_view = getDefaultViewForActionType("dispatcher", dispatcher_action)
        elseif menu_path and type(menu_path) == "table" then
            action_type = "menu"
            default_view = menu_path.view or "common"
        end
        
        local final_view
        if action_type == "menu" then
            final_view = default_view
        else
            final_view = user_view or default_view
        end
        
        local cfg_table = {
            label = final_label,
            icon = icon,
            is_in_place = (dispatcher_action ~= nil or plugin_key ~= nil),
            action_type = action_type,
        }
        if action_type ~= "menu" then
            cfg_table.view = final_view
        end
        
        if path and path ~= "" then
            cfg_table.action_value = path
        elseif collection and collection ~= "" then
            cfg_table.action_value = collection
        elseif plugin_key and plugin_key ~= "" then
            cfg_table.plugin_key = plugin_key
            cfg_table.plugin_method = plugin_method
        elseif dispatcher_action and dispatcher_action ~= "" then
            cfg_table.dispatcher_action = dispatcher_action
            cfg_table.dispatcher_value = dispatcher_value
        elseif menu_path and type(menu_path) == "table" then
            cfg_table.menu_path = menu_path
        end
        
        custom_tbl[final_id] = cfg_table
        setTable("custom", custom_tbl)

        local auto_add = getBool("qa_auto_add_to_panel")
        if auto_add then
            local slots = getQASlots()
            local already_exists = false
            for _, sid in ipairs(slots) do
                if sid == final_id then
                    already_exists = true
                    break
                end
            end
            if not already_exists then
                if #slots < MAX_SLOTS then
                    slots[#slots + 1] = final_id
                    saveQASlots(slots)
                else
                    UIManager:show(InfoMessage:new{
                        text = string.format(_("Button panel is full (maximum %d), cannot auto-add."), MAX_SLOTS),
                        timeout = 3,
                    })
                end
            end
        end

        if not qa_id then
            custom_list[#custom_list + 1] = final_id
            setSetting("custom_list", custom_list)
        end
        
        if on_done then on_done() end
    end

    local function cancelActionPicker()
        if not current_action_type and not qa_id then
            if on_done then on_done() end
        else
            if active_dialog then
                UIManager:close(active_dialog)
                active_dialog = nil
            end
            buildSaveDialog(false)
        end
    end

    local function openIconPicker()
        local saved_label = existing_label
        if active_dialog then
            local inputs = active_dialog:getFields()
            if inputs and inputs[1] then
                saved_label = inputs[1]
                existing_label = inputs[1]
            end
            UIManager:close(active_dialog)
            active_dialog = nil
        end
        showIconPicker(
            function(result)
                if result then
                    chosen_icon = result
                    buildSaveDialog(false)
                else
                    chosen_icon = nil
                    buildSaveDialog(false)
                end
            end,
            chosen_icon
        )
    end

    openActionPicker = function()
        if active_dialog then
            UIManager:close(active_dialog)
            active_dialog = nil
        end
        
        choice_dialog = ButtonDialog:new{
            title = _("Action type"),
            title_align = "center",
            buttons = {
                {{ text = _("Folder"), callback = function()
                    UIManager:close(choice_dialog)
                    choice_dialog = nil
                    local pc = PathChooser:new{
                        select_directory = true,
                        select_file = false,
                        path = start_path,
                        onConfirm = function(path)
                            path = path:gsub("/$", "")
                            current_action_type = "folder"
                            current_action_val1 = path
                            current_action_title = path:match("([^/]+)$") or path
                            current_view = "filemanager"
                            buildSaveDialog(true)
                        end,
                        onCancel = function()
                            cancelActionPicker()
                        end,
                    }
                    UIManager:show(pc)
                end }},
                {{ text = _("Collection"), enabled = #collections > 0, callback = function()
                    UIManager:close(choice_dialog)
                    choice_dialog = nil
                    local coll_buttons = {}
                    for _, name in ipairs(collections) do
                        local _name = name
                        coll_buttons[#coll_buttons + 1] = {{ text = name, callback = function()
                            if coll_picker then UIManager:close(coll_picker); coll_picker = nil end
                            if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
                            current_action_type = "collection"
                            current_action_val1 = _name
                            current_action_title = _name
                            current_view = "filemanager"
                            buildSaveDialog(true)
                        end }}
                    end
                    coll_buttons[#coll_buttons + 1] = {{ text = _("Back"), callback = function()
                        if coll_picker then UIManager:close(coll_picker); coll_picker = nil end
                        openActionPicker()
                    end }}
                    coll_picker = ButtonDialog:new{ title = _("Select collection"), title_align = "center", buttons = coll_buttons }
                    UIManager:show(coll_picker)
                end }},
                {{ text = _("Plugin"), callback = function()
                    UIManager:close(choice_dialog)
                    choice_dialog = nil
                    
                    local plugins = getPluginsList()
                    if #plugins == 0 then
                        UIManager:show(InfoMessage:new{ text = _("No plugins available"), timeout = 3 })
                        cancelActionPicker()
                        return
                    end
                    
                    table.sort(plugins, function(a, b) return a.title:lower() < b.title:lower() end)
                    local plugin_buttons = {}
                    for _, p in ipairs(plugins) do
                        local _p = p
                        plugin_buttons[#plugin_buttons + 1] = {{ text = p.title, callback = function()
                            if plugin_picker then UIManager:close(plugin_picker); plugin_picker = nil end
                            if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
                            current_action_type = "plugin"
                            current_action_val1 = _p.key
                            current_action_val2 = _p.method
                            current_action_title = _p.title
                            current_view = "common"
                            buildSaveDialog(true)
                        end }}
                    end
                    plugin_buttons[#plugin_buttons + 1] = {{ text = _("Back"), callback = function()
                        if plugin_picker then UIManager:close(plugin_picker); plugin_picker = nil end
                        openActionPicker()
                    end }}
                    plugin_picker = ButtonDialog:new{ title = _("Select plugin"), title_align = "center", buttons = plugin_buttons }
                    UIManager:show(plugin_picker)
                end }},
                {{ text = _("System action"), callback = function()
                    openDispatcherPicker()
                end }},
                {{ text = _("Record menu action"), callback = function()
                    UIManager:close(choice_dialog)
                    choice_dialog = nil
                    local FM = require("apps/filemanager/filemanager")
                    local fm = FM and FM.instance
                    local RUI = require("apps/reader/readerui")
                    
                    local target_menu = nil
                    local view = "reader"
                    
                    if RUI and RUI.instance and RUI.instance.menu then
                        if not RUI.instance.menu.menu_container or not RUI.instance.menu.menu_container[1] then
                            RUI.instance.menu:onShowMenu()
                        end
                        target_menu = RUI.instance.menu.menu_container and RUI.instance.menu.menu_container[1]
                        view = "reader"
                    elseif fm and fm.menu then
                        if not fm.menu.menu_container or not fm.menu.menu_container[1] then
                            fm.menu:onShowMenu()
                        end
                        target_menu = fm.menu.menu_container and fm.menu.menu_container[1]
                        view = "filemanager"
                    else
                        UIManager:show(InfoMessage:new{ text = _("Please open the menu first"), timeout = 3 })
                        cancelActionPicker()
                        return
                    end
                    
                    if not target_menu then
                        UIManager:show(InfoMessage:new{ text = _("Unable to open menu"), timeout = 3 })
                        cancelActionPicker()
                        return
                    end
                    
                    startPicking(target_menu, function(path_record)
                        if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
                        local function cleanString(s)
                            if not s then return "" end
                            return s:gsub("[\n\r]", ""):match("^%s*(.-)%s*$") or ""
                        end
                        local clean_record = {
                            tab_index = path_record.tab_index,
                            display_label = cleanString(path_record.display_label),
                            index_path = path_record.index_path,
                            view = view,
                            is_leaf = path_record.is_leaf,
                        }
                        current_action_type = "menu"
                        current_action_val1 = clean_record
                        current_action_title = clean_record.display_label
                        current_view = view
                        buildSaveDialog(true)
                    end, function()
                        cancelActionPicker()
                    end)
                end }},
                {{ text = _("Back"), callback = function()
                    if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
                    buildSaveDialog(false)
                end }},
            }
        }
        UIManager:show(choice_dialog)
    end

    buildSaveDialog = function(update_name_with_title)
        if coll_picker then
            UIManager:close(coll_picker)
            coll_picker = nil
        end
        if plugin_picker then
            UIManager:close(plugin_picker)
            plugin_picker = nil
        end
        if disp_picker then
            UIManager:close(disp_picker)
            disp_picker = nil
        end
        if sub_dialog then
            UIManager:close(sub_dialog)
            sub_dialog = nil
        end
        if choice_dialog then
            UIManager:close(choice_dialog)
            choice_dialog = nil
        end
        if active_dialog then
            UIManager:close(active_dialog)
            active_dialog = nil
        end

        if update_name_with_title then
            if current_action_title then
                existing_label = current_action_title
            end
        end

        local action_label = _("Action") .. ": "
        if current_action_type then
            action_label = action_label .. (current_action_title or "")
        else
            action_label = action_label .. _("Tap to set action")
        end

        local function iconButtonText()
            if not chosen_icon then return _("Icon: default (tap to change)") end
            local nerd_char = nerdIconChar(chosen_icon)
            if nerd_char then
                local hex = chosen_icon:match("nerd:(.+)")
                return _("Icon") .. ": " .. nerd_char .. " (" .. hex .. ")"
            end
            local fname = chosen_icon:match("([^/]+)$") or chosen_icon
            local stem = (fname:match("^(.+)%.[^%.]+$") or fname):gsub("_", " ")
            return _("Icon") .. ": " .. stem
        end

        local function viewButtonText()
            local is_locked = (current_action_type == "menu")
            if is_locked then
                return _("Interface") .. ": " .. view_labels[current_view] .. " (" .. _("locked") .. ")"
            else
                return _("Interface") .. ": " .. view_labels[current_view]
            end
        end

        local fields = { 
            { description = _("Name"), text = existing_label, hint = _("Action name…") },
        }

        -- Get current position
        local function getCurrentPosition()
            if not qa_id then return nil, 0 end
            local slots = getQASlots()
            for i, sid in ipairs(slots) do
                if sid == qa_id then
                    return i, #slots
                end
            end
            return nil, 0
        end

        local pos, total = getCurrentPosition()

        -- Build last row
        local last_row = {
            { text = _("Cancel"), callback = function()
                UIManager:close(active_dialog)
                active_dialog = nil
                if not qa_id and not current_action_type then
                    if on_done then on_done() end
                end
            end },
        }

        -- Delete: only for custom actions (qa_id exists)
        if qa_id then
            table.insert(last_row, { text = _("Delete"), callback = function()
                if active_dialog then
                    local inputs = active_dialog:getFields()
                    if inputs and inputs[1] then
                        existing_label = inputs[1]
                    end
                    UIManager:close(active_dialog)
                    active_dialog = nil
                end
                UIManager:show(ConfirmBox:new{
                    text = string.format(_("Delete quick action \"%s\"?"), existing_label),
                    ok_text = _("Delete"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        deleteCustomQA(qa_id)
                        local slots = getQASlots()
                        local new_slots = {}
                        for _, sid in ipairs(slots) do
                            if sid ~= qa_id then
                                table.insert(new_slots, sid)
                            end
                        end
                        saveQASlots(new_slots)
                        if on_done then on_done() end
                    end,
                })
            end })
        end

        -- Move left
        if pos then
            table.insert(last_row, { text = "◀", enabled = (pos > 1), callback = function()
                if active_dialog then
                    local inputs = active_dialog:getFields()
                    if inputs and inputs[1] then
                        existing_label = inputs[1]
                    end
                    UIManager:close(active_dialog)
                    active_dialog = nil
                end
                local slots = getQASlots()
                local idx = nil
                for i, sid in ipairs(slots) do
                    if sid == qa_id then
                        idx = i
                        break
                    end
                end
                if idx and idx > 1 then
                    slots[idx], slots[idx-1] = slots[idx-1], slots[idx]
                    saveQASlots(slots)
                end
                buildSaveDialog(false)
            end })
        end

        -- Position button
        if pos then
            table.insert(last_row, { text = pos .. "/" .. total, callback = function()
                UIManager:close(active_dialog)
                active_dialog = nil
                local slots = getQASlots()
                local sort_items = {}
                for i, id in ipairs(slots) do
                    sort_items[#sort_items + 1] = { text = getLabelForAction(id), orig_item = id }
                end
                local sort_dialog = SortWidget:new{
                    title = _("Reorder buttons"),
                    item_table = sort_items,
                    covers_fullscreen = true,
                    callback = function()
                        local new_slots = {}
                        for j = 1, #sort_items do
                            new_slots[#new_slots + 1] = sort_items[j].orig_item
                        end
                        saveQASlots(new_slots)
                        if on_done then on_done() end
                    end,
                }
                UIManager:show(sort_dialog)
            end })
        end

        -- Move right
        if pos then
            table.insert(last_row, { text = "▶", enabled = (pos < total), callback = function()
                if active_dialog then
                    local inputs = active_dialog:getFields()
                    if inputs and inputs[1] then
                        existing_label = inputs[1]
                    end
                    UIManager:close(active_dialog)
                    active_dialog = nil
                end
                local slots = getQASlots()
                local idx = nil
                for i, sid in ipairs(slots) do
                    if sid == qa_id then
                        idx = i
                        break
                    end
                end
                if idx and idx < #slots then
                    slots[idx], slots[idx+1] = slots[idx+1], slots[idx]
                    saveQASlots(slots)
                end
                buildSaveDialog(false)
            end })
        end

        -- Remove
        table.insert(last_row, { text = _("Remove"), callback = function()
            if active_dialog then
                local inputs = active_dialog:getFields()
                if inputs and inputs[1] then
                    existing_label = inputs[1]
                end
                UIManager:close(active_dialog)
                active_dialog = nil
            end
            removeFromPanel(qa_id, nil)
            if on_done then on_done() end
        end })

        table.insert(last_row, { text = _("Save"), is_enter_default = true, callback = function()
            local inputs = active_dialog:getFields()
            local final_label = inputs[1] or ""
            if final_label == "" then
                UIManager:show(InfoMessage:new{ text = _("Please enter a name"), timeout = 2 })
                return
            end
            if not current_action_type then
                UIManager:show(InfoMessage:new{ text = _("Please select an action type"), timeout = 2 })
                return
            end

            UIManager:close(active_dialog)
            active_dialog = nil

            local default_icon = "nerd:F07B"
            if current_action_type == "plugin" then
                default_icon = "nerd:F1B2"
            elseif current_action_type == "dispatcher" then
                default_icon = "nerd:F00A"
            elseif current_action_type == "menu" then
                default_icon = "nerd:F28D"
            elseif current_action_type == "collection" then
                default_icon = "nerd:F006"
            end

            local path, collection, plugin_key, plugin_method, dispatcher_action, dispatcher_value, menu_path
            if current_action_type == "folder" then
                path = current_action_val1
            elseif current_action_type == "collection" then
                collection = current_action_val1
            elseif current_action_type == "plugin" then
                plugin_key = current_action_val1
                plugin_method = current_action_val2
            elseif current_action_type == "dispatcher" then
                dispatcher_action = current_action_val1
                dispatcher_value = current_action_val2
            elseif current_action_type == "menu" then
                menu_path = current_action_val1
            end

            commitQA(final_label, path, collection, chosen_icon or default_icon, plugin_key, plugin_method, dispatcher_action, dispatcher_value, menu_path, current_view)
        end })

        local buttons = {
            { { text = action_label, callback = function()
                if active_dialog then
                    local inputs = active_dialog:getFields()
                    if inputs and inputs[1] then
                        existing_label = inputs[1]
                    end
                end
                openActionPicker()
            end } },
            { { text = iconButtonText(), callback = function() openIconPicker() end } },
            { { text = viewButtonText(), enabled = (current_action_type ~= "menu"), callback = function()
                if current_action_type == "menu" then return end
                if active_dialog then
                    local inputs = active_dialog:getFields()
                    if inputs and inputs[1] then
                        existing_label = inputs[1]
                    end
                    UIManager:close(active_dialog)
                    active_dialog = nil
                end
                local view_buttons = {}
                for _, v in ipairs(view_options) do
                    local _v = v
                    table.insert(view_buttons, {{
                        text = (current_view == _v and "✓ " or "  ") .. view_labels[_v],
                        callback = function()
                            UIManager:close(view_dialog)
                            current_view = _v
                            buildSaveDialog(false)
                        end,
                    }})
                end
                table.insert(view_buttons, {{
                    text = _("Back"),
                    callback = function()
                        UIManager:close(view_dialog)
                        buildSaveDialog(false)
                    end,
                }})
                view_dialog = ButtonDialog:new{
                    title = _("Select interface"),
                    title_align = "center",
                    buttons = view_buttons,
                }
                UIManager:show(view_dialog)
            end } },
            last_row,
        }

        active_dialog = MultiInputDialog:new{
            title = dlg_title,
            fields = fields,
            tap_close_callback = function()
                UIManager:close(active_dialog)
                active_dialog = nil
                if not qa_id and not current_action_type then
                    if on_done then on_done() end
                end
            end,
            buttons = buttons,
        }
        UIManager:show(active_dialog)
        pcall(function() active_dialog:onShowKeyboard() end)
    end

    -- Define openDispatcherPicker
    openDispatcherPicker = function(touch_menu)
        if choice_dialog then
            UIManager:close(choice_dialog)
            choice_dialog = nil
        end

        local actions = getDispatcherActions()
        if #actions == 0 then
            UIManager:show(InfoMessage:new{ text = _("No system actions available"), timeout = 3 })
            cancelActionPicker()
            return
        end

        local ok, DispatcherMod = pcall(require, "dispatcher")
        if not ok or not DispatcherMod then
            UIManager:show(InfoMessage:new{ text = _("Unable to load Dispatcher"), timeout = 3 })
            cancelActionPicker()
            return
        end

        local settingsList
        local fn_idx = 1
        while true do
            local name, val = debug.getupvalue(DispatcherMod.registerAction, fn_idx)
            if not name then break end
            if name == "settingsList" then settingsList = val end
            fn_idx = fn_idx + 1
        end

        if not settingsList then
            UIManager:show(InfoMessage:new{ text = _("Unable to get system actions list"), timeout = 3 })
            cancelActionPicker()
            return
        end

        local sections = {
            { key = "general",     title = _("General") },
            { key = "device",      title = _("Device") },
            { key = "screen",      title = _("Screen and lighting") },
            { key = "filemanager", title = _("File browser") },
            { key = "reader",      title = _("Reader") },
            { key = "rolling",     title = _("Re-flowable documents (epub, fb2, txt…)") },
            { key = "paging",      title = _("Fixed-layout documents (pdf, djvu, images…)") },
        }

        local sections_map = {}
        for __, sec in ipairs(sections) do
            sections_map[sec.key] = { title = sec.title, items = {} }
        end

        for __, action in ipairs(actions) do
            local def = settingsList[action.id]
            if def and def.category then
                local section_key = "general"
                for ___, sec in ipairs(sections) do
                    if def[sec.key] == true then
                        section_key = sec.key
                        break
                    end
                end
                table.insert(sections_map[section_key].items, {
                    id = action.id,
                    title = action.title,
                    category = def.category,
                    def = def,
                })
            end
        end

        local section_buttons = {}

        for __, sec in ipairs(sections) do
            local items = sections_map[sec.key].items
            if #items > 0 then
                table.sort(items, function(a, b) return a.title:lower() < b.title:lower() end)

                local action_buttons = {}

                table.insert(action_buttons, {{
                    text = "⚙️ " .. _("Open main menu"),
                    callback = function()
                        if sub_dialog then
                            UIManager:close(sub_dialog)
                            sub_dialog = nil
                        end
                        if disp_picker then
                            UIManager:close(disp_picker)
                            disp_picker = nil
                        end
                        closeSettingsDialog()
                        showSettingsMenu(touch_menu)
                    end
                }})

                table.insert(action_buttons, {{
                    text = "◂◂ " .. _("Back to edit"),
                    callback = function()
                        if sub_dialog then
                            UIManager:close(sub_dialog)
                            sub_dialog = nil
                        end
                        if disp_picker then
                            UIManager:close(disp_picker)
                            disp_picker = nil
                        end
                        buildSaveDialog(false)
                    end
                }})

                table.insert(action_buttons, {{
                    text = "◂ " .. _("Back"),
                    callback = function()
                        if sub_dialog then
                            UIManager:close(sub_dialog)
                            sub_dialog = nil
                        end
                        openDispatcherPicker(touch_menu)
                    end
                }})

                table.insert(action_buttons, {})

                for ___, item in ipairs(items) do
                    local _item = item
                    local category = item.category
                    local def = item.def

                    if category == "none" or category == "arg" then
                        table.insert(action_buttons, {{
                            text = item.title,
                            callback = function()
                                disp_picker, sub_dialog, choice_dialog = closeDispatcherDialogs(disp_picker, sub_dialog, choice_dialog)
                                current_action_type = "dispatcher"
                                current_action_val1 = _item.id
                                current_action_val2 = true
                                current_action_title = _item.title
                                if def and def.filemanager then
                                    current_view = "filemanager"
                                elseif def and (def.reader or def.rolling or def.paging) then
                                    current_view = "reader"
                                else
                                    current_view = "common"
                                end
                                buildSaveDialog(true)
                            end,
                        }})
                    elseif category == "absolutenumber" or category == "incrementalnumber" then
                        table.insert(action_buttons, {{
                            text = item.title,
                            callback = function()
                                if sub_dialog then UIManager:close(sub_dialog); sub_dialog = nil end
                                local spin = SpinWidget:new{
                                    title_text = _item.title,
                                    value = def.default or def.min or 0,
                                    value_min = def.min or 0,
                                    value_max = def.max or 100,
                                    value_step = def.step or 1,
                                    unit = def.unit,
                                    callback = function(spin)
                                        disp_picker, sub_dialog, choice_dialog = closeDispatcherDialogs(disp_picker, sub_dialog, choice_dialog)
                                        current_action_type = "dispatcher"
                                        current_action_val1 = _item.id
                                        current_action_val2 = spin.value
                                        current_action_title = _item.title .. ": " .. tostring(spin.value)
                                        if def and def.filemanager then
                                            current_view = "filemanager"
                                        elseif def and (def.reader or def.rolling or def.paging) then
                                            current_view = "reader"
                                        else
                                            current_view = "common"
                                        end                                        buildSaveDialog(true)
                                    end,
                                }
                                UIManager:show(spin)
                            end,
                        }})
elseif category == "string" or category == "configurable" then
    table.insert(action_buttons, {{
        text = item.title,
        callback = buildConfigurableSubItems(
            _item, def, touch_menu, 
            buildSaveDialog, openDispatcherPicker, closeSettingsDialog, showSettingsMenu,
            -- Pass getters/setters
            function() return current_action_type end,
            function() return current_action_val1 end,
            function() return current_action_val2 end,
            function() return current_action_title end,
            function() return current_view end,
            function(v) current_action_type = v end,
            function(v) current_action_val1 = v end,
            function(v) current_action_val2 = v end,
            function(v) current_action_title = v end,
            function(v) current_view = v end
              )
    }})
end
                end

                -- Handle section_buttons
                if #action_buttons > 4 then
                    table.insert(section_buttons, {{
                        text = sec.title,
                        callback = function()
                            if disp_picker then
                                UIManager:close(disp_picker)
                                disp_picker = nil
                            end
                           sub_dialog = ButtonDialog:new{
                                title = sec.title,
                                title_align = "center",
                                buttons = action_buttons,
                                width = math.floor(Screen:getWidth() * 0.7),
                            }
                            UIManager:show(sub_dialog)
                        end,
                    }})
                else
                    for _, btn in ipairs(action_buttons) do
                        table.insert(section_buttons, btn)
                    end
                end
            end
        end

        local final_buttons = {}

        table.insert(final_buttons, {{
            text = "⚙️ " .. _("Open main menu"),
            callback = function()
                if disp_picker then
                    UIManager:close(disp_picker)
                    disp_picker = nil
                end
                closeSettingsDialog()
                showSettingsMenu(touch_menu)
            end
        }})

        table.insert(final_buttons, {{
            text = "◂◂ " .. _("Back to edit"),
            callback = function()
                if disp_picker then
                    UIManager:close(disp_picker)
                    disp_picker = nil
                end
                buildSaveDialog(false)
            end
        }})

        table.insert(final_buttons, {{
            text = "◂ " .. _("Back"),
            callback = function()
                if disp_picker then
                    UIManager:close(disp_picker)
                    disp_picker = nil
                end
                openActionPicker()
            end
        }})

        table.insert(final_buttons, {})

        for __, btn in ipairs(section_buttons) do
            table.insert(final_buttons, btn)
        end

        disp_picker = ButtonDialog:new{
            title = _("System action"),
            title_align = "center",
            buttons = final_buttons,
            width = math.floor(Screen:getWidth() * 0.7),
        }
        UIManager:show(disp_picker)
    end

    if not qa_id then
        buildSaveDialog(false)
    else
        buildSaveDialog(false)
    end
end

-- ============================================================
-- Reset all settings
-- ============================================================

local function resetAllSettings(touch_menu)
    -- Clear all caches
    picker_cache = {}
    cached_file_icons = nil
    system_temp_overrides = nil

    local new_config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        if type(v) == "table" then
            new_config[k] = {}
            for k2, v2 in pairs(v) do
                new_config[k][k2] = v2
            end
        else
            new_config[k] = v
        end
    end
    local f = io.open(CONFIG_PATH, "w")
    if f then
        f:write("return " .. serializeTable(new_config))
        f:close()
        logger.info("[QuickActions] Configuration file rewritten:", CONFIG_PATH)
    end
    CONFIG_DATA = new_config
    local current_menu = nil
    local fm = require("apps/filemanager/filemanager").instance
    if fm and fm.menu and fm.menu.menu_container then
        current_menu = fm.menu.menu_container[1]
    end
    if not current_menu then
        local readerui = require("apps/reader/readerui").instance
        if readerui and readerui.menu and readerui.menu.menu_container then
            current_menu = readerui.menu.menu_container[1]
        end
    end
    if current_menu and current_menu.updateItems then
        current_menu:updateItems()
    end
    logger.info("[QuickActions] Configuration reset to default values")
end

-- ============================================================
-- Settings menu (main entry)
-- ============================================================

function showSettingsMenu(touch_menu)
    if not touch_menu then
        local fm = require("apps/filemanager/filemanager").instance
        touch_menu = fm and fm.menu and fm.menu.menu_container and fm.menu.menu_container[1]
        if not touch_menu then
            local readerui = require("apps/reader/readerui").instance
            touch_menu = readerui and readerui.menu and readerui.menu.menu_container and readerui.menu.menu_container[1]
        end
    end

    local function getSlots()
        local slots = getSetting("qa_slots")
        if type(slots) == "table" then return slots end
        return DEFAULT_CONFIG.qa_slots
    end

    local function getCustomActionSubMenu()
        local items = getCustomItems(touch_menu)
        local sub_items = {}
        local auto_add_key = "qa_auto_add_to_panel"
        table.insert(sub_items, {
            text = function()
                local is_checked = getBool(auto_add_key)
                return (is_checked and "✓ " or "  ") .. _("Auto-add to panel on save")
            end,
            callback = function()
                local current = getBool(auto_add_key)
                setBool(auto_add_key, not current)
            end,
            separator = true,
        })
        table.insert(sub_items, {
            text = "+ " .. _("New"),
            close_on_click = true,
            callback = function()
                closeSettingsDialog()
                showCustomQADialog(nil, function() 
                    refreshQuickPanel(touch_menu)
                end)
            end,
        })
        local builtin_items = {}
        local custom_items = {}
        for _, item in ipairs(items) do
            if item.is_builtin then
                table.insert(builtin_items, item)
            else
                table.insert(custom_items, item)
            end
        end
        if #builtin_items > 0 then
            local builtin_sub = {}
            for _, item in ipairs(builtin_items) do
                table.insert(builtin_sub, {
                    text = item.text,
                    close_on_click = true,
                    callback = function()
                        closeSettingsDialog()
                        item.on_edit()
                    end,
                })
            end
            table.insert(sub_items, {
                text = _("Built-in actions"),
                sub_item_table = builtin_sub,
            })
        end
        for _, item in ipairs(custom_items) do
            table.insert(sub_items, {
                text = item.text,
                close_on_click = true,
                callback = function()
                    closeSettingsDialog()
                    item.on_edit()
                end,
            })
        end
        return sub_items
    end

    local function getShapeSubMenu()
        return {
            { text = _("Round"), radio = true, checked_func = function() return getShape() == "round" end, callback = function() setString("qa_shape", "round") end },
            { text = _("Rounded square"), radio = true, checked_func = function() return getShape() == "square_round" end, callback = function() setString("qa_shape", "square_round") end },
            { text = _("Borderless"), radio = true, checked_func = function() return getShape() == "bare" end, callback = function() setString("qa_shape", "bare") end },
        }
    end

    local function getBgSubMenu()
        return {
            { text = _("Transparent"), radio = true, checked_func = function() return getBg() == "transparent" end, callback = function() setString("qa_bg", "transparent") end },
            { text = _("Solid"), radio = true, checked_func = function() return getBg() == "solid" end, callback = function() setString("qa_bg", "solid") end },
            { text = _("Light gray"), radio = true, checked_func = function() return getBg() == "flat" end, callback = function() setString("qa_bg", "flat") end },
        }
    end

local root_menu_items = {
    {
        text = function() return (isQAEnabled() and "✓ " or "  ") .. _("Enable tab") end,
        callback = function()
            local new_val = not isQAEnabled()
            setBool("qa_enabled", new_val)
            UIManager:show(ConfirmBox:new{
                text = _("Restart required.\n\nRestart KOReader now?"),
                ok_text = _("Restart"),
                cancel_text = _("Later"),
                ok_callback = function()
                    UIManager:restartKOReader()
                end,
            })
        end,
    },
   {
       text = function()
           local current = getString("qa_tab_icon")
           return _("Tab icon") .. ": " .. current
       end,
       close_on_click = true,
       callback = function()
           closeSettingsDialog()
           showIconPicker(
               function(file_path)
                   if file_path then
                       local filename_with_ext = file_path:match("([^/]+)$")
                       local filename = filename_with_ext:gsub("%.[^%.]+$", "")
                       setString("qa_tab_icon", filename)
                       UIManager:show(ConfirmBox:new{
                           text = _("Restart KOReader required. Restart now?"),
                           ok_text = _("Restart"),
                           cancel_text = _("Later"),
                           ok_callback = function()
                               UIManager:restartKOReader()
                           end,
                       })
                   end
               end,
               nil,  -- saved_icon
               "file"  -- Only show file icons
           )
       end,
    },
    {
        text = _("System icon replacement"),
        close_on_click = true,
        callback = function()
            closeSettingsDialog()
            showIconPicker(nil, nil, nil, "system")
        end,
    },
    {
        text = _("UI font switcher"),
        close_on_click = true,
        callback = function()
            closeSettingsDialog()
            showUIFontSwitcher()
        end,
    },
    {
        text = _("Interface filtering"),
        sub_item_table = function()
            return showInterfaceFilterMenu(touch_menu)
        end,
    },
    {
        text = _("Quick actions"),
        sub_item_table = getCustomActionSubMenu,
    },
    {
        text = _("Edit buttons"),
        sub_item_table = {
            {
                text = _("Reorder buttons") .. " ▸",
                close_on_click = true, 
                callback = function()
                    closeSettingsDialog()
                    local slots = getSlots()
                    local sort_items = {}
                    for i = 1, #slots do
                        local id = slots[i]
                        sort_items[#sort_items + 1] = { text = getLabelForAction(id), orig_item = id }
                    end
                    local sort_dialog = SortWidget:new{
                        title = _("Reorder buttons"),
                        item_table = sort_items,
                        covers_fullscreen = true,
                        callback = function()
                            local new_slots = {}
                            for j = 1, #sort_items do
                                new_slots[#new_slots + 1] = sort_items[j].orig_item
                            end
                            saveQASlots(new_slots)
                            refreshQuickPanel(touch_menu)
                        end,
                    }
                    UIManager:show(sort_dialog)
                end,
            },
            {
                text = _("Add button") .. " ▸",
                close_on_click = true,
                callback = function()
                    closeSettingsDialog()
                    showAddButtonMenu(touch_menu, function()
                        showSettingsMenu(touch_menu)
                    end)
                end,
            },
            {
                text = _("Button shape"),
                sub_item_table = getShapeSubMenu,
            },
            {
                text = _("Button background"),
                enabled = getShape() ~= "bare",
                sub_item_table = getBgSubMenu,
            },
            {
                text = function() return (showLabels() and "✓ " or "  ") .. _("Show labels") end,
                callback = function() setBool("qa_labels", not showLabels()) end,
            },
            {
                text = function() return _("Button size") .. ": " .. getButtonSizePct() .. "%" end,
                close_on_click = true,
                callback = function()
                    closeSettingsDialog()
                    local spin = SpinWidget:new{
                        title_text = _("Button size"),
                        value = getButtonSizePct(),
                        value_min = 60,
                        value_max = 150,
                        value_step = 5,
                        unit = "%",
                        callback = function(spin)
                            setNumber("qa_button_size_pct", spin.value)
                            refreshQuickPanel(touch_menu)
                        end,
                    }
                    UIManager:show(spin)
                end,
            },
            {
                text = function() return _("Label size") .. ": " .. getLabelScalePct() .. "%" end,
                close_on_click = true,
                callback = function()
                    closeSettingsDialog()
                    local spin = SpinWidget:new{
                        title_text = _("Label size"),
                        value = getLabelScalePct(),
                        value_min = 50,
                        value_max = 200,
                        value_step = 10,
                        unit = "%",
                        callback = function(spin)
                            setNumber("qa_label_scale_pct", spin.value)
                            refreshQuickPanel(touch_menu)
                        end,
                    }
                    UIManager:show(spin)
                end,
            },
        },
    },
    {
        text = function() return (buttonHoldEdit() and "✓ " or "  ") .. _("Long press button to edit") end,
        callback = function() 
            setBool("qa_button_hold_edit", not buttonHoldEdit())
            refreshQuickPanel(touch_menu)
        end,
    },
    {
        text = function() return (settingsOnHold() and "✓ " or "  ") .. _("Long press tab panel for settings") end,
        callback = function() setBool("qa_settings_on_hold", not settingsOnHold()) end,
    },
    {
        text = _("Save current as default"),
        close_on_click = true,
        callback = function()
            local json = require("json")
            local default_config = {
                qa_tab_icon = getString("qa_tab_icon"),
                qa_enabled = isQAEnabled(),
                qa_slots = json.decode(json.encode(getQASlots())),
                qa_frontlight = showFrontlight(),
                qa_warmth = showWarmth(),
                qa_shape = getShape(),
                qa_bg = getBg(),
                qa_labels = showLabels(),
                qa_label_scale_pct = getLabelScalePct(),
                qa_settings_on_hold = settingsOnHold(),
                qa_button_size_pct = getButtonSizePct(),
                qa_button_hold_edit = buttonHoldEdit(),
                custom_list = json.decode(json.encode(getSetting("custom_list"))),
                custom = json.decode(json.encode(getTable("custom"))),
                builtin_overrides = json.decode(json.encode(getTable("builtin_overrides"))),
                qa_context_filter = getBool("qa_context_filter"),
                qa_auto_add_to_panel = getBool("qa_auto_add_to_panel"),
                qa_slider_show_value = showSliderValue(),
                qa_filter_initialized = getBool("qa_filter_initialized"),
                qa_icon_overrides = json.decode(json.encode(getTable("qa_icon_overrides"))),
                ui_font_overrides = json.decode(json.encode(getTable("ui_font_overrides"))), 
            }
            setSetting("default_config", default_config)
            UIManager:show(Notification:new{
                text = _("Current configuration saved as default"),
                timeout = 2,
            })
        end,
    },
    {
        text = _("Apply default configuration"),
        close_on_click = true,
        callback = function()
            local default_config = getSetting("default_config")
            if not default_config or type(default_config) ~= "table" then
                UIManager:show(Notification:new{
                    text = _("No saved default configuration, please save first"),
                    timeout = 2,
                })
                return
            end
            setBool("qa_enabled", default_config.qa_enabled)
            setSetting("qa_slots", default_config.qa_slots)
            setBool("qa_frontlight", default_config.qa_frontlight)
            setBool("qa_warmth", default_config.qa_warmth)
            setString("qa_tab_icon", default_config.qa_tab_icon or "quickactions") 
            setString("qa_shape", default_config.qa_shape)
            setString("qa_bg", default_config.qa_bg)
            setBool("qa_labels", default_config.qa_labels)
            setNumber("qa_label_scale_pct", default_config.qa_label_scale_pct)
            setBool("qa_settings_on_hold", default_config.qa_settings_on_hold)
            setNumber("qa_button_size_pct", default_config.qa_button_size_pct)
            setBool("qa_button_hold_edit", default_config.qa_button_hold_edit)
            setSetting("custom_list", default_config.custom_list)
            setTable("custom", default_config.custom)
            setTable("builtin_overrides", default_config.builtin_overrides)
            setBool("qa_context_filter", default_config.qa_context_filter)
            setBool("qa_auto_add_to_panel", default_config.qa_auto_add_to_panel)
            setBool("qa_slider_show_value", default_config.qa_slider_show_value)
            setBool("qa_filter_initialized", default_config.qa_filter_initialized)
            setTable("qa_icon_overrides", default_config.qa_icon_overrides or {})
            setTable("ui_font_overrides", default_config.ui_font_overrides or {}) 
            -- Clear caches
            picker_cache = {}
            cached_file_icons = nil
            system_temp_overrides = nil
            -- Apply fonts
            applyUIFontChanges()
            refreshQuickPanel(touch_menu)
            UIManager:show(Notification:new{
                text = _("Default configuration applied"),
                timeout = 2,
            })
        end,
    },
    {
        text = _("Reset all settings"),
        close_on_click = true,
        callback = function()
            closeSettingsDialog()
            local confirm = ConfirmBox:new{
                text = _("Reset all settings to initial defaults?\nThis will clear all custom actions and your saved default configuration."),
                ok_text = _("Reset"),
                cancel_text = _("Cancel"),
                ok_callback = function()
                    resetAllSettings(touch_menu)
                    UIManager:show(Notification:new{
                        text = _("Settings reset"),
                        timeout = 2,
                    })
                end,
            }
            UIManager:show(confirm)
        end,
    },
    {
        text = _("About"),
        close_on_click = true,
        callback = function()
            closeSettingsDialog()
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = "quickactions - Quick Actions\n\n" ..
                       "Project URL:\n" ..
                       "GitHub: https://github.com/gytwo/kopatches\n" ..
                       "Gitee: https://gitee.com/gytwo/kopatches",
                timeout = 10,
            })
        end,
    },
}
    showMenu(root_menu_items, _("Quick Actions Settings"), nil, touch_menu, root_menu_items)
end

-- ============================================================
-- SlimSlider: thin rail slider
-- ============================================================

local SlimSlider = Widget:extend{
    width = 200,
    height = Screen:scaleBySize(28),
    minimum = 0,
    maximum = 100,
    value = 0,
    show_parent = nil,
    enabled = true,
}

function SlimSlider:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function SlimSlider:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function SlimSlider:setValue(v)
    self.value = math.max(self.minimum, math.min(self.maximum, v or 0))
end

function SlimSlider:getValueFromPosition(pos)
    if not self.dimen or not pos then return nil end
    local rel_x = pos.x - self.dimen.x
    rel_x = math.max(0, math.min(self.width, rel_x))
    local range = self.maximum - self.minimum
    if range <= 0 then return self.minimum end
    return self.minimum + (rel_x / self.width) * range
end

function SlimSlider:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    local track_h = Screen:scaleBySize(2)
    local thumb_w = Screen:scaleBySize(3)
    local thumb_h = Screen:scaleBySize(14)
    local cy = y + math.floor(self.height / 2)
    local range = math.max(1, self.maximum - self.minimum)
    local pct = (self.value - self.minimum) / range
    local fill_w = math.floor(pct * self.width)
    fill_w = math.max(0, math.min(self.width, fill_w))
    bb:paintRect(x, cy - math.floor(track_h / 2), self.width, track_h, Blitbuffer.COLOR_LIGHT_GRAY)
    if fill_w > 0 then
        bb:paintRect(x, cy - math.floor(track_h / 2), fill_w, track_h, Blitbuffer.COLOR_BLACK)
    end
    local tx = x + fill_w - math.floor(thumb_w / 2)
    tx = math.max(x, math.min(x + self.width - thumb_w, tx))
    bb:paintRect(tx, cy - math.floor(thumb_h / 2), thumb_w, thumb_h, Blitbuffer.COLOR_BLACK)
end

-- ============================================================
-- Panel builder
-- ============================================================

local function buildQSPanel(touch_menu)
    local slots = getQASlots()
    local panel_w = touch_menu.item_width
    local padding = Screen:scaleBySize(28)
    local inner_w = panel_w - padding * 2
    local base_btn_size = Screen:scaleBySize(60)
    local button_scale = getButtonSizePct() / 100
    local btn_size = math.floor(base_btn_size * button_scale)
    local icon_size = math.floor(btn_size * 0.52)
    local label_fs = math.max(6, math.floor(15 * getLabelScale()))
    local label_face = Font:getFace("cfont", label_fs)
    local medium_face = Font:getFace("ffont")
    local border_sz = 1
    local shape = getShape()
    local is_bare = (shape == "bare")

    local function makeButton(action_id)
        local label = getLabelForAction(action_id)
        local icon_path = getIconForAction(action_id)
        local icon_widget = getIconWidget(icon_path, icon_size)
        if not icon_widget then
            local first_char = label
            local chars = util.splitToChars(label)
            if chars and #chars > 0 then
                first_char = chars[1]
            end
            icon_widget = TextWidget:new{
                text = first_char,
                face = Font:getFace("cfont", math.floor(icon_size * 0.55)),
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
        end
        local corner_r
        if shape == "round" then
            corner_r = math.floor(btn_size / 2)
        elseif shape == "square_round" then
            corner_r = math.floor(btn_size / 4)
        else
            corner_r = math.floor(btn_size / 4)
        end
        local bg = getBg()
        local current_border = 0
        local bg_color = nil
        if not is_bare then
            current_border = (bg == "solid" or bg == "transparent") and border_sz or 0
            if bg == "flat" then
                bg_color = Blitbuffer.gray(0.08)
            elseif bg == "solid" then
                bg_color = Blitbuffer.COLOR_WHITE
            end
        end
        local btn_frame = FrameContainer:new{
            width = btn_size,
            height = btn_size,
            radius = corner_r,
            bordersize = current_border,
            color = current_border > 0 and Blitbuffer.gray(0.75) or nil,
            background = bg_color,
            padding = 0,
            CenterContainer:new{
                dimen = Geom:new{
                    w = btn_size - current_border * 2,
                    h = btn_size - current_border * 2,
                },
                icon_widget,
            },
        }
        local btn_wrapper = InputContainer:new{
            dimen = Geom:new{ w = btn_size, h = btn_size },
        }
        btn_wrapper[1] = btn_frame
        local function applyPressFeedback(widget)
            local original_bg = widget.background
            local original_color = widget.color
            widget.background = Blitbuffer.gray(0.3)
            if widget.color then
                widget.color = Blitbuffer.gray(0.3)
            end
            UIManager:setDirty(touch_menu.show_parent, function()
                return "ui", widget.dimen
            end)
            UIManager:scheduleIn(0.1, function()
                widget.background = original_bg
                widget.color = original_color
                UIManager:setDirty(touch_menu.show_parent, function()
                    return "ui", widget.dimen
                end)
            end)
        end
        local zones = {
            {
                id = "btn_tap_" .. action_id,
                ges = "tap",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
                },
                handler = function(ges)
                    local rel_x = ges.pos.x - (btn_wrapper.dimen and btn_wrapper.dimen.x or 0)
                    local rel_y = ges.pos.y - (btn_wrapper.dimen and btn_wrapper.dimen.y or 0)
                    if rel_x >= 0 and rel_x <= btn_size and rel_y >= 0 and rel_y <= btn_size then
                        applyPressFeedback(btn_frame)
                        local stay_open = isInPlace(action_id)
                        if stay_open then
                            executeAction(action_id, {touch_menu = touch_menu})
                            touch_menu:updateItems()
                        else
                            UIManager:scheduleIn(0.05, function()
                                executeAction(action_id, {touch_menu = touch_menu})
                            end)
                        end
                        return true
                    end
                    return false
                end,
            },
        }
        if buttonHoldEdit() then
            table.insert(zones, {
                id = "btn_hold_" .. action_id,
                ges = "hold",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
                },
                handler = function(ges)
                    local rel_x = ges.pos.x - (btn_wrapper.dimen and btn_wrapper.dimen.x or 0)
                    local rel_y = ges.pos.y - (btn_wrapper.dimen and btn_wrapper.dimen.y or 0)
                    if rel_x >= 0 and rel_x <= btn_size and rel_y >= 0 and rel_y <= btn_size then
                        local is_builtin = false
                        if ACTION_ORDER then
                            for _, builtin_id in ipairs(ACTION_ORDER) do
                                if builtin_id == action_id then
                                    is_builtin = true
                                    break
                                end
                            end
                        end
                        if is_builtin then
                            showEditActionDialog(action_id, function()
                                refreshQuickPanel(touch_menu)
                            end)
                        else
                            showCustomQADialog(action_id, function()
                                refreshQuickPanel(touch_menu)
                            end)
                        end
                        return true
                    end
                    return false
                end,
            })
        end
        btn_wrapper:registerTouchZones(zones)
        btn_wrapper.onShow = function()
        end
        local vg = VerticalGroup:new{ align = "center", btn_wrapper }
        if showLabels() then
            local lbl_w = btn_size + Screen:scaleBySize(6)
            table.insert(vg, VerticalSpan:new{ width = Screen:scaleBySize(2) })
            table.insert(vg, CenterContainer:new{
                dimen = Geom:new{ w = lbl_w, h = label_face.size },
                TextWidget:new{
                    text = label,
                    face = label_face,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    max_width = lbl_w,
                    width = lbl_w,
                    truncate_with_ellipsis = true,
                },
            })
        end
        return vg, btn_frame
    end

    local context_filter_enabled = getBool("qa_context_filter")
    local current_view = "filemanager"
    if context_filter_enabled then
        local RUI = require("apps/reader/readerui")
        local in_reader = RUI and RUI.instance and not RUI.instance.tearing_down
        current_view = in_reader and "reader" or "filemanager"
    end
    local visible_slots = {}
    for _, id in ipairs(slots) do
        local action = getAction(id)
        if action then
            if isActionVisible(id, current_view) then
                visible_slots[#visible_slots + 1] = id
            end
        end
    end
    local n = #visible_slots
    local fixed_gap = Screen:scaleBySize(8)
    local max_per_row = math.max(1, math.floor((inner_w + fixed_gap) / (btn_size + fixed_gap)))
    local rows = {}
    for i = 1, n, max_per_row do
        local row_slots = {}
        for j = i, math.min(i + max_per_row - 1, n) do
            table.insert(row_slots, visible_slots[j])
        end
        table.insert(rows, row_slots)
    end
    local rows_vg = VerticalGroup:new{ align = "center" }
    local row_gap = Screen:scaleBySize(8)
    local refs = { buttons = {} }
    if n > 0 then
        for ri, row_slots in ipairs(rows) do
            local row_n = #row_slots
            local gap = (row_n > 1) and math.max(0, math.floor((inner_w - row_n * btn_size) / (row_n - 1))) or 0
            local hg = HorizontalGroup:new{ align = "center" }
            for i, action_id in ipairs(row_slots) do
                local vg, btn_frame = makeButton(action_id)
                local _aid = action_id
                table.insert(refs.buttons, {
                    widget = btn_frame,
                    callback = function()
                        local stay_open = isInPlace(_aid)
                        if stay_open then
                            executeAction(_aid, {touch_menu = touch_menu})
                            touch_menu:updateItems()
                        else
                            UIManager:scheduleIn(0, function()
                                executeAction(_aid, {touch_menu = touch_menu})
                            end)
                        end
                        return stay_open
                    end,
                })
                table.insert(hg, vg)
                if i < row_n then
                    table.insert(hg, HorizontalSpan:new{ width = gap })
                end
            end
            table.insert(rows_vg, hg)
            if ri < #rows then
                table.insert(rows_vg, VerticalSpan:new{ width = row_gap })
            end
        end
    else
        table.insert(rows_vg, TextWidget:new{
            text = _("No actions configured"),
            face = Font:getFace("cfont"),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        })
    end
    local panel = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = Screen:scaleBySize(20) },
        CenterContainer:new{ dimen = Geom:new{ w = panel_w, h = rows_vg:getSize().h }, rows_vg },
        VerticalSpan:new{ width = Screen:scaleBySize(16) },
    }
    if showFrontlight() and Device:hasFrontlight() then
        local powerd = Device:getPowerDevice()
        local fl = {
            min = powerd.fl_min,
            max = powerd.fl_max,
            cur = powerd:frontlightIntensity(),
        }
        local small_btn_w = Screen:scaleBySize(40)
        local max_btn_w = Screen:scaleBySize(50)
        local slider_gap = Screen:scaleBySize(4)
        local slider_width = inner_w - 2 * small_btn_w - max_btn_w - 3 * slider_gap
        local fl_label = nil
        if showSliderValue() then
            fl_label = TextWidget:new{
                text = _("Frontlight") .. ": " .. tostring(fl.cur),
                face = medium_face,
                max_width = inner_w,
            }
        end
        local _dummy = Button:new{ text = "−", width = small_btn_w, show_parent = touch_menu.show_parent, callback = function() end }
        local btn_height = math.max(30, _dummy:getSize().h)
        local fl_slider = SlimSlider:new{
            width = slider_width,
            height = btn_height,
            minimum = fl.min,
            maximum = fl.max,
            value = fl.cur,
            show_parent = touch_menu.show_parent,
            enabled = true,
        }
        local fl_saved_brightness = (fl.cur > fl.min) and fl.cur or fl.max
        local fl_toggle_btn
        local function updateFLWidgets()
            fl_slider:setValue(fl.cur)
            if fl_label then
                fl_label:setText(_("Frontlight") .. ": " .. tostring(fl.cur))
            end
            if fl_toggle_btn then
                fl_toggle_btn:setText(fl.cur > fl.min and "ON" or "OFF")
            end
            UIManager:setDirty(touch_menu.show_parent, "ui")
        end
        local function setBrightness(intensity)
            if intensity ~= fl.min and intensity == fl.cur then return end
            intensity = math.max(fl.min, math.min(fl.max, intensity))
            powerd:setIntensity(intensity)
            fl.cur = powerd:frontlightIntensity()
            updateFLWidgets()
        end
        local fl_minus = Button:new{
            text = "−", width = small_btn_w, show_parent = touch_menu.show_parent,
            callback = function() setBrightness(fl.cur - 1) end,
            bordersize = 0,
            background = nil,
            framebg = nil,
        }
        local fl_plus = Button:new{
            text = "＋", width = small_btn_w, show_parent = touch_menu.show_parent,
            callback = function() setBrightness(fl.cur + 1) end,
            bordersize = 0,
            background = nil,
            framebg = nil,
        }
        fl_toggle_btn = Button:new{
            text = fl.cur > fl.min and "ON" or "OFF",
            width = max_btn_w,
            show_parent = touch_menu.show_parent,
            callback = function()
                if fl.cur > fl.min then
                    fl_saved_brightness = fl.cur
                    setBrightness(fl.min)
                else
                    setBrightness(fl_saved_brightness)
                end
            end,
            bordersize = 0,
            background = nil,
            framebg = nil,
        }
        local fl_row = HorizontalGroup:new{
            align = "center",
            fl_minus,
            HorizontalSpan:new{ width = slider_gap },
            fl_slider,
            HorizontalSpan:new{ width = slider_gap },
            fl_plus,
            HorizontalSpan:new{ width = slider_gap },
            fl_toggle_btn,
        }
        local fl_group = VerticalGroup:new{ align = "center" }
        if fl_label then
            table.insert(fl_group, fl_label)
            table.insert(fl_group, VerticalSpan:new{ width = Screen:scaleBySize(6) })
        end
        table.insert(fl_group, fl_row)
        table.insert(panel, VerticalSpan:new{ width = Screen:scaleBySize(10) })
        table.insert(panel, CenterContainer:new{ dimen = Geom:new{ w = panel_w, h = fl_group:getSize().h }, fl_group })
        refs.fl_slider = fl_slider
        refs.setBrightness = setBrightness
    end
    if showWarmth() and Device:hasNaturalLight() then
        local powerd = Device:getPowerDevice()
        local nl = {
            min = powerd.fl_warmth_min,
            max = powerd.fl_warmth_max,
            cur = powerd:toNativeWarmth(powerd:frontlightWarmth()),
        }
        local small_btn_w = Screen:scaleBySize(40)
        local max_btn_w = Screen:scaleBySize(50)
        local slider_gap = Screen:scaleBySize(4)
        local warmth_slider_w = inner_w - 2 * small_btn_w - max_btn_w - 3 * slider_gap
        local nl_label = nil
        if showSliderValue() then
            nl_label = TextWidget:new{
                text = _("Warmth") .. ": " .. tostring(nl.cur),
                face = medium_face,
                max_width = inner_w,
            }
        end
        local _dummy2 = Button:new{ text = "−", width = small_btn_w, show_parent = touch_menu.show_parent, callback = function() end }
        local btn_height2 = math.max(30, _dummy2:getSize().h)
        local nl_slider = SlimSlider:new{
            width = warmth_slider_w,
            height = btn_height2,
            minimum = nl.min,
            maximum = nl.max,
            value = nl.cur,
            show_parent = touch_menu.show_parent,
            enabled = true,
        }
        local function setWarmth(warmth)
            if warmth == nl.cur then return end
            warmth = math.max(nl.min, math.min(nl.max, warmth))
            powerd:setWarmth(powerd:fromNativeWarmth(warmth))
            nl.cur = powerd:toNativeWarmth(powerd:frontlightWarmth())
            nl_slider:setValue(nl.cur)
            if nl_label then
                nl_label:setText(_("Warmth") .. ": " .. tostring(nl.cur))
            end
            UIManager:setDirty(touch_menu.show_parent, "ui")
        end
        local nl_minus = Button:new{
            text = "−", width = small_btn_w, show_parent = touch_menu.show_parent,
            callback = function() setWarmth(nl.cur - 1) end,
            bordersize = 0,
            background = nil,
            framebg = nil,
        }
        local nl_plus = Button:new{
            text = "＋", width = small_btn_w, show_parent = touch_menu.show_parent,
            callback = function() setWarmth(nl.cur + 1) end,
            bordersize = 0,
            background = nil,
            framebg = nil,
        }
        local nl_max_btn = Button:new{
            text = _("Max"), width = max_btn_w, show_parent = touch_menu.show_parent,
            callback = function() setWarmth(nl.max) end,
            bordersize = 0,
            background = nil,
            framebg = nil,
        }
        local nl_row = HorizontalGroup:new{
            align = "center",
            nl_minus,
            HorizontalSpan:new{ width = slider_gap },
            nl_slider,
            HorizontalSpan:new{ width = slider_gap },
            nl_plus,
            HorizontalSpan:new{ width = slider_gap },
            nl_max_btn,
        }
        local warmth_group = VerticalGroup:new{ align = "center" }
        table.insert(warmth_group, VerticalSpan:new{ width = Screen:scaleBySize(12) })
        if nl_label then
            table.insert(warmth_group, nl_label)
            table.insert(warmth_group, VerticalSpan:new{ width = Screen:scaleBySize(6) })
        end
        table.insert(warmth_group, nl_row)
        table.insert(panel, CenterContainer:new{ dimen = Geom:new{ w = panel_w, h = warmth_group:getSize().h }, warmth_group })
        refs.nl_slider = nl_slider
    end
    table.insert(panel, VerticalSpan:new{ width = Screen:scaleBySize(14) })
    local panel_h = panel:getSize().h
    local ic = InputContainer:new{ dimen = Geom:new{ w = panel_w, h = panel_h }, [1] = panel }
    ic.ges_events = {
        HoldPanel = { GestureRange:new{ ges = "hold", range = function() return ic.dimen end } },
    }
    function ic:onHoldPanel()
        if not settingsOnHold() then return false end
        showSettingsMenu(touch_menu)
        return true
    end
    return ic, refs
end

-- ============================================================
-- TouchMenu patches
-- ============================================================

local TouchMenu = require("ui/widget/touchmenu")
local FocusManager = require("ui/widget/focusmanager")
local _orig_updateItems = TouchMenu.updateItems
local _orig_onTap = TouchMenu.onTapCloseAllMenus
local _orig_onSwipe = TouchMenu.onSwipe
local _orig_onPan = TouchMenu.onPan

function TouchMenu:updateItems(target_page, target_item_id)
    if not self.item_table or not self.item_table._qs_panel then
        self._qs_refs = nil
        return _orig_updateItems(self, target_page, target_item_id)
    end
    -- Fix: set page and page_num to prevent onNextPage errors
    self.page = 1
    self.page_num = 1
    
    self.item_group:clear()
    self.layout = {}
    table.insert(self.item_group, self.bar)
    table.insert(self.layout, self.bar.icon_widgets)
    local panel, refs = buildQSPanel(self)
    self._qs_refs = refs
    table.insert(self.item_group, panel)
    table.insert(self.item_group, self.footer_top_margin)
    table.insert(self.item_group, self.footer)
    self.page_info_text:setText("")
    self.page_info_left_chev:showHide(false)
    self.page_info_right_chev:showHide(false)
    if self.page_info_left_chev then
        self.page_info_left_chev.hold_callback = nil
    end
    if self.page_info_right_chev then
        self.page_info_right_chev.hold_callback = nil
    end
    local G = rawget(_G, "G_reader_settings")
    local time_txt = datetime.secondsToHour(os.time(), G and G:isTrue("twelve_hour_clock") or false)
    if Device:hasBattery() then
        local powerd = Device:getPowerDevice()
        local lvl = powerd:getCapacity()
        local sym = powerd:getBatterySymbol(powerd:isCharged(), powerd:isCharging(), lvl)
        time_txt = BD.wrap(time_txt) .. " " .. BD.wrap("⌁") .. BD.wrap(sym) .. BD.wrap(lvl .. "%")
    end
    self.time_info:setText(time_txt)
    local old_dimen = self.dimen:copy()
    self.dimen.w = self.width
    self.dimen.h = self.item_group:getSize().h + self.bordersize * 2 + self.padding
    self:moveFocusTo(self.cur_tab, 1, FocusManager.NOT_FOCUS)
    local keep_bg = old_dimen and self.dimen.h >= old_dimen.h
    UIManager:setDirty(
        (self.is_fresh or keep_bg) and self.show_parent or "all",
        function()
            local refresh_dimen = old_dimen and old_dimen:combine(self.dimen) or self.dimen
            local refresh_type = self.is_fresh and "flashui" or "ui"
            self.is_fresh = false
            return refresh_type, refresh_dimen
        end)
end

function TouchMenu:onTapCloseAllMenus(arg, ges_ev)
    if self._qs_refs and self.item_table and self.item_table._qs_panel then
        if self._qs_refs.fl_slider and self._qs_refs.fl_slider.dimen and ges_ev.pos:intersectWith(self._qs_refs.fl_slider.dimen) then
            local new_val = self._qs_refs.fl_slider:getValueFromPosition(ges_ev.pos)
            if new_val and self._qs_refs.setBrightness then
                self._qs_refs.setBrightness(math.floor(new_val + 0.5))
                return true
            end
        end
        if self._qs_refs.nl_slider and self._qs_refs.nl_slider.dimen and ges_ev.pos:intersectWith(self._qs_refs.nl_slider.dimen) then
            local new_val = self._qs_refs.nl_slider:getValueFromPosition(ges_ev.pos)
            if new_val then
                local powerd = Device:getPowerDevice()
                powerd:setWarmth(powerd:fromNativeWarmth(math.floor(new_val + 0.5)))
                return true
            end
        end
        for _, ref in ipairs(self._qs_refs.buttons or {}) do
            if ref.widget.dimen and ges_ev.pos:intersectWith(ref.widget.dimen) then
                local stay_open = ref.callback()
                if stay_open then
                    return true
                end
                self:onClose()
                return true
            end
        end
    end
    return _orig_onTap(self, arg, ges_ev)
end

function TouchMenu:onSwipe(arg, ges_ev)
    if self._qs_refs and self.item_table and self.item_table._qs_panel then
        if self._qs_refs.fl_slider and self._qs_refs.fl_slider.dimen and ges_ev.pos:intersectWith(self._qs_refs.fl_slider.dimen) then
            local new_val = self._qs_refs.fl_slider:getValueFromPosition(ges_ev.pos)
            if new_val and self._qs_refs.setBrightness then
                self._qs_refs.setBrightness(math.floor(new_val + 0.5))
                return true
            end
        end
        if self._qs_refs.nl_slider and self._qs_refs.nl_slider.dimen and ges_ev.pos:intersectWith(self._qs_refs.nl_slider.dimen) then
            local new_val = self._qs_refs.nl_slider:getValueFromPosition(ges_ev.pos)
            if new_val then
                local powerd = Device:getPowerDevice()
                powerd:setWarmth(powerd:fromNativeWarmth(math.floor(new_val + 0.5)))
                return true
            end
        end
        for _, ref in ipairs(self._qs_refs.buttons or {}) do
            if ref.widget.dimen and ges_ev.pos:intersectWith(ref.widget.dimen) then
                local stay_open = ref.callback()
                if stay_open then
                    return true
                end
                self:onClose()
                return true
            end
        end
    end
    if _orig_onSwipe then
        return _orig_onSwipe(self, arg, ges_ev)
    end
end

function TouchMenu:onPan(arg, ges_ev)
    if self._qs_refs and self.item_table and self.item_table._qs_panel then
        if self._qs_refs.fl_slider and self._qs_refs.fl_slider.dimen and ges_ev.pos:intersectWith(self._qs_refs.fl_slider.dimen) then
            local new_val = self._qs_refs.fl_slider:getValueFromPosition(ges_ev.pos)
            if new_val and self._qs_refs.setBrightness then
                self._qs_refs.setBrightness(math.floor(new_val + 0.5))
                return true
            end
        end
        if self._qs_refs.nl_slider and self._qs_refs.nl_slider.dimen and ges_ev.pos:intersectWith(self._qs_refs.nl_slider.dimen) then
            local new_val = self._qs_refs.nl_slider:getValueFromPosition(ges_ev.pos)
            if new_val then
                local powerd = Device:getPowerDevice()
                powerd:setWarmth(powerd:fromNativeWarmth(math.floor(new_val + 0.5)))
                return true
            end
        end
    end
    if _orig_onPan then
        return _orig_onPan(self, arg, ges_ev)
    end
end

-- ============================================================
-- Prefer quick action panel
-- ============================================================

local function patchFileManagerMenuClose()
    local ok, FileManagerMenu = pcall(require, "apps/filemanager/filemanagermenu")
    if not ok or not FileManagerMenu then return end
    if FileManagerMenu._qs_fm_close_patched then return end
    FileManagerMenu._qs_fm_close_patched = true
    local orig_onCloseFileManagerMenu = FileManagerMenu.onCloseFileManagerMenu
    FileManagerMenu.onCloseFileManagerMenu = function(self)
        if self.menu_container and self.menu_container[1] then
            self.menu_container[1].last_index = 1
        end
        return orig_onCloseFileManagerMenu(self)
    end
end

local function patchReaderMenuClose()
    local ok, ReaderMenu = pcall(require, "apps/reader/modules/readermenu")
    if not ok or not ReaderMenu then return end
    if ReaderMenu._qs_reader_close_patched then return end
    ReaderMenu._qs_reader_close_patched = true
    local orig_onCloseReaderMenu = ReaderMenu.onCloseReaderMenu
    ReaderMenu.onCloseReaderMenu = function(self)
        if self.menu_container and self.menu_container[1] then
            self.menu_container[1].last_index = 1
            self.last_tab_index = 1
        end
        return orig_onCloseReaderMenu(self)
    end
end

-- ============================================================
-- Inject tab into menu
-- ============================================================

local QS_PANEL_TAB = {
    icon = getString("qa_tab_icon"),   -- "quickactions"
    remember = false,
    _qs_panel = true,
}

local function injectPanelTab(m_self)
    if not isQAEnabled() then return end
    if type(m_self.tab_item_table) ~= "table" then return end
    for _, tab in ipairs(m_self.tab_item_table) do
        if tab._qs_panel then return end
    end
    table.insert(m_self.tab_item_table, 1, QS_PANEL_TAB)
end

local function patchFileManagerMenu()
    local FMMenu = require("apps/filemanager/filemanagermenu")
    if FMMenu._qs_tab_patched then return end
    FMMenu._qs_tab_patched = true
    local orig_sut = FMMenu.setUpdateItemTable
    FMMenu.setUpdateItemTable = function(m_self)
        local FileManagerMenuOrder = require("ui/elements/filemanager_menu_order")
        if FileManagerMenuOrder.tools then
            local already = false
            for _, v in ipairs(FileManagerMenuOrder.tools) do
                if v == "qa_settings" then already = true; break end
            end
            if not already then
                table.insert(FileManagerMenuOrder.tools, 1, "----------------------------")
                table.insert(FileManagerMenuOrder.tools, 2, "qa_settings")
            end
        end
        if not m_self.menu_items then
            m_self.menu_items = {}
        end
        m_self.menu_items.qa_settings = {
            text = _("Quick Actions Settings"),
            callback = function()
                showSettingsMenu()
            end,
        }
        orig_sut(m_self)
        injectPanelTab(m_self)
    end
    local fm = require("apps/filemanager/filemanager").instance
    if fm and fm.menu and fm.menu.setUpdateItemTable then
        fm.menu:setUpdateItemTable()
    end
end

local function patchReaderMenu()
    local RMenu = require("apps/reader/modules/readermenu")
    if RMenu._qs_tab_patched then return end
    RMenu._qs_tab_patched = true
    local orig_sut = RMenu.setUpdateItemTable
    RMenu.setUpdateItemTable = function(m_self)
        local ReaderMenuOrder = require("ui/elements/reader_menu_order")
        if ReaderMenuOrder.tools then
            local already = false
            for _, v in ipairs(ReaderMenuOrder.tools) do
                if v == "qa_settings" then already = true; break end
            end
            if not already then
                table.insert(ReaderMenuOrder.tools, "qa_settings")
            end
        end
        if not m_self.menu_items then
            m_self.menu_items = {}
        end
        m_self.menu_items.qa_settings = {
            text = _("Quick Actions Settings"),
            callback = function()
                showSettingsMenu()
            end,
        }
        orig_sut(m_self)
        injectPanelTab(m_self)
    end
    local orig_show_menu = RMenu.onShowMenu
    RMenu.onShowMenu = function(m_self, ...)
        if m_self.tab_item_table then
            local tabs = m_self.tab_item_table
            for i, tab in ipairs(tabs) do
                if tab.id == "filemanager" or (tab.text and tab.text == _("File manager")) then
                    if i < #tabs then
                        table.remove(tabs, i)
                        table.insert(tabs, tab)
                    end
                    break
                end
            end
            injectPanelTab(m_self)
        end
        return orig_show_menu(m_self, ...)
    end
    local readerui = require("apps/reader/readerui").instance
    if readerui and readerui.menu then
        readerui.menu:onCloseMenu()
        readerui.menu:onShowMenu()
    end
end

-- ============================================================
-- Patch IconWidget to support user icon overrides
-- ============================================================

local function patchIconWidget()
    local IconWidget = require("ui/widget/iconwidget")
    if IconWidget._qa_patched then return end
    IconWidget._qa_patched = true
    
    local orig_init = IconWidget.init
    function IconWidget:init()
        if self.icon then
            local overrides = getTable("qa_icon_overrides")
            if overrides and overrides[self.icon] then
                local user_icon = overrides[self.icon]
                local dir = getIconsDir()
                local full_path = dir .. "/" .. user_icon
                if lfs.attributes(full_path, "mode") == "file" then
                    self.file = full_path
                    self.icon = nil
                elseif lfs.attributes(user_icon, "mode") == "file" then
                    self.file = user_icon
                    self.icon = nil
                end
            end
        end
        return orig_init(self)
    end
end

-- ============================================================
-- Gesture registration
-- ============================================================

local function registerGestures()
    Dispatcher:registerAction("quick_actions_panel", {
        category = "none",
        event = "QuickActionsPanel",
        title = _("QA: Quick Actions Panel"),
        general = true,
    })

    Dispatcher:registerAction("qa_settings_action", {
        category = "none",
        event = "QuickActionsSettings",
        title = _("QA: Quick Actions Settings"),
        general = true,
    })

    local FileManager = require("apps/filemanager/filemanager")
    if FileManager and not FileManager._qs_gesture_added then
        function FileManager:onQuickActionsPanel()
            local menu = self.menu
            if menu then
                if not menu.menu_container or not menu.menu_container[1] then
                    menu:onShowMenu()
                end
                local target_menu = menu.menu_container and menu.menu_container[1]
                if target_menu then
                    for i, tab in ipairs(target_menu.tab_item_table or {}) do
                        if tab._qs_panel then
                            target_menu:switchMenuTab(i)
                            break
                        end
                    end
                end
            end
            return true
        end

        function FileManager:onQuickActionsSettings()
            showSettingsMenu()
            return true
        end
        FileManager._qs_gesture_added = true
    end

    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI and not ReaderUI._qs_gesture_added then
        function ReaderUI:onQuickActionsPanel()
            local menu = self.menu
            if menu then
                if not menu.menu_container or not menu.menu_container[1] then
                    menu:onShowMenu()
                end
                local target_menu = menu.menu_container and menu.menu_container[1]
                if target_menu then
                    for i, tab in ipairs(target_menu.tab_item_table or {}) do
                        if tab._qs_panel then
                            target_menu:switchMenuTab(i)
                            break
                        end
                    end
                end
            end
            return true
        end

        function ReaderUI:onQuickActionsSettings()
            showSettingsMenu()
            return true
        end
        ReaderUI._qs_gesture_added = true
    end
end

-- ============================================================
-- Initialization
-- ============================================================

local function initDefaultDedicatedLists()
    if getBool("qa_filter_initialized") then return end
    setBool("qa_filter_initialized", true)
    logger.info("[QuickActions] Dedicated list initialization complete")
end

local function install()
    logger.info("[QuickActions] Installing...")
    patchFileManagerMenuClose()
    patchReaderMenuClose()
    patchFileManagerMenu()
    patchReaderMenu()
    registerGestures()
    initDefaultDedicatedLists()
    patchIconWidget() 
    logger.info("[QuickActions] Installation complete, config path:", CONFIG_PATH)
end

install()

logger.info("[QuickActions] Load complete")