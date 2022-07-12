---
title: Rx源码分析之调用
toc: true
date: 2022-07-01 14:27:49
tags:
- android
categories:
- android
---
```java
Observable.just("Hello world")
        .map(String::length)
        .subscribeOn(Schedulers.computation())
        .observeOn(AndroidSchedulers.mainThread())
        .subscribe(len -> {
            System.out.println("got " + len + " @ "
                    + Thread.currentThread().getName());
        });
```
<!--more-->
# 调用

## just
根据参数创建`ObservableJust` 对象
```java
@CheckReturnValue
@NonNull
@SchedulerSupport(SchedulerSupport.NONE)
public static <T> Observable<T> just(T item) {
    ObjectHelper.requireNonNull(item, "item is null");
    return RxJavaPlugins.onAssembly(new ObservableJust<T>(item));
}

...

public final class ObservableJust<T> extends Observable<T> implements ScalarCallable<T> {
@Override
protected void subscribeActual(Observer<? super T> observer) {
    ScalarDisposable<T> sd = new ScalarDisposable<T>(observer, value);
    observer.onSubscribe(sd);
    sd.run();
}
}
```
## subscribeOn
`ObservableJust` 创建 `ObservableSubscribeOn`对象，并添加 `Scheduler`
```java
    @CheckReturnValue
    @SchedulerSupport(SchedulerSupport.CUSTOM)
    public final Observable<T> subscribeOn(Scheduler scheduler) {
        ObjectHelper.requireNonNull(scheduler, "scheduler is null");
        return RxJavaPlugins.onAssembly(new ObservableSubscribeOn<T>(this, scheduler));
    }

public final class ObservableSubscribeOn<T> extends AbstractObservableWithUpstream<T, T> {
    final Scheduler scheduler;

    @Override
    public void subscribeActual(final Observer<? super T> observer) {
        final SubscribeOnObserver<T> parent = new SubscribeOnObserver<T>(observer);
        observer.onSubscribe(parent);
        parent.setDisposable(scheduler.scheduleDirect(new SubscribeTask(parent)));
    }

    final class SubscribeTask implements Runnable {
        private final SubscribeOnObserver<T> parent;

        SubscribeTask(SubscribeOnObserver<T> parent) {
            this.parent = parent;
        }

        @Override
        public void run() {
            source.subscribe(parent);
        }
    }

    static final class SubscribeOnObserver<T>
                 extends AtomicReference<Disposable>
                 implements Observer<T>, Disposable {
            @Override
            public void onNext(T t) {
                downstream.onNext(t);
            }
    }
}
```

## observeOn
`ObservableSubscribeOn`创建 `ObservableObserveOn` 对象，同时也添加一个 `scheduler`
```java
    @CheckReturnValue
    @SchedulerSupport(SchedulerSupport.CUSTOM)
    public final Observable<T> observeOn(Scheduler scheduler, boolean delayError, int bufferSize) {
        ObjectHelper.requireNonNull(scheduler, "scheduler is null");
        ObjectHelper.verifyPositive(bufferSize, "bufferSize");
        return RxJavaPlugins.onAssembly(new ObservableObserveOn<T>(this, scheduler, delayError, bufferSize));
    }

public final class ObservableObserveOn<T> extends AbstractObservableWithUpstream<T, T> {
    final Scheduler scheduler;
    @Override
    protected void subscribeActual(Observer<? super T> observer) {
        if (scheduler instanceof TrampolineScheduler) {
            source.subscribe(observer);
        } else {
            Scheduler.Worker w = scheduler.createWorker();
            source.subscribe(new ObserveOnObserver<T>(observer, w, delayError, bufferSize));
        }
    }

    static final class ObserveOnObserver<T> extends BasicIntQueueDisposable<T>
    implements Observer<T>, Runnable {
        @Override
        public void onNext(T t) {
            if (done) {
                return;
            }

            if (sourceMode != QueueDisposable.ASYNC) {
                queue.offer(t);
            }
            schedule();
        }
        void schedule() {
            if (getAndIncrement() == 0) {
                worker.schedule(this);
            }
        }
        @Override
        public void run() {
            if (outputFused) {
                drainFused();
            } else {
                drainNormal();
            }
        }

        void drainNormal() {
            for (;;) {
                ...
                for (;;) {
                    ...
                    try {
                        v = q.poll();
                    } catch (Throwable ex) {
                        Exceptions.throwIfFatal(ex);
                        disposed = true;
                        upstream.dispose();
                        q.clear();
                        a.onError(ex);
                        worker.dispose();
                        return;
                    }
                    ...
                    a.onNext(v);
                }

                missed = addAndGet(-missed);
                if (missed == 0) {
                    break;
                }
            }
        }

        void drainFused() {
            int missed = 1;

            do {
                if (this.cancelled) {
                    return;
                }

                boolean d = this.done;
                Throwable ex = this.error;
                if (!this.delayError && d && ex != null) {
                    this.actual.onError(this.error);
                    this.worker.dispose();
                    return;
                }

                this.actual.onNext((Object)null);
                if (d) {
                    ex = this.error;
                    if (ex != null) {
                        this.actual.onError(ex);
                    } else {
                        this.actual.onComplete();
                    }

                    this.worker.dispose();
                    return;
                }

                missed = this.addAndGet(-missed);
            } while(missed != 0);

        }
    }
}
```
## subscribe
这里代码开始执行，实际是执行的`subscribeActual`
```java
@SchedulerSupport("none")
public final void subscribe(Observer<? super T> observer) {
    ObjectHelper.requireNonNull(observer, "observer is null");

    try {
        observer = RxJavaPlugins.onSubscribe(this, observer);
        ObjectHelper.requireNonNull(observer, "Plugin returned null Observer");
        this.subscribeActual(observer);
    } catch (NullPointerException var4) {
        throw var4;
    } catch (Throwable var5) {
        Exceptions.throwIfFatal(var5);
        RxJavaPlugins.onError(var5);
        NullPointerException npe = new NullPointerException("Actually not, but can't throw other exceptions due to RS");
        npe.initCause(var5);
        throw npe;
    }
}
```
我们看过代码后，可以看出来，通过语句先创建出一些对象，然后从subscribe开始调用，逐层向上游调用，遇到一些切换线程的都会创建一个task 来进行subscribeOn的线程切换，然后到数据源，开始向下游调用，其中都是一些内部类来处理 onSubscribe 和onNext，如下图
![调用](rx_call.png)

# 访问方式
## 串行访问之 发射者循环（emitter-loop）
我们使用了一个 boolean 值来记录当前是否有线程正在替其他所有线程（只允许有一个线程执行发射操作，以此来保证串行访问）进行发射操作，而正在发射的线程会把所有的发射任务执行完毕才会退出发射循环。
```java
class EmitterLoopSerializer {
    boolean emitting;
    boolean missed;
    public void emit() {
        synchronized (this) {           // (1)
            if (emitting) {
                missed = true;          // (2)
                return;
            }
            emitting = true;            // (3)
        }
        for (;;) {
            // do all emission work // (4)
            synchronized (this) {       // (5)
                if (!missed) {          // (6)
                    emitting = false;
                    return;
                }
                missed = false;         // (7)
            }
        }
    }
}
```
注意：由于我们在 synchronized 代码块中，如果（4）处有一个线程正在进行发射操作，那这个线程必须等待我们退出 synchronized 代码块（1），它才能进入 synchronized 代码块（5）。

1. 如果此时有一个线程正在发射，那我们就需要标记一下现在有更多的事件需要发射（由于只能有一个线程执行发射操作，所以后来的线程就不能自己发射了，它需要告诉当前的发射者，还有更多事件需要发射）。上面的例子中只是简单地使用了另一个 boolean 值来进行标记。出于不同的需求，我们可以使用不同的数据类型来标记还有更多的事件需要发射（例如 RxJava 的许多操作符使用了 java.util.List）。
2. 如果此时没有线程正在发射，那当前线程就获得了执行发射操作的权利，它会把 emitting 置为 true。
3. 当一个线程获得执行发射操作的权利之后，我们就进入到了发射循环，并在此尽可能多的执行发射操作（把这个线程能看到的所有需要发射的事件都发射出去）。这个循环的具体实现取决于这个发射者循环需要完成的功能，但是必须非常小心地实现，否则就会导致信号丢失和程序挂起（不执行）。
4. 当发射循环 认为 所有的发射任务执行完毕之后，它会进入 synchronized 代码块（5）。由于有可能会有其他线程在我们进入 synchronized 代码块之前调用 emit 函数，所以有可能依然还有事件需要发射。由于只有一个线程能进入 synchronized 代码块，加上我们使用的 missed 变量，所以当发射者循环进入 synchronized 代码块时，它只能看到仍然没有新的事件需要发射进而退出循环，或者又重新看到了新的事件进而继续循环发送。
5. 如果在发射者循环进入 synchronized 代码块（5）时，没有任何线程调用 emit 函数，我们就停止发射（把 emitting 置为 false）。新的线程在进入 synchronized 代码块（1）时，将会看到 emitting 为 false 了，所以这个线程就会自己进入发射者循环开始发射事件了。
6. 在发射者循环中，如果有更多的事件需要发射，我们会重置 missed 变量的值，然后重新开始循环。重置 missed 非常关键，否则将会导致死循环。

### 发射T类型数据在同步块之外
```java
class ValueEmitterLoop<T> {
    Queue<T> queue = new MpscLinkedQueue<>();    // (1)
    boolean emitting;
    Consumer<? super T> consumer;                // (2)

    public void emit(T value) {
        Objects.requireNonNull(value);
        queue.offer(value);                      // (3)
        synchronized (this) {
            if (emitting) {
                return;                          // (4)
            }
            emitting = true;
        }
        for (;;) {
            T v = queue.poll();                  // (5)
            if (v != null) {
                consumer.accept(v);              // (6)
            } else {
                synchronized (this) {
                    if (queue.isEmpty()) {       // (7)
                        emitting = false;
                        return;
                    }
                }
            }
        }
    }
}
```
### 发射T类型数据在同步块之内
```java
class ValueListEmitterLoop<T> {
    List<T> queue;                           // (1)
    boolean emitting;
    Consumer<? super T> consumer;

    public void emit(T value) {
        synchronized (this) {
            if (emitting) {
                List<T> q = queue;
                if (q == null) {
                    q = new ArrayList<>();   // (2)
                    queue = q;
                }
                q.add(value);
                return;
            }
            emitting = true;
        }
        consumer.accept(value);              // (3)
        for (;;) {
             List<T> q;
             synchronized (this) {           // (4)
                 q = queue;
                 if (q == null) {            // (5)
                     emitting = false;
                     return;
                 }
                 queue = null;               // (6)
             }
             q.forEach(consumer);            // (7)
        }        
    }
}
```
调用 consumer.accept() 的时候，可能会有 unchecked exception 被抛出，然后我们的发射者循环就退出了，但是 emitting 值依然为 true。如果发射事件的过程中伴随着 error 事件,新的线程并不会进入发射者循环，就出问题了.
为了避免这种情况，我们可以为每个调用都加上 try-catch，但通常 emit() 的调用方还是需要知道有异常发生的。所以我们可以把异常传播出去（propagate out），然后在异常发生时把 emitting 置为 false。
```java
public void emit(T value) {
       synchronized (this) {
           // same as above
           // ...
       }
       boolean skipFinal = false;             // (1)
       try {
           consumer.accept(value);            // (5)
           for (;;) {
               List<T> q;
               synchronized (this) {           
                   q = queue;
                   if (q == null) {            
                       emitting = false;
                       skipFinal = true;      // (2)
                       return;
                   }
                   queue = null;
               }
               q.forEach(consumer);           // (6)
           }
       } finally {
           if (!skipFinal) {                  // (3)
               synchronized (this) {
                   emitting = false;          // (4)
               }
           }
       }
   }
```
由于 RxJava 无法断定使用者的多线程或者线程调度场景，所以它需要在同步和异步场景下都能很好的工作。而我们发现，大部分应用在使用 RxJava 时，都是在同步场景中。synchronized 就完全没有额外的性能开销了，所以在串行场景下性能会更优.

## 串行访问之 队列漏（queue-drain）
如果异步执行占了主要部分，或者发射操作在另一个线程执行，由于其阻塞（blocking）的原理，发射者循环就会出现性能瓶颈。我们需要另一种非阻塞的串行实现方式，我称之为队列漏（queue-drain）
它的实现过程是比较简单的
```java
class BasicQueueDrain {
    final AtomicInteger wip = new AtomicInteger();  // (1)
    public void drain() {
        // work preparation
        if (wip.getAndIncrement() == 0) {           // (2)
            do {
                // work draining
            } while (wip.decrementAndGet() != 0);   // (3)
        }
    }
}
```
它的实现原理是这样的：
1. 我们需要有一个可以进行原子自增操作的数字变量，我通常称之为 wip (work-in-progress 的缩写)。它用来记录需要被执行的任务数量，只要 Java runtime 底层实现具有支持（2）和（3）操作的原语，那我们实现的队列漏甚至是完全没有等待（阻塞）的（译者注：CPU 如果支持 compare and set 指令，那自增操作就只需要一条指令）。在 RxJava 中我们使用了 AtomicInteger，因为我们认为在通常的场景下，溢出是不可能发生的。当然，如果需要的话，它完全可以替换为 AtomicLong。
2. 我们利用原子操作，获取 wip 当前的值，并对它进行加一操作。只有把它从零增加到一的线程才能进入后面的循环，而其他所有的线程都将在加一操作之后返回。
3. 每当一件任务被取出（漏出）并处理完毕，我们就对 wip 进行减一操作。如果减到了零，那我们就退出循环。由于我们只有一个线程在进行减一操作，我们就能保证不会发生信号丢失。
如果两个线程中，wip == 1，如果（2）先执行完毕，变为2，此线程不执行，（3）得到的 wip 值仍然为一，那就会再进行一次循环；而如果（3）先执行完毕，则wip变为0退出循环，那（2）就是把 wip 从零增加到一的线程，那它就会进入后面的循环，两者没有任何干扰。

### 发射T类型数据
```java
class ValueQueueDrain<T> {
    final Queue<T> queue = new MpscLinkedQueue<>();     // (1)
    final AtomicInteger wip = new AtomicInteger();
    Consumer consumer;                                  // (2)

    public void drain(T value) {
        queue.offer(Objects.requireNonNull(value));     // (3)
        if (wip.getAndIncrement() == 0) {
            do {
                T v = queue.poll();                     // (4)
                consumer.accept(v);                     // (5)
            } while (wip.decrementAndGet() != 0);       // (6)
        }
    }
}
```
### 性能比较
如果我们在单线程场景下对 ValueEmitterLoop 和 ValueQueueDrain 进行性能测试，在启动完毕（JIT 生效）之后，后者的吞吐量会更低。
出现这样的现象，是因为队列漏方式存在无法避免的原子操作开销，即便在没有多线程进程的场景下，也会多消耗几个 CPU 周期，这是由现代多核 CPU 强制缓冲区写刷新（mandatory write-buffer flush）导致的。我们每次 drain() 一个数据的时候，有两次增减原子操作，以及 MpscLinkedQueue 使用的原子操作。而一旦 ValueListEmitterLoop 完成了锁优化之后，性能就会更好。

### 队列漏优化
方案一
```java
class ValueQueueDrainFastpath<T> {
    final Queue<T> queue = new MpscLinkedQueue<>();
    final AtomicInteger wip = new AtomicInteger();
    Consumer consumer;

    public void drain(T value) {
        Objects.requireNonNull(value);
        if (wip.compareAndSet(0, 1)) {          // (1)
            consumer.accept(value);             // (2)
            if (wip.decrementAndGet() == 0) {   // (3)
                return;
            }
        } else {
            queue.offer(value);                 // (4)
            if (wip.getAndIncrement() != 0) {   // (5)
                return;
            }
        }
        do {
            T v = queue.poll();                 // (6)
            consumer.accept(v);
        } while (wip.decrementAndGet() != 0);
    }
}
```
这种优化主要是增加了一种单线程场景，如果是多线程场景，依旧会走原来的消耗

方案二
```java
class ValueQueueDrainOptimized<T> {
    final Queue<T> queue = new MpscLinkedQueue<>();
    final AtomicInteger wip = new AtomicInteger();
    Consumer consumer;

    public void drain(T value) {
        queue.offer(Objects.requireNonNull(value));
        if (wip.getAndIncrement() == 0) {
            do {
                wip.set(1);                              // (1)
                T v;
                while ((v = queue.poll()) != null) {     // (2)
                    consumer.accept(v);
                }
            } while (wip.decrementAndGet() != 0);        // (3)
        }
    }
}  
```
优化策略是把后续的所有数据一次性批量漏空，（2）处的缓存一致性（cache-coherence）保证，可能会让我们在某些情况下性能没有任何提升，所以这一版本的性能会取决于对 drain() 的调用分布。

# 背压
数据都是从 observable 到 subscriber 的，但要是 observable 发得太快，subscriber 处理不过来，该怎么办？一种办法是，把数据保存起来，但这显然可能导致内存耗尽；另一种办法是，多余的数据来了之后就丢掉，至于丢掉和保留的策略可以按需制定；还有一种办法就是让 subscriber 向 observable 主动请求数据，subscriber 不请求，observable 就不发出数据。它俩相互协调，避免出现过多的数据，而协调的桥梁。
```java
//被观察者在主线程中，每1ms发送一个事件
Observable.interval(1, TimeUnit.MILLISECONDS)
                //.subscribeOn(Schedulers.newThread())
                //将观察者的工作放在新线程环境中
                .observeOn(Schedulers.newThread())
                //观察者处理每1000ms才处理一个事件
                .subscribe(new Action1<Long>() {
                      @Override
                      public void call(Long aLong) {
                          try {
                              Thread.sleep(1000);
                          } catch (InterruptedException e) {
                              e.printStackTrace();
                          }
                          Log.w("TAG","---->"+aLong);
                      }
                  });
```
这段代码运行之后：
```
    ...
    Caused by: rx.exceptions.MissingBackpressureException
    ...
    ...
```
抛出MissingBackpressureException往往就是因为，被观察者发送事件的速度太快，而观察者处理太慢，而且你还没有做相应措施，所以报异常。

## 定义
背压是指在异步场景中，被观察者发送事件速度远快于观察者的处理速度的情况下，一种告诉上游的被观察者降低发送速度的策略

## 响应式拉取（reactive pull）

观察者主动从被观察者那里去拉取数据，而被观察者变成被动的等待通知再发送数据。
```java
//被观察者将产生100000个事件
Observable observable=Observable.range(1,100000);
class MySubscriber extends Subscriber<T> {
    @Override
    public void onStart() {
    //一定要在onStart中通知被观察者先发送一个事件
      request(1);
    }

    @Override
    public void onCompleted() {
        ...
    }

    @Override
    public void onError(Throwable e) {
        ...
    }

    @Override
    public void onNext(T n) {
        ...
        ...
        //处理完毕之后，在通知被观察者发送下一个事件
        request(1);
    }
}

observable.observeOn(Schedulers.newThread())
            .subscribe(MySubscriber);
```
在代码中，传递事件开始前的onstart()中，调用了request(1)，通知被观察者先发送一个事件，然后在onNext()中处理完事件，再次调用request(1)，通知被观察者发送下一个事件....
如果你想取消这种backpressure 策略，调用quest(Long.MAX_VALUE)即可。
