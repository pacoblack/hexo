---
title: Handler原理
toc: true
date: 2020-06-02 14:43:41
tags:
- Android
categories:
- Android
- 原理
---
Handler、Looper、Message是Android线程间通信的重要概念，我们在项目中会经常用到，最常用的写法，创建一个Handler对象，在线程中通过Handler发送消息来更新UI。现在我们来看看Handler是怎么工作的
<!--more-->
# 构造函数
## Handler

```java
public Handler(@Nullable Callback callback, boolean async) {
    if (FIND_POTENTIAL_LEAKS) {
        final Class<? extends Handler> klass = getClass();
        if ((klass.isAnonymousClass() || klass.isMemberClass() || klass.isLocalClass()) &&
                (klass.getModifiers() & Modifier.STATIC) == 0) {
            Log.w(TAG, "The following Handler class should be static or leaks might occur: " +
                klass.getCanonicalName());
        }
    }

    mLooper = Looper.myLooper();
    if (mLooper == null) {
        throw new RuntimeException(
            "Can't create handler inside thread " + Thread.currentThread()
                    + " that has not called Looper.prepare()");
    }
    mQueue = mLooper.mQueue;
    mCallback = callback;
    mAsynchronous = async;
}
```

## Looper

```java
private Looper(boolean quitAllowed) {
    mQueue = new MessageQueue(quitAllowed);
    mThread = Thread.currentThread();
}

private static void prepare(boolean quitAllowed) {
    if (sThreadLocal.get() != null) {
        throw new RuntimeException("Only one Looper may be created per thread");
    }
    sThreadLocal.set(new Looper(quitAllowed));
}
```

## MessageQueue

```java
MessageQueue(boolean quitAllowed) {
    mQuitAllowed = quitAllowed;
    mPtr = nativeInit();
}
```
从上面的代码我们看到 Handler 需要获取 Looper 句柄，并从Looper中获取 MessageQueue，需要注意，如果获取的Looper为 null，会抛出异常，意味着需要调用 prepare方法，一般在线程初始化的时候需要调用prepare方法，将当前线程的 Looper保存到一个 ThreadLocal中，然后再从这个sThreadLocal中获取 Looper。我们所谓的主线程是在ActivityThread的main方法中初始化的。下面是main方法的一些主要方法
```java
public static void main(String[] args) {
    Trace.traceBegin(Trace.TRACE_TAG_ACTIVITY_MANAGER, "ActivityThreadMain");

    // Install selective syscall interception
    AndroidOs.install();
    ...
    Looper.prepareMainLooper();
    ...
    ActivityThread thread = new ActivityThread();
    thread.attach(false, startSeq);

    if (sMainThreadHandler == null) {
        sMainThreadHandler = thread.getHandler();
    }

    if (false) {
        Looper.myLooper().setMessageLogging(new
                LogPrinter(Log.DEBUG, "ActivityThread"));
    }

    // End of event ActivityThreadMain.
    Trace.traceEnd(Trace.TRACE_TAG_ACTIVITY_MANAGER);
    Looper.loop();

    throw new RuntimeException("Main thread loop unexpectedly exited");
}
```

# 消息传递

## enqueueMesssage

Handler负责发送message到messageQueue，最终都是通过 MessageQueue.enqueueMessage。主要过程如下：
  1. 先持有MessageQueue.this锁
  2. 如果队列为空，或者当前处理的时间点为0（when的数值，when表示Message将要执行的时间点），或者当前Message需要处理的时间点先于队列中的首节点，那么就将Message放入队列首部，否则进行下一步。
  3. 寻找插入位置。遍历队列中Message，找到when比当前Message的when大的Message，将Message插入到该Message之前，如果没找到则将Message插入到队列最后。
  4. 如果有一个message需要发送，则调用 nativeWake 唤醒 MessageQueue.next 方法。这个方法在队列为空的情况下，会进入睡眠状态

这里插入一下，nativeWake 调用后表示唤醒了 nativePollOnce，即这个方法在next中被调用，而next方法是在 Looper.loop 中被调用, loop 和 next 方法中还都是for(;;)

## next
next方法主要是取出将要执行的message， 主要步骤如下：
  1. 初始化操作，如果mPtr为null，则直接返回null，设置nextPollTimeoutMillis为0，进入下一步。

  2. 调用nativePollOnce, nativePollOnce有两个参数,第一个为mPtr表示native层MessageQueue的指针，nextPollTimeoutMillis表示超时返回时间，调用这个nativePollOnce **会等待 nextPollTimeoutMillis 时间**，如果超过nextPollTimeoutMillis时间，则不管有没有被唤醒都会返回。-1表示一直等待，0表示立刻返回。

  3. **获取队列的头Message(msg)**，如果头Message的target为null，则查找一个异步Message来进行下一步处理。当队列中添加了同步Barrier的时候target会为null。

  4. 判断上一步获取的msg是否为null，为null说明当前队列中没有msg，设置等待时间nextPollTimeoutMillis为-1。实际上是等待enqueueMessage的nativeWake来唤醒，如果非null，则下一步

  5. 判断msg的执行时间(when)是否比当前时间(now)的大，如果小，则将msg从队列中移除，并且 **返回msg**，结束。如果大则设置等待时间nextPollTimeoutMillis为(int) Math.min(msg.when - now, Integer.MAX_VALUE)，执行时间与当前时间的差与MAX_VALUE的较小值。执行下一步

  6. 判断是否MessageQueue是否已经取消，如果取消的话则返回null，否则下一步

  7. 运行idle Handle，idle表示当前有空闲时间的时候执行，而运行到这一步的时候，表示消息队列处理已经是出于空闲时间了（队列中没有Message，或者头部Message的执行时间(when)在当前时间之后）。如果没有idle，则继续step2，如果有则执行idleHandler的queueIdle方法，我们可以自己添加IdleHandler到MessageQueue里面（addIdleHandler方法），执行完后，回到step2。

# native

```java
@UnsupportedAppUsage
@SuppressWarnings("unused")
private long mPtr; // used by native code

// 它创建了一个native层的Looper, Looper通过epoll_create创建了一个mEpollFd作为epoll的fd，并且创建了一个mWakeEventFd，
// 用来监听java层的wake，同时可以通过Looper的addFd方法来添加新的fd监听。
private native static long nativeInit();
private native static void nativeDestroy(long ptr);
@UnsupportedAppUsage
private native void nativePollOnce(long ptr, int timeoutMillis); /*non-static for callbacks*/
private native static void nativeWake(long ptr);
private native static boolean nativeIsPolling(long ptr);
private native static void nativeSetFileDescriptorEvents(long ptr, int fd, int events);
```

## epoll 与 android
我们知道handler 异步主要是通过 nativeInit nativeWake nativePollOnce, 而 nativeInit 主要是初始化，通过nativePollOnce阻塞，nativeWake唤醒阻塞，这里边就是epoll机制，nativeInit 向内核注册了一个文件系统，文件系统会通过红黑树创建高速缓存区，用来监听添加的socket，如果有事件就绪，内核就会将这个socket放到就绪list中，也就是这里的 nativeWake， 而nativePollOnce 会调用 epoll_waite, 来读取就绪list中的数据

# 扩展
## 同步屏障

设置了同步屏障之后，next函数将会忽略所有的同步消息，返回异步消息。换句话说就是，设置了同步屏障之后，Handler只会处理异步消息。再换句话说，同步屏障为Handler消息机制增加了一种简单的优先级机制，异步消息的优先级要高于同步消息。直到撤销该同步屏障消息，同步消息才得以继续处理。
如果队列中没有异步消息，则loop()方法会被Linux epoll机制阻塞。
Android应用框架中为了更快的响应UI刷新事件在ViewRootImpl.scheduleTraversals中使用了同步屏障。
```java
void scheduleTraversals() {
    if (!mTraversalScheduled) {
        mTraversalScheduled = true;
        //设置同步障碍，确保mTraversalRunnable优先被执行
        mTraversalBarrier = mHandler.getLooper().getQueue().postSyncBarrier();
        //内部通过Handler发送了一个异步消息
        mChoreographer.postCallback(
                Choreographer.CALLBACK_TRAVERSAL, mTraversalRunnable, null);
        if (!mUnbufferedInputDispatch) {
            scheduleConsumeBatchedInput();
        }
        notifyRendererOfFramePending();
        pokeDrawLockIfNeeded();
    }
}
```
mTraversalRunnable调用了performTraversals执行measure、layout、draw。为了让mTraversalRunnable尽快被执行，在发消息之前调用MessageQueue.postSyncBarrier设置了同步屏障
