---
title: ok/IO分析
toc: true
date: 2021-03-14 11:05:34
tags:
- android
categories:
- android
---
简单介绍下
<!--more-->
# http2.0
![](https://raw.githubusercontent.com/pacoblack/BlogImages/master/http/http1.png)
- 新的二进制格式。HTTP 1.x的解析是基于文本。
- 多路复用。一个request对应一个id，这样一个连接上可以有多个requst，每个连接的request可以随机的混杂在一起，接受方可以根据request的id将request再归属到各自不同的服务端请求里面
- 请求优先级。把HTTP消息分解为很多独立的帧后，就可以通过优化这些帧的交错和传输顺序，进一步提供性能。
- header压缩。HTTP1.x的header带有大量的信息，而且每次都要重复发送，HTTP2.0使用encoder来减少需要传输的header大小，通讯双方各自cache一个header field表，既避免了重复的header传输，又减少了需要传输的大小。
- 服务端推送
- 新增的二进制分帧层。它定义了如何封装HTTP消息并在客户端与服务器之间传输
![](https://raw.githubusercontent.com/pacoblack/BlogImages/master/http/http2.png)

所有HTTP 2.0通信都在一个连接上完成，这个连接可以承载任意数量的双向数据流。每个数据流以消息的形式发送。而消息由一或多个帧组成，而这些帧可以乱序发送，然后再根据每个帧首部流标识符重新组装。

# ok I/O
ok I/O是用的NIO的通信方式

有Source和Sink两个接口，类似于InputStream和OutputStream，是io操作的顶级接口类,这两个接口均实现了Closeable接口。所以可以把Source简单的看成InputStream，Sink简单看成OutputStream。

## Segment
okio将数据分割成一块块的片段，内部维护者固定长度的byte[]数组，同时segment拥有前面节点和后面节点，构成一个双向循环链表
![](https://raw.githubusercontent.com/pacoblack/BlogImages/master/http/http3.png)

分片中使用数组存储，兼具读的连续性，以及写的可插入性，对比单一使用链表或者数组，是一种折中的方案，读写更快，而且有个好处根据需求改动分片的大小来权衡读写的业务操作，另外，segment也有一些内置的优化操作

- compact 压缩
这是segment的一个优化技巧，写入数据后，因为每个segment的片段size是固定的，为了防止经过长时间的使用后，每个segment中的数据被分割的十分严重，可能一个很小的数据却占据了整个segment，所以有了一个压缩机制。
```Java
public void compact() {
  //上一个节点就是自己，意味着就一个节点，无法压缩，抛异常
  if (prev == this) throw new IllegalStateException();
   //如果上一个节点不是自己的，所以你是没有权利压缩的
  if (!prev.owner) return; // Cannot compact: prev isn't writable.
  //能进来说明，存在上一个节点，且上一个节点是自己的，可以压缩
  //记录当前Segment具有的数据，数据大小为limit-pos
  int byteCount = limit - pos;
  // 统计前结点是否被共享，如果共享则只记录Size-limit大小，
  // 如果没有被共享，则加上pre.pos之前的空位置；
  //本行代码主要是获取前一个segment的可用空间。
  // 先判断prev是否是共享的，如果是共享的，则只记录SIZE-limit,
  // 如果没有共享则记录SIZE-limit加上prev.pos之前的空位置
  int availableByteCount = SIZE - prev.limit + (prev.shared ? 0 : prev.pos);
 //判断prev的空余空间是否能够容纳Segment的全部数据，不能容纳则返回
  if (byteCount > availableByteCount) return;
  //能容纳则将自己的这个部分数据写入上一个Segment
  writeTo(prev, byteCount);
  //讲当前Segment从Segment链表中移除
  pop();
  //回收该Segment
  SegmentPool.recycle(this);
}
```
>如果前面的Segment是共享的，那么不可写，也不能压缩，接着判断前一个的剩余大小是否比当前空间大，如果有足够的空间来容纳数据，调用前面的writeTo方法写入数据，写完以后，移除当前segment，并回收segment。

- 共享 split()方法
为了减少数据复制带来的性能开销。先把Segment一分为二，将(pos + 1, pos + btyeCount - 1)的内容给新的Segment,将(pos + byteCount, limit - 1)的内容留给自己.

## SegemtnPool
SegmentPool是一个Segment池，由一个单项链表构成。该池负责Segment的回收和闲置Segment管理，也就是说Buffer使用的Segment是从Segment单项链表中取出的，这样有效的避免了GC频率.
```Java
//一个Segment记录的最大长度是8192，因此SegmentPool只能存储8个Segment
static final long MAX_SIZE = 64 * 1024;
//该SegmentPool存储了一个回收Segment的链表
static Segment next;
//该值记录了当前所有Segment的总大小，最大值是为MAX_SIZE
static long byteCount;  
它的两个重要的方法 take(), recycle()


  static Segment take() {
    synchronized (SegmentPool.class) {
      if (next != null) {
        Segment result = next;
        next = result.next;
        result.next = null;
        byteCount -= Segment.SIZE;
        return result;
      }
    }
    return new Segment(); // Pool is empty. Don't zero-fill while holding a lock.
  }

  static void recycle(Segment segment) {
    //如果这个要回收的Segment被前后引用，则无法回收
    if (segment.next != null || segment.prev != null) throw new IllegalArgumentException();
    //如果这个要回收的Segment的数据是分享的，则无法回收
    if (segment.shared) return; // This segment cannot be recycled.
    //加锁
    synchronized (SegmentPool.class) {
      //如果 这个空间已经不足以再放入一个空的Segment，则不回收
      if (byteCount + Segment.SIZE > MAX_SIZE) return; // Pool is full.
      //设置SegmentPool的池大小
      byteCount += Segment.SIZE;
      //segment的下一个指向头
      segment.next = next;
      //设置segment的可读写位置为0
      segment.pos = segment.limit = 0;
      //设置当前segment为头
      next = segment;
    }
  }
```

超时
```Java
 private static final class Watchdog extends Thread {
    public Watchdog() {
      super("Okio Watchdog");
      setDaemon(true);
    }

    public void run() {
      while (true) {
        try {
          AsyncTimeout timedOut;
          synchronized (AsyncTimeout.class) {
            timedOut = awaitTimeout();

            // Didn't find a node to interrupt. Try again.
            if (timedOut == null) continue;

            // The queue is completely empty. Let this thread exit and let another watchdog thread
            // get created on the next call to scheduleTimeout().
            if (timedOut == head) {
              head = null;
              return;
            }
          }

          // Close the timed out node.
          timedOut.timedOut();
        } catch (InterruptedException ignored) {
        }
      }
    }
  }
```
这里的WatchDog只是一个继承于Thread的一类，里面的run方法执行的就是超时的判断，之所以在socket写时采取异步超时，这完全是由socket自身的性质决定的，socket经常会阻塞自己，导致下面的事情执行不了。

## enter、exit
```java
  public final Source source(final Source source) {
    return new Source() {
      @Override public long read(Buffer sink, long byteCount) throws IOException {
        boolean throwOnTimeout = false;
        enter();
        try {
          long result = source.read(sink, byteCount);
          throwOnTimeout = true;
          return result;
        } catch (IOException e) {
          throw exit(e);
        } finally {
          exit(throwOnTimeout);
        }
      }
 }

private static synchronized void scheduleTimeout(
      AsyncTimeout node, long timeoutNanos, boolean hasDeadline) {
    //head==null，表明之前没有，本次是第一次操作，开启Watchdog守护线程
    if (head == null) {
      head = new AsyncTimeout();
      new Watchdog().start();
    }

    long now = System.nanoTime();
    //如果有 deadLine，并且超时时长不为0
    if (timeoutNanos != 0 && hasDeadline) {
      //对比最长限制和超时时长，选择最小的那个值
      node.timeoutAt = now + Math.min(timeoutNanos, node.deadlineNanoTime() - now);
    } else if (timeoutNanos != 0) {
      //如果没有最长限制，但是超时时长不为0，则使用超时时长
      node.timeoutAt = now + timeoutNanos;
    } else if (hasDeadline) {
      //如果有最长限制，但是超时时长为0，则使用最长限制
      node.timeoutAt = node.deadlineNanoTime();
    } else {
     //如果既没有最长限制，和超时时长，则抛异常
      throw new AssertionError();
    }

    // 按照排序顺序插入
    long remainingNanos = node.remainingNanos(now);
    for (AsyncTimeout prev = head; true; prev = prev.next) {
      //如果下一个为null或者剩余时间比下一个短 就插入node
      if (prev.next == null || remainingNanos < prev.next.remainingNanos(now)) {
        node.next = prev.next;
        prev.next = node;
        if (prev == head) {
          // 唤醒 watchdog
          AsyncTimeout.class.notify();
        }
        break;
      }
    }
  }
```
# Okio的特点
- 分块处理(Segment)，这样在大数据IO的时候可以以块为单位进行IO，这可以提高IO的吞吐率
- 数据块使用链表来进行管理，这可以仅通过移动指针就进行数据的管理，而不用真正的处理数据，而且对扩容来说十分方便.
- 闲置的块进行管理，通过一个块池(SegmentPool)的管理，避免系统GC和申请byte时的zero-fill。
- 为所有的Source、Sink提供了超时操作，这是在Java原生IO操作是没有的。
- okio它对数据的读写都进行了封装，调用者可以十分方便的进行各种值(Stringg,short,int,hex,utf-8,base64等)的转化。
