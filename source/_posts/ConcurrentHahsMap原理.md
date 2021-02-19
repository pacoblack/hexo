---
title: ConcurrentHahsMap原理
toc: true
date: 2021-02-19 17:37:27
tags:
- java
categories:
- java
---
参考来源：[https://www.cnblogs.com/hello-shf/p/12183263.html](https://www.cnblogs.com/hello-shf/p/12183263.html)
上一篇我们介绍了hashmap相关，其中hashmap有个明显的缺点就是不支持并发，在resize时会丢数据（JDK8），而HashTable虽然保证了线程安全性，但是其是通过给每个方法加Synchronized关键字达到的同步目的。但是都知道Synchronized在竞争激烈的多线程并发环境中，在性能上的表现是非常不如人意的。如果要并发的话就要用的ConcurrentHashMap
<!--more-->
# 初步认识
在Jdk8中的数据结构
![](https://img2018.cnblogs.com/i-beta/1635748/202001/1635748-20200112144800523-38023773.png)
和HashMap的结构是一样的，没错在数据结构层面，ConcurrentHashMap和HashMap是完全一样的。

# 之前的结构

在JDK8之前HashMap没有引入红黑树，同样的ConcurrentHashMap也没有引入红黑树。而且ConcurrentHashMap采用的是分段数组的底层数据结构。
如下图所示
![](https://img2018.cnblogs.com/i-beta/1635748/202001/1635748-20200112145618510-591452614.png)
JDK7中为了提高并发性能采用了这种分段的设计。所以在JDK7中ConcurrentHashMap采用的是分段锁，也就是在每个Segment上加`ReentrantLock`(*ReetrantLoack是比Synchronized更细粒度的一种锁。使用得当的话其性能要比Synchronized表现要好，但是如果实现不得当容易造成死锁*)实现的线程安全线。

这种基于Segment和ReetrantLock的设计相对HashTable来说大大提高了并发性能。也就是说多个线程可以并发的操作多个Segment，而HashTable是通过给每个方法加Synchronized即将多线程串行而实现的。所以在一定程度上提高了并发性能。但是这种性能的提升表现相对JDK8来说显得不值一提。

JDK8中ConcurrentHashMap采用的是CAS+Synchronized锁并且锁粒度是每一个桶。简单来说JDK7中锁的粒度是Segment，JDK8锁粒度细化到了桶级别。可想而知锁粒度是大大提到了。

# 预备知识
```java
//正在扩容，对应fwd类型的节点的hash
static final int MOVED     = -1; // hash for forwarding nodes

//当前数组
transient volatile Node<K,V>[] table;

//扩容时用到的，扩容后的数组。
private transient volatile Node<K,V>[] nextTable;

//1，大于零，表示size * 0.75。
//2，等于-1，表示正在初始化。
//3，-(n + 1)，表示正在执行扩容的线程其只表示基数，而不是真正的数量，需要计算得出的哦
private transient volatile int sizeCtl;


//tab为volatile，方法是获取table中索引 i 处的元素。
static final <K,V> Node<K,V> tabAt(Node<K,V>[] tab, int i) {
    return (Node<K,V>)U.getObjectVolatile(tab, ((long)i << ASHIFT) + ABASE);
}

//通过CAS设置table索引为 i 处的元素。
static final <K,V> boolean casTabAt(Node<K,V>[] tab, int i,
                                    Node<K,V> c, Node<K,V> v) {
    return U.compareAndSwapObject(tab, ((long)i << ASHIFT) + ABASE, c, v);
}

//修改table 索引 i 处的元素。
static final <K,V> void setTabAt(Node<K,V>[] tab, int i, Node<K,V> v) {
    U.putObjectVolatile(tab, ((long)i << ASHIFT) + ABASE, v);
}
```

# put方法
```java
final V putVal(K key, V value, boolean onlyIfAbsent) {
    if (key == null || value == null) throw new NullPointerException();
    //Step1:通过再散列获取hash值
    int hash = spread(key.hashCode());
    int binCount = 0;
    //Step2:迭代table中的node
    for (Node<K,V>[] tab = table;;) {//注意：这里是一个自旋锁的过程，保证数据一定能插入成功，比如说在处理Step4，或者Step8时发现节点修改过
        Node<K,V> f; int n, i, fh;
        //Step3:懒加载，如果为空，则初始化table和sizeCtl
        if (tab == null || (n = tab.length) == 0)
            tab = initTable();
        //Step4:根据key获取node，如果为空则直接插入
        else if ((f = tabAt(tab, i = (n - 1) & hash)) == null) {
            if (casTabAt(tab, i, null,
                         new Node<K,V>(hash, key, value, null)))
                break;                   // no lock when adding to empty bin
        }
        //Step5:table是否在扩容如果正在扩容，当前线程帮助进行扩容。每个线程只能同时负责一个桶上的数据迁移，并且不影响其它桶的put和get操作。
        else if ((fh = f.hash) == MOVED)
            tab = helpTransfer(tab, f);
        else {
          //Step6:进入这里则说明存在hash碰撞，且没有在扩容
            V oldVal = null;
            //Step7:这里f为当前下标的第一个元素，对链表来说是表头，对红黑树来说是根，先对根加锁
            synchronized (f) {
              //Step8:检查根节点是否被其他线程修改过
                if (tabAt(tab, i) == f) {
                  //Step9:如果当前为链表，则插入链表尾部
                    if (fh >= 0) {
                        binCount = 1;
                        for (Node<K,V> e = f;; ++binCount) {
                            K ek;
                            if (e.hash == hash &&
                                ((ek = e.key) == key ||
                                 (ek != null && key.equals(ek)))) {
                                oldVal = e.val;
                                if (!onlyIfAbsent)
                                    e.val = value;
                                break;
                            }
                            Node<K,V> pred = e;
                            if ((e = e.next) == null) {
                                pred.next = new Node<K,V>(hash, key,
                                                          value, null);
                                break;
                            }
                        }
                    }
                    //Step9:如果当前为红黑树，则插入其中
                    else if (f instanceof TreeBin) {
                        Node<K,V> p;
                        binCount = 2;
                        if ((p = ((TreeBin<K,V>)f).putTreeVal(hash, key,
                                                       value)) != null) {
                            oldVal = p.val;
                            if (!onlyIfAbsent)
                                p.val = value;
                        }
                    }
                    else if (f instanceof ReservationNode)
                        throw new IllegalStateException("Recursive update");
                }
            }
            //Step10:如果超过了阈值，就要将链表转换为红黑树
            if (binCount != 0) {
                if (binCount >= TREEIFY_THRESHOLD)
                    treeifyBin(tab, i);
                if (oldVal != null)
                    return oldVal;
                break;
            }
        }
    }
    //Step11:添加一个元素，判断是不是需要扩容ß
    addCount(1L, binCount);
    return null;
}
```

# initTable方法
```java
private final Node<K,V>[] initTable() {
    Node<K,V>[] tab; int sc;
    while ((tab = table) == null || tab.length == 0) {
      //Step1:赋值sc。sizeCtl == -1 即当前有线程正在执行初始化
        if ((sc = sizeCtl) < 0)
            //暂停当前正在执行的线程，执行其他线程,但是不一定会让当前线程停止，要取决于线程调度器
            Thread.yield();
        //Step2:修改 sizeCtl 的值为 -1。 SIZECTL 为 sizeCtl 的内存偏移。
        else if (U.compareAndSwapInt(this, SIZECTL, sc, -1)) {
            try {
                //Step3:初始化table
                if ((tab = table) == null || tab.length == 0) {
                    int n = (sc > 0) ? sc : DEFAULT_CAPACITY;
                    @SuppressWarnings("unchecked")
                    Node<K,V>[] nt = (Node<K,V>[])new Node<?,?>[n];
                    table = tab = nt;
                    sc = n - (n >>> 2);
                }
            } finally {
                //Step4:初始化完成, sizeCtl重新赋值为当前数组的长度。
                sizeCtl = sc;
            }
            break;
        }
    }
    return tab;
}
```

# transfer方法(扩容)
```java
//tab旧桶数组，nextTab新桶数组
private final void transfer(Node<K,V>[] tab, Node<K,V>[] nextTab) {
    int n = tab.length, stride;
    //Step1:根据Cpu获取并发数
    if ((stride = (NCPU > 1) ? (n >>> 3) / NCPU : n) < MIN_TRANSFER_STRIDE)
        stride = MIN_TRANSFER_STRIDE; // subdivide range
    //Step2:创建一个两倍的table
    if (nextTab == null) {           
        try {
            @SuppressWarnings("unchecked")
            Node<K,V>[] nt = (Node<K,V>[])new Node<?,?>[n << 1];
            nextTab = nt;
        } catch (Throwable ex) {      // try to cope with OOME
            sizeCtl = Integer.MAX_VALUE;
            return;
        }
        nextTable = nextTab;
        transferIndex = n;
    }
    int nextn = nextTab.length;
    //Step3:创建一个hash值为-1的node，这个节点会在后面的时候设置为旧桶的头节点
    ForwardingNode<K,V> fwd = new ForwardingNode<K,V>(nextTab);
    boolean advance = true;//false表示正在移动一个桶，true表示没有移动，可以移动下一桶
    boolean finishing = false; // to ensure sweep before committing nextTab
    //Step4:开始自旋移动
    for (int i = 0, bound = 0;;) {
        Node<K,V> f; int fh;
        //Step5:是不是已经移动完成了，如果已经完成了修改transferIndex，移动下一个
        while (advance) {
            int nextIndex, nextBound;
            if (--i >= bound || finishing)
                advance = false;
            else if ((nextIndex = transferIndex) <= 0) {
                i = -1;
                advance = false;
            }
            else if (U.compareAndSwapInt
                     (this, TRANSFERINDEX, nextIndex,
                      nextBound = (nextIndex > stride ?
                                   nextIndex - stride : 0))) {
                bound = nextBound;
                i = nextIndex - 1;
                advance = false;
            }
        }
        if (i < 0 || i >= n || i + n >= nextn) {
            int sc;
            //Step6:扩容结束
            if (finishing) {
                nextTable = null;
                table = nextTab;
                sizeCtl = (n << 1) - (n >>> 1);
                return;
            }
            if (U.compareAndSwapInt(this, SIZECTL, sc = sizeCtl, sc - 1)) {
                if ((sc - 2) != resizeStamp(n) << RESIZE_STAMP_SHIFT)
                    return;
                finishing = advance = true;
                i = n; // recheck before commit
            }
        }
        //Step7:移动时发现没有数据，则通过cas进行设置值
        else if ((f = tabAt(tab, i)) == null)
            advance = casTabAt(tab, i, null, fwd);
        //Step8:移动时发现已经移动过了，则移动下一个
        else if ((fh = f.hash) == MOVED)
            advance = true; // already processed
        else {
            //Step9:移动时发现还没有移动过的，先加锁
            // 此时就tab中的头节点已经变为了fwd，这个f节点已经不在之前的tab中了
            synchronized (f) {
                //Step10:如果是链表，
                // ln链表，由不需要移动的节点组成；hn由需要移动的链表组成
                // 判断方式是判断第n个字节位置是否为0
                if (tabAt(tab, i) == f) {
                    Node<K,V> ln, hn;
                    if (fh >= 0) {
                        int runBit = fh & n;
                        Node<K,V> lastRun = f;
                        for (Node<K,V> p = f.next; p != null; p = p.next) {
                            int b = p.hash & n;
                            if (b != runBit) {
                                runBit = b;
                                lastRun = p;
                            }
                        }
                        if (runBit == 0) {
                            ln = lastRun;
                            hn = null;
                        }
                        else {
                            hn = lastRun;
                            ln = null;
                        }
                        for (Node<K,V> p = f; p != lastRun; p = p.next) {
                            int ph = p.hash; K pk = p.key; V pv = p.val;
                            if ((ph & n) == 0)
                                ln = new Node<K,V>(ph, pk, pv, ln);
                            else
                                hn = new Node<K,V>(ph, pk, pv, hn);
                        }
                        setTabAt(nextTab, i, ln);
                        setTabAt(nextTab, i + n, hn);
                        setTabAt(tab, i, fwd);
                        advance = true;
                    }
                    else if (f instanceof TreeBin) {
                        TreeBin<K,V> t = (TreeBin<K,V>)f;
                        TreeNode<K,V> lo = null, loTail = null;
                        TreeNode<K,V> hi = null, hiTail = null;
                        int lc = 0, hc = 0;
                        for (Node<K,V> e = t.first; e != null; e = e.next) {
                            int h = e.hash;
                            TreeNode<K,V> p = new TreeNode<K,V>
                                (h, e.key, e.val, null, null);
                            if ((h & n) == 0) {
                                if ((p.prev = loTail) == null)
                                    lo = p;
                                else
                                    loTail.next = p;
                                loTail = p;
                                ++lc;
                            }
                            else {
                                if ((p.prev = hiTail) == null)
                                    hi = p;
                                else
                                    hiTail.next = p;
                                hiTail = p;
                                ++hc;
                            }
                        }
                        ln = (lc <= UNTREEIFY_THRESHOLD) ? untreeify(lo) :
                            (hc != 0) ? new TreeBin<K,V>(lo) : t;
                        hn = (hc <= UNTREEIFY_THRESHOLD) ? untreeify(hi) :
                            (lc != 0) ? new TreeBin<K,V>(hi) : t;
                        setTabAt(nextTab, i, ln);
                        setTabAt(nextTab, i + n, hn);
                        setTabAt(tab, i, fwd);
                        advance = true;
                    }
                }
            }
        }
    }
}
```
我们可以看下面的两个图
![](https://img2018.cnblogs.com/i-beta/1635748/202001/1635748-20200113164216447-1278369367.png)
![](https://img2018.cnblogs.com/i-beta/1635748/202001/1635748-20200113164252551-1234632431.png)
比如原先在1的位置，扩容后就可能在1或者17的位置，所以通过 `ph&n==0` 来判断是放在1中还是17中，
因为以前都是通过ph&16得到索引位置，新桶是通过ph&32取得索引位置，新的位置与旧的位置的差别显而易见。

现在看一个演示过程
![](https://img2018.cnblogs.com/i-beta/1635748/202001/1635748-20200113180828655-1406714067.png)
1. 显示遍历得到lastRun，并赋值给ln(或者hn，这里按ln解说)
2. 再重新遍历，将与ln相同位置的放到ln的表头，hn同理
3. 得到上图样式

# 并发演示
1. 线程1进行put操作，这时发现size > sizeCtl。开始进行扩容
![](https://img2018.cnblogs.com/i-beta/1635748/202001/1635748-20200114153245228-30554462.png)

2. 此时线程1已经完成oldTab中索引[2，16)中的扩容。正在进行索引为1的桶的扩容。接下来线程2执行get。
![](https://img2018.cnblogs.com/i-beta/1635748/202001/1635748-20200114153332267-1482925142.png)

3. 线程2根据get逻辑和key的hash，可能访问的三种情况如上图所示
- 访问蓝色号桶(未扩容的桶):该桶还未进行扩容，所以在桶中找到对应元素，返回。
- 访问绿色桶(正在扩容的桶):该桶正在扩容，在扩容过程中，线程1持有Synchronized锁，线程2只能自旋等待。
- 访问橘色桶(已扩容的桶):该桶已扩容，oldTab中是fwd节点，hash=-1，所以执行fwd节点的find逻辑，fwd节点持有newTab(nextTable)，所以线程2去newTab中查找对应元素，返回。
![](https://img2018.cnblogs.com/i-beta/1635748/202001/1635748-20200114153435438-1108705553.png)

4. 当线程1进行扩容时，线程3进来执行put，同样存在三种可能的情况
- 访问蓝色桶(未扩容的桶):正常执行put逻辑。
- 访问绿色桶(正扩容的桶):因为线层1持有Synchronized锁，线程3将一直自旋，等待扩容结束。
- 访问橘色桶(已扩容的桶):因为已扩容的桶，在oldTab中是fwd节点，hash = -1 = MOVED，所以线程3执行帮助扩容的逻辑。等待扩容完成，线程3继续完成put逻辑。
![](https://img2018.cnblogs.com/i-beta/1635748/202001/1635748-20200114153512551-1590215923.png)
