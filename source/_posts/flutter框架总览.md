---
title: flutter框架总览
toc: true
date: 2019-12-04 19:08:48
tags:
- flutter
- 深入理解
categories:
- flutter
- 深入理解
---
先来看看Flutter的大体构造
<!--more-->
# 引擎
![对比](https://mmbiz.qpic.cn/mmbiz_png/5EcwYhllQOiaCqUKfRGqGvSDWZsEKMQ0hzeGiaNklMOEn01zY5MhPiceSLbuADN5XJhlF1GzPNFDPCHr7ibLZpXHYQ/640?wx_fmt=png&tp=webp&wxfrom=5&wx_lazy=1&wx_co=1)

安卓原生框架 APP 调到大家熟悉的安卓 Framework，Framework 再调到 Skia，Skia 再最终渲染调到 GPU。对于 Flutter 中间调的是一个 Dart Framework，再调到 Skia，用 Flutter 平台和原生很接近

![Engine](https://mmbiz.qpic.cn/mmbiz_png/5EcwYhllQOiaCqUKfRGqGvSDWZsEKMQ0h6BibcBxvC5TXMLKyn8KU8PmOGFjSIJhjicibdQDfv5QL0cdYnQb940Nicg/640?wx_fmt=png&tp=webp&wxfrom=5&wx_lazy=1&wx_co=1)

上面是用 Dart 写的 APP，下面有 DartFramework，Framework 里有安卓和 iOS 的主体，里面有很多动画等等。再往下会调到引擎，引擎里有消息、PlatformChannel、Dart VM 等，引擎层再到平台。

# 进程框架
![启动框架](https://mmbiz.qpic.cn/mmbiz_png/5EcwYhllQOiaCqUKfRGqGvSDWZsEKMQ0hnm9uxt6976vXdVzeichzWwsnhVk0rJkKYygSoibuzEmuopTCO1mhklnA/640?wx_fmt=png&tp=webp&wxfrom=5&wx_lazy=1&wx_co=1)

Flutter 有 Flutter 的 Application 和 Flutter 的 Activity。在 Flutter Application 中就会把 Dart 写的代码生成一个产物，把它加载起来，我们的 Flutter Activity 过程中会拉起我们的引擎。

引擎中，Flutter 四个核心线程：平台线程、UI 线程、GPU 线程、IO 线程，它们各有分工：
- 平台线程，对于安卓和 iOS 来说就是常说的主线程，
- UI 线程，面对安卓本身的主线程，就是一个独立的线程；
- GPU 线程，指的是跑在 CPU 上的线程，它做的主要是 Skia 相关工作。
- IO 线程，比如图片解码、编解码，主要做 IO 相关的工作。

# 编译框架
![flutter编译结构](https://mmbiz.qpic.cn/mmbiz_png/5EcwYhllQOiaCqUKfRGqGvSDWZsEKMQ0hjdvIc4yakCb6OibKGfdR92EARA0SZaSicUcia5fgCvxicbYl3icHtSZhSVg/640?wx_fmt=png&tp=webp&wxfrom=5&wx_lazy=1&wx_co=1)

Dart 代码最上用前端编译器编译，下面左边绿色的是安卓，右边蓝色的是 iOS，根据不同的平台会产生不同的产物。

# 线程框架
![线程通信](https://mmbiz.qpic.cn/mmbiz_png/5EcwYhllQOiaCqUKfRGqGvSDWZsEKMQ0hD0CoBR1SniafxuVNxyEHYTsRhDmlicr42TvPd3Ih4vLhVcxk1Qhsygsg/640?wx_fmt=png&tp=webp&wxfrom=5&wx_lazy=1&wx_co=1)

以安卓为例，Flutter 依然有一个 Looper 线程，对于主线程复用了原来的 Native 的，对于另外三个线程创建的独立的 Looper，不同的是它有两个消息队列，依然是发送消息的方式，通过 Task Runner 就好比安卓的 Handler，通过 PostTask 就好比把一个消息放在一个消息队列里去。同样在 Dart 里经常用 Furture 和异步的方法，核心还是用 Task Runner 发一个消息。

# Dart虚拟机
![Dart虚拟机](https://mmbiz.qpic.cn/mmbiz_png/5EcwYhllQOiaCqUKfRGqGvSDWZsEKMQ0h1wsAxOOFH45ZW4CcDbFsHCzZpAKicEdZVJp78CgoVGictOY1KprJCPBQ/640?wx_fmt=png&tp=webp&wxfrom=5&wx_lazy=1&wx_co=1)

同一个进程里可以有很多 Isolate，两个 Isolate 的堆是不能共享的，但它们也可以交互。在 Dart 虚拟机里面也有一个特殊 Isolate，是运行在 UI 线程中，和 Root Isolate 是运行在一个线程的。当两个 Isolate 要通信，会找一个共同的可访问的内存。

Isolate1 和 Isolate2 通信是在 Isolate2 里创一个 ReceivePort，在 Isolate1 中调用其对应的 SendPort 的 send 方法，在引擎 PortMap 里面有映射表，每一个 port 端口对应一个相应 Isolate 的 MessageHandler，该 Handler 里面有两个队列，一个是普通的消息队列，一个是 OOB 高优先级消息，根据优先级把它放到相应消息队列。再把这个 **事件封装成一个 MessageTask，抛到另外一个 Isolate 里去**，我们一般创建一个 Isolate，它里面是一个 worker 线程，worker 线程放入一个新的 Task，它就会最终去执行这个 Task

# Widget 结构
![Widget](https://mmbiz.qpic.cn/mmbiz_png/5EcwYhllQOiaCqUKfRGqGvSDWZsEKMQ0hyMDogVq5w9LL0ics9egicT8C2f4cBgEichHmAYKpZVVZpYsGxia8mhicG4w/640?wx_fmt=png&tp=webp&wxfrom=5&wx_lazy=1&wx_co=1)

Widget 可以是一行文本、一张图片、一个颜色，所有都是 Widget。最大有两类，一个是无状态的 Widget，一个是有状态的。无状态顾名思义是一类 StatelessWidget，一旦创建状态是不可改变的；第二类 StatefulWidget 是状态可以改变的
![Widget渲染](https://mmbiz.qpic.cn/mmbiz_png/5EcwYhllQOiaCqUKfRGqGvSDWZsEKMQ0hQpCCCM2B0eUVqqhSuLINZuWM7lMKOAfDFAuwzKjoJTfxcaEcXtnYGg/640?wx_fmt=png&tp=webp&wxfrom=5&wx_lazy=1&wx_co=1)

对应 Widget 创建 Widget 树，它是 Element 的配置，如果两个 Widget 之间做了变化它会做差分，比较一下到底哪部分做了变化，只把变化更新到 Element 里去，以最小粒度做更新。到了 Element 里构建渲染过程中会创建 Render 对象，创建渲染的过程。

![渲染原理](https://mmbiz.qpic.cn/mmbiz_png/5EcwYhllQOiaCqUKfRGqGvSDWZsEKMQ0hWMvylXIds8SQug2KjSlQ9YnLnZUcfkGh23N6ibQZaRhMmwtDXHiaNZEQ/640?wx_fmt=png&tp=webp&wxfrom=5&wx_lazy=1&wx_co=1)
渲染来了一个信号，**UI 线程** 更新动画，动画完了会生成 Render，再往下布局、绘制大小等工作，最终生成一个 Layer Tree。

接着会到 **GPU 线程** 调用 Skia 做渲染

# 原生通信

![Channel](https://mmbiz.qpic.cn/mmbiz_png/5EcwYhllQOiaCqUKfRGqGvSDWZsEKMQ0hm0ia9xHOsoNstyrrriclEFhOKg6c9DpQvqibR1zlHLOre5mjjmcHAX0XQ/640?wx_fmt=png&tp=webp&wxfrom=5&wx_lazy=1&wx_co=1)

橙色部分代码，写相应平台安卓或者 iOS 定制代码，中间有一套封装好的机制，通过 Dart 代码直接可以调到安卓或者 iOS 代码，且这个过程是异步的。

# 总结

Flutter 是会根据ios和安卓编译生成不同的执行文件，android是生成一个flutter.jar。
以安卓为例，flutter的启动也是依赖原生的application来启动，并同时生成四个线程，四个线程的通信与Android原生的Handler通信类似，也是发送消息，不过在底层就有两个队列的区别，另外线程见与原生不同，不能直接通信，需要一个共享内存，这个共享内存位于flutter 引擎，记录不同线程的 sendPort 和 receivePort，每个port对应一个 MessageHandler，发送的消息会封装成一个MessageTask 发送到另一个Handler，接收端的Handler 把MessageTask 交给 自己的isolate中的 worker 处理。
创建完线程需要对UI渲染，GPU发送渲染信号，在UI线程中 从 WidgetTree 到 ElementTree 生成 RenderObject，接着布局、绘制，最终生成 LayerTree，接着给 GPU线程发送消息，进行Skia渲染
