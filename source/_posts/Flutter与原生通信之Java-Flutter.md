---
title: ”Flutter与原生通信之Java-Flutter“
toc: true
date: 2019-12-13 16:54:30
tags:
- Flutter
- 深入理解
categories:
- Flutter
- 深入理解
---
Native 到 Flutter
<!--more-->
我们知道FlutterViewHandlePlatformMessage()实际上是通过JNI的方式最终调用了FlutterJNI.java中的handlePlatformMessage()方法,该方法接受三个来自Native层的参数:
- channel: String类型,表示Channel名称.
- message: 字节数组,表示方法调用中的数据,如方法名和参数.
- replyId: int类型,在将此次调用的响应数据从Java层写回到Native层时用到
```
public class FlutterJNI {
  private PlatformMessageHandler platformMessageHandler;

      @UiThread
  public void setPlatformMessageHandler(@Nullable PlatformMessageHandler platformMessageHandler) {
    this.platformMessageHandler = platformMessageHandler;
  }

      // Called by native.
  @SuppressWarnings("unused")
  private void handlePlatformMessage(final String channel, byte[] message, final int replyId) {
    if (platformMessageHandler != null) {
      platformMessageHandler.handleMessageFromDart(channel, message, replyId);
    }
  }
}
```
*FlutterJNI类定义了Java层和Flutter C/C++引擎之间的相关接口.此类目前处于实验性质,随着后续的发展可能会被不断的重构和优化,不保证一直存在,不建议开发者调用该类.*

为了建立Android应用和Flutter C/C++引擎的连接,需要创建FlutterJNI实例,然后将其attach到Native,常见的使用方法如下:
```
// 1.创建FlutterJNI实例
FlutterJNI flutterJNI = new FlutterJNI();
// 2.建立和Native层的连接
flutterJNI.attachToNative();
......
// 3.断开和Native层的连接,并释放资源
flutterJNI.detachFromNativeAndReleaseResources();
```
FlutterJNI中`handlePlatformMessage()`,在该方法中首先判断platformMessageHandler是否为null,不为null,则调用其`handleMessageFromDart()`方法.其中platformMessageHandler需要通过FlutterJNI中的`setPlatformMessageHandler()`方法来设置.在FlutterNativeView中调用的。
```
public class FlutterNativeView implements BinaryMessenger {

    private final Map<String, BinaryMessageHandler> mMessageHandlers;
    private int mNextReplyId = 1;
    private final Map<Integer, BinaryReply> mPendingReplies = new HashMap<>();

    private final FlutterPluginRegistry mPluginRegistry;
    private FlutterView mFlutterView;
    private FlutterJNI mFlutterJNI;
    private final Context mContext;
    private boolean applicationIsRunning;

    public FlutterNativeView(Context context, boolean isBackgroundView) {
        mContext = context;
        mPluginRegistry = new FlutterPluginRegistry(this, context);
        // 创建FlutterJNI实例
        mFlutterJNI = new FlutterJNI();
        mFlutterJNI.setRenderSurface(new RenderSurfaceImpl());
        // 将PlatformMessageHandlerImpl实例赋值给FlutterJNI中的platformMessageHandler属性
        mFlutterJNI.setPlatformMessageHandler(new PlatformMessageHandlerImpl());
        mFlutterJNI.addEngineLifecycleListener(new EngineLifecycleListenerImpl());
        attach(this, isBackgroundView);
        assertAttached();
        mMessageHandlers = new HashMap<>();
    }

    .......
}
```
在FlutterNativeView的构造函数中,首先创建FlutterJNI实例mFlutterJNI,然后调用`setPlatformMessageHandler()`并把PlatformMessageHandlerImpl实例作为参数传入.因此在FlutterJNI的`handlePlatformMessage()`方法中,最终调用PlatformMessageHandlerImpl实例的`handleMessageFromDart()`来处理来自Flutter中的消息.
```
public class FlutterNativeView implements BinaryMessenger {
        private final Map<String, BinaryMessageHandler> mMessageHandlers;

    	......

        private final class PlatformMessageHandlerImpl implements PlatformMessageHandler {
        // Called by native to send us a platform message.
        public void handleMessageFromDart(final String channel, byte[] message, final int replyId) {
	   // 1.根据channel名称获取对应的BinaryMessageHandler对象.每个Channel对应一个Handler对象
            BinaryMessageHandler handler = mMessageHandlers.get(channel);
            if (handler != null) {
                try {
                    // 2.将字节数组对象封装为ByteBuffer对象
                    final ByteBuffer buffer = (message == null ? null : ByteBuffer.wrap(message));
                    // 3.调用handler对象的onMessage()方法来分发消息
                    handler.onMessage(buffer, new BinaryReply() {
                        private final AtomicBoolean done = new AtomicBoolean(false);
                        @Override
                        public void reply(ByteBuffer reply) {
                            // 4.根据reply的情况,调用FlutterJNI中invokePlatformMessageXXX()方法将响应数据发送给Flutter层
                            if (reply == null) {
                                mFlutterJNI.invokePlatformMessageEmptyResponseCallback(replyId);
                            } else {
                                mFlutterJNI.invokePlatformMessageResponseCallback(replyId, reply, reply.position());
                            }
                        }
                    });
                } catch (Exception exception) {
                    mFlutterJNI.invokePlatformMessageEmptyResponseCallback(replyId);
                }
                return;
            }
            mFlutterJNI.invokePlatformMessageEmptyResponseCallback(replyId);
        }
}
```
以Channel名称作为key,以BinaryMessageHandler类型为value.在`handleMessageFromDart()`方法中,首先根据Channel名称从mMessageHandlers取出对应的二进制消息处理器BinaryMessageHandler,然后将字节数组message封装为ByteBuffer对象,然后调用BinaryMessageHandler实例的`onMessage()`方法处理ByteBuffer,并进行响应.

BinaryReply是一个接口,主要用来将ByteBuffer类型的响应数据reply从Java层写回到Flutter层.根据reply是否为null,调用FlutterJNI实例不同的方法.

**BinaryMessageHandler是如何添加到mMessageHandler中:**
```
public class FlutterNativeView implements BinaryMessenger {
    private final Map<String, BinaryMessageHandler> mMessageHandlers;

    ......

    @Override
    public void setMessageHandler(String channel, BinaryMessageHandler handler) {
        if (handler == null) {
            mMessageHandlers.remove(channel);
        } else {
            mMessageHandlers.put(channel, handler);
        }
    }
    .......
}
```
```
public class MainActivity extends FlutterActivity {
    // 1.定义Channel的名称,该名称作为Channel的唯一标识符
    private static final String CHANNEL = "samples.flutter.io/battery";

    @Override
    public void onCreate(Bundle savedInstanceState) {

        super.onCreate(savedInstanceState);
        // 2.创建MethodChannel对象channel
        MethodChannel channel = new MethodChannel(getFlutterView(), CHANNEL);
        // 3.调用MethodChannel实例的setMethodCallHandler()方法为当前channel设置Handler
        channel.setMethodCallHandler(
                new MethodCallHandler() {
                    @Override
                    public void onMethodCall(MethodCall call, Result result) {
                        // TODO
                    }
                });
    }
}
```
接下来是 MethodChannel 定义
```
public final class MethodChannel {
    // 二进制信使
    private final BinaryMessenger messenger;
    // Channel名称
    private final String name;
    // 方法编码
    private final MethodCodec codec;

    public MethodChannel(BinaryMessenger messenger, String name) {
        this(messenger, name, StandardMethodCodec.INSTANCE);
    }

    public MethodChannel(BinaryMessenger messenger, String name, MethodCodec codec) {
        assert messenger != null;
        assert name != null;
        assert codec != null;
        this.messenger = messenger;
        this.name = name;
        this.codec = codec;
    }    

    ......

    public void setMethodCallHandler(final @Nullable MethodCallHandler handler) {
        messenger.setMessageHandler(name,
            handler == null ? null : new IncomingMethodCallHandler(handler));
    }
    ......
    private final class IncomingMethodCallHandler implements BinaryMessageHandler {
        private final MethodCallHandler handler;

        IncomingMethodCallHandler(MethodCallHandler handler) {
            this.handler = handler;
        }

        @Override
        public void onMessage(ByteBuffer message, final BinaryReply reply) {
            // 1.使用codec对来自Flutter方法调用数据进行解码,并将其封装为MethodCall对象.
            // MethodCall中包含两部分数据:method表示要调用的方法;arguments表示方法所需参数
            final MethodCall call = codec.decodeMethodCall(message);
            try {
                // 2.调用自定义MethodCallHandler中的onMethodCall方法继续处理方法调用
                handler.onMethodCall(call, new Result() {
                    @Override
                    public void success(Object result) {
                        // 调用成功时,需要回传数据给Flutter层时,使用codec对回传数据result
                        // 进行编码
                        reply.reply(codec.encodeSuccessEnvelope(result));
                    }

                    @Override
                    public void error(String errorCode, String errorMessage, Object errorDetails) {
                        // 调用失败时,需要回传错误数据给Flutter层时,使用codec对errorCode,
                        // errorMessage,errorDetails进行编码
                        reply.reply(codec.encodeErrorEnvelope(errorCode, errorMessage, errorDetails));
                    }

                    @Override
                    public void notImplemented() {
                        // 方法没有实现时,调用该方法后,flutter将会受到相应的错误消息
                        reply.reply(null);
                    }
                });
            } catch (RuntimeException e) {
                Log.e(TAG + name, "Failed to handle method call", e);
                reply.reply(codec.encodeErrorEnvelope("error", e.getMessage(), null));
            }
        }
    }
}
```
在上述代码中,首先使用codec对来自Flutter层的二进制数据进行解码,并将其封装为MethodCall对象,然后调用`MethodCallHandler.onMethodCall()`方法.
![调用过程](https://upload-images.jianshu.io/upload_images/16327616-fa10b42f2a33df75?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

# Java->Native
```
public class FlutterJNI {
  private Long nativePlatformViewId;

  ......  
  @UiThread
  public void invokePlatformMessageResponseCallback(int responseId, ByteBuffer message, int position) {
    // 1.检查FlutterJNI是否已经attach到Native层,如若没有则抛出异常  
    ensureAttachedToNative();
    // 2.继续调用nativeInvokePlatformMessageResponseCallback()  
    nativeInvokePlatformMessageResponseCallback(
        nativePlatformViewId,
        responseId,
        message,
        position
    );
  }

  private native void nativeInvokePlatformMessageResponseCallback(
     long nativePlatformViewId,
     int responseId,
     ByteBuffer message,
     int position
  );   

  ......  

  private void ensureAttachedToNative() {
    // FlutterJNI attach到Native层后,会返回一个long类型的值用来初始化nativePlatformViewId  
    if (nativePlatformViewId == null) {
      throw new RuntimeException("Cannot execute operation because FlutterJNI is not attached to native.");
    }
  }

}
```
当数据需要写回时,数据首先通过codec被编码成ByteBuffer类型,然后调用reply的`reply()`方法.在`reply()`方法中,对于非null类型的ByteBuffer,会调用FlutterJNI中的`invokePlatformMessageResponseCallback()`.
在上述`invokePlatformMessageResponseCallback()`方法中,首先检查当前FlutterJNI实例是否已经attach到Native层,然后调用Native方法`nativeInvokePlatformMessageResponseCallback()`向JNI层写入数据
```
void PlatformViewAndroid::InvokePlatformMessageResponseCallback(
    JNIEnv* env,
    jint response_id,
    jobject java_response_data,
    jint java_response_position) {
  if (!response_id)
    return;
  // 1.通过response_id从pending_responses_中取出response  
  auto it = pending_responses_.find(response_id);
  if (it == pending_responses_.end())
    return;
  // 2.GetDirectBufferAddress函数返回一个指向被传入的ByteBuffer对象的地址指针  
  uint8_t* response_data =
      static_cast<uint8_t*>(env->GetDirectBufferAddress(java_response_data));
  std::vector<uint8_t> response = std::vector<uint8_t>(
      response_data, response_data + java_response_position);
  auto message_response = std::move(it->second);
  // 3.从pending_responses_中移除该response  
  pending_responses_.erase(it);
  // 4.调用response的Complete()方法将二进制结果返回
  message_response->Complete(
      std::make_unique<fml::DataMapping>(std::move(response)));
}
```
# Native -> Dart
```
void PlatformMessageResponseDart::Complete(std::unique_ptr<fml::Mapping> data) {
  if (callback_.is_empty())
    return;
  FML_DCHECK(!is_complete_);
  is_complete_ = true;
  ui_task_runner_->PostTask(fml::MakeCopyable(
      [callback = std::move(callback_), data = std::move(data)]() mutable {
        std::shared_ptr<tonic::DartState> dart_state =
            callback.dart_state().lock();
        if (!dart_state)
          return;
        tonic::DartState::Scope scope(dart_state);
		// 将Native层的二进制数据data转为Dart中的二进制数据byte_buffer
        Dart_Handle byte_buffer = WrapByteData(std::move(data));
        tonic::DartInvoke(callback.Release(), {byte_buffer});
      }));
}
```
