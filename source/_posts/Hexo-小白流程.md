---
title: Hexo 小白流程
date: 2019-09-27 15:18:11
tags:
- hexo
categories:
- hexo
---

Hexo 的各种基础配置
<!--more-->

# 配置文件介绍
```
～/blog/_config.yml          // 站点配置文件

~/blog/themes/next/_config.yml  // 主题配置文件
```

# MarkDown
atom 编辑 `MarkDown` ，其中
```
Ctrl + Shift + M  // 可以实时渲染
```
通过三个尖点后可以指定语言

# Hexo
```
hexo clean     // 清理
hexo generate  // 生成
hexo deploy    // 部署
```


```
hexo new "文章标题"
```

## 修改背景图片
在文件 `～/blog/themes/next/source/css/_custom/_custom.styl` 中添加

```
// 添加背景图片
body {
  background: url(https://source.unsplash.com/random/1600x900?wallpapers);
  background-size: cover;
  background-repeat: no-repeat;
  background-attachment: fixed;
  background-position: 50% 50%;
}

// 修改主体透明度
.main-inner {
  background: #fff;
  opacity: 0.9;
}

// 修改菜单栏透明度
.header-inner {
  opacity: 0.8;
}
```

## 添加背景动画 canvas-nest
基本流程参考 [theme-next-canvas-nest](https://github.com/theme-next/theme-next-canvas-nest)

*step1* 进入 **next** 根目录下
```
git clone https://github.com/theme-next/theme-next-canvas-nest source/lib/canvas-nest
```

*step2* 修改 **next** 主题配置文件 _config.yml

```
...
canvas_nest: true
...
canvas_nest:
  enable: true
  onmobile: true # display on mobile or not
  color: '0,0,255' # RGB values, use ',' to separate
  opacity: 0.5 # the opacity of line: 0~1
  zIndex: -1 # z-index property of the background
  count: 99 # the number of lines
...
```

*step3* 在文件 `～/blog/themes/next/source/layout/_layout.swig` 中的</body>标签底部添加

```
{% if theme.canvas_nest %}
<script type="text/javascript" src="//cdn.bootcss.com/canvas-nest.js/1.0.0/canvas-nest.min.js"></script>
{% endif %}
```

## 添加卡通人物 live2d
项目地址[hexo-helper-live2d](https://github.com/EYHN/hexo-helper-live2d)

```
$ npm install --save hexo-helper-live2d
$ npm install  <live2d-widget-model>  // 在项目中选择喜欢的 model
```
最后在站点配置文件 _config.yml 添加

```
live2d:
  enable: true
  scriptFrom: local
  pluginRootPath: live2dw/
  pluginJsPath: lib/
  pluginModelPath: assets/
  tagMode: false
  log: false
  model:
    use: live2d-widget-model-wanko
  display:
    position: right
    width: 150
    height: 300
  mobile:
    show: true
  react:
    opacity: 0.7
```
