---
title: JVM内存模型
toc: true
date: 2021-02-22 10:58:09
tags:
- java
categories:
- java
---
内存模型从入门到放弃
![模型](jvm_all.jpg)
<!--more-->
# 内存结构
## 基本分配
1. *局部变量*中基础数据类型的引用和值都存储在栈中，*对象引用*存在栈中
2. *对象*存在堆中, *成员变量*存储在堆中的对象里面
3. 静态变量和常量在方法区，其中，常量在连接-解析时初始化，静态变量、静态代码块（封装在<cinit>方法，只执行一次）、类代码块在初始化阶段初始化（封装在<init>方法，以构造函数结束，每次创建都会执行）
## JVM 运行时数据区
![JVM 运行时数据区](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm1.jpg)

- 程序计数器。
    用来选取下一条需要执行的字节码指令、分支，来执行循环、跳转、异常处理、线程恢复等基础功能。

    在任何一个确定的时刻，一个处理器只会执行一条线程中的指令。因此，为了线程切换后能恢复到正确的执行位置，每条线程都需要有一个独立的程序计数器，各条线程之间的计数器互不影响、独立存储，我们称这类内存区域为“线程私有”的内存。

- Java虚拟机栈
    Java虚拟机栈（Java Vitual Machine Stacks）也是线程私有的，它的生命周期与线程相同。线程中每个方法被执行的时候都会同时创建一个栈帧（Stack Frame）用于存储局部变量表、操作栈、动态链接、方法出口等信息。

- 本地方法栈
    本地方法栈（Native Method Stacks）与虚拟机栈所发挥的作用非常类似，区别在于虚拟机栈为虚拟机执行Java方法服务，而本地方法栈则是为虚拟机使用到的Native方法服务。

- Java堆
    Java堆（java heap）是Java虚拟机所管理的内存中最大的一块。它是被所有线程共享的一块内存区域，在虚拟机启动时创建。同时堆是按代分配的，老年代、新生代(Eden区 2个、Survivor区)，垃圾回收会讲到。
    Java堆可以处于物理上不连续的内存空间中，只要逻辑上是连续的即可。

- 方法区
    方法区（Method Area）与Java堆一样，是各个线程共享的内存区域，它用于存储已被虚拟机加载的类信息、常量、静态变量、即时编译器编译后的代码等数据。
    Java虚拟机规范对这个区域的限制非常宽松，除了和Java堆一样不需要连续的内存和可以选择固定大小或者可扩展外，还可以选择不实现垃圾收集。
    当然垃圾回收的条件非常严格，当一个类在整个环境中不被引用的时候，这个类就可以卸载了
     - 该类所有的**实例都已经被回收**，也就是Java堆中不存在该类的任何实例
     - 加载该类的 **ClassLoader** 已经被回收
     - 该类对应的java.lang.Class对象没有在任何地方被引用，**无法在任何地方在反射访问该类的方法**

- 运行时常量池
    运行时常量池（Runtime Constant Pool）是方法区 的一部分。Class文件中除了有类的版本、字段、方法、接口等描述信息外，还会在编译器生成一些**字面量和符号引用**，这部分内容将在类加载后存放到方法区的运行时常量池中。
    java语言并不要求常量一定只能在编译器产生，运行期间也可能将新的常量放入池中，这种特性被开发人员利用的比较多的是String类的intern() 方法。

- 直接内存
    直接内存(DIrect Memory)并不是虚拟机运行时数据区的一部分，也不是java虚拟机规范中定义的内存区域。在JDK1.4中新加入了NIO(New Input/Output)类，引入了一种基于通道(Channel)与缓冲区(Buffer)的I/O方式，他可以Native函数库直接分配堆外内存，然后通过一个存储在Java堆里面的DirectByteBuffer对象作为这块内存 的引用进行操作。这样在一些场景中显著提高性能，因为避免了再Java堆和Native堆中来回复制数据。

## 对象访问
```
Object obj=new Object();
```
在这句代码上，`Object obj`这部分语义会反映到Java栈栈帧的本地变量表中，作为一个**reference类型**数据出现.
而`new Object()`这局会反映到Java堆中，形成一块存储了object类型所有实例数据值(Instance Data,对象中各个实例字段的数据)的**结构化内存**，根据具体类型以及虚拟机的实现的对象内存布局的不从，这块内存的长度是不固定的。另外，在Java堆中还必须包含能查找到此类型数据的地址信息，这些类型数据则存储在方法区中。

主流的访问方式有两种：使用句柄和直接指针。
- 句柄式访问。java堆中将划分出一块内存来作为句柄池，reference中存储的就是对象的句柄地址，而句柄中包含了对象实例数据和类型数据各自的具体地址信息。
![句柄式](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm2.jpg)
- 指针访问方式。reference变量中直接存储的就是对象的地址，而java堆对象一部分存储了对象实例数据，另外一部分存储了对象类型数据。
![指针式](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm3.jpg)

    这两种访问对象的方式各有优势，使用句柄访问方式最大好处就是reference中存储的是稳定的句柄地址，在对象移动时只需要**改变句柄中的实例数据指针**，而reference不需要改变。使用指针访问方式最大好处就是**速度快**，它节省了一次指针定位的时间开销，就虚拟机而言，它使用的是第二种方式

## 垃圾回收算法
- 标记-清除算法问题。存在效率问题，还有会产生大量不连续的内存碎片
- 复制算法。将可用内存按容量划分为**大小相等的两块**，每次只是用其中的一块。当这一块的内存用完了，就将还存活着的对象复制到另外一块上面，然后再把已使用过的内存空间一次清理掉。
![复制算法](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm4.jpg)

- 标记-整理算法。标记过程和”标记-清除”算法一样，但后续步骤不是直接对可回收对象进行清理，而是让所有存活 的对象都向一端移动，然后直接清理掉端边界以外的内存
![标记-整理](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm5.jpg)

## 内存分配机制
Java内存分配和回收的机制概括的说，就是分代分配，分代回收。对象将根据存活的时间被分为：
- 年轻代（Young Generation）。年轻代可以分为3个区域：Eden区和两个存活区（Survivor 0 、Survivor 1），一般比例是8:1:1
    1. 绝大多数刚创建的对象会被分配在Eden区，其中的大多数对象很快就会消亡。Eden区是连续的内存空间，因此在其上分配内存极快
    2. 当Eden区满的时候，执行Minor GC，将消亡的对象清理掉，并将剩余的对象复制到一个存活区Survivor0（此时，Survivor1是空白的，两个Survivor总有一个是空白的）
    3. 此后，每次Eden区满了，就执行一次Minor GC，并将剩余的对象都添加到Survivor0
    4. 当Survivor0也满的时候，将其中仍然活着的对象直接复制到Survivor1，以后Eden区执行Minor GC后，就将剩余的对象添加Survivor1（此时，Survivor0是空白的）。
    5. 当两个存活区切换了几次（HotSpot虚拟机默认15次，用-XX:MaxTenuringThreshold控制，大于该值进入老年代，但这只是个最大值，并不代表一定是这个值）之后，仍然存活的对象（其实只有一小部分，比如，我们自己定义的对象），将被复制到老年代。

>这种垃圾回收的方式就是著名的“停止-复制（Stop-and-copy）”清理法（将Eden区和一个Survivor中仍然存活的对象拷贝到另一个Survivor中），这不代表着停止复制清理法很高效，其实，它也只在这种情况下高效。
在Eden区，HotSpot虚拟机使用了两种技术来加快内存分配。分别是bump-the-pointer和TLAB（Thread-Local Allocation Buffers），这两种技术的做法分别是：由于Eden区是连续的，因此bump-the-pointer技术的核心就是跟踪最后创建的一个对象，在对象创建时，只需要**检查最后一个对象后面是否有足够的内存即可**，从而大大加快内存分配速度；而对于TLAB技术是对于多线程而言的，将**Eden区分为若干段**，每个线程使用独立的一段，避免相互影响。TLAB结合bump-the-pointer技术，将保证每个线程都使用Eden区的一段，并快速的分配内存。

- 年老代（Old Generation）
    对象如果在年轻代存活了足够长的时间而没有被清理掉（即在几次Young GC后存活了下来），则会被复制到年老代，年老代的空间一般比年轻代大，能存放更多的对象，在年老代上发生的GC次数也比年轻代少。当年老代内存不足时，将执行Major GC，也叫 Full GC。

    如果对象比较大（比如长字符串或大数组），Young空间不足，则大对象会直接分配到老年代上

    可能存在年老代对象引用新生代对象的情况，如果需要执行Young GC，则可能需要查询整个老年代以确定是否可以清理回收，这显然是低效的。解决的方法是，年老代中维护一个**512 byte的块**——”card table“，所有老年代对象引用新生代对象的记录都记录在这里。Young GC时，只要查这里即可，不用再去查全部老年代，因此性能大大提高。
- 永久代（Permanent Generation，也就是方法区）。

## 内存回收
上面已经说了年轻代是`停止-复制`算法。一般，老年代用的算法是`标记-整理`算法，即：标记出仍然存活的对象（存在引用的），将所有存活的对象向一端移动，以保证内存的连续。

在发生Minor GC时，虚拟机会检查每次晋升进入老年代的大小是否大于老年代的剩余空间大小，如果大于，则直接触发一次Full GC，否则，就查看是否设置了-XX:+HandlePromotionFailure（允许担保失败），如果允许，则只会进行MinorGC，此时可以容忍内存分配失败；如果不允许，则仍然进行Full GC（这代表着如果设置-XX:+Handle PromotionFailure，则触发MinorGC就会同时触发Full GC，哪怕老年代还有很多内存，所以，最好不要这样做）

永久代的回收有两种：常量池中的常量，无用的类信息，常量的回收很简单，没有引用了就可以被回收。

# 字节码加载

类的整个生命过程：加载、连接(验证、准备、解析)、初始化、使用和卸载五个阶段
![加载过程](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm6.jpg)
- 加载阶段。虚拟机主要完成以下工作
    1. 通过一个类的全限定名来获取定义**此类的二进制字节流**
    2. 将这个字节流所代表的的静态存储结构转换为**方法区的运行时数据结构**
    3. 在内存中生成一个代表这个类的**java.lang.Class对象**，作为方法区这些数据的访问入口（对于HotSpot虚拟机而言，Class 对象比较特殊，虽是对象，但是存放在方法区）
- 验证阶段。包括 文件格式验证、元数据验证、字节码验证和符号引用验证。
- 准备阶段。是正式为类变量**分配内存**并设置类变量初始值的阶段。
首先是这时候进行内存分配的仅包括**类变量**（被static修饰的变量），而不包括实例变量，实例变量将会在对象实例化时随着对象一起分配在Java堆中。其次，这里所说的初始值“通常情况下”是**数据类型的零值**。
```
public static int value = 123; // 在准备阶段初始化为 0

public static final int value = 123; // 在准备阶段初始化为 123
```
- 解析阶段。指检查指定的类是否引用了其他的类、接口，包括类或接口、字段、类方法、接口方法的解析。 是虚拟机将常量池中的**符号引用替换为直接引用**的过程。

## 加载器
只有两个类由同一个类加载器加载才有意义。否则，即使两个类来源于同一个Class文件，只要加载他们的类加载器不同，这两个类还是不同的。这里所说的“相等”，包括代表类的Class对象的equal()方法、isAssignableFrom（）方法、isInstance（）方法的返回结果，同时也包括了使用instanceos关键字作对象所属关系判定等情况。

在java虚拟机的角度来讲，只存在两种不同的类加载器：一种是**启动类加载器**(Bootstrap ClassLoader)，这个类加载器使用C++语言实现，是虚拟机自身的一部分；另外一种就是**所有其他的类加载器**，这些类加载器都由java实现，独立于虚拟机外部，并且全部继承在抽象类java.lang.ClassLoader。

而从java开发人员的角度来讲，类加载器还可以分为三类：
- 启动类加载器。这个类加载器负责将 `<JAVA_HOME>\lib` 目录下的，或 `-Xbootclasspath` 参数所指定的路径中的，并且是虚拟机识别的类库加载到虚拟机中。启动类加载器无法被java程序直接引用。
- 扩展类加载器。这个加载器由 `sun.misc.Launcher$ExtClassLoader`实现，它负责加载`<JAVA_HOME>\lib\ext`目录中，或者被`java.ext.dirs`系统变量所指定路径中的所有类库，开发者可以直接使用扩展类加载器。
- 应用程序类加载器：这个加载器由`sun.misc.Launcher$AppClassLoader`来实现。由于这个类加载器是ClassLoader 中的 `getSystemClassLoader()` 方法的返回值，所以一般也称他为系统类加载器。它负责加载用户路径上所指定的类库，开覆辙可以直接使用这个类加载器，如果应用程序中没有定义过自己的类加载器，一般情况下就是这个默认的类加载器。
![加载器关系图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm7.png)

这就是双亲委派模型：如果一个类加载器收到了类加载的请求，它首先不会自己去尝试加载这个类，而是把这个请求委派给父类加载器去完成，每一个层次的类加载器都是如此，因此所有的加载请求最终都应该传送到顶层的类加载器中，只有当父加载器反馈自己无法完成这个加载请求时，子加载器才尝试自己去加载。

## 字节码执行
- 栈帧结构
    栈帧是用于支持虚拟机进行方法调用和方法执行的数据结构，它是虚拟机运行时数据区中的虚拟机栈的栈元素。栈帧存储了方法的局部变量表、操作数栈、动态连接和方法返回地址等信息。
1. 返回地址：方法被调用的位置
2. 动态连接：常量池中该方法的引用
3. 操作数栈：和局部变量表一样，在编译时期就已经确定了该方法所需要分配的局部变量表的最大容量。
>当一个方法刚刚开始执行的时候，这个方法的操作数栈是空的，在方法的执行过程中，会有各种字节码指令往操作数栈中写入和提取内容，也就是出栈/入栈操作。例如，在做算术运算的时候是通过操作数栈来进行的，又或者在调用其他方法的时候是通过操作数栈来进行参数传递的。
在概念模型里面，虚拟机栈中的栈帧之间是完全相互独立的。但是在大多数虚拟机的实现里都会做一些优化处理，令两个栈帧出现一部分重叠。

4. 局部变量表：包括boolean、byte、char、short、int、float、reference，为了节省空间，这些slot会复用

![栈帧示意图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm8.jpg)

    当一个方法开始执行的时候，这个方法的操作数栈是空的，在方法的执行过程中，会有各种字节码指令向操作数栈中写入和提取内容，也就是入栈和出栈的操作。每个栈帧都包含一个指向运行时常量池中该栈帧**所属方法的引用**，持有这个引用是为了支持方法调用过程中的动态链接。

    在 Class 文件里面，描述一个方法调用了其他方法，或者访问其成员变量是通过符号引用（Symbolic Reference）来表示的，动态链接的作用就是将这些符号引用所表示的方法转换为实际方法的直接引用。类加载的过程中将要解析掉尚未被解析的符号引用，并且将变量访问转化为访问这些变量的存储结构所在的运行时内存位置的正确偏移量。

    由于动态链接的存在，通过晚期绑定（Late Binding）使用的其他类的方法和变量在发生变化时，将不会对调用它们的方法构成影响。

- 方法调用
    方法调用不等同与方法执行，方法调用阶段唯一的任务就是确定被调用方法的版本(调用哪一个方法)

    我们会需要解析，分派，还要考虑到动态类型语言的特点。解析调用一定是个静态的过程，在编译期间就完全确定，在类装载的解析阶段就会把涉及的符号引用全部转变为可确定的直接引用，不会延迟到运行期再去完成。而分派调用则可能是静态的也可能是动态的，根据分派依据的宗量数可分为单分派和多分派。
    动态类型语言的关键特征是它的类型检查的主体过程是在运行期而不是编译期，如JavaScript、Python、Ruby、Lisp等

    动态分派我们以 `invokevirtual` 为例
    1. 找到操作数栈顶的第一个元素所指向的**对象的实际类型**，记作C
    2. 如果找到与常量中的描述符和简单名称都相符的方法，则进行**访问权限校验**，如果通过则返回这个方法的直接引用，查找结束；不通过则返回java.lang.IllegalAccessError异常
    3. 否则，按照继承关系**从下往上**依次对C的各个父类进行第二步的搜索验证
    4. 如果始终找不到合适的方法，则抛出java.lang.AbstractMethodError异常

# 内存的访问
## 并发模型分类
在并发编程中，我们要解决线程之间通信及同步，通常考的是两种机制：**内存共享、消息传递**

同步是指程序用于控制不同线程之间操作发生相对顺序的机制。在共享内存并发模型里，同步是显式进行的。程序员必须显式指定某个方法或某段代码需要在线程之间互斥执行。在消息传递的并发模型里，由于消息的发送必须在消息的接收之前，因此同步是隐式进行的。

在共享内存的并发模型里，线程之间共享程序的公共状态，线程之间通过写-读内存中的公共状态来隐式进行通信。在消息传递的并发模型里，线程之间没有公共状态，线程之间必须通过明确的发送消息来显式进行通信。

## Java内存模型抽象
**Java的并发采用的是共享内存模型**，Java线程之间的通信总是隐式进行，整个通信过程对程序员完全透明。

Java线程之间的通信由Java内存模型（JMM）控制，JMM决定一个线程对共享变量的写入何时对另一个线程可见。从抽象的角度来看，JMM定义了**线程和主内存**之间的抽象关系：线程之间的共享变量存储在主内存（main memory）中，每个线程都有一个私有的本地内存（local memory），本地内存中存储了该线程以读/写共享变量的副本。本地内存是JMM的一个抽象概念，并不真实存在。它涵盖了缓存，写缓冲区，寄存器以及其他的硬件和编译器优化。Java内存模型的抽象示意图如下：
![内存模型示意图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm9.png)
所以如果两个线程要通信的话，一个线程要把本地中的变量刷新到主内存，另一个再从主内存读取

## 重排序
在执行程序时为了提高性能，编译器和处理器常常会对指令做重排序。重排序分三种类型：
1. 编译器优化的重排序。编译器在不改变单线程程序语义的前提下，可以重新安排语句的执行顺序。
2. 指令级并行的重排序。现代处理器采用了指令级并行技术（Instruction-Level Parallelism， ILP）来将多条指令重叠执行。如果不存在数据依赖性，处理器可以改变语句对应机器指令的执行顺序。
3. 内存系统的重排序。由于处理器使用缓存和读/写缓冲区，这使得加载和存储操作看上去可能是在乱序执行。

*我们看到除了指令和编译层面的优化，还有一个内存的重排序。这是为了避免频繁的同步主内存而进行的优化。*

对于编译器，JMM的编译器重排序规则会**禁止特定类型的编译器重排序**（不是所有的编译器重排序都要禁止）。对于处理器重排序，JMM的处理器重排序规则会要求java编译器在生成指令序列时，插入特定类型的**内存屏障**（memory barriers，intel称之为memory fence）指令，通过内存屏障指令来禁止特定类型的处理器重排序（不是所有的处理器重排序都要禁止）。而内存重排序，则是通过**禁止特定类型的编译器重排序和处理器重排序**，为程序员提供一致的内存可见性保证。

| Processor A | Processor B |
| ------ | ------ |
| a = 1; //A1 | b = 2; //B1 |
| x = b; //A2 | y = a; //B2 |
初始状态：a = b = 0
处理器允许执行后得到结果：x = y = 0
![处理过程示意图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm10.png)
这是因为 处理器A执行A3后来刷新自己的写缓存区，写操作A1才算真正执行了。虽然处理器A执行内存操作的顺序为：A1->A2，但内存操作实际发生的顺序却是：A2->A1。

这里的关键是，由于写缓冲区仅对自己的处理器可见，它会导致处理器执行内存操作的顺序可能会与内存实际的操作执行顺序不一致。由于现代的处理器都会使用写缓冲区，因此现代的处理器都会允许对写-读操做重排序。
为了保证内存可见性，java编译器在生成指令序列的适当位置会插入内存屏障指令来禁止特定类型的处理器重排序。JMM把内存屏障指令分为下列四类：

| 屏障类型 | 指令示例 | 说明 |
| ------ | ------ | ------ |
| Load - Load | Load1; LoadLoad; Load2 | 确保Load1数据的装载，之前于Load2及所有后续装载指令的装载。|
| Store - Store | Store1; StoreStore; Store2 | 确保Store1数据对其他处理器可见（刷新到内存），之前于Store2及所有后续存储指令的存储。 |
| Load - Store | Load1; LoadStore; Store2 | 确保Load1数据装载，之前于Store2及所有后续的存储指令刷新到内存。|
| Store - Load | Store1; StoreLoad; Load2 | 确保Store1数据对其他处理器变得可见（指刷新到内存），之前于Load2及所有后续装载指令的装载。StoreLoad Barriers会使该屏障之前的所有内存访问指令（存储和装载指令）完成之后，才执行该屏障之后的内存访问指令。|
StoreLoad Barriers是一个“全能型”的屏障，它同时具有其他三个屏障的效果。

## happens-before
如果一个操作执行的结果需要对另一个操作可见，那么这两个操作之间必须存在 happens-before 关系。这里提到的两个操作既可以是在一个线程之内，也可以是在不同线程之间。 与程序员密切相关的happens-before规则如下：
- 程序顺序规则：一个线程中的**每个操作**，happens- before 于该线程中的任意后续操作。
- 监视器锁规则：对一个监视器锁的解锁，happens- before 于随后对这个监视器锁的加锁。**解锁先于加锁**
- volatile变量规则：对一个volatile域的写，happens- before 于任意后续对这个volatile域的读。**写先于读**
- 传递性：如果A happens- before B，且B happens- before C，那么A happens- before C。

注意，两个操作之间具有happens-before关系，并不意味着前一个操作必须要在后一个操作之前执行！happens-before仅仅要求前一个操作（**执行的结果**）对后一个操作可见，且前一个操作按顺序排在第二个操作之前（the first is visible to and ordered before the second）。

## 数据依赖性与控制依赖性
如果两个操作访问同一个变量，且这两个操作中有一个为写操作，此时这两个操作之间就存在数据依赖性。
- **as-if-serial语义**。不管怎么重排序（编译器和处理器为了提高并行度）,（单线程）程序的执行结果不能被改变。
    为了遵守as-if-serial语义，编译器和处理器不会对存在数据依赖关系的操作做重排序，因为这种重排序会改变执行结果。但是，如果操作之间不存在数据依赖关系，这些操作可能被编译器和处理器重排序。比如
```
double pi  = 3.14;    //A
double r   = 1.0;     //B
double area = pi * r * r; //C
// C 依赖 A B
```
A和C之间存在数据依赖关系，同时B和C之间也存在数据依赖关系。因此在最终执行的指令序列中，C不能被重排序到A和B的前面（C排到A和B的前面，程序的结果将会被改变）。但A和B之间没有数据依赖关系，编译器和处理器可以重排序A和B之间的执行顺序。

- **程序顺序规则**
    根据happens- before的程序顺序规则，上面计算圆的面积的示例代码存在三个happens- before关系：
    1. A happens- before B；
    2. B happens- before C；
    3. A happens- before C；

    如果A happens - before B，JMM并不要求A一定要在B之前执行。JMM仅仅要求前一个操作（执行的结果）对后一个操作可见，且前一个操作按顺序排在第二个操作之前。这里**操作A的执行结果不需要对操作B可见**；而且重排序操作A和操作B后的执行结果，与操作A和操作B按happens- before顺序执行的结果一致。在这种情况下，JMM会认为这种重排序并不非法（not illegal），JMM允许这种重排序。
- 重排序对多线程的影响
```
class ReorderExample {
    int a = 0;
    boolean flag = false;

    public void writer() {
        a = 1;                   //1
        flag = true;             //2
    }

    public void reader() {
        if (flag) {                //3
            int i =  a * a;        //4
            ……
        }
    }
}
```
由于操作1和操作2没有数据依赖关系，编译器和处理器可以对这两个操作重排序；同样，操作3和操作4没有数据依赖关系，编译器和处理器也可以对这两个操作重排序。
但是在重排序后会出现非预期结果，这是因为代码中存在**控制依赖性**，会影响指令序列执行的并行度。为此，编译器和处理器会采用**猜测（Speculation）执行**来克服控制相关性对并行度的影响。以处理器的猜测执行为例，执行线程 B 的处理器可以提前读取并计算 a*a，然后把计算结果临时保存到一个名为重排序缓冲（reorder buffer ROB）的硬件缓存中。当接下来操作 3 的条件判断为真时，就把该计算结果写入变量 i 中。

## 数据不同步引起数据竞争与顺序一致性问题
当程序未正确同步时，就会存在数据竞争。java内存模型规范对数据竞争的定义如下：
1. 在一个线程中写一个变量，
2. 在另一个线程读同一个变量，
3. 而且写和读没有通过同步来排序。

JMM对正确同步的多线程程序的内存一致性做了如下保证：
- 顺序一致性内存模型
    如果程序是正确同步的，程序的执行将具有顺序一致性（sequentially consistent），即程序的执行结果与该程序在顺序一致性内存模型中的执行结果相同。这里的同步是指广义上的同步，包括对常用同步原语（lock，volatile和final）的正确使用。
    顺序一致性内存模型有两大特性：
    - 一个线程中的所有操作必须**按照程序的顺序**来执行。
    - （不管程序是否同步）所有线程都只能看到一个单一的操作执行顺序。在顺序一致性内存模型中，每个操作都必须**原子执行且立刻对所有线程可见**。

    为了更好的理解，下面我们通过两个示意图来对顺序一致性模型的特性做进一步的说明。

    假设有两个线程A和B并发执行。其中A线程有三个操作，它们在程序中的顺序是：A1->A2->A3。B线程也有三个操作，它们在程序中的顺序是：B1->B2->B3。

    假设这两个线程使用监视器来正确同步：A线程的三个操作执行后释放监视器，随后B线程获取同一个监视器。那么程序在顺序一致性模型中的执行效果将如下图所示：
![执行示意图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm11.png)
    现在我们再假设这两个线程没有做同步，下面是这个未同步程序在顺序一致性模型中的执行示意图：
![未同步执行](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm12.png)
    未同步程序在顺序一致性模型中虽然整体执行顺序是无序的，但所有线程都只能看到一个一致的整体执行顺序。以上图为例，线程A和B看到的执行顺序都是：B1->A1->A2->B2->A3->B3。之所以能得到这个保证是因为顺序一致性内存模型中的每个操作必须立即对任意线程可见。

- 同步程序的顺序一致性效果
```
class SynchronizedExample {
    int a = 0;
    boolean flag = false;

    public synchronized void writer() {
        a = 1;
        flag = true;
    }

    public synchronized void reader() {
        if (flag) {
            int i = a;
            ……
        }
    }
}
```
上面示例代码中，假设A线程执行writer()方法后，B线程执行reader()方法。这是一个正确同步的多线程程序。根据JMM规范，该程序的执行结果将与该程序在顺序一致性模型中的执行结果相同。下面是该程序在两个内存模型中的执行时序对比图：
![执行顺序对比](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm13.png)
在顺序一致性模型中，所有操作完全按程序的顺序串行执行。
- 未同步程序的执行特性
对于未同步或未正确同步的多线程程序，JMM只提供最小安全性：线程执行时读取到的值，要么是之前某个线程写入的值，要么是默认值（0，null，false），JMM保证线程读操作读取到的值不会无中生有（out of thin air）的冒出来。

JMM不保证未同步程序的执行结果与该程序在顺序一致性模型中的执行结果一致。因为未同步程序在顺序一致性模型中执行时，整体上是无序的，其执行结果无法预知。

## volatile 与内存屏障
volatile变量自身具有下列特性：
- 可见性。对一个volatile变量的读，总是能看到（任意线程）对这个volatile变量**最后的写入**。
- 原子性：对任意单个volatile变量的**读/写具有原子性**，但类似于volatile++这种复合操作不具有原子性。

volatile写的内存语义如下：
- 当写一个volatile变量时，JMM会把该线程对应的本地内存中的共享变量刷新到主内存。

volatile读的内存语义如下：
- 当读一个volatile变量时，JMM会把该线程对应的本地内存置为无效。线程接下来将从主内存中读取共享变量。

### 内存屏障
为了实现volatile的内存语义，编译器在生成字节码时，会在指令序列中**插入内存屏障**来禁止特定类型的处理器重排序。

内存屏障（Memory Barrier）可以被分为以下几种类型：
- LoadLoad屏障：对于这样的语句`Load1; LoadLoad; Load2;`在Load2及后续读取操作要读取的数据被访问前，保证Load1要读取的数据被读取完毕。
- StoreStore屏障：对于这样的语句`Store1; StoreStore; Store2;`在Store2及后续写入操作执行前，保证Store1的写入操作对其它处理器可见。
- LoadStore屏障：对于这样的语句`Load1; LoadStore; Store2;`在Store2及后续写入操作被刷出前，保证Load1要读取的数据被读取完毕。
- StoreLoad屏障：对于这样的语句`Store1; StoreLoad; Load2;`在Load2及后续所有读取操作执行前，保证Store1的写入对所有处理器可见。它的开销是四种屏障中最大的。在大多数处理器的实现中，这个屏障是个万能屏障，兼具其它三种内存屏障的功能

下面是在保守策略下，volatile读插入内存屏障后生成的指令序列示意图：
![插入内存屏障后生成的指令序列示意图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm14.png)
>内存写：StoreStore屏障---写---StoreLoad屏障
内存读：LoadLoad屏障----读----LoadStore屏障

上图中的StoreStore屏障可以保证在volatile写之前，其前面的所有普通写操作已经对任意处理器可见了。这是因为StoreStore屏障将保障上面所有的普通写在volatile写之前**刷新到主内存**。
后面的StoreLoad屏障的作用是避免volatile写与后面可能有的volatile读/写操作**重排序**。为了保证能正确实现volatile的内存语义，JMM在这里采取了保守策略：在每个volatile写的后面或在每个volatile读的前面插入一个StoreLoad屏障。从整体执行效率的角度考虑，JMM选择了在每个volatile写的后面插入一个StoreLoad屏障。

在实际执行时，只要不改变volatile写-读的内存语义，编译器可以根据具体情况省略不必要的屏障。下面我们通过具体的示例代码来说明：
```
class VolatileBarrierExample {
    int a;
    volatile int v1 = 1;
    volatile int v2 = 2;

    void readAndWrite() {
        int i = v1;           //第一个volatile读
        int j = v2;           // 第二个volatile读
        a = i + j;            //普通写
        v1 = i + 1;          // 第一个volatile写
        v2 = j * 2;          //第二个 volatile写
    }
    …                    //其他方法
}
```
针对readAndWrite()方法，编译器在生成字节码时可以做如下的优化：
![优化后的屏障插入位置](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm15.png)
注意，**最后的StoreLoad屏障不能省略**。因为第二个volatile写之后，方法立即return。此时编译器可能无法准确断定后面是否会有volatile读或写，为了安全起见，编译器常常会在这里插入一个StoreLoad屏障。

旧的Java内存模型允许volatile变量与普通变量之间重排序。为了提供一种比监视器锁更轻量级的线程之间通信的机制，JSR-133专家组决定增强volatile的内存语义：严格限制编译器和处理器对volatile变量与普通变量的重排序，确保volatile的写-读和监视器的释放-获取一样，具有相同的内存语义。

## 锁释放和获取的内存语义
当线程释放锁时，JMM会把该线程对应的本地内存中的共享变量刷新到主内存中。以上面的MonitorExample程序为例，A线程释放锁后，共享数据的状态示意图如下：
![锁释放后的状态](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm16.png)
当线程获取锁时，JMM会把该线程对应的本地内存置为无效。从而使得被监视器保护的临界区代码必须要从主内存中去读取共享变量。下面是锁获取的状态示意图：
![获取锁时的状态](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm17.png)
对比锁释放-获取的内存语义与volatile写-读的内存语义，可以看出：**锁释放与volatile写有相同的内存语义；锁获取与volatile读有相同的内存语义。**

借助ReentrantLock的源代码，来分析锁内存语义的具体实现机制。
```
class ReentrantLockExample {
    int a = 0;
    ReentrantLock lock = new ReentrantLock();

    public void writer() {
        lock.lock();         //获取锁
        try {
            a++;
        } finally {
            lock.unlock();  //释放锁
        }
    }

    public void reader () {
        lock.lock();        //获取锁
        try {
            int i = a;
        ……
        } finally {
            lock.unlock();  //释放锁
        }
    }
}
```
在ReentrantLock中，调用lock()方法获取锁；调用unlock()方法释放锁。

ReentrantLock的实现依赖于java同步器框架AbstractQueuedSynchronizer（AQS）。AQS使用一个整型的volatile变量（命名为state）来维护同步状态，马上我们会看到，这个volatile变量是ReentrantLock内存语义实现的关键。 下面是ReentrantLock的类图：
![ReentrantLock的类图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm18.png)
ReentrantLock分为公平锁和非公平锁，我们首先分析公平锁。

使用公平锁时，加锁方法lock()的方法调用轨迹如下：
ReentrantLock.lock() -> FairSync.lock() -> AbstractQueuedSynchronizer.acquire(int arg) -> ReentrantLock.tryAcquire(int acquires)
```
protected final boolean tryAcquire(int acquires) {
    final Thread current = Thread.currentThread();
    int c = getState();   //获取锁的开始，首先读volatile变量state
    if (c == 0) {
        if (isFirst(current) &&
            compareAndSetState(0, acquires)) {
            setExclusiveOwnerThread(current);
            return true;
        }
    }
    else if (current == getExclusiveOwnerThread()) {
        int nextc = c + acquires;
        if (nextc < 0)  
            throw new Error("Maximum lock count exceeded");
        setState(nextc);
        return true;
    }
    return false;
}
```
从上面源代码中我们可以看出，加锁方法首先读volatile变量state。

在使用公平锁时，解锁方法unlock()的方法调用轨迹如下：
ReentrantLock -> unlock() -> AbstractQueuedSynchronizer.release(int arg) -> Sync.tryRelease(int releases)
```
protected final boolean tryRelease(int releases) {
    int c = getState() - releases;
    if (Thread.currentThread() != getExclusiveOwnerThread())
        throw new IllegalMonitorStateException();
    boolean free = false;
    if (c == 0) {
        free = true;
        setExclusiveOwnerThread(null);
    }
    setState(c);           //释放锁的最后，写volatile变量state
    return free;
}
```
从上面的源代码我们可以看出，在释放锁的最后写volatile变量state。

公平锁在释放锁的最后写volatile变量state；在获取锁时首先读这个volatile变量。根据volatile的happens-before规则，释放锁的线程在写volatile变量之前可见的共享变量，在获取锁的线程读取同一个volatile变量后将立即变的对获取锁的线程可见。

非公平锁的释放和公平锁完全一样，所以这里仅仅分析非公平锁的获取。
```
protected final boolean compareAndSetState(int expect, int update) {
    return unsafe.compareAndSwapInt(this, stateOffset, expect, update);
}
```
该方法以原子操作的方式更新state变量，compareAndSet()就是通常所说的CAS。JDK文档对该方法的说明如下：如果当前状态值等于预期值，则以原子方式将同步状态设置为给定的更新值。此操作具有 volatile 读和写的内存语义。
之前提到过，编译器不会对volatile读与volatile读后面的任意内存操作重排序；也不会对volatile写与volatile写前面的任意内存操作重排序。组合这两个条件，意味着为了同时实现volatile读和volatile写的内存语义，编译器不能对CAS与CAS前面和后面的任意内存操作重排序。

现在对公平锁和非公平锁的内存语义做个总结：
- 公平锁和非公平锁释放时，最后都要写一个volatile变量state。
- 公平锁获取时，首先会去读这个volatile变量。
- 非公平锁获取时，首先会用CAS更新这个volatile变量,这个操作同时具有volatile读和volatile写的内存语义。

## concurrent包的实现
把volatile变量的读/写和CAS可以实现线程之间的通信整合在一起，就形成了整个concurrent包得以实现的基石。如果我们仔细分析concurrent包的源代码实现，会发现一个通用化的实现模式：
- 首先，声明共享变量为volatile；
- 然后，使用CAS的原子条件更新来实现线程之间的同步；
- 同时，配合以volatile的读/写和CAS所具有的volatile读和写的内存语义来实现线程之间的通信。

## final
与前面介绍的锁和volatile相比较，对final域的读和写更像是普通的变量访问。对于final域，编译器和处理器要遵守两个重排序规则：
1. 在构造函数内对一个final域的写入，与随后把这个被构造对象的引用赋值给一个引用变量，这两个操作之间不能重排序。
2. 初次读一个包含final域的对象的引用，与随后初次读这个final域，这两个操作之间不能重排序。

下面，我们通过一些示例性的代码来分别说明这两个规则：
```
public class FinalExample {
    int i;                            //普通变量
    final int j;                      //final变量
    static FinalExample obj;

    public void FinalExample () {     //构造函数
        i = 1;                        //写普通域
        j = 2;                        //写final域
    }

    public static void writer () {    //写线程A执行
        obj = new FinalExample ();
    }

    public static void reader () {       //读线程B执行
        FinalExample object = obj;       //读对象引用
        int a = object.i;                //读普通域
        int b = object.j;                //读final域
    }
}
```
这里假设一个线程A执行writer ()方法，随后另一个线程B执行reader ()方法。下面我们通过这两个线程的交互来说明这两个规则。
- 写final域的重排序规则
    这个规则禁止把final域的写**重排序到构造函数之外**。这个规则的实现包含下面2个方面：
    1. JMM禁止编译器把final域的写重排序到构造函数之外。
    2. 编译器会在final域的写之后，构造函数return之前，插入一个StoreStore屏障。这个屏障禁止处理器把final域的写重排序到构造函数之外。

    假设线程B读对象引用与读对象的成员域之间没有重排序，下图是一种可能的执行时序：
![可能的执行时序](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm19.jpg)
    在上图中，写普通域的操作被编译器重排序到了构造函数之外，读线程B错误的读取了普通变量i初始化之前的值。而写final域的操作，被写final域的重排序规则“限定”在了构造函数之内，读线程B正确的读取了final变量初始化之后的值。
    这是因为写final域的重排序规则可以确保：**在对象引用为任意线程可见之前，对象的final域已经被正确初始化过了，而普通域不具有这个保障**。
- 读final域的重排序规则
    读final域的重排序规则如下：
    在一个线程中，初次读对象引用与初次读该对象包含的final域，JMM禁止处理器重排序这两个操作（注意，这个规则仅仅针对处理器）。编译器会在读final域操作的前面插入一个LoadLoad屏障。

    初次读对象引用与初次读该对象包含的final域，这两个操作之间存在间接依赖关系。由于编译器遵守间接依赖关系，因此**编译器不会重排序这两个操作**。

    现在我们假设写线程A没有发生任何重排序，同时程序在不遵守间接依赖的处理器上执行，下面是一种可能的执行时序：
![另一种可能的执行时序](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm20.png)
    在上图中，读对象的普通域的操作被处理器重排序到读对象引用之前。读普通域时，该域还没有被写线程A写入，这是一个错误的读取操作。而读final域的重排序规则会把读对象final域的操作“限定”在读对象引用之后，此时该final域已经被A线程初始化过了，这是一个正确的读取操作。

- 如果final域是引用类型
```
public class FinalReferenceExample {
    final int[] intArray;                     //final是引用类型
    static FinalReferenceExample obj;

    public FinalReferenceExample () {        //构造函数
        intArray = new int[1];              //1
        intArray[0] = 1;                   //2
    }

    public static void writerOne () {          //写线程A执行
        obj = new FinalReferenceExample ();  //3
    }

    public static void writerTwo () {          //写线程B执行
        obj.intArray[0] = 2;                 //4
    }

    public static void reader () {              //读线程C执行
        if (obj != null) {                    //5
            int temp1 = obj.intArray[0];       //6
        }
    }
}
```
对于引用类型，写final域的重排序规则对编译器和处理器增加了如下约束：
   - 在构造函数内对一个final引用的对象的成员域的写入，与随后在构造函数外把这个被构造对象的引用赋值给一个引用变量，这两个操作之间不能重排序。

对上面的示例程序，我们假设首先线程A执行writerOne()方法，执行完后线程B执行writerTwo()方法，执行完后线程C执行reader ()方法。下面是一种可能的线程执行时序：
![一种可能的时序](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm21.png)
在上图中，1是对final域的写入，2是对这个final域引用的对象的成员域的写入，3是把被构造的对象的引用赋值给某个引用变量。这里除了前面提到的1不能和3重排序外，2和3也不能重排序。

也就是说一个final对象，**其在构造函数中的操作一定是先于构造函数外的操作**

- final引用溢出
    写final域的重排序规则可以确保：在引用变量为任意线程可见之前，该引用变量指向的对象的final域已经在构造函数中被正确初始化过了。其实要得到这个效果，还需要一个保证：在构造函数内部，不能让这个被构造对象的引用为其他线程可见，也就是对象引用不能在构造函数中“逸出”。
```
public class FinalReferenceEscapeExample {
    final int i;
    static FinalReferenceEscapeExample obj;

    public FinalReferenceEscapeExample () {
        i = 1;                              //1写final域
        obj = this;                          //2 this引用在此“逸出”
    }

    public static void writer() {
        new FinalReferenceEscapeExample ();
    }

    public static void reader {
        if (obj != null) {                     //3
            int temp = obj.i;                 //4
        }
    }
}
```
假设一个线程A执行writer()方法，另一个线程B执行reader()方法。这里的操作2使得对象还未完成构造前就为线程B可见。即使这里的操作2是构造函数的最后一步，且即使在程序中操作2排在操作1后面，执行read()方法的线程仍然可能无法看到final域被初始化后的值，因为这里的操作1和操作2之间可能被重排序。实际的执行时序可能如下图所示：![可能的顺序图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm22.png)

从上图我们可以看出：在构造函数返回前，被构造对象的引用不能为其他线程可见，因为此时的final域可能还没有被初始化。但是在构造函数返回后，任意线程都将保证能看到final域正确初始化之后的值。

# 锁的实现
## Synchronized
```
public class SynchronizedDemo {
    public void method() {
        synchronized (this) {
            System.out.println("Method 1 start");
        }
    }
}
```
对上面的代码进行反编译：
![反编译后的字节码](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm23.jpeg)
具体原因如下：
每个对象都会关联一个监视器锁（monitor）。当monitor被占用时就会处于锁定状态，线程执行monitorenter指令时尝试获取monitor的所有权，过程如下：
1. 如果monitor的进入数为0，则该线程进入monitor，然后将进入数设置为1，该线程即为monitor的所有者。
2. 如果线程已经占有该monitor，只是重新进入，则进入monitor的进入数加1. (可重入的原理)
3. 如果其他线程已经占用了monitor，则该线程进入阻塞状态，直到monitor的进入数为0，再重新尝试获取monitor的所有权。

## 锁
![锁](lock_all.jpg)
锁的状态总共有四种：无锁状态、偏向锁、轻量级锁和重量级锁。随着锁的竞争，锁可以从偏向锁 -> 轻量级锁
 -> 重量级锁（但是锁的升级是单向的，也就是说只能从低到高升级，*不会出现锁的降级*）。JDK 1.6中默认是开启偏向锁和轻量级锁的，我们也可以通过-XX:-UseBiasedLocking来禁用偏向锁。锁的状态保存在**对象头**中，剩下的就是指向方法区对象类型数据的指针，以32位的JDK为例：![Mark Word](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm24.png)
**无锁与偏向锁的区别是有没有线程ID**
监视器锁(monitor)本质是依赖于底层的操作系统的Mutex Lock来实现的。而操作系统实现线程之间的切换需要从**用户态转换到核心态**，这个成本非常高，状态之间的转换需要相对比较长的时间，这就是为什么Synchronized效率低的原因。因此，这种依赖于操作系统Mutex Lock所实现的锁我们称之为**重量级锁**。JDK中对Synchronized做的种种优化，其核心都是为了减少这种重量级锁的使用。JDK1.6以后，为了减少获得锁和释放锁所带来的性能消耗，提高性能，引入了**轻量级锁**和**偏向锁**。

## 偏向锁(只修改了线程ID，标志为01，无需释放)
偏向锁是为了在无多线程竞争的情况下尽量减少不必要的轻量级锁执行路径，**因为轻量级锁的获取及释放依赖多次CAS原子指令，而偏向锁只需要在置换ThreadID的时候依赖一次CAS原子指令**（由于一旦出现多线程竞争的情况就必须撤销偏向锁，所以偏向锁的撤销操作的性能损耗必须小于节省下来的CAS原子指令的性能消耗）。

>轻量级锁是为了在线程交替执行同步块时提高性能，而偏向锁则是在只有一个线程执行同步块时进一步提高性能。

- 偏向锁获取过程(标识表状态，threadId表示当前持有线程)：
    1. 访问Mark Word中偏向锁的标识是否设置成1，锁标志位是否为01，**确认为可偏向状态**。
    2. 如果为可偏向状态，则测试**线程ID是否指向当前线程**，如果是，进入步骤（5），否则进入步骤（3）。
    3. 如果线程ID并未指向当前线程，则通过**CAS操作竞争锁**。如果竞争成功，则将Mark Word中线程ID设置为当前线程ID，然后执行（5）；如果竞争失败，执行（4）。
    4. 如果CAS获取偏向锁失败，则表示有竞争。当到达全局安全点（safepoint）时获得偏向锁的线程被挂起，偏向锁**升级为轻量级锁**，然后被阻塞在安全点的线程继续往下执行同步代码。
    5. 执行同步代码。

- 偏向锁的释放：
　　偏向锁只有遇到其他线程尝试竞争偏向锁时，持有偏向锁的线程才会释放锁，线程不会主动去释放偏向锁。偏向锁的撤销，需要等待全局安全点（在这个时间点上没有字节码正在执行），它会首先暂停拥有偏向锁的线程，判断锁对象是否处于被锁定状态，撤销偏向锁后恢复到未锁定（标志位为“01”）或轻量级锁（标志位为“00”）的状态。

## 轻量级锁
**修改了对象头的记录、标志位和栈帧记录，标志为00，解锁需要拷贝回对象头，标志依旧是00，根据栈帧记录判断持有锁的线程**
- 轻量级锁的加锁过程
    1. 在代码进入同步块的时候，如果同步对象锁状态为无锁状态（锁标志位为“01”状态，是否为偏向锁为“0”），虚拟机首先将在**当前线程的栈帧中建立一个名为锁记录**（Lock Record）的空间，用于存储锁对象目前的Mark Word的拷贝，官方称之为 Displaced Mark Word。这时候线程堆栈与对象头的状态如下图所示。
![栈帧和对象头关系](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm25.jpeg)
    2. **拷贝对象头中的Mark Word到锁记录(Lock Record)中**。
    3. 拷贝成功后，虚拟机将使用**CAS操作**尝试将 **对象的Mark Word更新为指向栈帧中的锁记录(Lock Record)** 的指针，并将 **栈帧中锁记录(Lock Record)里的owner指针指向对象的 Mark word**。如果更新成功，则执行步骤（3），否则执行步骤（4）。
    4. 如果这个更新动作成功了，那么这个线程就拥有了该对象的锁，并且更新对象Mark Word的**锁标志**位设置为“00”，即表示此对象处于轻量级锁定状态，这时候线程堆栈与对象头的状态如下图所示。
![轻量级锁状态](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm26.jpeg)

    5. 如果这个更新操作失败了，虚拟机首先会检查对象的Mark Word是否指向当前线程的栈帧，如果是就说明当前线程已经拥有了这个对象的锁，那就可以直接进入同步块继续执行。否则说明多个线程竞争锁，轻量级锁就要膨胀为重量级锁，锁标志的状态值变为“10”，Mark Word中存储的就是指向重量级锁（互斥量）的指针，后面等待锁的线程也要进入阻塞状态。 而当前线程便尝试使用自旋来获取锁，自旋就是为了不让线程阻塞，而采用循环去获取锁的过程。

- 轻量级锁的解锁过程
    1. 通过CAS操作尝试把**栈帧中复制的 Mark Word对象替换当前的Mark Word**。
    2. 如果替换成功，整个同步过程就完成了。
    3. 如果替换失败，说明有其他线程尝试过获取该锁（此时锁已膨胀），那就要在释放锁的同时，唤醒被挂起的线程。

## 重量级锁
**Mark Word指向 monitor，monitor负责管理阻塞、执行队列**
首先重量级锁有多个队列，当多个线程一起访问某个对象监视器的时候，对象监视器会将这些线程存储在不同的容器中。
    - ContentionList。竞争队列，所有请求锁的线程首先被放在这个竞争队列中；
    - EntryList。ContentionList中那些有资格成为**候选资源**的线程被移动到EntryList中；
    - WaitSet。由于wait方法被阻塞的线程被放置在这里
    - OnDeck。任意时刻，最多只有一个线程正在竞争锁资源，该线程被成为OnDeck；
    - Owner：当前已经获取到所资源的线程被称为Owner；
    - !Owner：当前释放锁的线程。

JVM每次从队列的尾部取出一个数据用于锁竞争候选者（OnDeck），但是并发情况下，ContentionList会被大量的并发线程进行CAS访问，也为了降低对尾部元素的竞争，JVM会将一部分线程移动到 EntryList 中作为候选竞争线程。Owner线程会在unlock时，将ContentionList中的部分线程迁移到EntryList中，并指定EntryList中的某个线程为OnDeck线程（一般是最先进去的那个线程）。Owner线程并不直接把锁传递给OnDeck线程，而是把锁竞争的权利交给OnDeck，OnDeck需要重新竞争锁（与此时synchronized的线程竞争）。这样虽然牺牲了一些公平性，但是能极大的提升系统的吞吐量，在JVM中，也把这种选择行为称之为“竞争切换”。

OnDeck线程获取到锁资源后会变为Owner线程，而没有得到锁资源的仍然停留在EntryList中。如果Owner线程被wait方法阻塞，则转移到WaitSet队列中，直到某个时刻通过notify或者notifyAll唤醒，会重新进去EntryList中。

处于ContentionList、EntryList、WaitSet中的线程都处于阻塞状态，该阻塞是由操作系统来完成的（Linux内核下采用pthread_mutex_lock内核函数实现的）。

Synchronized是**非公平锁**。 Synchronized在线程进入ContentionList时，等待的线程会**先尝试自旋获取锁**，如果获取不到就进入ContentionList，这明显对于已经进入队列的线程是不公平的，还有一个不公平的事情就是自旋获取锁的线程甚至可能直接抢占OnDeck线程的锁资源。
![synchronized管理示意图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm28.png)

## 重量级锁、轻量级锁和偏向锁之间转换
![转换图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/jvm/jvm27.jpeg)
最后 2bit 的值的变化是 01 -> 00 -> 10

## 自旋锁
自旋锁原理非常简单，如果持有锁的线程能在很短时间内释放锁资源，那么那些等待竞争锁的线程就不需要做内核态和用户态之间的切换进入阻塞挂起状态，它们只需要等一等（自旋），等持有锁的线程释放锁后即可立即获取锁，这样就避免用户线程和内核的切换的消耗。
