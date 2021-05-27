---
title: Android优化总结
toc: true
date: 2021-02-23 15:06:09
tags:
- android
categories:
- android
---
对之前遇到的优化进行一个小结
<!--more-->
# apk瘦身
1. 开启混淆压缩
2. D8/R8优化
```
#开启D8优化
android.enableD8 = true

#R8优化
android.enableR8=true
android.enableR8.libraries=true
```
ProGuard 和 R8 都应用了基本名称混淆：它们 都使用简短，无意义的名称重命名类，字段和方法。他们还可以 删除调试属性。但是，R8 在 inline 内联容器类中更有效，并且在删除未使用的类，字段和方法上则更具侵略性。
3. 通过ReDex去除debug信息与行号信息
4. 通过ReDex将有调用关系的类和方法分配到同一个 Dex 中，从而实现分包优化
5. 通过ThinRPlugin进行R Field的内联优化（它解决了 R Field 过多导致 MultiDex 65536 的问题）
6. XZ Utils进行Dex压缩 - 使用了 LZMA/LZMA2 算法。LZMA 提供了高压缩比和快速解压缩，因此非常适合嵌入式应用。
7. 只引入需要的第三方库来减少包大小
8. 通过Lint监测无效代码，删除无用的代码
9. 通过Lint删除冗余资源，android-arscblamer删除没有用到的资源，并解析resources.arsc中可以优化的部分
10. 通过android-chunk-utils优化重复的资源，首先需要通过资源包中的每个ZipEntry的CRC-32 checksum来筛选出重复的资源。
11. 通过AndroidResGuard进行资源混淆
12. 通过TinyPngPlugin等进行图片压缩，通过不同的图片格式进行优化
13. 对resources.arsc进行压缩优化
14. 通过ByteX的access_inline插件避免产生Java access方法（Java 编译器在编译过程中自动生成 package 可见性的静态 access$xxx 方法，并且在需要访问对方私有成员的地方改为调用对应的 access 方法。）
15. so优化：尽量只用armeabi架构，使用XZ Utils进行压缩，删除无用的symbol，动态加载


# 绘制优化

## 刷新机制
4.1版本的Project Butter对Android Display系统进行了重构，引入了三个核心元素：VSYNC（Vertical Synchronization）、Triple Buffer、Choreographer。
- VSYNC，即垂直同步可认为是一种定时中断。
- Choreographer，起调度的作用，将绘制工作统一到VSYNC的某个时间点上，使应用的绘制工作有序。当收到VSYNC信号时，就会调用用户设置的回调函数。回调类型的优先级从高到低为CALLBACK_INPUT、CALLBACK_ANIMATION、CALLBACK_TRAVERSAL。

## 双缓冲技术
在Linux上通常使用Framebuffer来做显示输出，当用户进程更新Framebuffer中的数据后，显示驱动会把FrameBuffer中每个像素点的值更新到屏幕，但是如果上一帧数据还没显示完，Framebuffer中的数据又更新了，就会带来残影的问题，用户会觉得有闪烁感，所以采用了双缓冲技术。

双缓冲意味着要使用两个缓冲区（在上文提及的SharedBufferStack中），其中一个称为Front Buffer，另一个称为Back Buffer。UI总是先在Back Buffer中绘制，然后再和Front Buffer交换，渲染到显示设备中。即只有当另一个buffer的数据准备好后，通过io_ctl来通知显示设备切换Buffer。

## 优化方法
- 布局优化：减少层级、提升显示速度(ViewStub)、复用布局
- 绘制优化：减少背景设置、自定义View优化

# 内存优化
## 优化策略
1. 检测内存抖动、内存泄漏、内存溢出、图片bitmap
2. 修复抖动：字符串拼接、资源复用、减少对象创建、使用恰当的数据结构
3. 图片优化：统一的图片库、不同设备不同的图片加载策略、坚持使用小图片、ARTHook监测ImageView的操作、线上监测Bitmap的创建和回收（通过全局的WeakHashMap，包括第三方的bitmap，然后定时监测bitmap是否被引用）
- 高级：在native分配bitmap，参考fresco；编码降级
4. 线上内存监测：
- 内存使用率超过阈值、dump内存、回传服务端、分析
- 定制LeakCanary中的haha组件，预设可疑泄漏点，存在泄漏则上传
- 服务端分析内存快照，如果发现问题，分配相应负责人
- 通过onTrimMemory / onLowMemory 添加监听回调，超过阈值则触发警告
5. 监听线程相关信息，定时上传相关数据
6. 监听GC情况，如内存分配次数、大小以及GC次数
7. 通过Probe监听线上OOM
8. 线下native内存检测，可以使用 Address Sanitizer、Malloc 调试和 Malloc 钩子 进行 native 内存分析
9. 内存兜底，在用户无感知的情况下，在接近触发系统异常前，选择合适的场景杀死进程并将其重启，从而使得应用内存占用回到正常情况。
- 1）、是否在主界面退到后台且位于后台时间超过 30min。
- 2）、当前时间为早上 2~5 点。
- 3）、不存在前台服务（通知栏、音乐播放栏等情况）。
- 4）、Java heap 必须大于当前进程最大可分配的85% || native内存大于800MB。
- 5）、vmsize 超过了4G（32bit）的85%。
- 6）、非大量的流量消耗（不超过1M/min） && 进程无大量CPU调度情况。
10. 优化建议：
- 每隔 3 分钟去获取当前应用内存占最大内存的比例，超过设定的危险阈值（如80%）则主动释放应用 cache（Bitmap 为大头），并且显示地除去应用的 memory
- webView使用单独进程
- 使用类似 Hack 的方式修复系统内存泄漏，如 Booster
- 当应用使用的Service不再使用时应该销毁它，建议使用 IntentServcie
- 谨慎使用第三方库
11. 其他工具如：top、dumpsys meminfo、LeakInspector、jHat

## 对象声明周期
- Created
1. 为对象分配存储空间。
2. 构造对象。
3. 从超类到子类对static成员进行初始化，类的static成员的初始化在ClassLoader加载该类时进行。
4. 超类成员变量按顺序初始化，递归调用超类的构造方法。
5. 子类成员变量按顺序初始化，一旦对象被创建，子类构造方法就调用该对象并为某些变量赋值。
- InUse 此时对象至少被一个强引用持有。
- Invisible 当一个对象处于不可见阶段时，说明程序本身不再持有该对象的任何强引用，虽然该对象仍然是存在的。
- Unreachable 该对象不再被任何强引用持有。
- Collected 当GC已经对该对象的内存空间重新分配做好准备时，对象进入收集阶段，如果该对象重写了finalize()方法，则执行它
- Finalized 等待垃圾回收器回收该对象空间
- Deallocated GC对该对象所占用的内存空间进行回收或者再分配，则该对象彻底消失。

## 虚拟机内存分配
对于Android Runtime有两种虚拟机，Dalvik和ART，不管是Dlavik还是ART，运行时堆都分为LinearAlloc（类似于ART的Non Moving Space）、Zygote Space和Alloc Space。它们分配的内存区域块是不同的：

Dalvik
- Linear Alloc
是一个线性内存空间，是一个只读区域，主要用来存储虚拟机中的类，因为类加载后只需要读的属性，并且不会改变它。把这些只读属性以及在整个进程的生命周期都不能结束的永久数据放到线性分配器中管理，能很好地减少堆混乱和GC扫描，提升内存管理的性能。
- Zygote Space
在Zygote进程和应用程序进程之间共享
- Alloc Space
每个进程独占

ART
- Non Moving Space
- Zygote Space
- Alloc Space
- Image Space 存放一些预加载类，类似于Dalvik中的Linear Alloc。与Zygote Space一样，在Zygote进程和应用程序进程之间共享。
- Large Obj Space 离散地址的集合，分配一些大对象，用于提高GC的管理效率和整体性能。

Android系统的第一个虚拟机由Zygote进程创建并且只有一个Zygote Space。但是当Zygote进程在fork第一个应用程序进程之前，会将已经使用的那部分堆内存划分为一部分，还没有使用的堆内存划分为另一部分，也就是Allocation Space。但无论是应用程序进程，还是Zygote进程，当他们需要分配对象时，都是在各自的Allocation Space堆上进行。

## 内存回收
![](https://raw.githubusercontent.com/pacoblack/BlogImages/master/optm/optm1.jpg)
1、对象创建后在Eden区。(Copying算法)
2、执行GC后，如果对象仍然存活，则复制到S0区。
3、当S0区满时，该区域存活对象将复制到S1区，然后S0清空，接下来S0和S1角色互换。
4、当第3步达到一定次数（系统版本不同会有差异）后，存活对象将被复制到Old Generation。(标记算法)
5、当这个对象在Old Generation区域停留的时间达到一定程度时，它会被移动到Old Generation，最后累积一定时间再移动到Permanent Generation区域。

## 常见内存泄漏场景
资源性对象未关闭、注册对象未注销、类的静态变量持有大数据对象、非静态内部类的静态实例、Handler临时性内存泄漏、容器中的对象没清理造成的内存泄漏、WebView（为WebView开启一个独立的进程，使用AIDL与应用的主进程进行通信，WebView所在的进程可以根据业务的需要选择合适的时机进行销毁）

## 优化方法
引用方式(SoftReference、WeakReference和PhantomReference)、减少不必要的内存开销（自动装箱、内存复用）、合理使用数据结构、图片优化

# 启动速度优化
## 统计方式
代码打点、AOP动态代理打点

## 优化方案
懒加载、线程池、hook线程构建、预加载优化（替换ClassLOader，打印加载时间）、webView启动优化、页面数据预加载、启动阶段不启动子进程、闪屏页优化、IO优化、定义task绘制有向无环图
```java
//hook线程的构造函数
DexposedBridge.hookAllConstructors(Thread.class, new XC_MethodHook() {
    @Override protected void afterHookedMethod（MethodHookParam param）throws Throwable {                         
        super.afterHookedMethod(param);
        Thread thread = (Thread) param.thisObject;
        LogUtils.i("stack " + Log.getStackTraceString(new Throwable());
    }
);
```

# 稳定性优化
## native崩溃信号

```
#define SIGHUP 1  // 终端连接结束时发出(不管正常或非正常)
#define SIGINT 2  // 程序终止(例如Ctrl-C)
#define SIGQUIT 3 // 程序退出(Ctrl-\)
#define SIGILL 4 // 执行了非法指令，或者试图执行数据段，堆栈溢出
#define SIGTRAP 5 // 断点时产生，由debugger使用
#define SIGABRT 6 // 调用abort函数生成的信号，表示程序异常
#define SIGIOT 6 // 同上，更全，IO异常也会发出
#define SIGBUS 7 // 非法地址，包括内存地址对齐出错，比如访问一个4字节的整数, 但其地址不是4的倍数
#define SIGFPE 8 // 计算错误，比如除0、溢出
#define SIGKILL 9 // 强制结束程序，具有最高优先级，本信号不能被阻塞、处理和忽略
#define SIGUSR1 10 // 未使用，保留
#define SIGSEGV 11 // 非法内存操作，与 SIGBUS不同，他是对合法地址的非法访问，    比如访问没有读权限的内存，向没有写权限的地址写数据
#define SIGUSR2 12 // 未使用，保留
#define SIGPIPE 13 // 管道破裂，通常在进程间通信产生
#define SIGALRM 14 // 定时信号,
#define SIGTERM 15 // 结束程序，类似温和的 SIGKILL，可被阻塞和处理。通常程序如    果终止不了，才会尝试SIGKILL
#define SIGSTKFLT 16  // 协处理器堆栈错误
#define SIGCHLD 17 // 子进程结束时, 父进程会收到这个信号。
#define SIGCONT 18 // 让一个停止的进程继续执行
#define SIGSTOP 19 // 停止进程,本信号不能被阻塞,处理或忽略
#define SIGTSTP 20 // 停止进程,但该信号可以被处理和忽略
#define SIGTTIN 21 // 当后台作业要从用户终端读数据时, 该作业中的所有进程会收到SIGTTIN信号
#define SIGTTOU 22 // 类似于SIGTTIN, 但在写终端时收到
#define SIGURG 23 // 有紧急数据或out-of-band数据到达socket时产生
#define SIGXCPU 24 // 超过CPU时间资源限制时发出
#define SIGXFSZ 25 // 当进程企图扩大文件以至于超过文件大小资源限制
#define SIGVTALRM 26 // 虚拟时钟信号. 类似于SIGALRM,     但是计算的是该进程占用的CPU时间.
#define SIGPROF 27 // 类似于SIGALRM/SIGVTALRM, 但包括该进程用的CPU时间以及系统调用的时间
#define SIGWINCH 28 // 窗口大小改变时发出
#define SIGIO 29 // 文件描述符准备就绪, 可以开始进行输入/输出操作
#define SIGPOLL SIGIO // 同上，别称
#define SIGPWR 30 // 电源异常
#define SIGSYS 31 // 非法的系统调用
```
