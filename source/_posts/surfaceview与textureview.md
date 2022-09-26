---
title: SurfaceView与TextureView
toc: true
date: 2022-09-26 17:26:17
tags:
- Video
categories:
- Video
---
 Surface 对应了一块屏幕缓冲区，每个Window对应一个Surface，任何View都是画在Surface上的，传统的view共享一块屏幕缓冲区，所有的绘制必须在UI线程中进行我们不能直接操作Surface实例，要通过SurfaceHolder，在SurfaceView中可以通过getHolder()方法获取到SurfaceHolder实例。
 <!--more-->
# SurfaceView简介
[SurfaceView与Vsync](https://pacoblack.github.io/2020/12/28/SurfaceView%E4%B8%8EVsync%E5%8E%9F%E7%90%86/)
SurfaceView就是一个有Surface的View里面内嵌了一个专门用于绘制的Surface,SurfaceView 控制这个 Surface 的格式和尺寸以及绘制位置。
```java
if (mWindow == null) {  
    mWindow = new MyWindow(this);  
    mLayout.type = mWindowType;  
    mLayout.gravity = Gravity.LEFT|Gravity.TOP;  
    mSession.addWithoutInputChannel(mWindow, mWindow.mSeq, mLayout,  
    mVisible ? VISIBLE : GONE, mContentInsets);  
}  
```
每个SurfaceView创建的时候都会创建一个MyWindow，new MyWindow(this)中的this正是SurfaceView自身，因此将SurfaceView和window绑定在一起，而前面提到过每个window对应一个Surface.
SurfaceView 的核心在于提供了两个线程：UI线程和渲染线程,两个线程通过“双缓冲”机制来达到高效的界面适时更新。而这个双缓冲可以理解为，SurfaceView在更新视图时用到了两张Canvas，一张frontCanvas和一张backCanvas。
每次实际显示的是frontCanvas，backCanvas存储的是上一次更改前的视图，当使用lockCanvas（）获取画布时，得到的实际上是backCanvas而不是正在显示的frontCanvas，之后你在获取到的backCanvas上绘制新视图，再unlockCanvasAndPost（canvas）此视图，那么上传的这张canvas将替换原来的frontCanvas作为新的frontCanvas，原来的frontCanvas将切换到后台作为backCanvas。

>例如，如果你已经先后两次绘制了视图A和B，那么你再调用lockCanvas（）获取视图，获得的将是A而不是正在显示的B，之后你将重绘的C视图上传，那么C将取代B作为新的frontCanvas显示在SurfaceView上，原来的B则转换为backCanvas。

一般的Activity包含的多个View会组成View hierachy的树形结构，只有最顶层的DectorView才是对WMS可见的，这个DecorView在WMS中有一个对应的WindowState，再SurfaceFlinger中有对应的Layer，而SurfaceView正因为它有自己的Surface，有自己的Window，它在WMS中有对应的WindowState，在SurfaceFlinger中有Layer。

虽然在App端它仍在View hierachy中，但在SurfaceView的Server端(WMS和SurfaceFlinger)中，它与宿主窗口是分离的。这样的好处是对这个Surface的渲染可以放到单独的线程中去做，渲染时可以有自己的GL context。

因为它不会影响主线程对时间的响应。所以它的优点就是可以在独立的线程中绘制，不影响主线程，而且使用双缓冲机制，播放视频时画面更顺畅。

# SurfaceHolder 简介
我们无法直接操作Surface只能通过SurfaceHolder这个接口来获取和操作Surface。

SurfaceHolder中提供了一些lockCanvas():获取一个Canvas对象，并锁定之。

所得到的Canvas对象，其实就是 Surface 中一个成员。加锁的目的其实就是为了在绘制的过程中，Surface 中的数据不会被改变。lockCanvas 是为了防止同一时刻多个线程对同一 canvas写入。

从设计模式的角度来看,Surface、SurfaceView、SurfaceHolder实质上就是MVC(Model-View-Controller)，Model就是模型或者说是数据模型，更简单的可以理解成数据，在这里也就是Surface，View就是视图，代表用户交互界面，这里就是 SurfaceView, SurfaceHolder 就是 Controller.

# TextureView简介
因为SurfaceView不在主窗口中，它没法做动画没法使用一些View的特性方法，所以在Android 4.0中引入了TextureView，它是一个结合了View和SurfaceTexture的View对象。
它不会在WMS中单独创建窗口，而是作为View hierachy中的一个普通view，因此它可以和其他普通View一样进行平移、旋转等动画。但是TextureView必须在硬件加速的窗口中，它显示的内容流数据可以来自App进程或者远程进程。
TextureView 重载了 draw() 方法，其中主要 SurfaceTexture 中收到的图像数据作为纹理更新到对应的 HardwareLayer 中。
urfaceTexture.OnFrameAvailableListener用于通知TextureView内容流有新图像到来。SurfaceTextureListener接口用于让TextureView的使用者知道SurfaceTexture已准备好，这样就可以把SurfaceTexture交给相应的内容源。

Surface为BufferQueue的Producer接口实现类，使生产者可以通过它的软件或硬件渲染接口为SurfaceTexture内部的BufferQueue提供graphic buffer。

SurfaceTexture 可以用作非直接输出的内容流，这样就提供二次处理的机会。与SurfaceView直接输出相比，这样会有若干帧的延迟。同时，由于它本身管理BufferQueue，因此内存消耗也会稍微大一些。

TextureView 是一个可以把内容流作为外部纹理输出在上面的 View, 它本身需要是一个硬件加速层。

# SurfaceTexture
urfaceTexture 是从Android 3.0开始加入，与SurfaceView不同的是，它对图像流的处理并不直接显示，而是转为GL外部纹理，因此用于图像流数据的二次处理。

比如 Camera 的预览数据，变成纹理后可以交给 GLSurfaceView 直接显示，也可以通过SurfaceTexture 交给TextureView 作为 View heirachy 中的一个硬件加速层来显示。
首先，SurfaceTexture从图像流 (来自Camera预览、视频解码、GL绘制场景等) 中获得帧数据，当调用updateTexImage()时，根据内容流中最近的图像更新 SurfaceTexture 对应的GL纹理对象。

SurfaceTexture 包含一个应用是其使用方的BufferQueue。当生产方将新的缓冲区排入队列时，onFrameAvailable() 回调会通知应用。然后，应用调用updateTexImage()，这会释放先前占有的缓冲区，从队列中获取新缓冲区并执行EGL调用，从而使GLES可将此缓冲区作为外部纹理使用。

# SurfaceView vs TextureView
- SurfaceView 是一个有自己Surface的View。
  1. 它的渲染可以放在单独线程而不是主线程中。
  2. 不能做变形和动画。
  3. 客户端使用 SurfaceView 呈现内容时，SurfaceView 会为客户端提供单独的合成层。如果设备支持，SurfaceFlinger 会将单独的层合成为硬件叠加层。
- SurfaceTexture可以用作非直接输出的内容流，这样就提供二次处理的机会。
  1. 与SurfaceView直接输出相比，这样会有若干帧的延迟。同时，由于它本身管理BufferQueue，因此内存消耗也会稍微大一些。
- TextureView是一个可以把内容流作为外部纹理输出在上面的View。它本身需要是一个硬件加速层。
  1. TextureView本身也包含了SurfaceTexture。
  2. 它在View hierachy中做绘制，因此一般它是在主线程上做的（在Android 5.0引入渲染线程后，它是在渲染线程中做的）。
  3. 与SurfaceView+SurfaceTexture组合相比可以完成类似的功能
  4. 具有更出色的 Alpha 版和旋转处理能力，但在视频上以分层方式合成界面元素时，SurfaceView 具有性能方面的优势。

# 小结
1. 在Android 7.0上系统 Surfaceview 的性能比 TextureView 更有优势，支持对象的内容位置和包含的应用内容同步更新，平移、缩放不会产生黑边。 在7.0以下系统如果使用场景有动画效果，可以选择性使用TextureView。
2. 由于失效(invalidation)和缓冲的特性，TextureView增加了额外1~3帧的延迟显示画面更新。
3. TextureView总是使用GL合成，而SurfaceView可以使用硬件overlay后端，可以占用更少的内存。
4. TextureView的内部缓冲队列导致比SurfaceView使用更多的内存。
5. SurfaceView内部自己持有surface，surface 创建、销毁、大小改变时系统来处理的，通过surfaceHolder 的callback回调通知。
6. 当画布创建好时，可以将surface绑定到MediaPlayer中。SurfaceView如果为用户可见的时候，创建SurfaceView的SurfaceHolder用于显示视频流解析的帧图片，如果发现SurfaceView变为用户不可见的时候，则立即销毁SurfaceView的SurfaceHolder，以达到节约系统资源的目的。
