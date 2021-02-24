---
title: okhttp架构解析
toc: true
date: 2021-02-24 15:44:55
tags:
- android
- 开源
categories:
- android
---
OkHttp的优点
- 支持HTTP/2 协议，允许连接到同一个主机地址的所有请求共享Socket。
- 在HTTP/2协议不可用的情况下，通过连接池减少请求的延迟。
- GZip透明压缩减少传输的数据包大小。
- 响应缓存，避免同一个重复的网络请求。
<!--more-->

# 使用入门
```java
OkHttpClient client = new OkHttpClient();

String run(String url) throws IOException {
  Request request = new Request.Builder()
      .url(url)
      .build();

  try (Response response = client.newCall(request).execute()) {
    return response.body().string();
  }
}
```
这就是OkHttp 的简单用法，我们看到只要有 HttpClient、Request、Response
![流程图](https://raw.githubusercontent.com/pacoblack/BlogImages/master/okhttp/okhttp1.png)

# 代码流程
## execute
当我们 `execute` 的时候，我们是委托的 `Dispatcher` 的 `execute`
```java
  synchronized void executed(RealCall call) {
    runningSyncCalls.add(call);
  }
```
```java
@Override
public Response execute() throws IOException {
  synchronized (this) {
    if (executed) throw new IllegalStateException("Already Executed");
    executed = true;
  }
  transmitter.timeoutEnter();
  transmitter.callStart();
  try {
    client.dispatcher().executed(this);
    return getResponseWithInterceptorChain();
  } finally {
    client.dispatcher().finished(this);
  }
}
```
也就是添加到 `Dispatcher` 的 `runningSyncCalls`
```
  private final Deque<AsyncCall> readyAsyncCalls = new ArrayDeque<>();
  // 异步请求队列
  private final Deque<AsyncCall> runningAsyncCalls = new ArrayDeque<>();
  // 同步请求队列
  private final Deque<RealCall> runningSyncCalls = new ArrayDeque<>();
```
这三个都是双向队列，添加到队列后，RealCall 就要 `getResponseWithInterceptorChain()`
```
 Response getResponseWithInterceptorChain() throws IOException {
    // Build a full stack of interceptors.
    List<Interceptor> interceptors = new ArrayList<>();
    //添加开发者应用层自定义的Interceptor
    interceptors.addAll(client.interceptors());
    //这个Interceptor是处理请求失败的重试，重定向    
    interceptors.add(retryAndFollowUpInterceptor);
    //这个Interceptor工作是添加一些请求的头部或其他信息
    //并对返回的Response做一些友好的处理（有一些信息你可能并不需要）
    interceptors.add(new BridgeInterceptor(client.cookieJar()));
    //这个Interceptor的职责是判断缓存是否存在，读取缓存，更新缓存等等
    interceptors.add(new CacheInterceptor(client.internalCache()));
    //这个Interceptor的职责是建立客户端和服务器的连接
    interceptors.add(new ConnectInterceptor(client));
    if (!forWebSocket) {
      //添加开发者自定义的网络层拦截器
      interceptors.addAll(client.networkInterceptors());
    }
    interceptors.add(new CallServerInterceptor(forWebSocket));
    //一个包裹这request的chain
    Interceptor.Chain chain = new RealInterceptorChain(
        interceptors, null, null, null, 0, originalRequest);
    //把chain传递到第一个Interceptor手中
    return chain.proceed(originalRequest);
  }
```
因为每一个interceptor的intercept方法里面都会调用chain.proceed()从而调用下一个interceptor的intercept(next)方法，这样就可以实现遍历getResponseWithInterceptorChain里面interceptors的item，实现遍历循环.

## 请求队列
如果当前还可以执行异步任务，则入队，并立即执行，否则加入readyAsyncCalls队列，当一个请求执行完毕后，会调用 promoteAndExecute()，来把readyAsyncCalls队列中的Async移出来并加入到runningAsyncCalls，并开始执行。然后在当前线程中去执行Call的getResponseWithInterceptorChain（）方法，直接获取当前的返回数据Response.

对比同步和异步任务，我们会发现:同步请求和异步请求原理都是一样的，都是在getResponseWithInterceptorChain()函数通过Interceptor链条来实现网络请求逻辑，而异步任务则通过ExecutorService来实现的。
PS:在Dispatcher中添加一个封装了Callback的Call的匿名内部类AsyncCall来执行当前的Call。这个AsyncCall是RealCall的匿名内部类。AsyncCall的execute方法仍然会回调到RealCall的 getResponseWithInterceptorChain方法来完成请求，同时将返回数据或者状态通过Callback来完成。

## 连接
### Address地址
在 `newRealCall` 的时候配置了 `transmitter`
```java
  static RealCall newRealCall(OkHttpClient client, Request originalRequest, boolean forWebSocket) {
    // Safely publish the Call instance to the EventListener.
    RealCall call = new RealCall(client, originalRequest, forWebSocket);
    call.transmitter = new Transmitter(client, call);
    return call;
  }
```
```java
  private ExchangeFinder exchangeFinder;
  public Transmitter(OkHttpClient client, Call call) {
    this.client = client;
    this.connectionPool = Internal.instance.realConnectionPool(client.connectionPool());
    this.call = call;
    this.eventListener = client.eventListenerFactory().create(call);
    this.timeout.timeout(client.callTimeoutMillis(), MILLISECONDS);
  }
```
`Transmitter` 中有 `connectionPool` 还有 `exchangeFinder`
`getResponseWithInterceptorChain` ->
`RetryAndFollowUpInterceptor.intercept()` ->
`Transmitter.prepareToConnect()` 时需要获取地址，并随后创建`ExchangeFinder`,
它的参数之一 Address 则是通过 `createAddress()`产生的.
`Address` 的url字段仅仅包含HTTP请求的url的schema+host+port三部分的信息，而不包含path和query等信息。它还有一个重要的方法 `equalsNonHost ()`, 这个方法会在连接池复用的时候调用，如果返回 true， 那么就可以使用 `RealConnection` 的复用

### RouteSelector路由
在 `ExchangeFinder` 初始化的时候 new 一个 `RouteSelector`。
这个类主要是选择连接到服务器的路由，选择的连接需要是代理服务器、IP地址、TLS模式 三者中的一种。这个选择的连接是可以被回收的。

`getResponseWithInterceptorChain` ->
`ConnectInterceptor.intercept()` ->
`Transmitter.newExchange()` ->
`ExchangeFinder.find()` ->
`ExchangeFinder.findConnection()` ->
`RouteSelector.next()`

因为HTTP请求连接到服务器的时候，需要找到一个Route，然后依据代理协议规则与特定目标建立TCP连接。如果是**无代理**的情况，是与HTTP服务器建立TCP连接，对于**SOCKS代理和http代理**，是与代理服务器建立tcp连接，虽然都是与代理服务器建立tcp连接，但是SOCKS代理协议和http代理协议又有一定的区别。
有的网站会借助于域名做负均衡，常常会有域名对应不同IP地址的情况。在OKHTTP中，对Route连接有一定的错误处理机制。OKHTTP会逐个尝试找到Route建立TCP连接，直到找到可用的哪一个。这样对Route信息有良好的管理。OKHTTP中借助RouteSelector类管理所有路由信息，并帮助选择路由。
```
public final class Route {
  final Address address;
  final Proxy proxy;
  final InetSocketAddress inetSocketAddress;
}
```
在构造函数中就会调用 `resetNextProxy()` 来收集路由，分为两种情况：1.收集所有的代理；2.收集特定的代理服务器的目标地址。

它们的实现也是通过两种方式：
1. 通过外部address传入代理。因为是来自 OkHttpClient，我们可以指定代理
2. 借助于ProxySelectory获得多个代理。默认收集的所有代理保存在列表proxies中

`RouteSelector`有两个重要的成员函数 `hasNext()` 和 `next()`
`hasNext()` 表明是否还有可用的路由
```
  public boolean hasNext() {
    return hasNextInetSocketAddress()
        || hasNextProxy()
        || hasNextPostponed();
  }

  //是否还有代理
  private boolean hasNextProxy() {
    return nextProxyIndex < proxies.size();
  }

  //是否还有socket地址
  private boolean hasNextInetSocketAddress() {
    return nextInetSocketAddressIndex < inetSocketAddresses.size();
  }

  //是否还有延迟路由
  private boolean hasNextPostponed() {
    return !postponedRoutes.isEmpty();
  }
```
`next()` 方法就是用来获取可能的连接地址
1. 对于没有配置代理的情况，会对HTTP服务器的域名进行DNS域名解析，并为每个解析到的IP地址创建连接的目标地址
2. 对于SOCKS代理，直接以HTTP的服务器的域名以及协议端口创建连接目标地址
3. 对于HTTP代理，则会对HTTP代理服务器的域名进行DNS域名解析，并为每个解析到的IP地址创建 连接的目标地址
```
  public Route next() throws IOException {
    // Compute the next route to attempt.
    if (!hasNextInetSocketAddress()) {
      if (!hasNextProxy()) {
        if (!hasNextPostponed()) {
          throw new NoSuchElementException();
        }
        return nextPostponed();
      }
      lastProxy = nextProxy();
    }
    lastInetSocketAddress = nextInetSocketAddress();

    Route route = new Route(address, lastProxy, lastInetSocketAddress);
    if (routeDatabase.shouldPostpone(route)) {
      postponedRoutes.add(route);
      // We will only recurse in order to skip previously failed routes. They will be tried last.
      return next();
    }

    return route;
  }
```
对应的是 `hasNextPostponed()`, `hasNextProxy()`, `hasNextInetSocketAddress()`

## RetryAndFollowUpInterceptor
上面我们分析了 `Address`、`RouteSelector`，现在我们看它们是怎么用的
```
public final class RetryAndFollowUpInterceptor implements Interceptor {

  private static final int MAX_FOLLOW_UPS = 20;

  private final OkHttpClient client;

  public RetryAndFollowUpInterceptor(OkHttpClient client) {
    this.client = client;
  }

  @Override public Response intercept(Chain chain) throws IOException {
    Request request = chain.request();
    RealInterceptorChain realChain = (RealInterceptorChain) chain;
    Transmitter transmitter = realChain.transmitter();

    int followUpCount = 0;
    Response priorResponse = null;
    while (true) {
      // 根据连接池、Address，构建出了 exchangeFinder
      transmitter.prepareToConnect(request);

      if (transmitter.isCanceled()) {
        throw new IOException("Canceled");
      }

      Response response;
      boolean success = false;
      try {
        // 将配置好的 transmitter 传递个下一个拦截器，即 BridgeIntercepter
        response = realChain.proceed(request, transmitter, null);
        success = true;
      } catch (RouteException e) {
        // The attempt to connect via a route failed. The request will not have been sent.
        if (!recover(e.getLastConnectException(), transmitter, false, request)) {
          throw e.getFirstConnectException();
        }
        continue;
      } catch (IOException e) {
        // An attempt to communicate with a server failed. The request may have been sent.
        boolean requestSendStarted = !(e instanceof ConnectionShutdownException);
        if (!recover(e, transmitter, requestSendStarted, request)) throw e;
        continue;
      } finally {
        // The network call threw an exception. Release any resources.
        if (!success) {
          transmitter.exchangeDoneDueToException();
        }
      }

      // Attach the prior response if it exists. Such responses never have a body.
      if (priorResponse != null) {
        response = response.newBuilder()
            .priorResponse(priorResponse.newBuilder()
                    .body(null)
                    .build())
            .build();
      }

      Exchange exchange = Internal.instance.exchange(response);
      // 获取route
      Route route = exchange != null ? exchange.connection().route() : null;
      Request followUp = followUpRequest(response, route);

      if (followUp == null) {
        if (exchange != null && exchange.isDuplex()) {
          transmitter.timeoutEarlyExit();
        }
        return response;
      }

      RequestBody followUpBody = followUp.body();
      if (followUpBody != null && followUpBody.isOneShot()) {
        return response;
      }

      closeQuietly(response.body());
      if (transmitter.hasExchange()) {
        exchange.detachWithViolence();
      }

      if (++followUpCount > MAX_FOLLOW_UPS) {
        throw new ProtocolException("Too many follow-up requests: " + followUpCount);
      }

      request = followUp;
      priorResponse = response;
    }
  }
}
```
执行过程如下：
1. 先是获取 Call 的`transmitter`, transmitter中是有 connectionPool 的
2. 开启 while 循环
3. 执行 `prepareToConnect`，判断是否是相同连接、是否需要`maybeReleaseConnection()`，并重置 `exchangeFinder`，这个 `finder` 就是用来寻找可用 `Connection`
4. 执行下一个拦截器
5. 如果 priorResponse 不为空，说明得到了 response
6. 获取从 `RouteSelector` 中得到的 Route
7. 执行 `followUpRequest()`查看响应是否需要重定向，如果不需要重定向则返回当前请求
8. 重定向次数+1，同时判断是否达到最大限制数量。是：退出
9. 重置request，并把当前的Response保存到priorResponse，进入下一次的while循环

总的来说：
就是不停的循环来获取response，每循环一次都会获取下一个request，如果没有request，则返回response，退出循环。而获取的request 是根据上一个response 的状态码确定的。

## BridgeInterceptor
主要负责对Request和Response报文进行加工
1. 在发送阶段**补全了一些header**，如Content-Type、Content-Length、Transfer-Encoding、Host、Connection、Accept-Encoding、User-Agent 等。
2. 如果需要gzip压缩则进行**gzip压缩**
3. **加载Cookie**
4. 随后**创建新的request**并交付给后续的interceptor来处理，以获取响应。
5. **保存Cookie**
6. 如果服务器返回的响应content是以gzip压缩过的，则会先进行解压缩，移除响应中的header Content-Encoding和Content-Length，构造新的响应返回。
7. 否则直接返回 response

## CacheInterceptor

### 常用缓存请求头
- Cache-Control 常见的取值有private、public、no-cache、max-age、no-store、默认是 private。
在浏览器里面，private 表示客户端可以缓存，public表示客户端和服务器都可以缓存。
- Last-Modified 服务器告诉浏览器资源的最后修改时间。
- If-Modified-Since 客户端再次请求服务器时，通过此字段通知服务器上次服务器返回的最后修改时间。
资源被改动过，则响应内容返回的状态码是200；资源没有修改，则响应状态码为304，告诉客户端继续使用cache。
- Etag 服务响应请求时，告诉客户端当前资源在服务器的唯一标识
- If-None-Match 客户端再次请求服务器时，通过此字段通知服务器上次服务器返回的数据标识。
同修改过返回200，可以使用cache 返回304.

负责将**Request和Response** 关联的保存到缓存中。客户端和服务器根据一定的机制(策略CacheStrategy )，在需要的时候使用缓存的数据作为网络响应，节省了时间和宽带。
```
 //CacheInterceptor.java
 @Override
 public Response intercept(Chain chain) throws IOException {
    //如果存在缓存，则从缓存中取出，有可能为null
    Response cacheCandidate = cache != null
        ? cache.get(chain.request())
        : null;

    long now = System.currentTimeMillis();
    //获取缓存策略对象
    CacheStrategy strategy = new CacheStrategy.Factory(now, chain.request(), cacheCandidate).get();
    //策略中的请求
    Request networkRequest = strategy.networkRequest;
     //策略中的响应
    Response cacheResponse = strategy.cacheResponse;
     //缓存非空判断，
    if (cache != null) {
      cache.trackResponse(strategy);
    }
    //缓存策略不为null并且缓存响应是null
    if (cacheCandidate != null && cacheResponse == null) {
      closeQuietly(cacheCandidate.body()); // The cache candidate wasn't applicable. Close it.
    }
     //禁止使用网络(根据缓存策略)，缓存又无效，直接返回
    if (networkRequest == null && cacheResponse == null) {
      return new Response.Builder()
          .request(chain.request())
          .protocol(Protocol.HTTP_1_1)
          .code(504)
          .message("Unsatisfiable Request (only-if-cached)")
          .body(Util.EMPTY_RESPONSE)
          .sentRequestAtMillis(-1L)
          .receivedResponseAtMillis(System.currentTimeMillis())
          .build();
    }
     //缓存有效，不使用网络
    if (networkRequest == null) {
      return cacheResponse.newBuilder()
          .cacheResponse(stripBody(cacheResponse))
          .build();
    }
    //缓存无效，执行下一个拦截器
    Response networkResponse = null;
    try {
      networkResponse = chain.proceed(networkRequest);
    } finally {
      if (networkResponse == null && cacheCandidate != null) {
        closeQuietly(cacheCandidate.body());
      }
    }
     //本地有缓存，根据条件选择使用哪个响应
    if (cacheResponse != null) {
      if (networkResponse.code() == HTTP_NOT_MODIFIED) {
        Response response = cacheResponse.newBuilder()
            .headers(combine(cacheResponse.headers(), networkResponse.headers()))
            .sentRequestAtMillis(networkResponse.sentRequestAtMillis())
            .receivedResponseAtMillis(networkResponse.receivedResponseAtMillis())
            .cacheResponse(stripBody(cacheResponse))
            .networkResponse(stripBody(networkResponse))
            .build();
        networkResponse.body().close();

        cache.trackConditionalCacheHit();
        cache.update(cacheResponse, response);
        return response;
      } else {
        closeQuietly(cacheResponse.body());
      }
    }
     //使用网络响应
    Response response = networkResponse.newBuilder()
        .cacheResponse(stripBody(cacheResponse))
        .networkResponse(stripBody(networkResponse))
        .build();

    if (cache != null) {
       //缓存到本地
      if (HttpHeaders.hasBody(response) && CacheStrategy.isCacheable(response, networkRequest)) {
        CacheRequest cacheRequest = cache.put(response);
        return cacheWritingResponse(cacheRequest, response);
      }

      if (HttpMethod.invalidatesCache(networkRequest.method())) {
        try {
          cache.remove(networkRequest);
        } catch (IOException ignored) {
        }
      }
    }

    return response;
  }
```
### 大致流程
1. 如果配置缓存，则从缓存中取一次
2. 获取缓存策略
3. 根据缓存策略获取缓存
4. 没有网络并且缓存为空，直接返回
5. 没有网络，直接根据缓存的response返回
6. 执行下一个拦截器
7. 存在缓存，根据response的相应头选择缓存
8. 不存在缓存，直接使用网络 response
9. 根据缓存策略缓存到本地

### CacheStrategy类
`CacheStrategy` 根据输出的networkRequest和cacheResponse的值是否为null给出不同的策略

| networkRequest | cacheResponse | result 结果 |
|---|---|---|
| null | null | only-if-cached (表明不进行网络请求，且缓存不存在或者过期，一定会返回503错误) |
| null | non-null | 不进行网络请求，直接返回缓存，不请求网络 |
| non-null | null | 需要进行网络请求，而且缓存不存在或者过去，直接访问网络 |
| non-null | non-null | Header中包含ETag/Last-Modified标签，需要在满足条件下请求，还是需要访问网络 |

`Cachestrategy` 通过如下方式构建
```
CacheStrategy strategy = new CacheStrategy.Factory(
            now,
            chain.request(),
            cacheCandidate)
            .get();
```
```
    public Factory(long nowMillis, Request request, Response cacheResponse) {
      this.nowMillis = nowMillis;
      this.request = request;
      this.cacheResponse = cacheResponse;

      if (cacheResponse != null) {
        this.sentRequestMillis = cacheResponse.sentRequestAtMillis();
        this.receivedResponseMillis = cacheResponse.receivedResponseAtMillis();
        Headers headers = cacheResponse.headers();
        //获取cacheReposne中的header中值
        for (int i = 0, size = headers.size(); i < size; i++) {
          String fieldName = headers.name(i);
          String value = headers.value(i);
          if ("Date".equalsIgnoreCase(fieldName)) {
            servedDate = HttpDate.parse(value);
            servedDateString = value;
          } else if ("Expires".equalsIgnoreCase(fieldName)) {
            expires = HttpDate.parse(value);
          } else if ("Last-Modified".equalsIgnoreCase(fieldName)) {
            lastModified = HttpDate.parse(value);
            lastModifiedString = value;
          } else if ("ETag".equalsIgnoreCase(fieldName)) {
            etag = value;
          } else if ("Age".equalsIgnoreCase(fieldName)) {
            ageSeconds = HttpHeaders.parseSeconds(value, -1);
          }
        }
      }
    }

    public CacheStrategy get() {
      //获取当前的缓存策略
      CacheStrategy candidate = getCandidate();
     //如果是网络请求不为null并且请求里面的cacheControl是只用缓存
      if (candidate.networkRequest != null && request.cacheControl().onlyIfCached()) {
        //使用只用缓存的策略
        return new CacheStrategy(null, null);
      }
      return candidate;
    }

    private CacheStrategy getCandidate() {
      //如果没有缓存响应，返回一个没有响应的策略
      if (cacheResponse == null) {
        return new CacheStrategy(request, null);
      }
       //如果是https，丢失了握手，返回一个没有响应的策略
      if (request.isHttps() && cacheResponse.handshake() == null) {
        return new CacheStrategy(request, null);
      }

      // 响应不能被缓存
      if (!isCacheable(cacheResponse, request)) {
        return new CacheStrategy(request, null);
      }

      //获取请求头里面的CacheControl
      CacheControl requestCaching = request.cacheControl();
      //如果请求里面设置了不缓存，则不缓存
      if (requestCaching.noCache() || hasConditions(request)) {
        return new CacheStrategy(request, null);
      }
      //获取响应的年龄
      long ageMillis = cacheResponseAge();
      //获取上次响应刷新的时间
      long freshMillis = computeFreshnessLifetime();
      //如果请求里面有最大持久时间要求，则两者选择最短时间的要求
      if (requestCaching.maxAgeSeconds() != -1) {
        freshMillis = Math.min(freshMillis, SECONDS.toMillis(requestCaching.maxAgeSeconds()));
      }

      long minFreshMillis = 0;
      //如果请求里面有最小刷新时间的限制
      if (requestCaching.minFreshSeconds() != -1) {
         //用请求中的最小更新时间来更新最小时间限制
        minFreshMillis = SECONDS.toMillis(requestCaching.minFreshSeconds());
      }
      //最大验证时间
      long maxStaleMillis = 0;
      //响应缓存控制器
      CacheControl responseCaching = cacheResponse.cacheControl();
      //如果响应(服务器)那边不是必须验证并且存在最大验证秒数
      if (!responseCaching.mustRevalidate() && requestCaching.maxStaleSeconds() != -1) {
        //更新最大验证时间
        maxStaleMillis = SECONDS.toMillis(requestCaching.maxStaleSeconds());
      }
       //响应支持缓存
       //持续时间+最短刷新时间<上次刷新时间+最大验证时间 则可以缓存
      //现在时间(now)-已经过去的时间（sent）+可以存活的时间<最大存活时间(max-age)
      if (!responseCaching.noCache() && ageMillis + minFreshMillis < freshMillis + maxStaleMillis) {
        Response.Builder builder = cacheResponse.newBuilder();
        if (ageMillis + minFreshMillis >= freshMillis) {
          builder.addHeader("Warning", "110 HttpURLConnection \"Response is stale\"");
        }
        long oneDayMillis = 24 * 60 * 60 * 1000L;
        if (ageMillis > oneDayMillis && isFreshnessLifetimeHeuristic()) {
          builder.addHeader("Warning", "113 HttpURLConnection \"Heuristic expiration\"");
        }
       //缓存响应
        return new CacheStrategy(null, builder.build());
      }

      //如果想缓存request，必须要满足一定的条件
      String conditionName;
      String conditionValue;
      if (etag != null) {
        conditionName = "If-None-Match";
        conditionValue = etag;
      } else if (lastModified != null) {
        conditionName = "If-Modified-Since";
        conditionValue = lastModifiedString;
      } else if (servedDate != null) {
        conditionName = "If-Modified-Since";
        conditionValue = servedDateString;
      } else {
        //没有条件则返回一个定期的request
        return new CacheStrategy(request, null);
      }

      Headers.Builder conditionalRequestHeaders = request.headers().newBuilder();
      Internal.instance.addLenient(conditionalRequestHeaders, conditionName, conditionValue);

      Request conditionalRequest = request.newBuilder()
          .headers(conditionalRequestHeaders.build())
          .build();
      //返回有条件的缓存request策略
      return new CacheStrategy(conditionalRequest, cacheResponse);
    }
```

### Cache类
```
public final class Cache implements Closeable, Flushable {
  final InternalCache internalCache = new InternalCache() {
    @Override public @Nullable Response get(Request request) throws IOException {
      return Cache.this.get(request);
    }

    @Override public @Nullable CacheRequest put(Response response) throws IOException {
      return Cache.this.put(response);
    }

    @Override public void remove(Request request) throws IOException {
      Cache.this.remove(request);
    }

    @Override public void update(Response cached, Response network) {
      Cache.this.update(cached, network);
    }

    @Override public void trackConditionalCacheHit() {
      Cache.this.trackConditionalCacheHit();
    }

    @Override public void trackResponse(CacheStrategy cacheStrategy) {
      Cache.this.trackResponse(cacheStrategy);
    }
  };
  Cache(File directory, long maxSize, FileSystem fileSystem) {
    this.cache = DiskLruCache.create(fileSystem, directory, VERSION, ENTRY_COUNT, maxSize);
  }
}
```
```
  DiskLruCache(FileSystem fileSystem, File directory, int appVersion, int valueCount, long maxSize,
      Executor executor) {
    this.fileSystem = fileSystem;
    this.directory = directory;
    this.appVersion = appVersion;
    this.journalFile = new File(directory, JOURNAL_FILE);
    this.journalFileTmp = new File(directory, JOURNAL_FILE_TEMP);
    this.journalFileBackup = new File(directory, JOURNAL_FILE_BACKUP);
    this.valueCount = valueCount;
    this.maxSize = maxSize;
    this.executor = executor;
  }
```
### DiskLruCache 类
`Entry` 实际用于存储的缓存数据的实体类，每一个url对应一个Entry实体。同时，每个Entry对应两个文件，key.1存储的是Response的headers，key.2文件存储的是Response的body
`Snapshot ` 一个Entry对象一一对应一个Snapshot对象
`Editor` 编辑entry类的

#### 初始化
`DiskLruCache`包含三个日志文件，在执行任何成员函数之前，都需要 `initialize()` 方法先进行初始化，虽然都调用，但整个生命周期只会被执行一次。

在执行 `readJournalLine ()` 的时候我们会根据不同的头部做出不同的操作
1. 如果是CLEAN的话，对这个entry的文件长度进行更新
2. 如果是DIRTY，说明这个值正在被操作，还没有commit，于是给entry分配一个Editor。
3. 如果是READ，说明这个值被读过了，什么也不做。
journal 文件
```
libcore.io.DiskLruCache // MAGIC
1 // VERSION
100 // appVersion
2 // valueCount 每个entry的 value 数量

CLEAN 3400330d1dfc7f3f7f4b8d4d803dfcf6 832 21054
DIRTY 335c4c6028171cfddfbaae1a9c313c52
CLEAN 335c4c6028171cfddfbaae1a9c313c52 3934 2342
REMOVE 335c4c6028171cfddfbaae1a9c313c52
DIRTY 1ab96a171faeeee38496d8b330771a7a
CLEAN 1ab96a171faeeee38496d8b330771a7a 1600 234
READ 335c4c6028171cfddfbaae1a9c313c52
READ 3400330d1dfc7f3f7f4b8d4d803dfcf6
```

在执行 `rebuildJournal ()` 的时候
1. 获取一个写入流，将lruEntries集合中的Entry对象写入tmp文件中，根据Entry的currentEditor的值判断是CLEAN还是DIRTY,来决定写入该Entry的key。如果是CLEAN还需要写入文件的大小bytes。
2. 把journalFileTmp更名为journalFile
3. 将journalWriter跟文件绑定，通过它来向journalWrite写入数据，最后设置一些属性即可。

其实 rebuild 操作是以lruEntries为准，把DIRTY和CLEAN的操作都写回到journal中。其实这个操作没有改动真正的value，只不过重写了一些事务的记录。事实上，lruEntries和journal文件共同确定了cache数据的有效性。lruEntries是索引，journal是归档。

#### 小结
- 通过LinkedHashMap实现LRU替换
- 通过本地维护Cache操作日志保证Cache原子性与可用性，同时为防止日志过分膨胀定时执行日志精简。
- 每一个Cache项对应两个状态副本：DIRTY，CLEAN。CLEAN表示当前可用的Cache。外部访问到cache快照均为CLEAN状态；DIRTY为编辑状态的cache。由于更新和创新都只操作DIRTY状态的副本，实现了读和写的分离。
- 每一个url请求cache有四个文件。首先是两个状态(DIRY，CLEAN)，而每个状态又对应两个文件：一个(key.0, key.0.tmp)文件对应存储meta数据，一个(key.1, key.1.tmp)文件存储body数据。

## ConnectInterceptor
### UML图
![](https://raw.githubusercontent.com/pacoblack/BlogImages/master/okhttp/okhttp2.jpg)
主要作用是打开了与服务器的链接，正式开启了网络请求
```
public final class ConnectInterceptor implements Interceptor {
  public final OkHttpClient client;

  public ConnectInterceptor(OkHttpClient client) {
    this.client = client;
  }

  @Override public Response intercept(Chain chain) throws IOException {
    RealInterceptorChain realChain = (RealInterceptorChain) chain;
    Request request = realChain.request();
    Transmitter transmitter = realChain.transmitter();

    boolean doExtensiveHealthChecks = !request.method().equals("GET");
    Exchange exchange = transmitter.newExchange(chain, doExtensiveHealthChecks);

    return realChain.proceed(request, transmitter, exchange);
  }
}
```
之前我们在`RetryAndFollowUpInterceptor` 已经 `prepareToConnect()` 做过准备了，
然后在 `BridgeIntercepter` 中添加一些请求头和相应头，
接着在`CacheIntercepter` 看是否可以直接使用缓存，如果有缓存的话也不会走到这里，
如果没有缓存就需要 `ConnectIntercepter` 借用 `Transmitter`来桥接应用层和网络层，通过 `ExchangeFinder` 中的 `finHealthyConnection()` 从 `connectionPool` 中找到一个可用的连接，这个连接可能是复用的，并 `connect()`,从而得到 输入/输出 流 (source/sink) ，返回一个 `Exchange` 给 `CallServerIntercepter` , 通过这个 `Exchange` 就可以添加请求头和请求体，并读取响应头和响应体，来交给上面的 Intercepter，层层向上传递。

```
// ExchangeFinder.java
  private RealConnection findConnection(int connectTimeout, int readTimeout, int writeTimeout,
      int pingIntervalMillis, boolean connectionRetryEnabled) throws IOException {
    boolean foundPooledConnection = false;
    RealConnection result = null;
    Route selectedRoute = null;
    RealConnection releasedConnection;
    Socket toClose;
    synchronized (connectionPool) {
      if (transmitter.isCanceled()) throw new IOException("Canceled");
      hasStreamFailure = false; // This is a fresh attempt.

      // 尝试复用已分配 Connection
      releasedConnection = transmitter.connection;
      toClose = transmitter.connection != null && transmitter.connection.noNewExchanges
          ? transmitter.releaseConnectionNoEvents()
          : null;

      if (transmitter.connection != null) {
        // 得到了已分配的connection
        result = transmitter.connection;
        releasedConnection = null;
      }

      if (result == null) {
        // 尝试获取已回收的connection
        if (connectionPool.transmitterAcquirePooledConnection(address, transmitter, null, false)) {
          foundPooledConnection = true;
          result = transmitter.connection;
        } else if (nextRouteToTry != null) {
          selectedRoute = nextRouteToTry;
          nextRouteToTry = null;
        } else if (retryCurrentRoute()) {
          selectedRoute = transmitter.connection.route();
        }
      }
    }
    closeQuietly(toClose);

    if (releasedConnection != null) {
      eventListener.connectionReleased(call, releasedConnection);
    }
    if (foundPooledConnection) {
      eventListener.connectionAcquired(call, result);
    }
    if (result != null) {
      // 从connectionPool中找到了就返回
      return result;
    }

    // 如果需要路由选择器，就创建。这是一个阻塞操作
    boolean newRouteSelection = false;
    if (selectedRoute == null && (routeSelection == null || !routeSelection.hasNext())) {
      newRouteSelection = true;
      routeSelection = routeSelector.next();
    }

    List<Route> routes = null;
    synchronized (connectionPool) {
      if (transmitter.isCanceled()) throw new IOException("Canceled");

      if (newRouteSelection) {
        // 根据 IP addresses 集合, 再次尝试从 connectionPool中获取connection。这里与上次的区别是 routes不为空
        routes = routeSelection.getAll();
        if (connectionPool.transmitterAcquirePooledConnection(
            address, transmitter, routes, false)) {
          foundPooledConnection = true;
          result = transmitter.connection;
        }
      }

      if (!foundPooledConnection) {
        if (selectedRoute == null) {
          selectedRoute = routeSelection.next();
        }

        // 这里就创建一个 Connection并指派
        result = new RealConnection(connectionPool, selectedRoute);
        connectingConnection = result;
      }
    }

    // 得到了connection，返回
    if (foundPooledConnection) {
      eventListener.connectionAcquired(call, result);
      return result;
    }

    // 进行 TCP + TLS handshakes. 一个阻塞操作
    result.connect(connectTimeout, readTimeout, writeTimeout, pingIntervalMillis,
        connectionRetryEnabled, call, eventListener);
    connectionPool.routeDatabase.connected(result.route());

    Socket socket = null;
    synchronized (connectionPool) {
      connectingConnection = null;
      // 将 connection进行合并，只有在多个connection 复用一个 host的时候
      if (connectionPool.transmitterAcquirePooledConnection(address, transmitter, routes, true)) {
        // We lost the race! Close the connection we created and return the pooled connection.
        result.noNewExchanges = true;
        socket = result.socket();
        result = transmitter.connection;
      } else {
        connectionPool.put(result);
        transmitter.acquireConnectionNoEvents(result);
      }
    }
    closeQuietly(socket);

    eventListener.connectionAcquired(call, result);
    return result;
  }
```
以上代码主要做的事情有：
1. StreamAllocation的connection如果可以复用则复用;
2. 如果connection不能复用，则从连接池中获取RealConnection对象，获取成功则返回;
3. 如果连接池里没有，则new一个RealConnection对象;
4. 调用RealConnection的connect()方法发起请求;
5. 将RealConnection对象存进连接池中，以便下次复用;
6. 返回RealConnection对象。


### RealConnection
```
 // Connection 接口
 Route route(); //返回一个路由
 Socket socket();  //返回一个socket
 Handshake handshake();  //如果是一个https,则返回一个TLS握手协议
 Protocol protocol(); //返回一个协议类型 比如 http1.1 等或者自定义类型
```

RealConnection是Connection的实现类，代表着链接socket的链路，如果拥有了一个RealConnection就代表了我们已经跟服务器有了一条通信链路。

```
 // RealConnection 成员变量
  private final ConnectionPool connectionPool;
  private final Route route;

  //下面这些字段，通过connect()方法初始化赋值，且不会再次赋值

  private Socket rawSocket; //底层 TCP socket

  private Socket socket;  //应用层socket

  private Handshake handshake;  //握手

  private Protocol protocol;  //协议

  private Http2Connection http2Connection; // http2的链接

  // 通过source和sink，与服务器交互的输入输出流
  private BufferedSource source;
  private BufferedSink sink;

  // 下面这个字段是表示链接状态的字段，并且有connectPool统一管理

  // 如果noNewStreams被设为true，则noNewStreams一直为true，不会被改变，
  // 并且这个链接不会再创建新的stream流
  public boolean noNewStreams;

  //成功的次数
  public int successCount;

  //此链接可以承载最大并发流的限制，如果不超过限制，可以随意增加
  public int allocationLimit = 1;
```
由上面的我们可以得出一些结论：
- source和sink，以流的形式对服务器进行交互
- 除了route 字段，部分的字段都是在connect()方法里面赋值的，并且不会改变
- noNewStream 可以简单理解为该连接不可用。
- allocationLimit是分配流的数量上限，一个connection最大只能支持一个1并发

首先是`connect()` 方法
```
  public void connect(int connectTimeout, int readTimeout, int writeTimeout,
      int pingIntervalMillis, boolean connectionRetryEnabled, Call call,
      EventListener eventListener) {
    if (protocol != null) throw new IllegalStateException("already connected");
    // 创建一个 Selector 来选择 connectionSpec 也就是线路
    RouteException routeException = null;
    List<ConnectionSpec> connectionSpecs = route.address().connectionSpecs();
    ConnectionSpecSelector connectionSpecSelector = new ConnectionSpecSelector(connectionSpecs);
    ...
    // 尝试连接
    while (true) {
      try {
        // 如果要求隧道模式，建立通道连接，通常不会使用这种
        if (route.requiresTunnel()) {
          connectTunnel(connectTimeout, readTimeout, writeTimeout, call, eventListener);
          if (rawSocket == null) {
            // We were unable to connect the tunnel but properly closed down our resources.
            break;
          }
        } else {
          // socket 连接
          connectSocket(connectTimeout, readTimeout, call, eventListener);
        }
        // 建立 https 连接
        establishProtocol(connectionSpecSelector, pingIntervalMillis, call, eventListener);
        eventListener.connectEnd(call, route.socketAddress(), route.proxy(), protocol);
        break;
      } catch (IOException e) {
        ...
      }
    }
    if (route.requiresTunnel() && rawSocket == null) {
      ProtocolException exception = new ProtocolException("Too many tunnel connections attempted: "
          + MAX_TUNNEL_ATTEMPTS);
      throw new RouteException(exception);
    }

    if (http2Connection != null) {
      synchronized (connectionPool) {
        allocationLimit = http2Connection.maxConcurrentStreams();
      }
    }
  }
```
socket 连接
```
  private void connectSocket(int connectTimeout, int readTimeout, Call call,
      EventListener eventListener) throws IOException {
    Proxy proxy = route.proxy();
    Address address = route.address();
     // 根据代理类型来选择socket是代理还是直连类型
    rawSocket = proxy.type() == Proxy.Type.DIRECT || proxy.type() == Proxy.Type.HTTP
        ? address.socketFactory().createSocket()
        : new Socket(proxy);

    eventListener.connectStart(call, route.socketAddress(), proxy);
    rawSocket.setSoTimeout(readTimeout);
    try {
      // 为支持不同的平台，实际是 socket.connect(address, connectTimeout)
      Platform.get().connectSocket(rawSocket, route.socketAddress(), connectTimeout);
    } catch (ConnectException e) {
      ConnectException ce = new ConnectException("Failed to connect to " + route.socketAddress());
      ce.initCause(e);
      throw ce;
    }

    try {
      // 得到输入／输出流
      source = Okio.buffer(Okio.source(rawSocket));
      sink = Okio.buffer(Okio.sink(rawSocket));
    } catch (NullPointerException npe) {
      if (NPE_THROW_WITH_NULL.equals(npe.getMessage())) {
        throw new IOException(npe);
      }
    }
  }
```
隧道连接
```
  private void connectTunnel(int connectTimeout, int readTimeout, int writeTimeout)
      throws IOException {
    // 创建隧道请求
    Request tunnelRequest = createTunnelRequest();
    HttpUrl url = tunnelRequest.url();
    int attemptedConnections = 0;
    int maxAttempts = 21;
    while (true) {
      if (++attemptedConnections > maxAttempts) {
        throw new ProtocolException("Too many tunnel connections attempted: " + maxAttempts);
      }
      // 建立Socket连接
      connectSocket(connectTimeout, readTimeout);
      // 建立隧道
      tunnelRequest = createTunnel(readTimeout, writeTimeout, tunnelRequest, url);

      if (tunnelRequest == null) break; // Tunnel successfully created.

      closeQuietly(rawSocket);
      rawSocket = null;
      sink = null;
      source = null;
    }
  }
```
它们调用`connectSocket` 中参数 `Call` 是不一样的。

connectSocket中的代理连接建立的过程
1. **没有设置代理**的情况下，则直接与HTTP服务器建立TCP连接
2. **设置了SOCKS代理**的情况下，创建Socket时，为其传入proxy，连接时还是以HTTP服务器为目标。
3. 设置了HTTP代理时，如果是**HTTP请求**，则与HTTP代理服务器建立TCP连接。HTTP代理服务器解析HTTP请求/响应的内容，并根据其中的信息来完成数据的转发。
4. 设置了HTTP代理时，如果是 **HTTPS/HTTP2请求**，与HTTP服务器建立通过HTTP代理的隧道连接。HTTP代理不再解析传输的数据，仅仅完成数据转发的功能。此时HTTP代理的功能退化为如同SOCKS代理类似。
5. 设置了代理类时，HTTP的服务器的域名解析会交给代理服务器执行。如果是HTTP代理，会对HTTP代理的域名做域名解析。

establishProtocol 建立连接过程：
1. 建立 TLS 连接
    1. 用SSLSocketFactory基于原始的TCP Socket，创建一个SSLSocket， 配置SSLSocket。
    2. configureTlsExtensions 配置 TLS扩展
    3. 进行TLS握手
    4. 获取证书信息。
    5. 对证书进行验证。
    6. 完成HTTP/2的ALPN扩展
    7. 基于前面获取到SSLSocket创建于执行的IO的BufferedSource和BufferedSink等，并保存握手信息以及所选择的协议。
2. 如果是HTTP 2.0，通过Http2Connection.Builder 建立一个 Http2Connection，通过 http2Connection.start() 和服务器建立连接。

### ConnectionPool

管理http和http/2的链接，以减少请求的网络延迟。同一个address将共享同一个connection。实现了连接复用的功能。
```
public final class ConnectionPool {
  final RealConnectionPool delegate;
}
```
当前版本将具体的实现委托给了 `RealConnectionPool`
```
public final class RealConnectionPool {
  // 后台线程用来清理过期连接，在每一个连接池中最多又一个线程。
  // 这个 executor 允许自己被GC 清理
  private static final Executor executor = new ThreadPoolExecutor(0 /* corePoolSize */,
      Integer.MAX_VALUE /* maximumPoolSize */, 60L /* keepAliveTime */, TimeUnit.SECONDS,
      new SynchronousQueue<>(), Util.threadFactory("OkHttp ConnectionPool", true));
  // 清理任务
  private final Runnable cleanupRunnable = () -> {
    while (true) {
      long waitNanos = cleanup(System.nanoTime());
      if (waitNanos == -1) return;
      if (waitNanos > 0) {
        long waitMillis = waitNanos / 1000000L;
        waitNanos -= (waitMillis * 1000000L);
        synchronized (RealConnectionPool.this) {
          try {
            RealConnectionPool.this.wait(waitMillis, (int) waitNanos);
          } catch (InterruptedException ignored) {
          }
        }
      }
    }
  };
  // 过期连接队列
  private final Deque<RealConnection> connections = new ArrayDeque<>();
  // 路由数据库，用来记录不可用的route
  final RouteDatabase routeDatabase = new RouteDatabase();
}
```
默认情况下，这个连接池最多维持5个连接，且每个链接最多活5分钟。
从 ConnectionPool 获取Connection
```
  // RealConectionPool.java
  boolean transmitterAcquirePooledConnection(Address address, Transmitter transmitter,
      @Nullable List<Route> routes, boolean requireMultiplexed) {
    assert (Thread.holdsLock(this));
    for (RealConnection connection : connections) {
      if (requireMultiplexed && !connection.isMultiplexed()) continue;
      if (!connection.isEligible(address, routes)) continue;
      transmitter.acquireConnectionNoEvents(connection);
      return true;
    }
    return false;
  }
```
然后把这个connection 设置到 Transmitter 中去
```
 // 此方法有两处调用，一个是 findConnection，另一个是 connectionPool.transmitterAcquirePooledConnection()
 // 后一个方法也会在 findConnection处被调用
  void acquireConnectionNoEvents(RealConnection connection) {
    assert (Thread.holdsLock(connectionPool));

    if (this.connection != null) throw new IllegalStateException();
    this.connection = connection;
    connection.transmitters.add(new TransmitterReference(this, callStackTrace));
  }
```
从代码可以看出来，这个connection 必须 isMultiplexed、 isEligible, 才可以
至于添加 connection ,就是异步触发清理任务，然后将连接添加到队列中。
```
 void put(RealConnection connection) {
    assert (Thread.holdsLock(this));
    if (!cleanupRunning) {
      cleanupRunning = true;
      executor.execute(cleanupRunnable);
    }
    connections.add(connection);
  }
```
至于这个清理任务，代码就是上面的 cleanupRunnable
1. 调用`cleanup`方法
2. 等待 `connectionBecameIdle()` 触发 `notifyAll()`
而这个 `connectionBecameIdle()` 是在 `Transmitter` 的 `releaseConnectionNoEvents()` -> `maybeReleaseConnection()` -> `exchangeMessageDone()` -> `Exchange.bodyComplete` -> `complete` -> `close`
这个 close 属于 `ForwardingSource`,它的 delegate， 即为 `codec.openResponseBodySource(response)`

我们现在看一下 cleanup 做了什么
1. 统计空连接数量
2. 查找最长空闲时间的连接，以及它的空闲时长
3. 如果超过了最大连接数或者最大空闲时长，就 remove 掉这个连接
4. 否则返回一个等待时长，也就是cleanup 的返回值 waitNanos
然后阻塞相应的时间，如果有了废弃连接就清理，否则，接着等待

cleanup中还有一个方法 `pruneAndGetAllocationCount()`，它是用来追踪泄露连接的，返回还存活于 connection 的 transmitter 的数量。所谓泄漏，就是还在追踪这个connection 但是程序已经废弃掉他们了。

### Transmitter
是OkHttp的应用程序和网络层之间的桥梁。 此类公开了高级应用程序层原语：连接，请求，响应和流。
它持有okhttpclient对象以及RealCall对象。
它支持异步取消，如果是一个 HTTP/2， 取消的是这个流而不是共享的这个连接，但是如果是在进行TLS握手，就会取消整个连接。

### ExchangeFinder
它尝试去是为一些可能的变化去找到一条可用的连接，策略如下：
1. 如果当前 call 已经有了一个连接，能够满足请求，就用相同的连接，做一些初始化修改。
2. 如果连接池中的一个连接满足这个请求。
3. 如果没有现存的连接，就创建一个路由列表，并创建一个新连接。如果失败了，就迭代的尝试列表中可用的路由。


## CallServerInterceptor
主要功能就是向服务器发送请求，并最终返回Response对象供客户端使用
### 连接与请求
OkHttp 中，ConnectionSpec用于描述HTTP数据经由socket时的socket连接配置。由 OkHttpClient 管理。

还提供了ConnectionSpecSelector，用以从ConnectionSpec几个中选择与SSLSocket匹配的ConnectionSpec，并对SSLSocket做配置操作。

在RetryAndFollowUpInterceptor这个拦截器中，需要创建Address，从OkHttpClient中获取ConnectionSpec集合，交给Address配置。
接着在ConnectInterceptor 这个拦截器中，`newExchange()` -> `find()` -> `findHealthyConnection()` -> `findConnection()` -> `connect()` 的时候，ConnectionSpec集合就会从Address中取出来，用于构建连接过程。

接着往下是 `connect()` -> `establishProtocol()` -> `connectTls()` -> `configureSecureSocket()` ->`OkHttpClient.apply()` -> `supoortedSpec()` ，这就是重新构建一个兼容的 ConnectionSpec，并配置到 SSLSocket 上

### 请求头
```
  @Override public void writeRequestHeaders(Request request) throws IOException {
    String requestLine = RequestLine.get(
        request, streamAllocation.connection().route().proxy().type());
    writeRequest(request.headers(), requestLine);
  }

  public void writeRequest(Headers headers, String requestLine) throws IOException {
    if (state != STATE_IDLE) throw new IllegalStateException("state: " + state);
    sink.writeUtf8(requestLine).writeUtf8("\r\n");
    for (int i = 0, size = headers.size(); i < size; i++) {
      sink.writeUtf8(headers.name(i))
          .writeUtf8(": ")
          .writeUtf8(headers.value(i))
          .writeUtf8("\r\n");
    }
    sink.writeUtf8("\r\n");
    state = STATE_OPEN_REQUEST_BODY;
  }
```

### 请求体
```
@Override
public Sink createRequestBody(Request request, long contentLength) {
    if ("chunked".equalsIgnoreCase(request.header("Transfer-Encoding"))) {
      // Stream a request body of unknown length.
      return newChunkedSink();
    }
    ...
}
```
```
  private final class ChunkedSink implements Sink {
    private final ForwardingTimeout timeout = new ForwardingTimeout(sink.timeout());
    private boolean closed;

    ChunkedSink() {
    }

    @Override public Timeout timeout() {
      return timeout;
    }

    @Override public void write(Buffer source, long byteCount) throws IOException {
      if (closed) throw new IllegalStateException("closed");
      if (byteCount == 0) return;

      sink.writeHexadecimalUnsignedLong(byteCount);
      sink.writeUtf8("\r\n");
      sink.write(source, byteCount);
      sink.writeUtf8("\r\n");
    }

    @Override public synchronized void flush() throws IOException {
      if (closed) return; // Don't throw; this stream might have been closed on the caller's behalf.
      sink.flush();
    }

    @Override public synchronized void close() throws IOException {
      if (closed) return;
      closed = true;
      sink.writeUtf8("0\r\n\r\n");
      detachTimeout(timeout);
      state = STATE_READ_RESPONSE_HEADERS;
    }
  }
```
写完请求头和请求体会调用 `sink.flush()`

接下来是读取相应头和响应体
```
  @Override public Response.Builder readResponseHeaders(boolean expectContinue) throws IOException {
    if (state != STATE_OPEN_REQUEST_BODY && state != STATE_READ_RESPONSE_HEADERS) {
      throw new IllegalStateException("state: " + state);
    }

    try {
      StatusLine statusLine = StatusLine.parse(source.readUtf8LineStrict());

      Response.Builder responseBuilder = new Response.Builder()
          .protocol(statusLine.protocol)
          .code(statusLine.code)
          .message(statusLine.message)
          .headers(readHeaders());

      if (expectContinue && statusLine.code == HTTP_CONTINUE) {
        return null;
      }

      state = STATE_OPEN_RESPONSE_BODY;
      return responseBuilder;
    } catch (EOFException e) {
      // Provide more context if the server ends the stream before sending a response.
      IOException exception = new IOException("unexpected end of stream on " + streamAllocation);
      exception.initCause(e);
      throw exception;
    }
  }

  @Override public ResponseBody openResponseBody(Response response) throws IOException {
    Source source = getTransferStream(response);
    return new RealResponseBody(response.headers(), Okio.buffer(source));
  }
```
