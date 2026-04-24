--[[
Patch: Cover Mode - 点击高亮自动切换遮盖 + 手势批量操作
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

local function patchCoverMode()
    logger.info("[CoverMode] 安装补丁...")
    
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local ReaderView = require("apps/reader/modules/readerview")
    local ReaderUI = require("apps/reader/readerui")
    
    if not ReaderView or ReaderView._cover_patched then
        return
    end
    
    -- ============================================================
    -- 1. 修改绘制函数
    -- ============================================================
    local original_draw = ReaderView.drawHighlightRect
    
    function ReaderView.drawHighlightRect(self, bb, _x, _y, rect, drawer, color, draw_note_mark)
        if drawer == "lighten" then
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
                    bb:paintRectRGB32(x, y, w, h, color)
                else
                    local yellow = Blitbuffer.colorFromName("yellow")
                    if yellow then
                        bb:paintRectRGB32(x, y, w, h, yellow)
                    else
                        bb:paintRect(x, y, w, h, Blitbuffer.COLOR_BLACK)
                    end
                end
            else
                bb:darkenRect(x, y, w, h, self.highlight.lighten_factor)
            end
            return
        end
        
        if original_draw then
            original_draw(self, bb, _x, _y, rect, drawer, color, draw_note_mark)
        end
    end
    
    -- ============================================================
    -- 2. Hook onTap：点击高亮时自动切换遮盖状态
    -- ============================================================
    local original_onTap = ReaderHighlight.onTap
    
    function ReaderHighlight:onTap(_, ges)
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
            self._temp_covered = self._temp_covered or {}
            local is_covered = self._temp_covered[tapped_index] == true
            self._temp_covered[tapped_index] = not is_covered
            
            local ReaderUI = require("apps/reader/readerui")
            if ReaderUI and ReaderUI.instance then
                forceRedraw(ReaderUI.instance)
            else
                UIManager:setDirty(nil, "full")
            end
        end
        
        return original_onTap(self, _, ges)
    end
    
    -- ============================================================
    -- 3. 批量操作函数
    -- ============================================================
    local function coverAllHighlights(highlight)
        highlight._temp_covered = highlight._temp_covered or {}
        local annotations = highlight.ui.annotation.annotations
        for idx, item in ipairs(annotations) do
            if item.drawer then
                highlight._temp_covered[idx] = true
            end
        end
    end
    
    local function uncoverAllHighlights(highlight)
        highlight._temp_covered = highlight._temp_covered or {}
        local annotations = highlight.ui.annotation.annotations
        for idx, item in ipairs(annotations) do
            if item.drawer then
                highlight._temp_covered[idx] = false
            end
        end
    end
    
    -- ============================================================
    -- 4. 手势处理函数
    -- ============================================================
    function ReaderUI:onToggleCoverMode()
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
    -- 5. 注册 Dispatcher 手势动作
    -- ============================================================
    Dispatcher:registerAction("toggle_cover_mode_action", {
        category = "none",
        event = "ToggleCoverMode",
        title = _("Cover all / Uncover all"),
        reader = true,
        ui = true,
    })
    
    -- ============================================================
    -- 6. 主菜单（Cover mode 勾选框）
    -- ============================================================
    local function addToMainMenu(menu_items)
        if menu_items.cover_mode then
            return
        end
        
        menu_items.cover_mode = {
            text = _("Cover mode"),
            sorting_hint = "typeset",
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
            callback = function()
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
            end,
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