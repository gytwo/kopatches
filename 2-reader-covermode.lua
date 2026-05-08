--[[
Patch: Cover Mode - 为标注（高亮、下划线、删除线、反色）添加遮盖模式以供复习
作者：gytwo
版本号：V2
更新内容：
（1）修复在PDF中切换遮盖无反应（匹配不到index）的问题
（2）修复切换书籍时菜单丢失的问题（取消只注册一次的限制）
（3）修复PDF连续视图模式下部分标注无法遮盖的问题（通过 getScrollPagePosition 获取正确页码）
提示：PDF分页视图模式下由于PDF物理页码与实际屏幕页码不一致，会存在双击跳转回物理页码第一部分所在屏幕页码的问题，推荐使用PDF连续视图模式。
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

-- 获取 rect 所属的实际页码（连续模式专用）
local function getPageFromScreenRect(self, rect)
    -- 分页模式：直接用 self.state.page
    if not self.page_states then
        return self.state and self.state.page or 1
    end
    
    -- 连续模式：通过 Y 坐标查找所属页面
    local y = rect.y
    local y_offset = 0
    local gap = (self.page_gap and self.page_gap.height) or 0
    
    for _, state in ipairs(self.page_states) do
        if y >= y_offset and y < y_offset + state.visible_area.h then
            return state.page
        end
        y_offset = y_offset + state.visible_area.h + gap
    end
    
    -- 没找到，返回第一页
    return self.page_states[1] and self.page_states[1].page or 1
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

-- 绘制函数是否已安装的标志
local drawer_patched = false

local function patchCoverMode()
    
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local ReaderView = require("apps/reader/modules/readerview")
    local ReaderUI = require("apps/reader/readerui")
    
    if not ReaderView then
        return
    end
    
    -- ============================================================
    -- 1. 修改绘制函数 - 支持多种样式 + PDF 兼容（只执行一次）
    -- ============================================================
    if not drawer_patched then
        local original_draw = ReaderView.drawHighlightRect
        
        function ReaderView.drawHighlightRect(self, bb, _x, _y, rect, drawer, color, draw_note_mark)
            if shouldCoverDrawer(drawer) then
                local index = nil
                -- 方法1：直接对象引用匹配（EPUB 有效）
                if self.highlight.visible_boxes then
                    for _, box in ipairs(self.highlight.visible_boxes) do
                        if box.rect == rect then
                            index = box.index
                            break
                        end
                    end
                end
                
                -- 方法2：坐标转换匹配（PDF 需要，因为 visible_boxes 存的是页面坐标）
                if index == nil and self.highlight.visible_boxes then
                    -- 获取 rect 所属的实际页码（修复连续模式问题）
                    local current_page = getPageFromScreenRect(self, rect)
                    for _, box in ipairs(self.highlight.visible_boxes) do
                        local screen_rect = self:pageToScreenTransform(current_page, box.rect)
                        if screen_rect and math.abs(screen_rect.x - rect.x) < 2 and math.abs(screen_rect.y - rect.y) < 2 then
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
        
        drawer_patched = true
    end
    
    -- ============================================================
    -- 2. 注册双击手势（每次打开都确保已注册）
    -- ============================================================
    local original_reader_ready = ReaderHighlight.onReaderReady
    local doubletap_registered = false
    
    function ReaderHighlight:onReaderReady()
        if original_reader_ready then
            original_reader_ready(self)
        end

        if not doubletap_registered then
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
            doubletap_registered = true
        end
    end
    
    function ReaderHighlight:onDoubleTap(ges)
        if not isEnabled() or not isDoubleTapMode() then
            return false
        end
 
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
    -- 8. 主菜单（中文）- 每次打开书本都尝试添加
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
                        local Notification = require("ui/widget/notification")
                        if new_value then
                            Notification:notify(_("遮盖模式已启用"))
                        else
                            Notification:notify(_("遮盖模式已禁用"))
                        end
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
                    text = _("单个遮盖-切换模式"),
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
    
    -- 每次打开书都尝试添加菜单
    UIManager:scheduleIn(1, tryAddMenu)
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverMode)

patchCoverMode()
