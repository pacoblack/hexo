---
title: android启动优化
toc: true
date: 2021-10-28 18:23:18
tags:
- android
categories:
- android
---
优化app的启动速度
<!--more-->
# 启动流程
Click Event -> IPC -> Process.start -> ActivityThread -> bindApplication -> LifeCycle -> ViewRootImpl

首先，用户进行了一个点击操作，这个点击事件它会触发一个IPC的操作，之后便会执行到Process的start方法中，这个方法是用于进程创建的，接着，便会执行到ActivityThread的main方法，这个方法可以看做是我们单个App进程的入口，相当于Java进程的main方法，在其中会执行消息循环的创建与主线程Handler的创建，创建完成之后，就会执行到 bindApplication 方法，在这里使用了反射去创建 Application以及调用了 Application相关的生命周期，Application结束之后，便会执行Activity的生命周期，在Activity生命周期结束之后，最后，就会执行到 ViewRootImpl，这时才会进行真正的一个页面的绘制

启动App
加载空白Window
创建进程
创建 Application
启动主线程
创建 MainActivity
加载布局
布置屏幕
首帧绘制

# 查看启动时间
1. 在Android Studio Logcat中过滤关键字“Displayed”，可以看到对应的冷启动耗时日志。
2. 通过 adb 获取
```
// 其中的AppstartActivity全路径可以省略前面的packageName
adb shell am start -W [packageName]/[AppstartActivity全路径]
```
其中：
ThisTime：表示最后一个Activity启动耗时。
TotalTime：表示所有Activity启动耗时。
WaitTime：表示AMS启动Activity的总耗时。

3.代码插桩
```java
/**
* 耗时监视器对象，记录整个过程的耗时情况，可以用在很多需要统计的地方，比如Activity的启动耗时和Fragment的启动耗时。
*/
public class TimeMonitor {

    private final String TAG = TimeMonitor.class.getSimpleName();
    private int mMonitord = -1;

    // 保存一个耗时统计模块的各种耗时，tag对应某一个阶段的时间
    private HashMap<String, Long> mTimeTag = new HashMap<>();
    private long mStartTime = 0;

    public TimeMonitor(int mMonitorId) {
        Log.d(TAG, "init TimeMonitor id: " + mMonitorId);
        this.mMonitorId = mMonitorId;
    }

    public int getMonitorId() {
        return mMonitorId;
    }

    public void startMonitor() {
        // 每次重新启动都把前面的数据清除，避免统计错误的数据
        if (mTimeTag.size() > 0) {
        mTimeTag.clear();
        }
        mStartTime = System.currentTimeMillis();
    }

    /**
    * 每打一次点，记录某个tag的耗时
    */
    public void recordingTimeTag(String tag) {
        // 若保存过相同的tag，先清除
        if (mTimeTag.get(tag) != null) {
            mTimeTag.remove(tag);
        }
        long time = System.currentTimeMillis() - mStartTime;
        Log.d(TAG, tag + ": " + time);
        mTimeTag.put(tag, time);
    }

    public void end(String tag, boolean writeLog) {
        recordingTimeTag(tag);
        end(writeLog);
    }

    public void end(boolean writeLog) {
        if (writeLog) {
            //写入到本地文件
        }
    }

    public HashMap<String, Long> getTimeTags() {
        return mTimeTag;
    }
}
```
```Java
/**
* 采用单例管理各个耗时统计的数据。
*/
public class TimeMonitorManager {

    private static TimeMonitorManager mTimeMonitorManager = null;
private HashMap<Integer, TimeMonitor> mTimeMonitorMap = null;

    public synchronized static TimeMonitorManager getInstance() {
        if (mTimeMonitorManager == null) {
            mTimeMonitorManager = new TimeMonitorManager();
        }
        return mTimeMonitorManager;
    }

    public TimeMonitorManager() {
        this.mTimeMonitorMap = new HashMap<Integer, TimeMonitor>();
    }

    /**
     * 初始化打点模块
    */
    public void resetTimeMonitor(int id) {
        if (mTimeMonitorMap.get(id) != null) {
            mTimeMonitorMap.remove(id);
        }
        getTimeMonitor(id).startMonitor();
    }

    /**
    * 获取打点器
    */
    public TimeMonitor getTimeMonitor(int id) {
        TimeMonitor monitor = mTimeMonitorMap.get(id);
        if (monitor == null) {
            monitor = new TimeMonitor(id);
            mTimeMonitorMap.put(id, monitor);
        }
        return monitor;
    }
}
```
```Java
@Override
protected void attachBaseContext(Context base) {
    super.attachBaseContext(base);
    TimeMonitorManager.getInstance().resetTimeMonitor(TimeMonitorConfig.TIME_MONITOR_ID_APPLICATION_START);
}

@Override
public void onCreate() {
    super.onCreate();
    SoLoader.init(this, /* native exopackage */ false);
    TimeMonitorManager.getInstance().getTimeMonitor(TimeMonitorConfig.TIME_MONITOR_ID_APPLICATION_START).recordingTimeTag("Application-onCreate");
}
```
4. AOP插桩
```Java
@Aspect
public class ApplicationAop {

    @Around("call (* com.json.chao.application.BaseApplication.**(..))")
    public void getTime(ProceedingJoinPoint joinPoint) {
    Signature signature = joinPoint.getSignature();
    String name = signature.toShortString();
    long time = System.currentTimeMillis();
    try {
        joinPoint.proceed();
    } catch (Throwable throwable) {
        throwable.printStackTrace();
    }
    Log.i(TAG, name + " cost" +     (System.currentTimeMillis() - time));
    }
}
```

# 启动分析工具（TraceView）
1、代码中添加：Debug.startMethodTracing()、检测方法、Debug.stopMethodTracing()。（需要使用adb pull将生成的.trace文件导出到电脑，然后使用Android Studio的Profiler进行加载）
2、打开 Profiler  ->  CPU   ->    点击 Record   ->  点击 Stop  ->  查看Profiler下方Top Down/Bottom Up 区域，以找出耗时的热点方法。

# 启动分析工具（Systrace）
1. 定义一个Trace静态工厂类，将Trace.begainSection()，Trace.endSection()封装成i、o方法，然后再在想要分析的方法前后进行插桩即可。
2. 在命令行下执行systrace.py脚本
```
python /Users/quchao/Library/Android/sdk/platform-tools/systrace/systrace.py -t 20 sched gfx view wm am app webview -a "com.wanandroid.json.chao" -o ~/Documents/open-project/systrace_data/wanandroid_start_1.html
```

# 优化方案
## 第三方库懒加载
按需初始化，特别是针对于一些应用启动时不需要初始化的库，可以等到用时才进行加载。

## Android异步加载
- Thread
- HandlerThread
- IntentService
- AsyncTask
- 线程池
- RxJava

## 线程池优化实践
```Java
// 如果当前执行的任务是CPU密集型任务，则从基础线程池组件
// DispatcherExecutor中获取到用于执行 CPU 密集型任务的线程池
DispatcherExecutor.getCPUExecutor().execute(YourRunable());

// 如果当前执行的任务是IO密集型任务，则从基础线程池组件
// DispatcherExecutor中获取到用于执行 IO 密集型任务的线程池
DispatcherExecutor.getIOExecutor().execute(YourRunable());


public class DispatcherExecutor {

    /**
     * CPU 密集型任务的线程池
     */
    private static ThreadPoolExecutor sCPUThreadPoolExecutor;

    /**
     * IO 密集型任务的线程池
     */
    private static ExecutorService sIOThreadPoolExecutor;

    /**
     * 当前设备可以使用的 CPU 核数
     */
    private static final int CPU_COUNT = Runtime.getRuntime().availableProcessors();

    /**
     * 线程池核心线程数，其数量在2 ~ 5这个区域内
     */
    private static final int CORE_POOL_SIZE = Math.max(2, Math.min(CPU_COUNT - 1, 5));

    /**
     * 线程池线程数的最大值：这里指定为了核心线程数的大小
     */
    private static final int MAXIMUM_POOL_SIZE = CORE_POOL_SIZE;

    /**
    * 线程池中空闲线程等待工作的超时时间，当线程池中
    * 线程数量大于corePoolSize（核心线程数量）或
    * 设置了allowCoreThreadTimeOut（是否允许空闲核心线程超时）时，
    * 线程会根据keepAliveTime的值进行活性检查，一旦超时便销毁线程。
    * 否则，线程会永远等待新的工作。
    */
    private static final int KEEP_ALIVE_SECONDS = 5;

    /**
    * 创建一个基于链表节点的阻塞队列
    */
    private static final BlockingQueue<Runnable> S_POOL_WORK_QUEUE = new LinkedBlockingQueue<>();

    /**
     * 用于创建线程的线程工厂
     */
    private static final DefaultThreadFactory S_THREAD_FACTORY = new DefaultThreadFactory();

    /**
     * 线程池执行耗时任务时发生异常所需要做的拒绝执行处理
     * 注意：一般不会执行到这里
     */
    private static final RejectedExecutionHandler S_HANDLER = new RejectedExecutionHandler() {
        @Override
        public void rejectedExecution(Runnable r, ThreadPoolExecutor executor) {
            Executors.newCachedThreadPool().execute(r);
        }
    };

    /**
     * 获取CPU线程池
     *
     * @return CPU线程池
     */
    public static ThreadPoolExecutor getCPUExecutor() {
        return sCPUThreadPoolExecutor;
    }

    /**
     * 获取IO线程池
     *
     * @return IO线程池
     */
    public static ExecutorService getIOExecutor() {
        return sIOThreadPoolExecutor;
    }

    /**
     * 实现一个默认的线程工厂
     */
    private static class DefaultThreadFactory implements ThreadFactory {
        private static final AtomicInteger POOL_NUMBER = new AtomicInteger(1);
        private final ThreadGroup group;
        private final AtomicInteger threadNumber = new AtomicInteger(1);
        private final String namePrefix;

        DefaultThreadFactory() {
            SecurityManager s = System.getSecurityManager();
            group = (s != null) ? s.getThreadGroup() :
                    Thread.currentThread().getThreadGroup();
            namePrefix = "TaskDispatcherPool-" +
                    POOL_NUMBER.getAndIncrement() +
                    "-Thread-";
        }

        @Override
        public Thread newThread(Runnable r) {
            // 每一个新创建的线程都会分配到线程组group当中
            Thread t = new Thread(group, r,
                    namePrefix + threadNumber.getAndIncrement(),
                    0);
            if (t.isDaemon()) {
                // 非守护线程
                t.setDaemon(false);
            }
            // 设置线程优先级
            if (t.getPriority() != Thread.NORM_PRIORITY) {
                t.setPriority(Thread.NORM_PRIORITY);
            }
            return t;
        }
    }

    static {
        sCPUThreadPoolExecutor = new ThreadPoolExecutor(
                CORE_POOL_SIZE, MAXIMUM_POOL_SIZE, KEEP_ALIVE_SECONDS, TimeUnit.SECONDS,
                S_POOL_WORK_QUEUE, S_THREAD_FACTORY, S_HANDLER);
        // 设置是否允许空闲核心线程超时时，线程会根据keepAliveTime的值进行活性检查，一旦超时便销毁线程。否则，线程会永远等待新的工作。
        sCPUThreadPoolExecutor.allowCoreThreadTimeOut(true);
        // IO密集型任务线程池直接采用CachedThreadPool来实现，
        // 它最多可以分配Integer.MAX_VALUE个非核心线程用来执行任务
        sIOThreadPoolExecutor = Executors.newCachedThreadPool(S_THREAD_FACTORY);
    }

}
```

## 异步启动器
https://github.com/zeshaoaaa/AppStarter
启动的核心流程如下所示：
1、任务Task化，启动逻辑抽象成Task（Task即对应一个个的初始化任务）。
2、根据所有任务依赖关系排序生成一个有向无环图：例如推送SDK初始化任务需要依赖于获取设备id的初始化任务，各个任务之间都可能存在依赖关系，所以将它们的依赖关系排序生成一个有向无环图能将并行效率最大化。
3、多线程按照排序后的优先级依次执行：例如必须先初始化获取设备id的初始化任务，才能去进行推送SDK的初始化任务。

```Java
// 1、启动器初始化
TaskDispatcher.init(this);
// 2、创建启动器实例，这里每次获取的都是新对象
TaskDispatcher dispatcher = TaskDispatcher.createInstance();
// 3、给启动器配置一系列的（异步/非异步）初始化任务并启动启动器
dispatcher
        .addTask(new InitAMapTask())
        .addTask(new InitStethoTask())
        .addTask(new InitWeexTask())
        .addTask(new InitBuglyTask())
        .addTask(new InitFrescoTask())
        .addTask(new InitJPushTask())
        .addTask(new InitUmengTask())
        .addTask(new GetDeviceIdTask())
        .start();

// 4、需要等待微信SDK初始化完成，程序才能往下执行
dispatcher.await();
```
在注释3处，我们给启动器配置了一系列的初始化任务并启动启动器，需要注意的是，这里的Task既可以是用于执行异步任务（子线程）的也可以是用于执行非异步任务（主线程）。下面，我们来分析下这两种Task的用法，比如InitStethoTask这个异步任务的初始化，代码如下所示：
```Java
/**
 * Task中的runOnMainThread方法返回为false，说明 task 是用于处理异步任务的task
*/
public class InitStethoTask extends Task {

    @Override
    public void run() {
        Stetho.initializeWithDefaults(mContext);
    }
}

```
下面，我们再看看另一个用于初始化非异步任务的例子，例如用于微信SDK初始化的InitWeexTask，代码如下所示：
```java
/**
* 主线程中的非异步任务
*/
public abstract class MainTask extends Task {

    @Override
    public boolean runOnMainThread() {
        return true;
    }

}
/**
* 它直接继承了MainTask,主线程执行的task
*/
public class InitWeexTask extends MainTask {

    /**
    * 表示在某个时刻之前必须等待当前Task初始化完成程序才能继续往下执行
    */
    @Override
    public boolean needWait() {
        return true;
    }

    @Override
    public void run() {
        InitConfig config = new InitConfig.Builder().build();
        WXSDKEngine.initialize((Application) mContext, config);
    }
}
```
```java
/**
* 存在依赖关系的Task
*/
public class InitJPushTask extends Task {

    @Override
    public List<Class<? extends Task>> dependsOn() {
        List<Class<? extends Task>> task = new ArrayList<>();
        task.add(GetDeviceIdTask.class);
        return task;
    }

    @Override
    public void run() {
        JPushInterface.init(mContext);
        MyApplication app = (MyApplication) mContext;
        JPushInterface.setAlias(mContext, 0, app.getDeviceId());
    }
}
```

## 延迟初始化
https://github.com/zeshaoaaa/AppStarter

```java
/**
 * 延迟初始化分发器
 */
public class DelayInitDispatcher {

    private Queue<Task> mDelayTasks = new LinkedList<>();

    private MessageQueue.IdleHandler mIdleHandler = new     MessageQueue.IdleHandler() {
        @Override
        public boolean queueIdle() {
            // 分批执行的好处在于每一个task占用主线程的时间相对
            // 来说很短暂，并且此时CPU是空闲的，这些能更有效地避免UI卡顿
            if(mDelayTasks.size()>0){
                Task task = mDelayTasks.poll();
                new DispatchRunnable(task).run();
            }
            return !mDelayTasks.isEmpty();
        }
    };

    public DelayInitDispatcher addTask(Task task){
        mDelayTasks.add(task);
        return this;
    }

    public void start(){
        Looper.myQueue().addIdleHandler(mIdleHandler);
    }

}
```

## Multidex预加载优化
https://github.com/lanshifu/MultiDexTest

1、启动时单独开一个进程去异步进行Multidex的第一次加载，即Dex提取和Dexopt操作。
2、此时，主进程Application进入while循环，不断检测Multidex操作是否完成。
3、执行到Multidex时，则已经发现提取并优化好了Dex，直接执行。MultiDex执行完之后主进程Application继续执行ContentProvider初始化和Application的onCreate方法。

### 抖音BoostMultiDex优化
https://juejin.cn/post/6844904079206907911

1. 在第一次启动的时候，直接加载没有经过 OPT 优化的原始 DEX，先使得 APP 能够正常启动。
2. 在后台启动一个单独进程，慢慢地做完 DEX 的 OPT 工作，尽可能避免影响到前台 APP 的正常使用。
绕过 ODEX 直接加载 DEX 的方案如下：
1）从 APK 中解压获取原始 Secondary DEX 文件的字节码
2）通过 dlsym 获取dvm_dalvik_system_DexFile数组
3）在数组中查询得到Dalvik_dalvik_system_DexFile_openDexFile_bytearray函数
4）调用该函数，逐个传入之前从 APK 获取的 DEX 字节码，完成 DEX 加载，得到合法的DexFile对象
5）把DexFile对象都添加到 APP 的PathClassLoader的 pathList 里

## 类预加载优化
在Application中提前异步加载初始化耗时较长的类。

>如何找到耗时较长的类？
替换系统的ClassLoader，打印类加载的时间，按需选取需要异步加载的类。

## WebView启动优化
1、WebView首次创建比较耗时，需要预先创建WebView提前将其内核初始化。
2、使用WebView缓存池，用到WebView的时候都从缓存池中拿，注意内存泄漏问题。
3、本地离线包，即预置静态页面资源。

## 优化黑科技
1. 启动阶段抑制GC
2. CPU锁频
3. IO优化
4. 数据重排
5. 类加载优化（Dalvik）
6. 保活

参考资料：https://juejin.cn/post/6870457006784774152#heading-91
