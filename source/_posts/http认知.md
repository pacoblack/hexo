---
title: http认知
toc: true
date: 2022-06-28 10:31:06
tags: 
    - android
categories:
    - android
---
http协议目前已更新到3.0
<!--more-->

# RTT
RTT是Round Trip Time的缩写，通俗地说，就是通信一来一回的时间。

## TCP的RTT
TCP需要三次握手，建立TCP的虚拟通道，那么这三次握手需要几个RTT时间？
去 （SYN）     ---->
回 （SYN+ACK） <----
去 （ACK）     ---->
一个半来回，故TCP连接的时间 = 1.5 RTT 。

## HTTP的RTT
用户在浏览器输入URL，1.5个RTT之后，TCP开始传输HTTP Request，浏览器收到服务器的 Response，又花费了1 RTT
HTTP的同心时间 = TCP握手时间 + HTTP交易时间 = 1.5RTT + 1 RTT = 2.5 RTT

## SSL 与 TLS
为了保证数据安全，发明了SSL（Secure Socket Layer），位于TCP和HTTP之间，负责HTT的安全加密
但是最初的SSL只能加密HTTP，为了能更大范围的使用，在协议中增加了 Application Protocol 字段
在SSL 3.0版本上，添加了这个协议，更名为TLS 报文格式如下：
IP/TCP/TLS/[HTTP]

当前浏览器支持的TLS版本为 1.0 1.1 1.2
通常将TLS保护的HTTP通信，称为HTTPS


## TLS 1.2的RTT
1. 客户端发送 Client Hello ---- ‘我支持1.2版本，加密套件列表1、2、3…，以及我的随机码N1，请出示您的证件。’
2. 服务端回复 Server Hello ---- ‘那就1.2版本通信吧，加密套件我选用1，我的随机码N2，ECDHE密钥交换素材2，这是我的证件。’
3. 客户端发送 Key Exchange ---- ‘验证首长的证件是否伪造的；生成密钥交换素材1；回复我的ECDHE密钥交换素材1，接下来我发给您的消息都要加密了’
花费时间总和= TCP链接建立时间+ TLS建立时间 +HTTP交易时间 = 1.5 RTT + 1.5RTT + 1RTT = 4 RTT

# HTTP 1.x
客户端从服务端获取页面，页面中包含很多资源链接，浏览器去加载链接资源的时候，需要重新建立 TCP、TLS、HTTP
完整的页面加载时间 = 4RTT + 4RTT = 8RTT

# HTTP 2.0
如果第一个页面和第二个页面是同一个服务器，为什么要重新建立 TCP、TLS链接呢，我们可以进行优化
用户多个HTTP请求，使用同一个通道进行传输，可以减少很多时间
但是副作用是，多个HTTP使用一个TCP连接，需要遵守流量状态控制，如果某个HTTP遇到阻塞，那么后面的HTTP就会无法发送，这就是头部阻塞
## QUIC(Quick UDP Internet Connection)
报文格式：*IP/UDP/QUIC*
Google开发了QUIC协议，它集成了TCP可靠传输机制、TLS安全机制、HTTP2.0 流量复用机制，其页面加载时间是2.5RTT

### 升级困难
QUIC 的实现在传输层换了协议，从 TCP 换到了 UDP，这个变化可不是说升级就升级的。
一个官方的例子：NAT 网关。NAT 网关对 TCP 的映射是根据 source_ip:port 和 destination_ip:port 来做的，经过 NAT 网关的 TCP 流量都通过这个四元组做识别，监听 SYN 和 ACK 可以确定 TCP 链接是否建立是否断开；而 NAT 网关对 UDP 流量的处理却没有这么可靠，对于 UDP 流量，NAT 的端口映射可能在某次传输超时之后就被重新分配了，这本来对 UDP 的不可靠的流量也不那么严重，但 QUIC 基于这种实际情况下做，某个建立好要复用的链接，对 NAT 内部机器来说流量来源的端口是会发生变化的，从而四元组做链接标识的事情就 GG 了。如下图：
![nat](quic_nat.jpeg)
为了解决上面的问题，QUIC 使用一个通用的 QUIC Connection ID 来解决这个问题，绕过四元组。

# HTTP3.0
IETF希望QUIC不仅可以传输HTTP，也可以传输其他协议，把QUIC和HTTP分离
报文格式： *IP /UDP/QUIC/HTTP*
整体的页面加载时间是 2RTT

## TLS 1.3
建立TLS连接不再需要1.5 RTT，而只需要1 RTT，是因为浏览器第一次就把自己的密钥交换的素材发给服务器，这样就节省了第三次消息，少了0.5个RTT时间。
页面的整体加载时间 = TLS 1.3连接时间 + HTTP交易时间 = 1RTT + 1RTT = 2 RTT
重连页面的加载时间 = HTTP交易时间 = 1 RTT

# 小结
HTTP/2 虽然具有多个流并发传输的能力，但是传输层是 TCP 协议，于是存在以下缺陷：
- *队头阻塞*，HTTP/2 多个请求跑在一个 TCP 连接中，如果序列号较低的 TCP 段在网络传输中丢失了，即使序列号较高的 TCP 段已经被接收了，应用层也无法从内核中读取到这部分数据，从 HTTP 视角看，就是多个请求被阻塞了；
- *TCP 和 TLS 握手时延*，TCL 三次握手和 TLS 四次握手，共有 3-RTT 的时延；
- *连接迁移需要重新连接*，移动设备从 4G 网络环境切换到 WIFI 时，由于 TCP 是基于四元组来确认一条 TCP 连接的，那么网络环境变化后，就会导致 IP 地址或端口变化，于是 TCP 只能断开连接，然后再重新建立连接，切换网络环境的成本高；


# 附图
![连接demo](quic_vs_tcp.webp)
![比较报文](http2_vs_http3.jpeg)
