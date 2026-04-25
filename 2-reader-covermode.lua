--[[
Patch: Cover Mode - 支持双击/单击切换模式 + 样式选择
]]

local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local userpatch = require("userpatch")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local logger = require("logger")
local _ = require("gettext")

-- 辅助函数：判断点是否在矩形内
local function inside_box(pos, box)
    if pos then
        local x, y = pos.x, pos.y
        if box.x <= x and box.y <= y
            and box.x + box.w >= x
            and box.y + box.h >= y then
            return true
        end
    end
    return false
end

-- 强制重绘函数
local function forceRedraw(ui)
    if not ui or not ui.view then
        return
    end
    if ui.view.recalculate then
        ui.view:recalculate()
    end
    ui:handleEvent(Event:new("RedrawCurrentView"))
    UIManager:setDirty(nil, "full")
end

-- 总开关
local function isEnabled()
    return G_reader_settings:readSetting("cover_mode_enabled", true)
end

-- 实时获取当前模式
local function isDoubleTapMode()
    return G_reader_settings:readSetting("cover_mode_double_tap", true)
end

-- 获取需要遮盖的样式列表
local function getCoveredDrawers()
    local covered_drawers = G_reader_settings:readSetting("cover_mode_drawers", {lighten = true})
    return covered_drawers
end

-- 检查某个样式是否需要遮盖
local function shouldCoverDrawer(drawer)
    if not isEnabled() then
        return false
    end
    local covered = getCoveredDrawers()
    return covered[drawer] == true
end

local function toggleHighlight(highlight, index)
    if not isEnabled() then
        return
    end
    highlight._temp_covered = highlight._temp_covered or {}
    local is_covered = highlight._temp_covered[index] == true
    highlight._temp_covered[index] = not is_covered
    
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI and ReaderUI.instance then
        forceRedraw(ReaderUI.instance)
    else
        UIManager:setDirty(nil, "full")
    end
end

local function patchCoverMode()
    logger.info("[CoverMode] 安装补丁...")
    
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local ReaderView = require("apps/reader/modules/readerview")
    local ReaderUI = require("apps/reader/readerui")
    
    if not ReaderView or ReaderView._cover_patched then
        return
    end
    
    -- ============================================================
    -- 1. 修改绘制函数 - 支持多种样式
    -- ============================================================
    local original_draw = ReaderView.drawHighlightRect
    
    function ReaderView.drawHighlightRect(self, bb, _x, _y, rect, drawer, color, draw_note_mark)
        if shouldCoverDrawer(drawer) then
            local index = nil
            if self.highlight.visible_boxes then
                for _, box in ipairs(self.highlight.visible_boxes) do
                    if box.rect == rect then
                        index = box.index
                        break
                    end
                end
            end
            
            local is_covered = false
            if index and self.ui and self.ui.highlight and self.ui.highlight._temp_covered then
                is_covered = self.ui.highlight._temp_covered[index] == true
            end
            
            local x, y, w, h = rect.x, rect.y, rect.w, rect.h
            
            if is_covered then
                if color then
                    local c = Blitbuffer.ColorRGB32(color.r, color.g, color.b, 0xFF)
                    bb:blendRectRGB32(x, y, w, h, c)
                else
                    local yellow = Blitbuffer.colorFromName("yellow")
                    if yellow then
                        local c = Blitbuffer.ColorRGB32(yellow.r, yellow.g, yellow.b, 0xFF)
                        bb:blendRectRGB32(x, y, w, h, c)
                    else
                        bb:darkenRect(x, y, w, h, 1)
                    end
                end
                return
            end
        end
        
        if original_draw then
            original_draw(self, bb, _x, _y, rect, drawer, color, draw_note_mark)
        end
    end
    
    -- ============================================================
    -- 2. 注册双击手势
    -- ============================================================
    local original_reader_ready = ReaderHighlight.onReaderReady
    
    function ReaderHighlight:onReaderReady()
        if original_reader_ready then
            original_reader_ready(self)
        end
        
        self.ui:registerTouchZones({
            {
                id = "readerhighlight_double_tap",
                ges = "double_tap",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0,
                    ratio_w = 1, ratio_h = 1,
                },
                handler = function(ges)
                    if not isEnabled() or not isDoubleTapMode() then
                        return false
                    end
                    return self:onDoubleTap(ges)
                end,
                overrides = {
                    "readerhighlight_tap",
                    "readerhighlight_hold",
                },
            },
        })
        logger.info("[CoverMode] 双击手势已注册")
    end
    
    function ReaderHighlight:onDoubleTap(ges)
        if not isEnabled() or not isDoubleTapMode() then
            return false
        end
        
        logger.info("[CoverMode] 双击触发")
        
        local pos = self.view:screenToPageTransform(ges.pos)
        if not pos then
            return false
        end
        
        local tapped_index = nil
        if self.view.highlight.visible_boxes then
            for _, box in ipairs(self.view.highlight.visible_boxes) do
                if inside_box(pos, box.rect) then
                    tapped_index = box.index
                    break
                end
            end
        end
        
        if tapped_index then
            logger.info("[CoverMode] 双击高亮切换, idx=", tapped_index)
            toggleHighlight(self, tapped_index)
            return true
        end
        
        return false
    end
    
    -- ============================================================
    -- 3. Hook onTap
    -- ============================================================
    local original_onTap = ReaderHighlight.onTap
    
    function ReaderHighlight:onTap(_, ges)
        if not isEnabled() or isDoubleTapMode() then
            return original_onTap(self, _, ges)
        end
        
        local pos = self.view:screenToPageTransform(ges.pos)
        
        local tapped_index = nil
        if self.view.highlight.visible_boxes then
            for _, box in ipairs(self.view.highlight.visible_boxes) do
                if inside_box(pos, box.rect) then
                    tapped_index = box.index
                    break
                end
            end
        end
        
        if tapped_index then
            logger.info("[CoverMode] 单击高亮切换, idx=", tapped_index)
            toggleHighlight(self, tapped_index)
        end
        
        return original_onTap(self, _, ges)
    end
    
    -- ============================================================
    -- 4. 批量操作函数
    -- ============================================================
    local function coverAllHighlights(highlight)
        if not isEnabled() then
            return
        end
        highlight._temp_covered = highlight._temp_covered or {}
        local annotations = highlight.ui.annotation.annotations
        for idx, item in ipairs(annotations) do
            if item.drawer then
                highlight._temp_covered[idx] = true
            end
        end
    end
    
    local function uncoverAllHighlights(highlight)
        if not isEnabled() then
            return
        end
        highlight._temp_covered = highlight._temp_covered or {}
        local annotations = highlight.ui.annotation.annotations
        for idx, item in ipairs(annotations) do
            if item.drawer then
                highlight._temp_covered[idx] = false
            end
        end
    end
    
    -- ============================================================
    -- 5. 手势处理函数
    -- ============================================================
    function ReaderUI:onToggleCoverMode()
        if not isEnabled() then
            return
        end
        local highlight = self.highlight
        if not highlight then
            return
        end
        
        local has_covered = false
        local annotations = highlight.ui.annotation.annotations
        for idx, item in ipairs(annotations) do
            if item.drawer then
                local is_cov = highlight._temp_covered and highlight._temp_covered[idx]
                if is_cov then
                    has_covered = true
                    break
                end
            end
        end
        
        if has_covered then
            uncoverAllHighlights(highlight)
        else
            coverAllHighlights(highlight)
        end
        
        forceRedraw(self)
    end
    
    -- ============================================================
    -- 6. 注册 Dispatcher 手势动作
    -- ============================================================
    Dispatcher:registerAction("toggle_cover_mode_action", {
        category = "none",
        event = "ToggleCoverMode",
        title = _("Cover all / Uncover all"),
        reader = true,
        ui = true,
    })
    
    -- ============================================================
    -- 7. 样式选项（中文）
    -- ============================================================
    local drawer_names = {
        lighten = _("文本高亮"),
        underscore = _("下划线"),
        strikeout = _("删除线"),
        invert = _("反色"),
    }
    
    local function buildDrawerSettingsMenu()
        local items = {}
        local covered = getCoveredDrawers()
        local enabled = isEnabled()
        
        for drawer, name in pairs(drawer_names) do
            table.insert(items, {
                text = name,
                enabled_func = function() return enabled end,
                checked_func = function()
                    return covered[drawer] == true
                end,
                callback = function(touchmenu_instance)
                    local new_value = not covered[drawer]
                    covered[drawer] = new_value
                    G_reader_settings:saveSetting("cover_mode_drawers", covered)
                    local ReaderUI = require("apps/reader/readerui")
                    if ReaderUI and ReaderUI.instance then
                        forceRedraw(ReaderUI.instance)
                    end
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            })
        end
        
        return items
    end
    
    -- ============================================================
    -- 8. 主菜单（中文）
    -- ============================================================
    local function addToMainMenu(menu_items)
        if menu_items.cover_mode then
            return
        end
        
        menu_items.cover_mode = {
            text = _("遮盖模式"),
            sorting_hint = "typeset",
            sub_item_table = {
                {
                    text = _("启用遮盖"),
                    checked_func = function()
                        return isEnabled()
                    end,
                    callback = function(touchmenu_instance)
                        local new_value = not isEnabled()
                        G_reader_settings:saveSetting("cover_mode_enabled", new_value)
                        logger.info("[CoverMode] 启用遮盖:", new_value)
                        local Notification = require("ui/widget/notification")
                        if new_value then
                            Notification:notify(_("遮盖模式已启用"))
                        else
                            Notification:notify(_("遮盖模式已禁用"))
                        end
                        -- 刷新整个界面
                        local ReaderUI = require("apps/reader/readerui")
                        if ReaderUI and ReaderUI.instance then
                            forceRedraw(ReaderUI.instance)
                        end
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
                        end
                    end,
                },
                {
                    text = _("全部遮盖"),
                    enabled_func = function()
                        return isEnabled()
                    end,
                    checked_func = function()
                        local ReaderUI = require("apps/reader/readerui")
                        if not ReaderUI or not ReaderUI.instance then
                            return false
                        end
                        local highlight = ReaderUI.instance.highlight
                        if not highlight or not highlight._temp_covered then
                            return false
                        end
                        local annotations = highlight.ui.annotation.annotations
                        for idx, item in ipairs(annotations) do
                            if item.drawer and highlight._temp_covered[idx] then
                                return true
                            end
                        end
                        return false
                    end,
                    callback = function(touchmenu_instance)
                        local ReaderUI = require("apps/reader/readerui")
                        if not ReaderUI or not ReaderUI.instance then
                            return
                        end
                        local highlight = ReaderUI.instance.highlight
                        if not highlight then
                            return
                        end
                        local has_covered = false
                        local annotations = highlight.ui.annotation.annotations
                        for idx, item in ipairs(annotations) do
                            if item.drawer and highlight._temp_covered and highlight._temp_covered[idx] then
                                has_covered = true
                                break
                            end
                        end
                        if has_covered then
                            uncoverAllHighlights(highlight)
                        else
                            coverAllHighlights(highlight)
                        end
                        forceRedraw(ReaderUI.instance)
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
                        end
                    end,
                },
                {
                    text = _("切换模式"),
                    enabled_func = function()
                        return isEnabled()
                    end,
                    sub_item_table = {
                        {
                            text = _("双击切换（请确保已在[设置]-[手势]中取消禁用双击）"),
                            checked_func = function()
                                return isDoubleTapMode() == true
                            end,
                            callback = function(touchmenu_instance)
                                if not isDoubleTapMode() then
                                    G_reader_settings:saveSetting("cover_mode_double_tap", true)
                                    local Notification = require("ui/widget/notification")
                                    Notification:notify(_("遮盖模式：双击切换"))
                                    if touchmenu_instance then
                                        touchmenu_instance:updateItems()
                                    end
                                end
                            end,
                        },
                        {
                            text = _("单击切换"),
                            checked_func = function()
                                return isDoubleTapMode() == false
                            end,
                            callback = function(touchmenu_instance)
                                if isDoubleTapMode() then
                                    G_reader_settings:saveSetting("cover_mode_double_tap", false)
                                    local Notification = require("ui/widget/notification")
                                    Notification:notify(_("遮盖模式：单击切换"))
                                    if touchmenu_instance then
                                        touchmenu_instance:updateItems()
                                    end
                                end
                            end,
                        },
                    },
                },
                {
                    text = _("可遮盖样式"),
                    enabled_func = function()
                        return isEnabled()
                    end,
                    sub_item_table = buildDrawerSettingsMenu(),
                },
            },
        }
    end
    
    local function tryAddMenu()
        local ReaderUI = require("apps/reader/readerui")
        if not ReaderUI or not ReaderUI.instance or not ReaderUI.instance.menu then
            UIManager:scheduleIn(0.5, tryAddMenu)
            return
        end
        local ui = ReaderUI.instance
        if not ui.menu.menu_items then
            UIManager:scheduleIn(0.5, tryAddMenu)
            return
        end
        addToMainMenu(ui.menu.menu_items)
        if ui.menu.touchmenu_instance then
            ui.menu:updateItems()
        end
    end
    
    ReaderView._cover_patched = true
    logger.info("[CoverMode] 安装完成")
    
    UIManager:scheduleIn(1, tryAddMenu)
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverMode)

patchCoverMode()