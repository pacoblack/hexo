---
title: Activity启动流程
toc: true
date: 2020-06-04 10:08:05
tags:
- android
categories:
- android
---
现在我们来看看Activity的启动流程
<!--more-->
# 整体流程
![整体流程图](http://gityuan.com/images/activity/start_activity_process.jpg)

启动流程：

1. 点击桌面App图标，Launcher进程采用 **Binder IPC** 向system_server进程发起startActivity请求；
2. system_server进程接收到请求后，向zygote进程通过 **socket** 发送创建进程的请求；
3. ygote进程fork出新的子进程，即App进程；
4. App进程，通过 **Binder IPC** 向sytem_server进程发起attachApplication请求；
5. system_server进程在收到请求后，进行一系列准备工作后，再通过 **binder IPC** 向App进程发送scheduleLaunchActivity请求；
6. App进程的binder线程（ApplicationThread）在收到请求后，通过 **handler** 向主线程发送LAUNCH_ACTIVITY消息；
7. 主线程在收到Message后，通过发射机制创建目标Activity，并回调Activity.onCreate()等方法

# 具体流程
![调用流程图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/activity/activity1.jpg)

![UML图](startActivity.jpg)
