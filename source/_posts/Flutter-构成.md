---
title: Flutter 构成
toc: true
date: 2019-09-29 17:41:19
tags:
  - Flutter
categories:
  - Flutter
---
Flutter 的构成
<!--more-->
![Vsync 流](/images/Vsync_single.jpg)

在Flutter框架中存在着一个渲染流水线（Rendering pipline）。这个渲染流水线是由垂直同步信号（Vsync）驱动的，而Vsync信号是由系统提供的，如果你的Flutter app是运行在Android上的话，那Vsync信号就是我们熟悉的Android的那个Vsync信号。当Vsync信号到来以后，Flutter 框架会按照图里的顺序执行一系列动作: 动画（Animate）、构建（Build）、布局（Layout）和绘制（Paint），最终生成一个场景（Scene）之后送往底层，由GPU绘制到屏幕上。

//TODO: https://juejin.im/post/5c7cd2f4e51d4537b05b0974
