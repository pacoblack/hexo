---
title: android设备id方案对比
toc: true
date: 2020-10-19 20:07:25
tags:
- android
categories:
- android
---
我们看一下获取android设备ID的方案优缺点
<!--more-->
# 对比
|标识|描述|权限|缺点|
|:--|:--|:--|:--|
|IMEI(国际移动设备识别码)|15位数字组成，与每台手机一一对应，且全球唯一，是GSM设备返回的，并且是写在主板上的，重装APP不会改变IMEI|READ_PHONE_STATE| 需要 READ_PHONE_STATE 权限<br>Android 6.0以后, 这类权限要动态申请<br>Android 10.0 将彻底禁止第三方应用获取设备的IMEI（即使申请了 READ_PHONE_STATE 权限|
|MEID(全球唯一的56bit CDMA制式移动终端标识号)|14位数字，标识号会被烧入终端里，且不能被修改|READ_PHONE_STATE|需要付费的。目前的价格是每1M范围的MEID的费用是8000美元|
|Serial(序列码)|是为了验证“产品的合法身份”而引入的，它是用来保障用户的正版权益，享受合法服务的；一套正版的产品只对应一组产品序列号|READ_PHONE_STATE|对于定位SDK高于Build.VERSION_CODES.O_MR1的应用，此字段设置为UNKNOWN。26以后被弃用，getSerial ()替代，需要动态申请READ_PHONE_STATE权限|
|deviceId|它根据不同的手机设备返回IMEI，MEID或ESN码；它返回的是设备的真实标识|READ_PHONE_STATE|Q上无法正常获取<br>之前的需要动态申请权限|
|Advertising ID|广告id|	android.permission.INTERNET|没有谷歌服务会抛出异常|
|ANDROID_ID|设备首次启动时，系统会随机生成一个64位的数字，并把这个数字以16进制字符串的形式保存下来。当设备被wipe后该值会被重置|无|不同签名的APP，获取到的Android ID不一样<br>刷机、root、恢复出厂设置等会使得 Android ID 改变|
|MAC地址|ip地址|ACCESS_WIFI_STATE<br>BLUETOOTH|如果WiFi没有打开过，是无法获取其Mac地址的（高版本获取到的mac将是固定的：02:00:00:00:00:00）<br>[高版本好像有方法可以获取到](https://blog.csdn.net/chaozhung_no_l/article/details/78329371)<br>蓝牙是只有在打开的时候才能获取到其Mac地址（需要动态申请权限）|

# IMEI
- Android 6.0以下：无需申请权限，可以通过 `getDeviceId()` 方法获取到IMEI码
- Android 6.0-Android 8.0：需要申请READ_PHONE_STATE权限，可以通过 `getDeviceId()` 方法获取到IMEI码，如果用户拒绝了权限，会抛出java.lang.SecurityException异常
- Android 8.0-Android 10：需要申请READ_PHONE_STATE权限，可以通过 `getImei()` 方法获取到IMEI码，如果用户拒绝了权限，会抛出java.lang.SecurityException异常
- Android 10及以上：分为以下两种情况：
    - targetSdkVersion<29：没有申请权限的情况，通过 `getImei()` 方法获取IMEI码时抛出java.lang.SecurityException异常；申请了权限，通过 `getImei()` 方法获取到IMEI码为null
    - targetSdkVersion=29：无论是否申请了权限，通过 `getImei()` 方法获取IMEI码时都会直接抛出java.lang.SecurityException异常

IMEI码在Android 10之后已经无法获取到了，而且甚至会直接抛出异常导致程序崩溃，在Android 10以下版本虽然可以获取到IMEI码，但是需要在应用获取到 `了READ_PHONE_STATE` 权限的前提下，我们依然无法保证这一点。

# 设备序列号
- Android 8.0以下：无需申请权限，可以通过Build.SERIAL获取到设备序列号
- Android 8.0-Android 10：需要申请READ_PHONE_STATE权限，可以通过Build.getSerial()获取到设备序列号，如果用户拒绝了权限，会抛出java.lang.SecurityException异常
- Android 10及以上：分为以下两种情况：
    - targetSdkVersion<29：没有申请权限的情况，调用Build.getSerial()方法时抛出java.lang.SecurityException异常；申请了权限，通过Build.getSerial()方法获取到的设备序列号为“unknown”
    - targetSdkVersion=29：无论是否申请了权限，调用Build.getSerial()方法时都会直接抛出java.lang.SecurityException异常
