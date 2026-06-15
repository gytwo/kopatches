-- 2-quickactions.lua - Quick Actions Panel for KOReader
-- 增强版：集成菜单录制、Nerd Font、5种动作类型、独立存储
-- 安装：放入 koreader/patches/ 目录
-- 卸载：删除本文件，同时删除 koreader/settings/quickactions.lua（可选）

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

logger.info("[QuickActions] 加载中...")

-- ButtonDialog 全局补丁：设置默认每页行数
local _orig_ButtonDialog_new = ButtonDialog.new
function ButtonDialog.new(_, ...)
    local args = ... or {}
    if type(args) == "table" and args.rows_per_page == nil then
        args.rows_per_page = 10
    end
    return _orig_ButtonDialog_new(_, args)
end

-- ============================================================
-- 默认配置
-- ============================================================

local DEFAULT_CONFIG = {
    qa_tab_icon = "quickactions",
    qa_enabled = true,
    qa_slots = { "wifi", "night", "rotate", "restart", "search","qa_add_button","qa_new"},
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
    qa_context_filter = false,
    qa_auto_add_to_panel = true,
    qa_button_hold_edit = true,
    qa_slider_show_value = false,
    version = 1,
}

-- 硬性限制
local MAX_SLOTS = 48

-- ============================================================
-- 独立存储
-- ============================================================

local function getConfigPath()
    local ok, DataStorage = pcall(require, "datastorage")
    if ok and DataStorage then
        return DataStorage:getSettingsDir() .. "/quickactions.lua"
    end
    return "quickactions.lua"
end

local CONFIG_PATH = getConfigPath()
local CONFIG_DATA = nil

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
    
    local f = io.open(CONFIG_PATH, "r")
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
                    logger.info("[QuickActions] 配置加载成功")
                    return CONFIG_DATA
                else
                    logger.warn("[QuickActions] pcall 失败:", err)
                end
            else
                logger.warn("[QuickActions] load 失败:", err)
            end
        end
        logger.warn("[QuickActions] 配置文件损坏，使用默认配置覆盖")
        CONFIG_DATA = DEFAULT_CONFIG
        saveConfig()
        return CONFIG_DATA
    end
    
    logger.info("[QuickActions] 配置文件不存在，创建默认配置")
    CONFIG_DATA = DEFAULT_CONFIG
    saveConfig()
    return CONFIG_DATA
end

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
    -- 深拷贝 value，避免引用传递
    local json = require("json")
    local value_copy = json.decode(json.encode(value))
    cfg[key] = value_copy
    saveConfig()
end

-- 重置所有配置（即时生效）
local function resetAllSettings(touch_menu)
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
        logger.info("[QuickActions] 配置文件已重写:", CONFIG_PATH)
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
    
    logger.info("[QuickActions] 配置已重置为默认值")
end

-- ============================================================
-- 便捷配置访问函数
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

local function contextFilterEnabled()
    return getBool("qa_context_filter")
end

-- ============================================================
-- Nerd Font 支持
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
-- 图标目录
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
    
    if icon_name:sub(1,1) == "/" then
        if lfs.attributes(icon_name, "mode") == "file" then
            return icon_name
        end
        return nil
    end
    
    local dir = getIconsDir()
    local path = dir .. "/" .. icon_name
    if lfs.attributes(path, "mode") == "file" then
        return path
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
-- 内置图标选择器（完全独立，不依赖外部模块）
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
    self.title = _('选择图标')
    
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
        local real_path = ffiUtil.realpath(path) or path
        if self.show_parent then
            self.show_parent:onClose()
        end
        if self.onConfirm then
            self.onConfirm(real_path)
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

    local lfs_check = require("libs/libkoreader-lfs")
    
    -- 获取当前工作目录的绝对路径
    local function toAbsolutePath(path)
        if path:sub(1,1) == "." then
            local current_dir = lfs.currentdir() or ""
            local abs = current_dir .. "/" .. path:gsub("^%.?/?", "")
            abs = abs:gsub("//+", "/")
            return abs
        end
        return path
    end
    
    -- 检查路径顺序
    local paths_to_check = {
        self.path,                    -- koreader/icons
        "./resources/icons/mdlight",          -- koreader/resources/icons/mdlight
        "./"                          -- koreader 根目录
    }
    
    local final_path = nil
    for _, path in ipairs(paths_to_check) do
        if lfs_check.attributes(path, "mode") == "directory" then
            final_path = toAbsolutePath(path)
            logger.info("[QuickActions] 使用图标目录:", final_path)
            break
        end
    end
    
    if not final_path then
        logger.warn("[QuickActions] 无法找到任何可用目录")
        UIManager:show(InfoMessage:new{
            text = _("找不到图标目录，无法打开图标浏览器"),
            timeout = 3,
        })
        return
    end
    
    self.path = final_path

    self._filter_input = InputText:new{
        text = "",
        hint = _("按名称筛选…"),
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

local function showNerdIconPreview(sentinel, on_confirm, on_cancel)
    local hex = sentinel:match("nerd:(.+)")
    UIManager:show(ConfirmBox:new{
        text = ("U+%s  %s"):format(hex, nerdIconChar(sentinel)) .. "\n\n" .. _("使用这个 Nerd Font 图标？"),
        ok_text = _("确定"),
        cancel_text = _("取消"),
        ok_callback = function() on_confirm(sentinel) end,
        cancel_callback = function() if on_cancel then on_cancel() end end,
    })
end

local function showNerdIconInput(current_icon, on_select, on_cancel)
    local current_hex = ""
    if current_icon then
        current_hex = current_icon:match("^nerd:([0-9A-Fa-f]+)$") or ""
    end
    local dlg
    local function openInputDlg()
        dlg = InputDialog:new{
            title = _("Nerd Font 图标"),
            input = current_hex:upper(),
            input_hint = _("十六进制码位, 如 E001"),
            description = _("输入 Nerd Fonts 符号的 Unicode 码位(十六进制)。\n留空并确定可移除 Nerd Font 图标。"),
            buttons = {{
                {
                    text = _("取消"),
                    callback = function()
                        UIManager:close(dlg)
                        if on_cancel then on_cancel() end
                    end,
                },
                {
                    text = _("确定"),
                    is_enter_default = true,
                    callback = function()
                        local raw = dlg:getInputText()
                        if raw:match("^%s*$") then
                            UIManager:close(dlg)
                            on_select(nil)
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
                                    text = _("无效的 Unicode 码位"),
                                    timeout = 3,
                                })
                            end
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("请输入 1-6 位十六进制数字 (0-9, A-F)"),
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

local function showNerdFontBrowser(on_select)
    local _ = require("gettext")
    local Screen = require("device").screen
    local Geom = require("ui/geometry")
    local Blitbuffer = require("ffi/blitbuffer")
    local Font = require("ui/font")
    local Size = require("ui/size")
    local UIManager = require("ui/uimanager")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local TextWidget = require("ui/widget/textwidget")
    local Button = require("ui/widget/button")
    
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local pad = Screen:scaleBySize(24)  
    local brd = Screen:scaleBySize(1) 
  
    -- ... 图标列表 ...
    local icons_list = {
        { hex = "F002" }, { hex = "E690" }, { hex = "F021" }, { hex = "F01E" },
        { hex = "EB4D" }, { hex = "F00C" }, { hex = "F14A" }, { hex = "2610" },
        { hex = "2611" }, { hex = "002B" }, { hex = "F067" }, { hex = "F0FE" },
        { hex = "F142" }, { hex = "F143" }, { hex = "F068" }, { hex = "F00D" },
        { hex = "F011" }, { hex = "F0AB" }, { hex = "F08B" }, { hex = "F236" },
        { hex = "F023" }, { hex = "F09C" }, { hex = "F015" }, { hex = "F06A" },
        { hex = "F071" }, { hex = "F1F8" }, { hex = "F1F4" }, { hex = "F02D" },
        { hex = "F02E" }, { hex = "F02C" }, { hex = "F1C3" }, { hex = "F187" },
        { hex = "F02A" }, { hex = "F02B" }, { hex = "F0CA" }, { hex = "F1DA" },
        { hex = "F07C" }, { hex = "F07B" }, { hex = "F115" }, { hex = "F14A" },
        { hex = "F15B" }, { hex = "F1C0" }, { hex = "F0A0" }, { hex = "F1C1" },
        { hex = "F0CE" }, { hex = "F303" }, { hex = "F044" }, { hex = "F0EA" },
        { hex = "F0C5" }, { hex = "F0E2" }, { hex = "F0DE" }, { hex = "F05A" },
        { hex = "F059" }, { hex = "2328" }, { hex = "F11C" }, { hex = "F031" },
        { hex = "F16C" }, { hex = "0041" }, { hex = "6587" }, { hex = "5B57" },
        { hex = "270D" }, { hex = "F040" }, { hex = "F121" }, { hex = "F126" },
        { hex = "ECA8" }, { hex = "ECA9" }, { hex = "F0C1" }, { hex = "F0E0" },
        { hex = "F09E" }, { hex = "F019" }, { hex = "F093" }, { hex = "F1D8" },
        { hex = "F1D9" }, { hex = "F0C2" }, { hex = "F1ED" }, { hex = "E6AD" },
        { hex = "F0EC" }, { hex = "F13E" }, { hex = "F09C" }, { hex = "F0AC" },
        { hex = "F1E4" }, { hex = "F120" }, { hex = "F121" }, { hex = "F127" },
        { hex = "F0F2" }, { hex = "F0F3" }, { hex = "F1CD" }, { hex = "F1CE" },
        { hex = "F19B" }, { hex = "F074" }, { hex = "F08E" }, { hex = "F14C" },
        { hex = "F029" }, { hex = "F1AC" }, { hex = "F0E0" }, { hex = "F0F6" },
        { hex = "F186" }, { hex = "F185" }, { hex = "F017" }, { hex = "F03E" },
        { hex = "F030" }, { hex = "F03D" }, { hex = "F130" }, { hex = "F131" },
        { hex = "F282" }, { hex = "F291" }, { hex = "F008" }, { hex = "F04B" },
        { hex = "F048" }, { hex = "F04C" }, { hex = "F026" }, { hex = "F027" },
        { hex = "F028" }, { hex = "F013" }, { hex = "F085" }, { hex = "F0AD" },
        { hex = "F0D0" }, { hex = "F0EB" }, { hex = "F0B0" }, { hex = "F06E" },
        { hex = "F070" }, { hex = "F1E7" }, { hex = "F00A" }, { hex = "F00B" },
        { hex = "F492" }, { hex = "F1E6" }, { hex = "F060" }, { hex = "F061" },
        { hex = "F062" }, { hex = "F063" }, { hex = "F0A9" }, { hex = "F0AA" },
        { hex = "F104" }, { hex = "F105" }, { hex = "F106" }, { hex = "F107" },
        { hex = "F10B" }, { hex = "F28D" }, { hex = "F109" }, { hex = "F108" },
        { hex = "F28B" }, { hex = "F287" }, { hex = "F233" }, { hex = "F2DB" },
        { hex = "F135" }, { hex = "F07A" }, { hex = "F291" }, { hex = "F11B" },
        { hex = "F007" }, { hex = "F0C0" }, { hex = "F086" }, { hex = "F08A" },
        { hex = "F004" }, { hex = "F005" }, { hex = "F006" }, { hex = "F123" },
        { hex = "F063" }, { hex = "F0B2" }, { hex = "F2BE" }, { hex = "F095" },
        { hex = "F1C4" }, { hex = "F1C5" }, { hex = "F1C6" }, { hex = "F1C7" },
        { hex = "F1C8" }, { hex = "F1C9" }, { hex = "F1CA" }, { hex = "F1C1" },
        { hex = "F1C2" }, { hex = "E795" }, { hex = "E615" }, { hex = "E70C" },
        { hex = "E70F" }, { hex = "E708" }, { hex = "E22F" }, { hex = "E20E" },
        { hex = "E256" }, { hex = "E24B" }, { hex = "E22C" }, { hex = "E7B8" },
        { hex = "F1B2" }, { hex = "F240" }, { hex = "F1DC" }, { hex = "F073" },
        { hex = "F29C" },{ hex = "F2A9" },{ hex = "F140" },
    }

    local cols = 7
    local rows = 5
    local per_page = cols * rows
    
    local h_gap = Screen:scaleBySize(15)
    local v_gap = Screen:scaleBySize(15)
    
    local frame_w = math.floor(sw * 0.90)
    local frame_h = math.floor(sh * 0.70)
    
    local content_w = frame_w - 2 * pad - 2 * brd
    
    local title_bar_h = Screen:scaleBySize(50)
    local button_bar_h = Screen:scaleBySize(50)
    local footer_h = Screen:scaleBySize(40)
    
    local cell_w = math.floor((content_w - (cols - 1) * h_gap) / cols)
    
    local available_h = frame_h - pad - title_bar_h - button_bar_h - footer_h - pad
    local cell_h = math.max(44, math.floor((available_h - (rows - 1) * v_gap) / rows))
    
    local icon_sz = math.floor(cell_h * 0.55)
    local font_size = math.floor(icon_sz * 0.85)
    local cell_pad = math.max(4, math.floor(cell_h * 0.2))
    
    local grid_w = cols * cell_w + (cols - 1) * h_gap
    local grid_h = cell_h * rows + (rows - 1) * v_gap
    
    local frame_x = math.floor((sw - frame_w) / 2)
    local frame_y = math.max(0, math.floor((sh - frame_h) / 2))
    
    local total_pages = math.max(1, math.ceil(#icons_list / per_page))
    local cur_page = 1
    
    local page_widgets = {}
    for p = 1, total_pages do
        local page_vg = VerticalGroup:new{ align = "left" }
        local start_idx = (p - 1) * per_page + 1
        
        for row = 0, rows - 1 do
            local row_hg = HorizontalGroup:new{ align = "top" }
            for col = 0, cols - 1 do
                local idx = start_idx + row * cols + col
                if idx <= #icons_list then
                    local icon = icons_list[idx]
                    
                    local nerd_char = nerdIconChar("nerd:" .. icon.hex)
                    local display_char = nerd_char or "?"

                    local cell = FrameContainer:new{
                        width = cell_w,
                        height = cell_h,
                        bordersize = 1,
                        color = Blitbuffer.COLOR_LIGHT_GRAY,
                        background = Blitbuffer.COLOR_WHITE,
                        radius = Screen:scaleBySize(4),
                        padding = cell_pad,
                        CenterContainer:new{
                            dimen = Geom:new{ w = cell_w - cell_pad*2 - 2, h = cell_h - cell_pad*2 - 2 },
                            TextWidget:new{
                                text = display_char,
                                face = Font:getFace("symbols", font_size),
                                fgcolor = Blitbuffer.COLOR_BLACK,
                            },
                        },
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
    
    local btn_width = math.floor(content_w / 3) - 5
    local default_btn = Button:new{
        text = _("默认"),
        width = btn_width,
        show_parent = nil,
        callback = function()
            UIManager:close(dialog)
            UIManager:setDirty("all", "full")
            on_select(nil)
        end,
    }
    
    local more_btn = Button:new{
        text = _("更多 Nerd Font 图标"),
        width = btn_width,
        show_parent = nil,
        callback = function()
            UIManager:close(dialog)
            UIManager:setDirty("all", "full")
            showNerdIconInput(nil, on_select, nil)
        end,
    }
    
    local browse_btn = Button:new{
        text = _("浏览文件"),
        width = btn_width,
        show_parent = nil,
        callback = function()
            UIManager:close(dialog)
            UIManager:setDirty("all", "full")
            UIManager:show(IconBrowser:new{
                path = getIconsDir(),
                onConfirm = function(file_path)
                    on_select(file_path)
                end,
            })
        end,
    }
    
    local btn_row = HorizontalGroup:new{
        align = "center",
        default_btn,
        HorizontalSpan:new{ width = 8 },
        more_btn,
        HorizontalSpan:new{ width = 8 },
        browse_btn,
    }
    
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
                    if gx >= frame_x + pad and gx < frame_x + pad + 40
                       and gy >= frame_y + pad and gy < frame_y + pad + 40 then
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        return true
                    end
                    local btn_y = frame_y + pad + title_bar_h
                    if gy >= btn_y and gy < btn_y + button_bar_h then
                        local btn_width = math.floor(content_w / 3) - 5
                        local btn_x_start = frame_x + pad
    
                        if gx >= btn_x_start and gx < btn_x_start + btn_width then
                            UIManager:close(self)
                            UIManager:setDirty("all", "full")
                            on_select(nil)
                            return true
                        end
                        if gx >= btn_x_start + btn_width + 8 and gx < btn_x_start + (btn_width + 8) * 2 then
                            UIManager:close(self)
                            UIManager:setDirty("all", "full")
                            showNerdIconInput(nil, on_select, nil)
                            return true
                        end
                        if gx >= btn_x_start + (btn_width + 8) * 2 and gx < btn_x_start + (btn_width + 8) * 3 then
                            UIManager:close(self)
                            UIManager:setDirty("all", "full")
                            UIManager:show(IconBrowser:new{
                                path = getIconsDir(),
                                onConfirm = function(file_path)
                                    on_select(file_path)
                                end,
                            })
                            return true
                        end
                        return true
                    end
                    local bar_y = frame_y + pad + title_bar_h + button_bar_h + grid_h
                    if gy >= bar_y and gy < bar_y + footer_h then
                        local chev_w = 40
                        if gx < frame_x + pad + chev_w then
                            cur_page = math.max(1, cur_page - 1)
                            UIManager:setDirty(self, function() return "ui", self.dimen end)
                        elseif gx > frame_x + frame_w - pad - chev_w then
                            cur_page = math.min(total_pages, cur_page + 1)
                            UIManager:setDirty(self, function() return "ui", self.dimen end)
                        end
                        return true
                    end
                    local grid_start_x = frame_x + pad + (content_w - grid_w) / 2
                    local grid_y = frame_y + pad + title_bar_h + button_bar_h
                    if gx >= grid_start_x and gx < grid_start_x + grid_w
                       and gy >= grid_y and gy < grid_y + grid_h then
                        local col = math.floor((gx - grid_start_x) / (cell_w + h_gap))
                        local row = math.floor((gy - grid_y) / (cell_h + v_gap))
                        local idx = (cur_page - 1) * per_page + row * cols + col + 1
                        if idx >= 1 and idx <= #icons_list then
                            local selected_icon = "nerd:" .. icons_list[idx].hex
                            UIManager:close(self)
                            UIManager:setDirty("all", "full")
                            on_select(selected_icon)
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
                        cur_page = math.min(total_pages, cur_page + 1)
                    elseif dir == "east" then
                        cur_page = math.max(1, cur_page - 1)
                    else
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        return true
                    end
                    UIManager:setDirty(self, function() return "ui", self.dimen end)
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
        
        local title_tw = TextWidget:new{
            text = _("选择 Nerd Font 图标"),
            face = Font:getFace("smallinfofont", 18),
            bold = true,
        }
        local title_w = title_tw:getSize().w
        title_tw:paintTo(bb, content_x + (content_w - title_w) / 2, content_y + 12)
        
        local close_tw = TextWidget:new{
            text = "✕",
            face = Font:getFace("cfont", 22),
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        close_tw:paintTo(bb, content_x, content_y + 5)
        
        local btn_y = content_y + title_bar_h
        btn_row:paintTo(bb, content_x, btn_y)
        
        local grid_start_x = content_x + (content_w - grid_w) / 2
        local grid_start_y = content_y + title_bar_h + button_bar_h
        
        page_widgets[cur_page]:paintTo(bb, grid_start_x, grid_start_y)
        
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
    
    local dialog = PickerDlg:new{}
    UIManager:show(dialog, "full")
end

-- ============================================================
-- 菜单路径录制器
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
        text = _("完成录制并保存为快捷操作"),
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
                    display_label = _pick_state.nav_path[#_pick_state.nav_path] and _pick_state.nav_path[#_pick_state.nav_path].text or _("菜单动作"),
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
        text = _("取消"),
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
    _pick_state.view = view or "reader"
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
        text = _("点击任意菜单项录制为快捷操作"),
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
-- 动作执行
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
    local plugin_inst = fm and fm[plugin_key]
    
    if plugin_inst and type(plugin_inst[plugin_method]) == "function" then
        pcall(plugin_inst[plugin_method], plugin_inst)
    else
        logger.warn("[QuickActions] 插件不可用:", plugin_key)
        UIManager:show(InfoMessage:new{
            text = string.format(_("插件不可用: %s"), plugin_key),
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
    
    local recorded_view = menu_path.view or "fb"
    
    local current_view = nil
    if rui and rui.instance and not rui.instance.tearing_down then
        current_view = "reader"
    elseif fm and fm.instance then
        current_view = "fb"
    end
    
    if recorded_view ~= current_view then
        local msg = (recorded_view == "reader") 
            and _("此快捷操作只能在阅读器中执行，请先打开一本书。")
            or _("此快捷操作只能在文件浏览器中执行。")
        UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
        return
    end
    
    local target_menu = nil
    
    if recorded_view == "reader" then
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
            text = _("无法打开菜单"),
            timeout = 2,
        })
    end
end

local function getActionView(id, cfg)
    if ACTION_REGISTRY[id] then
        return "common"
    end
    
    if not cfg then return "common" end
    
    if cfg.action_type == "folder" or cfg.action_type == "collection" then
        return "fb"
    elseif cfg.action_type == "plugin" then
        return "common"
    elseif cfg.action_type == "dispatcher" and cfg.dispatcher_action then
        local ok, Dispatcher = pcall(require, "dispatcher")
        if ok and Dispatcher then
            local settingsList
            local fn_idx = 1
            while true do
                local name, val = debug.getupvalue(Dispatcher.registerAction, fn_idx)
                if not name then break end
                if name == "settingsList" then settingsList = val end
                fn_idx = fn_idx + 1
            end
            local def = settingsList and settingsList[cfg.dispatcher_action]
            if def then
                if def.filemanager then return "fb" end
                if def.reader or def.rolling or def.paging then return "reader" end
            end
        end
        return "common"
    elseif cfg.action_type == "menu" and cfg.menu_path then
        return cfg.menu_path.view or "common"
    end
    
    return "common"
end

local function getAction(id)
    local builtin_overrides = getTable("builtin_overrides")
    if builtin_overrides[id] then
        return {
            label = builtin_overrides[id].label or (ACTION_REGISTRY[id] and ACTION_REGISTRY[id].label) or id,
            icon = builtin_overrides[id].icon or (ACTION_REGISTRY[id] and ACTION_REGISTRY[id].icon),
            is_in_place = ACTION_REGISTRY[id] and ACTION_REGISTRY[id].is_in_place or false,
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
        return {
            label = cfg.label,
            icon = cfg.icon,
            is_in_place = cfg.is_in_place or false,
            view = getActionView(id, cfg),
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

registerAction("wifi", _("Wi-Fi"), "net-wifi.svg", true, "common",function(ctx)
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

registerAction("night", _("夜间模式"), "nerd:F186", true, "common",function(ctx)
    local G = rawget(_G, "G_reader_settings")
    local night_mode = G and G:isTrue("night_mode") or false
    Screen:toggleNightMode()
    UIManager:ToggleNightMode(not night_mode)
    if G then G:saveSetting("night_mode", not night_mode) end
    UIManager:setDirty("all", "full")
end)

registerAction("rotate", _("旋转"), "nerd:EB4D", true,"common", function(ctx)
    UIManager:broadcastEvent(require("ui/event"):new("SwapRotation"))
end)

registerAction("screenshot", _("截图"), "nerd:F10B", false, "common",function(ctx)
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

-- 继续阅读（智能切换）
registerAction("continue", _("继续阅读"), "nerd:F02D", false,"common", function(ctx)
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    local RH = require("readhistory")
    
    local target_file = nil
    
    if reader and reader.document then
        -- 在阅读器中：打开上一本书（排除当前）
        local current_file = reader.document.file
        target_file = RH:getPreviousFile(current_file)
    else
        -- 在文件管理器中：打开历史记录第一本
        target_file = RH and RH.hist and RH.hist[1] and RH.hist[1].file
    end
    
    if target_file then
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(target_file)
    else
        UIManager:show(InfoMessage:new{
            text = _("没有找到最近阅读的书籍"),
            timeout = 2,
        })
    end
end)

registerAction("search", _("搜索"), "nerd:F002", false,"common", function(ctx)
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

registerAction("quit", _("退出"), "nerd:F08B", false, "common",function(ctx)
    UIManager:quit()
end)

registerAction("restart", _("重启"), "nerd:F01E", false,"common", function(ctx)
    UIManager:restartKOReader()
end)

registerAction("power", _("电源"), "nerd:F011", true, "common",function(ctx)
    local buttons = {}
    if Device:canRestart() then
        buttons[#buttons + 1] = {{ text = _("重启"), callback = function()
            UIManager:restartKOReader()
        end }}
    end
    if Device:canSuspend() then
        buttons[#buttons + 1] = {{ text = _("睡眠"), callback = function()
            UIManager:suspend()
        end }}
    end
    buttons[#buttons + 1] = {{ text = _("退出"), callback = function()
        UIManager:quit()
    end }}
    UIManager:show(ButtonDialog:new{ width = math.floor(Screen:getWidth() * 0.42), buttons = buttons })
end)

-- 动作：新建快捷操作
registerAction("qa_new", _("新建快捷操作"), "nerd:F067", false, "common",function()
    showCustomQADialog(nil, function()
        -- 刷新面板
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

-- 动作：添加按钮
registerAction("qa_add_button", _("添加按钮"), "nerd:F055", false, "common",function()
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

-- 动作：封面视觉设置
registerAction("fmcoversettings", _("封面视觉设置"), "nerd:F2A9", false, "fb", function()
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    
    if reader then
        -- 在阅读器中，提示不可用
        UIManager:show(InfoMessage:new{
            text = _("此功能仅在文件管理器中可用"),
            timeout = 2,
        })
    else
        -- 在文件管理器中，广播事件
        local UIManager = require("ui/uimanager")
        local Event = require("ui/event")
        UIManager:broadcastEvent(Event:new("FMCoverSettings"))
    end
end)

-- 动作：HTTP服务器（调用 httpinspector 插件注册的动作）
registerAction("httpinspector", _("HTTP服务器"), "nerd:F0C1", true, "common",function()
    -- 获取当前UI实例
    local ui = require("apps/reader/readerui").instance
    if not ui then
        local FM = require("apps/filemanager/filemanager")
        ui = FM.instance
    end
    
    -- 调用 httpinspector 插件
    if ui and ui.httpinspector then
        if ui.httpinspector:isRunning() then
            ui.httpinspector:stop()
            UIManager:show(Notification:new{
                text = _("HTTP服务器已关闭"),
                timeout = 2,
            })
        else
            ui.httpinspector:start()
            UIManager:show(Notification:new{
                text = _("HTTP服务器已启动"),
                timeout = 2,
            })
        end
    else
        UIManager:show(InfoMessage:new{
            text = _("未找到httpinspector插件实例，请检查插件是否已安装或者修改动作注册方法以适应更新后的插件"),
            timeout = 2,
        })
    end
end)

-- 动作：FileBrowserPlus 文件服务器
registerAction("filebrowserplus", _("FilebrowserPlus"), "nerd:F029", true, "common",function()
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
            text = _("未找到filebrowserplus插件实例或方法，请检查插件是否已安装或者修改动作注册方法以适应更新后的插件"),
            timeout = 2,
        })
    end
end)

-- 动作：ZLibrary 搜索
registerAction("zlibrary_search", _("ZLibrary搜索"), "nerd:005A", false, "common",function()
    -- 获取插件实例
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
            text = _("未找到zlibrary 插件实例或方法，请检查插件是否已安装或者修改动作注册方法以适应更新后的插件"),
            timeout = 2,
        })
    end
end)

-- 动作：CloudLibrary 云端书库省心同步模式
registerAction("cloudlibrary_autosync", _("CloudLibrary：省心同步"), "nerd:F021", false,"common", function()
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
            text = _("未找到cloudLibrary 插件实例或方法，请检查插件是否已安装或者修改动作注册方法以适应更新后的插件"),
            timeout = 2,
        })
    end
end)

-- 动作：CloudLibrary 云端书库批量下载/删除云端书籍
registerAction("cloudlibrary_batch_download_books", _("CloudLibrary：批量下载/删除"), "nerd:F019", false, "common",function()
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
            text = _("未找到cloudLibrary 插件实例或方法，请检查插件是否已安装或者修改动作注册方法以适应更新后的插件"),
            timeout = 2,
        })
    end
end)

-- 动作：CloudLibrary云端书库快捷设置
registerAction("cloudlibrary_settings", _("CloudLibrary：云库设置"), "nerd:F00A", false, "common",function()
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
        -- 根据当前界面调用对应的方法
        if reader then
            plugin:onCloudLibrarySettingsReader()
        else
            plugin:onCloudLibrarySettingsFileManager()
        end
    else
        UIManager:show(InfoMessage:new{
            text = _("未找到cloudLibrary 插件实例或方法，请检查插件是否已安装或者修改动作注册方法以适应更新后的插件"),
            timeout = 2,
        })
    end
end)

-- 动作：annotationsviewer笔记（智能切换）
registerAction("annotations_viewer", _("annotationsviewer"), "nerd:F040", false, "common",function()
    local UIManager = require("ui/uimanager")
    local Event = require("ui/event")
    
    local RUI = require("apps/reader/readerui")
    local reader = RUI and RUI.instance
    
    if reader then
        -- 在阅读器中
        UIManager:broadcastEvent(Event:new("ShowCurrentBookAnnotations"))
    else
        -- 在文件管理器中
        UIManager:broadcastEvent(Event:new("ShowAllAnnotations"))
    end
end)

-- ============================================================
-- 工具函数
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

local function getPluginsList()
    local FM = require("apps/filemanager/filemanager")
    local fm = FM and FM.instance
    if not fm then return {} end
    
    local plugins = {}
    local known = {
        { key = "history", method = "onShowHist", title = _("历史") },
        { key = "collections", method = "onShowCollList", title = _("收藏列表") },
        { key = "filesearcher", method = "onShowFileSearch", title = _("文件搜索") },
        { key = "dictionary", method = "onShowDictionaryLookup", title = _("词典") },
    }
    for _, entry in ipairs(known) do
        if fm[entry.key] and type(fm[entry.key][entry.method]) == "function" then
            plugins[#plugins + 1] = {
                key = entry.key,
                method = entry.method,
                title = entry.title,
            }
        end
    end
    return plugins
end

local function getDispatcherActions()
    local ok, Dispatcher = pcall(require, "dispatcher")
    if not ok or not Dispatcher then return {} end
    pcall(Dispatcher.init, Dispatcher)
    
    local settingsList, dispatcher_menu_order
    local fn_idx = 1
    while true do
        local name, val = debug.getupvalue(Dispatcher.registerAction, fn_idx)
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
        { key = "general",     title = _("通用") },
        { key = "device",      title = _("设备") },
        { key = "screen",      title = _("屏幕和灯光") },
        { key = "filemanager", title = _("文件浏览器") },
        { key = "reader",      title = _("阅读器") },
        { key = "rolling",     title = _("流式文档 (epub, fb2, txt…)") },
        { key = "paging",      title = _("固定布局文档 (pdf, djvu, 图片…)") },
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
-- 自定义动作编辑对话框
-- ============================================================

local function deleteCustomQA(qa_id)
    -- 强制重新加载配置，确保是最新状态
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

-- 从快捷操作面板中移除按钮（不删除动作本身）
function removeFromPanel(action_id, touch_menu)
    local slots = getQASlots()
    local found = false
    local new_slots = {}
    for _, sid in ipairs(slots) do
        if sid == action_id then
            found = true
            -- 跳过，不加入新列表
        else
            new_slots[#new_slots + 1] = sid
        end
    end
    
    if not found then
        UIManager:show(Notification:new{
            text = _("快捷操作标签页中没有该按钮"),
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
    local dlg_title = qa_id and _("编辑快捷操作") or _("新建快捷操作")
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
        current_action_title = cfg.menu_path.display_label or _("菜单动作")  
    end

    local active_dialog = nil
    local choice_dialog = nil
    local coll_picker = nil
    local plugin_picker = nil
    local disp_picker = nil
    local sub_dialog = nil
    local buildSaveDialog

    local function commitQA(final_label, path, collection, icon, plugin_key, plugin_method, dispatcher_action, dispatcher_value, menu_path)
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
        
        local cfg_table = {
            label = final_label,
            icon = icon,
            is_in_place = (dispatcher_action ~= nil or plugin_key ~= nil),
        }
        
        if path and path ~= "" then
            cfg_table.action_type = "folder"
            cfg_table.action_value = path
        elseif collection and collection ~= "" then
            cfg_table.action_type = "collection"
            cfg_table.action_value = collection
        elseif plugin_key and plugin_key ~= "" then
            cfg_table.action_type = "plugin"
            cfg_table.plugin_key = plugin_key
            cfg_table.plugin_method = plugin_method
        elseif dispatcher_action and dispatcher_action ~= "" then
            cfg_table.action_type = "dispatcher"
            cfg_table.dispatcher_action = dispatcher_action
            cfg_table.dispatcher_value = dispatcher_value
        elseif menu_path and type(menu_path) == "table" then
            cfg_table.action_type = "menu"
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
                        text = string.format(_("按钮面板已满（最多 %d 个），无法自动添加。"), MAX_SLOTS),
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
        if active_dialog then
            local inputs = active_dialog:getFields()
            if inputs and inputs[1] then
                existing_label = inputs[1]
            end
            UIManager:close(active_dialog)
            active_dialog = nil
        end
        
        showNerdFontBrowser(function(new_icon)
            chosen_icon = new_icon
            buildSaveDialog(false)
        end)
    end

    local function openDispatcherPicker()
        if choice_dialog then
            UIManager:close(choice_dialog)
            choice_dialog = nil
        end
        
        local actions = getDispatcherActions()
        if #actions == 0 then
            UIManager:show(InfoMessage:new{ text = _("没有可用的系统动作"), timeout = 3 })
            cancelActionPicker()
            return
        end

        local ok, Dispatcher = pcall(require, "dispatcher")
        if not ok or not Dispatcher then
            UIManager:show(InfoMessage:new{ text = _("无法加载 Dispatcher"), timeout = 3 })
            cancelActionPicker()
            return
        end

        local settingsList
        local fn_idx = 1
        while true do
            local name, val = debug.getupvalue(Dispatcher.registerAction, fn_idx)
            if not name then break end
            if name == "settingsList" then settingsList = val end
            fn_idx = fn_idx + 1
        end

        if not settingsList then
            UIManager:show(InfoMessage:new{ text = _("无法获取系统动作列表"), timeout = 3 })
            cancelActionPicker()
            return
        end

        local sections = {
            { key = "general",     title = _("通用") },
            { key = "device",      title = _("设备") },
            { key = "screen",      title = _("屏幕和灯光") },
            { key = "filemanager", title = _("文件浏览器") },
            { key = "reader",      title = _("阅读器") },
            { key = "rolling",     title = _("流式文档 (epub, fb2, txt…)") },
            { key = "paging",      title = _("固定布局文档 (pdf, djvu, 图片…)") },
        }

        local sections_map = {}
        for _, sec in ipairs(sections) do
            sections_map[sec.key] = { title = sec.title, items = {} }
        end

        for _, action in ipairs(actions) do
            local def = settingsList[action.id]
            if def and def.category then
                local section_key = "general"
                for _, sec in ipairs(sections) do
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

        local function closeAllDialogs()
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
        end

        local section_buttons = {}
        
        for _, sec in ipairs(sections) do
            local items = sections_map[sec.key].items
            if #items > 0 then
                table.sort(items, function(a, b) return a.title:lower() < b.title:lower() end)
                
                local action_buttons = {}
                for _, item in ipairs(items) do
                    local _item = item
                    local category = item.category
                    local def = item.def
                    
                    if category == "none" or category == "arg" then
                        table.insert(action_buttons, {{
                            text = item.title,
                            callback = function()
                                closeAllDialogs()
                                current_action_type = "dispatcher"
                                current_action_val1 = _item.id
                                current_action_val2 = true
                                current_action_title = _item.title
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
                                        closeAllDialogs()
                                        current_action_type = "dispatcher"
                                        current_action_val1 = _item.id
                                        current_action_val2 = spin.value
                                        current_action_title = _item.title .. ": " .. tostring(spin.value)
                                        buildSaveDialog(true)
                                    end,
                                }
                                UIManager:show(spin)
                            end,
                        }})
                    elseif category == "string" or category == "configurable" then
                        table.insert(action_buttons, {{
                            text = item.title,
                            callback = function()
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
                                if args and #args > 0 then
                                    for i, value in ipairs(args) do
                                        local display = toggle and toggle[i] or tostring(value)
                                        table.insert(sub_items, {{
                                            text = display,
                                            callback = function()
                                                closeAllDialogs()
                                                current_action_type = "dispatcher"
                                                current_action_val1 = _item.id
                                                current_action_val2 = value
                                                current_action_title = display
                                                buildSaveDialog(true)
                                            end,
                                        }})
                                    end
                                end
                                table.insert(sub_items, {{ text = _("返回"), callback = function()
                                    openDispatcherPicker()
                                end }})
                                sub_dialog = ButtonDialog:new{
                                    title = _item.title,
                                    title_align = "center",
                                    buttons = sub_items,
                                    width = math.floor(Screen:getWidth() * 0.7),
                                }
                                UIManager:show(sub_dialog)
                            end,
                        }})
                    end
                end
                
                if #action_buttons > 0 then
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
                end
            end
        end
        
        section_buttons[#section_buttons + 1] = {{ text = _("返回"), callback = function()
            if disp_picker then UIManager:close(disp_picker); disp_picker = nil end
            buildSaveDialog(false)
        end }}

        disp_picker = ButtonDialog:new{
            title = _("系统动作"),
            title_align = "center",
            buttons = section_buttons,
            width = math.floor(Screen:getWidth() * 0.7),
        }
        UIManager:show(disp_picker)
    end

    local function openActionPicker()
        if active_dialog then
            UIManager:close(active_dialog)
            active_dialog = nil
        end
        
        choice_dialog = ButtonDialog:new{
            title = _("动作类型"),
            title_align = "center",
            buttons = {
                {{ text = _("文件夹"), callback = function()
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
                            buildSaveDialog(true)
                        end,
                        onCancel = function()
                            cancelActionPicker()
                        end,
                    }
                    UIManager:show(pc)
                end }},
                {{ text = _("集合"), enabled = #collections > 0, callback = function()
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
                            buildSaveDialog(true)
                        end }}
                    end
                    coll_buttons[#coll_buttons + 1] = {{ text = _("返回"), callback = function()
                        if coll_picker then UIManager:close(coll_picker); coll_picker = nil end
                        openActionPicker()
                    end }}
                    coll_picker = ButtonDialog:new{ title = _("选择集合"), title_align = "center", buttons = coll_buttons }
                    UIManager:show(coll_picker)
                end }},
                {{ text = _("插件"), callback = function()
                    UIManager:close(choice_dialog)
                    choice_dialog = nil
                    local FM = require("apps/filemanager/filemanager")
                    local fm = FM and FM.instance
                    if not fm then
                        UIManager:show(InfoMessage:new{ text = _("文件管理器不可用"), timeout = 3 })
                        cancelActionPicker()
                        return
                    end
                    
                    local plugins = getPluginsList()
                    if #plugins == 0 then
                        UIManager:show(InfoMessage:new{ text = _("没有可用的插件"), timeout = 3 })
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
                            buildSaveDialog(true)
                        end }}
                    end
                    plugin_buttons[#plugin_buttons + 1] = {{ text = _("返回"), callback = function()
                        if plugin_picker then UIManager:close(plugin_picker); plugin_picker = nil end
                        openActionPicker()
                    end }}
                    plugin_picker = ButtonDialog:new{ title = _("选择插件"), title_align = "center", buttons = plugin_buttons }
                    UIManager:show(plugin_picker)
                end }},
                {{ text = _("系统动作"), callback = function()
                    openDispatcherPicker()
                end }},
                {{ text = _("录制菜单动作"), callback = function()
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
                        view = "fb"
                    else
                        UIManager:show(InfoMessage:new{ text = _("请先打开菜单"), timeout = 3 })
                        cancelActionPicker()
                        return
                    end
                    
                    if not target_menu then
                        UIManager:show(InfoMessage:new{ text = _("无法打开菜单"), timeout = 3 })
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
                        buildSaveDialog(true)
                    end, function()
                        cancelActionPicker()
                    end)
                end }},
                {{ text = _("返回"), callback = function()
                    if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
                    buildSaveDialog(false)
                end }},
            }
        }
        UIManager:show(choice_dialog)
    end

    function buildSaveDialog(update_name_with_title)
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

        local action_label = _("动作") .. ": "
        if current_action_type then
            action_label = action_label .. (current_action_title or "")
        else
            action_label = action_label .. _("未设置")
        end

        local function iconButtonText()
            if not chosen_icon then return _("图标: 默认") end
            local nerd_char = nerdIconChar(chosen_icon)
            if nerd_char then
                local hex = chosen_icon:match("nerd:(.+)")
                return _("图标") .. ": " .. nerd_char .. " (" .. hex .. ")"
            end
            local fname = chosen_icon:match("([^/]+)$") or chosen_icon
            local stem = (fname:match("^(.+)%.[^%.]+$") or fname):gsub("_", " ")
            return _("图标") .. ": " .. stem
        end

        local fields = { { description = _("名称"), text = existing_label, hint = _("动作名称…") } }

        local buttons_row = {}

        table.insert(buttons_row, { text = _("取消"), callback = function()
            if active_dialog then
                UIManager:close(active_dialog)
                active_dialog = nil
            end
            if not qa_id and not current_action_type then
                if on_done then on_done() end
            end
        end } )

        if qa_id then
            table.insert(buttons_row, { text = _("移除"), callback = function()
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
            end } )

            table.insert(buttons_row, { text = _("删除"), callback = function()
                UIManager:show(ConfirmBox:new{
                    text = string.format(_("删除快捷操作 \"%s\"？"), existing_label),
                    ok_text = _("删除"),
                    cancel_text = _("取消"),
                    ok_callback = function()
                        UIManager:close(active_dialog)
                        active_dialog = nil
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
            end } )
        end

        table.insert(buttons_row, { text = _("保存"), is_enter_default = true, callback = function()
            local inputs = active_dialog:getFields()
            local final_label = inputs[1] or ""
            if final_label == "" then
                UIManager:show(InfoMessage:new{ text = _("请输入名称"), timeout = 2 })
                return
            end
            if not current_action_type then
                UIManager:show(InfoMessage:new{ text = _("请选择动作类型"), timeout = 2 })
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
            
            commitQA(final_label, path, collection, chosen_icon or default_icon, plugin_key, plugin_method, dispatcher_action, dispatcher_value, menu_path)
        end } )

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
            buttons_row,
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

    if not qa_id then
        buildSaveDialog(false)
    else
        buildSaveDialog(false)
    end
end

-- ============================================================
-- SlimSlider: 细轨滑块
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
-- 设置菜单
-- ============================================================

local _settings_dialog = nil

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

local function showEditActionDialog(action_id, on_done)
    local action = getAction(action_id)
    if not action then return end
    
    local current_label = action.label
    local current_icon = action.icon
    local active_dialog = nil
    
    local function rebuildDialog()
        if active_dialog then
            UIManager:close(active_dialog)
            active_dialog = nil
        end
        
        local function iconButtonText()
            if not current_icon then return _("图标: 默认") end
            local nerd_char = nerdIconChar(current_icon)
            if nerd_char then
                local hex = current_icon:match("nerd:(.+)")
                return _("图标") .. ": " .. nerd_char .. " (" .. hex .. ")"
            end
            local fname = current_icon:match("([^/]+)$") or current_icon
            local stem = (fname:match("^(.+)%.[^%.]+$") or fname):gsub("_", " ")
            return _("图标") .. ": " .. stem
        end
        
        local fields = {
            { description = _("名称"), text = current_label, hint = _("动作名称…") }
        }
        
        local buttons_row = {
            { text = _("取消"), callback = function()
                UIManager:close(active_dialog)
                active_dialog = nil
            end },
            { text = _("移除"), callback = function()
                if active_dialog then
                    local inputs = active_dialog:getFields()
                    if inputs and inputs[1] then
                        current_label = inputs[1]
                    end
                    UIManager:close(active_dialog)
                    active_dialog = nil
                end
                removeFromPanel(action_id, touch_menu)
                if on_done then on_done() end
            end },
            { text = _("保存"), is_enter_default = true, callback = function()
                if not active_dialog then return end
                local inputs = active_dialog:getFields()
                local new_label = inputs[1] or ""
                if new_label == "" then
                    UIManager:show(InfoMessage:new{ text = _("请输入名称"), timeout = 2 })
                    return
                end
                UIManager:close(active_dialog)
                active_dialog = nil
                local builtin_overrides = getTable("builtin_overrides")
                builtin_overrides[action_id] = {
                    label = new_label,
                    icon = current_icon,
                }
                setTable("builtin_overrides", builtin_overrides)
                if on_done then on_done() end
            end },
        }
        
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
                showNerdFontBrowser(function(new_icon)
                    current_icon = new_icon
                    rebuildDialog()
                end)
            end } },
            buttons_row,
        }
        
        active_dialog = MultiInputDialog:new{
            title = _("编辑快捷操作"),
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
    
    for i = 1, #ACTION_ORDER do
        local id = ACTION_ORDER[i]
        local label = getLabelForAction(id)
        local circle_char = nerdIconChar("nerd:E22F") or "○"
        items[#items + 1] = {
            id = id,
            text = circle_char .. " " .. label,
            is_builtin = true,
            on_edit = function()
                showEditActionDialog(id, function() 
                    refreshQuickPanel(touch_menu)
                end)
            end,
            on_delete = nil,
        }
    end
    
    local custom_list = getSetting("custom_list")
    if type(custom_list) ~= "table" then custom_list = {} end
    for i = 1, #custom_list do
        local id = custom_list[i]
        local cfg = getTable("custom")[id]
        if cfg then
            local symbol = ""
            if cfg.action_type == "dispatcher" then
                symbol = "⊕ "
            elseif cfg.action_type == "plugin" then
                symbol = "⬡ "
            elseif cfg.action_type == "collection" then
                symbol = "⊞ "
            elseif cfg.action_type == "menu" then
                symbol = "⊚ "
            elseif cfg.action_type == "folder" then
                symbol = "◇ "
            end
            
            items[#items + 1] = {
                id = id,
                text = symbol .. cfg.label,
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

-- 直接显示添加按钮的选择列表
function showAddButtonMenu(touch_menu)
    local current_dialog = nil
    local slots = getQASlots()
    local available = {}
    
    for i = 1, #ACTION_ORDER do
        local id = ACTION_ORDER[i]
        available[#available + 1] = { id = id, label = getLabelForAction(id) }
    end
    local custom_list = getSetting("custom_list")
    if type(custom_list) == "table" then
        for i = 1, #custom_list do
            local id = custom_list[i]
            available[#available + 1] = { id = id, label = getLabelForAction(id) }
        end
    end
    table.sort(available, function(a, b)
    -- 获取符号优先级
    local function getSymbolPriority(id)
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
        -- builtin_id 放最后
        for _, builtin_id in ipairs(ACTION_ORDER) do
            if builtin_id == id then
                return 7
            end
        end
        return 8
    end
    
    local a_prio = getSymbolPriority(a.id)
    local b_prio = getSymbolPriority(b.id)
    
    if a_prio ~= b_prio then
        return a_prio < b_prio
    end
    return a.label:lower() < b.label:lower()
end)
    
    local buttons = {}
    
    -- 前光滑块选项
    local show_fl = showFrontlight()
    table.insert(buttons, {
        {
            text = (show_fl and "✓ " or "  ") .. _("前光滑块"),
            callback = function()
                setBool("qa_frontlight", not showFrontlight())
                if touch_menu then touch_menu:updateItems() end
                UIManager:close(current_dialog)
                showAddButtonMenu(touch_menu)
            end,
        }
    })
    
    if Device:hasNaturalLight() then
        local show_wl = showWarmth()
        table.insert(buttons, {
            {
                text = (show_wl and "✓ " or "  ") .. _("色温滑块"),
                callback = function()
                    setBool("qa_warmth", not showWarmth())
                    if touch_menu then touch_menu:updateItems() end
                    UIManager:close(current_dialog)
                    showAddButtonMenu(touch_menu)
                end,
            }
        })
    end
    
    local show_slider_val = showSliderValue()
    table.insert(buttons, {
        {
            text = (show_slider_val and "✓ " or "  ") .. _("显示滑块数值"),
            callback = function()
                setBool("qa_slider_show_value", not showSliderValue())
                if touch_menu then touch_menu:updateItems() end
                UIManager:close(current_dialog)
                showAddButtonMenu(touch_menu)
            end,
        }
    })
    
    table.insert(buttons, {})  -- 分隔线
    
    for i = 1, #available do
        local action = available[i]
        local symbol = ""
        local is_builtin = false
        for _, builtin_id in ipairs(ACTION_ORDER) do
            if builtin_id == action.id then
                is_builtin = true
                break
            end
        end
        
            if is_builtin then
                local circle_char = nerdIconChar("nerd:E22F") or "○"
                symbol = circle_char .. " "
            else
            local cfg = getTable("custom")[action.id]
            if cfg then
                if cfg.action_type == "dispatcher" then
                    symbol = "⊕ "
                elseif cfg.action_type == "plugin" then
                    symbol = "⬡ "
                elseif cfg.action_type == "collection" then
                    symbol = "⊞ "
                elseif cfg.action_type == "menu" then
                    symbol = "⊚ "
                elseif cfg.action_type == "folder" then
                    symbol = "◇ "
                else
                    symbol = "● "
                end
            else
                symbol = "● "
            end
        end
        
        -- 检查是否已添加，勾选标记统一放在最前面
        local is_checked = false
        for j = 1, #slots do
            if slots[j] == action.id then
                is_checked = true
                break
            end
        end
        
        local check_mark = is_checked and "✓ " or "  "
        local display_text = check_mark .. symbol .. action.label
        
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
                                text = string.format(_("最多 %d 个按钮"), MAX_SLOTS),
                                timeout = 2,
                            })
                            return
                        end
                        current_slots[#current_slots + 1] = action.id
                        saveQASlots(current_slots)
                    end
                    if touch_menu then touch_menu:updateItems() end
                    UIManager:close(current_dialog)
                    showAddButtonMenu(touch_menu)
                end,
            }
        })
    end
    
    table.insert(buttons, {})
    table.insert(buttons, {
        { text = _("关闭"), callback = function()
            UIManager:close(current_dialog)
        end }
    })
    
    local dialog = ButtonDialog:new{
        title = _("添加按钮"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    current_dialog = dialog
    UIManager:show(dialog)
end

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

    local function getAvailableActions()
        local available = {}
        for i = 1, #ACTION_ORDER do
            local id = ACTION_ORDER[i]
            available[#available + 1] = { id = id, label = getLabelForAction(id) }
        end
        local custom_list = getSetting("custom_list")
        if type(custom_list) == "table" then
            for i = 1, #custom_list do
                local id = custom_list[i]
                available[#available + 1] = { id = id, label = getLabelForAction(id) }
            end
        end
        table.sort(available, function(a, b) return a.label:lower() < b.label:lower() end)
        return available
    end

    local function getCustomActionSubMenu()
        local items = getCustomItems(touch_menu)
        local sub_items = {}
        
        local auto_add_key = "qa_auto_add_to_panel"
        table.insert(sub_items, {
            text = function()
                local is_checked = getBool(auto_add_key)
                return (is_checked and "✓ " or "  ") .. _("保存时自动添加到按钮")
            end,
            callback = function()
                local current = getBool(auto_add_key)
                setBool(auto_add_key, not current)
            end,
            separator = true,
        })

        table.insert(sub_items, {
            text = "+ " .. _("新建"),
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
                text = _("内置动作"),
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
            { text = _("圆形"), radio = true, checked_func = function() return getShape() == "round" end, callback = function() setString("qa_shape", "round") end },
            { text = _("圆角方形"), radio = true, checked_func = function() return getShape() == "square_round" end, callback = function() setString("qa_shape", "square_round") end },
            { text = _("无边框"), radio = true, checked_func = function() return getShape() == "bare" end, callback = function() setString("qa_shape", "bare") end },
        }
    end

    local function getBgSubMenu()
        return {
            { text = _("透明"), radio = true, checked_func = function() return getBg() == "transparent" end, callback = function() setString("qa_bg", "transparent") end },
            { text = _("实色"), radio = true, checked_func = function() return getBg() == "solid" end, callback = function() setString("qa_bg", "solid") end },
            { text = _("浅灰"), radio = true, checked_func = function() return getBg() == "flat" end, callback = function() setString("qa_bg", "flat") end },
        }
    end

    local root_menu_items = {
        {
            text = function() return (isQAEnabled() and "✓ " or "  ") .. _("启用快捷操作标签页") end,
            callback = function()
                local new_val = not isQAEnabled()
                setBool("qa_enabled", new_val)
                UIManager:show(ConfirmBox:new{
                    text = _("重启后生效。\n\n立即重启 KOReader？"),
                    ok_text = _("重启"),
                    cancel_text = _("稍后"),
                    ok_callback = function()
                        UIManager:restartKOReader()
                    end,
                })
            end,
        },
        {
            text = function()
                local current = getString("qa_tab_icon")
                return _("快捷操作标签页图标") .. ": " .. current
            end,
            close_on_click = true,
            callback = function()
                closeSettingsDialog()
                UIManager:show(IconBrowser:new{
                    path = getIconsDir(),
                    onConfirm = function(file_path)
                        if file_path then
                            local filename_with_ext = file_path:match("([^/]+)$")
                            local filename = filename_with_ext:gsub("%.[^%.]+$", "")
                            setString("qa_tab_icon", filename)
                            UIManager:show(ConfirmBox:new{
                                text = _("重启 KOReader 后生效。立即重启？"),
                                ok_text = _("重启"),
                                cancel_text = _("稍后"),
                                ok_callback = function()
                                    UIManager:restartKOReader()
                                end,
                            })
                        end
                    end,
                })
            end,
        },
        {
            text = function()
                local enabled = getBool("qa_context_filter")
                return (enabled and "✓ " or "  ") .. _("过滤快捷操作标签页按钮")
            end,
            callback = function()
                local current = getBool("qa_context_filter")
                setBool("qa_context_filter", not current)
                refreshQuickPanel(touch_menu)
            end,
        },
        {
            text = _("快捷操作"),
            sub_item_table = getCustomActionSubMenu,
        },
        {
            text = _("排列按钮").. " ▸",
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
                    title = _("排列按钮"),
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
            text = _("添加按钮") .. " ▸",
            close_on_click = true,
            callback = function()
                closeSettingsDialog()
                showAddButtonMenu(touch_menu)
            end,
        },
        {
            text = _("按钮形状"),
            sub_item_table = getShapeSubMenu,
        },
        {
            text = _("按钮背景"),
            enabled = getShape() ~= "bare",
            sub_item_table = getBgSubMenu,
        },
        {
            text = function() return (showLabels() and "✓ " or "  ") .. _("显示标签") end,
            callback = function() setBool("qa_labels", not showLabels()) end,
        },
        {
            text = function() return _("按钮大小") .. ": " .. getButtonSizePct() .. "%" end,
            close_on_click = true,
            callback = function()
                closeSettingsDialog()
                local spin = SpinWidget:new{
                    title_text = _("按钮大小"),
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
            text = function() return _("标签大小") .. ": " .. getLabelScalePct() .. "%" end,
            close_on_click = true,
            callback = function()
                closeSettingsDialog()
                local spin = SpinWidget:new{
                    title_text = _("标签大小"),
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
        {
            text = function() return (buttonHoldEdit() and "✓ " or "  ") .. _("长按按钮打开编辑框") end,
            callback = function() 
                setBool("qa_button_hold_edit", not buttonHoldEdit())
                refreshQuickPanel(touch_menu)
            end,
        },
        {
            text = function() return (settingsOnHold() and "✓ " or "  ") .. _("长按标签页面板打开设置") end,
            callback = function() setBool("qa_settings_on_hold", not settingsOnHold()) end,
        },
{
    text = _("保存当前设置为默认"),
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
        }
        setSetting("default_config", default_config)
        UIManager:show(Notification:new{
            text = _("当前配置已保存为默认"),
            timeout = 2,
        })
    end,
},
        {
            text = _("应用默认配置"),
            close_on_click = true,
            callback = function()
                local default_config = getSetting("default_config")
                if not default_config or type(default_config) ~= "table" then
                    UIManager:show(Notification:new{
                        text = _("没有保存的默认配置，请先保存"),
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
        
                refreshQuickPanel(touch_menu)
                UIManager:show(Notification:new{
                    text = _("已应用默认配置"),
                    timeout = 2,
                })
            end,
        },
        {
            text = _("重置所有设置"),
            close_on_click = true,
            callback = function()
                closeSettingsDialog()
                local confirm = ConfirmBox:new{
                    text = _("重置所有设置到初始默认值？\n这将清除所有自定义动作及您自己保存的默认配置。"),
                    ok_text = _("重置"),
                    cancel_text = _("取消"),
                    ok_callback = function()
                        resetAllSettings(touch_menu)
                        UIManager:show(Notification:new{
                            text = _("设置已重置"),
                            timeout = 2,
                        })
                    end,
                }
                UIManager:show(confirm)
            end,
        },
    }

    local function showMenu(items, title, parent_stack)
        local buttons = {}
        
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
                            closeSettingsDialog()
                            local new_stack = {}
                            for _, v in ipairs(parent_stack or {}) do
                                table.insert(new_stack, v)
                            end
                            table.insert(new_stack, { items = items, title = title })
                            showMenu(sub_table, display_text, new_stack)
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
                
                table.insert(buttons, {
                    {
                        text = prefix .. display_text,
                        enabled = (item.enabled == nil) or (type(item.enabled) == "function" and item.enabled()) or item.enabled,
                        callback = function()
                            if item.callback then
                                item.callback()
                            end
                            if item.close_on_click then
                                closeSettingsDialog()
                            else
                                closeSettingsDialog()
                                refreshQuickPanel(touch_menu)
                                showMenu(items, title, parent_stack)
                            end
                        end
                    }
                })
            end
        end
        
        if parent_stack and #parent_stack > 0 then
            table.insert(buttons, {})
            table.insert(buttons, {
                {
                    text = "◂ " .. _("返回"),
                    callback = function()
                        local parent = parent_stack[#parent_stack]
                        closeSettingsDialog()
                        showMenu(parent.items, parent.title, parent.parent_stack)
                    end
                }
            })
            
            if #parent_stack > 1 then
                table.insert(buttons, {
                    {
                        text = "◂◂ " .. _("返回根菜单"),
                        callback = function()
                            closeSettingsDialog()
                            showMenu(root_menu_items, _("快捷操作设置"), nil)
                        end
                    }
                })
            end
        end
        
        local dialog = ButtonDialog:new{
            title = title or _("快捷操作设置"),
            title_align = "center",
            buttons = buttons,
            width = math.floor(Screen:getWidth() * 0.7),
            max_height = math.floor(Screen:getHeight() * 0.7),
        }
        _settings_dialog = dialog
        UIManager:show(dialog)
    end

    showMenu(root_menu_items, _("快捷操作设置"), nil)
end

-- ============================================================
-- 面板构建器
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
        
        -- 点击反馈函数
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
                        -- 点击反馈
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
                        for _, builtin_id in ipairs(ACTION_ORDER) do
                            if builtin_id == action_id then
                                is_builtin = true
                                break
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
    local current_view = "common"

    if context_filter_enabled then
        local RUI = require("apps/reader/readerui")
        local in_reader = RUI and RUI.instance and not RUI.instance.tearing_down
        current_view = in_reader and "reader" or "fb"
    end

    local visible_slots = {}
    for _, id in ipairs(slots) do
        local action = getAction(id)
        if action then
            if context_filter_enabled then
                local action_view = action.view or "common"
                if action_view == "common" or action_view == current_view then
                    visible_slots[#visible_slots + 1] = id
                end
            else
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
            text = _("没有配置动作"),
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
                text = _("前光") .. ": " .. tostring(fl.cur),
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
                fl_label:setText(_("前光") .. ": " .. tostring(fl.cur))
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
                text = _("色温") .. ": " .. tostring(nl.cur),
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
                nl_label:setText(_("色温") .. ": " .. tostring(nl.cur))
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
            text = _("最大"), width = max_btn_w, show_parent = touch_menu.show_parent,
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
-- TouchMenu 补丁
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
-- 优先显示快捷操作面板
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
-- 注入标签页到菜单
-- ============================================================

local QS_PANEL_TAB = {
    icon = getString("qa_tab_icon") ,
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
                if v == "quickactions_settings" then already = true; break end
            end
            if not already then
                table.insert(FileManagerMenuOrder.tools, 1, "----------------------------")
                table.insert(FileManagerMenuOrder.tools, 2, "quickactions_settings")
            end
        end
        if not m_self.menu_items then
            m_self.menu_items = {}
        end
        m_self.menu_items.quickactions_settings = {
            text = _("快捷操作设置"),
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
                if v == "quickactions_settings" then already = true; break end
            end
            if not already then
                table.insert(ReaderMenuOrder.tools, "quickactions_settings")
            end
        end
        if not m_self.menu_items then
            m_self.menu_items = {}
        end
        m_self.menu_items.quickactions_settings = {
            text = _("快捷操作设置"),
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
-- 手势注册
-- ============================================================

local function registerGestures()
    Dispatcher:registerAction("quick_actions_panel", {
        category = "none",
        event = "QuickActionsPanel",
        title = _("快捷操作面板"),
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
        ReaderUI._qs_gesture_added = true
    end
end

-- ============================================================
-- 安装
-- ============================================================

local function install()
    logger.info("[QuickActions] 安装中...")

    patchFileManagerMenuClose()
    patchReaderMenuClose()
    patchFileManagerMenu()
    patchReaderMenu()
    registerGestures()

    logger.info("[QuickActions] 安装完成，配置路径:", CONFIG_PATH)
end

install()

logger.info("[QuickActions] 加载完成")