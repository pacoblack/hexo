---
title: android系统概览
toc: true
date: 2020-10-14 14:37:56
tags:
- android
categories:
- android
---
已经android开发多年，对android的认识已经不是当年，我们应该能够从更广的角度来观察android
<!--more-->
Android底层内核空间以Linux Kernel作为基石，上层用户空间由Native系统库、虚拟机运行环境、框架层组成，通过系统调用(Syscall)连通系统的内核空间与用户空间。对于用户空间主要采用C++和Java代码编写，通过JNI技术打通用户空间的Java层和Native层(C++/C)，从而连通整个系统。
先来看一张Google官方提供的经典分层架构图，从下往上依次分为Linux内核、HAL、系统Native库和Android运行时环境、Java框架层以及应用层这5层架构，其中每一层都包含大量的子模块或子系统。
![系统](http://gityuan.com/images/android-arch/android-stack.png)

# android架构
首先来看看启动架构图
![启动架构图](http://gityuan.com/images/android-arch/android-boot.jpg)
 Android系统启动过程由上图从下往上的一个过程是由Boot Loader引导开机，然后依次进入 -> Kernel -> Native -> Framework -> App

## Kernel层
Android平台的基础是Linux内核，比如ART虚拟机最终调用底层Linux内核来执行功能。Linux内核的安全机制为Android提供相应的保障，也允许设备制造商为内核开发硬件驱动程序。
- swapper进程(pid=0)：该进程又称为idle进程, 系统初始化过程Kernel由无到有开创的第一个进程, 用于初始化进程管理、内存管理，加载Display,Camera Driver，Binder Driver等相关工作；
- kthreadd进程（pid=2）：是Linux系统的内核进程，会创建内核工作线程kworkder，软中断线程ksoftirqd，thermal等内核守护进程。kthreadd进程是所有内核进程的鼻祖。

## 硬件抽象层(HAL)
硬件抽象层 (HAL) 提供标准接口，HAL包含多个库模块，其中每个模块都为特定类型的硬件组件实现一组接口，比如WIFI/蓝牙模块，当框架API请求访问设备硬件时，Android系统将为该硬件加载相应的库模块。

## Android Runtime & 系统库
每个应用都在其自己的进程中运行，都有自己的虚拟机实例。ART通过执行DEX文件可在设备运行多个虚拟机。ART主要功能包括：预先(AOT)和即时(JIT)编译，优化的垃圾回收(GC)，以及调试相关的支持。

这里的Native系统库主要包括init孵化来的用户空间的守护进程、HAL层以及开机动画等。启动init进程(pid=1),是Linux系统的用户进程，init进程是所有用户进程的鼻祖。
- init进程会孵化出ueventd、logd、healthd、installd、adbd、lmkd等用户守护进程；
- init进程还启动servicemanager(binder服务管家)、bootanim(开机动画)等重要服务
- init进程孵化出Zygote进程，Zygote进程是Android系统的第一个Java进程(即虚拟机进程)，Zygote是所有Java进程的父进程，Zygote进程本身是由init进程孵化而来的。

## Framework层
Zygote进程，是由init进程通过解析init.rc文件后fork生成的，Zygote进程主要包含：
- 加载ZygoteInit类，注册Zygote Socket服务端套接字
  - 加载虚拟机
  - 提前加载类preloadClasses
  - 提前加载资源preloadResouces
- System Server进程，是由Zygote进程fork而来，System Server是Zygote孵化的第一个进程，System Server负责启动和管理整个Java framework，包含ActivityManager，WindowManager，PackageManager，PowerManager等服务。
- Media Server进程，是由init进程fork而来，负责启动和管理整个C++ framework，包含AudioFlinger，Camera Service等服务。

## App层
Zygote进程孵化出的第一个App进程是Launcher，这是用户看到的桌面App；
Zygote进程还会创建Browser，Phone，Email等App进程，每个App至少运行在一个进程上；
所有的App进程都是由Zygote进程fork生成的。

## Syscall && JNI
Native与Kernel之间有一层系统调用(SysCall)层
Java层与Native(C/C++)层之间的纽带JNI

# 通信方式
无论是Android系统，还是各种Linux衍生系统，各个组件、模块往往运行在各种不同的进程和线程内，这里就必然涉及进程/线程之间的通信。对于IPC(Inter-Process Communication, 进程间通信)，Linux现有管道、消息队列、共享内存、套接字、信号量、信号这些IPC机制，Android额外还有Binder IPC机制，Android OS中的Zygote进程的IPC采用的是Socket机制，在上层system server、media server以及上层App之间更多的是采用Binder IPC方式来完成跨进程间的通信。对于Android上层架构中，很多时候是在同一个进程的线程之间需要相互通信，例如同一个进程的主线程与工作线程之间的通信，往往采用的Handler消息机制。

## binder
参考[binder原理](https://pacoblack.github.io/2020/06/02/Binder%E9%80%9A%E4%BF%A1%E5%8E%9F%E7%90%86/)

## Socket
Socket通信方式也是C/S架构，比Binder简单很多。在Android系统中采用Socket通信方式的主要有：

- zygote：用于孵化进程，system_server创建进程是通过socket向zygote进程发起请求；
- installd：用于安装App的守护进程，上层PackageManagerService很多实现最终都是交给它来完成；
- lmkd：lowmemorykiller的守护进程，Java层的LowMemoryKiller最终都是由lmkd来完成；
- adbd：这个也不用说，用于服务adb；
- logcatd:这个不用说，用于服务logcat；
- vold：即volume Daemon，是存储类的守护进程，用于负责如USB、Sdcard等存储设备的事件处理。

## handler
参考[Handler原理](https://pacoblack.github.io/2020/06/02/Handler%E5%8E%9F%E7%90%86/)
