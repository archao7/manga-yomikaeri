# 日语漫画点读助手 · Manga Yomikaeri

在漫画原页点选日语对白，把生词和整句一起收藏。复习时点「回到原处」，便能看见当时是谁、在哪一格说了这句话。

**[打开在线样章](https://archao7.github.io/manga-yomikaeri/)**　·　[下载离线版 ZIP](https://archao7.github.io/manga-yomikaeri/downloads/manga-yomikaeri-offline.zip)　·　[观看 21 秒操作演示](https://archao7.github.io/manga-yomikaeri/media/walkthrough.mp4)

[![车站问路样章，第三句对白与右侧的中文释义](media/reader.png)](https://archao7.github.io/manga-yomikaeri/)

## 第一次用，先试着收藏一个词

1. 打开上方的**在线样章**。离线使用时，解压 ZIP，双击根目录的 **index.html** 即可。
2. 点左下格的对白「次の駅で乗り換えてください。」。先试着理解，再点「查看释义」核对。
3. 展开「收藏句中的词」，输入或粘贴 **乗り換えて**，点「收藏词语」。
4. 打开「复习本」，在刚出现的词卡上点「回到原处」。阅读器会回到原页并选中这句对白。

## 我想读自己的漫画

| 手头的文件 | 怎么开始 | 所需环境 |
| --- | --- | --- |
| 内置样章 | 打开在线版，或双击下载包中的 index.html | 桌面现代浏览器，开启 JavaScript |
| 图片和配套的 .mokuro 标注 | 展开「导入自己的漫画」，先选标注，再多选原图 | 同上。可直接试用 examples/volume 里的标注和三张 PNG |
| 一本扫描 PDF 或一张 JPG、PNG，尚无标注 | 下载并解压，双击「导入自己的漫画.command」，在弹窗选择漫画 | Mac 和 Apple 命令行工具。已实测 Apple Silicon、macOS 26.4 |
| 其他系统上的 PDF 或原图 | 先在 Mac 生成标注和配套页图，再复制到阅读设备 | 阅读设备只需浏览器 |

**Mac 首次处理自己的文件。** 如果工具提示缺少 Swift，在「终端」运行 `xcode-select --install`，在系统窗口完成安装后再次双击导入工具。处理完成后，Finder 会定位到标注，浏览器会打开阅读器。按页面提示选择标注及原图，整卷图片可以一次多选。PDF 的输出位于原文件旁的「文件名-点读」文件夹；单张图片的标注与原图同目录。[分步操作与常见问题](docs/usage.md)

## 从产品问题到交付

| 阶段 | 关键决定 | 可查看的交付物 |
| --- | --- | --- |
| 用户场景与范围 | 面向读原版漫画学日语的人，将「隔天还能找回这句对白」作为核心任务 | [需求、范围和验收标准](docs/product-spec.md) |
| 原型与交互 | 词卡记录生词、原句和书页位置，复习时可直接跳回 | [三屏交互原型](docs/reading-flow.png) · [成品演示](media/walkthrough.mp4) |
| 实现 | 在 Mac 上一次识别文字与位置，浏览器复用标注并在本地保存学习记录 | [网页源码](src/) · [本地转换工具](tools/) |
| 评测与迭代 | 用同一批横排测试漫画比较缩略图与原图识别，再用整卷样例验收阅读操作 | [评测、原始记录与复算命令](evaluation/README.md) · [三页验收样卷](examples/volume/) |

6 页自制测试漫画含 24 句预写对白，以整句文字和标点全部一致计分。400 像素宽缩略图匹配 **22/24**，1600 像素宽原图匹配 **24/24**。因此在原图上识别，显示时再缩放。复杂竖排、手写对白和真实读者的学习效果有待验证。

## 工作原理与使用范围

Swift 工具将扫描 PDF 转成页图，或直接读取 JPG、PNG，用苹果 Vision 的文字识别功能提取日文对白和坐标。每卷按页存为 JSON 标注文件（扩展名 .mokuro）。HTML / JavaScript 阅读器先核对文件名和图像尺寸，再将各句的坐标映射为可点击区域。空白页按原书顺序保留。

图片在本机处理。内置样章附手写中文释义，导入自己的书页可以添加释义、对照原图订正错字。收藏和订正保存在当前浏览器。换浏览器、切换在线与本地入口或清理站点数据，都会影响能看到的笔记。

## 开发和复现

阅读器已经构建好。修改网页时，在项目根目录运行下列命令即可重新生成可离线分发的单文件版本。构建和复算均使用 Python 3 标准库。

```sh
python3 tools/build_reader.py
python3 tools/build_reader.py --check
python3 tools/score.py
```

内置图画和演示使用本项目的自制样章。标注结构参考了 mokuro，文字识别使用苹果 Vision。[mokuro 项目](https://github.com/kha-white/mokuro) · [Apple Vision 文档](https://developer.apple.com/documentation/vision/recognizing-text-in-images)
