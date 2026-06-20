# Table of Contents

- [QuickActions Panel](#quickactions---koreader-shortcut-panel)
- [Cover Visual Settings](#cover-visual-settings)
- [Cloze Mode](#cloze-mode)

---

# QuickActions - KOReader Shortcut Panel

> KOReader QuickActions Patch - Adds a customizable shortcut tab to the top menu bar

---

## Installation

Place `2-quickactions.lua` into `koreader/patches/` directory, then restart KOReader.

> Uninstallation: Delete the file, and optionally delete `koreader/settings/quickactions.lua` (configuration file).

---

## Quick Start

New user? Follow these steps to get started:

1. **Open the panel**: Click the QuickActions tab (⭐ icon) in the top menu bar

2. **Try default buttons**: The panel comes pre-configured with WiFi, Night Mode, Rotation, and other commonly used functions—tap to use them

3. **Add more built-in actions**: Click the **[Add Button](#adding-buttons)** on the panel → tap **☐ Add All** → all built-in actions are added to the panel with one click

4. **Show button labels**: **[Settings Menu](#settings-menu)** → **[Edit Buttons](#editing-buttons)** → enable **Show Labels** for easier button identification

5. **Customize as needed**: If built-in actions aren't enough, click **[Create Custom Action](#creating-custom-actions)** to create your own shortcuts

![qa-start](picture/qa-start.jpg)
![qa-add%20buttons](picture/qa-add%20buttons.jpg)
![qa-settings](picture/qa-settings.jpg)
![edit%20buttons-label](picture/qa-edit%20buttons-label.jpg)

---

## Core Concept: Three-Layer Architecture


```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Action Library (all available actions) │
│ ├── Built-in actions (system-preset, 26 total) │
│ └── Custom actions (user-created) │
└─────────────────────────────────────────────────────────────┘
│
▼ Add/Remove
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: Button Panel (buttons shown in the QuickActions │
│ tab) │
│ └── Select actions from the library to display, in order │
└─────────────────────────────────────────────────────────────┘
│
▼ Filter Display
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: Interface Filtering (show different buttons in │
│ different interfaces) │
│ ├── Universal: shown in both File Manager + Reader │
│ ├── File Manager Only: shown only in File Manager │
│ └── Reader Only: shown only in Reader │
└─────────────────────────────────────────────────────────────┘

```


---

## Settings Menu

### Access (choose any)

- Tap the **QuickActions Settings** button on the panel
- Long-press the panel title area (enabled by default, can be disabled in settings)
- File Manager/Reader top menu → **Tools** → **QuickActions Settings**
- [Gesture binding](#gesture-support) (`qa_settings_action`)

> 💡 Any of the above methods will open the settings menu.

### Settings Overview

| Menu | Function |
|------|----------|
| Enable Tab | Show/hide the panel, requires restart |
| Tab Icon | Select panel tab icon in the [Icon Picker](#icon-picker) |
| [System Icon Replacement](#system-icon-replacement) | Replace KOReader's native system icons |
| [UI Font Switching](#ui-font-switching) | Switch menu, dialog, button, and other UI fonts |
| [Interface Filtering](#interface-filtering) | Set button visibility per interface |
| QuickActions | Manage [Built-in Actions](#built-in-actions-list) / [Custom Actions](#creating-custom-actions), [Edit Actions](#editing-actions) |
| [Edit Buttons](#editing-buttons) | Arrange, [Add Buttons](#adding-buttons), adjust shape/background/size/labels |
| Save Current as Default | **Save all current settings on this device as default configuration** |
| Apply Default Configuration | **Restore the saved default configuration** |
| Reset All Settings | **Restore factory state**: 💡 Note that this will overwrite the previously saved default configuration—use with caution |

> 💡 All configurations are device-specific. To migrate to another device, simply copy the configuration file `koreader/settings/quickactions.lua` from this device to the corresponding directory on the target device.

---

## Built-in Actions List

> 💡 **Integration Notes**: Patch-integrated and plugin-integrated actions always exist in the action library but are only functional when the corresponding patch/plugin is installed.

| # | Action Library | Function | Type | Button Panel | [Interface Filter](#interface-filtering) | Integration |
|---|----------------|----------|------|:---:|------|------|
| 1 | Wi-Fi | Toggle Wi-Fi | System Control | ✅ Added by default | Universal | None |
| 2 | Night Mode | Toggle dark/light theme | System Control | ✅ Added by default | Universal | None |
| 3 | Rotation | Rotate screen orientation | System Control | ✅ Added by default | Universal | None |
| 4 | Screenshot | Take screenshot after 4-second countdown | System Control | ✅ Added by default | Universal | None |
| 5 | Continue Reading | Open the most recently read book | System Control | ✅ Added by default | Universal | None |
| 6 | Search | Full-text search (Reader) / File search (FM) | System Control | ✅ Added by default | Universal | None |
| 7 | Exit | Exit KOReader | System Control | ❌ Needs [Adding](#adding-buttons) | Universal | None |
| 8 | Restart | Restart KOReader | System Control | ✅ Added by default | Universal | None |
| 9 | Frontlight Slider | Show brightness slider at panel bottom | System Control | ✅ Added by default | Universal | None |
| 10 | Color Temperature Slider | Show color temperature slider at panel bottom | System Control | ✅ Added by default (if supported) | Universal | None |
| 11 | Power | Show power menu (Sleep/Restart/Exit) | System Control | ❌ Needs [Adding](#adding-buttons) | Universal | None |
| 12 | HTTP Server | Start/stop HTTP service | System Control | ❌ Needs [Adding](#adding-buttons) | Universal | None |
| 13 | Font List | Quickly switch **Reader** fonts (book content) | Font Management | ✅ Added by default | Reader | None |
| 14 | Switch UI Font | Switch **KOReader UI** fonts (menus/dialogs) | Font Management | ❌ Needs [Adding](#adding-buttons) | Universal | None |
| 15 | QuickActions Settings | Open this patch's settings menu | QA Control | ✅ Added by default | Universal | None |
| 16 | Add Button | Select actions from library to add to panel | QA Control | ✅ Added by default | Universal | None |
| 17 | Create QuickAction | Create new custom actions | QA Control | ✅ Added by default | Universal | None |
| 18 | Cover Visual Settings | Cover display settings | Patch Integration | ❌ Needs [Adding](#adding-buttons) | File Manager | `2-fm-cover.lua` |
| 19 | Cloze Mode | Toggle text cloze mode | Patch Integration | ❌ Needs [Adding](#adding-buttons) | Reader | `2-reader-clozemode.lua` |
| 20 | Reading Insights | Show reading statistics popup | Patch Integration | ❌ Needs [Adding](#adding-buttons) | Universal | `2-reading-insights-dashboard-v2` |
| 21 | ZLibrary Search | Open ZLibrary search | Plugin Integration | ❌ Needs [Adding](#adding-buttons) | Universal | `zlibrary.koplugin` |
| 22 | CloudLibrary - Sync | One-click cloud library sync | Plugin Integration | ❌ Needs [Adding](#adding-buttons) | Universal | `cloudlibrary.koplugin` |
| 23 | CloudLibrary - Batch Download/Delete | Batch manage cloud library books | Plugin Integration | ❌ Needs [Adding](#adding-buttons) | Universal | `cloudlibrary.koplugin` |
| 24 | CloudLibrary - Settings | Open cloud library settings | Plugin Integration | ❌ Needs [Adding](#adding-buttons) | Universal | `cloudlibrary.koplugin` |
| 25 | FilebrowserPlus | Start/stop file browsing service | Plugin Integration | ❌ Needs [Adding](#adding-buttons) | Universal | `filebrowserplus.koplugin` |
| 26 | Annotations Viewer | View current book/all annotations | Plugin Integration | ❌ Needs [Adding](#adding-buttons) | Universal | `annotationsviewer.koplugin` |

---

## Creating Custom Actions

When [built-in actions](#built-in-actions-list) don't meet your needs, custom actions can be created in the following ways.

### Access (choose any)

- Tap the **Create QuickAction** button on the panel
- Or via [Settings Menu](#settings-menu) → QuickActions → Create New

### Steps

> 💡 Edit in the [Edit Dialog](#editing-actions) that appears

![qa-add%20actions](picture/qa-add%20actions.jpg)

1. **Select action type** (five types)

| Type | Description |
|------|-------------|
| **Folder** | Navigate to a specified directory |
| **Collection** | Open a specific collection from Favorites |
| **Plugin** | Call a function from an installed plugin (automatically scans and lists) |
| **System Action** | Call Dispatcher system actions (supports all types) |
| **Menu Recording** | Click menu items to record a path, execute complex operations with one click |

![qa-add%20actions2](picture/qa-add%20actions2.jpg)
![qa-add%20actions3](picture/qa-add%20actions3.jpg)

2. **Select icon**

> 💡 Choose an icon in the [Icon Picker](#icon-picker)

![qa-add%20actions4](picture/qa-add%20actions4.jpg)

3. **Select [Interface Filtering](#interface-filtering)**

| Option | Description |
|--------|-------------|
| **Universal** | Shown in both File Manager + Reader |
| **File Manager Only** | Shown only in File Manager |
| **Reader Only** | Shown only in Reader |

> 💡 The interface filter auto-populates based on the action type, but can be changed.
> 💡 Menu-recorded actions are automatically locked to the interface they were recorded in and cannot be changed.

4. **Modify action name** (optional)

> 💡 The action name auto-populates based on the selected action, but can be changed.

5. Tap **Save**

> 💡 After saving, the action is added to the action library (visible in [Add Button](#adding-buttons))

- If **Auto-add to buttons on save** is enabled (enabled by default), the action appears in the panel automatically
- If disabled, manually add it via [Add Button](#adding-buttons)

---

## Editing Actions

All buttons (both built-in and custom actions) can be edited by long-pressing.

### Long-Press Entry

Long-press any button on the panel (enabled by default, can be disabled in settings) to enter the edit interface:

- **Built-in actions long-press**: Edit name, icon, interface filter, reorder, remove
- **Custom actions long-press**: Edit name, icon, interface filter, **action**, reorder, remove, **delete**

> 💡 Built-in actions cannot have their action changed or be deleted.

### Edit Dialog

| Operation | Description |
|-----------|-------------|
| **Name** | Modify the button's display name |
| **[Icon](#icon-picker)** | Tap to open the icon picker and change the icon |
| **[Interface](#interface-filtering)** | Switch between Universal/File Manager Only/Reader Only (menu actions are locked and cannot be changed) |
| **[Action](#creating-custom-actions)** | Only supports changing custom actions |
| **[Reorder](#editing-buttons)** | ◀ Move Left / ▶ Move Right / Tap position number to enter sort interface for drag-and-drop reordering |
| **[Remove](#adding-buttons)** | Remove from panel only; action remains in library and can be re-added |
| **[Delete](#creating-custom-actions)** | Custom actions only; permanently deletes from the action library—must be recreated |

![qa-edit%20actions](picture/qa-edit%20actions.jpg)
![qa-edit%20actions2](picture/qa-edit%20actions2.jpg)

---

## Editing Buttons

- **Arrange buttons**: [Settings Menu](#settings-menu) → Edit Buttons → Arrange Buttons (drag to reorder) (also via long-press → [Edit Dialog](#editing-actions))
- **[Add Buttons](#adding-buttons)**: [Settings Menu](#settings-menu) → Edit Buttons → Add Buttons (select from action library)
- **Button appearance**: [Settings Menu](#settings-menu) → Edit Buttons → Adjust shape/background/size/labels

![edit%20buttons-label](picture/qa-edit%20buttons-label.jpg)

## Adding Buttons

> 💡 Add buttons from the action library to the panel or remove them from the panel (without deleting the action itself)

1. Tap the **Add Button** button on the panel to enter the add interface
2. Tap an action in the list to toggle add/remove status
3. Tap **☐ Add All** to add all actions to the panel with one click (up to 66 buttons)
4. Tap **☑ Remove All** to remove all addable actions from the panel with one click
5. Can also access via **[Settings Menu](#settings-menu)** → **[Edit Buttons](#editing-buttons)** → Add Buttons

![qa-add%20buttons](picture/qa-add%20buttons.jpg)

---

## Interface Filtering

Set button visibility per interface, allowing the panel to automatically show the most relevant buttons in different scenarios.

### Access

| Access Method | Description |
|---------------|-------------|
| [Settings Menu](#settings-menu) → **Interface Filtering** | Centrally manage interface filter settings for all actions |
| **Create Custom Action** → Select Interface Filter | Specify interface filter level directly when creating an action |
| **Long-press button** → Edit → Interface | Modify interface filter level of an existing action |

> 💡 Any of the above methods can be used to set interface filtering.

### Enable Interface Filtering

When enabled, buttons are shown or hidden based on their interface settings in the corresponding interface. When disabled, all buttons are shown in all interfaces.

### Three Interface Filter Levels

| Level | Display Location | Use Case |
|-------|------------------|----------|
| **Universal** | Shown in both File Manager + Reader | Functions unrelated to the current interface, usable in any scenario |
| **File Manager Only** | Shown only in File Manager | Functions related only to file management, e.g., Cover Visual Settings |
| **Reader Only** | Shown only in Reader | Functions related only to reading, e.g., Font List, Cloze Mode |

### Dedicated List Management

Tap **File Manager Only** or **Reader Only** to enter the dedicated list:

| Operation | Description |
|-----------|-------------|
| Tap an action to toggle dedicated status | ✓ indicates the action is shown only in the current interface |
| **Set All Dedicated** | Set all manually configurable actions in the current interface to dedicated (menu-recorded actions excluded) with one click |
| **Clear All** | Clear the dedicated status of all manually configurable actions in the current interface (menu-recorded actions excluded) with one click |

> 💡 Menu-recorded actions have their interface locked at the time of recording and cannot be changed, so they are not included in batch operations.

### Reset Dedicated

Tap **Reset to Default Dedicated** to restore all actions to their default state:

| Action Type | Reset Result |
|-------------|--------------|
| Built-in actions | Restore to the default view defined in the code |
| Custom actions | Restore to the view selected at creation time |
| Menu actions | Keep the interface locked at recording time—unaffected by reset |

![qa-filter](picture/qa-filter.jpg)
![qa-filter2](picture/qa-filter2.jpg)
![qa-filter3](picture/qa-filter3.jpg)

---

## Icon Picker

QuickActions includes a unified icon picker interface for selecting icons for actions, tabs, etc.

- Browse Nerd Font icons included in koreader system in grid view
- Automatically scan SVG/PNG files in `koreader/icons/` and system icon directories
- Search/filter by **icon name** or **Nerd Font codepoint**
- Jump to a specific page (tap the page number to bring up a jump dialog)
- Browse and switch to any directory to find icon files

| Mode | Supported Types | Trigger Entry |
|------|-----------------|---------------|
| **Full Mode** | Nerd Font + SVG/PNG files | Edit action icon, [Create custom action](#creating-custom-actions) |
| **File Mode** | SVG/PNG files only (Nerd Font not supported) | [Settings Menu](#settings-menu) → Tab icon, [System icon replacement](#system-icon-replacement) |

> 💡 **Tab icons** and **System icon replacement** only support SVG/PNG format files, Nerd Font icons are not supported.

![qa-icons-all](picture/qa-icons-all.png)
![qa-icons-onlyfile](picture/qa-icons-onlyfile.png)
![qa-icons-search](picture/qa-icons-search.png)
![qa-icons-file%20browser](picture/qa-icons-file%20browser.jpg)
![qa-icons-rotate-nerdfont](picture/qa-icons-rotate-all.png)
![qa-icons-rotate-custom](picture/qa-icons-rotate-file.png)

---

## System Icon Replacement

Globally replace KOReader's built-in system icons (such as menu icons, button icons, etc.).

> ⚠️ **Note**: Only SVG/PNG formats are supported; Nerd Font icons are not supported. See [Icon Picker](#icon-picker) for details.

### Access

[Settings Menu](#settings-menu) → **System Icon Replacement**

### Steps

1. Enter to view all system icons displayed in a grid; replaced icons show a black border
2. Tap any icon to open the selection interface (see [Icon Picker](#icon-picker))
3. Select a new icon from the icon library, or tap **Restore Default** to revert to the system default
4. Tap **Apply Replacements** to save all changes
5. Restart KOReader for changes to take effect

### Batch Operations

| Button | Function |
|--------|----------|
| **Reset All** | Restore all system icons to default (requires restart to take effect) |
| **Apply Replacements** | Save all current replacements (requires restart to take effect) |

![qa-switch%20system%20icons](picture/qa-switch%20system%20icons.jpg)
![switch%20system%20icons2](picture/qa-switch%20system%20icons2.jpg)

---

## UI Font Switching

Switch KOReader UI fonts (menus, dialogs, buttons, and all UI text) without affecting the book content fonts in the reader.

### Access (choose any)

- Tap the **Switch UI Font** button on the panel (needs to be added via [Add Button](#adding-buttons))
- [Settings Menu](#settings-menu) → **UI Font Switching**

### Three Font Types

| Type | Scope | Default Font |
|------|-------|--------------|
| **Regular Font** | Menus, dialogs, notifications, and other main UI text | NotoSans-Regular.ttf |
| **Bold Font** | Titles, buttons, etc. | NotoSans-Bold.ttf |
| **Monospace Font** | Input fields, etc. | DroidSansMono.ttf |

### Steps

1. Open **UI Font Switching**
2. Tap the font type to switch (Regular/Bold/Monospace)
3. All available fonts on the device are automatically listed; select the target font
4. Restart KOReader for changes to take effect

> 💡 If the fonts pre-installed on your device don't meet your needs, you can place font files (`.ttf` / `.otf`) into `koreader/fonts/` directory; they will appear in the list after restart.

### Reset

Tap **Reset All** to restore all fonts to default → confirmation dialog appears → tap **Restart** for dialog fonts to take effect immediately; tab menu fonts require a restart.

![qa-switch%20ui%20font](picture/qa-switch%20ui%20font.jpg)
![switch%20ui%20font2](picture/qa-switch%20ui%20font2.jpg)
![switch%20ui%20font3](picture/qa-switch%20ui%20font3.jpg)

---

## Font List

Quickly switch **Reader** fonts (the display font for book content), available only in the Reader.

### Access (choose any)

- Added by default on the panel
- If not present, add via [Add Button](#adding-buttons)

### Steps

1. Open a book
2. Tap the **Font List** button on the panel
3. A font list dialog appears, automatically listing all available fonts on the device
4. Tap the target font to switch immediately
5. The currently used font is marked with a ✓

> 💡 If the fonts pre-installed on your device don't meet your needs, you can place font files (`.ttf` / `.otf`) into `koreader/fonts/` directory; they will appear in the list after restart.

![qa-switch%20font%20in%20reader](picture/qa-switch%20font%20in%20reader.jpg)

### Comparison: Font List vs UI Font Switching

| | Font List | UI Font Switching |
|--|-----------|-------------------|
| **Target** | Book content fonts | KOReader UI fonts (menus/dialogs) |
| **Applicable Interface** | Reader only | Universal |
| **Switch Method** | Takes effect immediately | Menu title fonts require restart to take effect |

---

## Gesture Support

Bind Dispatcher actions in KOReader's gesture settings (General):

| Action Name | Display Name | Function |
|-------------|--------------|----------|
| `quick_actions_panel` | QA: QuickActions Panel | Open the QuickActions panel |
| `qa_settings_action` | QA: QuickActions Settings | Open the [Settings Menu](#settings-menu) |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Panel doesn't display | Check if "Enable Tab" is turned on; delete configuration file `koreader/settings/quickactions.lua` and restart |
| Nerd Font not displaying | If some icons show as question marks, the codepoint may not be compatible with your version—update the hardcoded Nerd Font codepoints in the patch file or remove the problematic ones |
| SVG/PNG icons not displaying | Place icon files in `koreader/icons/` directory |
| UI font switching doesn't take effect | Tab menu fonts require restarting KOReader to take effect |
| Integrated plugin/patch actions unavailable | Confirm the plugin is installed and enabled; if still not working, the original plugin/patch may have been updated and the action interface may have changed—update the registration code accordingly |
| Menu recording doesn't execute | Menu structure may have changed (e.g., system update, installing/updating other plugins/patches that inject or modify the menu) causing the recorded menu path to no longer point to the current menu—re-record the action |

---

# Cover Visual Settings

## Overview

- Unified handling of book covers and folder covers, with optimized placeholders for books without covers
- Works in both Mosaic (grid covers) and List modes
- Compatible with simpleui.koplugin (disable simpleui library-related settings)

![fmcover](picture/fmcover.jpg)

---

## Feature List

![fmcover1](picture/fmcover1.jpg)

### I. Book Covers

![fmcover2](picture/fmcover2.jpg)

#### 1. Placeholder Covers

![fmcover3](picture/fmcover3.jpg)

Automatically generated when a book has no embedded cover:

| Style | Effect |
|-------|--------|
| Simple | White background + black text |
| Gradient | Blue-purple gradient background + dark text |

#### 2. Badge System

![fmcover4](picture/fmcover4.jpg)

| Badge | Position | Description |
|-------|----------|-------------|
| Favorite Star | Top-left | Marks favorited books |
| Reading Progress | Top-right | Shows 1%-99% progress |
| NEW Banner | Top-right (diagonal) | Marks newly added books |
| Page Count | Bottom-left | Shows total pages (K/M formatted) |
| Format Badge | Bottom-right | Shows EPUB/PDF/CBZ format |

#### 3. Status Feedback
- **Dim Finished Books**: Read books have cover brightness reduced to 60%

---

### II. Folder Covers

![fmcover5](picture/fmcover5.jpg)

#### 1. Cover Retrieval Priority
1. Explicit cover files (`cover.jpg`, `cover2.jpg`, `cover3.jpg`, `cover4.jpg`)
2. Covers from books inside the folder (take first N based on KOReader sort order)
3. Auto-generated placeholder cover (displays folder name)

#### 2. Cover Display Modes

![fmcover6](picture/fmcover6.jpg)

| Mode | Description |
|------|-------------|
| Gallery | 4-grid collage, up to 4 covers |
| Stack | Stacked effect, covers scaled to 72% and offset-stacked |
| Normal | Shows only the first book's cover (fills entire area) |
| None | No cover, only folder name displayed |

#### 3. Folder Cover Overlays

| Element | Position/Style |
|---------|----------------|
| Folder Name | Centered or bottom, semi-transparent or opaque |
| File Count Badge | Circular badge at top-right |
| Spine Decorative Lines | Double-line decoration on left or top |

---

### III. General Settings

![fmcover7](picture/fmcover7.jpg)

| Setting | Options |
|---------|---------|
| Unified Cover Aspect Ratio | 3:4 (default) / 2:3 |
| Rounded Corners | On/Off |
| Show Title | On/Off |
| Show Author | On/Off |
| Hide Underline | On/Off |
| Hide Up Folder | On/Off |

---

### IV. Badge Customization

#### 1. Badge Size
- Compact / Normal / Large / Extra Large

#### 2. Badge Color
- Black / White / Gray / Blue / Green / Amber / Red

#### 3. Individual Switches
- Favorite Star
- Progress Percentage
- NEW Banner
- Dim Finished Books
- Page Count
- Format Badge

---

### V. Gesture Support

| Feature | Description |
|---------|-------------|
| Gesture Action | Open Cover Visual Settings |
| Binding Method | KOReader Settings → Gesture Manager |
| Applicable Interface | File Manager |

Triggering the gesture opens the settings menu directly without navigating through the system menu.

![fmcover8](picture/fmcover8.jpg)
![fmcover9](picture/fmcover9.jpg)
![fmcover10](picture/fmcover10.jpg)

---

## Installation

1. Place `2-fm-cover.lua` into KOReader's `patches` folder
2. Restart KOReader
3. Access settings via the file manager top menu or gesture manager

---

## Default Configuration

| Setting | Default Value |
|---------|---------------|
| Cover Aspect Ratio | 3:4 |
| Rounded Corners | On |
| Show Title | On |
| Show Author | On |
| Badge Size | Normal |
| Badge Color | Black |
| Placeholder Style | Simple |
| Folder Mode | Gallery |
| Show Spine Lines | On |
| Show File Count | On |
| Show Folder Name | On (bottom, semi-transparent) |

---

## Changelog

- Supports both Mosaic and List modes
- Unified cover aspect ratio (3:4 / 2:3)
- Complete badge system
- Folder cover modes (Gallery/Stack/Normal/None)
- Folder name, file count, spine decorative lines
- Gesture quick access to settings
- ButtonDialog-style menu with multi-level navigation

---

# Cloze Mode

Adds a cloze/review mode for KOReader annotations (highlights, underlines, strikeouts, inverted colors).

## Installation

1. Place `2-reader-clozemode` into KOReader's `patches` folder
2. Restart KOReader
3. Access settings via the file manager top menu or gesture manager

## Screenshots

![cover-ink screen](picture/cover-墨水屏.png)
![uncover-ink screen](picture/uncover-墨水屏.png)
![cover-android phone](picture/cover-安卓手机.jpg)
![uncover-android phone](picture/uncover-安卓手机.jpg)
![PDF-cover all](picture/遮盖模式-PDF-全部遮盖.png)
![PDF-uncover all](picture/遮盖模式-PDF-全部揭开.png)
![PDF-toggle single](picture/遮盖模式-PDF-切换单个遮盖.png)

## Usage Instructions

- **Cover All**: Check to batch-cover all annotations with coverable styles; uncheck to batch-uncover and restore original styles. (Supports gesture shortcut: Reader - Cover All/Uncover All)
- **Individual Cover - Toggle Mode**: Default double-tap toggles individual annotation cover state. Can be changed to single-tap, but note that single-tap originally opens KOReader's annotation menu (can be enabled regardless of this interference).
- **Coverable Styles**: Default is Highlight only. Can be changed, multiple styles can be selected simultaneously.
- **Note**: The cover mode only affects the currently open book and does not modify the original annotation data. After closing and reopening the book, annotations return to their original style (non-covered state).

![clozemode-menu entry](picture/遮盖模式-菜单-入口.png)
![clozemode-main menu](picture/遮盖模式-菜单-主菜单.png)
![clozemode-toggle mode](picture/遮盖模式-菜单-单个遮盖切换模式.png)
![clozemode-coverable styles](picture/遮盖模式-菜单-可遮盖样式.png)

## Changelog

- (1) Fixed issue where toggling cover mode had no effect in PDF (index mismatch) (V3)
- (2) Fixed menu loss when switching books (re-add menu each time a book is opened) (V3)
- (3) Fixed issue where some annotations couldn't be covered in PDF continuous view mode (get correct page number via getScrollPagePosition) (V3)
- (4) Fixed page jumping issue in PDF paginated mode (removed recalculate from forceRedraw) (V3)
- (5) Re-register gestures each time a book is opened to ensure double-tap toggle always works (V3)
- (6) Three toggle modes: double-tap toggle, single-tap toggle (block menu), single-tap toggle (popup menu) (V3)

#### Contributing

1. Fork this repository
2. Create a new Feat_xxx branch
3. Commit your code
4. Create a new Pull Request

#### Repository Links

- Gitee: https://gitee.com/gytwo/kopatches
- GitHub: https://github.com/gytwo/kopatches