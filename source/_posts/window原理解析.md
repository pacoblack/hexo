---
title: window原理解析
toc: true
date: 2020-10-14 17:30:14
tags:
- android
categories:
- android
---
分析下window原理
<!--more-->
# Touch简介
![Activity与Window.jpg](https://raw.githubusercontent.com/pacoblack/BlogImages/master/touch/touch2.jpg)

我们已知[touch 事件起始](https://www.jianshu.com/p/1c127769c9ea)是 Activity -> PhoneWindow -> DecorView -> (TitleView + ContentView) 传递的，但是这个touch事件的源头是哪里呢，是从Window中获取的

这里我们只关注Window相关。
# Window介绍
![window关系图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/touch/touch3.png)
## UI显示过程的三个进程
Android显示的整个过程由App进程、System_server进程、SurfaceFlinger进程一起配合完成。

- App进程： App需要将自己的内容显示在屏幕上，所以需要负责发起Surface创建的请求。同时触发对控件的测量、布局、绘制以及输入事件的派发处理，这些主要在ViewRootImpl中触发；

- System_server进程： 主要是WindowManagerService，负责接收App请求，同时和SurfaceFlinger建立连接，向SurfaceFlinger发起具体请求创建Surface，并且创建Surace的辅助管理类SurfaceControl（和window一一对应）(AMS作用是统一调度所有App的Activity）；
- SurfaceFlinger： 为App创建具体的Surface，在SurfaceFLinger对应成Layer，然后负责管理、合成所有图层，最终显示。
![整体流程](window_all.png)
![调用流程](window_call.png)

## WindowManager
Android中基本上**所有的View都是通过Window来呈现的**，不管是Activity、Toast还是Dialog，它们的视图都是附加到Window上的，因此可以将Window理解为View的承载者与直接管理者。而Window需要WindowManager协助完成，这里它的实现类是 WindowManagerImpl . 而 WindowManagerImpl 通过 getSystemService(Context.WINDOW_SERVICE) 来得到。

## WindowManagerService
WindowManagerService 位于 Framework 层的窗口管理服务，它的职责就是管理系统中的所有窗口，负责协调Window的层级、显示及事件派发等。可以这样理解，**WindowManager 是本地端的管理者，负责与 WindowManagerService 进行交互**，从而使Window能层次分明的显示出来。WindowManager 与 WindowManagerService 的交互是一个IPC过程。
WindowManagerService 会在 SystemServer 启动的时候创建，并注册到 ServiceManager 中。

## WindowManagerGlobal
WindowManagerImpl 是 WindowManager 的实现类，但实际上它的工作基本委托给了 WindowManagerGlobal 类来完成。 WindowManagerGlobal 实现了 WindowManagerImpl 的功能，并对 View、ViewRootImpl 以及LayoutParams 进行管理
```
mViews：存储了所有Window所对应的View
mRoots：存储了所有Window所对应的ViewRootImpl
mParams：存储了所有Window所对应的布局参数
mDyingViews：存储的是即将被删除的View对象或正在被删除的View对象
```
# Window分析
Window 有三种类型，分别是应用 Window、子 Window 和系统 Window。应用类 Window 对应一个 Acitivity，子 Window 不能单独存在，需要依附在特定的父 Window 中，比如常见的一些 Dialog 就是一个子 Window。系统 Window是需要声明权限才能创建的 Window，比如 Toast 和系统状态栏都是系统 Window。
Window 是分层的，每个 Window 都有对应的 z-ordered，层级大的会覆盖在层级小的 Window 上面，这和 HTML 中的 z-index 概念是完全一致的。在三种 Window 中，应用 Window 层级范围是 1~99，子 Window 层级范围是 1000~1999，系统 Window 层级范围是 2000~2999。

## WindowManager
WindowManager  继承自 ViewManager
```
public interface ViewManager{
    public void addView(View view, ViewGroup.LayoutParams params);
    public void updateViewLayout(View view, ViewGroup.LayoutParams params);
    public void removeView(View view);
}
```
可以用来添加和删除 View，但是在实际使用中无法直接访问 Window，对 Window 的访问必须通过 WindowManager，它的实现类是WindowMagerImpl，具体的添加删除View 都是委托给了 WindowManagerGlobal。

## addView
具体过程如下：
1. 检查合法性
```
 public void addView(View view, ViewGroup.LayoutParams params,
            Display display, Window parentWindow) {
        if (view == null) {
            throw new IllegalArgumentException("view must not be null");
        }
        if (display == null) {
            throw new IllegalArgumentException("display must not be null");
        }
        if (!(params instanceof WindowManager.LayoutParams)) {
            throw new IllegalArgumentException("Params must be WindowManager.LayoutParams");
        }

        final WindowManager.LayoutParams wparams = (WindowManager.LayoutParams) params;
        if (parentWindow != null) {
            parentWindow.adjustLayoutParamsForSubWindow(wparams);
        } else {
            // If there's no parent, then hardware acceleration for this view is
            // set from the application's hardware acceleration setting.
            final Context context = view.getContext();
            if (context != null
                    && (context.getApplicationInfo().flags
                            & ApplicationInfo.FLAG_HARDWARE_ACCELERATED) != 0) {
                wparams.flags |= WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED;
            }
        }
     ...
}
```
2. 创建 ViewRootImpl，并将View 添加到集合中
```
// WindowManagerGlobal 中几个重要的集合
private final ArrayList<View> mViews = new ArrayList<View>();
private final ArrayList<ViewRootImpl> mRoots = new ArrayList<ViewRootImpl>();
private final ArrayList<WindowManager.LayoutParams> mParams = new ArrayList<WindowManager.LayoutParams>();
private final ArraySet<View> mDyingViews = new ArraySet<View>();
```
| 集合| 存储内容 |
| ------ | ------- |
| mViews | Window 对应的 View |
| mRoots | Window 对应的 ViewRootImpl |
| mParams | Window 对应的布局参数 |
| mDyingViews | 正在被删除的 View |
```
synchronized (mLock) {
    ...
    root = new ViewRootImpl(view.getContext(), display);
    view.setLayoutParams(wparams);

     mViews.add(view);
     mRoots.add(root);
     mParams.add(wparams);
     ...
}
```
3. 通过 ViewRootImpl 来更新界面并完成 Window 的添加过程
ViewRootImpl 不是View，实际上是顶级View的管理者。每一个 ViewRootImpl 都对应着一个ViewTree ，通过它来完成 View 的绘制及显示过程。下图展示了它与WM、WMS之间的关系:
![ViewRootImpl 关系图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/touch/touch4.png)

Window是一个抽象的概念，**每一个Window都对应着一个 View 和 ViewRootImpl ，Window与View通过 ViewRootImpl 建立起联系**，Window 是以 View 作为实体存在，实际使用WindowManager访问来Window，外部无法直接访问Window。

## setView
ViewRootImpl 会通过 setView来完成界面的更新，实现 View 的添加。
setView 会执行 View 的绘制 ，

```
    public void setView(View view, WindowManager.LayoutParams attrs, View panelParentView) {
        synchronized (this) {
         ...
         requestLayout();
         ...
         res = mWindowSession.addToDisplay(mWindow, mSeq, mWindowAttributes,
                            getHostVisibility(), mDisplay.getDisplayId(), mWinFrame,
                            mAttachInfo.mContentInsets, mAttachInfo.mStableInsets,
                            mAttachInfo.mOutsets, mAttachInfo.mDisplayCutout, mInputChannel);
         ...
        }
    }
    @Override
    public void requestLayout() {
        if (!mHandlingLayoutInLayoutRequest) {
            checkThread();
            mLayoutRequested = true;
            scheduleTraversals();
        }
    }
```
调用栈为
setView -> requestLayout -> scheduleTraversals -> doTraversal (mTraversalRunnable) -> performTraversal

## performTraversal
performTranversal 主要工作
```
dispatchAttachedToWindow -> onAttachedToWindow // 第一次添加时调用
executeActions // 执行 attach view 中 post 的 Runnable action
relayoutWindow //  请求 WindowManagerService 来计算窗体大小，内容区域等。
performMeasure -> measure -> onMeasure // 递归执行测量
performLayout -> layout -> onLayout //  递归执行布局
performDraw -> draw -> onDraw // 递归执行绘制
```
这里我们看到了熟悉的 onMeasure onLayout onDraw
执行完 requestLayout 之后，便是 mWindowSession 的工作。mWindowSession的类型是IWindowSession，它是一个Binder对象，真正的实现类是Session，因此 Window 的添加的过程是一个IPC调用

## addToDisplay
```
res = mWindowSession.addToDisplay(mWindow, mSeq, mWindowAttributes,
                            getHostVisibility(), mDisplay.getDisplayId(), mWinFrame,
                            mAttachInfo.mContentInsets, mAttachInfo.mStableInsets,
                            mAttachInfo.mOutsets, mAttachInfo.mDisplayCutout, mInputChannel);
```
addToDisplay 中Session 会通过 addWindow 方法将 Window 添加到 WindowManagerService 中，WindowManagerService会为每个应用保留一个单独的Session。
![委托流程](https://raw.githubusercontent.com/pacoblack/BlogImages/master/touch/touch5.png)
最终，Window 的添加请求移交给 WindowManagerService 手上。

## removeView
删除与添加类似，具体流程可以查看源码。

值得注意的是，删除操作是由ViewRootImpl来完成的，删除分为两种，分别为同步删除（removeViewImmediate）和异步删除（removeView）,在ViewRootImpl的die（immediate）方法中进行判断。如果为同步则直接调用doDie方法进行删除，否则会发送一个消息进行异步处理，同时执行mDyingViews.add(view)
最终的删除操作还是交给Session: mWindowSession.remove(mWindow)，此过程是一个IPC过程，最终会调用WindowManagerService的removeWindow方法。

# 普通Window创建
我们知道 Activity 开始应用是从 attach 开始的。这里除了attachContext 外，就是Window的初始化在`performLaunchActivity()` ->`Activity.attach()` 方法中
```
mWindow = new PhoneWindow(this, window, activityConfigCallback);
Window.setWindowControllerCallback(this);
mWindow.setCallback(this);
mWindow.setOnWindowDismissedCallback(this);
mWindow.getLayoutInflater().setPrivateFactory(this);
if (info.softInputMode != WindowManager.LayoutParams.SOFT_INPUT_STATE_UNSPECIFIED) {
      mWindow.setSoftInputMode(info.softInputMode);
}
if (info.uiOptions != 0) {
      mWindow.setUiOptions(info.uiOptions);
}
...
mWindow.setWindowManager(
                (WindowManager)context.getSystemService(Context.WINDOW_SERVICE),
                mToken, mComponent.flattenToString(),
                (info.flags & ActivityInfo.FLAG_HARDWARE_ACCELERATED) != 0);
if (mParent != null) {
       mWindow.setContainer(mParent.getWindow());
}
```
这里为我们注备好了 Window，接下来是将Activity 附属到Window上，而Activity视图是有 setContentView 提供的。
```
   // Activity.java
   public void setContentView(@LayoutRes int layoutResID) {
        getWindow().setContentView(layoutResID);
        initWindowDecorActionBar();
    }
    // PhoneWindow.java
    @Override
    public void setContentView(View view, ViewGroup.LayoutParams params) {
        // Note: FEATURE_CONTENT_TRANSITIONS may be set in the process of installing the window
        // decor, when theme attributes and the like are crystalized. Do not check the feature
        // before this happens.
        if (mContentParent == null) {
            installDecor();  // 创建DecorView
        } else if (!hasFeature(FEATURE_CONTENT_TRANSITIONS)) {
            mContentParent.removeAllViews();
        }

        if (hasFeature(FEATURE_CONTENT_TRANSITIONS)) {
            view.setLayoutParams(params);
            final Scene newScene = new Scene(mContentParent, view);
            transitionTo(newScene);
        } else {
            mContentParent.addView(view, params); //我们的布局被填充到了mContentParent中
        }
        mContentParent.requestApplyInsets();
        final Callback cb = getCallback(); // 得到的是mCallback，实际上是设置回调传入的activity引用
        if (cb != null && !isDestroyed()) {  // 最后还会回调Activity来通知content改变
            cb.onContentChanged();
        }
        mContentParentExplicitlySet = true;
```
大体过程如下：
1. 创建 DecorView
    DecorView 是 Activity 中的顶级 View，是一个 FrameLayout，一般来说它的内部包含标题栏和内容栏，但是这个会随着主题的变化而改变，不管怎么样，内容栏是一定存在的，并且有固定的 id：”android.R.id.content”，在 PhoneWindow 中，通过 generateDecor 方法创建 DecorView，通过 generateLayout 初始化主题有关布局。
2. 将 View 添加到 DecorView 的 mContentParent 中
3. 回调 Activity 的 onContentChanged 方法通知 Activity 视图已经发生改变

经过上面的三个步骤，DecorView 已经被创建并初始化完毕，Activity 的布局文件也已经成功添加到了 DecorView 的 mContentParent 中，但是这个时候 DecorView 还没有被 WindowManager 正式添加到 Window 中。在 ActivityThread 的 handleResumeActivity 方法中，会调用onResume 方法，接着会调用 Activity 的 makeVisible() 方法，正是在 makeVisible 方法中，DecorView 才真正的完成了显示过程，到这里 Activity 的视图才能被用户看到，如下：
ActivityThread.java
```
    @Override
    public void handleResumeActivity(IBinder token, boolean finalStateRequest, boolean isForward,
            String reason) {
    ...
           if (r.activity.mVisibleFromClient) {
                r.activity.makeVisible(); //  设置 View 显示
            }
    }

    void makeVisible() {
        if (!mWindowAdded) {
            ViewManager wm = getWindowManager();
            wm.addView(mDecor, getWindow().getAttributes());
            mWindowAdded = true;
        }
        mDecor.setVisibility(View.VISIBLE);
    }
```
**调用 WindowManager.addView 添加到WindowService，并显示**

# Dialog的Window创建过程
1. 创建 PhoneWindow
2. 初始化 DecorView 并将 Dialog 的视图添加到 DecorView 中
```
public void setContentView(int layoutResID){
   mWindow.setContentView(layoutResID);
}
```
3. 将 DecorView 添加到 Window 中并显示

从上面三个步骤可以发现，Dialog 的 Window 创建过程和 Activity 创建过程很类似，当 Dialog 关闭时，它会通过 WindowManager 来移除 DecorView。普通的 Dialog 必须采用 Activity 的 Context，如果采用 Application 的 Context 就会报错。这是因为没有应用 token 导致的，而应用 token 一般只有 Activity 拥有，另外，系统 Window 比较特殊，可以不需要 token。

# Toast 的 Window 创建
Toast 与 Dialog 不同，它的工作过程稍显复杂，首先 Toast 也是基于 Window 来实现的，但是由于 Toast 具有**定时取消**这一功能，所以系统采用了 Handler。在 Toast 内部有两类 IPC 过程，一是 Toast 访问 **NotificationManagerService**，第二类是 NotificationManagerService **回调 Toast 里的 TN 接口**。NotificationManagerService 同 WindowManagerService 一样，都是位于 Framework 层的服务。
Toast 属于系统 Window，Toast 提供 show 和 cancel 分别用于显示和隐藏 Toast，它们内部是一个 IPC 过程
```
    public void show() {
        if (mNextView == null) {
            throw new RuntimeException("setView must have been called");
        }

        INotificationManager service = getService();
        String pkg = mContext.getOpPackageName();
        TN tn = mTN;
        tn.mNextView = mNextView;

        try {
            service.enqueueToast(pkg, tn, mDuration);
        } catch (RemoteException e) {
            // Empty
        }
    }

   public void cancel() {
        mTN.cancel();
    }

   // class TN
   public void cancel() {
        if (localLOGV) Log.v(TAG, "CANCEL: " + this);
        mHandler.obtainMessage(CANCEL).sendToTarget();
    }
    mHandler = new Handler(looper, null) {
        @Override
        public void handleMessage(Message msg) {
            switch (msg.what) {
                case SHOW: {
                     IBinder token = (IBinder) msg.obj;
                     handleShow(token);
                     break;
                 }
                 case HIDE: {
                      handleHide();
                      // Don't do this in handleHide() because it is also invoked by
                      // handleShow()
                      mNextView = null;
                      break;
                  }
                  case CANCEL: {
                       handleHide();
                        // Don't do this in handleHide() because it is also invoked by
                        // handleShow()
                        mNextView = null;
                        try {
                            getService().cancelToast(mPackageName, TN.this);
                        } catch (RemoteException e) {
                        }
                        break;
                    }
                }
            }
       };
```
TN 是一个 Binder 类，当 NotificationManagerService 处理 Toast 的显示或隐藏请求时会跨进程回调 TN 中的方法。由于 TN 运行在 Binder 线程池中，所以需要通过 Handler 将其切换到当前线程中，这里的当前线程指的是发送 Toast 请求所在的线程。

代码在显示 Toast 中调用了 NotificationManagerService 的 enqueueToast 方法， enqueueToast 方法内部将 Toast 请求封装为 ToastRecord 对象并将其添加到一个名为 mToastQueue 的队列中，对于非系统应用来说，mToastQueue 中最多同时存在 50 个 ToastRecord，用于防止 DOS （Denial of Service 拒绝服务）。

当 ToastRecord 添加到 mToastQueue 中后，NotificationManagerService 就会通过 showNextToastLocked 方法来顺序显示 Toast，但是 Toast 真正的显示并不是在 NotificationManagerService 中完成的，而是由 ToastRecord 的 callback 来完成的：
```
    // NotificationManagerService.java
    void showNextToastLocked() {
        ToastRecord record = mToastQueue.get(0);
        while (record != null) {
            if (DBG) Slog.d(TAG, "Show pkg=" + record.pkg + " callback=" + record.callback);
            try {
                record.callback.show(record.token); // 这里
                scheduleDurationReachedLocked(record);
                return;
            } catch (RemoteException e) {
                Slog.w(TAG, "Object died trying to show notification " + record.callback
                        + " in package " + record.pkg);
                // remove it from the list and let the process die
                int index = mToastQueue.indexOf(record);
                if (index >= 0) {
                    mToastQueue.remove(index);
                }
                keepProcessAliveIfNeededLocked(record.pid);
                if (mToastQueue.size() > 0) {
                    record = mToastQueue.get(0);
                } else {
                    record = null;
                }
            }
        }
    }
```
这个 callback 就是 Toast 中的 TN 对象的远程 Binder，最终被调用的 TN 中的方法会运行在发起 Toast 请求的应用的 Binder 线程池中。Toast 显示以后，NotificationManagerService 还调用了 sheduleTimeoutLocked 方法，此方法中首先进行延时，具体的延时时长取决于 Toast 的显示时长，延迟相应时间后，NMS 会通过 cancelToastLocked 方法来隐藏 Toast 并将它从 mToastQueue 中移除，这时如果 mToastQueue 中还有其他 Toast，那么 NotificationManagerService 就继续显示其他 Toast。Toast 的隐藏也是通过 ToastRecord 的 callback 来完成的，同样也是一次 IPC 过程。

从上面的分析，可以知道 NotificationManagerService 只是起到了管理 Toast 队列及其延时的效果，Toast 的显示和隐藏过程实际上是通过 Toast 的 TN 类来实现的，TN 类的两个方法 show 和 hide，是被 NotificationManagerService 以跨进程的方式调用的，因此它们运行在 Binder 线程池中，为了将执行环境切换到 Toast 请求所在的线程，在它们内部使用了 Handler。

Toast 毕竟是要在 Window 中实现的，因此它最终还是要依附于 WindowManager，TN 的 handleShow 中代码如下：
```
    mWM = (WindowManager)context.getSystemService(Context.WINDOW_SERVICE);
    try {
          mWM.addView(mView, mParams);
          trySendAccessibilityEvent();
     } catch (WindowManager.BadTokenException ignore) {}
```

# 最后
任何 View 都是附属在一个 Window 上面的，Window 表示一个窗口的概念，也是一个抽象的概念，Window 并不是实际存在的，它是以 View 的形式存在的。WindowManager 是外界也就是我们访问 Window 的入口，Window 的具体实现位于 WindowManagerService 中，WindowManagerService 和 WindowManager 的交互是一个 IPC 过程。

# 其他问题
这里顺便解决一个疑惑，为什么在 onCreate 中创建的子线程更新UI不会崩溃？
答：我们知道android重绘有两个重要的ViewRootImpl方法，一是 requestLayout，一个是invalidate，（requestLayout 只会调用 onMeasure、onLayout，而 invalidate 会调用 onDraw），在 ViewRootImpl.requestLayout 中首先执行的就是 checkThread 方法，也就是用来抛出 CalledFromWrongThreadException 异常的，根据上面的总结我们知道，ViewRootImpl 是在 onResume 的时候创建的，在 onCreate 的时候还没有创建，也就没有办法调用 checkThread

# 补充
![touch事件传递处理](https://raw.githubusercontent.com/pacoblack/BlogImages/master/touch/touch1.png)
![touch事件传递处理](https://raw.githubusercontent.com/pacoblack/BlogImages/master/touch/touch6.png)
![touch](https://raw.githubusercontent.com/pacoblack/BlogImages/master/touch/touch7.jpg)
