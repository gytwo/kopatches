--[[
Patch: Cover Mode - Add cover mode for highlights (highlight, underline, strikethrough, invert) for review
Author: gytwo
Version: V2
Changelog:
(1) Fixed no response when toggling cover in PDF (cannot match index)
(2) Fixed menu loss when switching books (removed one-time registration restriction)
(3) Fixed inability to cover some highlights in PDF continuous view mode (get correct page number via getScrollPagePosition)
Note: Due to inconsistency between physical PDF page numbers and actual screen page numbers in PDF paged view mode, double-tap navigation will jump back to the screen page where the first part of the physical page is located. PDF continuous view mode is recommended.
]]

local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local userpatch = require("userpatch")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local logger = require("logger")
local _ = require("gettext")

-- Helper function: Check if a point is inside a rectangle
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

-- Force redraw function
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

-- Get the actual page number of a rect (for continuous mode)
local function getPageFromScreenRect(self, rect)
    -- Paged mode: directly use self.state.page
    if not self.page_states then
        return self.state and self.state.page or 1
    end
    
    -- Continuous mode: find page by Y coordinate
    local y = rect.y
    local y_offset = 0
    local gap = (self.page_gap and self.page_gap.height) or 0
    
    for _, state in ipairs(self.page_states) do
        if y >= y_offset and y < y_offset + state.visible_area.h then
            return state.page
        end
        y_offset = y_offset + state.visible_area.h + gap
    end
    
    -- Not found, return first page
    return self.page_states[1] and self.page_states[1].page or 1
end

-- Master switch
local function isEnabled()
    return G_reader_settings:readSetting("cover_mode_enabled", true)
end

-- Get current mode in real-time
local function isDoubleTapMode()
    return G_reader_settings:readSetting("cover_mode_double_tap", true)
end

-- Get list of drawer types to cover
local function getCoveredDrawers()
    local covered_drawers = G_reader_settings:readSetting("cover_mode_drawers", {lighten = true})
    return covered_drawers
end

-- Check if a specific drawer type needs covering
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

-- Flag indicating whether the drawer function has been patched
local drawer_patched = false

local function patchCoverMode()
    
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local ReaderView = require("apps/reader/modules/readerview")
    local ReaderUI = require("apps/reader/readerui")
    
    if not ReaderView then
        return
    end
    
    -- ============================================================
    -- 1. Override drawer function - support multiple styles + PDF compatibility (execute only once)
    -- ============================================================
    if not drawer_patched then
        local original_draw = ReaderView.drawHighlightRect
        
        function ReaderView.drawHighlightRect(self, bb, _x, _y, rect, drawer, color, draw_note_mark)
            if shouldCoverDrawer(drawer) then
                local index = nil
                -- Method 1: Direct object reference matching (works for EPUB)
                if self.highlight.visible_boxes then
                    for _, box in ipairs(self.highlight.visible_boxes) do
                        if box.rect == rect then
                            index = box.index
                            break
                        end
                    end
                end
                
                -- Method 2: Coordinate transformation matching (required for PDF, visible_boxes stores page coordinates)
                if index == nil and self.highlight.visible_boxes then
                    -- Get the actual page number for rect (fixes continuous mode issue)
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
    -- 2. Register double-tap gesture (ensure registration each time a book is opened)
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
    -- 4. Batch operation functions
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
    -- 5. Gesture handler function
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
    -- 6. Register Dispatcher gesture action
    -- ============================================================
    Dispatcher:registerAction("toggle_cover_mode_action", {
        category = "none",
        event = "ToggleCoverMode",
        title = _("Cover all / Uncover all"),
        reader = true,
        ui = true,
    })
    
    -- ============================================================
    -- 7. Drawer type options
    -- ============================================================
    local drawer_names = {
        lighten = _("Highlight"),
        underscore = _("Underline"),
        strikeout = _("Strikethrough"),
        invert = _("Invert"),
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
    -- 8. Main menu - attempt to add each time a book is opened
    -- ============================================================
    local function addToMainMenu(menu_items)
        if menu_items.cover_mode then
            return
        end
        
        menu_items.cover_mode = {
            text = _("Cover Mode"),
            sorting_hint = "typeset",
            sub_item_table = {
                {
                    text = _("Enable Cover"),
                    checked_func = function()
                        return isEnabled()
                    end,
                    callback = function(touchmenu_instance)
                        local new_value = not isEnabled()
                        G_reader_settings:saveSetting("cover_mode_enabled", new_value)
                        local Notification = require("ui/widget/notification")
                        if new_value then
                            Notification:notify(_("Cover mode enabled"))
                        else
                            Notification:notify(_("Cover mode disabled"))
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
                    text = _("Cover All / Uncover All"),
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
                    text = _("Single Cover - Toggle Mode"),
                    enabled_func = function()
                        return isEnabled()
                    end,
                    sub_item_table = {
                        {
                            text = _("Double-tap to toggle (ensure double-tap is not disabled in [Settings] - [Gestures])"),
                            checked_func = function()
                                return isDoubleTapMode() == true
                            end,
                            callback = function(touchmenu_instance)
                                if not isDoubleTapMode() then
                                    G_reader_settings:saveSetting("cover_mode_double_tap", true)
                                    local Notification = require("ui/widget/notification")
                                    Notification:notify(_("Cover mode: double-tap to toggle"))
                                    if touchmenu_instance then
                                        touchmenu_instance:updateItems()
                                    end
                                end
                            end,
                        },
                        {
                            text = _("Single-tap to toggle"),
                            checked_func = function()
                                return isDoubleTapMode() == false
                            end,
                            callback = function(touchmenu_instance)
                                if isDoubleTapMode() then
                                    G_reader_settings:saveSetting("cover_mode_double_tap", false)
                                    local Notification = require("ui/widget/notification")
                                    Notification:notify(_("Cover mode: single-tap to toggle"))
                                    if touchmenu_instance then
                                        touchmenu_instance:updateItems()
                                    end
                                end
                            end,
                        },
                    },
                },
                {
                    text = _("Coverable Drawer Types"),
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
    
    -- Attempt to add menu each time a book is opened
    UIManager:scheduleIn(1, tryAddMenu)
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverMode)

patchCoverMode()