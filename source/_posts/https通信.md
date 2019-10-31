---
title: https通信
toc: true
date: 2019-10-31 10:55:13
tags:
- https
categories:
- https
---

主要介绍https的通信过程

<!--more-->
![图示流程](https://upload-images.jianshu.io/upload_images/2829175-9385a8c5e94ad1da.png)

现在来介绍主要流程：
1. client Hello, 浏览器向服务器发起加密通信请求， 其中包括：
    - 支持的协议版本，比如TLS 1.0版。从低到高依次 SSLv2 SSLv3 TLSv1 TLSv1.1 TLSv1.2，当前基本不再使用低于 TLSv1 的版本;
    - 客户端支持的加密套件 cipher suites 列表。 每个加密套件对应前面 TLS 原理中的四个功能的组合：认证算法 Au (身份验证)、密钥交换算法 KeyExchange(密钥协商)、对称加密算法 Enc (信息加密)和信息摘要 Mac(完整性校验);
    - 一个客户端生成的随机数 random1，稍后用于生成"对话密钥"。
    - 支持的加密方法，比如RSA公钥加密。
    - 支持的压缩方法。

2. server Hello， 服务器收到请求,然后响应， 其中包括：
    - 确认使用的加密通信协议版本，比如TLS 1.0版本。如果浏览器与服务器支持的版本不一致，服务器关闭加密通信。
    - 一个服务器生成的随机数random2，稍后用于生成"对话密钥"。
    - 确认使用的加密方法，比如RSA公钥加密。
    - 服务器证书。

3. 证书认证
    >我们知道CA机构在签发证书的时候，都会使用自己的私钥对证书进行签名, 证书里的签名算法字段 sha256RSA 即表示用到的加密算法。
    CA机构使用 sha256 对证书进行摘要，然后使用 RSA 算法用私钥对摘要进行签名，而我们也知道 RSA 算法中，使用私钥签名之后，只有公钥才能进行验签。

    证书的公钥（购买的证书）会预置在操作系统，浏览器会将得到的证书，用操作系统中的公钥来对服务器证书进行验签，确定是不是是由正规结构颁发。验签之后会得到证书的摘要（sha256加密所得），然后客户端再使用sha256对证书内容进行一次摘要，如果得到的值和验签之后得到的摘要值相同，则表示证书没有被修改过。
4. 生成随机数
    验证通过之后，客户端会生成一个随机数(pre-master secret)
    > PreMaster Secret是在客户端使用RSA或者Diffie-Hellman等加密算法生成的。它将用来跟服务端和客户端在Hello阶段产生的随机数结合在一起生成 Master Secret。在客户端使用服务端的公钥对PreMaster Secret进行加密之后传送给服务端，服务端将使用私钥进行解密得到PreMaster secret。也就是说服务端和客户端都有一份相同的PreMaster secret和随机数。

    > PreMaster secret前两个字节是TLS的版本号，这是一个比较重要的用来核对握手数据的版本号，因为在Client Hello阶段，客户端会发送一份加密套件列表和当前支持的SSL/TLS的版本号给服务端，而且是使用明文传送的，如果握手的数据包被破解之后，攻击者很有可能串改数据包，选择一个安全性较低的加密套件和版本给服务端，从而对数据进行破解。所以，服务端需要对密文中解密出来对的PreMaster版本号跟之前Client Hello阶段的版本号进行对比，如果版本号变低，则说明被串改，则立即停止发送任何消息。

    > Master secret 由于服务端和客户端都有一份相同的PreMaster secret和随机数，这个随机数将作为后面产生Master secret的种子，结合PreMaster secret，客户端和服务端将计算出同样的Master secret。Master secret是一系列的hash值组成的，它将作为数据加解密相关的secret的 Key Material 的一部分。

    > master_secret = PRF(pre_master_secret,"master secret", ClientHello.random +  ServerHello.random)
![Master secret](https://www.linuxidc.com/upload/2015_07/15072110389322.png)
5. 客户端回应
    如果证书没有问题，客户端就会从服务器证书中取出服务器的公钥。然后，向服务器发送下面三项信息：
    - PreMaster Secret。该随机数用服务器公钥加密，防止被窃听
    - 编码改变通知，表示随后的信息都将用双方商定的加密方法和密钥发送
    - 客户端握手结束通知，表示客户端的握手阶段已经结束。这一项同时也是前面发送的所有内容的hash值，用来供服务器校验

![ChangeCipherSpec](https://www.linuxidc.com/upload/2016_05/16050821032069.png)
***ChangeCipherSpec***  
- ChangeCipherSpec是一个独立的协议，体现在数据包中就是一个字节的数据，用于告知服务端，客户端已经切换到之前协商好的加密套件（Cipher Suite）的状态，准备使用之前协商好的加密套件加密数据并传输了。
在ChangecipherSpec传输完毕之后，客户端会使用之前协商好的加密套件和Session Secret加密一段 Finish 的数据传送给服务端，此数据是为了在正式传输应用数据之前对刚刚握手建立起来的加解密通道进行验证。

- 服务端在接收到客户端传过来的 PreMaster 加密数据之后，使用私钥对这段加密数据进行解密，并对数据进行验证，也会使用跟客户端同样的方式生成 Session Secret，一切准备好之后，会给客户端发送一个 ChangeCipherSpec，告知客户端已经切换到协商过的加密套件状态，准备使用加密套件和 Session Secret加密数据了。之后，服务端也会使用 Session Secret 加密一段 Finish 消息发送给客户端，以验证之前通过握手建立起来的加解密通道是否成功。
根据之前的握手信息，如果客户端和服务端都能对Finish信息进行正常加解密且消息正确的被验证，则说明握手通道已经建立成功，接下来，双方可以使用上面产生的Session Secret对数据进行加密传输了。

> session secret或者说是session key。生成session Key的过程中会先用 PRF(Pseudorandom Function伪随机方法)来生成一个key_block,然后再使用key_block,生成后面使用的秘钥。

> <p align="left">key_block = PRF(SecurityParameters.master_secret,"key expansion",  SecurityParameters.server_random + SecurityParameters.client_random);</p>

我们会用 key_block 生成以下数据
- client_write_MAC_secret[SecurityParameters.hash_size] 客户端发送数据使用的摘要MAC算法
- server_write_MAC_secret[SecurityParameters.hash_size] 服务端发送数据使用摘要MAC算法
- client_write_key[SecurityParameters.key_material_length] 客户端数据加密，服务端解密
- server_write_key[SecurityParameters.key_material_length] 服务端加密，客户端解密
- client_write_IV[SecurityParameters.IV_size] 初始化向量，运用于分组对称加密
- server_write_IV[SecurityParameters.IV_size] 初始化向量，运用于分组对称加密

[具体过程请查看这里](http://www.moserware.com/2009/06/first-few-milliseconds-of-https.html)

6. 再后续的交互中就使用session Key和MAC算法的秘钥对传输的内容进行加密和解密。
    - 具体的步骤是先使用MAC秘钥对内容进行摘要，然后把摘要放在内容的后面使用sessionKey再进行加密。对于客户端发送的数据，服务器端收到之后，需要先使用client_write_key进行解密，然后使用client_write_MAC_key对数据完整性进行验证。服务器端发送的数据，客户端会使用server_write_key和server_write_MAC_key进行相同的操作。
