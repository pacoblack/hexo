---
title: Android Project Butter
toc: true
date: 2019-09-29 18:18:35
tags:
  - Android
categories:
  - Android
---

Android 有关 UI 显示不流畅的问题也一直未得到根本解决, 直到 Android 4.0问世。作为严重影响Android口碑问题之一的UI流畅性差的问题，首先在Android 4.1版本中得到了有效处理。其解决方法就是本文要介绍的Project Butter。Project Butter对Android Display系统进行了重构，引入了三个核心元素，即 **VSYNC** 、**Triple Buffer** 和 **Choreographer**。其中，**VSYNC** 是理解Project Buffer的核心。

<!--more-->

# Android系统UI交互滞后的原因

在一个典型的显示系统中，frame buffer代表了屏幕即将要显示的一帧画面。假如CPU/GPU绘图过程与屏幕刷新所使用的buffer是同一块，那么当它们的速度不同步的时候，是很可能出现类似的画面“割裂”的。
举个具体的例子来说
>假设显示器的刷新率为66Hz，而CPU/GPU绘图能力则达到100Hz，也就是它们处理完成一帧数据分别需要0.015秒和0.01秒。
1. 0.01秒时，由于两者速率相差不小，此时buffer中已经准备好了第1帧数据，显示器只显示了第1帧画面的2/3
2. 0.015秒时，第1帧画面完整地显示出来了，此时buffer中有1/3的部分已经被填充上第2帧数据了
3. 0.02秒时，Buffer中已经准备好第2帧数据，而显示屏出现了screen tearing，有三分之一是第2帧内容，其余的则属于第1帧画面

在单缓冲区的情况下，这个问题很难规避。所以引进了双缓冲技术，基本原理就是采用两块buffer。一块back buffer用于CPU/GPU后台绘制，另一块framebuffer则用于显示，当back buffer准备就绪后，它们才进行交换。那么什么时候切换两个缓冲区最合适呢？显示器有两个重要特性，行频和场频。行频(Horizontal ScanningFrequency)又称为“水平扫描频率”，是屏幕每秒钟从左至右扫描的次数; 场频(Vertical Scanning Frequency)也称为“垂直扫描频率”，是每秒钟整个屏幕刷新的次数。即：行频=场频*纵坐标分辨率。

当扫描完一个屏幕后，设备需要重新回到第一行以进入下一次的循环，此时有一段时间空隙，称为Vertical Blanking Interval(VBI)。这个时间点就是我们进行缓冲区交换的最佳时间。因为此时屏幕没有在刷新，也就避免了交换过程中出现screentearing的状况。VSync是Vertical Synchronization的简写，它利用VBI时期出现的vertical sync pulse来保证双缓冲在最佳时间点才进行交换。

在没有 VSync 信号同步下的绘制过程：
![没有VSYNC的绘图过程](/images/no_sync.png)

1. 时间从0开始，进入第一个16ms：Display显示第0帧，CPU处理完第一帧后，GPU紧接其后处理继续第一帧。三者互不干扰，一切正常。
2. 时间进入第二个16ms：因为早在上一个16ms时间内，第1帧已经由CPU，GPU处理完毕。故Display可以直接显示第1帧。显示没有问题。但在本16ms期间，CPU和GPU却并未及时去绘制第2帧数据（注意前面的空白区），而是在本周期快结束时，CPU/GPU才去处理第2帧数据。
3. 时间进入第3个16ms，此时Display应该显示第2帧数据，但由于CPU和GPU还没有处理完第2帧数据，故Display只能继续显示第一帧的数据，结果使得第1帧多画了一次（对应时间段上标注了一个Jank）。

> 通过上述分析可知，此处发生Jank的关键问题在于，为何第1个16ms段内，CPU/GPU没有及时处理第2帧数据？原因很简单，CPU可能是在忙别的事情（比如某个应用通过sleep固定时间来实现动画的逐帧显示），不知道该到处理UI绘制的时间了。可CPU一旦想起来要去处理第2帧数据，时间又错过了！

为解决这个问题，从Android 4.1Jelly Bean开始，Project Buffer引入了VSYNC，系统在收到VSync pulse后，将马上开始下一帧的渲染。结果如下图所示：
![引入VSYNC的绘制过程](/images/with_sync.png)

每收到VSYNC中断，CPU就开始处理各帧数据。大部分的Android显示设备刷新率是60Hz,这也就意味着每一帧最多只能有1/60=16ms左右的准备时间。假如CPU/GPU的FPS(FramesPer Second)高于这个值，那么显示效果将很好。但是，这时出现一个新问题：CPU和GPU处理数据的速度都能在16ms内完成，而且还有时间空余，但必须等到VSYNC信号到来后才处理下一帧数据，因此CPU/GPU的FPS被拉低到与Display的FPS相同。下图是采用双缓冲区的显示效果：
![双缓冲下CPU/GPU FPS大于刷新频率](/images/d_v_sync.png)

同时采用了双缓冲技术以及VSYNC，可以看到整个过程还是相当不错的，虽然CPU/GPU处理所用的时间时短时长，但总的来说都在16ms以内，因而不影响显示效果。A和B分别代表两个缓冲区，它们不断地交换来正确显示画面。如果CPU/GPU的FPS小于Display的FPS，会是什么情况呢？
![双缓冲下CPU/GPU FPS小于刷新频率](/images/l_d_vsync.png)

当CPU/GPU的处理时间超过16ms时，第一个VSync到来时，缓冲区B中的数据还没有准备好，于是只能继续显示之前A缓冲区中的内容。而B完成后，又因为缺乏VSync信号，CPU/GPU只能等待下一个VSync的来临才开处理下一帧数据。于是在这一过程中，有一大段时间是被浪费。当下一个VSync出现时，CPU/GPU马上执行操作，此时它可操作的buffer是A，相应的显示屏对应的就是B。这时看起来就是正常的。只不过由于执行时间仍然超过16ms，导致下一次应该执行的缓冲区交换又被推迟了。也就是说在第二个16ms时间段，Display本应显示B帧，但却因为GPU还在处理B帧，导致A帧被重复显示，同时CPU无所事事，因为A 被Display在使用。B被GPU在使用。为什么CPU不能在第二个16ms处即VSync到来就开始工作呢？原因就是只有两个Buffer。如果有第三个Buffer的存在，CPU就可以开始工作，而不至于空闲。出于这一思路就引出了Triple Buffer。结果如图所示：
![Triple Buffering](/images/t_vsync.png)

第二个16ms时间段，CPU使用C Buffer绘图。虽然刚开始还是会多显示A帧一次，但后续显示效果就比较好，第三个VSync信号到来时，由于GPU/CPU都处理完了B，因此B被显示，在第四个VSync信号到来时，GPU/CPU同时完成了A和C，并着手开始处理B，此时C被显示。从上图可以看出，CPU绘制的第C帧数据要到第四个16ms才能显示，这比双Buffer情况多了16ms延迟。我们知道，应用程序这边的本地窗口Surface在SurfaceFlinger服务进程端有一个对应的BufferQueue对象，该对象用于管理Surface的图形绘制缓冲区。BufferQueue中最多有32个BufferSlot，不过在实际使用时具体值是可以设置的。在Layer对象的onFirstRef函数中初始化了图形缓冲区的个数：
```C++
#ifdef TARGET_DISABLE_TRIPLE_BUFFERING
#warning "disabling triple buffering"
    mSurfaceTexture->setBufferCountServer(2);
#else
    mSurfaceTexture->setBufferCountServer(3);
#endif
```

# Project Buffer 分析

Project Buffer的三个关键点：
1. 需要VSYNC定时中断；
2. 当双Buffer不够使用时，该系统可分配第三块Buffer；
3. 图形buffer的绘制工作又VSYNC信号触发；

## 中断的产生
- HardwareComposer封装了相关的HAL层，如果硬件厂商提供的HAL层实现能定时产生VSYNC中断，则直接使用硬件的VSYNC中断，否则HardwareComposer内部会通过VSyncThread来模拟产生VSYNC中断（其实现很简单，就是sleep固定时间，然后唤醒）。
- 当VSYNC中断产生时（不管是硬件产生还是VSyncThread模拟的），VSyncHandler的onVSyncReceived函数将被调用。所以，对VSYNC中断来说，VSyncHandler的onVSyncReceived，就是其中断处理函数。

## 中断的接收与派发
VSyncHandler的实例是EventThread。EventThread本身运行在一个单独的线程中，并继承了VSyncHandler。EventThread在其线程函数threadLoop中等待下一次VSYNC的到来，并派发该中断事件给VSYNC监听者。通过EventThread，VSYNC中断事件可派发给多个该中断的监听者去处理。

## 中断的处理
- EventThread最重要的一个VSYNC监听者就是MessageQueue的mEvents对象，来自EventThread的VSYNC中断信号，将通过MessageQueue转化为一个REFRESH消息并传递给SurfaceFlinger的onMessageReceived函数处理。
- DisplayEventReceiver是一个abstract class，其JNI的代码部分会创建一个IDisplayEventConnection的VSYNC监听者对象。这样，来自EventThread的VSYNC中断信号就可以传递给Choreographer对象了。当Choreographer收到VSYNC信号时，就会调用使用者通过postCallback设置的回调函数。
![VSync信号分发过程](/images/d_vsync.png)
