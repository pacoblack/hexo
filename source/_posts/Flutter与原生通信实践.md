---
title: Flutter与原生通信实践
toc: true
date: 2019-12-05 11:38:27
tags:
- Flutter
- 实践
categories:
- Flutter
- 实践
---
具体用法
<!--more-->

Flutter和Native的通信是通过Channel来完成的。
Flutter使用了一个灵活的系统，允许您调用特定平台的API，无论在Android上的Java或Kotlin代码中，还是iOS上的ObjectiveC或Swift代码中均可用。

Flutter与原生之间的通信依赖灵活的消息传递方式：
- 应用的Flutter部分通过平台通道（platform channel）将消息发送到其应用程序的所在的宿主（iOS或Android）应用（原生应用）。
- 宿主监听平台通道，并接收该消息。然后它会调用该平台的API，并将响应发送回客户端，即应用程序的Flutter部分。

![Flutter通信](https://upload-images.jianshu.io/upload_images/4511172-e39a4d2cc43de609.png?imageMogr2/auto-orient/)

当在Flutter中调用原生方法时，调用信息通过**平台通道**传递到原生，原生收到调用信息后方可执行指定的操作，如需返回数据，则原生会将数据再通过**平台通道**传递给Flutter。值得注意的是**消息传递是异步的**，这确保了用户界面在消息传递时不会被挂起。

在客户端，[MethodChannel API](https://docs.flutter.io/flutter/services/MethodChannel-class.html) 可以发送与方法调用相对应的消息。 在宿主平台上，`MethodChannel` 在[Android API](https://docs.flutter.io/javadoc/io/flutter/plugin/common/MethodChannel.html) 和 [FlutterMethodChannel iOS API](https://docs.flutter.io/objcdoc/Classes/FlutterMethodChannel.html)可以接收方法调用并返回结果。这些类可以帮助我们用很少的代码就能开发平台插件。


#创建实例
1. 首先创建一个新的应用程序:
```bash
flutter create batterylevel

// 默认情况下，模板支持使用Java编写Android代码，或使用Objective-C编写iOS代码。
// 要使用Kotlin或Swift，请使用-i和/或-a标志:
flutter create -i swift -a kotlin batterylevel
```
2. 构建通道。通过 `MethodChannel` 来获取*电池电量*。
```Dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
...
class _MyHomePageState extends State<MyHomePage> {
  static const platform = const MethodChannel('samples.flutter.io/battery');

  // Get battery level.
}
```
接下来，我们调用通道上的方法，指定通过字符串标识符调用方法`getBatteryLevel`。 该调用可能失败(平台不支持平台API，例如在模拟器中运行时)，所以我们将invokeMethod调用包装在try-catch语句中。
```Dart
 // Get battery level.
  String _batteryLevel = 'Unknown battery level.';

  Future<Null> _getBatteryLevel() async {
    String batteryLevel;
    try {
      final int result = await platform.invokeMethod('getBatteryLevel');
      batteryLevel = 'Battery level at $result % .';
    } on PlatformException catch (e) {
      batteryLevel = "Failed to get battery level: '${e.message}'.";
    }

    // 在setState中来更新用户界面状态batteryLevel。
    setState(() {
      _batteryLevel = batteryLevel;
    });
  }
```
最后，我们在build创建包含一个小字体显示电池状态和一个用于刷新值的按钮的用户界面。
```Dart
@override
Widget build(BuildContext context) {
  return new Material(
    child: new Center(
      child: new Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          new RaisedButton(
            child: new Text('Get Battery Level'),
            onPressed: _getBatteryLevel,
          ),
          new Text(_batteryLevel),
        ],
      ),
    ),
  );
}
```
3. android 端接口实现
在java目录下打开 MainActivity.java的 `onCreate`里创建`MethodChannel`并设置一个`MethodCallHandler`。确保使用和Flutter客户端中使用的通道名称相同的名称。
```java
import io.flutter.app.FlutterActivity;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "samples.flutter.io/battery";

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        new MethodChannel(getFlutterView(), CHANNEL).setMethodCallHandler(
          new MethodCallHandler() {
             @Override
             public void onMethodCall(MethodCall call, Result result) {
                 // TODO
             }
          });
    }
}
```
```java
@Override
public void onMethodCall(MethodCall call, Result result) {
    if (call.method.equals("getBatteryLevel")) {
        int batteryLevel = getBatteryLevel();

        if (batteryLevel != -1) {
            result.success(batteryLevel);
        } else {
            result.error("UNAVAILABLE", "Battery level not available.", null);
        }
    } else {
        result.notImplemented();
    }
}

private int getBatteryLevel() {
  int batteryLevel = -1;
  if (VERSION.SDK_INT >= VERSION_CODES.LOLLIPOP) {
    BatteryManager batteryManager = (BatteryManager) getSystemService(BATTERY_SERVICE);
    batteryLevel = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY);
  } else {
    Intent intent = new ContextWrapper(getApplicationContext()).
        registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
    batteryLevel = (intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) * 100) /
        intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
  }

  return batteryLevel;
}
```
#Flutter定义了三种不同类型的Channel：
- BasicMessageChannel：用于传递字符串和半结构化的信息，持续通信，收到消息后可以回复此次消息，如：Native将遍历到的文件信息陆续传递到Dart，在比如：Flutter将从服务端陆陆续获取到信息交个Native加工，Native处理完返回等；
```Dart
import 'package:flutter/services.dart';

static const BasicMessageChannel _basicMessageChannel =
      const BasicMessageChannel('BasicMessageChannelPlugin', StringCodec());

//使用BasicMessageChannel接受来自Native的消息，并向Native回复
_basicMessageChannel
    .setMessageHandler((String message) => Future<String>(() {
          setState(() {
            showMessage = message;
          });
          return "收到Native的消息：" + message;
        }));
//使用BasicMessageChannel向Native发送消息，并接受Native的回复
String response;
    try {
       response = await _basicMessageChannel.send(value);
    } on PlatformException catch (e) {
      print(e);
    }
```
```java
public class BasicMessageChannelPlugin implements BasicMessageChannel.MessageHandler<String>, BasicMessageChannel.Reply<String> {
    private final Activity activity;
    private final BasicMessageChannel<String> messageChannel;

    static BasicMessageChannelPlugin registerWith(FlutterView flutterView) {
        return new BasicMessageChannelPlugin(flutterView);
    }

    private BasicMessageChannelPlugin(FlutterView flutterView) {
        this.activity = (Activity) flutterView.getContext();
        this.messageChannel = new BasicMessageChannel<>(flutterView, "BasicMessageChannelPlugin", StringCodec.INSTANCE);
        //设置消息处理器，处理来自Dart的消息
        messageChannel.setMessageHandler(this);
    }

    @Override
    public void onMessage(String s, BasicMessageChannel.Reply<String> reply) {//处理Dart发来的消息
        reply.reply("BasicMessageChannel收到：" + s);//可以通过reply进行回复
        if (activity instanceof IShowMessage) {
            ((IShowMessage) activity).onShowMessage(s);
        }
        Toast.makeText(activity, s, Toast.LENGTH_SHORT).show();
    }

    /**
     * 向Dart发送消息，并接受Dart的反馈
     *
     * @param message  要给Dart发送的消息内容
     * @param callback 来自Dart的反馈
     */
    void send(String message, BasicMessageChannel.Reply<String> callback) {
        messageChannel.send(message, callback);
    }

    @Override
    public void reply(String s) {

    }
}
```
- MethodChannel：用于传递方法调用（method invocation）一次性通信：如Flutter调用Native拍照；
- EventChannel: 用于数据流（event streams）的通信，持续通信，收到消息后无法回复此次消息，通常用于Native向Dart的通信，如：手机电量变化，网络连接变化，陀螺仪，传感器等；
```Dart
import 'package:flutter/services.dart';
...
static const EventChannel _eventChannelPlugin =
      EventChannel('EventChannelPlugin');
StreamSubscription _streamSubscription;
  @override
  void initState() {
    _streamSubscription=_eventChannelPlugin
        .receiveBroadcastStream()
        .listen(_onToDart, onError: _onToDartError);
    super.initState();
  }
  @override
  void dispose() {
    if (_streamSubscription != null) {
      _streamSubscription.cancel();
      _streamSubscription = null;
    }
    super.dispose();
  }
  void _onToDart(message) {
    setState(() {
      showMessage = message;
    });
  }
  void _onToDartError(error) {
    print(error);
  }
```
```java
public interface StreamHandler {
    void onListen(Object args, EventChannel.EventSink eventSink);

    void onCancel(Object o);
}

public class EventChannelPlugin implements EventChannel.StreamHandler {
    private List<EventChannel.EventSink> eventSinks = new ArrayList<>();

    static EventChannelPlugin registerWith(FlutterView flutterView) {
        EventChannelPlugin plugin = new EventChannelPlugin();
        new EventChannel(flutterView, "EventChannelPlugin").setStreamHandler(plugin);
        return plugin;
    }

    void sendEvent(Object params) {
        for (EventChannel.EventSink eventSink : eventSinks) {
            eventSink.success(params);
        }
    }

    @Override
    public void onListen(Object args, EventChannel.EventSink eventSink) {
        eventSinks.add(eventSink);
    }

    @Override
    public void onCancel(Object o) {

    }
}
```

这三种类型的类型的Channel都是全双工通信，即A <=> B，Dart可以主动发送消息给platform端，并且platform接收到消息后可以做出回应，同样，platform端可以主动发送消息给Dart端，dart端接收数后返回给platform端。
