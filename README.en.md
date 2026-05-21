# kopatches

#### Description: Some small patches for KOReader

- Cover Mode: `2-reader-covermode` - Adds a cover mode for annotations (highlight, underline, strikethrough, invert) for review purposes
- Cover Generator: `2-visual-covergenerator-v2` - Automatically generates simple Calibre-style covers based on book title and author information when a file lacks a cover

#### Installation

1. Download the `.lua` file and place it directly into the `koreader/patches` folder

#### Screenshots

1. `2-reader-covermode`

![cover-eink](picture/cover-%E5%A2%A8%E6%B0%B4%E5%B1%8F.png)
![uncover-eink](picture/uncover-%E5%A2%A8%E6%B0%B4%E5%B1%8F.png)
![cover-android](picture/cover-%E5%AE%89%E5%8D%93%E6%89%8B%E6%9C%BA.jpg)
![uncover-android](picture/uncover-%E5%AE%89%E5%8D%93%E6%89%8B%E6%9C%BA.jpg)
![PDF-cover-all](picture/%E9%81%AE%E7%BD%96%E6%A8%A1%E5%BC%8F-PDF-%E5%85%A8%E9%83%A8%E9%81%AE%E7%BD%96.png)
![PDF-uncover-all](picture/%E9%81%AE%E7%BD%96%E6%A8%A1%E5%BC%8F-PDF-%E5%85%A8%E9%83%A8%E6%8F%AD%E5%BC%80.png)
![PDF-toggle-single](picture/%E9%81%AE%E7%BD%96%E6%A8%A1%E5%BC%8F-PDF-%E5%88%87%E6%8D%A2%E5%8D%95%E4%B8%AA%E9%81%AE%E7%BD%96.png)

2. `2-visual-covergenerator-v2`

#### Usage Instructions

1. `2-reader-covermode`

- **Cover All / Uncover All**: Check to batch cover all annotations with coverable styles; uncheck to batch uncover all and restore original styles. (Configurable gesture shortcut: Reader - Cover all / Uncover all)
- **Single Cover - Toggle Mode**: Double-tap by default toggles the cover state of a single annotation (if double-tap is disabled, you need to re-enable it). Can be changed to single-tap toggle. Note that single-tapping an annotation will also bring up KOReader's original menu, which may cause some interference. You can enable single-tap toggle if you don't mind this interference.
- **Coverable Drawer Types**: Default is Highlight (only highlights are covered). Can be changed, and multiple types can be selected simultaneously.
- **Note**: Cover mode only affects the currently open book and does not modify the original annotation data. After closing and reopening the book, the original styles (non-cover mode) will be restored.

![covermode-menu-entry](picture//遮盖模式-菜单-入口.png)
![covermode-main-menu](picture/遮盖模式-菜单-主菜.png)
![covermode-single-toggle](picture/遮盖模式-菜单-单个遮盖切换模式.png)
![covermode-coverable-styles](picture/遮盖模式-菜单-可遮盖样式.png)

2. `2-visual-covergenerator-v2`

#### Changelog

1. `2-reader-covermode (V2)`

- Fixed the issue where toggling cover in PDF had no response (could not match index)
- Fixed menu loss when switching books (removed the one-time registration restriction)
- Fixed the issue where some annotations could not be covered in PDF continuous view mode (obtains correct page number via getScrollPagePosition)
- Note: In PDF paged view mode, due to inconsistency between physical PDF page numbers and actual screen page numbers, double-tap will jump back to the screen page containing the first part of the physical page. PDF continuous view mode or switching to single-tap toggle is recommended.

2. `2-visual-covergenerator-v2`

#### Contributing

1. Fork this repository
2. Create a new Feat_xxx branch
3. Commit your code
4. Create a new Pull Request

#### Repository Links

- Gitee: https://gitee.com/gytwo/kopatches
- GitHub: https://github.com/gytwo/kopatches
