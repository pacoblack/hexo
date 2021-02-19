---
title: HashMap与SparseArray区别
toc: true
date: 2021-02-18 16:33:14
tags:
- java
categories:
- java
---
android中我们经常会需要存储键-值对，而他们的存储方式常见的就有HashMap、ArrayMap和SparseArray，那么他们有什么区别呢
<!--more-->
# HashMap
HashMap基本上是HashMap.Entry对象的一个数组。 Entry是HashMap的内部类，它用来保存键值对。
![](https://cdn-images-1.medium.com/max/800/1*lXkll8fb72OFk5NVVbi_wQ.png)
我们看一下源码
```java
//构造函数没有什么操作，主要是初始化一下capacity和loadFactor，默认值分别为16和0.75
// 主要逻辑还是看putVal
final V putVal(int hash, K key, V value, boolean onlyIfAbsent,
               boolean evict) {
    Node<K,V>[] tab; Node<K,V> p; int n, i;
    // Step1:初始化table
    if ((tab = table) == null || (n = tab.length) == 0)
        n = (tab = resize()).length;
    // Step2:如果根据hash值计算得到的索引是空的，直接复制
    if ((p = tab[i = (n - 1) & hash]) == null)
        tab[i] = newNode(hash, key, value, null);
    else {
      //进入这里说明索引不为空
      //Step3:如果hash值相同、key值相同则获取当前node
        Node<K,V> e; K k;
        if (p.hash == hash &&
            ((k = p.key) == key || (key != null && key.equals(k))))
            e = p;
        //Step4：如果当前节点为TreeNode，就当作二叉树插入
        else if (p instanceof TreeNode)
            e = ((TreeNode<K,V>)p).putTreeVal(this, tab, hash, key, value);
        else {
            //Step5:遍历所有节点
            for (int binCount = 0; ; ++binCount) {
                if ((e = p.next) == null) {
                  //Step6:如果下一个节点是空则插入
                    p.next = newNode(hash, key, value, null);
                    //Step7:如果插入的节点已经超过了8个，就将单向列表转换为二叉树
                    if (binCount >= TREEIFY_THRESHOLD - 1) // -1 for 1st
                        treeifyBin(tab, hash);
                    break;
                }
                //Step8:如果找到了节点就结束当前循环
                if (e.hash == hash &&
                    ((k = e.key) == key || (key != null && key.equals(k))))
                    break;
                p = e;
            }
        }
        //Step9:如果找到了节点，就返回节点的旧的值，并更新为新的值
        if (e != null) { // existing mapping for key
            V oldValue = e.value;
            if (!onlyIfAbsent || oldValue == null)
                e.value = value;
            afterNodeAccess(e);
            return oldValue;
        }
    }
    ++modCount;
    //Step10:如果插入后的大小超过了阈值，就对当前列表扩容
    if (++size > threshold)
        resize();
    afterNodeInsertion(evict);
    return null;
}
```
从数组中检索值的时间效率为恒定时间或O(1)。 这意味着不管数组的大小，拉取数组中的任何元素时间都相同。 这可以通过使用散列函数来生成指定键的数组索引。

# ArrayMap
ArrayMap中包含了两个小数组。 第一个数组（Hash-Array）按顺序包含指定的哈希键。 第二个数组（Key Value Array）根据第一个数组存储对象的键和值。第二个数组的长度是第一个数组的一倍。
![](https://cdn-images-1.medium.com/max/800/1*v1_3ug_tpscGtYc7JxP2Og.png)
在源码的构造函数中，创建了两个空的数组
```java
//这个的代码看起来很长，但是逻辑很简单
public V put(K key, V value) {
    final int osize = mSize;
    final int hash;
    int index;
    //Step1:根据key值获取到hash值，以及hash值在列表中的索引
    if (key == null) {
        hash = 0;
        index = indexOfNull();
    } else {
        hash = mIdentityHashCode ? System.identityHashCode(key) : key.hashCode();
        index = indexOf(key, hash);
    }
    //Step2:如果找到了这个值，就更新一下
    if (index >= 0) {
        index = (index<<1) + 1;
        final V old = (V)mArray[index];
        mArray[index] = value;
        return old;
    }
    //Step3:如果没有找到，那么我们就要插入
    index = ~index;
    //Step4:如果已经达到最大长度，我们就要扩容
    if (osize >= mHashes.length) {
        final int n = osize >= (BASE_SIZE*2) ? (osize+(osize>>1))
                : (osize >= BASE_SIZE ? (BASE_SIZE*2) : BASE_SIZE);

        if (DEBUG) Log.d(TAG, "put: grow from " + mHashes.length + " to " + n);

        final int[] ohashes = mHashes;
        final Object[] oarray = mArray;
        allocArrays(n);

        if (CONCURRENT_MODIFICATION_EXCEPTIONS && osize != mSize) {
            throw new ConcurrentModificationException();
        }

        if (mHashes.length > 0) {
            if (DEBUG) Log.d(TAG, "put: copy 0-" + osize + " to 0");
            System.arraycopy(ohashes, 0, mHashes, 0, ohashes.length);
            System.arraycopy(oarray, 0, mArray, 0, oarray.length);
        }

        freeArrays(ohashes, oarray, osize);
    }
    //Step5:如果可以插入，调用native方法来将hash和key-value插入到相应位置
    if (index < osize) {
        if (DEBUG) Log.d(TAG, "put: move " + index + "-" + (osize-index)
                + " to " + (index+1));
        System.arraycopy(mHashes, index, mHashes, index + 1, osize - index);
        System.arraycopy(mArray, index << 1, mArray, (index + 1) << 1, (mSize - index) << 1);
    }

    if (CONCURRENT_MODIFICATION_EXCEPTIONS) {
        if (osize != mSize || index >= mHashes.length) {
            throw new ConcurrentModificationException();
        }
    }
    mHashes[index] = hash;
    mArray[index<<1] = key;
    mArray[(index<<1)+1] = value;
    mSize++;
    return null;
}
```
## 缓存机制
ArrayMap是专为Android优化而设计的Map对象，使用场景比较高频，很多场景可能起初都是数据很少，为了减少频繁地创建和回收，特意设计了两个缓存池，分别缓存大小为4和8的ArrayMap对象。

### freeArrays
```java
private static void freeArrays(final int[] hashes, final Object[] array, final int size) {
    if (hashes.length == (BASE_SIZE*2)) {  //当释放的是大小为8的对象
        synchronized (ArrayMap.class) {
            // 当大小为8的缓存池的数量小于10个，则将其放入缓存池
            if (mTwiceBaseCacheSize < CACHE_SIZE) {
                array[0] = mTwiceBaseCache;  //array[0]指向原来的缓存池
                array[1] = hashes;
                for (int i=(size<<1)-1; i>=2; i--) {
                    array[i] = null;  //清空其他数据
                }
                mTwiceBaseCache = array; //mTwiceBaseCache指向新加入缓存池的array
                mTwiceBaseCacheSize++;
            }
        }
    } else if (hashes.length == BASE_SIZE) {  //当释放的是大小为4的对象，原理同上
        synchronized (ArrayMap.class) {
            if (mBaseCacheSize < CACHE_SIZE) {
                array[0] = mBaseCache;
                array[1] = hashes;
                for (int i=(size<<1)-1; i>=2; i--) {
                    array[i] = null;
                }
                mBaseCache = array;
                mBaseCacheSize++;
            }
        }
    }
}
```
最初mTwiceBaseCache和mBaseCache缓存池中都没有数据，在freeArrays释放内存时，如果同时满足释放的array大小等于4或者8，且相对应的缓冲池个数未达上限，则会把该arrya加入到缓存池中,缓存池的个数增加。
加入的方式是将数组array的第0个元素指向原有的缓存池，第1个元素指向hashes数组的地址，第2个元素以后的数据全部置为null。再把缓存池的头部指向最新的array的位置，并将该缓存池大小执行加1操作。
具体如下所示。
![](http://gityuan.com/images/arraymap/cache_add.jpg)
而执行过程是不断mBaseCache向上，更新上一个Array的a[0]和a[1]并将其他置空

### allocArrays
```java
private void allocArrays(final int size) {
    if (size == (BASE_SIZE*2)) {  //当分配大小为8的对象，先查看缓存池
        synchronized (ArrayMap.class) {
            if (mTwiceBaseCache != null) { // 当缓存池不为空时
                final Object[] array = mTwiceBaseCache;
                mArray = array;         //从缓存池中取出mArray
                mTwiceBaseCache = (Object[])array[0]; //将缓存池指向上一条缓存地址
                mHashes = (int[])array[1];  //从缓存中mHashes
                array[0] = array[1] = null;
                mTwiceBaseCacheSize--;  //缓存池大小减1
                return;
            }
        }
    } else if (size == BASE_SIZE) { //当分配大小为4的对象，原理同上
        synchronized (ArrayMap.class) {
            if (mBaseCache != null) {
                final Object[] array = mBaseCache;
                mArray = array;
                mBaseCache = (Object[])array[0];
                mHashes = (int[])array[1];
                array[0] = array[1] = null;
                mBaseCacheSize--;
                return;
            }
        }
    }

    // 分配大小除了4和8之外的情况，则直接创建新的数组
    mHashes = new int[size];
    mArray = new Object[size<<1];
}
```
当调用allocArrays分配内存时，如果所需要分配的大小等于4或者8，且相对应的缓冲池不为空，则会从相应缓存池中取出缓存的mArray和mHashes。
从缓存池取出缓存的方式是将当前缓存池赋值给mArray，将缓存池指向上一条缓存地址，将缓存池的第1个元素赋值为mHashes，再把mArray的第0和第1个位置的数据置为null，并将该缓存池大小执行减1操作.
如下图所示
![](http://gityuan.com/images/arraymap/cache_delete.jpg)
而执行过程是不断mBaseCache向下，并将Array的a[0]和a[1]置空

## 小结
- ArrayMap和SparseArray采用的都是两个数组，Android专门针对内存优化而设计的
- ArrayMap比HashMap更节省内存，综合性能方面在数据量不大的情况下，推荐使用ArrayMap
- ArrayMap查找时间复杂度O(logN)；
- ArrayMap增加、删除操作需要移动成员，速度相比较慢，对于个数小于1000的情况下，性能基本没有明显差异，适用于插入和产删除不频繁的情况

# SparseArray
结构式两个相同大小的列表
与ArrayMap的主要区别在于，在SparseArray键中始终是原始类型。SparseArray旨在消除自动装箱的问题（ArrayMap不能避免自动装箱问题），而这种方法会影响内存消耗。
```java
public void put(int key, E value) {
  //Step1:先通过二叉查找到索引
    int i = ContainerHelpers.binarySearch(mKeys, mSize, key);

    //Step2:如果找到就更新
    if (i >= 0) {
        mValues[i] = value;
    } else {
        i = ~i;
        // Step3:如果没有找到，如果是被删除的也可以更新
        if (i < mSize && mValues[i] == DELETED) {
            mKeys[i] = key;
            mValues[i] = value;
            return;
        }
        //Step4:如果有存在能够回收的，先回收再查找索引
        if (mGarbage && mSize >= mKeys.length) {
            gc();

            // Search again because indices may have changed.
            i = ~ContainerHelpers.binarySearch(mKeys, mSize, key);
        }
        //Step5:根据查找的结果重新插入，并确定是否需要扩容
        mKeys = GrowingArrayUtils.insert(mKeys, mSize, i, key);
        mValues = GrowingArrayUtils.insert(mValues, mSize, i, value);
        mSize++;
    }
}
```
## 小结
- SparseArray比ArrayMap节省1/3的内存，但SparseArray只能用于key为int类型的Map，所以int类型的Map数据推荐使用SparseArray；
- SparseArray适合频繁删除和插入来回执行的场景，性能比较好
- SparseArray有延迟回收机制，提供删除效率，同时减少数组成员来回拷贝的次数

# Hashtable
>注意是 `Hashtable` 不是 `HashTable` (t为小写)，这不是违背了驼峰定理了嘛？这还得从 `Hashtable` 的出生说起，
`Hashtable` 是在Java1.0的时候创建的，而集合的统一规范命名是在后来的Java2开始约定的，而当时又发布了新的集合代替它，所以这个命名也一直使用到现在。

## 简单认识
1. HashMap是线程不安全的，在多线程环境下会容易产生死循环，但是单线程环境下运行效率高；Hashtable线程安全的，很多方法都有synchronized修饰，但同时因为加锁导致单线程环境下效率较低。
2. HashMap允许有一个key为null，允许多个value为null；而Hashtable不允许key或者value为null。

## 构造函数
```java
public Hashtable(int initialCapacity, float loadFactor) {
    if (initialCapacity < 0)
        throw new IllegalArgumentException("Illegal Capacity: "+
                                           initialCapacity);
    if (loadFactor <= 0 || Float.isNaN(loadFactor))
        throw new IllegalArgumentException("Illegal Load: "+loadFactor);

    if (initialCapacity==0)
        initialCapacity = 1;
    this.loadFactor = loadFactor;
    table = new HashtableEntry<?,?>[initialCapacity];
    // Android-changed: Ignore loadFactor when calculating threshold from initialCapacity
    // threshold = (int)Math.min(initialCapacity * loadFactor, MAX_ARRAY_SIZE + 1);
    threshold = (int)Math.min(initialCapacity, MAX_ARRAY_SIZE + 1);
}
```
- HashMap的底层数组的长度必须为2^n
- Hashtable底层数组的长度可以为任意值，这就造成了当底层数组长度为合数的时候，Hashtable的hash算法散射不均匀，容易产生hash冲突。所以，可以清楚的看到Hashtable的默认构造函数底层数组长度为11（质数）

## hash算法
```Java
// HashMap
static final int hash(Object key) {
    int h;
    return (key == null) ? 0 : (h = key.hashCode()) ^ (h >>> 16);
}
```
HashMap的hash算法通过非常规的设计，将底层table长度设计为2^n（合数）
```java
int hash = key.hashCode();
//0x7FFFFFFF转换为10进制之后是Intger.MAX_VALUE,也就是2^31 - 1
int index = (hash & 0x7FFFFFFF) % tab.length;
```
Hashtable的hash算法首先使得hash的值小于等于整型数的最大值，再通过%运算实现均匀散射。

## 扩容机制
```java
//HashMap
final Node<K,V>[] resize() {
    Node<K,V>[] oldTab = table;
    int oldCap = (oldTab == null) ? 0 : oldTab.length;
    int oldThr = threshold;
    int newCap, newThr = 0;
    if (oldCap > 0) {
        if (oldCap >= MAXIMUM_CAPACITY) {
            threshold = Integer.MAX_VALUE;
            return oldTab;
        }
        else if ((newCap = oldCap << 1) < MAXIMUM_CAPACITY &&
                 oldCap >= DEFAULT_INITIAL_CAPACITY)
            newThr = oldThr << 1; // 将阈值扩大为2倍
    }
    else if (oldThr > 0) // initial capacity was placed in threshold
        newCap = oldThr;
    else {               // 当threshold的为0的使用默认的容量，也就是16
        newCap = DEFAULT_INITIAL_CAPACITY;
        newThr = (int)(DEFAULT_LOAD_FACTOR * DEFAULT_INITIAL_CAPACITY);
    }
    if (newThr == 0) {
        float ft = (float)newCap * loadFactor;
        newThr = (newCap < MAXIMUM_CAPACITY && ft < (float)MAXIMUM_CAPACITY ?
                  (int)ft : Integer.MAX_VALUE);
    }
    threshold = newThr;
    @SuppressWarnings({"rawtypes","unchecked"})
        //新建一个数组长度为原来2倍的数组
        Node<K,V>[] newTab = (Node<K,V>[])new Node[newCap];
    table = newTab;
    if (oldTab != null) {
        for (int j = 0; j < oldCap; ++j) {
            Node<K,V> e;
            if ((e = oldTab[j]) != null) {
                oldTab[j] = null;
                if (e.next == null)
                    newTab[e.hash & (newCap - 1)] = e;
                else if (e instanceof TreeNode)
                    ((TreeNode<K,V>)e).split(this, newTab, j, oldCap);
                else {
                    //HashMap在JDK1.8的时候改善了扩容机制，原数组索引i上的链表不需要再反转。
                    // 扩容之后的索引位置只能是i或者i+oldCap（原数组的长度）
                    // 所以我们只需要看hashcode新增的bit为0或者1。
                   // 假如是0扩容之后就在新数组索引i位置，新增为1，就在索引i+oldCap位置
                    Node<K,V> loHead = null, loTail = null;
                    Node<K,V> hiHead = null, hiTail = null;
                    Node<K,V> next;
                    do {
                        next = e.next;
                        // 新增bit为0，扩容之后在新数组的索引不变
                        if ((e.hash & oldCap) == 0) {
                            if (loTail == null)
                                loHead = e;
                            else
                                loTail.next = e;
                            loTail = e;
                        }
                        else {  //新增bit为1，扩容之后在新数组索引变为i+oldCap（原数组的长度）
                            if (hiTail == null)
                                hiHead = e;
                            else
                                hiTail.next = e;
                            hiTail = e;
                        }
                    } while ((e = next) != null);
                    if (loTail != null) {
                        loTail.next = null;
                        //数组索引位置不变，插入原索引位置
                        newTab[j] = loHead;
                    }
                    if (hiTail != null) {
                        hiTail.next = null;
                        //数组索引位置变化为j + oldCap
                        newTab[j + oldCap] = hiHead;
                    }
                }
            }
        }
    }
    return newTab;
}
```
HashMap数组的扩容的整体思想就是创建一个长度为原先2倍的数组。然后对原数组进行遍历和复制。只不过jdk1.8对扩容进行优化，使得扩容不再需要进行链表的反转，只需要知道hashcode新增的bit位为0还是1。如果是0就在原索引位置，新增索引是1就在oldIndex+oldCap位置。

```java
//Hashtable
protected void rehash() {
    int oldCapacity = table.length;
    Entry<?,?>[] oldMap = table;
​
    // overflow-conscious code
    int newCapacity = (oldCapacity << 1) + 1;
    if (newCapacity - MAX_ARRAY_SIZE > 0) {
        if (oldCapacity == MAX_ARRAY_SIZE)
            // Keep running with MAX_ARRAY_SIZE buckets
            return;
        newCapacity = MAX_ARRAY_SIZE;
    }
    Entry<?,?>[] newMap = new Entry<?,?>[newCapacity];
​
    modCount++;
    threshold = (int)Math.min(newCapacity * loadFactor, MAX_ARRAY_SIZE + 1);
    table = newMap;
​
    for (int i = oldCapacity ; i-- > 0 ;) {
        for (Entry<K,V> old = (Entry<K,V>)oldMap[i] ; old != null ; ) {
            Entry<K,V> e = old;
            old = old.next;
​
            int index = (e.hash & 0x7FFFFFFF) % newCapacity;
            //使用头插法将链表反序
            e.next = (Entry<K,V>)newMap[index];
            newMap[index] = e;
        }
    }
}
```
Hashtable的扩容将先创建一个长度为原长度2倍的数组，再使用头插法将链表进行反序。

## 结构组成
```java
private transient HashtableEntry<?,?>[] table;

private static class HashtableEntry<K,V> implements Map.Entry<K,V> {
   // END Android-changed: Renamed Entry -> HashtableEntry.
   final int hash;
   final K key;
   V value;
   HashtableEntry<K,V> next;
}
```
所以结构是一个 数组+单链表 的组成
