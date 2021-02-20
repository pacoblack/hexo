---
title: Binder通信原理
toc: true
date: 2020-06-02 11:48:22
tags:
- android
categories:
- android
- 原理
---

# 介绍
跨进程通信是需要内核空间做支持的。传统的 IPC 机制如管道、Socket 都是内核的一部分，因此通过内核支持来实现进程间通信自然是没问题的。

但是 Binder 并不是 Linux 系统内核的一部分，通过 Linux 的动态内核可加载模块（Loadable Kernel Module，LKM）的机制。

模块是具有独立功能的程序，它可以被单独编译，但是不能独立运行。它在运行时被链接到内核作为内核的一部分运行。这样，Android 系统就可以通过动态添加一个内核模块运行在内核空间，用户进程之间通过这个内核模块作为桥梁来实现通信。在 Android 系统中，这个模块就是 Binder 驱动（Binder Dirver）

Binder IPC 机制中涉及到的内存映射通过 `mmap()` 来实现，`mmap()` 是操作系统中一种内存映射的方法。内存映射简单的讲就是将用户空间的一块内存区域映射到内核空间。**映射关系建立后，用户对这块内存区域的修改可以直接反应到内核空间；反之内核空间对这段区域的修改也能直接反应到用户空间**。内存映射能减少数据拷贝次数，实现用户空间和内核空间的高效互动。两个空间各自的修改能直接反映在映射的内存区域，从而被对方空间及时感知。也正因为如此，内存映射能够提供对进程间通信的支持。

<!--more-->

# 优势
- 首先进程间的通信方式：管道、消息队列、共享内存、信号量、信号、socket套接字、信号等
- binder 的优势：
 - 拷贝次数：Binder数据拷贝只需要一次，而管道、消息队列、Socket都需要2次，但共享内存方式一次内存拷贝都不需要；从性能角度看，Binder性能仅次于共享内存。
 - 稳定性：基于C/S架构，职能分工明确
 - 安全性： Android系统中对外只暴露Client端，Client端将任务发送给Server端，Server端会根据权限控制策略，判断UID/PID是否满足访问权限。
 - 架构：在Zygote孵化出system_server进程后，在system_server进程中出初始化支持整个Android framework的各种各样的Service，而这些Service从大的方向来划分，分为Java层Framework和Native Framework层(C++)的Service，几乎都是基于BInder IPC机制。

# C/S端
## Java framework
作为Server端继承(或间接继承)于Binder类，Client端继承(或间接继承)于 BinderProxy类。例如 ActivityManagerService(用于控制Activity、Service、进程等) 这个服务作为Server端，间接继承Binder类，而相应的ActivityManager作为Client端，间接继承于BinderProxy类。

## Native Framework层
这是C++层，作为Server端继承(或间接继承)于BBinder类，Client端继承(或间接继承)于BpBinder。例如MediaPlayService(用于多媒体相关)作为Server端，继承于BBinder类，而相应的MediaPlay作为Client端，间接继承于BpBinder类.

# Linux 下的传统 IPC 通信原理
通常的做法是消息发送方将要发送的数据存放在内存缓存区中，通过系统调用进入内核态。然后内核程序在内核空间分配内存，开辟一块内核缓存区，调用 copyfromuser() 函数将数据从用户空间的内存缓存区拷贝到内核空间的内核缓存区中。同样的，接收方进程在接收数据时在自己的用户空间开辟一块内存缓存区，然后内核程序调用 copytouser() 函数将数据从内核缓存区拷贝到接收进程的内存缓存区。这样数据发送方进程和数据接收方进程就完成了一次数据传输，我们称完成了一次进程间通信。如下图：
![传统IPC](ipc.jpeg)

# 内存映射
Binder IPC 机制中涉及到的内存映射通过 mmap() 来实现，mmap() 是操作系统中一种内存映射的方法。内存映射简单的讲就是将用户空间的一块内存区域映射到内核空间。映射关系建立后，用户对这块内存区域的修改可以直接反应到内核空间；反之内核空间对这段区域的修改也能直接反应到用户空间。

内存映射能减少数据拷贝次数，实现用户空间和内核空间的高效互动。两个空间各自的修改能直接反映在映射的内存区域，从而被对方空间及时感知。也正因为如此，内存映射能够提供对进程间通信的支持。

# Binder通信
进程中的用户区域是不能直接和物理设备打交道的，如果想要把磁盘上的数据读取到进程的用户区域，需要两次拷贝（磁盘-->内核空间-->用户空间）；通常在这种场景下 mmap() 就能发挥作用，通过在物理介质和用户空间之间建立映射，减少数据的拷贝次数，用内存读写取代I/O读写，提高文件读取效率。

一次完整的 Binder IPC 通信过程通常如下：
1, 首先 Binder 驱动在内核空间创建一个数据接收缓存区；
2, 接着在内核空间开辟一块内核缓存区，建立**内核缓存区**和**数据接收缓存区**之间的映射关系，以及数据接收缓存区和接收进程用户空间地址的映射关系；
3, 发送方进程通过系统调用 copyfromuser() 将数据 copy 到内核中的内核缓存区，由于内核缓存区和接收进程的用户空间存在内存映射，因此也就相当于把数据发送到了接收进程的用户空间，这样便完成了一次进程间的通信。
![通信过程](https://raw.githubusercontent.com/pacoblack/BlogImages/master/binder/binder1.jpg)

# 通信模型
Binder 是基于 C/S 架构的，由Client、Server、ServiceManager、BinderDriver 四部分组成。其中 Client、Server、ServiceManager 运行在用户空间，BinderDriver 运行在内核空间。其中 ServiceManager 和 BinderDriver 由系统提供，而 Client、Server 由应用程序来实现。Client、Server 和 ServiceManager 均是通过系统调用 open、mmap 和 ioctl 来访问设备文件 /dev/binder，从而实现与 BinderDriver 的交互来间接的实现跨进程通信。
![通信结构模型](https://raw.githubusercontent.com/pacoblack/BlogImages/master/binder/binder2.jpg)
> **Binder 驱动**
Binder 驱动是整个通信的核心；驱动负责进程之间 Binder 通信的建立，Binder 在进程之间的传递，Binder 引用计数管理，数据包在进程之间的传递和交互等一系列底层支持。
**ServiceManager 与 Server Binder**
Server 创建了 Binder，并为它起一个字符形式，可读易记得名字，将这个 Binder 实体连同名字一起以数据包的形式通过 BinderDriver 发送给 ServiceManager ，通知 ServiceManager 注册 Binder。驱动为这个穿越进程边界的 Binder 创建位于内核中的**实体节点**以及 ServiceManager 对**实体的引用**，将名字以及新建的引用打包传给 ServiceManager。ServiceManger 收到数据后从中取出名字和引用填入查找表。
我们知道，ServierManager 是一个进程，Server 是另一个进程，Server 向 ServiceManager 中注册 Binder 必然涉及到进程间通信。ServiceManager 和其他进程同样采用 Binder 通信，ServiceManager 是 Server 端，有自己的 Binder 实体，其他进程都是 Client。ServiceManager 提供的 Binder 比较特殊，它没有名字也不需要注册。当一个进程使用 BINDERSETCONTEXT_MGR 命令将自己注册成 ServiceManager 时**Binder 驱动会自动为它创建 Binder 实体**。其次这个 Binder 实体的引用在所有 Client 中都固定为 0 而无需通过其它手段获得。也就是说，一个 Server 想要向 ServiceManager 注册自己的 Binder 就必须通过这个 0 号引用和 ServiceManager 的 Binder 通信。
**ServiceManager 与 Client Binder**
Server 向 ServiceManager 中注册了 Binder 以后， Client 就能通过名字获得 Binder 的引用了。Client 也利用保留的 0 号引用向 ServiceManager 请求访问某个 Binder，ServiceManager 收到这个请求后从请求数据包中取出 Binder 名称，在查找表里找到对应的条目，取出对应的 Binder 引用作为回复发送给发起请求的 Client。从面向对象的角度看，Server 中的 Binder 实体现在有两个引用：一个位于 ServiceManager 中，一个位于发起请求的 Client 中。如果接下来有更多的 Client 请求该 Binder，系统中就会有更多的引用指向该 Binder 。

大致总结出 Binder 通信过程：
1, 一个进程使用 BINDERSETCONTEXT_MGR 命令通过 Binder 驱动将自己注册成为 ServiceManager；
2, Server 通过驱动向 ServiceManager 中注册 Binder（Server 中的 Binder 实体），表明可以对外提供服务。驱动为这个 Binder 创建位于内核中的实体节点以及 ServiceManager 对实体的引用，将名字以及新建的引用打包传给 ServiceManager，ServiceManger 将其填入查找表。
3, Client 通过名字，在 Binder 驱动的帮助下从 ServiceManager 中获取到对 Binder 实体的引用，通过这个引用就能实现和 Server 进程的通信。
![通信过程模型](https://raw.githubusercontent.com/pacoblack/BlogImages/master/binder/binder3.jpg)
其中是从绿色的箭头开始，server -> Binder 驱动 -> ServiceManager , Client -> Binder 驱动  -> ServiceManager -> Binder驱动 -> Client

![Binder 通信协议](https://raw.githubusercontent.com/pacoblack/BlogImages/master/binder/binder4.jpg)
- Binder客户端或者服务端向Binder Driver发送的命令都是以BC_开头,例如本文的BC_TRANSACTION和BC_REPLY, 所有Binder Driver向Binder客户端或者服务端发送的命令则都是以BR_开头, 例如本文中的BR_TRANSACTION和BR_REPLY.
- 只有当BC_TRANSACTION或者BC_REPLY时, 才调用binder_transaction()来处理事务. 并且都会回应调用者一个BINDER_WORK_TRANSACTION_COMPLETE事务, 经过binder_thread_read()会转变成BR_TRANSACTION_COMPLETE.
- 在A端向B写完数据之后，A会返回给自己一个BR_TRANSACTION_COMPLETE命令，告知自己数据已经成功写入到B的Binder内核空间中去了，如果是需要回复，在处理完 BR_TRANSACTION_COMPLETE 命令后会继续阻塞等待结果的返回
```
status_t IPCThreadState::waitForResponse(Parcel *reply, status_t *acquireResult){
    ...
  while (1) {
    if ((err=talkWithDriver()) < NO_ERROR) break;
     cmd = mIn.readInt32();
    switch (cmd) {
       <!--关键点1 -->
      case BR_TRANSACTION_COMPLETE:
            if (!reply && !acquireResult) goto finish;
            break;
     <!--关键点2 -->
      case BR_REPLY:
            {
                binder_transaction_data tr;
                  // free buffer，先设置数据，直接
                if (reply) {
                    if ((tr.flags & TF_STATUS_CODE) == 0) {
                        // 牵扯到数据利用，与内存释放
                        reply->ipcSetDataReference(...)
            }
            goto finish;
    }
 finish:
 ...
return err;
}
```
客户端通过talkWithDriver等待结果返回，如果没有返回值，直接break，否则会执行到*关键点2*，就上图来说，就是发送了 BR_TRANSACTION，而不会有 BC_REPLY。

# Android 对 Binder 的支持
由于Android 的app都是从Zygote进程fork出来的，Zygote.forkAndSpecialize()用来 fork 新进程，通过RuntimeInit.nativeZygoteInit来初始化一些环境，通过 runSelectLoop来循环监听 socket，等待fork请求。
![Android对Binder支持原理](https://raw.githubusercontent.com/pacoblack/BlogImages/master/binder/binder5.png)
首先，ProcessState::self()函数会调用open()打开/dev/binder设备，这个时候能够作为Client通过Binder进行远程通信；其次，proc->startThreadPool()负责新建一个binder线程，监听Binder设备，这样进程就具备了作为Binder服务端的资格。每个APP的进程都会通过onZygoteInit打开Binder，既能作为Client，也能作为Server，这就是Android进程天然支持Binder通信的原因。

问：Android APP有多少Binder线程，是固定的么
答：Android APP上层应用的进程一般是开启一个Binder线程，而对于SystemServer或者media服务等使用频率高，服务复杂的进程，一般都是开启两个或者更多。驱动会根据目标进程中是否存在足够多的Binder线程来告诉进程是不是要新建Binder线程,所以是不固定的
```
int main(int argc, char** argv)
{      ...
        ProcessState::self()->startThreadPool();
        IPCThreadState::self()->joinThreadPool();
 }
```

参考：
[https://zhuanlan.zhihu.com/p/35519585](https://zhuanlan.zhihu.com/p/35519585)
[http://gityuan.com/2014/01/01/binder-gaishu/](http://gityuan.com/2014/01/01/binder-gaishu/)
[https://juejin.im/post/58c90816a22b9d006413f624](https://juejin.im/post/58c90816a22b9d006413f624)
