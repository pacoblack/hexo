---
title: android内存优化
toc: true
date: 2021-10-28 15:31:58
tags:
- android
categories:
- android
---
关于内存的一些原理和优化方式
<!--more-->

# 内存管理机制
应用程序的内存分配和垃圾回收都是由Android虚拟机完成的，**在Android 5.0以下，使用的是Dalvik虚拟机，5.0及以上，则使用的是ART虚拟机。**

## Java对象生命周期
1. Created（创建）
Java对象的创建分为如下几步：
  1、为对象分配存储空间。
  2、构造对象。
  3、从超类到子类对static成员进行初始化，类的static成员的初始化在ClassLoader加载该类时进行。
  4、超类成员变量按顺序初始化，递归调用超类的构造方法。
  5、子类成员变量按顺序初始化，一旦对象被创建，子类构造方法就调用该对象并为某些变量赋值。

2. InUse（应用）
此时对象至少被一个强引用持有。

3. Invisible（不可见）
当一个对象处于不可见阶段时，说明程序本身不再持有该对象的任何强引用，虽然该对象仍然是存在的。简单的例子就是程序的执行已经超出了该对象的作用域了。但是，该对象仍可能被虚拟机下的某些已装载的静态变量线程或JNI等强引用持有，这些特殊的强引用称为“GC Root”。被这些GC Root强引用的对象会导致该对象的内存泄漏，因而无法被GC回收。

4. Unreachable（不可达）
该对象不再被任何强引用持有。

5. Collected（收集）
当GC已经对该对象的内存空间重新分配做好准备时，对象进入收集阶段，如果该对象重写了finalize()方法，则执行它。

6. Finalized（终结）
等待垃圾回收器回收该对象空间。

7. Deallocated（对象空间重新分配）
GC对该对象所占用的内存空间进行回收或者再分配，则该对象彻底消失

## Android 内存分配模型
在Android系统中，堆实际上就是一块匿名共享内存。Android虚拟机仅仅只是把它封装成一个 mSpace，由底层C库来管理，并且仍然使用libc提供的函数malloc和free来分配和释放内存。

在大多数情况下，Android通过显示分配共享内存区域（如Ashmem或者Gralloc）来实现动态RAM区域能够在不同进程之间共享的机制。例如，Window Surface在App和Screen Compositor之间使用共享的内存，Cursor Buffers在Content Provider和Clients之间共享内存。

对于Android Runtime有两种虚拟机，Dalvik 和 ART，它们分配的内存区域块是不同的，下面我们就来简单了解下。
Dalvik:
- Linear Alloc
- Zygote Space
- Alloc Space

ART:
- Non Moving Space
- Zygote Space
- Alloc Space
- Image Space
- Large Obj Space

不管是Dlavik还是ART，运行时堆都分为 LinearAlloc（类似于ART的Non Moving Space）、Zygote Space 和 Alloc Space。
Dalvik中的Linear Alloc是一个线性内存空间，是一个只读区域，主要用来存储虚拟机中的类，因为类加载后只需要只读的属性，并且不会改变它。把这些只读属性以及在整个进程的生命周期都不能结束的永久数据放到线性分配器中管理，能很好地减少堆混乱和GC扫描，提升内存管理的性能。
Zygote Space在Zygote进程和应用程序进程之间共享，
Allocation Space则是每个进程独占。

Android系统的第一个虚拟机由Zygote进程创建并且只有一个Zygote Space。但是当Zygote进程在fork第一个应用程序进程之前，会将已经使用的那部分堆内存划分为一部分，还没有使用的堆内存划分为另一部分，也就是Allocation Space。但无论是应用程序进程，还是Zygote进程，当他们需要分配对象时，都是在各自的Allocation Space堆上进行。

当在ART运行时，还有另外两个区块，即 ImageSpace和Large Object Space。
- Image Space：存放一些预加载类，类似于Dalvik中的Linear Alloc。与Zygote Space一样，在Zygote进程和应用程序进程之间共享。
- Large Object Space：离散地址的集合，分配一些大对象，用于提高GC的管理效率和整体性能。

Dalvik 与 ART 回收的区别
1）Dalivk 仅固定一种回收算法。
2）ART 回收算法可运行期选择。
3）ART 具备内存整理能力，减少内存空洞。

# 检查方法
## Profiler
1）启动Memory Profiler，观察内存变化曲线，触发内存泄漏可能所在的流程
2）dump内存泄漏阶段的内存快照
3）根据工具中的Class Name、Allocations、Shallow Size、Retained Size分析出可能存在内存泄漏的地方
## MAT分析
1）从Android Studio进入Profile的Memory视图，选择需要分析的应用进程，对应用进行怀疑有内存问题的操作，结束操作后，主动GC几次，最后export dump文件。
2）因为Android Studio保存的是Android Dalvik/ART格式的.hprof文件，所以需要转换成J2SE HPROF格式才能被MAT识别和分析。Android SDK自带了一个转换工具在SDK的platform-tools下，其中转换语句为：
```
./hprof-conv file.hprof converted.hprof
```
3）通过其中的Histogram类似Profiler对内存进行分析，或对两个文件进行对比
4）通过Leak Suspects分析其提示可能存在内存泄漏的地方

## 常用的检测方式
1、shell命令 + LeakCanary + MAT：运行程序，所有功能跑一遍，确保没有改出问题，完全退出程序，手动触发GC，然后使用`adb shell dumpsys meminfo packagename -d` 命令查看退出界面后Objects下的Views和Activities数目是否为0，如果不是则通过LeakCanary检查可能存在内存泄露的地方，最后通过MAT分析，如此反复，改善满意为止。

2、Profile MEMORY：运行程序，对每一个页面进行内存分析检查。首先，反复打开关闭页面5次，然后收到GC（点击Profile MEMORY左上角的垃圾桶图标），如果此时total内存还没有恢复到之前的数值，则可能发生了内存泄露。此时，再点击Profile MEMORY左上角的垃圾桶图标旁的heap dump按钮查看当前的内存堆栈情况，选择按包名查找，找到当前测试的Activity，如果引用了多个实例，则表明发生了内存泄露。

3、从首页开始用依次dump出每个页面的内存快照文件，然后利用MAT的对比功能，找出每个页面相对于上个页面内存里主要增加了哪些东西，做针对性优化。

4、利用Android Memory Profiler实时观察进入每个页面后的内存变化情况，然后对产生的内存较大波峰做分析。

## 查找tip
MAT的关键使用细节：
1）、善于使用 Regex 查找对应泄漏类。
2）、使用 group by package 查找对应包下的具体类。
3）、明白 with outgoing references 和 with incoming references 的区别。
with outgoing references：它引用了哪些对象。
with incoming references：哪些对象引用了它。
4）、了解 Shallow Heap 和 Retained Heap 的区别。
Shallow Heap：表示对象自身占用的内存。
Retained Heap：对象自身占用的内存 + 对象引用的对象所占用的内存。

MAT的 5个关键组件：
1、Dominator（支配者）：
如果从GC Root到达对象A的路径上必须经过对象B，那么B就是A的支配者。
2、Histogram和dominator_tree的区别：
1）、Histogram 显示 Shallow Heap、Retained Heap、Objects，而 dominator_tree 显示的是 Shallow Heap、Retained Heap、Percentage。
2）、Histogram 基于 类 的角度，dominator_tree是基于 实例 的角度。Histogram 不会具体显示每一个泄漏的对象，而dominator_tree会。

3、thread_overview
查看 线程数量 和 线程的 Shallow Heap、Retained Heap、Context Class Loader 与 is Daemon。
4、Top Consumers
通过 图形 的形式列出 占用内存比较多的对象。
在下方的 Biggest Objects 还可以查看其 相对比较详细的信息，例如 Shallow Heap、Retained Heap。
5、Leak Suspects
列出有内存泄漏的地方，点击 Details 可以查看其产生内存泄漏的引用链。

# Bitmap内存分配的历史变化
在Android 3.0之前
  1）、Bitmap 对象存放在 Java Heap，而像素数据是存放在 Native 内存中的。
  2）、如果不手动调用 recycle，Bitmap Native 内存的回收完全依赖 finalize 函数回调，但是回调时机是不可控的。

Android 3.0 ~ Android 7.0
将 Bitmap对象 和 像素数据 统一放到 Java Heap 中，即使不调用 recycle，Bitmap 像素数据也会随着对象一起被回收。
但是，Bitmap 全部放在 Java Heap 中的缺点很明显，大致有如下两点：
1）、Bitmap是内存消耗的大户，而 Max Java Heap 一般限制为 256、512MB，Bitmap 过大过多容易导致 OOM。
2）、容易引起大量 GC，没有充分利用系统的可用内存。

Android 8.0及以后
1）、使用了能够辅助回收 Native 内存的 NativeAllocationRegistry，以实现将像素数据放到 Native 内存中，并且可以和 Bitmap 对象一起快速释放，最后，在 GC 的时候还可以考虑到这些 Bitmap 内存以防止被滥用。
2）、Android 8.0 为了 解决图片内存占用过多和图像绘制效率过慢 的问题新增了 硬件位图 Hardware Bitmap。

将图片内存存放在Native中的步骤有 四步，如下所示：

1）、调用 libandroid_runtime.so 中的 Bitmap 构造函数，申请一张空的 Native Bitmap。对于不同 Android 版本而言，这里的获取过程都有一些差异需要适配。
2）、申请一张普通的 Java Bitmap。
3）、将 Java Bitmap 的内容绘制到 Native Bitmap 中。
4）、释放 Java Bitmap 内存。

当 系统内存不足 的时候，LMK 会根据 OOM_adj 开始杀进程，从 后台、桌面、服务、前台，直到手机重启。并且，如果频繁申请释放 Java Bitmap 也很容易导致内存抖动。

# 检测大图方法
使用 Epic 来进行 Hook
Epic通常的使用步骤为如下三个步骤：
1、在项目 moudle 的 build.gradle 中添加
```
compile 'me.weishu:epic:0.6.0'
```
2、继承 XC_MethodHook，实现 Hook 方法前后的逻辑。如 监控Java线程的创建和销毁：
```Java
class ThreadMethodHook extends XC_MethodHook{
    @Override
    protected void beforeHookedMethod(MethodHookParam param) throws Throwable {
        super.beforeHookedMethod(param);
        Thread t = (Thread) param.thisObject;
        Log.i(TAG, "thread:" + t + ", started..");
    }

    @Override
    protected void afterHookedMethod(MethodHookParam param) throws Throwable {
        super.afterHookedMethod(param);
        Thread t = (Thread) param.thisObject;
        Log.i(TAG, "thread:" + t + ", exit..");
    }
}
```
3、注入 Hook 好的方法：
```Java
DexposedBridge.findAndHookMethod(Thread.class, "run", new ThreadMethodHook());
```
知道了 Epic 的基本使用方法之后，我们便可以利用它来实现大图片的监控报警了。

## 实战
在 Application 的 onCreate 方法中添加如下代码：
```Java
DexposedBridge.hookAllConstructors(ImageView.class, new XC_MethodHook() {
        @Override
        protected void afterHookedMethod(MethodHookParam param) throws Throwable {
            super.afterHookedMethod(param);
        // 1
        DexposedBridge.findAndHookMethod(ImageView.class, "setImageBitmap", Bitmap.class, new ImageHook());
        }
    });
```
在注释1处，我们 通过调用 DexposedBridge 的 findAndHookMethod 方法找到所有通过 ImageView 的 setImageBitmap 方法设置的切入点，其中最后一个参数 ImageHook 对象是继承了 XC_MethodHook 类，其目的是为了 重写 afterHookedMethod 方法拿到相应的参数进行监控逻辑的判断。
接下来，我们来实现我们的 ImageHook 类，代码如下所示：
```Java
public class ImageHook extends XC_MethodHook {

    @Override
    protected void afterHookedMethod(MethodHookParam param) throws Throwable {
        super.afterHookedMethod(param);
        // 1
        ImageView imageView = (ImageView) param.thisObject;
        checkBitmap(imageView,((ImageView) param.thisObject).getDrawable());
    }


    private static void checkBitmap(Object thiz, Drawable drawable) {
        if (drawable instanceof BitmapDrawable && thiz instanceof View) {
            final Bitmap bitmap = ((BitmapDrawable) drawable).getBitmap();
            if (bitmap != null) {
                final View view = (View) thiz;
                int width = view.getWidth();
                int height = view.getHeight();
                if (width > 0 && height > 0) {
                    // 2、图标宽高都大于view的2倍以上，则警告
                    if (bitmap.getWidth() >= (width << 1)
                        &&  bitmap.getHeight() >= (height << 1)) {
                    warn(bitmap.getWidth(), bitmap.getHeight(), width, height, new RuntimeException("Bitmap size too large"));
                }
                } else {
                    // 3、当宽高度等于0时，说明ImageView还没有进行绘制，使用ViewTreeObserver进行大图检测的处理。
                    final Throwable stackTrace = new RuntimeException();
                    view.getViewTreeObserver().addOnPreDrawListener(new ViewTreeObserver.OnPreDrawListener() {
                        @Override
                        public boolean onPreDraw() {
                            int w = view.getWidth();
                            int h = view.getHeight();
                            if (w > 0 && h > 0) {
                                if (bitmap.getWidth() >= (w << 1)
                                    && bitmap.getHeight() >= (h << 1)) {
                                    warn(bitmap.getWidth(), bitmap.getHeight(), w, h, stackTrace);
                                }
                                view.getViewTreeObserver().removeOnPreDrawListener(this);
                            }
                            return true;
                        }
                    });
                }
            }
        }
    }

    private static void warn(int bitmapWidth, int bitmapHeight, int viewWidth, int viewHeight, Throwable t) {
        String warnInfo = "Bitmap size too large: " +
            "\n real size: (" + bitmapWidth + ',' + bitmapHeight + ')' +
            "\n desired size: (" + viewWidth + ',' + viewHeight + ')' +
            "\n call stack trace: \n" + Log.getStackTraceString(t) + '\n';

        LogHelper.i(warnInfo);
    }
}
```
首先，在注释1处，我们重写了 ImageHook 的 afterHookedMethod 方法，拿到了当前的 ImageView 和要设置的 Bitmap 对象。然后，在注释2处，如果当前 ImageView 的宽高大于0，我们便进行大图检测的处理：ImageView 的宽高都大于 View 的2倍以上，则警告。接着，在注释3处，如果当前 ImageView 的宽高等于0，则说明 ImageView 还没有进行绘制，则使用 ImageView 的 ViewTreeObserver 获取其宽高进行大图检测的处理。至此，我们的大图检测检测组件就已经实现了。

# 线上内存监控
要建立线上应用的内存监控体系，我们需要 先获取 App 的 DalvikHeap 与 NativeHeap，它们的获取方式可归结为如下四个步骤：

1、首先，通过 ActivityManager 的 getProcessMemoryInfo => Debug.MemoryInfo 获取内存信息数据。
2、然后，通过 hook Debug.MemoryInfo 的 getMemoryStat 方法（os v23 及以上）可以获得 Memory Profiler 中的多项数据，进而获得细分内存的使用情况。
3、接着，通过 Runtime 获取 DalvikHeap。
4、最后，通过 Debug.getNativeHeapAllocatedSize 获取 NativeHeap

## 常规内存监控
根据 斐波那契数列 每隔一段时间（max：30min）获取内存的使用情况。

项目早期：针对场景进行线上 Dump 内存的方式
具体使用 Debug.dumpHprofData() 实现。
其实现的流程为如下四个步骤：
1）、超过最大内存的 80%。
2）、内存 Dump。
3）、回传文件至服务器。
4）、MAT 手动分析。

但是，这种方式有如下几个缺点：
1）、Dump文件太大，和对象数正相关，可以进行裁剪。
2）、上传失败率高，分析困难。

项目中期：LeakCanary带到线上的方式
在使用 LeakCanary 的时候我们需要 预设泄漏怀疑点，一旦发现泄漏进行回传。但这种实现方式缺点比较明显，如下所示：
1）、不适合所有情况，需要预设怀疑点。
2）、分析比较耗时，容易导致 OOM。

项目成熟期：定制 LeakCanary 方式
定制 LeakCanary 其实就是对 haha组件 来进行 定制
对于haha库，它的 基本用法 一般遵循为如下四个步骤：
1、导出堆栈文件
```Java
File heapDumpFile = ...
Debug.dumpHprofData(heapDumpFile.getAbsolutePath());
```
2、根据堆栈文件创建出内存映射文件缓冲区
```Java
DataBuffer buffer = new MemoryMappedFileBuffer(heapDumpFile);
```
3、根据文件缓存区创建出对应的快照
```Java
Snapshot snapshot = Snapshot.createSnapshot(buffer);
```
4、从快照中获取指定的类
```Java
ClassObj someClass = snapshot.findClass("com.example.SomeClass");
```

我们在实现线上版的LeakCanary的时候主要要解决的问题有三个，如下所示：
1）、解决 预设怀疑点 时不准确的问题 => 自动找怀疑点。
2）、解决掉将 hprof 文件映射到内存中的时候可能导致内存暴涨甚至发生 OOM 的问题 => 对象裁剪，不全部加载到内存。即对生成的 Hprof 内存快照文件做一些优化：裁剪大部分图片对应的 byte 数据 以减少文件开销，最后，使用 7zip 压缩，一般可 节省 90% 大小。
3）、分析泄漏链路慢而导致分析时间过长 => 分析 Retain size 大的对象。

# GC 监控组件搭建
通过 Debug.startAllocCounting 来监控 GC 情况，注意有一定 性能影响。
在 Android 6.0 之前 可以拿到 内存分配次数和大小以及 GC 次数，其对应的代码如下所示：
```Java
long allocCount = Debug.getGlobalAllocCount();
long allocSize = Debug.getGlobalAllocSize();
long gcCount = Debug.getGlobalGcInvocationCount();
```
并且，在 Android 6.0 及之后 可以拿到 更精准 的 GC 信息：
```
Debug.getRuntimeStat("art.gc.gc-count");
Debug.getRuntimeStat("art.gc.gc-time");
Debug.getRuntimeStat("art.gc.blocking-gc-count");
Debug.getRuntimeStat("art.gc.blocking-gc-time");
```
对于 GC 信息的排查，我们一般关注 阻塞式GC的次数和耗时，因为它会 暂停线程，可能导致应用发生 卡顿。建议 仅对重度场景使用。

# 使用基于 LeakCannary 的改进版 ResourceCanary
https://github.com/Tencent/matrix/wiki/Matrix-Android-ResourceCanary

目前，它的主要功能有 三个部分：
1、分离 检测和分析 两部分流程：自动化测试由测试平台进行，分析则由监控平台的服务端离线完成，最后再通知相关开发解决问题。
2、裁剪 Hprof文件，以降低 传输 Hprof 文件与后台存储 Hprof 文件的开销：获取 需要的类和对象相关的字符串 信息即可，其它数据都可以在客户端裁剪，一般能 Hprof 大小会减小至原来的 1/10 左右。
3、增加重复 Bitmap 对象检测：方便通过减少冗余 Bitmap 的数量，以降低内存消耗。


参考资料：https://juejin.cn/post/6844904099998089230#heading-14
