# Cover Visual Settings: 2-fm-cover

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

# Cloze Mode: 2-reader-clozemode

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