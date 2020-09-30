---
title: AQS源码分析
toc: true
date: 2020-09-29 16:24:21
tags:
- java
- 源码
categories:
- java
---
AQS 全称是 AbstractQueuedSynchronizer，顾名思义，是一个用来构建锁和同步器的框架，它底层用了 CAS 技术来保证操作的原子性，同时利用 FIFO 队列实现线程间的锁竞争，将基础的同步相关抽象细节放在 AQS，这也是 ReentrantLock、CountDownLatch 等同步工具实现同步的底层实现机制。它能够成为实现大部分同步需求的基础，也是 J.U.C 并发包同步的核心基础组件
<!--more-->
# 结构介绍

AQS 就是建立在 CAS 的基础之上，增加了大量的实现细节，例如获取同步状态、FIFO 同步队列，独占式锁和共享式锁的获取和释放等等，这些都是 AQS 类对于同步操作抽离出来的一些通用方法，这么做也是为了对实现的一个同步类屏蔽了大量的细节，大大降低了实现同步工具的工作量，这也是为什么 AQS 是其它许多同步类的基类的原因。

1. AQS是一个基于先进先出（FIFO）等待队列的实现阻塞锁和同步器的框架。AQS通过一个volatile int state变量来保存锁的状态。子类必须通过：
- getState(): 获取当前的同步状态
- setState(int newState): 设置当前同步状态
- compareAndSetState(int expect,int update):使用CAS设置当前状态，该方法能够保证状态设置的原子性。

2. AQS支持独占锁和共享锁两种。
- 独占锁：锁在一个时间点只能被一个线程占有。根据锁的获取机制，又分为“公平锁”和“非公平锁”。等待队列中按照FIFO的原则获取锁，等待时间越长的线程越先获取到锁，这就是公平的获取锁，即公平锁。而非公平锁，线程获取的锁的时候，无视等待队列直接获取锁。ReentrantLock和ReentrantReadWriteLock.Writelock是独占锁。
```java
// 获取锁方法
protected boolean tryAcquire(int arg) {
  throw new UnsupportedOperationException();
}
// 释放锁方法
protected boolean tryRelease(int arg) {
  throw new UnsupportedOperationException();
}
```
- 共享锁：同一个时候能够被多个线程获取的锁，能被共享的锁。JUC包中ReentrantReadWriteLock.ReadLock，CyclicBarrier，CountDownLatch和Semaphore都是共享锁。
```java
// 获取锁方法
protected int tryAcquireShared(int arg) {
  throw new UnsupportedOperationException();
}
// 释放锁方法
protected boolean tryReleaseShared(int arg) {
  throw new UnsupportedOperationException();
}
```

3. AQS中没有实现任何的同步接口，一般子类通过继承AQS以内部类的形式实现锁机制。
一般通过继承AQS类实现同步器，通过getState、setState、compareAndSetState来监测状态，并重写以下方法：
- tryAcquire()：独占方式。尝试获取资源，成功则返回true，失败则返回false。
- tryRelease()：独占方式。尝试释放资源，成功则返回true，失败则返回false。
- tryAcquireShared()：共享方式。尝试获取资源。负数表示失败；0表示成功，但没有剩余可用资源；正数表示成功，且有剩余资源。
- tryReleaseShared()：共享方式。尝试释放资源，如果释放后允许唤醒后续等待结点返回true，否则返回false。
- isHeldExclusively()：该线程是否正在独占资源。只有用到condition才需要去实现它。
一般来说，自定义同步器要么是独占方法，要么是共享方式，他们也只需实现tryAcquire-tryRelease、tryAcquireShared-tryReleaseShared中的一种即可。但AQS也支持自定义同步器同时实现独占和共享两种方式，如ReentrantReadWriteLock。

4. AQS同步器的存储结构
```java
public abstract class AbstractQueuedSynchronizer extends AbstractOwnableSynchronizer
    implements java.io.Serializable {

    // 等待队列的头节点
    private transient volatile Node head;
    // 等待队列的尾节点
    private transient volatile Node tail;
    // 同步状态，其中 state > 0 为有锁状态，每次加锁就在原有 state 基础上加 1，即代表当前持有锁的线程加了 state 次锁，反之解锁时每次减一，当 state = 0 为无锁状态；
    private volatile int state;
    // CAS 更改 state 状态，保证 state 的原子性
    protected final boolean compareAndSetState(int expect, int update) {
        // See below for intrinsics setup to support this
        return unsafe.compareAndSwapInt(this, stateOffset, expect, update);
    }

    // ...

 }
```
**这几个字段都用 volatile 关键字进行修饰，以确保多线程间保证字段的可见性**

AQS 的结构大概可总结为以下 3 部分：
1. 用 volatile 修饰的整数类型的 state 状态，用于表示同步状态，提供 getState 和 setState 来操作同步状态；
2. 提供了一个 FIFO 等待队列，实现线程间的竞争和等待，这是 AQS 的核心；
3. AQS 内部提供了各种基于 CAS 原子操作方法，如 compareAndSetState 方法，并且提供了锁操作的acquire和release方法。

# 实现分析
## 独占锁
独占锁的原理是如果有线程获取到锁，那么其它线程只能是获取锁失败，然后进入等待队列中等待被唤醒。
### 获取锁
```java
public final void acquire(int arg) {
    if (!tryAcquire(arg) &&
        acquireQueued(addWaiter(Node.EXCLUSIVE), arg))
        selfInterrupt();
}
```
1. 通过 tryAcquire(arg) 方法尝试获取锁，这个方法需要实现类自己实现获取锁的逻辑，获取锁成功后则不执行后面加入等待队列的逻辑了；
2. 如果尝试获取锁失败后，则执行 addWaiter(Node.EXCLUSIVE) 方法将当前线程封装成一个 Node 节点对象，并加入队列尾部；
3. 把当前线程执行封装成 Node 节点后，继续执行 acquireQueued 的逻辑，该逻辑主要是判断当前节点的前置节点是否是头节点，来尝试获取锁，如果获取锁成功，则当前节点就会成为新的头节点，这也是获取锁的核心逻辑。

#### 加入等待队列
```java
private Node addWaiter(Node mode) {
  // 创建一个基于当前线程的节点，该节点是 Node.EXCLUSIVE 独占式类型
  Node node = new Node(Thread.currentThread(), mode);
  // Try the fast path of enq; backup to full enq on failure
  Node pred = tail;
  // 这里先判断队尾是否为空，如果不为空则直接将节点加入队尾
  if (pred != null) {
    node.prev = pred;
    // 采取 CAS 操作，将当前节点设置为队尾节点，由于采用了 CAS 原子操作，无论并发怎么修改，都有且只有一条线程可以修改成功，其余都将执行后面的enq方法
    if (compareAndSetTail(pred, node)) {
      pred.next = node;
      return node;
    }
  }
  enq(node);
  return node;
}
```
1. 创建基于当前线程的独占式类型的节点
2. 利用 CAS 原子操作，将节点加入队尾。

```java
private Node enq(final Node node) {
  // 自旋操作
  for (;;) {
    Node t = tail;
    // 如果队尾节点为空，那么进行CAS操作初始化队列
    if (t == null) {
      // 这里很关键，即如果队列为空，那么此时必须初始化队列，初始化一个空的节点表示队列头，用于表示当前正在执行的节点，头节点即表示当前正在运行的节点
      if (compareAndSetHead(new Node()))
        tail = head;
    } else {
      node.prev = t;
      // 这一步也是采取CAS操作，将当前节点加入队尾，如果失败的话，自旋继续修改直到成功为止
      if (compareAndSetTail(t, node)) {
        t.next = node;
        return t;
      }
    }
  }
}
```
1. 采用自旋机制，这是 aqs 里面很重要的一个机制；
2. 如果队尾节点为空，则初始化队列，将头节点设置为空节点，头节点即表示当前正在运行的节点；
3. 如果队尾节点不为空，则继续采取 CAS 操作，将当前节点加入队尾，不成功则继续自旋，直到成功为止；

#### 队列是否能获取锁
```java
final boolean acquireQueued(final Node node, int arg) {
  boolean failed = true;
  try {
    // 线程中断标记字段
    boolean interrupted = false;
    for (;;) {
      // 获取当前节点的 pred 节点
      final Node p = node.predecessor();
      // 如果 pred 节点为 head 节点，那么再次尝试获取锁
      if (p == head && tryAcquire(arg)) {
        // 获取锁之后，那么当前节点也就成为了 head 节点
        setHead(node);
        p.next = null; // help GC
        failed = false;
        // 不需要挂起，返回 false
        return interrupted;
      }
      // 获取锁失败，则进入挂起逻辑
      if (shouldParkAfterFailedAcquire(p, node) &&
          parkAndCheckInterrupt())
        interrupted = true;
    }
  } finally {
    if (failed)
      cancelAcquire(node);
  }
}
```
1. 判断当前节点的 pred 节点是否为 head 节点，如果是，则尝试获取锁；
2. 获取锁失败后，进入挂起逻辑。
**注意：head 节点代表当前持有锁的线程，那么如果当前节点的 pred 节点是 head 节点，很可能此时 head 节点已经释放锁了，所以此时需要再次尝试获取锁**

#### 获取锁失败
```java
private static boolean shouldParkAfterFailedAcquire(Node pred, Node node) {
  int ws = pred.waitStatus;
  if (ws == Node.SIGNAL)
    // 如果 pred 节点为 SIGNAL 状态，返回true，说明当前节点需要挂起
    return true;
  // 如果ws > 0,说明节点状态为CANCELLED，需要从队列中删除
  if (ws > 0) {
    do {
      node.prev = pred = pred.prev;
    } while (pred.waitStatus > 0);
    pred.next = node;
  } else {
    // 如果是其它状态，则操作CAS统一改成SIGNAL状态
    // 由于这里waitStatus的值只能是0或者PROPAGATE，所以我们将节点设置为SIGNAL，从新循环一次判断
    compareAndSetWaitStatus(pred, ws, Node.SIGNAL);
  }
  return false;
}
```
1. 判断 pred 节点状态，如果为 SIGNAL 状态，则直接返回 true 执行挂起；
2. 删除状态为 CANCELLED 的节点；
3. 若 pred 节点状态为 0 或者 PROPAGATE，则将其设置为为 SIGNAL，再从 acquireQueued 方法自旋操作从新循环一次判断
*根据 pred 节点状态来判断当前节点是否可以挂起，如果该方法返回 false，那么挂起条件还没准备好，就会重新进入 acquireQueued(final Node node, int arg) 的自旋体，重新进行判断。如果返回 true，那就说明当前线程可以进行挂起操作了，那么就会继续执行挂起。*

#### 挂起当前节点
```java
private final boolean parkAndCheckInterrupt() {
  LockSupport.park(this);
  return Thread.interrupted();
}
```
LockSupport 是用来创建锁和其他同步类的基本线程阻塞原语。LockSupport 提供 park() 和 unpark() 方法实现阻塞线程和解除线程阻塞。release 释放锁方法逻辑会调用 LockSupport.unPark 方法来唤醒后继节点。

获取独占锁流程图：
![独占锁](aqs.jpg)

###  释放锁
```java
public final boolean release(int arg) {
  if (tryRelease(arg)) {
    Node h = head;
    if (h != null && h.waitStatus != 0)
      unparkSuccessor(h);
    return true;
  }
  return false;
}
```
通过 tryRelease(arg) 方法尝试释放锁，这个方法需要实现类自己实现释放锁的逻辑，释放锁成功后则执行后面的唤醒后续节点的逻辑了，然后判断 head 节点不为空并且 head 节点状态不为 0，因为 addWaiter 方法默认的节点状态为 0，此时节点还没有进入就绪状态。

```java
private void unparkSuccessor(Node node) {
  int ws = node.waitStatus;
  if (ws < 0)
    // 将头节点的状态设置为0
    // 这里会尝试清除头节点的状态，改为初始状态
    compareAndSetWaitStatus(node, ws, 0);

  // 后继节点
  Node s = node.next;
  // 如果后继节点为null，或者已经被取消了
  if (s == null || s.waitStatus > 0) {
    s = null;
    // for循环从队列尾部一直往前找可以唤醒的节点
    for (Node t = tail; t != null && t != node; t = t.prev)
      if (t.waitStatus <= 0)
        s = t;
  }
  if (s != null)
    // 唤醒后继节点
    LockSupport.unpark(s.thread);
}
```
释放锁主要是将头节点的后继节点唤醒，如果后继节点不符合唤醒条件，则从队尾一直往前找，直到找到符合条件的节点为止。

## 共享锁
### 获取锁
```java
public final void acquireShared(int arg) {
  // 尝试获取共享锁，小于0表示获取失败
  if (tryAcquireShared(arg) < 0)
    // 执行获取锁失败的逻辑
    doAcquireShared(arg);
}

private void doAcquireShared(int arg) {
  // 添加共享锁类型节点到队列中
  final Node node = addWaiter(Node.SHARED);
  boolean failed = true;
  try {
    boolean interrupted = false;
    for (;;) {
      final Node p = node.predecessor();
      if (p == head) {
        // 再次尝试获取共享锁
        int r = tryAcquireShared(arg);
        // 如果在这里成功获取共享锁，会进入共享锁唤醒逻辑
        if (r >= 0) {
          // 共享锁唤醒逻辑
          setHeadAndPropagate(node, r);
          p.next = null; // help GC
          if (interrupted)
            selfInterrupt();
          failed = false;
          return;
        }
      }
      // 与独占锁相同的挂起逻辑
      if (shouldParkAfterFailedAcquire(p, node) &&
          parkAndCheckInterrupt())
        interrupted = true;
    }
  } finally {
    if (failed)
      cancelAcquire(node);
  }
}
```
在线程挂起之前，不断地循环尝试获取锁，不同的是，一旦获取共享锁，会调用 setHeadAndPropagate 方法同时唤醒后继节点，实现共享模式,参考如下：
```java
private void setHeadAndPropagate(Node node, int propagate) {
  // 头节点
  Node h = head;
  // 设置当前节点为新的头节点
  // 这里不需要加锁操作，因为获取共享锁后，会从FIFO队列中依次唤醒队列，并不会产生并发安全问题
  setHead(node);
  if (propagate > 0 || h == null || h.waitStatus < 0 ||
      (h = head) == null || h.waitStatus < 0) {
    // 后继节点
    Node s = node.next;
    // 如果后继节点为空或者后继节点为共享类型，则进行唤醒后继节点
    // 这里后继节点为空意思是只剩下当前头节点了
    if (s == null || s.isShared())
      doReleaseShared();
  }
}
```
1. 将当前节点设置为新的头节点，这点很重要，这意味着当前节点的前置节点（旧头节点）已经获取共享锁了，从队列中去除；
2. 调用 doReleaseShared 方法，它会调用 unparkSuccessor 方法唤醒后继节点。

### 释放锁
```java
public final boolean releaseShared(int arg) {
  // 由用户自行实现释放锁条件
  if (tryReleaseShared(arg)) {
    // 执行释放锁
    doReleaseShared();
    return true;
  }
  return false;
}

private void doReleaseShared() {
  for (;;) {
    // 从头节点开始执行唤醒操作
    // 这里需要注意，如果从setHeadAndPropagate方法调用该方法，那么这里的head是新的头节点
    Node h = head;
    if (h != null && h != tail) {
      int ws = h.waitStatus;
      //表示后继节点需要被唤醒
      if (ws == Node.SIGNAL) {
        // 初始化节点状态
        //这里需要CAS原子操作，因为setHeadAndPropagate和releaseShared这两个方法都会顶用doReleaseShared，避免多次unpark唤醒操作
        if (!compareAndSetWaitStatus(h, Node.SIGNAL, 0))
          // 如果初始化节点状态失败，继续循环执行
          continue;            // loop to recheck cases
        // 执行唤醒操作
        unparkSuccessor(h);
      }
      //如果后继节点暂时不需要唤醒，那么当前头节点状态更新为PROPAGATE，确保后续可以传递给后继节点
      else if (ws == 0 &&
               !compareAndSetWaitStatus(h, 0, Node.PROPAGATE))
        continue;                // loop on failed CAS
    }
    // 如果在唤醒的过程中头节点没有更改，退出循环
    // 这里防止其它线程又设置了头节点，说明其它线程获取了共享锁，会继续循环操作
    if (h == head)                   // loop if head changed
      break;
  }
}
```
共享锁的释放锁逻辑比独占锁的释放锁逻辑稍微复杂，原因是共享锁需要释放队列中所有共享类型的节点，因此需要循环操作，由于释放锁过程中会涉及多个地方修改节点状态，此时需要 CAS 原子操作来并发安全。
获取共享锁流程图：
![共享锁](aqs_2.jpg)

# 总结
在独占锁模式下，用 state 值表示锁并且 0 表示无锁状态，0 -> 1 表示从无锁到有锁，仅允许一条线程持有锁，其余的线程会被包装成一个 Node 节点放到队列中进行挂起，队列中的头节点表示当前正在执行的线程，当头节点释放后会唤醒后继节点，从而印证了 AQS 的队列是一个 FIFO 同步队列。
