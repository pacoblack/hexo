---
title: glide源码简析
toc: true
date: 2021-02-24 17:50:33
tags:
- android
- 开源
categories:
- android
---
glide是一个图片管理器
<!--more-->
首先是一个简单的用法
```
Glide.with(fragment)
    .load(myUrl)
    .into(imageView);
```
![总体框架](https://raw.githubusercontent.com/pacoblack/BlogImages/master/glide/glide1.jpg)
# 简介
Glide是一个性能优良的第三方网络图片加载框架，在节省内存和快速流畅加载方面具有较好体现。究其内部机制，发现其优良性能得益于以下几点：
1. 与使用环境生命周期相绑定：RequestManagerFragment & SupportRequestManagerFragment
2. 内存的三级缓存池：LruMemoryResources, ActiveResources, BitmapPool
3. 内存复用机制：BitmapPool、ArrayPool
![缓存示意图](glide-cache-arch.png)
注意：完成解码的图片resource并不是一开始就被添加到cache，而是先添加到active resource。当resource被释放时，如果可缓存则添加到cache，如果不可缓存则经由recycler回收至bitmapPool

## 缓存策略简介
GlideBuilder允许自定义缓存策略。如果没有自定义缓存策略，使用内置的缓存策略。
```java
public final class GlideBuilder {

    public Glide build(Context context) {
        ...
    
        if (memorySizeCalculator == null) {
          memorySizeCalculator = new MemorySizeCalculator.Builder(context).build();
        }
        //如果resource不可缓存则经由recycler回收至bitmapPool，回收时需要
        if (bitmapPool == null) {
          int size = memorySizeCalculator.getBitmapPoolSize();
          bitmapPool = new LruBitmapPool(size);
        }
        //防止图片操作导致内存抖动和频繁GC，解码时需要
        if (arrayPool == null) {
          arrayPool = new LruArrayPool(memorySizeCalculator.getArrayPoolSizeInBytes());
        }

        if (memoryCache == null) {
          memoryCache = new LruResourceCache(memorySizeCalculator.getMemoryCacheSize());
        }
    
        if (diskCacheFactory == null) {
          diskCacheFactory = new InternalCacheDiskCacheFactory(context);
        }
    
        ...
        engine = new Engine(memoryCache, diskCacheFactory, diskCacheExecutor, sourceExecutor,
              GlideExecutor.newUnlimitedSourceExecutor());
    
    
        RequestManagerRetriever requestManagerRetriever = new RequestManagerRetriever(
            requestManagerFactory);
    
        return new Glide(...);
    }
}
```
**BitmapPool出现在有Bitmap回收需求的地方，而ArrayPool则出现在有解码需求的地方。**

# 绑定生命周期
![glide_lifecycle.jpg](https://raw.githubusercontent.com/pacoblack/BlogImages/master/glide/glide2.jpg)
这里就是一个简单的返回 `RequestManager` 的时序图
```
  RequestManager(
      Glide glide,
      Lifecycle lifecycle,
      RequestManagerTreeNode treeNode,
      RequestTracker requestTracker,
      ConnectivityMonitorFactory factory,
      Context context) {
    this.glide = glide;
    this.lifecycle = lifecycle;
    this.treeNode = treeNode;
    this.requestTracker = requestTracker;
    this.context = context;

    connectivityMonitor =
        factory.build(
            context.getApplicationContext(),
            new RequestManagerConnectivityListener(requestTracker));
    // lifecycle 注册回调
    if (Util.isOnBackgroundThread()) {
      mainHandler.post(addSelfToLifecycle);
    } else {
      lifecycle.addListener(this);
    }
    lifecycle.addListener(connectivityMonitor);

    defaultRequestListeners =
        new CopyOnWriteArrayList<>(glide.getGlideContext().getDefaultRequestListeners());
    setRequestOptions(glide.getGlideContext().getDefaultRequestOptions());
    // glide 注册RequestManager
    glide.registerRequestManager(this);
  }
```
这里就是把 `RequestManager` 和 `lifecycle` 绑定起来

# 请求管理
上面已经初始化好了 `RequestManager`, 当调用 `load` 方法的时候会构建一个`RequestBuilder`
```
  @NonNull
  @CheckResult
  @Override
  public RequestBuilder<Drawable> load(@Nullable Uri uri) {
    return asDrawable().load(uri);
  }

  @NonNull
  @CheckResult
  public RequestBuilder<Drawable> asDrawable() {
    return as(Drawable.class);
  }
```
`RequestBuilder`的构造函数非常简单，没有过多的操作，主要是初始化了一些参数，主要包括 `requestManager` 和 `transcodeClass`，分别用来管理request 队列和返回type，主要的方法还是 `into`
```
  private <Y extends Target<TranscodeType>> Y into(
      @NonNull Y target,
      @Nullable RequestListener<TranscodeType> targetListener,
      BaseRequestOptions<?> options,
      Executor callbackExecutor) {
    Preconditions.checkNotNull(target);
    if (!isModelSet) {
      throw new IllegalArgumentException("You must call #load() before calling #into()");
    }

    Request request = buildRequest(target, targetListener, options, callbackExecutor);

    Request previous = target.getRequest();
    if (request.isEquivalentTo(previous)
        && !isSkipMemoryCacheWithCompletePreviousRequest(options, previous)) {
      request.recycle();
      // 资源重用
      if (!Preconditions.checkNotNull(previous).isRunning()) {
        // 使用先前的 request
        previous.begin();
      }
      return target;
    }
    // 清空之前的request，设置当前的request，并将request添加到 requestManager的track队列中
    requestManager.clear(target);
    target.setRequest(request);
    requestManager.track(target, request);

    return target;
  }
```
```
  synchronized void track(@NonNull Target<?> target, @NonNull Request request) {
    targetTracker.track(target);
    requestTracker.runRequest(request);
  }
```
在request 添加到 requestTracker 后，由于 requestTracker 受 requestManager 管理，requestManager 又和生命周期绑定，所以会相应的执行 `onStart`, `onStop`, ` onDestroy`,Tracker 就会相应的开始， 暂停和清空队列。

# 缓存
不同于其他常见网络加载框架只有LruCatch一种缓存机制，Glide内存为三块：
- ActiveResourceCache：缓存当前正在使用的资源（***注意是弱引用***）
- LruResourceCache： 缓存最近使用过但是当前未使用的资源，LRU算法
- BitmapPool：缓存所有被释放的图片，内存复用，LRU算法

***LruResourceCache和ActiveResourceCache设计是为了尽可能的资源复用，而BitmapPool的设计目的是为了尽可能的内存复用***

![缓存过程图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/glide/glide3.png)
当我们需要某个资源的时候，我们会：
1. 先去查找ActiveResourceCache；
2. ActiveResourceCache找不到资源则查找LruResourceCache，找到了则将资源从LruResourceCache移除加入到ActiveResourceCache；
3. 如果在LruResourceCache也找不到合适的资源，则会根据加载策略从硬盘或者网络加载资源。

找到资源后，我们会：
1. 从BitmapPool中找寻合适的可供内存复用的废弃recycled bitmap（找不到则会重新创建bitmap对象），然后刷新bitmap的数据。
2. bitmap被转换封装为Resource缓存入ActiveResourceCache和Request对象中。也就是说此时有一个资源同时存在 ActiveResourceCache 和 BitMapPool 中，只是格式不同。（推测 Cache中保存的是数据的引用）
3. Request的target会从ActiveResourceCache中获取resource引用的bitmap并展示。

当数据不再使用时，我们会：
1. 当target的资源需要release时，resource会首先被缓存到LruResourceCache，同时ActiveResourceCache中的弱引用会被删除。如果，该资源不能缓存到LruResourceCache，则资源将被recycle到BitmapPool。
2. 当需要回收内存时（比如系统内存不足或者生命周期结束），LruResourceCache将根据LRU算法recycle一些resource到BitmapPool。
3. BitmapPool 会根据***LRU算法和缓存池的尺寸***来决定缓存的bitmap 和 释放的资源
4. 系统 GC时， 会回收可回收的资源
![Glide回收示例](https://raw.githubusercontent.com/pacoblack/BlogImages/master/glide/glide4.png)
回收前的状态是：ActiveCache 持有45678，LruCache 持有 123， bitmapPool 持有 abc，它们每个的大小都是1M，
现在我们要回收3M
回收过程是：ActiveCache 因为持有弱引用首先释放，但是具体的内存没有释放，因为 viewTarget还持有，所以无法执行第一步；接下来 LruCache 会根据算法减少3M，从而将123 缓存到 bitmapPool，释放abc，现在达到目标，无需继续执行。
# 执行流程
上面讲到 `RequestBuilder.into()` ->
`RequestManager.track() ` ->
`RequestTracker.runRequest()` 来启动请求
这个request 一般都是从 `SingleRequest`的 `begin`开始，在 `onSizeReady` 中委托 `engine.load()` 方法
注意：根据buildKey，同一张图片加载到2个不同大小的ImageView会生成2个缓存图片
```
  public synchronized <R> LoadStatus load(
      GlideContext glideContext,
      Object model,
      Key signature,
      int width,
      int height,
      Class<?> resourceClass,
      Class<R> transcodeClass,
      Priority priority,
      DiskCacheStrategy diskCacheStrategy,
      Map<Class<?>, Transformation<?>> transformations,
      boolean isTransformationRequired,
      boolean isScaleOnlyOrNoTransform,
      Options options,
      boolean isMemoryCacheable,
      boolean useUnlimitedSourceExecutorPool,
      boolean useAnimationPool,
      boolean onlyRetrieveFromCache,
      ResourceCallback cb,
      Executor callbackExecutor) {
    long startTime = VERBOSE_IS_LOGGABLE ? LogTime.getLogTime() : 0;
    // 获取 key
    EngineKey key = keyFactory.buildKey(model, signature, width, height, transformations,
        resourceClass, transcodeClass, options);
    //查找ActiveResourceCache
    EngineResource<?> active = loadFromActiveResources(key, isMemoryCacheable);
    if (active != null) {
      cb.onResourceReady(active, DataSource.MEMORY_CACHE);
      if (VERBOSE_IS_LOGGABLE) {
        logWithTimeAndKey("Loaded resource from active resources", startTime, key);
      }
      return null;
    }
    // 查找 LruResourceCache
    EngineResource<?> cached = loadFromCache(key, isMemoryCacheable);
    if (cached != null) {
      cb.onResourceReady(cached, DataSource.MEMORY_CACHE);
      if (VERBOSE_IS_LOGGABLE) {
        logWithTimeAndKey("Loaded resource from cache", startTime, key);
      }
      return null;
    }
    // 创建EngineJob
    EngineJob<?> current = jobs.get(key, onlyRetrieveFromCache);
    if (current != null) {
      current.addCallback(cb, callbackExecutor);
      if (VERBOSE_IS_LOGGABLE) {
        logWithTimeAndKey("Added to existing load", startTime, key);
      }
      return new LoadStatus(cb, current);
    }

    EngineJob<R> engineJob =
        engineJobFactory.build(
            key,
            isMemoryCacheable,
            useUnlimitedSourceExecutorPool,
            useAnimationPool,
            onlyRetrieveFromCache);
    //创建DecodeJob:注意fetcher（数据加载器）
    DecodeJob<R> decodeJob =
        decodeJobFactory.build(
            glideContext,
            model,
            key,
            signature,
            width,
            height,
            resourceClass,
            transcodeClass,
            priority,
            diskCacheStrategy,
            transformations,
            isTransformationRequired,
            isScaleOnlyOrNoTransform,
            onlyRetrieveFromCache,
            options,
            engineJob);
    // 将任务加入管理队列
    jobs.put(key, engineJob);

    engineJob.addCallback(cb, callbackExecutor);
     // 启动任务
    engineJob.start(decodeJob);

    if (VERBOSE_IS_LOGGABLE) {
      logWithTimeAndKey("Started new load", startTime, key);
    }
    return new LoadStatus(cb, engineJob);
  }
```
加载完成后，`SingleRequest` 给 engine 传递来一个 `ResourceCallback` 的回调来调用 `onResourceReady`,在这个方法中来通知各个 target。
当ActiveCache 中保存的是 `EngineResource` 的弱引用，如果EngineResource 通过引用计数来判断引用acquire，当没有引用的时候 release，在 Engine 的 `onResourceReleased` 中，将这个资源放到 LruCache 中,若是 `recycle` 则会放到bitmapPool 中

# 磁盘加载
```
// EngineJob.java
  public synchronized void start(DecodeJob<R> decodeJob) {
    this.decodeJob = decodeJob;
    GlideExecutor executor = decodeJob.willDecodeFromCache()
        ? diskCacheExecutor
        : getActiveSourceExecutor();
    executor.execute(decodeJob);
  }
```
```
 // DecodeJob.java
  boolean willDecodeFromCache() {
    Stage firstStage = getNextStage(Stage.INITIALIZE);
    return firstStage == Stage.RESOURCE_CACHE || firstStage == Stage.DATA_CACHE;
  }

  private void runWrapped() {
    switch (runReason) {
      case INITIALIZE:  // 显示这里初始化
        stage = getNextStage(Stage.INITIALIZE);
        currentGenerator = getNextGenerator();
        runGenerators();
        break;
      case SWITCH_TO_SOURCE_SERVICE:
        runGenerators();
        break;
      case DECODE_DATA:
        decodeFromRetrievedData();
        break;
      default:
        throw new IllegalStateException("Unrecognized run reason: " + runReason);
    }
  }

  private DataFetcherGenerator getNextGenerator() {
    switch (stage) {
      case RESOURCE_CACHE:
        return new ResourceCacheGenerator(decodeHelper, this);
      case DATA_CACHE: // 磁盘缓存
        return new DataCacheGenerator(decodeHelper, this);
      case SOURCE:
        return new SourceGenerator(decodeHelper, this);
      case FINISHED:
        return null;
      default:
        throw new IllegalStateException("Unrecognized stage: " + stage);
    }
  }
  private void runGenerators() {
    currentThread = Thread.currentThread();
    startFetchTime = LogTime.getLogTime();
    boolean isStarted = false;
    while (!isCancelled && currentGenerator != null
        && !(isStarted = currentGenerator.startNext())) {
      stage = getNextStage(stage);
      currentGenerator = getNextGenerator();

      if (stage == Stage.SOURCE) {
        reschedule();
        return;
      }
    }
    // We've run out of stages and generators, give up.
    if ((stage == Stage.FINISHED || isCancelled) && !isStarted) {
      notifyFailed();
    }

    // Otherwise a generator started a new load and we expect to be called back in
    // onDataFetcherReady.
  }

  private void decodeFromRetrievedData() {
    if (Log.isLoggable(TAG, Log.VERBOSE)) {
      logWithTimeAndKey("Retrieved data", startFetchTime,
          "data: " + currentData
              + ", cache key: " + currentSourceKey
              + ", fetcher: " + currentFetcher);
    }
    Resource<R> resource = null;
    try {
      resource = decodeFromData(currentFetcher, currentData, currentDataSource);
    } catch (GlideException e) {
      e.setLoggingDetails(currentAttemptingKey, currentDataSource);
      throwables.add(e);
    }
    if (resource != null) {
      notifyEncodeAndRelease(resource, currentDataSource);
    } else {
      runGenerators();
    }
  }
```
`Engine` 是 Glide 的一个成员变量，用来管理缓存和磁盘数据的加载。`Engine` 通过一些 JobFactory 生成 `EngineJob`，通过它来加载磁盘数据。如果缓存都没有命中，就需要它来执行。
glide加载过程就是由EngineJob触发DecodeJob,DecodeJob中会有ResourceCacheGenerator->DataCacheGenerator->SourceGenerator，只要其中一个的startNext方法返回为 true，则不再寻找下一个Generator。这三个不一定都会有执行的，如果有缓存存在且能命中，则不会经历SourceGenerator阶段，否则就会有SourceGenerator 并且还会更新缓存。
- ResourceCacheGenerator 从包含 ***downsampled/transformed*** 的缓存文件中生成 DataFetchers
- DataCacheGenerator 从包含***原始、未修改***的缓存文件中生成 DataFetchers
- SourceGenerator 从***原始数据***来生成 DataFetchers
在DecodeJob中获取到数据之后，则会层层上报，由Fetcher->Generator->DecodeJob->EngineJob->SingleRequest->Target这样一个序列回调

# 磁盘缓存
磁盘缓存比较简单，其中也分为ResourceCacheKey与DataCacheKey，一个是已经decode过的可以之间供Target给到View去渲染的，另一个是还未decode过的，缓存的是源数据。磁盘缓存的保存是在第一次请求网络成功时候，会刷新磁盘缓存，此时处理的是源数据，至于是否会缓存decode过后的数据，取决于DiskCacheStrategy的策略。

# 加载全过程
1. 按照之前的 ActiveResourcesCache 和 LruCache 读取顺序
2. 如果内存没有，就构造或复用已有的EngineJob与DecodeJob，开始资源的加载，加载过程是ResourceCacheGenerator -> DataCacheGenerator -> SourceGenerator优先级顺序，不管哪种方式取到了数据，最终都会回调至DecodeJob中处理。
3. DecodeJob回调中，一方面通过decodeFromData从DataFetcher中decode取到的原数据，转换为View能够展示的Resource，比如Drawable或Bitmap等，同时根据缓存策略，来决定是否会构建ResourceCacheKey类型的缓存。
