---
title: SurfaceView与Vsync原理
toc: true
date: 2020-12-28 10:32:32
tags:
- android
categories:
- android
---
我们知道View是通过刷新来重绘视图，系统通过发出VSYNC信号来进行屏幕的重绘，刷新的时间间隔是16ms,如果我们可以在16ms以内将绘制工作完成，则没有任何问题，如果我们绘制过程逻辑很复杂，并且我们的界面更新还非常频繁，这时候就会造成界面的卡顿，影响用户体验，为此Android提供了SurfaceView来解决这一问题。
<!--more-->
# 介绍
## 优点
SurfaceView 拥有独立的绘图表面，即它不与其宿主窗口共享同一个绘图表面。由于拥有独立的绘图表面，因此SurfaceView的UI就可以在一个独立的线程中进行绘制。又由于不会占用主线程资源，SurfaceView 一方面可以实现复杂而高效的UI，另一方面又不会导致用户输入得不到及时响应。

## 一般绘制原理
我们知道普通的 Android 控件，例如 TextView、Button 等，它们都是将自己的UI绘制在宿主窗口的绘图表面之上，这意味着它们的UI是在应用程序的主线程中进行绘制的。

一般来说，每一个窗口在SurfaceFlinger服务中都对应有一个Layer，用来描述它的绘图表面。对于那些具有SurfaceView的窗口来说，每一个 SurfaceView 在 SurfaceFlinger 服务中还对应有一个独立的 Layer 或者 LayerBuffer ，用来单独描述它的绘图表面，以区别于它的宿主窗口的绘图表面。SurfaceFlinger 服务把所有的 LayerBuffer 和 Layer 都抽象为 LayerBase，因此就可以用统一的流程来绘制和合成它们的UI。
![SurfaceView 与 Activity 绘制](http://upload-images.jianshu.io/upload_images/16327616-f53ffe0c69416850.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

上图中 Activity 的 DecorView 及其中的两个 TextView 的UI就是绘制在 [SurfaceFlinger](https://www.jianshu.com/p/730dd558c269) 服务中的**同一个Layer**上面的，而 SurfaceView 的 UI 是绘制在 SurfaceFlinger 服务中的**另外一个 Layer 或者 LayerBuffer** 上的。
>注意，用来描述SurfaceView的Layer或者LayerBuffer的Z轴位置是小于用来其宿主Activity窗口的Layer的Z轴位置的，但是前者会在后者的上面挖一个“洞”出来，以便它的UI可以对用户可见。实际上，SurfaceView在其宿主Activity窗口上所挖的“洞”只不过是在其宿主Activity窗口上设置了一块透明区域。

![调用时序图](https://upload-images.jianshu.io/upload_images/16327616-0e141c2081ad969a.jpg)

## 用法
```java
public class SurfaceViewDemo extends SurfaceView implements SurfaceHolder.Callback, Runnable {
    public SurfaceViewTemplate(Context context) {
        this(context, null);
        //在三个参数的构造方法中完成初始化操作
       initView();
   }

    public SurfaceViewTemplate(Context context, AttributeSet attrs) {
        this(context, attrs, 0);
    }

    public SurfaceViewTemplate(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
    }

   private void initView(){
        mSurfaceHolder = getHolder();
        //注册回调方法
        mSurfaceHolder.addCallback(this);
        //设置一些参数方便后面绘图
        setFocusable(true);
        setKeepScreenOn(true);
        setFocusableInTouchMode(true);
   }

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
           //创建
          new Thread(this).start();
   }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
        //改变
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        //销毁
    }

    @Override
    public void run() {
        //子线程
    }
}
```

# 原理
![屏幕应用程序window组成](http://upload-images.jianshu.io/upload_images/16327616-4214f5d552b6e654.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
每个应用程序可能对应着一个或者多个图形界面，而每个界面我们就称之为一个surface ，或者说是window ，在上面的图中我们能看到4 个surface ，一个是home 界面，还有就是红、绿、蓝分别代表的3个surface ，而两个button 实际是home surface 里面的内容。我们需要考虑以下两种情况：
- 每个surface 在屏幕上有它的位置、大小，然后每个surface 里面还有要显示的内容
- 各个surface 之间可能有重叠

在实际中对这些Surface 进行merge 可以采用两种方式，一种就是采用软件的形式来merge ，还一种就是采用硬件的方式，软件的方式就是我们的SurfaceFlinger ，而硬件的方式就是Overlay 。

## Overlay(层叠)
因为硬件merge 内容相对简单，我们首先来看overlay 。
以IMX51 为例，当IPU 向内核申请FB 的时候它会申请3 个FB ，一个是主屏的，还一个是副屏的，还一个就是Overlay 的。 简单地来说，Overlay就是我们将硬件所能接受的格式数据和控制信息送到这个Overlay FrameBuffer，由硬件驱动来负责merge Overlay buffer和主屏buffer中的内容。

一般来说现在的硬件都只支持一个Overlay，主要用在视频播放以及camera preview上，因为视频内容的不断变化用硬件Merge比用软件Merge要有效率得多，下面就是使用Overlay和不使用Overlay的过程：
![对比图](http://upload-images.jianshu.io/upload_images/16327616-ebaa08beb860a44c.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
这两个的区别在于，有overlay的将Preview、Video data 发送给的是Overlay 层进行单独的处理和显示

## SurfaceFlinger
SurfaceFlinger 只是负责 merge Surface 的控制，比如说计算出两个 Surface 重叠的区域，至于 Surface 需要显示的内容，则通过 skia，opengl 和 pixflinger 来计算。

### 创建过程
![创建类图](http://upload-images.jianshu.io/upload_images/16327616-1fd1faa0c8c1584d.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
在IBinder 左边的就是客户端部分，也就是需要窗口显示的应用程序，而右边就是我们的 Surface  Flinger service 。 创建一个surface 分为两个过程，一个是在 SurfaceFlinger 这边为**每个应用程序(Client) 创建一个管理结构**，另一个就是创建**存储内容的buffer** ，以及在这个buffer 上的一系列画图之类的操作。

#### 创建Client
因为SurfaceFlinger 要管理多个应用程序的多个窗口界面，为了进行管理它提供了一个Client 类，每个来请求服务的应用程序就对应了一个 Client 。因为 surface 是在 SurfaceFlinger 创建的，必须返回一个结构让应用程序知道自己申请的 surface 信息，因此 SurfaceFlinger 将 Client 创建的控制结构per_client_cblk_t 经过 BClient 的封装以后返回给 SurfaceComposerClient ，并向应用程序提供了一组创建和销毁 surface 的接口：
![Client、BClient 与 SurfaceFlinger](http://upload-images.jianshu.io/upload_images/16327616-eac1e392ef24da6f.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
Flinger 为每个 Client 提供了 8M 的空间，包括控制信息和存储内容的 buffer 。
为应用程序创建一个 Client 以后，下面需要做的就是为这个 Client 分配 Surface ， 可以理解为创建一个 Surface 就是创建一个 Layer 。

#### 创建 Layer
创建 Layer 的过程，首先是由这个应用程序的 Client 根据应用程序的 pid 生成一个唯一的 layer ID ，然后根据大小、位置、格式等信息创建出 Layer 。在 Layer 里面有一个嵌套的 Surface 类，它主要包含一个 ISurfaceFlingerClient::Surface_data_t ，包含了这个 Surface 的统一标识符以及 buffer 信息等，提供给应用程序使用。最后应用程序会根据返回来的 ISurface 创建一个自己的 Surface 。
![Layer 创建过程](http://upload-images.jianshu.io/upload_images/16327616-c5dd1f37b7ff92b4.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
Android 提供了 4 种类型的 layer 供选择： Layer ， LayerBlur ， LayerBuffer ， LayerDim ，每个 layer 对应一种类型的窗口，并对应这种窗口相应的操作
    - Normal Layer
       它是 Android 种**使用最多**的一种 Layer ，一般的应用程序在创建 surface 的时候都是采用的这样的 layer ， Normal Layer 为每个 Surface 分配两个 buffer ： front buffer 和 back buffer ， Front buffer 用于 SurfaceFlinger 进行显示，而 Back buffer 用于应用程序进行画图，当 Back buffer 填满数据 (dirty) 以后，就会 flip ， back buffer 就变成了 front buffer 用于显示，而 front buffer 就变成了 back buffer 用来画图。
    - LayerBuffer
        **最复杂**的一个 layer，它不具备 render buffer ，主要用在 camera preview / video playback 上。它提供了两种实现方式，一种就是 post buffer ，另外一种就是我们前面提到的 overlay ， Overlay 的接口实际上就是在这个 layer 上实现的。不管是 overlay 还是 post buffer 都是指这个 layer 的数据来源自其他地方，只是 post buffer 是通过软件的方式最后还是将这个 layer merge 主的 FB ，而 overlay 则是通过硬件 merge 的方式来实现。与这个 layer 紧密联系在一起的是 ISurface 这个接口，通过它来注册数据来源。用法如下：
```C++
// 要使用 Surfaceflinger 的服务必须先创建一个 client
sp<SurfaceComposerClient> client = new SurfaceComposerClient();

// 然后向 Surfaceflinger 申请一个 Surface ， surface 类型为 PushBuffers
sp<Surface> surface = client->createSurface(getpid(), 0, 320, 240,
            PIXEL_FORMAT_UNKNOWN, ISurfaceComposer::ePushBuffers);

// 然后取得 ISurface 这个接口， getISurface() 这个函数的调用时具有权限限制的，
// 必须在Surface.h 中打开： /framewoks/base/include/ui/Surface.h
sp<ISurface> isurface = Test::getISurface(surface);

//overlay 方式下就创建 overlay ，然后就可以使用 overlay 的接口了
sp<OverlayRef> ref = isurface->createOverlay(320, 240, PIXEL_FORMAT_RGB_565);
sp<Overlay> verlay = new Overlay(ref);

//post buffer 方式下，首先要创建一个 buffer ，然后将 buffer 注册到 ISurface 上
ISurface::BufferHeap buffers(w, h, w, h,
                                          PIXEL_FORMAT_YCbCr_420_SP,
                                         transform,
                                         0,
                                         mHardware->getPreviewHeap());
mSurface->registerBuffers(buffers);
```

#### 应用程序对窗口的控制以及画图
首先了解一下 SurfaceFlinger 这个服务的运作方式：
>SurfaceFlinger 是一个线程类，它继承了 Thread 类。当创建 SurfaceFlinger 这个服务的时候会启动一个 SurfaceFlinger 监听线程，这个线程会一直等待事件的发生，比如说需要进行 sruface flip ，或者说窗口位置大小发生了变化等，一旦产生这些事件，SurfaceComposerClient 就会通过 IBinder 发出信号，这个线程就会结束等待处理这些事件，处理完成以后会继续等待，如此循环。
SurfaceComposerClient 和 SurfaceFlinger 是通过 SurfaceFlingerSynchro 这个类来同步信号的，其实说穿了就是一个条件变量。监听线程等待条件的值一旦变成 OPEN 就结束等待并将条件置成 CLOSE 然后进行事件处理，处理完成以后再继续等待条件的值变成 OPEN ，而 Client 的Surface 一旦改变就通过 IBinder 通知 SurfaceFlinger 将条件变量的值变成 OPEN ，并唤醒等待的线程，这样就通过线程类和条件变量实现了一个动态处理机制。

- lockSurface
在对 Surface 进行画图之前必须**锁定 Surface 的 layer** ，实际上就是锁定了 Layer_cblk_t 里的 swapstate 这个变量。SurfaceComposerClient 通过调用 lockSurface() 来锁定  swapsate 的值来确定要使用哪个 buffer 画图，如果 swapstate 是下面的值就会阻塞 Client ，
| value | usages |
| ------ | ------ |
| eNextFlipPending |  we've used both buffers already, so we need to  wait for one to become availlable. |
| eResizeRequested | the buffer we're going to acquire is being resized. Block until it is done. |
| eFlipRequested && eBusy: | he buffer we're going to acquire is currently in use by the server. |
| eInvalidSurface |  this is a special case, we don't block in this case, we just return an error. |

- unlockSurfaceAndPost
调用 unlockSurfaceAndPost() 来通知 SurfaceFlinger 进行Flip。或者仅仅调用 unlockSurface() 而不通知 SurfaceFlinger 。

一般来说画图的过程需要重绘 Surface 上的所有像素，因为一般情况下显示过后的像素是不做保存的，不过也可以通过设定来保存一些像素，而只绘制部分像素，这里就涉及到像素的拷贝了，需要将Front buffer 的内容拷贝到 Back buffer 。
在 SurfaceFlinger 服务实现中像素的拷贝是经常需要进行的操作，而且还可能涉及拷贝过程的转换，比如说屏幕的旋转，翻转等一系列操作。因此 Android 提供了拷贝像素的 hal ，这个也可能是我们将来需要实现的，因为用硬件完成像素的拷贝，以及拷贝过程中可能的矩阵变换等操作，比用 memcpy 要有效率而且节省资源。这个 HAL 头文件在：[/hardware/libhardware/hardware/include/copybit.h]()

#### SurfaceFlinger 的处理
窗口状态变化的处理是一个很复杂的过程，SurfaceFlinger 只是执行 Windows Manager 的指令，由 Windows manager 来决定什么是偶改变大小、位置、透明度、以及如何调整layer 之间的顺序， SurfaceFlinger 仅仅只是执行它的指令。
![监听的处理过程](http://upload-images.jianshu.io/upload_images/16327616-3cd7df3b69ffc1c1.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
前面已经说过了SurfaceFlinger 这个服务在创建的时候会启动一个监听的线程，这个线程负责每次窗口更新时候的处理。
Android 组合各个窗口的原理:
**Android 实际上是通过计算每一个窗口的可见区域，就是我们在屏幕上可见的窗口区域 ( 用 Android 的词汇来说就是 visibleRegionScreen ) ，然后将各个窗口的可见区域画到一个主 layer 的相应部分，最后就拼接成了一个完整的屏幕，然后将主 layer 输送到 FB 显示。在将各个窗口可见区域画到主 layer 过程中涉及到一个硬件实现和一个软件实现的问题，如果是软件实现则通过 Opengl 重新画图，其中还包括存在透明度的 alpha 计算；如果实现了 copybit hal 的话，可以直接将窗口的这部分数据直接拷贝过来，并完成可能的旋转，翻转，以及 alhpa计算等。**

1. handleConsoleEvent
当接收到 signal 或者 singalEvent 事件以后，线程就停止等待开始对 Client 的请求进行处理，第一个步骤是 handleConsoleEvent ，它会取得屏幕或者释放屏幕，只有**取得屏幕**的时候才能够在屏幕上画图。
2. handleTransaction
因为**窗口状态的改变**只能在一个 Transaction 中进行。而窗口状态的改变可能造成本窗口和其他窗口的可见区域变化，所以就必须重新来计算窗口的可见区域。在这个处理子过程中 Android会根据标志位来对所有 layer 进行遍历，一旦发现哪个窗口的状态发生了变化就设置标志位以在将来重新计算这个窗口的可见区域。在完成所有子 layer 的遍历以后， Android 还会根据标志位来处理主layer ，举个例子，比如说传感器感应到手机横过来了，会将窗口横向显示，此时就要重新设置主 layer 的方向。
3. handlePageFlip
处理**每个窗口 surface buffer 之间的翻转**，根据 layer_state_t 的 swapsate 来决定是否要翻转，当 swapsate 的值是 eNextFlipPending 是就会翻转。处理完翻转以后它会重新计算每个 layer的可见区域。
4. handleRepaint
计算出每个 layer 的可见区域以后，这一步就是将所有可见区域的内容**画到主 layer 的相应部分**了，也就是说将各个 surface buffer 里面相应的内容拷贝到主 layer 相应的 buffer ，其中可能还涉及到alpha 运算，像素的翻转，旋转等等操作，这里就像我前面说的可以用硬件来实现也可以用软件来实现。在使用软件的 opengl 做计算的过程中还会用到 PixFlinger 来做像素的合成，
5. postFrameBuffer
翻转主 layer 的两个 buffer ，将刚刚写入的内容**放入 FB 内显示**了。

### 共享内存
普通的Android控件，例如TextView、Button和CheckBox等，它们都是将自己的UI绘制在宿主窗口的绘图表面之上，这意味着它们的UI是在应用程序的主线程中进行绘制的。由于应用程序的主线程除了要绘制UI之外，还需要及时地响应用户输入，否则系统就会认为应用程序没有响应了。而对于一些游戏画面，或者摄像头预览、视频播放来说，它们的UI都比较复杂，而且要求能够进行高效的绘制。这时候就必须要给那些需要复杂而高效UI的视图生成一个独立的绘图表面，以及使用一个独立的线程来绘制这些视图的UI。

SurfaceFlinger服务运行在Android系统的System进程中，它负责管理Android系统的帧缓冲区（Frame Buffer）。Android应用程序为了能够将自己的UI绘制在系统的帧缓冲区上，它们就必须要与SurfaceFlinger服务进行通信。

在APP端执行draw的时候，数据很明显是要绘制到APP的进程空间，但是视图窗口要经过SurfaceFlinger图层混排才会生成最终的帧，而SurfaceFlinger又运行在另一个独立的服务进程，那么View视图的数据是如何在两个进程间传递的呢，普通的Binder通信肯定不行，因为Binder不太适合这种数据量较大的通信，那么View数据的通信采用的是什么IPC手段呢？答案就是**共享内存**，更精确的说是匿名共享内存。共享内存是Linux自带的一种IPC机制，Android直接使用了该模型，不过做出了自己的改进，进而形成了Android的匿名共享内存（Anonymous Shared Memory-Ashmem）。通过Ashmem，APP进程同SurfaceFlinger共用一块内存，如此，就不需要进行数据拷贝，APP端绘制完毕，通知SurfaceFlinger端合成，再输出到硬件进行显示即可。
![View绘制与共享内存](http://upload-images.jianshu.io/upload_images/16327616-abac9840b56cef02?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

在每一个Android应用程序与SurfaceFlinger服务之间的连接上加上一块用来传递UI元数据的匿名共享内存，这个共享内存就是 SharedClient
![shareClient.jpg](https://upload-images.jianshu.io/upload_images/16327616-6d3fdf5f2916b07d.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

在每一个SharedClient里面，有至多31个SharedBufferStack。SharedBufferStack就是Android应用程序和SurfaceFlinger 的缓冲区堆栈。用来缓冲 UI 元数据。
一般我们就绘制UI的时候，都会采用一种称为“双缓冲”的技术。双缓冲意味着要使用两个缓冲区，其中一个称为Front Buffer，另外一个称为Back Buffer。
UI总是先在Back Buffer中绘制，然后再和Front Buffer交换，渲染到显示设备中。这下就可以理解SharedBufferStack的含义了吧？SurfaceFlinger服务只不过是将传统的“双缓冲”技术升华和抽象为了一个SharedBufferStack。可别小看了这个升华和抽象，有了SharedBufferStack之后，SurfaceFlinger 服务就可以使用N个缓冲区技术来绘制UI了。N值的取值范围为2到16。例如，在Android 2.3中，N的值等于2，而在Android 4.1中，据说就等于3了。

在SurfaceFlinger服务中，每一个SharedBufferStack都对应一个Surface，即一个窗口。这样，我们就可以知道为什么每一个SharedClient里面包含的是一系列SharedBufferStack而不是单个SharedBufferStack：**一个SharedClient对应一个Android应用程序，而一个Android应用程序可能包含有多个窗口**，即Surface。从这里也可以看出，一个Android应用程序至多可以包含31个Surface。
![SharedBufferStack](http://upload-images.jianshu.io/upload_images/16327616-8dd2fa114cd2fe60.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
我们假设图中的SharedBufferStack有5个Buffer，其中，Buffer-1和Buffer-2是已经使用了的，而Buffer-3、Buffer-4和Buffer-5是空闲的。指针head和tail分别指向空闲缓冲区列表的头部和尾部，而指针queue_head指向已经使用了的缓冲区列表的头部。从这里就可以看出，从指针tail到head之间的Buffer即为空闲缓冲区表，而从指针head到queue_head之间的Buffer即为已经使用了的缓冲区列表。注意，图中的5个Buffer是循环使用的。

SharedBufferStack中的**缓冲区只是用来描述UI元数据的**，这意味着它们不包含真正的UI数据。**真正的UI数据保存在GraphicBuffer中**，后面我们再描述GaphicBuffer。因此，为了完整地描述一个UI，SharedBufferStack中的每一个已经使用了的缓冲区都对应有一个GraphicBuffer，用来描述真正的UI数据。当SurfaceFlinger服务缓制Buffer-1和Buffer-2的时候，就会找到与它们所对应的GraphicBuffer，这样就可以将对应的UI绘制出来了。

当Android应用程序需要**更新一个Surface**的时候，它就会找到与它所对应的SharedBufferStack，并且从它的空闲缓冲区列表的尾部取出一个空闲的Buffer。我们假设这个取出来的空闲Buffer的编号为index。接下来Android应用程序就请求SurfaceFlinger服务为这个编号为index的**Buffer分配一个图形缓冲区GraphicBuffer**。

SurfaceFlinger 服务分配好图形缓冲区 GraphicBuffer 之后，会将它的编号设置为 index，然后再将这个图形缓冲区 GraphicBuffer 返回给 Android 应用程序访问。Android应用程序得到了 SurfaceFlinger 服务返回的图形缓冲区 GraphicBuffer 之后，就在里面**写入UI数据**。写完之后，就将与它所对应的缓冲区，即编号为 index 的 Buffer，插入到对应的 SharedBufferStack 的已经使用了的**缓冲区列表的头部**去。这一步完成了之后，Android 应用程序就通知 SurfaceFlinger 服务去绘制那些保存在已经使用了的缓冲区所描述的图形缓冲区GraphicBuffer了。用上面例子来说，SurfaceFlinger服务需要绘制的是编号为1和2的Buffer所对应的图形缓冲区GraphicBuffer。由于SurfaceFlinger服务知道编号为1和2的 Buffer 所对应的图形缓冲区 GraphicBuffer 在哪里，因此，Android 应用程序只需要告诉 SurfaceFlinger 服务要绘制的 Buffer 的编号就OK了。**当一个已经被使用了的Buffer被绘制了之后，它就重新变成一个空闲的 Buffer 了**。

SharedBufferStack 是在 Android 应用程序和 SurfaceFlinger 服务之间共享的，但是，Android 应用程序和 SurfaceFlinger 服务使用 SharedBufferStack 的方式是不一样的，具体来说，就是 **Android 应用程序关心的是它里面的空闲缓冲区列表，而 SurfaceFlinger 服务关心的是它里面的已经使用了的缓冲区列表。**从SurfaceFlinger服务的角度来看，保存在 SharedBufferStack中 的已经使用了的缓冲区其实就是在排队等待渲染。

为了方便 SharedBufferStack 在 Android 应用程序和 SurfaceFlinger 服务中的访问，Android 系统分别使用 SharedBufferClient 和 SharedBufferServer 来描述 SharedBufferStack ，其中，SharedBufferClient 用来在Android 应用程序这一侧访问 SharedBufferStack 的空闲缓冲区列表，而 SharedBufferServer 用来在SurfaceFlinger 服务这一侧访问 SharedBufferStack 的排队缓冲区列表。
![SharedBufferClient眼中的SharedBufferStack ](http://upload-images.jianshu.io/upload_images/16327616-d5ee8b65c1b9e71d.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 只要 SharedBufferStack 中的 available 的 buffer 的数量大于0， SharedBufferClient 就会将指针 tail 往前移一步，并且减少 available 的值，以便可以获得一个空闲的 Buffer。当 Android 应用程序往这个空闲的 Buffer 写入好数据之后，它就会通过 SharedBufferClient 来将它添加到 SharedBufferStack 中的排队缓冲区列表的尾部去，即指针 queue_head 的下一个位置上。
![SharedBufferServer眼中的SharedBufferStack.jpg](https://upload-images.jianshu.io/upload_images/16327616-0f5d5d4438015d59.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

 当 Android 应用程序通知 SurfaceFlinger 服务更新UI的时候，只要对应的 SharedBufferStack 中的 queued 的缓冲区的数量大于0，SharedBufferServer 就会将指针 head 的下一个Buffer绘制出来，并且将指针 head 向前移一步，以及将 queued 的值减1。

我们之前多次提到了图形缓冲区 GraphicBuffer ，它是什么东东呢？我们看图
![GraphicBuffer](https://img-my.csdn.net/uploads/201208/11/1344643974_9844.jpg)
每一个GraphicBuffer内部都包含有一块用来保存UI数据的缓冲区，这块缓冲区使用一个buffer_handle_t对象来描述。看到buffer_handle_t，是不是有点眼熟？在前面Android帧缓冲区（Frame Buffer）硬件抽象层（HAL）模块Gralloc的实现原理分析一文中，我们说过，**由HAL层的Gralloc模块分配的图形缓冲区的是使用一个buffer_handle_t对象来描述的**，而由buffer_handle_t对象所描述的图形缓冲区要么是在系统帧缓冲区（Frame Buffer）或者匿名共享内存（Anonymous Shared Memory）中分配的。这样，我们就可以将SurfaceFlinger服务与HAL层中的Gralloc模块关联起来了。

# Vsync(垂直同步信号)
假设显示内容和绘制使用的是用一块内存，那可能会出现下面的问题。显示有截断的异常，因为cpu/gpu 处理和屏幕展示的速度不一样但是却使用的是同一块内存。
怎么解决呢？
可以将cpu/gpu 处理和屏幕展示分开，cpu/gpu 在后台处理，处理完一帧的数据以后才交给屏幕展示(这样可能导致另外的问题是，如果cpu/gpu 处理很慢，那么屏幕可能会一直展示某一帧的数据)。

绘制过程中的两个概念。
- 手机屏幕刷新率：手机硬件每秒刷新屏幕的次数，单位HZ。一般是一个固定值，例如60HZ。
- FPS：画面每秒传输帧数，通俗来讲就是指动画或视频的画面数。单位HZ。
手机屏幕刷新率是固定的，FPS 则是一直变化的，怎么才能保证能够运行流畅呢？从几个例子来看吧。

## 无VSync机制
![](https://coolegos.github.io/img/vsync_1.png)
先解释图片代表的意思：最下面黑线代表的是时间，黄色代表屏幕展示，绿色代表GPU 处理，蓝色代表CPU 处理。Jank 代表的是重复展示上一帧的异常。下面会从屏幕展示的每一帧开始分析

没有引入VSync 机制的处理流程如下：
1. Display 展示第0帧数据，这时cpu/gpu 会去处理第1帧的数据。
2. Display 展示第1帧数据(此时屏幕显示是正常的)，这时cpu/gpu 可能处理其他任务导致很晚才去处理绘制。
3. 因为cpu/gpu 没处理好第2帧的数据，所以Display 还是展示第1帧数据(此时屏幕显示是异常的)，cpu/gpu 处理完第2帧没有处理完的数据然后继续处理第3帧的数据

上图中一个很明显的问题是，只要一次cpu/gpu 处理出现异常就可能导致后面的一系列的处理出现异常。

## 引入VSync 机制
VSync 可以简单的认为是一种定时中断，系统在每次需要绘制的时候都会发送VSync Pulse 信号，cpu/gpu 收到信号后马上处理绘制。
### 正常情况下
![](https://coolegos.github.io/img/vsync_2.png)

### Double Buffering 异常情况
![](https://coolegos.github.io/img/vsync_3.png)
VSync 机制下Double Buffering 时FPS > 手机屏幕刷新率的情况。
1. Display 展示第A 帧数据，cpu/gpu 收到VSync Pulse 信号马上处理B 帧的数据，但是由于计算太多，导致没有在一个VSync 间隔内处理完。
2. 由于第B 帧数据没有处理好，Display 继续展示第A 帧数据(此时屏幕显示是异常的)。由于系统中只存在一块内存给cpu/gpu 处理绘制，所以在这个VSync 间隔内cpu 不处理任何事。
3. Display 展示第B 帧数据，cpu/gpu 收到VSync Pulse 信号马上处理即将展示A 帧的数据，由于计算太多，导致没有在一个VSync 间隔内处理完。
4. 需要展示的A 帧数据没有处理好，Display 继续展示第B 帧数据(此时屏幕显示是异常的)。由于系统中只存在一块内存给cpu/gpu 处理绘制，所以在这个VSync 间隔内cpu 不处理任何事。
上图中一个很明显的问题是，只要出现一次Jank 就会影响下一次的VSync(cpu 不能工作)

### Triple Buffering 异常情况
![](https://coolegos.github.io/img/vsync_4.png)
1. Display 展示第A 帧数据，cpu/gpu 收到VSync Pulse 信号马上处理B 帧的数据，但是由于计算太多，导致没有在一个VSync 间隔内处理完。
2. 由于第B 帧数据没有准备好，Display 继续展示第A 帧数据(此时屏幕显示是异常的)。此时虽然B 被gpu 在使用，但是cpu 可以处理Buffer C(因为有3个缓冲)。
3. Display 展示第B 帧数据，gpu 继续处理上一步骤的C，cpu 则处理A。
4. 后续过程出错的情况被降低了…

## Choreographer
Google在Android 4.1系统中对Android Display系统进行了优化：在收到VSync pulse后，将马上开始下一帧的渲染。即一旦收到VSync通知，CPU和GPU就立刻开始计算然后把数据写入buffer。通过“drawing with VSync” 的实现——Choreographer

Activity启动 走完onResume方法后，会进行window的添加。window添加过程会 调用ViewRootImpl的setView()方法，setView()方法会调用requestLayout()方法来请求绘制布局，requestLayout()方法内部又会走到scheduleTraversals()方法，最后会走到performTraversals()方法，接着到了我们熟知的测量、布局、绘制三大流程了。

当我们使用 ValueAnimator.start()、View.invalidate()时，最后也是走到ViewRootImpl的scheduleTraversals()方法。（View.invalidate()内部会循环获取ViewParent直到ViewRootImpl的 invalidateChildInParent() 方法，然后走到scheduleTraversals()，所有UI的变化都是走到ViewRootImpl的 scheduleTraversals()方法。
现在我们来Trace一下 scheduleTraversals
```java
//ViewRootImpl.java
void scheduleTraversals() {
    if (!mTraversalScheduled) {
        //此字段保证同时间多次更改只会刷新一次，例如TextView连续两次setText(),也只会走一次绘制流程
        mTraversalScheduled = true;
        //添加同步屏障，屏蔽同步消息，保证VSync到来立即执行绘制
        mTraversalBarrier = mHandler.getLooper().getQueue().postSyncBarrier();
        //mTraversalRunnable是TraversalRunnable实例，最终走到run()，也即doTraversal();
        mChoreographer.postCallback(
                Choreographer.CALLBACK_TRAVERSAL, mTraversalRunnable, null);
        if (!mUnbufferedInputDispatch) {
            scheduleConsumeBatchedInput();
        }
        notifyRendererOfFramePending();
        pokeDrawLockIfNeeded();
    }
}

final class TraversalRunnable implements Runnable {
    @Override
    public void run() {
        doTraversal();
    }
}
final TraversalRunnable mTraversalRunnable = new TraversalRunnable();

void doTraversal() {
    if (mTraversalScheduled) {
        mTraversalScheduled = false;
        //移除同步屏障
        mHandler.getLooper().getQueue().removeSyncBarrier(mTraversalBarrier);

        if (mProfile) {
            Debug.startMethodTracing("ViewAncestor");
        }

        //开始三大绘制流程
        performTraversals();

        if (mProfile) {
            Debug.stopMethodTracing();
            mProfile = false;
        }
    }
}
```
主要有以下逻辑：
1. 首先使用mTraversalScheduled字段保证同时间多次更改只会刷新一次，例如TextView连续两次setText()，也只会走一次绘制流程。
2. 然后把当前线程的消息队列Queue添加了同步屏障，这样就屏蔽了正常的同步消息，保证VSync到来后立即执行绘制，而不是要等前面的同步消息。后面会具体分析同步屏障和异步消息的代码逻辑。
3. 调用了mChoreographer.postCallback()方法，发送一个会在下一帧执行的回调，即在下一个VSync到来时会执行TraversalRunnable–>doTraversal()—>performTraversals()–>绘制流程。

接下来，就是分析的重点——Choreographer

### 实例创建
```java
//ViewRootImpl实例是在添加window时创建
public ViewRootImpl(Context context, Display display) {
	...
	mChoreographer = Choreographer.getInstance();
	...
}
```
```java
//Choreographer.java
public static Choreographer getInstance() {
    return sThreadInstance.get();
}

private static final ThreadLocal<Choreographer> sThreadInstance =
        new ThreadLocal<Choreographer>() {
    @Override
    protected Choreographer initialValue() {
        Looper looper = Looper.myLooper();
        if (looper == null) {
        	  //当前线程要有looper，Choreographer实例需要传入
            throw new IllegalStateException("The current thread must have a looper!");
        }
        Choreographer choreographer = new Choreographer(looper, VSYNC_SOURCE_APP);
        if (looper == Looper.getMainLooper()) {
            mMainInstance = choreographer;
        }
        return choreographer;
    }
};

private Choreographer(Looper looper, int vsyncSource) {
    mLooper = looper;
    //使用当前线程looper创建 mHandler
    mHandler = new FrameHandler(looper);
    //USE_VSYNC 4.1以上默认是true，表示 具备接受VSync的能力，这个接受能力就是FrameDisplayEventReceiver
    mDisplayEventReceiver = USE_VSYNC
            ? new FrameDisplayEventReceiver(looper, vsyncSource)
            : null;
    mLastFrameTimeNanos = Long.MIN_VALUE;

    // 计算一帧的时间，Android手机屏幕是60Hz的刷新频率，就是16ms
    mFrameIntervalNanos = (long)(1000000000 / getRefreshRate());

    // 创建一个链表类型CallbackQueue的数组，大小为5，
    //也就是数组中有五个链表，每个链表存相同类型的任务：输入、动画、遍历绘制等任务（CALLBACK_INPUT、CALLBACK_ANIMATION、CALLBACK_TRAVERSAL）
    mCallbackQueues = new CallbackQueue[CALLBACK_LAST + 1];
    for (int i = 0; i <= CALLBACK_LAST; i++) {
        mCallbackQueues[i] = new CallbackQueue();
    }
    // b/68769804: For low FPS experiments.
    setFPSDivisor(SystemProperties.getInt(ThreadedRenderer.DEBUG_FPS_DIVISOR, 1));
}
```
### 安排任务 mChoreographer.postCallback
在scheduleTraversals()的时候会 postCallback，postCallback()内部调用postCallbackDelayed()，接着又调用postCallbackDelayedInternal()，
```java
private void postCallbackDelayedInternal(int callbackType,
        Object action, Object token, long delayMillis) {
...
    synchronized (mLock) {
    	  // 当前时间
        final long now = SystemClock.uptimeMillis();
        // 加上延迟时间
        final long dueTime = now + delayMillis;
        //取对应类型的CallbackQueue添加任务
        mCallbackQueues[callbackType].addCallbackLocked(dueTime, action, token);

        if (dueTime <= now) {
        	  //立即执行
            scheduleFrameLocked(now);
        } else {
        	  //延迟运行，最终也会走到scheduleFrameLocked()
            Message msg = mHandler.obtainMessage(MSG_DO_SCHEDULE_CALLBACK, action);
            msg.arg1 = callbackType;
            msg.setAsynchronous(true);
            mHandler.sendMessageAtTime(msg, dueTime);
        }
    }
}

private final class FrameHandler extends Handler {
       public FrameHandler(Looper looper) {
           super(looper);
       }
       @Override
       public void handleMessage(Message msg) {
           switch (msg.what) {
               case MSG_DO_FRAME:
                   // 执行doFrame,即绘制过程
                   doFrame(System.nanoTime(), 0);
                   break;
               case MSG_DO_SCHEDULE_VSYNC:
                   //申请VSYNC信号，例如当前需要绘制任务时
                   doScheduleVsync();
                   break;
               case MSG_DO_SCHEDULE_CALLBACK:
                   //需要延迟的任务，最终还是执行上述两个事件
                   doScheduleCallback(msg.arg1);
                   break;
           }
       }
   }

   private void scheduleFrameLocked(long now) {
       if (!mFrameScheduled) {
           mFrameScheduled = true;
           //开启了VSYNC
           if (USE_VSYNC) {
               if (DEBUG_FRAMES) {
                   Log.d(TAG, "Scheduling next frame on vsync.");
               }

               //当前执行的线程，是否是mLooper所在线程
               if (isRunningOnLooperThreadLocked()) {
                 //申请 VSYNC 信号
                   scheduleVsyncLocked();
               } else {
                 // 若不在，就用mHandler发送消息到原线程，最后还是调用scheduleVsyncLocked方法
                   Message msg = mHandler.obtainMessage(MSG_DO_SCHEDULE_VSYNC);
                   msg.setAsynchronous(true);//异步
                   mHandler.sendMessageAtFrontOfQueue(msg);
               }
           } else {
             // 如果未开启VSYNC则直接doFrame方法（4.1后默认开启）
               final long nextFrameTime = Math.max(
                       mLastFrameTimeNanos / TimeUtils.NANOS_PER_MS + sFrameDelay, now);
               if (DEBUG_FRAMES) {
                   Log.d(TAG, "Scheduling next frame in " + (nextFrameTime - now) + " ms.");
               }
               Message msg = mHandler.obtainMessage(MSG_DO_FRAME);
               msg.setAsynchronous(true);//异步
               mHandler.sendMessageAtTime(msg, nextFrameTime);
           }
       }
   }
```
1. 如果系统未开启 VSYNC 机制，此时直接发送 MSG_DO_FRAME 消息到 FrameHandler。注意查看上面贴出的 FrameHandler 代码，此时直接执行 doFrame 方法。
2. Android 4.1 之后系统默认开启 VSYNC，在 Choreographer 的构造方法会创建一个 FrameDisplayEventReceiver，scheduleVsyncLocked 方法将会通过它申请 VSYNC 信号。
3. isRunningOnLooperThreadLocked 方法，其内部根据 Looper 判断是否在原线程，否则发送消息到 FrameHandler。最终还是会调用 scheduleVsyncLocked 方法申请 VSYNC 信号。
所以，FrameHandler的作用：**发送异步消息（因为前面设置了同步屏障）。有延迟的任务发延迟消息、不在原线程的发到原线程、没开启VSYNC的直接走 doFrame 方法取执行绘制。**

### 申请和接收VSync信号
VSYNC 信号是通过 scheduleVsyncLocked 方法申请的
```java
private void scheduleVsyncLocked() {
    // mDisplayEventReceiver是Choreographer构造方法中创建，是FrameDisplayEventReceiver 的实例
    mDisplayEventReceiver.scheduleVsync();
}
```
```java
public void scheduleVsync() {
        if (mReceiverPtr == 0) {
            Log.w(TAG, "Attempted to schedule a vertical sync pulse but the display event "
                    + "receiver has already been disposed.");
        } else {
        	// 申请VSYNC中断信号，会回调onVsync方法
            nativeScheduleVsync(mReceiverPtr);
        }
    }
```
在 DisplayEventReceiver 的构造方法会通过 JNI 创建一个 IDisplayEventConnection 的 VSYNC 的监听者
VSYNC信号的接收回调是onVsync()，我们直接看onVsync()：
```java
// FrameDisplayEventReceiver.java
private final class FrameDisplayEventReceiver extends DisplayEventReceiver
        implements Runnable {
    private boolean mHavePendingVsync;
    private long mTimestampNanos;
    private int mFrame;

    public FrameDisplayEventReceiver(Looper looper, int vsyncSource) {
        super(looper, vsyncSource);
    }

    @Override
    public void onVsync(long timestampNanos, long physicalDisplayId, int frame) {
        // Post the vsync event to the Handler.
        // The idea is to prevent incoming vsync events from completely starving
        // the message queue.  If there are no messages in the queue with timestamps
        // earlier than the frame time, then the vsync event will be processed immediately.
        // Otherwise, messages that predate the vsync event will be handled first.
        long now = System.nanoTime();
        if (timestampNanos > now) {
            Log.w(TAG, "Frame time is " + ((timestampNanos - now) * 0.000001f)
                    + " ms in the future!  Check that graphics HAL is generating vsync "
                    + "timestamps using the correct timebase.");
            timestampNanos = now;
        }

        if (mHavePendingVsync) {
            Log.w(TAG, "Already have a pending vsync event.  There should only be "
                    + "one at a time.");
        } else {
            mHavePendingVsync = true;
        }

        mTimestampNanos = timestampNanos;
        mFrame = frame;
        //将本身作为runnable传入msg， 发消息后 会走run()，即doFrame()，也是异步消息
        Message msg = Message.obtain(mHandler, this);
        msg.setAsynchronous(true);
        mHandler.sendMessageAtTime(msg, timestampNanos / TimeUtils.NANOS_PER_MS);
    }

    @Override
    public void run() {
        mHavePendingVsync = false;
        doFrame(mTimestampNanos, mFrame);
    }
}
```
onVsync()中，将Receiver本身作为runnable参数传入异步消息msg中，并使用mHandler发送msg，最终执行的就是doFrame()方法了。

注意一点是，**onVsync()方法中只是使用mHandler发送消息到MessageQueue中，不一定是立刻执行，如何MessageQueue中前面有较为耗时的操作，那么就要等完成，才会执行本次的doFrame()。**

### doFrame
申请VSync信号接收到后走的是 doFrame()方法
```java
void doFrame(long frameTimeNanos, int frame) {
    final long startNanos;
    synchronized (mLock) {
        if (!mFrameScheduled) {
            return; // no work to do
        }

        ...
  // 预期执行时间
        long intendedFrameTimeNanos = frameTimeNanos;
        startNanos = System.nanoTime();
        // 超时时间是否超过一帧的时间（这是因为MessageQueue虽然添加了同步屏障，但是还是有正在执行的同步任务，导致doFrame延迟执行了）
        final long jitterNanos = startNanos - frameTimeNanos;
        if (jitterNanos >= mFrameIntervalNanos) {
          // 计算掉帧数
            final long skippedFrames = jitterNanos / mFrameIntervalNanos;
            if (skippedFrames >= SKIPPED_FRAME_WARNING_LIMIT) {
              // 掉帧超过30帧打印Log提示
                Log.i(TAG, "Skipped " + skippedFrames + " frames!  "
                        + "The application may be doing too much work on its main thread.");
            }
            final long lastFrameOffset = jitterNanos % mFrameIntervalNanos;
            ...
            frameTimeNanos = startNanos - lastFrameOffset;
        }

        ...

        mFrameInfo.setVsync(intendedFrameTimeNanos, frameTimeNanos);
        // Frame标志位恢复
        mFrameScheduled = false;
        // 记录最后一帧时间
        mLastFrameTimeNanos = frameTimeNanos;
    }

    try {
  // 按类型顺序 执行任务
        Trace.traceBegin(Trace.TRACE_TAG_VIEW, "Choreographer#doFrame");
        AnimationUtils.lockAnimationClock(frameTimeNanos / TimeUtils.NANOS_PER_MS);

        mFrameInfo.markInputHandlingStart();
        doCallbacks(Choreographer.CALLBACK_INPUT, frameTimeNanos);

        mFrameInfo.markAnimationsStart();
        doCallbacks(Choreographer.CALLBACK_ANIMATION, frameTimeNanos);
        doCallbacks(Choreographer.CALLBACK_INSETS_ANIMATION, frameTimeNanos);

        mFrameInfo.markPerformTraversalsStart();
        doCallbacks(Choreographer.CALLBACK_TRAVERSAL, frameTimeNanos);

        doCallbacks(Choreographer.CALLBACK_COMMIT, frameTimeNanos);
    } finally {
        AnimationUtils.unlockAnimationClock();
        Trace.traceEnd(Trace.TRACE_TAG_VIEW);
    }
}
```

```java
void doCallbacks(int callbackType, long frameTimeNanos) {
    CallbackRecord callbacks;
    synchronized (mLock) {

        final long now = System.nanoTime();
        // 根据指定的类型CallbackkQueue中查找到达执行时间的CallbackRecord
        callbacks = mCallbackQueues[callbackType].extractDueCallbacksLocked(now / TimeUtils.NANOS_PER_MS);
        if (callbacks == null) {
            return;
        }
        mCallbacksRunning = true;

        //提交任务类型
        if (callbackType == Choreographer.CALLBACK_COMMIT) {
            final long jitterNanos = now - frameTimeNanos;
            if (jitterNanos >= 2 * mFrameIntervalNanos) {
                final long lastFrameOffset = jitterNanos % mFrameIntervalNanos
                        + mFrameIntervalNanos;
                if (DEBUG_JANK) {
                    Log.d(TAG, "Commit callback delayed by " + (jitterNanos * 0.000001f)
                            + " ms which is more than twice the frame interval of "
                            + (mFrameIntervalNanos * 0.000001f) + " ms!  "
                            + "Setting frame time to " + (lastFrameOffset * 0.000001f)
                            + " ms in the past.");
                    mDebugPrintNextFrameTimeDelta = true;
                }
                frameTimeNanos = now - lastFrameOffset;
                mLastFrameTimeNanos = frameTimeNanos;
            }
        }
    }
    try {
        // 迭代执行队列所有任务
        for (CallbackRecord c = callbacks; c != null; c = c.next) {
            // 回调CallbackRecord的run，其内部回调Callback的run
            c.run(frameTimeNanos);
        }
    } finally {
        synchronized (mLock) {
            mCallbacksRunning = false;
            do {
                final CallbackRecord next = callbacks.next;
                //回收CallbackRecord
                recycleCallbackLocked(callbacks);
                callbacks = next;
            } while (callbacks != null);
        }
    }
}
```
主要内容就是取对应任务类型的队列，遍历队列执行所有任务,执行任务是 CallbackRecord的 run 方法
```java
private static final class CallbackRecord {
    public CallbackRecord next;
    public long dueTime;
    public Object action; // Runnable or FrameCallback
    public Object token;

    @UnsupportedAppUsage
    public void run(long frameTimeNanos) {
        if (token == FRAME_CALLBACK_TOKEN) {
          // 通过postFrameCallback 或 postFrameCallbackDelayed，会执行这里
            ((FrameCallback)action).doFrame(frameTimeNanos);
        } else {
          //取出Runnable执行run()
            ((Runnable)action).run();
        }
    }
}
```
前面看到mChoreographer.postCallback传的token是null，所以取出action，就是Runnable，执行run()，这里的action就是 ViewRootImpl 发起的绘制任务mTraversalRunnable了。

那么 啥时候 token == FRAME_CALLBACK_TOKEN 呢？答案是Choreographer的postFrameCallback()方法：
```java
    public void postFrameCallback(FrameCallback callback) {
        postFrameCallbackDelayed(callback, 0);
    }

    public void postFrameCallbackDelayed(FrameCallback callback, long delayMillis) {
        if (callback == null) {
            throw new IllegalArgumentException("callback must not be null");
        }

		//也是走到是postCallbackDelayedInternal，并且注意是CALLBACK_ANIMATION类型，
		//token是FRAME_CALLBACK_TOKEN，action就是FrameCallback
        postCallbackDelayedInternal(CALLBACK_ANIMATION,
                callback, FRAME_CALLBACK_TOKEN, delayMillis);
    }

    public interface FrameCallback {
        public void doFrame(long frameTimeNanos);
    }
```
可以看到postFrameCallback()传入的是FrameCallback实例，接口FrameCallback只有一个doFrame()方法。并且也是走到postCallbackDelayedInternal，FrameCallback实例作为action传入，token则是FRAME_CALLBACK_TOKEN，并且任务是CALLBACK_ANIMATION类型。

**Choreographer的postFrameCallback()通常用来计算丢帧情况**，使用方式如下：
```java
		//Application.java
         public void onCreate() {
             super.onCreate();
             //在Application中使用postFrameCallback
             Choreographer.getInstance().postFrameCallback(new FPSFrameCallback(System.nanoTime()));
         }


    public class FPSFrameCallback implements Choreographer.FrameCallback {

      private static final String TAG = "FPS_TEST";
      private long mLastFrameTimeNanos = 0;
      private long mFrameIntervalNanos;

      public FPSFrameCallback(long lastFrameTimeNanos) {
          mLastFrameTimeNanos = lastFrameTimeNanos;
          mFrameIntervalNanos = (long)(1000000000 / 60.0);
      }

      @Override
      public void doFrame(long frameTimeNanos) {

          //初始化时间
          if (mLastFrameTimeNanos == 0) {
              mLastFrameTimeNanos = frameTimeNanos;
          }
          final long jitterNanos = frameTimeNanos - mLastFrameTimeNanos;
          if (jitterNanos >= mFrameIntervalNanos) {
              final long skippedFrames = jitterNanos / mFrameIntervalNanos;
              if(skippedFrames>30){
              	//丢帧30以上打印日志
                  Log.i(TAG, "Skipped " + skippedFrames + " frames!  "
                          + "The application may be doing too much work on its main thread.");
              }
          }
          mLastFrameTimeNanos=frameTimeNanos;
          //注册下一帧回调
          Choreographer.getInstance().postFrameCallback(this);
      }
  }
```
![](https://img-blog.csdnimg.cn/20200821112357259.png#pic_center)
参考：
[https://blog.csdn.net/luoshengyang/article/details/7846923](https://blog.csdn.net/luoshengyang/article/details/7846923)
