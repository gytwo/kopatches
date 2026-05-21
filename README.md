# kopatches

#### 介绍：适用于koreader的一些小补丁

- 遮盖模式：2-reader-covermode  为标注（高亮、下划线、删除线、反色）添加遮盖模式以供复习
- 封面生成器：2-visual-covergenerator-v2  在文件没有封面时自动生成类似calibre风格的简单封面（基于书籍标题及作者信息）
  
#### 安装教程

1.  下载_lua文件，直接放到koreader/patches文件夹下

#### 效果

1.  2-reader-covermode
![cover-墨水屏](picture/cover-%E5%A2%A8%E6%B0%B4%E5%B1%8F.png)
![uncover-墨水屏](picture/uncover-%E5%A2%A8%E6%B0%B4%E5%B1%8F.png)
![cover-安卓手机](picture/cover-%E5%AE%89%E5%8D%93%E6%89%8B%E6%9C%BA.jpg)
![uncover-安卓手机](picture/uncover-%E5%AE%89%E5%8D%93%E6%89%8B%E6%9C%BA.jpg)
![PDF-全部遮盖](picture/遮盖模式-PDF-全部遮盖.png)
![PDF-全部揭开](picture/遮盖模式-PDF-全部揭开.png)
![PDF-切换单个遮盖](picture/遮盖模式-PDF-切换单个遮盖.png)

2.  2-visual-covergenerator-v2

#### 使用说明

1.  2-reader-covermode

- 全部遮盖：点击勾选即可批量遮盖所有可遮盖样式的标注，取消勾选则批量揭开所有遮盖，还原原本样式。（可设置快捷手势：阅读器-cover all/uncover all）
- 单个遮盖-切换模式：默认双击可以切换单个标注的遮盖状态（但有些人可能设置了禁用双击，需要取消禁用双击才能实现切换）。可以更改为单击切换，但是单击标注本身会弹出koreader原始菜单，会有一些干扰，不介意这点干扰的话可以开启单击切换。
- 可遮盖样式：默认为高亮（即仅高亮应用遮盖模式），可更改，也可同时选择多个样式
- PS：遮盖模式仅对当前打开的书籍有效，不会影响原本的标注数据，关闭书籍后重新打开，仍旧是原本样式（即非遮盖模式）

![covermode-设置入口](picture/遮盖模式-菜单-入口.png)
![covermode-设置入口2](picture/遮盖模式-菜单-主菜单.png)
![covermode-设置入口3](picture/遮盖模式-菜单-单个遮盖切换模式.png)
![covermode-设置入口4](picture/遮盖模式-菜单-可遮盖样式.png)

2.  2-visual-covergenerator-v2
   
#### 更新说明

1.  2-reader-covermode（V2）

- 修复在PDF中切换遮盖无反应（匹配不到index）的问题
- 修复切换书籍时菜单丢失的问题（取消只注册一次的限制）
- 修复PDF连续视图模式下部分标注无法遮盖的问题（通过 getScrollPagePosition 获取正确页码）
- 提示：PDF分页视图模式下由于PDF物理页码与实际屏幕页码不一致，会存在双击跳转回物理页码第一部分所在屏幕页码的问题，推荐使用PDF连续视图模式或者改用单击切换遮盖

2.  2-visual-covergenerator-v2

#### 参与贡献

1.  Fork 本仓库
2.  新建 Feat_xxx 分支
3.  提交代码
4.  新建 Pull Request


#### 项目地址

- Gitee : https://gitee.com/gytwo/kopatches
- GitHub: https://github.com/gytwo/kopatches
