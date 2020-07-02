---
title: Flutter与原生通信之Flutter->Java
toc: true
date: 2019-12-05 11:52:14
tags:
- Flutter
- 深入理解
categories:
- Flutter
- 深入理解
---

# 通信过程

我们知道，Flutter定义了三种不同类型的Channel，它们分别是

- BasicMessageChannel：用于传递字符串和半结构化的信息。
- MethodChannel：用于传递方法调用（method invocation）。
- EventChannel: 用于数据流（event streams）的通信。

三种Channel之间互相独立，各有用途，但它们在设计上却非常相近。每种Channel均有三个重要成员变量：

- name: String类型，代表Channel的名字，也是其唯一标识符。
- messager：BinaryMessenger类型，代表消息信使，是消息的发送与接收的工具。
- codec: MessageCodec类型或MethodCodec类型，代表消息的编解码器。

一个Flutter应用中可能存在多个Channel，每个Channel在创建时必须指定一个独一无二的name，Channel之间使用name来区分彼此。当有消息从Flutter端发送到Platform端时，会根据其传递过来的channel name找到该Channel对应的Handler

虽然三种Channel各有用途，但是他们与Flutter通信的工具却是相同的，均为BinaryMessager。

​BinaryMessenger是Platform端与Flutter端通信的工具，其通信使用的消息格式为二进制格式数据。当我们初始化一个Channel，并向该Channel注册处理消息的Handler时，实际上会生成一个与之对应的BinaryMessageHandler，并以channel name为key，注册到BinaryMessenger中。当Flutter端发送消息到BinaryMessenger时，BinaryMessenger会根据其入参channel找到对应的BinaryMessageHandler，并交由其处理。

Binarymessenger在Android端是一个接口，其具体实现为FlutterNativeView。而其在iOS端是一个协议，名称为FlutterBinaryMessenger。

Binarymessenger并不知道Channel的存在，它只和BinaryMessageHandler打交道。由于Channel从BinaryMessageHandler接收到的消息是二进制格式数据，无法直接使用，故Channel会将该二进制消息通过Codec（消息编解码器）解码为能识别的消息并传递给Handler进行处理。

当Handler处理完消息之后，会通过回调函数返回result，并将result通过编解码器编码为二进制格式数据，通过BinaryMessenger发送回Flutter端。

# 消息解码器 Codec
![codec](flutter1.jpg)

消息编解码器Codec主要用于将二进制格式的数据转化为Handler能够识别的数据，Flutter定义了两种Codec：`MessageCodec` 和 `MethodCodec`。

​Android中，MessageCodec是一个接口，定义了两个方法:
- encodeMessage 接收一个特定的数据类型T，并将其编码为二进制数据ByteBuffer
- decodeMessage 则接收二进制数据ByteBuffer，将其解码为特定数据类型T。

iOS中，其名称为FlutterMessageCodec，是一个协议，定义了两个方法：
- encode 接收一个类型为id的消息，将其编码为NSData类型，
- decode 接收NSData类型消息，将其解码为id类型数据。

MesageCodec 有不同的子类：
- BinaryCodec, 是最为简单的一种Codec，因为其返回值类型和入参的类型相同，均为二进制格式（Android中为ByteBuffer，iOS中为NSData）。实际上，BinaryCodec在编解码过程中什么都没做，只是原封不动将二进制数据消息返回而已。或许你会因此觉得BinaryCodec没有意义，但是在某些情况下它非常有用，比如使用BinaryCodec可以使传递内存数据块时在编解码阶段免于内存拷贝。

- StringCodec, 用于字符串与二进制数据之间的编解码，其编码格式为UTF-8。

- JSONMessageCodec, 用于基础数据与二进制数据之间的编解码，其支持基础数据类型以及列表、字典。其在iOS端使用了NSJSONSerialization作为序列化的工具，而在Android端则使用了其自定义的JSONUtil与StringCodec作为序列化工具。

- StandardMessageCodec, 是BasicMessageChannel的默认编解码器，其支持基础数据类型、二进制数据、列表、字典，

# StandardMethodCodec
```
public class StandardMessageCodec implements MessageCodec<Object> {
    public static final StandardMessageCodec INSTANCE = new StandardMessageCodec();

    // 根据数据类型,先向stream中写入类型标志值,及上述提到的14个常量值,然后将具体的
    // value值转成byte继续写入到stream
    protected void writeValue(ByteArrayOutputStream stream, Object value) {
        if (value == null) {
            stream.write(NULL);
        } else if (value == Boolean.TRUE) {
            stream.write(TRUE);
        } else if (value == Boolean.FALSE) {
            stream.write(FALSE);
        } else if (value instanceof Number) {
            if (value instanceof Integer || value instanceof Short || value instanceof Byte) {         // 1.写入类型标志值
                stream.write(INT);
                // value转为byte,继续写入到stream中
                writeInt(stream, ((Number) value).intValue());
            }
            .......
        }else if (value instanceof String) {
            stream.write(STRING);
            writeBytes(stream, ((String) value).getBytes(UTF8));
        }
        .......
    }

    // writeValue()方法反向过程,原理一致
    protected final Object readValue(ByteBuffer buffer) {
        .......
    }
}
```
在StandardMessageCodec中最重要的两个方法是`writeValue()`和`readValue()`.前者用于将value值写入到字节输出流ByteArrayOutputStream中,后者从字节缓冲数组中读取.在Android返回电量的过程中,假设电量值为100,该值转换成二进制数据流程为:首先向字节流stream中写入表示int类型的标志值3,再将100转为4个byte,继续写入到字节流stream中.当Dart中接受到该二进制数据后,先读取第一个byte值,根据此值得知后面需要读取一个int类型的数据,随后读取后面4个byte,并将其转为dart类型中int类型.
![图示](https://upload-images.jianshu.io/upload_images/16327616-acd76bda9eb173ad?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

# Handler
Flutter中定义了一套Handler用于处理经过Codec解码后消息.在使用Platform Channel时,需要为其设置对应的Handler,实际上就是为其注册一个对应BinaryMessageHandler,二进制数据会被BinaryMessageHanler进行处理,首先使用Codec进行解码操作,然后再分发给具体Handler进行处理.与三种Platform Channel相对应,Flutter中也定义了三种Handler:

- MessageHandler: 用于处理字符串或者半结构化消息,定义在BasicMessageChannel中.
```
public final class BasicMessageChannel<T> {
    ......

    public interface MessageHandler<T> {
        // onMessage()用于处理来自Flutter中的消息,
        // 该接受两个参数:T类型的消息以及用于异步返回T类型的result
        void onMessage(T message, Reply<T> reply);
    }

    ......
}
```
- MethodCallHandler: 用于处理方法调用,定义在MethodChannel中.
- StreamHandler: 用于事件流通信,定义在EventChannel中.

# MethodChannel调用原理
## Dart -> Native
```
class MethodChannel {
  // 构造方法,通常我们只需要指定该channel的name,  
  const MethodChannel(this.name, [this.codec = const StandardMethodCodec()]);
  // name作为通道的唯一标志符,用于区分不同的通道调用
  final String name;
  // 用于方法调用过程的编码
  final MethodCodec codec;

  // 用于发起异步平台方法调用,需要指定方法名,以及可选方法参数  
  Future<dynamic> invokeMethod(String method, [dynamic arguments]) async {
    assert(method != null);
    // 将一次方法调用中需要的方法名和方法参数封装为MethodCall对象,然后使用MethodCodec对该
    //  对象进行进行编码操作,最后通过BinaryMessages中的send方法发起调用
    final dynamic result = await BinaryMessages.send(
      name,
      codec.encodeMethodCall(MethodCall(method, arguments)),
    );
    if (result == null)
      throw MissingPluginException('No implementation found for method $method on channel $name');
    return codec.decodeEnvelope(result);
  }
}

final MethodChannel _channel = new MethodChannel('flutter.io/player')
```
Channel名称作为MethodChannel的唯一标识符,用于区分不同的MethodChannel对象.
拿到MethodChannel对象后,通过调用其`invokeMethod()`方法用于向平台发起一次调用.在`invokeMethod()`方法中会将一次方法调中的方法名method和方法参数arguments封装为MethodCall对象,然后使用MethodCodec对其进行二进制编码,最后通过`BinaryMessages.send()`发起平台方法调用请求.
```
// BinaryMessages类中提供了用于发送和接受平台插件的二进制消息.
class BinaryMessages {
   ......
   static Future<ByteData> send(String channel, ByteData message) {
    final _MessageHandler handler = _mockHandlers[channel];
    // 在没有设置Mock Handler的情况下,继续调用_sendPlatformMessage()   
    if (handler != null)
      return handler(message);
    return _sendPlatformMessage(channel, message);
  }

   static Future<ByteData> _sendPlatformMessage(String channel, ByteData message) {
    final Completer<ByteData> completer = Completer<ByteData>();   
    ui.window.sendPlatformMessage(channel, message, (ByteData reply) {
      try {
        completer.complete(reply);
      } catch (exception, stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'services library',
          context: 'during a platform message response callback',
        ));
      }
    });
    return completer.future;
  }
   ......  
}
```
```
class Window{
    ......
    void sendPlatformMessage(String name,
                           ByteData data,
                           PlatformMessageResponseCallback callback) {
    final String error =
        _sendPlatformMessage(name, _zonedPlatformMessageResponseCallback(callback), data);
    if (error != null)
      throw new Exception(error);
  }
  // 和Java类似,Dart中同样提供了Native方法用于调用底层C++/C代码的能力  
  String _sendPlatformMessage(String name,
                              PlatformMessageResponseCallback callback,
                              ByteData data) native 'Window_sendPlatformMessage';
   .......
}
```
上述过程最终会调用到`ui.Window._sendPlatformMessage()`方法,该方法是一个native方法,这与Java中JNI技术非常类似.
![调用过程](https://upload-images.jianshu.io/upload_images/16327616-26910abb6a266c60?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
在调用该Native方法中,我们向native层发送了三个参数：
- name: String类型,代表Channel名称
- data: ByteData类型,代表之前封装的二进制数据
- callback: Function类型,用于结果回调

`_sendPlatformMessage()`具体实现在 Window.cc 中:
```
void Window::RegisterNatives(tonic::DartLibraryNatives* natives) {
  natives->Register({
      {"Window_defaultRouteName", DefaultRouteName, 1, true},
      {"Window_scheduleFrame", ScheduleFrame, 1, true},
      {"Window_sendPlatformMessage", _SendPlatformMessage, 4, true},
      {"Window_respondToPlatformMessage", _RespondToPlatformMessage, 3, true},
      {"Window_render", Render, 2, true},
      {"Window_updateSemantics", UpdateSemantics, 2, true},
      {"Window_setIsolateDebugName", SetIsolateDebugName, 2, true},
      {"Window_reportUnhandledException", ReportUnhandledException, 2, true},
  });
}
void _SendPlatformMessage(Dart_NativeArguments args) {
  // 最终调用SendPlatformMessage函数  
  tonic::DartCallStatic(&SendPlatformMessage, args);
}
```
```
Dart_Handle SendPlatformMessage(Dart_Handle window,
                                const std::string& name,
                                Dart_Handle callback,
                                const tonic::DartByteData& data) {
  UIDartState* dart_state = UIDartState::Current();
  // 1.只能在main iolate调用平台方法
  if (!dart_state->window()) {
    // Must release the TypedData buffer before allocating other Dart objects.
    data.Release();
    return tonic::ToDart(
        "Platform messages can only be sent from the main isolate");
  }
  // 此处response的作用?
  fml::RefPtr<PlatformMessageResponse> response;
  if (!Dart_IsNull(callback)) {
    response = fml::MakeRefCounted<PlatformMessageResponseDart>(
        tonic::DartPersistentValue(dart_state, callback),
        dart_state->GetTaskRunners().GetUITaskRunner());
  }
  // 2.核心方法调用
  if (Dart_IsNull(data.dart_handle())) {
    dart_state->window()->client()->HandlePlatformMessage(
        fml::MakeRefCounted<PlatformMessage>(name, response));
  } else {
    const uint8_t* buffer = static_cast<const uint8_t*>(data.data());

    dart_state->window()->client()->HandlePlatformMessage(
        fml::MakeRefCounted<PlatformMessage>(
            name, std::vector<uint8_t>(buffer, buffer + data.length_in_bytes()),
            response));
  }

  return Dart_Null();
}
```
`HandlePlatformMessage()`的实现类在`RuntimeController`
```
class RuntimeController final : public WindowClient {
    ......

    private:
      RuntimeDelegate& client_;

      .......
      void HandlePlatformMessage(fml::RefPtr<PlatformMessage> message) override;
      ......

}
// runtime_controller.cc
void RuntimeController::HandlePlatformMessage(
    fml::RefPtr<PlatformMessage> message) {
  client_.HandlePlatformMessage(std::move(message));
}
```
在运行过程中,不同的平台有运行机制不同,需要不同的处理策略,因此RuntimeController中相关的方法实现都被委托到了不同的平台实现类`RuntimeDelegate`中,即上述代码中client_,定义如下：
```
class Engine final : public blink::RuntimeDelegate {
    ........
}

// engine.cc
void Engine::HandlePlatformMessage(
    fml::RefPtr<blink::PlatformMessage> message) {
  // kAssetChannel值为flutter/assets  
  if (message->channel() == kAssetChannel) {
    HandleAssetPlatformMessage(std::move(message));
  } else {
    delegate_.OnEngineHandlePlatformMessage(std::move(message));
  }
}
```
```
void Shell::OnEngineHandlePlatformMessage(
    fml::RefPtr<blink::PlatformMessage> message) {
  FML_DCHECK(is_setup_);
  FML_DCHECK(task_runners_.GetUITaskRunner()->RunsTasksOnCurrentThread());

  // kSkiaChannel值为flutter/skia  
  if (message->channel() == kSkiaChannel) {
    HandleEngineSkiaMessage(std::move(message));
    return;
  }
  // 其他情况下,向PlatformTaskRunner中添加Task
  task_runners_.GetPlatformTaskRunner()->PostTask(
      [view = platform_view_->GetWeakPtr(), message = std::move(message)]() {
        if (view) {
          view->HandlePlatformMessage(std::move(message));
        }
      });
}
```
Engine在处理message时,如果该message值等于`kAssetChannel`,即flutter/assets,表示当前操作想要获取资源,因此会调用`HandleAssetPlatformMessage()`来走获取资源的逻辑;否则调用`delegate_.OnEngineHandlePlatformMessage()`方法.
`OnEngineHandlePlatformMessage`在接收到消息后,首先判断要调用Channel是否是flutter/skia,如果是则调用`HandleEngineSkiaMessage()`进行处理后返回,否则向PlatformTaskRunner添加一个Task,在该Task中会调用PlatformView的`HandlePlatformMessage()`方法.根据运行平台不同PlatformView有不同的实现,对于Android平台而言,其具体实现是PlatformViewAndroid;对于IOS平台而言,其实现是PlatformViewIOS.
```
void PlatformViewAndroid::HandlePlatformMessage(
    fml::RefPtr<blink::PlatformMessage> message) {
  JNIEnv* env = fml::jni::AttachCurrentThread();
  fml::jni::ScopedJavaLocalRef<jobject> view = java_object_.get(env);
  if (view.is_null())
    return;
  // response_id在Flutter调用平台代码时,会传到平台代码中,后续平台代码需要回传数据时
  // 需要用到它
  int response_id = 0;
  // 如果message中有response(response类型为PlatformMessageResponseDart),则需要对
  // response_id进行自增  
  if (auto response = message->response()) {
    response_id = next_response_id_++;
    // pending_responses是一个Map结构  
    pending_responses_[response_id] = response;
  }
  auto java_channel = fml::jni::StringToJavaString(env, message->channel());
  if (message->hasData()) {
    fml::jni::ScopedJavaLocalRef<jbyteArray> message_array(
        env, env->NewByteArray(message->data().size()));
    env->SetByteArrayRegion(
        message_array.obj(), 0, message->data().size(),
        reinterpret_cast<const jbyte*>(message->data().data()));
    message = nullptr;

    // This call can re-enter in InvokePlatformMessageXxxResponseCallback.
    FlutterViewHandlePlatformMessage(env, view.obj(), java_channel.obj(),
                                     message_array.obj(), response_id);
  } else {  
    message = nullptr;
    // This call can re-enter in InvokePlatformMessageXxxResponseCallback.
    FlutterViewHandlePlatformMessage(env, view.obj(), java_channel.obj(),
                                     nullptr, response_id);
  }
}
```
该方法在接受PlatformMessage类型的消息时,如果消息中有response,则对response_id自增,并以response_id为key,response为value存放在变量`pending_responses_`中.
接着将消息中的channel和data数据转成Java可识别的数据,并连同response_id一同作为`FlutterViewHandlePlatformMessage()`方法的参数,最终通过JNI调用的方式传递到Java层.
```
// platform_android_jni.cc
static jmethodID g_handle_platform_message_method = nullptr;
void FlutterViewHandlePlatformMessage(JNIEnv* env,
                                      jobject obj,
                                      jstring channel,
                                      jobject message,
                                      jint responseId) {
  // g_handle_platform_message_method中指向Java层的方法
  // 其在 RegisterApi 中被初始化
  env->CallVoidMethod(obj, g_handle_platform_message_method, channel, message,
                      responseId);
  FML_CHECK(CheckException(env));
}
```
```
bool PlatformViewAndroid::Register(JNIEnv* env) {
  ......  
  g_flutter_jni_class = new fml::jni::ScopedJavaGlobalRef<jclass>(
      env, env->FindClass("io/flutter/embedding/engine/FlutterJNI"));

  ......

  return RegisterApi(env);
}

bool RegisterApi(JNIEnv* env) {
  ......  
  g_handle_platform_message_method =
      env->GetMethodID(g_flutter_jni_class->obj(), "handlePlatformMessage",
                       "(Ljava/lang/String;[BI)V");
  ......  
}
```
不难看出 `g_flutter_jni_class` 指向FlutterJNI.java类, `g_handle_platform_message_method` 指向FlutterJN.javaI中的 `handlePlatformMessage()` 方法.
![image](http://gityuan.com/img/method_channel/MethodChannel.jpg)
FlutterViewHandlePlatformMessage()方法会调用到Java层的FlutterJNI.handlePlatformMessage()方法。接下来是返回参数
![image](http://gityuan.com/img/method_channel/ChannelReply.jpg)
