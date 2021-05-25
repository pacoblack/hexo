---
title: flutter框架总览
toc: true
date: 2019-12-04 19:08:48
tags:
- Flutter
- 深入理解
categories:
- Flutter
- 深入理解
---
先来看看Flutter的大体构造
<!--more-->
# 引擎
![对比](flutter1.jpg)

安卓原生框架 APP 调到大家熟悉的安卓 Framework，Framework 再调到 Skia，Skia 再最终渲染调到 GPU。对于 Flutter 中间调的是一个 Dart Framework，再调到 Skia，用 Flutter 平台和原生很接近

![Engine](flutter2.jpg)

上面是用 Dart 写的 APP，下面有 DartFramework，Framework 里有安卓和 iOS 的主体，里面有很多动画等等。再往下会调到引擎，引擎里有消息、PlatformChannel、Dart VM 等，引擎层再到平台。

>一个FlutterView对应一个FlutterEngine实例；
一个FlutterEngine实例对应一个Dart Isolate实例；
同一个进程只有且仅有一个Dart VM虚拟机；
一个Dart VM上会存在多个Dart Isolate实例，Isolate是dart代码的执行环境；

# 编译框架
![flutter编译结构](flutter4.jpg)

Dart 代码最上用前端编译器编译，下面左边绿色的是安卓，右边蓝色的是 iOS，根据不同的平台会产生不同的产物。

# 进程框架
![启动框架](flutter3.jpg)

Flutter 有 Flutter 的 Application 和 Flutter 的 Activity。在 Flutter Application 中就会把 Dart 写的代码生成一个产物，把它加载起来，我们的 Flutter Activity 过程中会拉起我们的引擎。

引擎中，Flutter 四个核心线程：平台线程、UI 线程、GPU 线程、IO 线程，它们各有分工：
- 平台线程，对于安卓和 iOS 来说就是常说的主线程，
一般来说，一个Flutter应用启动的时候会创建一个Engine实例，Engine创建的时候会创建一个线程供 Platform Runner 使用。跟Flutter Engine的所有交互（接口调用）必须在 Platform Thread 进行，否则可能导致无法预期的异常。这跟iOS UI相关的操作都必须在主线程进行相类似。需要注意的是在Flutter Engine中有很多模块都是非线程安全的。规则很简单，对于Flutter Engine的接口调用都需保证在Platform Thread进行。阻塞 Platform Thread 不会直接导致Flutter应用的卡顿（跟iOS android主线程不同）。尽管如此，也不建议在这个Runner执行繁重的操作，长时间卡住Platform Thread应用有可能会被系统Watchdog强杀。
实际上我们可以同时启动多个Engine实例，每个Engine对应一个Platform Runxner，每个Runner跑在各自的线程里。
- UI 线程，面对安卓本身的主线程，就是一个独立的线程；UI Task Runner用于执行Dart root isolate代码
Root isolate比较特殊，它绑定了不少Flutter需要的函数方法，以便进行渲染相关操作。对于每一帧，引擎要做的事情有：
    1. Root isolate通知Flutter Engine有帧需要渲染。
    2. Flutter Engine通知平台，需要在下一个vsync的时候得到通知。
    3. 平台等待下一个vsync
    4. 对创建的对象和Widgets进行Layout并生成一个Layer Tree，这个Tree马上被提交给Flutter Engine。当前阶段没有进行任何光栅化，这个步骤仅是生成了对需要绘制内容的描述。
    5. 创建或者更新Tree，这个Tree包含了用于屏幕上显示Widgets的语义信息。这个东西主要用于平台相关的辅助Accessibility元素的配置和渲染。
除了渲染相关逻辑之外Root Isolate还是处理来自Native Plugins的消息，Timers，Microtasks和异步IO等操作。Root Isolate负责创建管理的Layer Tree最终决定绘制到屏幕上的内容。因此这个线程的过载会直接导致卡顿掉帧。
- GPU 线程，指的是跑在 GPU 上的线程，它做的主要是 Skia 相关工作。
UI Task Runner创建的Layer Tree是跨平台的，它不关心到底由谁来完成绘制。GPU Task Runner负责将Layer Tree提供的信息转化为平台可执行的GPU指令。GPU Task Runner同时负责绘制所需要的GPU资源的管理。资源主要包括平台Framebuffer，Surface，Texture和Buffers等。
一般来说UI Runner和GPU Runner跑在不同的线程。GPU Runner会根据目前帧执行的进度去向UI Runner要求下一帧的数据，在任务繁重的时候可能会告诉UI Runner延迟任务。这种调度机制确保GPU Runner不至于过载，同时也避免了UI Runner不必要的消耗。
建议为每一个Engine实例都新建一个专用的GPU Runner线程。
- IO 线程，比如图片解码、编解码，主要做 IO 相关的工作。
Platform Runner过载可能导致系统WatchDog强杀，UI和GPU Runner过载则可能导致Flutter应用的卡顿。但是GPU线程的一些必要操作，例如IO，放到哪里执行呢？答案正是IO Runner。
IO Runner的主要功能是从图片存储（比如磁盘）中读取压缩的图片格式，将图片数据进行处理为GPU Runner的渲染做好准备。IO Runner首先要读取压缩的图片二进制数据（比如PNG，JPEG），将其解压转换成GPU能够处理的格式然后将数据上传到GPU。
获取诸如ui.Image这样的资源只有通过async call去调用，当调用发生的时候Flutter Framework告诉IO Runner进行加载的异步操作。
IO Runner直接决定了图片和其它一些资源加载的延迟间接影响性能。所以建议为IO Runner创建一个专用的线程。

# 线程框架
![线程通信](flutter5.jpg)

以安卓为例，Flutter 依然有一个 Looper 线程，对于主线程复用了原来的 Native 的，对于另外三个线程创建的独立的 Looper，不同的是它有两个消息队列，依然是发送消息的方式，通过 Task Runner 就好比安卓的 Handler，通过 PostTask 就好比把一个消息放在一个消息队列里去。同样在 Dart 里经常用 Furture 和异步的方法，核心还是用 Task Runner 发一个消息。

# Dart虚拟机
![Dart虚拟机](flutter6.jpg)

同一个进程里可以有很多 Isolate，两个 Isolate 的堆是不能共享的，但它们也可以交互。在 Dart 虚拟机里面也有一个特殊 Isolate，是运行在 UI 线程中，和 Root Isolate 是运行在一个线程的。当两个 Isolate 要通信，会找一个共同的可访问的内存。

![isolate](isolate.jpg)
```dart
//在父Isolate中调用
Isolate isolate;
start() async {
  ReceivePort receivePort = ReceivePort();
  //创建子Isolate对象
  isolate = await Isolate.spawn(getMsg, receivePort.sendPort);
  //监听子Isolate的返回数据
  receivePort.listen((data) {
    print('data：$data');
    receivePort.close();
    //关闭Isolate对象
    isolate?.kill(priority: Isolate.immediate);
    isolate = null;
  });
}
//子Isolate对象的入口函数，可以在该函数中做耗时操作
getMsg(sendPort) => sendPort.send("hello");
```
创建Isolate时会将其中的MessageHandler对象添加到一个全局的map，（在Dart VM初始化的时候创建，每个元素都是一个Entry对象，在Entry中，有一个MessageHandler对象，一个端口号及该端口的状态。），接着创建 ReceivePort 对象，ReceivePort对应着Dart SDK中的_RawReceivePortImpl对象，SendPort对应着Dart SDK中的_SendPortImpl对象。当ReceivePort创建成功后，就可以通过调用_SendPortImpl的send函数来发送消息。send 发送消息时，将消息加入到了目标Isolate的MessageHandler中，
在PostMessage中主要是做了以下操作
1. 根据消息级别将消息加入到不同的队列中。主要有OOB消息及普通消息两个级别，OOB消息在队列oob_queue_中，普通消息在队列queue_中。OOB消息级别高于普通消息，会立即处理。
2. 将一个消息处理任务MessageHandlerTask加入到线程中。

普通消息的处理
1. 首先调用Dart SDK中_RawReceivePortImpl对象的_lookupHandler函数，返回一个在创建_RawReceivePortImpl对象时注册的一个自定义函数。
2. 调用Dart SDK中_RawReceivePortImpl对象的_handleMessage函数并传入1中返回的自定义函数，通过该自定义函数将消息分发出去

双向通信也很简单，在父Isolate中创建一个端口，并在创建子Isolate时，将这个端口传递给子Isolate。然后在子Isolate调用其入口函数时也创建一个新端口，并通过父Isolate传递过来的端口把子Isolate创建的端口传递给父Isolate，这样父Isolate与子Isolate分别拥有对方的一个端口号，从而实现了通信
```dart
//当前函数在父Isolate中
Future<dynamic> asyncFactoriali(n) async {
  //父Isolate对应的ReceivePort对象
  final response = ReceivePort();
  //创建一个子Isolate对象
  await Isolate.spawn(_isolate, response.sendPort);
  final sendPort = await response.first as SendPort;
  final answer = ReceivePort();
  //给子Isolate发送数据
  sendPort.send([n, answer.sendPort]);
  return answer.first;
}

//子Isolate的入口函数，可以在该函数中做耗时操作
//_isolate必须是顶级函数（不能存在任何类中）或者是静态函数（可以存在类中）
_isolate(SendPort initialReplyTo) async {
  //子Isolate对应的ReceivePort对象
  final port = ReceivePort();
  initialReplyTo.send(port.sendPort);
  final message = await port.first as List;
  final data = message[0] as int;
  final send = message[1] as SendPort;
  //给父Isolate的返回数据
  send.send(syncFactorial(data));
}

//运行代码
start() async {
  print("计算结果：${await asyncFactoriali(4)}");
}
start();
```

![过程图](sendMsg.jpg)
[原文](https://juejin.im/post/5e149a7df265da5d3b32e167#heading-6)

Isolate1 和 Isolate2 通信是在 Isolate2 里创一个 ReceivePort，在 Isolate1 中调用其对应的 SendPort 的 send 方法，在引擎 PortMap 里面有映射表，每一个 port 端口对应一个相应 Isolate 的 MessageHandler，该 Handler 里面有两个队列，一个是普通的消息队列，一个是 OOB 高优先级消息，根据优先级把它放到相应消息队列。再把这个 **事件封装成一个 MessageTask，抛到另外一个 Isolate 里去**，我们一般创建一个 Isolate，它里面是一个 worker 线程，worker 线程放入一个新的 Task，它就会最终去执行这个 Task

# Widget 结构
![Widget](flutter7.jpg)

Widget 可以是一行文本、一张图片、一个颜色，所有都是 Widget。最大有两类，一个是无状态的 Widget，一个是有状态的。无状态顾名思义是一类 StatelessWidget，一旦创建状态是不可改变的；第二类 StatefulWidget 是状态可以改变的
![Widget渲染](flutter8.jpg)

对应 Widget 创建 Widget 树，它是 Element 的配置，如果两个 Widget 之间做了变化它会做差分，比较一下到底哪部分做了变化，只把变化更新到 Element 里去，以最小粒度做更新。到了 Element 里构建渲染过程中会创建 Render 对象，创建渲染的过程。

![渲染原理](flutter9.jpg)
渲染来了一个信号，**UI 线程** 更新动画，动画完了会生成 Render，再往下布局、绘制大小等工作，最终生成一个 Layer Tree。

接着会到 **GPU 线程** 调用 Skia 做渲染

# 原生通信

![Channel](flutter10.jpg)

橙色部分代码，写相应平台安卓或者 iOS 定制代码，中间有一套封装好的机制，通过 Dart 代码直接可以调到安卓或者 iOS 代码，且这个过程是异步的。

# 总结

Flutter 是会根据ios和安卓编译生成不同的执行文件，android是生成一个flutter.jar。
以安卓为例，flutter的启动也是依赖原生的application来启动，并同时生成四个线程，四个线程的通信与Android原生的Handler通信类似，也是发送消息，区别在于另外三个线程公用两个队列，另外进程间通信与原生不同，不能直接通信，需要一个共享内存，这个共享内存位于flutter 引擎，记录不同线程的 sendPort 和 receivePort，每个port对应一个 MessageHandler，发送的消息会封装成一个MessageTask 发送到另一个Handler，接收端的Handler 把MessageTask 交给 自己的isolate中的 worker 处理。
创建完线程需要对UI渲染，GPU发送渲染信号，在UI线程中 从 WidgetTree 将变化更新到Element中去生成 ElementTree 生成 RenderObject，接着布局、绘制，最终生成 LayerTree，接着给 GPU线程发送消息，进行Skia渲染
不同的平台可以通过MethodChannel实现不同平台的原生与flutter通信
