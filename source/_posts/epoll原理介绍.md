---
title: epoll原理介绍
toc: true
date: 2020-06-02 10:59:37
tags:
- android
categories:
- android
- 原理
---
# 文件描述符fd
文件描述符是一个索引值，指向该进程打开文件的记录表，这个表是由内核为相应进程维护的。当程序打开一个现有文件或者创建一个新文件时，内核就会给进程返回一个文件描述符fd。
<!--more-->

# 缓存I/O
在 Linux 的缓存 I/O 机制中，数据会先被拷贝到操作系统内核的缓冲区中，然后才会从操作系统内核的缓冲区拷贝到应用程序的地址空间，即文件系统的也缓存（ page cache ）。

# I/O模式
- 阻塞 I/O
 ![阻塞模型](https://raw.githubusercontent.com/pacoblack/BlogImages/master/epoll/epoll1.png)
用户等待数据被阻塞，内核等待数据被阻塞，然后从内核拷贝到用户内存，内核返回结果，用户进程才解除阻塞

- 非阻塞 I/O (轮询)
![非阻塞模型](https://raw.githubusercontent.com/pacoblack/BlogImages/master/epoll/epoll2.png)
当用户进程发出read操作时，如果kernel中的数据还没有准备好，那么它并不会block用户进程，而是立刻返回一个error。用户进程判断结果是一个error时，它就知道数据还没有准备好，于是它可以再次发送read操作。一旦kernel中的数据准备好了，并且又再次收到了用户进程的system call，那么它马上就将数据拷贝到了用户内存，然后返回。

- I/O 多路复用
![多路复用模型](https://raw.githubusercontent.com/pacoblack/BlogImages/master/epoll/epoll3.png)
就是我们说的select，poll，epoll，有的也称这种IO方式为事件驱动 I/O。
单个process就可以同时处理多个网络连接的IO，select方法会不断的轮询所负责的所有socket，当某个socket有数据到达了，就通知用户进程。
`当用户进程调用了select，那么整个进程会被block`，而同时，kernel会“监视”所有select负责的socket，当任何一个socket中的数据准备好了，select就会返回。这个时候用户进程再调用read操作，将数据从kernel拷贝到用户进程。
与阻塞IO的区别是可以同时处理多个连接，但需要两个system call (select 和 recvfrom)
- 信号驱动 I/O
（无）
- 异步 I/O
![异步IO模型](https://raw.githubusercontent.com/pacoblack/BlogImages/master/epoll/epoll4.png)
用户进程发起read操作之后，立刻就可以开始去做其它的事。而另一方面，从kernel的角度，当它收到一个asynchronous read之后，首先它会立刻返回，所以不会对用户进程产生任何block。然后，kernel会等待数据准备完成，然后将数据拷贝到用户内存，当这一切都完成之后，kernel会给用户进程发送一个signal，告诉它read操作完成了。

# 五种模型对比图
![多个IO模型对比](https://raw.githubusercontent.com/pacoblack/BlogImages/master/epoll/epoll5.png)

# 异步I/O 介绍
## select
![select工作模型](https://raw.githubusercontent.com/pacoblack/BlogImages/master/epoll/epoll6.jpg)
用户首先将需要进行IO操作的socket添加到select中，然后阻塞等待select系统调用返回。当数据到达时，socket被激活，select函数返回。用户线程正式发起read请求，读取数据并继续执行。
从流程上来看，使用select函数进行IO请求和同步阻塞模型没有太大的区别，甚至还多了添加监视socket，以及调用select函数的额外操作，效率更差。但是，使用select以后最大的优势是用户可以在一个线程内同时处理多个socket的IO请求。用户可以注册多个socket，然后不断地调用select读取被激活的socket，即可达到在同一个线程内同时处理多个IO请求的目的。而在同步阻塞模型中，必须通过多线程的方式才能达到这个目的。

### API
```
int select (int n, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout);
```
select 函数监视的文件描述符分3类，分别是writefds、readfds、和exceptfds。调用后select函数会阻塞，直到有描述符就绪（有数据 可读、可写、或者有except），或者超时（timeout指定等待时间，如果立即返回设为null即可），函数返回。当select函数返回后，可以 通过遍历fdset，来找到就绪的描述符。
**select目前几乎在所有的平台上支持，缺点在于单个进程能够监视的文件描述符的数量存在最大限制，在Linux上一般为1024**，可以通过修改宏定义甚至重新编译内核的方式提升这一限制，但是这样也会造成效率的降低。

## poll
poll的机制与select类似，与select在本质上没有多大差别，管理多个描述符也是进行轮询，根据描述符的状态进行处理，但是 **poll没有最大文件描述符数量的限制** 。poll和select同样存在一个缺点就是，包含大量文件描述符的数组被整体复制于用户态和内核的地址空间之间，而不论这些文件描述符是否就绪，它的开销随着文件描述符数量的增加而线性增大。
```
int poll (struct pollfd *fds, unsigned int nfds, int timeout);
struct pollfd {
    int fd; /* file descriptor */
    short events; /* requested events to watch */
    short revents; /* returned events witnessed */
};
```
pollfd结构包含了要监视的event和发生的event，poll返回后，需要轮询pollfd来获取就绪的描述符。

## epoll
```
// 创建一个epoll的句柄，size用来告诉内核这个监听的数目一共有多大
// 参数size并不是限制了epoll所能监听的描述符最大个数，只是对内核初始分配内部数据结构的一个建议
// 当创建好epoll句柄后，它就会占用一个fd值，在linux下如果查看/proc/进程id/fd/，
// 在使用完epoll后，必须调用close()关闭，否则可能导致fd被耗尽。
int epoll_create(int size)；

// epoll_ctl 对指定描述符fd执行op操作
// epfd：是epoll_create()的返回值。
// op：表示op操作，用三个宏来表示：添加EPOLL_CTL_ADD，删除EPOLL_CTL_DEL，修改EPOLL_CTL_MOD。分别添加、删除和修改对fd的监听事件。
// fd：是需要监听的fd（文件描述符）
// epoll_event：是告诉内核需要监听什么事，struct epoll_event结构如下：
struct epoll_event {
  __uint32_t events;  /* Epoll events */
  epoll_data_t data;  /* User data variable */
};

// events可以是以下几个宏的集合：
// EPOLLIN ：表示对应的文件描述符可以读（包括对端SOCKET正常关闭）；
// EPOLLOUT：表示对应的文件描述符可以写；
// EPOLLPRI：表示对应的文件描述符有紧急的数据可读（这里应该表示有带外数据到来）；
// EPOLLERR：表示对应的文件描述符发生错误；
// EPOLLHUP：表示对应的文件描述符被挂断；
// EPOLLET： 将EPOLL设为边缘触发(Edge Triggered)模式，这是相对于水平触发(Level Triggered)来说的。
// EPOLLONESHOT：只监听一次事件，当监听完这次事件之后，如果还需要继续监听这个socket的话，需要再次把这个socket加入到EPOLL队列里
int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event)；

// 等待epfd上的io事件，最多返回maxevents个事件。
// 参数events用来从内核得到事件的集合，maxevents告之内核这个events有多大，
// 这个maxevents的值不能大于创建epoll_create()时的size，参数timeout是超时时间（毫秒，0会立即返回，-1将不确定，也有说法说是永久阻塞）。
// 该函数返回需要处理的事件数目，如返回0表示已超时。
int epoll_wait(int epfd, struct epoll_event * events, int maxevents, int timeout);
```
相对于select和poll来说，epoll更加灵活，没有描述符限制。epoll使用**一个文件描述符管理多个描述符**，将用户关系的文件描述符的事件存放到内核的一个事件表中，这样在用户空间和内核空间的copy只需一次。

### 工作模式
epoll对文件描述符的操作有两种模式：LT（level trigger）和ET（edge trigger）。LT模式是默认模式，LT模式与ET模式的区别如下：
　　LT模式：当epoll_wait检测到描述符事件发生并将此事件通知应用程序，应用程序`可以不立即处理`该事件。下次调用epoll_wait时，会再次响应应用程序并通知此事件。**如果你不作任何操作，内核还是会继续通知你的。**
　　ET(高速)模式：当epoll_wait检测到描述符事件发生并将此事件通知应用程序，应用程序`必须立即处理`该事件。如果不处理，下次调用epoll_wait时，不会再次响应应用程序并通知此事件。
### 小结
在 select/poll中，进程只有在调用一定的方法后，内核才对所有监视的文件描述符进行扫描，而epoll事先通过epoll_ctl()来注册一个文件描述符，**一旦某个文件描述符就绪时，内核会采用类似callback的回调机制，迅速激活这个文件描述符**，当进程调用epoll_wait() 时便得到通知。
epoll 监视的描述符数量不受限制，它所支持的FD上限是最大可以打开文件的数目，这个数字一般远大于2048,举个例子,在1GB内存的机器上大约是10万左右，具体数目可以cat /proc/sys/fs/file-max察看,一般来说这个数目和系统内存关系很大。select的最大缺点就是进程打开的fd是有数量限制的。这对于连接数量比较大的服务器来说根本不能满足。

### 实现结构
![epoll内部数据结构](https://raw.githubusercontent.com/pacoblack/BlogImages/master/epoll/epoll7.png)
调用epoll_create后，内核就已经在内核态开始准备帮你存储要监控的句柄了，每次调用epoll_ctl只是在往内核的数据结构里塞入新的socket句柄。

在内核里，一切皆文件。所以，epoll向内核注册了一个文件系统，用于存储上述的被监控socket。当你调用epoll_create时，就会在这个**虚拟的epoll文件系统里创建一个file结点**。当然这个file不是普通文件，它只服务于epoll。

epoll在被内核初始化时（操作系统启动），同时会开辟出epoll自己的内核高速cache区，用于安置每一个我们想监控的socket，这些socket会以红黑树的形式保存在内核cache里，以支持快速的查找、插入、删除。这个内核高速cache区，就是建立连续的物理内存页，然后在之上建立slab层，简单的说，就是物理上分配好你想要的size的内存对象，每次使用时都是使用空闲的已分配好的对象。

在内核cache里建了个红黑树用于存储以后epoll_ctl传来的socket外，还会再建立一个list链表，用于存储准备就绪的事件，当epoll_wait调用时，仅仅观察这个list链表里有没有数据即可。有数据就返回，没有数据就sleep，等到timeout时间到后即使链表没数据也返回。所以，epoll_wait非常高效。

通常情况下即使我们要监控百万计的句柄，大多一次也只返回很少量的准备就绪句柄而已，所以，**epoll_wait仅需要从内核态copy少量的句柄到用户态而已**，所以会显得非常高效。

关于就绪list，当我们执行epoll_ctl时，除了把socket放到epoll文件系统里file对象对应的红黑树上之外，还会给**内核中断处理程序**注册一个回调函数，告诉内核，如果这个句柄的中断到了，就把它放到准备就绪list链表里。所以，当一个socket上有数据到了，内核在把网卡上的数据copy到内核中后，就把socket插入到准备就绪链表里了。

[epoll在input服务中的应用](https://www.jianshu.com/p/ada73604871e)

[epoll在messageQueue中的应用](https://www.jianshu.com/p/f00c3fa9e6c0)


参考：
[https://segmentfault.com/a/1190000003063859](https://segmentfault.com/a/1190000003063859)
