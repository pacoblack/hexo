---
title: ndk 入门
toc: true
date: 2019-11-01 10:20:44
tags:
- NDK
categories:
- NDK
---
介绍在项目中添加ndk支持
<!--more-->
# 配置环境
//TODO，暂时忽略

# NDK支持
由于在同一个工程中，同时支持 cmake 和 ndk-build 两种方式编译 so 文件，可以让 cmake、ndk-build 区分不同的module进行编译。

# CMake module
要创建一个可以用作 CMake 编译脚本的纯文本文件，请按以下步骤操作：
1. 从 IDE 的左侧打开 Project 窗格，然后从下拉菜单中选择 Project 视图。
2. 右键点击 your-module 的根目录，然后依次选择 New > File
3. 入“CMakeLists.txt”作为文件名，然后点击 OK。

## CMakeLists.txt cmake编译配置文件
```shell
cmake_minimum_required(VERSION 3.4.1)

add_library(
        hello-jni # so 库的名称 libhello-jni.so
        SHARED # 设置为分享库
        # 指定C源文件的路径，指向公共cpp-src目录
        ../../../../cpp-src/hello-jni.c
)

find_library(
        log-lib # 设置路径变量名称
        log # 指定CMake需要加载的NDK库
)

# 链接hello-jni库依赖的库，注意下面变量名的配置
target_link_libraries(hello-jni
        ${log-lib}
)
```
[官方文档](https://developer.android.google.cn/ndk/guides/cmake)去了解更多

## AndroidManifes.xml
```xml
<?xml version="1.0" encoding="UTF-8" ?>
<manifest package="com.flueky.cmake">

</manifest>
```
## Build.gradle 的配置
```Groovy
apply plugin: 'com.android.library'

android {
    compileSdkVersion 28

    defaultConfig{
        externalNativeBuild {
            cmake {
                // 指定配置参数，更多参数设置见 https://developer.android.google.cn/ndk/guides/cmake
                arguments "-DCMAKE_BUILD_TYPE=DEBUG"
                // 添加CPP标准
                // cppFlags "-std=c++11"
            }
        }
    }

    externalNativeBuild { //配置是生成Gradle Task 可以不运行工程，
      // 直接在 ndk-cmake -> Tasks -> other 找到编译 so 文件有关的四个任务。
        cmake {
            // 指定CMake编译配置文件路径
            path "src/main/cpp/CMakeLists.txt"
        }
    }
}
```

# ndk-build
在配置得当的情况下，可以在不打开 AndroidStudio 情况下完成so文件的编译和输出。
创建 ndk-build module ,添加4个文件
## Android.mk
```c
# 讲真，这个参数我看不懂。从 官方demo 抄来的。用于指定源文件的时候使用
abspath_wa = $(join $(filter %:,$(subst :,: ,$1)),$(abspath $(filter-out %:,$(subst :,: ,$1))))

# 指定当前路径
LOCAL_PATH := $(call my-dir)

# 指定源文件路径
JNI_SRC_PATH := $(call abspath_wa, $(LOCAL_PATH)/../../../../cpp-src)

# 声明 clear 变量
include $(CLEAR_VARS)

# 指定 so 库的名称 libhello-jni.so
LOCAL_MODULE    := hello-jni
# 指定 c 源文件
LOCAL_SRC_FILES := $(JNI_SRC_PATH)/hello-jni.c
# 添加需要依赖的NDK库
LOCAL_LDLIBS := -llog -landroid
# 指定为分享库
include $(BUILD_SHARED_LIBRARY)
```
[Andriod.mk 官方资料](https://developer.android.google.cn/ndk/guides/android_mk)去了解更多

## Application.mk
```shell
# 指定编译的的so版本
APP_ABI := all
# 指定 APP 平台版本。比 android:minSdkVersion 值大时，会有警告
APP_PLATFORM := android-28
```
[Application.mk 官方资料](https://developer.android.google.cn/ndk/guides/application_mk)去了解更多

## AndroidManifest.xml
```xml
<?xml version="1.0" encoding="UTF-8" ?>
<manifest package="com.flueky.ndk">

</manifest>
```

## build.gradle
```Groovy
apply plugin: 'com.android.library'

android {
    compileSdkVersion 28
    externalNativeBuild {
        ndkBuild {
            // 指定mk文件路径
            path 'src/main/jni/Android.mk'
        }
    }
    defaultConfig {
    }
}
```

在 jni 目录执行 `ndk-build` 即可，在 libs 目录下可以找到所有的so 文件

# 示例
java 端
```java
public class MainActivity extends Activity {

    static {
        // 加载 JNI 库
        System.loadLibrary("hello-jni");
    }

    ......

    // 声明 Native 方法
    private native String hello();
}
```

ndk 端
```c
#include <string.h>
#include <jni.h>
#include "com_flueky_demo_MainActivity.h"
#include "util/log.h"

/**
 * JNI 示例，演示native方法返回一个字符串，Java 源码见
 *
 * ndk-sample/app/src/main/java/com/flueky/demo/MainActivity.java
 */
JNIEXPORT jstring JNICALL
Java_com_flueky_demo_MainActivity_hello( JNIEnv* env,
                                                  jobject thiz )
{
#if defined(__arm__)
    #if defined(__ARM_ARCH_7A__)
        #if defined(__ARM_NEON__)
            #if defined(__ARM_PCS_VFP)
                #define ABI "armeabi-v7a/NEON (hard-float)"
            #else
                #define ABI "armeabi-v7a/NEON"
            #endif
        #else
            #if defined(__ARM_PCS_VFP)
                #define ABI "armeabi-v7a (hard-float)"
            #else
                #define ABI "armeabi-v7a"
            #endif
        #endif
    #else
        #define ABI "armeabi"
    #endif
#elif defined(__i386__)
    #define ABI "x86"
#elif defined(__x86_64__)
    #define ABI "x86_64"
#elif defined(__mips64)  /* mips64el-* toolchain defines __mips__ too */
    #define ABI "mips64"
#elif defined(__mips__)
    #define ABI "mips"
#elif defined(__aarch64__)
    #define ABI "arm64-v8a"
#else
    #define ABI "unknown"
#endif

    LOGD("日志输出示例");

    return (*env)->NewStringUTF(env, "Hello from JNI !  Compiled with ABI " ABI ".");
}
```
