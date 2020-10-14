---
title: Input事件分析
toc: true
date: 2020-06-02 16:16:27
tags:
- android
categories:
- android
- 原理
---
前面我们已经介绍了Epoll机制，并且在Handler中也是利用的Epoll机制，现在介绍下 InputService，同样利用了Epoll

<!--more-->
# 创建

## InputManagerService 的创建
  Android Framework 层的 service，大部分都是在 SystemServer 进程中创建，InputManagerService 即是如此，
  创建完 进程中创建，InputManagerService 后，便把它加入到 ServiceManager 中，并同时设置了 InputMonitor，如下
```java
// SystemServer.startOtherServices
inputManager = new InputManagerService(context);
WindowManagerService wm = WindowManagerService.main(context, inputManager,
                    mFactoryTestMode != FactoryTest.FACTORY_TEST_LOW_LEVEL,
                    !mFirstBoot, mOnlyCore, new PhoneWindowManager());
ServiceManager.addService(Context.WINDOW_SERVICE, wm, /* allowIsolated= */ false,
                    DUMP_FLAG_PRIORITY_CRITICAL | DUMP_FLAG_PROTO);
ServiceManager.addService(Context.INPUT_SERVICE, inputManager,
                    /* allowIsolated= */ false, DUMP_FLAG_PRIORITY_CRITICAL);
mActivityManagerService.setWindowManager(wm);
inputManager.setWindowManagerCallbacks(wm.getInputMonitor());
inputManager.start();
```
## InputManagerservice 的构造
```java
public InputManagerService(Context context) {
    this.mContext = context;
    this.mHandler = new InputManagerHandler(DisplayThread.get().getLooper());

    mUseDevInputEventForAudioJack =
            context.getResources().getBoolean(R.bool.config_useDevInputEventForAudioJack);
    Slog.i(TAG, "Initializing input manager, mUseDevInputEventForAudioJack="
            + mUseDevInputEventForAudioJack);
    mPtr = nativeInit(this, mContext, mHandler.getLooper().getQueue());

    String doubleTouchGestureEnablePath = context.getResources().getString(
            R.string.config_doubleTouchGestureEnableFile);
    mDoubleTouchGestureEnableFile = TextUtils.isEmpty(doubleTouchGestureEnablePath) ? null :
        new File(doubleTouchGestureEnablePath);

    LocalServices.addService(InputManagerInternal.class, new LocalService());
}
```
在InputManagerServer的构造函数中创建了InputManagerHandler, 并且我们看到 nativeInit，参数是this、Context、MessageQueue
## nativeInit 的实现
```c++
static jlong nativeInit(JNIEnv* env, jclass /* clazz */,
        jobject serviceObj, jobject contextObj, jobject messageQueueObj) {
    sp<MessageQueue> messageQueue = android_os_MessageQueue_getMessageQueue(env, messageQueueObj);
    if (messageQueue == NULL) {
        jniThrowRuntimeException(env, "MessageQueue is not initialized.");
        return 0;
    }

    NativeInputManager* im = new NativeInputManager(contextObj, serviceObj,
            messageQueue->getLooper());
    im->incStrong(0);
    return reinterpret_cast<jlong>(im);
}
```
1. nativeInit中首先是获取 MessageQueue， 接着创建 NativeInputManager ，NativeInputManager 的实现如下
```C++
NativeInputManager::NativeInputManager(jobject contextObj,
        jobject serviceObj, const sp<Looper>& looper) :
        mLooper(looper), mInteractive(true) {
    JNIEnv* env = jniEnv();
     ...

    mInteractive = true;
    sp<EventHub> eventHub = new EventHub();
    mInputManager = new InputManager(eventHub, this, this);
}
```
2. NativeInputManager 中创建了 EventHub，并利用 EventHub 创建了InputManger， InputManager 实现如下
```c++
InputManager::InputManager(
        const sp<EventHubInterface>& eventHub,
        const sp<InputReaderPolicyInterface>& readerPolicy,
        const sp<InputDispatcherPolicyInterface>& dispatcherPolicy) {
    mDispatcher = new InputDispatcher(dispatcherPolicy);
    mReader = new InputReader(eventHub, readerPolicy, mDispatcher);
    initialize();
}
```
3. InputManager中创建了 InputDispatcher，接着创建了 InputReader，接着是 initialize 方法
```c++
void InputManager::initialize()
{
    mReaderThread = new InputReaderThread(mReader);
    mDispatcherThread = new InputDispatcherThread(mDispatcher);
}
```
4. InputManager分别将 reader 和 dispatcher 封装到相应的 Thread 中，此时对 SystemServer 来说，InputManager 基本创建完成.

5. 接着便是 start Service ，对应的 native 方法便是 nativeStart(mPtr)
```C++
static void nativeStart(JNIEnv* env, jclass /* clazz */, jlong ptr) {
    NativeInputManager* im = reinterpret_cast<NativeInputManager*>(ptr);

    status_t result = im->getInputManager()->start();
}
```
```c++
status_t InputManager::start() {
    status_t result = mDispatcherThread->run("InputDispatcher", PRIORITY_URGENT_DISPLAY);
    result = mReaderThread->run("InputReader", PRIORITY_URGENT_DISPLAY);
}
```
## UML结构
![InputManagerService](InputManagerService.jpg)

## 构造流程
![整体流程图](http://upload-images.jianshu.io/upload_images/16327616-789cc8d3db15cf8d?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

InputManger 通过 InputReaderThread 读和处理未加工的输入事件然后分发到 DispatcherThread 队列中， InputDispatcherThread 将接收的队列发送给相应的应用程序

## epoll

这里首先了解一下 epoll，之前我们处理输入流的时候，我们会对每一个流进行遍历，然后检测到有修改的数据，将其取出来，这其中存在大量的资源消耗，尤其是在流比较多的时候，epoll 便在这里优化，当无数据的时候会阻塞队列，当有数据的时候，只将其中有变化的进行分发。
详见: [epoll更详细的分析](https://pacoblack.github.io/2020/06/02/epoll%E5%8E%9F%E7%90%86%E4%BB%8B%E7%BB%8D/)

# 事件处理过程

### 流程概览
![具体流程图](http://upload-images.jianshu.io/upload_images/16327616-bba049140b690101?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

![整体流程图](http://upload-images.jianshu.io/upload_images/16327616-f00876a0a8171f40?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

在 NativeInputManager 中，曾经创建的EventHub，并作为参数传递给了 InputManger。EventHub是将不同来源的消息转化为统一类型并交给上层处理。主要就是控制InputThread和DispatchThread进行交互
### 初始化
```c++
EventHub::EventHub(void) :
      mBuiltInKeyboardId(NO_BUILT_IN_KEYBOARD), mNextDeviceId(1), mControllerNumbers(),
      mOpeningDevices(0), mClosingDevices(0),
      mNeedToSendFinishedDeviceScan(false),
      mNeedToReopenDevices(false), mNeedToScanDevices(true),
      mPendingEventCount(0), mPendingEventIndex(0), mPendingINotify(false) {

    acquire_wake_lock(PARTIAL_WAKE_LOCK, WAKE_LOCK_ID);
    //创建一个epoll句柄
    mEpollFd = epoll_create(EPOLL_SIZE_HINT);

    mINotifyFd = inotify_init();

    //监视dev/input目录的变化删除和创建变化
    int result = inotify_add_watch(mINotifyFd, DEVICE_PATH, IN_DELETE | IN_CREATE);

    struct epoll_event eventItem;
    memset(&eventItem, 0, sizeof(eventItem));
    eventItem.events = EPOLLIN;
    eventItem.data.u32 = EPOLL_ID_INOTIFY;

    //把inotify的句柄加入到epoll监测
    result = epoll_ctl(mEpollFd, EPOLL_CTL_ADD, mINotifyFd, &eventItem);

    //创建匿名管道
    int wakeFds[2];
    result = pipe(wakeFds);
    mWakeReadPipeFd = wakeFds[0];
    mWakeWritePipeFd = wakeFds[1];

    //将管道的读写端设置为非阻塞
    result = fcntl(mWakeReadPipeFd, F_SETFL, O_NONBLOCK);
    result = fcntl(mWakeWritePipeFd, F_SETFL, O_NONBLOCK);

    eventItem.data.u32 = EPOLL_ID_WAKE;

    //将管道的读端加入到epoll监测
    result = epoll_ctl(mEpollFd, EPOLL_CTL_ADD, mWakeReadPipeFd, &eventItem);

    int major, minor;
    getLinuxRelease(&major, &minor);
    // EPOLLWAKEUP was introduced in kerel 3.5
    mUsingEpollWakeup = major > 3 || (major == 3 && minor >= 5);
}
```
1. 创建了 epoll 句柄、inotify 句柄、匿名管道（非阻塞），inotify负责监控目录和文件的变化，这里监控的是/dev/input 目录。

2. EventHub中相关事件的处理由 ReaderThread 处理。ReaderThread 是继承Android 的 Thread。其中的主要方法是threadLoop，主要功能是从EventHub中获取事件，将事件发送给 InputDispater

```c++
bool InputReaderThread::threadLoop() {
    mReader->loopOnce();
    // true， 表示 threadLoop会被循环调用，也就是 loopOnce 会被循环调用
    return true;
}
```
```c++
void InputReader::loopOnce() {
      .....
    //从EventHub中获取事件
    size_t count = mEventHub->getEvents(timeoutMillis, mEventBuffer, EVENT_BUFFER_SIZE);

    { // acquire lock
        AutoMutex _l(mLock);
        mReaderIsAliveCondition.broadcast();
        //如果读到数据，处理事件数据
        if (count) {
            processEventsLocked(mEventBuffer, count);
        }

        if (mNextTimeout != LLONG_MAX) {
            nsecs_t now = systemTime(SYSTEM_TIME_MONOTONIC);
            if (now >= mNextTimeout) {
#if DEBUG_RAW_EVENTS
                ALOGD("Timeout expired, latency=%0.3fms", (now - mNextTimeout) * 0.000001f);
#endif
                mNextTimeout = LLONG_MAX;
                timeoutExpiredLocked(now);
            }
        }

        if (oldGeneration != mGeneration) {
            inputDevicesChanged = true;
            getInputDevicesLocked(inputDevices);
        }
    } // release lock

   //将排队的事件队列发送给监听者，实际上这个监听者就是Input dispatcher
    mQueuedListener->flush();
}
```
### getEvents
在loopOnce中有两个重要的方法 getEvents 和 processEventsLocked

```c++
size_t EventHub::getEvents(int timeoutMillis, RawEvent* buffer, size_t bufferSize) {
    RawEvent* event = buffer;
    size_t capacity = bufferSize;
     for(;;) {
        ....
      while (mPendingEventIndex < mPendingEventCount) {
         const struct epoll_event& eventItem = mPendingEventItems[mPendingEventIndex++];
        .....
       ssize_t deviceIndex = mDevices.indexOfKey(eventItem.data.u32);
     if (eventItem.events & EPOLLIN) {
         int32_t readSize = read(device->fd, readBuffer,
                        sizeof(struct input_event) * capacity);
        if (readSize == 0 || (readSize < 0 && errno == ENODEV)) {
           // 设备被移除，关闭设备
           deviceChanged = true;
           closeDeviceLocked(device);
         } else if (readSize < 0) {
             //无法获得事件
             if (errno != EAGAIN && errno != EINTR) {
                 ALOGW("could not get event (errno=%d)", errno);
             }
         } else if ((readSize % sizeof(struct input_event)) != 0) {
            //获得事件的大小非事件类型整数倍
            ALOGE("could not get event (wrong size: %d)", readSize);
       } else {
           int32_t deviceId = device->id == mBuiltInKeyboardId ? 0 : device->id;
          //计算读入了多少事件
           size_t count = size_t(readSize) / sizeof(struct input_event);
           for (size_t i = 0; i < count; i++) {
               struct input_event& iev = readBuffer[i];
               if (iev.type == EV_MSC) {
                 if (iev.code == MSC_ANDROID_TIME_SEC) {
                     device->timestampOverrideSec = iev.value;
                     continue;
                  } else if (iev.code == MSC_ANDROID_TIME_USEC) {
                     device->timestampOverrideUsec = iev.value;
                     continue;
                  }
               }
              //事件时间相关计算，时间的错误可能会导致ANR和一些bug。这里采取一系列的防范
               .........
             event->deviceId = deviceId;
             event->type = iev.type;
             event->code = iev.code;
             event->value = iev.value;
             event += 1;
             capacity -= 1;
          }
        if (capacity == 0) {
          //每到我们计算完一个事件，capacity就会减1，如果为0。则表示  结果缓冲区已经满了，
      //需要重置开始读取时间的索引值，来读取下一个事件迭代                    
           mPendingEventIndex -= 1;
           break;
      }
 }
    //表明读到事件了，跳出循环
    if (event != buffer || awoken) {
            break;
     }
     mPendingEventIndex = 0;
     int pollResult = epoll_wait(mEpollFd, mPendingEventItems, EPOLL_MAX_EVENTS, timeoutMillis);
       if (pollResult == 0) {
          mPendingEventCount = 0;
          break;
       }
      //判断是否有事件发生
       if (pollResult < 0) {
          mPendingEventCount = 0;
        } else {
            //产生的事件的数目
          mPendingEventCount = size_t(pollResult);
        }
    }
    //产生的事件数目
    return event - buffer;
}
```
```c++
void InputReader::processEventsLocked(const RawEvent* rawEvents, size_t count) {
    for (const RawEvent* rawEvent = rawEvents; count;) {
        int32_t type = rawEvent->type;
        size_t batchSize = 1;
        if (type < EventHubInterface::FIRST_SYNTHETIC_EVENT) {
            int32_t deviceId = rawEvent->deviceId;
            while (batchSize < count) {
                if (rawEvent[batchSize].type >= EventHubInterface::FIRST_SYNTHETIC_EVENT
                        || rawEvent[batchSize].deviceId != deviceId) {
                    break;
                }
                batchSize += 1;
            }
            processEventsForDeviceLocked(deviceId, rawEvent, batchSize);
        } else {
            switch (rawEvent->type) {
            case EventHubInterface::DEVICE_ADDED:
                addDeviceLocked(rawEvent->when, rawEvent->deviceId);
                break;
            case EventHubInterface::DEVICE_REMOVED:
                removeDeviceLocked(rawEvent->when, rawEvent->deviceId);
                break;
            case EventHubInterface::FINISHED_DEVICE_SCAN:
                handleConfigurationChangedLocked(rawEvent->when);
                break;
            default:
                ALOG_ASSERT(false); // can't happen
                break;
            }
        }
        count -= batchSize;
        rawEvent += batchSize;
    }
}
```

- `getEvents` 方法会进行一些新增设备和移除设备的更新操作。至于点击事件是通过指针参数 RawEvent, 其作为起始地址记录事件，在循环体中，处理获取时间、检测相关设备类型、读取事件，如果检测到事件，则跳出循环。更新 mPendingEventCount 和 mPendingEventIndex 来控制事件的读取，epoll_wait 来得到事件的来源。
- `processEventsLocked` 在 looperOnce 获取到事件后，会被调用. 其负责事件添加、设备移除等，事件相关还有 processEventsForDeviceLocked 方法，根据事件获取相应的设备类型，并交给相应的设备处理，即 InputMapper 。
![InputMapper及其子类](http://upload-images.jianshu.io/upload_images/16327616-2fbdda7840e38fc9?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

### processEventsLocked
分发到对应的mapper后，事件会被 mapper.process 处理

```c++
void TouchInputMapper::process(const RawEvent* rawEvent) {
    mCursorButtonAccumulator.process(rawEvent);
    mCursorScrollAccumulator.process(rawEvent);
    mTouchButtonAccumulator.process(rawEvent);

    if (rawEvent->type == EV_SYN && rawEvent->code == SYN_REPORT) {
        sync(rawEvent->when);
    }
}
void TouchInputMapper::sync(nsecs_t when) {
    .....
    processRawTouches(false /*timeout*/);
}
void TouchInputMapper::dispatchTouches(nsecs_t when, uint32_t policyFlags) {
      ....
    dispatchMotion();
      ....
}
void TouchInputMapper::dispatchMotion() {
   ....
   NotifyMotionArgs args(when, getDeviceId(), source, policyFlags,
            action, actionButton, flags, metaState, buttonState, edgeFlags,
            mViewport.displayId, pointerCount, pointerProperties, pointerCoords,
            xPrecision, yPrecision, downTime);
    getListener()->notifyMotion(&args);
}
```
```c++
InputListenerInterface* InputReader::ContextImpl::getListener() {
    return mReader->mQueuedListener.get();
}
```
```c++
void QueuedInputListener::notifyMotion(const NotifyMotionArgs* args) {
    mArgsQueue.push(new NotifyMotionArgs(*args));
}
```
将数据加入到参数队列ArgsQueue中，至此 processEventsLocked 执行完成

### flush
1. 执行 loopOnce 中后面的方法，也就是 QueuedInputListener 的 flush 方法
```c++
void QueuedInputListener::flush() {
    size_t count = mArgsQueue.size();
    for (size_t i = 0; i < count; i++) {
        NotifyArgs* args = mArgsQueue[i];
        args->notify(mInnerListener);
        delete args;
    }
    mArgsQueue.clear();
}
```
```C++
void NotifyMotionArgs::notify(const sp<InputListenerInterface>& listener) const {
    listener->notifyMotion(this);
}
```
```C++
void InputDispatcher::notifyMotion(const NotifyMotionArgs* args) {
    .....
   MotionEvent event;
   event.initialize(args->deviceId, args->source, args->action, args->actionButton,
                    args->flags, args->edgeFlags, args->metaState, args->buttonState,
                    0, 0, args->xPrecision, args->yPrecision,
                    args->downTime, args->eventTime,
                    args->pointerCount, args->pointerProperties, args->pointerCoords);
    ....
  MotionEntry* newEntry = new MotionEntry(args->eventTime,
                args->deviceId, args->source, policyFlags,
                args->action, args->actionButton, args->flags,
                args->metaState, args->buttonState,
                args->edgeFlags, args->xPrecision, args->yPrecision, args->downTime,
                args->displayId,
                args->pointerCount, args->pointerProperties, args->pointerCoords, 0, 0);
   needWake = enqueueInboundEventLocked(newEntry);
    ....
   if (needWake) {
      mLooper->wake();
   }
}
```

2. 在 notifyMotion 中将参数包装成 MotionEntry，加入到 enqueueInboundEventLocked 中，然后唤醒 looper。
在前面的InputReaderThread中，有threadLoop，在Dispatcher 下的也有threadLoop，循环调用的是 dispatchOnce

```c++
bool InputDispatcherThread::threadLoop() {
    mDispatcher->dispatchOnce();
    return true;
}
void InputDispatcher::dispatchOnce() {
    ...
   dispatchOnceInnerLocked(&nextWakeupTime);
    ...
}
void InputDispatcher::dispatchOnceInnerLocked(nsecs_t* nextWakeupTime) {
   ....
   mPendingEvent = mInboundQueue.dequeueAtHead();
   ....
   switch (mPendingEvent->type) {
        case EventEntry::TYPE_MOTION: {
        MotionEntry* typedEntry = static_cast<MotionEntry*>(mPendingEvent);
        if (dropReason == DROP_REASON_NOT_DROPPED && isAppSwitchDue) {
            dropReason = DROP_REASON_APP_SWITCH;
        }
        if (dropReason == DROP_REASON_NOT_DROPPED
                && isStaleEventLocked(currentTime, typedEntry)) {
            dropReason = DROP_REASON_STALE;
        }
        if (dropReason == DROP_REASON_NOT_DROPPED && mNextUnblockedEvent) {
            dropReason = DROP_REASON_BLOCKED;
        }
        done = dispatchMotionLocked(currentTime, typedEntry,
                &dropReason, nextWakeupTime);
        break;
    }
    ....
   }
}
void InputDispatcher::dispatchEventLocked(nsecs_t currentTime,
    EventEntry* eventEntry, const Vector<InputTarget>& inputTargets) {
    ....
    pokeUserActivityLocked(eventEntry);
    .....
    for (size_t i = 0; i < inputTargets.size(); i++) {
        const InputTarget& inputTarget = inputTargets.itemAt(i);

        ssize_t connectionIndex = getConnectionIndexLocked(inputTarget.inputChannel);
        if (connectionIndex >= 0) {
            sp<Connection> connection = mConnectionsByFd.valueAt(connectionIndex);
            prepareDispatchCycleLocked(currentTime, connection, eventEntry, &inputTarget);
        }
    }
}
```

3. prepareDispatchCycleLocked 调用 enqueueDispatchEntriesLocked 调用  startDispatchCycleLocked

```c++
void InputDispatcher::startDispatchCycleLocked(nsecs_t currentTime,
        const sp<Connection>& connection) {
   EventEntry* eventEntry = dispatchEntry->eventEntry;
    ....
   switch (eventEntry->type) {
      ....
    case EventEntry::TYPE_MOTION: {
      status = connection->inputPublisher.publishMotionEvent( ....);    
      break;
    }
    ....
   }
    ...
}
```
```C++
status_t InputPublisher::publishMotionEvent(...) {
  ....
  InputMessage msg;
  msg.header.type = InputMessage::TYPE_MOTION;
  msg.body.motion.seq = seq;
  msg.body.motion.deviceId = deviceId;
  msg.body.motion.source = source;
  msg.body.motion.action = action;
  msg.body.motion.actionButton = actionButton;
  msg.body.motion.flags = flags;
  msg.body.motion.edgeFlags = edgeFlags;
  msg.body.motion.metaState = metaState;
  msg.body.motion.buttonState = buttonState;
  msg.body.motion.xOffset = xOffset;
  msg.body.motion.yOffset = yOffset;
  msg.body.motion.xPrecision = xPrecision;
  msg.body.motion.yPrecision = yPrecision;
  msg.body.motion.downTime = downTime;
  msg.body.motion.eventTime = eventTime;
  msg.body.motion.pointerCount = pointerCount;
  for (uint32_t i = 0; i < pointerCount; i++) {
      msg.body.motion.pointers[i].properties.copyFrom(pointerProperties[i]);
      msg.body.motion.pointers[i].coords.copyFrom(pointerCoords[i]);
  }
    return mChannel->sendMessage(&msg);
}
```
此方法所执行的操作是利用传入的触摸信息，构建点击消息，然后通过InputChannel将消息发送到 FrameWork 层。这里引出了InputChannel。

### 小结
我们在 EventHub 中 创建了 ReaderThread，RenderThread 开启后会从EventHub轮训获取时间，获取事件后，经过一系列的封装，通过 InputChannel 发送出去

# InputChannel 处理过程
既然事件最终是通过 InputChannel 发送出去，那么我们继续追踪 InputChannel。

## 注册InputChannel

1. 在 InputManagerService 中 registerInputChannel

```java
public void registerInputChannel(InputChannel inputChannel,
            InputWindowHandle inputWindowHandle) {
   if (inputChannel == null) {
      throw new IllegalArgumentException("inputChannel must not be null.");
   }
   nativeRegisterInputChannel(mPtr, inputChannel, inputWindowHandle, false);
}
```

```java
static void nativeRegisterInputChannel(JNIEnv* env, jclass /* clazz */,
        jlong ptr, jobject inputChannelObj, jobject inputWindowHandleObj, jboolean monitor) {
    NativeInputManager* im = reinterpret_cast<NativeInputManager*>(ptr);

    sp<InputChannel> inputChannel = android_view_InputChannel_getInputChannel(env,
            inputChannelObj);
    if (inputChannel == NULL) {
        throwInputChannelNotInitialized(env);
        return;
    }

    sp<InputWindowHandle> inputWindowHandle =
            android_server_InputWindowHandle_getHandle(env, inputWindowHandleObj);

    status_t status = im->registerInputChannel(
            env, inputChannel, inputWindowHandle, monitor);
    if (status) {
        String8 message;
        message.appendFormat("Failed to register input channel.  status=%d", status);
        jniThrowRuntimeException(env, message.string());
        return;
    }

    if (! monitor) {
        android_view_InputChannel_setDisposeCallback(env, inputChannelObj,
                handleInputChannelDisposed, im);
    }
}
```

2. NativeInputManager 的 registerInputChannel 会调用到 InputDispatcher 的 registerInputChannel，通过 InputChannel 创建相应的 Connection ，同时将InputChannel加入到 InputManager 中。上面的 InputChannel 获取

```c++
status_t InputDispatcher::registerInputChannel(const sp<InputChannel>& inputChannel,
        const sp<InputWindowHandle>& inputWindowHandle, bool monitor) {
    { // acquire lock
        AutoMutex _l(mLock);

        if (getConnectionIndexLocked(inputChannel) >= 0) {
            ALOGW("Attempted to register already registered input channel '%s'",
                    inputChannel->getName().string());
            return BAD_VALUE;
        }

        sp<Connection> connection = new Connection(inputChannel, inputWindowHandle, monitor);

        int fd = inputChannel->getFd();
        mConnectionsByFd.add(fd, connection);

        if (monitor) {
            mMonitoringChannels.push(inputChannel);
        }

        mLooper->addFd(fd, 0, ALOOPER_EVENT_INPUT, handleReceiveCallback, this);
    } // release lock

    // Wake the looper because some connections have changed.
    mLooper->wake();
    return OK;
}
```

3. InputReaderThread 和 InputDispatcherThread 是运行在 SystemServer 进程中的，而我们的应用进程是和其不在同一个进程中的。这之间一定也是有进程间的通信机制在里面。即 ViewRootImpl 的 setView 方法中

```java
public void setView(View view, WindowManager.LayoutParams attrs, View panelParentView) {
    ....
  if ((mWindowAttributes.inputFeatures
                        & WindowManager.LayoutParams.INPUT_FEATURE_NO_INPUT_CHANNEL) == 0) {
       mInputChannel = new InputChannel();
   }
  ....
  res = mWindowSession.addToDisplay(mWindow, mSeq, mWindowAttributes,
                            getHostVisibility(), mDisplay.getDisplayId(),
                            mAttachInfo.mContentInsets, mAttachInfo.mStableInsets,
                            mAttachInfo.mOutsets, mInputChannel);
  ....
}
```

## 连接 Window 和 SystemServer

```java
// WindowManagerService.java
 public int addWindow(Session session, IWindow client, int seq,
            WindowManager.LayoutParams attrs, int viewVisibility, int displayId,
            Rect outContentInsets, Rect outStableInsets, Rect outOutsets,
            InputChannel outInputChannel) {
      ....

      final boolean openInputChannels = (outInputChannel != null
                    && (attrs.inputFeatures & INPUT_FEATURE_NO_INPUT_CHANNEL) == 0);
      if  (openInputChannels) {
          win.openInputChannel(outInputChannel);
      }
      ....
}
```
```java
void openInputChannel(InputChannel outInputChannel) {
    if (mInputChannel != null) {
        throw new IllegalStateException("Window already has an input channel.");
     }
     String name = makeInputChannelName();
     InputChannel[] inputChannels = InputChannel.openInputChannelPair(name);
     mInputChannel = inputChannels[0];
     mClientChannel = inputChannels[1];
     mInputWindowHandle.inputChannel = inputChannels[0];
     if (outInputChannel != null) {
       mClientChannel.transferTo(outInputChannel);
       mClientChannel.dispose();
       mClientChannel = null;
      } else {
         mDeadWindowEventReceiver = new DeadWindowEventReceiver(mClientChannel);
      }
       mService.mInputManager.registerInputChannel(mInputChannel, mInputWindowHandle);
}
```
```c++
status_t InputChannel::openInputChannelPair(const String8& name,
        sp<InputChannel>& outServerChannel, sp<InputChannel>& outClientChannel) {
    int sockets[2];
    if (socketpair(AF_UNIX, SOCK_SEQPACKET, 0, sockets)) {
        status_t result = -errno;
        ALOGE("channel '%s' ~ Could not create socket pair.  errno=%d",
                name.string(), errno);
        outServerChannel.clear();
        outClientChannel.clear();
        return result;
    }

    int bufferSize = SOCKET_BUFFER_SIZE;
    setsockopt(sockets[0], SOL_SOCKET, SO_SNDBUF, &bufferSize, sizeof(bufferSize));
    setsockopt(sockets[0], SOL_SOCKET, SO_RCVBUF, &bufferSize, sizeof(bufferSize));
    setsockopt(sockets[1], SOL_SOCKET, SO_SNDBUF, &bufferSize, sizeof(bufferSize));
    setsockopt(sockets[1], SOL_SOCKET, SO_RCVBUF, &bufferSize, sizeof(bufferSize));

    String8 serverChannelName = name;
    serverChannelName.append(" (server)");
    outServerChannel = new InputChannel(serverChannelName, sockets[0]);

    String8 clientChannelName = name;
    clientChannelName.append(" (client)");
    outClientChannel = new InputChannel(clientChannelName, sockets[1]);
    return OK;
}
```
**这里创建两个 Socket，设置为读写双端，然后根据 socket，创建出连两个InputChannel，一个 Server，一个Client。这样在SystemServer进程和应用进程间的InputChannel的通信就可以连接，由于两个channel不在同一个进程中，这里进程通信则是通过socket来进行。在sendMessage和receiveMessage中，通过对Socket的写，读操作来实现消息的传递。**
```c++
status_t InputChannel::sendMessage(const InputMessage* msg) {
    size_t msgLength = msg->size();
    ssize_t nWrite;
    do {
        nWrite = ::send(mFd, msg, msgLength, MSG_DONTWAIT | MSG_NOSIGNAL);
    } while (nWrite == -1 && errno == EINTR);

    if (nWrite < 0) {
        int error = errno;
        if (error == EAGAIN || error == EWOULDBLOCK) {
            return WOULD_BLOCK;
        }
        if (error == EPIPE || error == ENOTCONN || error == ECONNREFUSED || error == ECONNRESET) {
            return DEAD_OBJECT;
        }
        return -error;
    }

    if (size_t(nWrite) != msgLength) {
        return DEAD_OBJECT;
    }
    return OK;
}

status_t InputChannel::receiveMessage(InputMessage* msg) {
    ssize_t nRead;
    do {
        nRead = ::recv(mFd, msg, sizeof(InputMessage), MSG_DONTWAIT);
    } while (nRead == -1 && errno == EINTR);

    if (nRead < 0) {
        int error = errno;
        if (error == EAGAIN || error == EWOULDBLOCK) {
            return WOULD_BLOCK;
        }
        if (error == EPIPE || error == ENOTCONN || error == ECONNREFUSED) {
            return DEAD_OBJECT;
        }
        return -error;
    }

    if (nRead == 0) { // check for EOF
        return DEAD_OBJECT;
    }

    if (!msg->isValid(nRead)) {
        return BAD_VALUE;
    }
    return OK;
}
```
这样，ViewRootImpl.WindowInputEventReceiver 便可以接收输入事件

## InputEventReceiver

下面来分析一下 InputEventReceiver 中的 nativeInit 方法
```c++
static jlong nativeInit(JNIEnv* env, jclass clazz, jobject receiverWeak,
        jobject inputChannelObj, jobject messageQueueObj) {
   ....
  sp<InputChannel> inputChannel = android_view_InputChannel_getInputChannel(env,
            inputChannelObj);
  sp<MessageQueue> messageQueue = android_os_MessageQueue_getMessageQueue(env, messageQueueObj);
  sp<NativeInputEventReceiver> receiver = new NativeInputEventReceiver(env,
            receiverWeak, inputChannel, messageQueue);
    status_t status = receiver->initialize();
  .....
}
```
```C++
status_t NativeInputEventReceiver::initialize() {
    setFdEvents(ALOOPER_EVENT_INPUT);
    return OK;
}
void NativeInputEventReceiver::setFdEvents(int events) {
    if (mFdEvents != events) {
        mFdEvents = events;
        int fd = mInputConsumer.getChannel()->getFd();
        if (events) {
            mMessageQueue->getLooper()->addFd(fd, 0, events, this, NULL);
        } else {
            mMessageQueue->getLooper()->removeFd(fd);
        }
    }
}
```
```C++
int ALooper_addFd(ALooper* looper, int fd, int ident, int events,
        ALooper_callbackFunc callback, void* data) {
    return ALooper_to_Looper(looper)->addFd(fd, ident, events, callback, data);
}
```
```C++
int Looper::addFd(int fd, int ident, int events, const sp<LooperCallback>& callback, void* data) {
    Request request;
    request.fd = fd;
    request.ident = ident;
    request.events = events;
    request.seq = mNextRequestSeq++;
    request.callback = callback;
     request.data = data;
     if (mNextRequestSeq == -1) mNextRequestSeq = 0;
     struct epoll_event eventItem;
     request.initEventItem(&eventItem);
     ssize_t requestIndex = mRequests.indexOfKey(fd);
      if (requestIndex < 0) {
          int epollResult = epoll_ctl(mEpollFd, EPOLL_CTL_ADD, fd, & eventItem);
          if (epollResult < 0) {
                return -1;
            }
         mRequests.add(fd, request);
       }
}
```

addFd 就是对传递的 fd 添加 epoll 监控，Looper 会循环调用 pollOnce，而pollOnce方法的核心实现就是pollInner 。其代码大致实现内容为等待消息的到来，当有消息到来后，根据消息类型做一些判断处理，然后调用其相关的callback。我们当前是对于开启的socket的一个监听，当有数据到来，我们便会执行相应的回调。这里对于InputChannel的回调是在调用了 NativeInputEventReceiver的handleEvent方法。

```C++
int NativeInputEventReceiver::handleEvent(int receiveFd, int events, void* data) {
    .....
   if (events & ALOOPER_EVENT_INPUT) {
        JNIEnv* env = AndroidRuntime::getJNIEnv();
        status_t status = consumeEvents(env, false /*consumeBatches*/, -1, NULL);
        mMessageQueue->raiseAndClearException(env, "handleReceiveCallback");
        return status == OK || status == NO_MEMORY ? 1 : 0;
    }
    ....
    return 1;
}
status_t NativeInputEventReceiver::consumeEvents(JNIEnv* env,
        bool consumeBatches, nsecs_t frameTime, bool* outConsumedBatch) {
    ...
    for(;;) {
      ...
     InputEvent* inputEvent;
     status_t status = mInputConsumer.consume(&mInputEventFactory,
                consumeBatches, frameTime, &seq, &inputEvent);
        ...
    }
   ...
}
```
```C++
status_t InputConsumer::consume(InputEventFactoryInterface* factory,
        bool consumeBatches, nsecs_t frameTime, uint32_t* outSeq, InputEvent** outEvent) {
    while (!*outEvent) {
         ....
         status_t result = mChannel->receiveMessage(&mMsg);
          ....
    }
}
```
调用 consume 方法会持续的调用 InputChannel 的 receiveMessage 方法来从 socket 中读取数据。到这里，我们已经将写入socket的事件读出来了。接下来就会通过 ViewRootImpl 将事件派发到 Activity 中去。
![事件派发原理图](http://upload-images.jianshu.io/upload_images/16327616-740fdbafdfa48224?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

## 总结
在 SystemServer 进程通过epoll 监听 input，在用户进程创建window的时候注册channel，channel通过socket进行进程间通信，InputConsumer 通过consume 发送到用户activity消费输入事件

# 应用层处理
上节说到，native层会通过 InputChannel 通过 socket 通信，将 Touch 事件发送到应用层，在 ViewRootImpl 的  setView  方法中，requestLayout 之后就会创建一个 inputChannel，在调用的  mWindowSession.addToDisplay  中，inputChannel 就是其中的一个参数。同时也是 WindowInputEventReceiver 的构造参数。 WindowInputEventReceiver 是 ViewRootImpl 的内部类，继承了 InputEventReceiver， 并重写了 onInputEvent 方法，通过 onInputEvent 方法将Touch事件交给了 应用层，结合Android 结构视图就可以分析出事件的分发顺序

![TouchEvent传递](touchEvent.jpg)

参考：
https://segmentfault.com/a/1190000011826846
