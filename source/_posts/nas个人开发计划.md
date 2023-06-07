---
title: NAS个人开发计划
toc: true
date: 2023-05-26 10:20:44
tags:
- DIY
categories:
- 其他
---
先规划下nas 都能搭建哪些服务
<!--more-->
# 搭建

# 随时访问
## QuickConnect
1. 控制面板 > 网络 > 常规，勾选手动配置DNS服务器，并更改 首选的 DNS 为 223.5.5.5 或者是  180.76.76.76，并保存。（为了排除dns故障导致的无法访问）。
2. 控制面板 > 网络 > 网络界面 > 编辑 > IPv4，关闭“手动设置 MTU 值”选项，并保存。（排除 MTU 值导致的网络数据传输问题）。
3. 控制面板 > 网络 > 网络界面 > 编辑 > IPv6，关闭 IPv6，并保存。（排除 IPv6 导致的网络问题）。
4. 控制面板 > 区域选项，选择“与 NTP 服务器同步”，服务器地址选择  pool.ntp.org，并保存。（排除 DSM 系统时间故障导致的访问异常）。

这个方法会出现传输速度慢，偶尔不稳定的情况。

## 公网IP
1. 申请一个公网IP（联系营业厅即可）
2. 在群晖系统中设置 DDNS。点击新增，服务供应商可以选择群晖（Synology），起个主机名字就可以了
3. 路由器配置，设置端口转发。群晖系统可以点击自动配置路由器。

## 花生壳
[https://service.oray.com/question/4615.html]()
按照官方教程即可

## DDNSTO
1. 安装docker
2. 搜索 linkease/ddnsto
3. 官网[https://www.ddnsto.com]()注册账号
4. 回到docker，将令牌配置到 TOKEN中去
5. 在DDNSTO中查看设备是否已同步到控制台
6. 添加域名和地址映射，最多5个
7. 七天试用，1年套餐26元

## Cloudflare
1. 首先是注册一个CloudFlare账号 [https://www.cloudflare-cn.com/]()
2. 阿里云注册一个域名[https://www.alibabacloud.com/zh/domain]()，注册成功后
3. 添加站点，输入刚注册的域名，一路确认，直到出现两个 CloudFlare nameserver
4. 回到阿里云搜索域名控制台，选择我们的`域名`-`DNS管理`-`DNS修改`-`修改DNS服务器`，将两个nameserver添加进去，点击确定
5. 回到cloudFlare，点击完成，后面一路点击完成
6. cloudFlare中选择 `Zero Trust`-`Access`-`Tunnels`-`Create a tunel`,选择免费计划，给tunel命名，保存
7. 复制tunel右侧的ID，选择 `configure` -`Docker` ，复制这个Token
8. `Public Hostname Page`， `Subdomain` 填写“www”，`Domain` 填写 “之前注册的域名”，`Service` 选择 “HTTP”，ip和端口号
9. 进入nas，打开Docker，搜索 cloudflare/cloudflared，并下载
10. 装载路径 配置 `/etc/cloudflared`
11. 修改网络为`host`
12. 命令在自定义处添加` 'tunnel' '--config' '/etc/cloudflared/config.yaml' '--no-autoupdate' 'run' '--token' '刚刚Docker中复制的Token'`
13. 如果想穿透多个端口，，打开`Cloudflare Zero Trust` - `Access-Tunels`，再创建一遍即可

## Zerotier Moon
1. 注册账号[https://www.zerotier.com]()
2. Network 中创建【Network ID】，内部选择【private】则连接的时候需要确认，【public】则不需要
3. 安装客户端,配置 【Network ID】即可
在 **基本设置** 中选择zerotier创建的接口
**防火墙**中选择zerotier的lan口
**自定义规则**中配置如下
勾选 **Allow Ethernet Bridging**
在**Managed Routes**中配置**Destination**为内网ip,**Via**为zerotier分配给路由系统的虚拟ip
```shell
# zt7nnmu3yd换成自己系统分配的接口名字
iptables -I FORWARD -i zt7nnmu3yd -j ACCEPT
iptables -I FORWARD -o zt7nnmu3yd -j ACCEPT
iptables -t nat -I POSTROUTING -o zt7nnmu3yd -j MASQUERADE
```
4. 返回网页端，勾选允许接入网络，【Do not Auto-Assign IPs】勾选会使用设置ip，否则会自动分配 IP

### 自建方案
由于zerotier官方服务器主要是在国外，在国内高峰时期经常会出现连接不上官方服务器的情况。
因此需要在国内服务器搭建一个moon服务器
Zerotier 定义了几个专业名词：
>PLANET 行星服务器，Zerotier 各地的根服务器，有日本、新加坡等地
moon 卫星级服务器，用户自建的私有根服务器，起到中转加速的作用
LEAF 相当于各个枝叶，就是每台连接到该网络的机器节点。

1. 购买阿里云服务器，抢占式，centOS
2. 配置

```bash
#1. 搭建
curl -s https://install.zerotier.com | sudo bash

//systemctl enable zerotier-one //配置为开机启动

#2. 搭建的moon服务器加入到创建的网络中
zerotier-cli join <network-id>

#3. 生成moon.json 模版
cd /var/lib/zerotier-one
zerotier-idtool initmoon identity.public > moon.json

#4.修改json文件
sudo vi /var/lib/zerotier-one/moon.json
#通过vim修改下面选项的内容并保存
"stableEndpoints": [ "你的公网IP地址/端口(9993)" ]
#切记饿进入阿里云后台开启9993端口，协议类型为udp

#5. 生成签名文件 xxx.moon
zerotier-idtool genmoon moon.json

#6. 建立 /var/lib/zerotier-one/moons.d 文件夹，将 xxx.moon 文件拷贝进去
```
3. 重启 zerotier.
4. openWrt连接moon服务器,修改配置文件
```bash
vim /etc/config/zerotier

# /etc/config/zerotier
option enabled '1'
option config_path '/etc/zerotier'
list join 'your Network ID'
option nat '1'
```
在/etc中创建zerotier文件夹，将moons.d文件夹复制到/etc/zerotier下，重启zerotier服务 `/etc/init.d/zerotier restart`
执行命令`zerotier-cli listpeers | grep MOON`，如果有自己服务器公网ip显示表示配置成功

### 客户机连接到moon节点
1. `zerotier-cli orbit <id> <id>`  id就是000000xxxx.moon，两个id是一样的
2. 需要在 /var/lib/zerotier-one 目录下新建 moons.d 文件夹和 moon 节点一样，将 000000xxxx.moon 文件放到其中，并重启 zerotier。

## FRP
frp就是一个反向代理软件，它体积轻量但功能很强大，可以使处于内网或防火墙后的设备对外界提供服务，它支持HTTP、TCP、UDP等众多协议。我们今天仅讨论TCP和UDP相关的内容。
1. 搭建
```shell
wget https://github.com/fatedier/frp/releases/download/v0.22.0/frp_0.22.0_linux_amd64.tar.gz
tar -zxvf frp_0.22.0_linux_amd64.tar.gz

# 文件夹改个名，方便使用
cp -r frp_0.22.0_linux_amd64 frp
cd frp

rm frpc | rm frpc.ini
vim frps.ini

./frps -c frps.ini
nohup .frps -c frps.ini & #至后台运行
```
frps.ini 文件说明
>**如果没有必要，端口均可使用默认值，token、user和password项请自行设置。**
“bind_port”表示用于客户端和服务端连接的端口，这个端口号我们之后在配置客户端的时候要用到。
“dashboard_port”是服务端仪表板的端口，若使用7500端口，在配置完成服务启动后可以通过浏览器访问 x.x.x.x:7500 （其中x.x.x.x为VPS的IP）查看frp服务运行信息。
“token”是用于客户端和服务端连接的口令，请自行设置并记录，稍后会用到。
“dashboard_user”和“dashboard_pwd”表示打开仪表板页面登录的用户名和密码，自行设置即可。
“vhost_http_port”和“vhost_https_port”用于反向代理HTTP主机时使用，本文不涉及HTTP协议，因而照抄或者删除这两条均可。

2. 客户端修改frpc.ini 修改其中的server_addr、server_port、token

## TailScale
tailscale的一个重要的功能是可以借助局域网中安装了tailscale客户端的机器做为网关，并添加子网路由，来实现直接在外通过内网原生IP实现远程访问，也就是说，这个内网地址除了可以在局域网中连接外，在局域网外也能无缝连接，也可以让不能安装tailscale的机器实现远程访问，非常好用。
1. 官网注册账号[https://tailscale.com/]()
2. 设备中安装客户端
3. 在客户端中登录账号
4. 在官网中找到【Machines】,将自己常用的设备设置为【disable key expiry】,即不过期
5. 记住这台机器的ip，以及端口号，通过浏览器输入 ip：端口号，即可访问
6. 如果机器中部署了其他服务，修改端口号即可
7. 访问路由器，即设置反向代理服务器，如目的地址为路由器地址 http://192.168.2.1, 来源就是机器的端口号如 http://*:5088, 必须保证这个端口不被占用

### 子路由设置
1. 打开 终端机-启动SSH功能
2. 使用命令 `sudo tailscale up --advertise-routes 192.168.1.0/24 --advertise-xit-node --reset`
3. 回到 官网-machines， 找到这台机器 【Edit route settings】，enable 即可

### 优化
1. 开启IPv6
2. 关闭 IPv6Spi

### 搭建
1. 首先我们需要准备一台服务器
2. [https://github.com/juanfont/headscale/releases]()寻找最新的版本
```shell
# 下载
wget https://github.com/juanfont/headscale/releases/download/v0.16.4/headscale_0.16.4_linux_amd64 -O /usr/local/bin/headscale

# 增加可执行权限
chmod +x /usr/local/bin/headscale

# 配置目录
mkdir -p /etc/headscale

# 创建用户
useradd \
	--create-home \
	--home-dir /var/lib/headscale/ \
	--system \
	--user-group \
	--shell /usr/sbin/nologin \
	headscale

# 创建文件 /lib/systemd/system/headscale.service
[Unit]
Description=headscale controller
After=syslog.target
After=network.target

[Service]
Type=simple
User=headscale
Group=headscale
ExecStart=/usr/local/bin/headscale serve
Restart=always
RestartSec=5

# Optional security enhancements
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/headscale /var/run/headscale
AmbientCapabilities=CAP_NET_BIND_SERVICE
RuntimeDirectory=headscale

[Install]
WantedBy=multi-user.target

# 在 /etc/headscale/config.yaml 中配置 Headscale 的启动配置
---
# Headscale 服务器的访问地址
#
# 这个地址是告诉客户端需要访问的地址, 即使你需要在跑在
# 负载均衡器之后这个地址也必须写成负载均衡器的访问地址
server_url: https://your.domain.com

# Headscale 实际监听的地址
listen_addr: 0.0.0.0:8080

# 监控地址
metrics_listen_addr: 127.0.0.1:9090

# grpc 监听地址
grpc_listen_addr: 0.0.0.0:50443

# 是否允许不安全的 grpc 连接(非 TLS)
grpc_allow_insecure: false

# 客户端分配的内网网段
ip_prefixes:
  - fd7a:115c:a1e0::/48
  - 100.64.0.0/10

# 中继服务器相关配置
derp:
  server:
    # 关闭内嵌的 derper 中继服务(可能不安全, 还没去看代码)
    enabled: false

  # 下发给客户端的中继服务器列表(默认走官方的中继节点)
  urls:
    - https://controlplane.tailscale.com/derpmap/default

  # 可以在本地通过 yaml 配置定义自己的中继接待你
  paths: []

# SQLite config
db_type: sqlite3
db_path: /var/lib/headscale/db.sqlite

# 使用自动签发证书是的域名
tls_letsencrypt_hostname: ""

# 使用自定义证书时的证书路径
tls_cert_path: ""
tls_key_path: ""

# 是否让客户端使用随机端口, 默认使用 41641/UDP
randomize_client_port: false
```
3. 证书及反向代理
可能很多人和我一样, 希望使用 ACME 自动证书, 又不想占用 80/443 端口, 又想通过负载均衡器负载, 配置又看的一头雾水; 所以这里详细说明一下 Headscale 证书相关配置和工作逻辑:

>1、Headscale 的 ACME 只支持 HTTP/TLS 挑战, 所以使用后必定占用 80/443
2、当配置了 tls_letsencrypt_hostname 时一定会进行 ACME 申请
3、在不配置 tls_letsencrypt_hostname 时如果配置了 tls_cert_path 则使用自定义证书
4、两者都不配置则不使用任何证书, 服务端监听 HTTP 请求
5、三种情况下(ACME 证书、自定义证书、无证书)主服务都只监听 listen_addr 地址, 与 server_url 没半毛钱关系
6、只有在有证书(ACME 证书或自定义证书)的情况下或者手动开启了 grpc_allow_insecure 才会监听 grpc 远程调用服务

综上所述, 如果你想通过 Nginx、Caddy 反向代理 Headscale, 则你需要满足以下配置:
>1、删除掉 tls_letsencrypt_hostname 或留空, 防止 ACME 启动
2、删除掉 tls_cert_path 或留空, 防止加载自定义证书
3、server_url 填写 Nginx 或 Caddy 被访问的 HTTPS 地址
4、在你的 Nginx 或 Caddy 中反向代理填写 listen_addr 的 HTTP 地址
Nginx 配置参考 官方 Wiki, Caddy 只需要一行 reverse_proxy headscale:8080 即可(地址自行替换).

至于 ACME 证书你可以通过使用 acme.sh 自动配置 Nginx 或者使用 Caddy 自动申请等方式, 这些已经与 Headscale 无关了, 不在本文探讨范围内.

4. 内网地址分配
请尽量不要将 ip_prefixes 配置为默认的 100.64.0.0/10 网段, 如果你有兴趣查询了该地址段, 那么你应该明白它叫 CGNAT; 很不幸的是例如 Aliyun 底层的 apt 源等都在这个范围内, 可能会有一些奇怪问题.

5. `systemctl enable headscale --now` 开机自启动 并 立即启动
其他的请参考连接 [https://www.hi-linux.com/posts/33684.html]()

# 照片与文件自动备份
软件 Synology Photos
软件 Cloud Sync

# 个人影音
搭建 Jellyfin
1. 创建账户
2. 添加影音路径
3. 配置【刮削器】，影音使用插件TMDb，动漫使用插件Bangumi，书籍使用插件 Bookshelf，同步使用InfuseSync， 或者使用kodi播放器就需要插件 【Kodi Sync Queue】

## 插件安装
控制台-插件-目录，找到对应的插件即可

# 磁性链接
软件使用 Download Station

# 直播与在线语音
Docker 中搜索 nibrev/ant-media-server 或者 bytelang/kplayer
[https://post.smzdm.com/p/apv56l97/]()
[https://juejin.cn/post/7206226905309446202]()

## RTMPServer在线直播
### 安装
1. 在Apps搜索“RTMP”，找到“RTMPServer”，点击下载
2. 进入容器模版设置 RTMPServer，设置ip地址，点击应用
3. 电脑端设置OBS推流（就是电脑获取手机直播内容，然后推给服务器）
4. 手机端设置服务器地址

## Rocket.Chat
官方地址：[https://github.com/RocketChat/Rocket.Chat]()

### 创建MongoDB
1. 搜索“Mongo”，下载并安装，如果需要指令集AVX，修改版本为4.4
2. 创建db
```shell
mkdir -p /mnt/user/appdata/mongodb

cd /mnt/user/appdata/mongodb

nano mongod.conf
```
3. mongod.conf 内容如下
```shell
# mongod.conf

# for documentation of all options, see:
#   http://docs.mongodb.org/manual/reference/configuration-options/

# Where and how to store data.
storage:
  dbPath: /data/db
  journal:
    enabled: true
#  engine:
#  mmapv1:
#  wiredTiger:

# network interfaces
net:
  port: 27017
  bindIp: 127.0.0.1

# how the process runs
processManagement:
  timeZoneInfo: /usr/share/zoneinfo

#security:
#  authorization: "enabled"

#operationProfiling:

replication:
  replSetName: "rs01"

#sharding:

## Enterprise-Only Options:

#auditLog:

#snmp:
```
4. 运行MongoDB的Docker容器
```shell
docker run \
-itd \
-e PGID=1000 \
-e PUID=1000 \
--name='MongoDB' \
--net='br0' \
--ip=192.168.2.3 \  #改成自己的内网IP 固定MongoDB的IP地址
-e TZ="Asia/Shanghai" \
-p '27017:27017/tcp' \
-v '/mnt/user/appdata/mongodb/':'/data/db':'rw' \
--hostname mongodatabase 'mongo' \
-f /data/db/mongod.conf
```
5. 创建MongoDB数据库 `docker exec -it MongoDB bash`
6. 进入MongoDB容器
```shell
mongo
rs.initiate()

use admin
db.createUser({user: "root",pwd: "rocketchat",roles: [{ role: "root", db: "admin"}]})
db.createUser({user: "rocketchat",pwd: "rocketchat",roles: [{role: "readWrite", db: "local" }]})
use rocketchat
db.createUser({user: "rocketchat",pwd: "rocketchat",roles: [{ role: "dbOwner",db: "rocketchat" }]})
```
7. 输入`docker stop MongoDB` 停止容器运行
8. 回到 `/mnt/user/appdata/mongodb`文件夹下
9. 输入`nano mongod.conf`找到
```
#security:
#   authorization: "enabled"
```
删除这两行开头的#
10. 输入docker start MongoDB 运行容器

### 安装
1. 安装docker和 docker-compose
2. 安装软件
```shell
# 创建并进入工作目录
mkdir /opt/rocketchat
cd /opt/rocketchat
# 下载编排文件
curl -L https://raw.githubusercontent.com/RocketChat/Rocket.Chat/develop/docker-compose.yml -o docker-compose.yml
```
3. 启动服务 `docker-compose up -d`
4. 运行Rocket.Chat容。下面的命令部署镜像，如果下载较慢或超时可以多试几次。
```shell
docker run \
-itd \
-e PGID=1000 \
-e PUID=1000 \
--name='Rocket.Chat' \
--net='br0' \
--ip=192.168.2.4 \ #改为自己的内网IP
-e TZ="Asia/Shanghai" \
-e 'MONGO_URL'='mongodb://rocketchat:rocketchat@192.168.2.3:27017/rocketchat' \ #改为自己的MongoDB的IP地址
-e 'ROOT_URL'='http://192.168.2.5' \ #改为自己的内网IP
-e 'MONGO_OPLOG_URL'='mongodb://rocketchat:rocketchat@192.168.2.3:27017/local?authSource=admin' \  #改为自己的MongoDB的IP地址
-p '3000:3000/tcp' \
-v '/mnt/user/appdata/rocketchat':'/app/uploads':'rw' 'library/rocket.chat'
```
5. 输入`docker logs -f Rocket.Chat` 查看容器运行情况，如果为“SERVER RUNNING”，表示成功
6. 浏览器输入IP:3000就可以进入后台配置

### 账号配置
1. 配置管理员信息，直至注册服务器完成
2. 在登录页面注册普通用户信息
3. 注册用户还可以创建 私聊、讨论组、频道、团队

# 软路由

# 旁路由
## Docker方案
1. 安装docker，在商店安装
2. 开启ssh，`终端机和SNMP`-`开启SSH功能`
3. 安装openwrt
    - windows 端下载SSH工具，`Hosts`-`New Host`
		- 配置需要连接的nas的 Label Address Port Username password
		- 通过ssh查看nas对应的网卡 `ifconfig`
		- `sudo -i`开始管理员模式
		- `ip link set etch0 promisc on` 开启混杂模式
		- `docker network create -d macvlan --subnet=192.168.1.0/24 --gateway 192.168.1.1 -o parent=eth0 mac-net` 注意“192.168.1.1”为主路由地址，“eth0”为网卡， “192.168.1.0/24”为路由器的子网地址
		- 上面执行完就可以在`docker`-`网络` 下看到对应的设置
		- `docker pull esirpg/buddha:latst` 拉去openWrt容器
		- `docker run -d --restart always --name esirpg-buddha --privileged --network mac-net --ip=192.168.1.13 esirpg/buddha:latest  /sbin/init`,启动容器，其中“192.168.1.13” 为旁路由ip，需要保证这个ip没有被占用
		- `bash docker exec -it esirpg-buddha ash` 进入容器
		- `bash vi /etc/config/network` 修改网络设置，将 config interface ‘lan’ 下面的 option ipaddr 修改为上面的 “192.168.1.13”
		- `bash /etc/init.d/network restart` 重启网络配置，使配置生效，`bash exit`
### 配置openwrt
此时，浏览器打开“192.168.1.13” 进入openwrt登录页，账号 “root”，没有密码，进入后会提示修改密码
- `网络`-`接口`,修改LAN口 `IpV4地址`修改为`192.168.1.13`,也就是openWrt的地址， `IPV4网关`和`自定义DNS服务`修改为主路由地址
- 勾选最下面的`忽略此接口`，保存&退出。
- `网络`-`防火墙`，`入站数据` `出站数据` `转发`包括 区域中的全部选择`接受`，Lan的`MSS钳制`不勾选，其余全部勾选,保存&退出
### 配置clash
- 下载[clash](https://github.com/Dreamacro/clash/releases),选择linux amd64，解压并改名为 clash
- `服务`-`clash`-`更新`，上传并安装
- 在`配置`- `导入配置`中配置服务即可
- 保存应用 ，启动配置

这个方案相对于 VM 安装简单，但坑的地方在于，不支持 udp 转发，在某些模式上甚至连不了网。推测是这些功能依赖于 kmod ，虽然在容器中安装了，但实际上用的还是 host kernel ，而 host 并未安装。一种可行的方法是给群晖的 kernel 编个 kmod ，但需要安装群晖一堆的构建套件，以前为了编 Wireguard 试过一次，非常痛苦，建议不要折腾。

## VM方案
vm 方案的缺点在于，guest 存在虚拟化开销，并且由于群晖对虚拟机的支持非常有限（没 vt-d），网卡只能通过 virtio 或者模拟设备的方式给 vm 用。但鉴于 docker 方案不支持 UDP，只能将就用了。类似于 docker 方案，起一个 openwrt vm，装 openclash 。
1. 下载 openwrt image https://downloads.openwrt.org/releases/19.07.7/targets/x86/64/combined-squashfs.img.gz
2. 群晖在 Virtual Machine Manage - 映像 - 硬盘映像 导入该镜像，并在 虚拟机 - 导入 - 从硬盘映像导入 ，给个 1C1G ，硬盘选择刚刚导入的镜像，网络选择默认的即可
3. 启动虚拟机，通过 虚拟机 - 连接拿到 shell ，同样修改 /etc/config/network 配置，手动指定 ip 和 dns 并重新加载配置。这时候 ping 测试会发现虽然能解析到 ip 但连接不上。这是因为缺少一条路由指令，建议加入到 /etc/config/network 持久化：
```
config route 'external'
    option interface 'lan'
    option target '0.0.0.0'
    option netmask '0.0.0.0'
    option gateway '192.168.10.1'
```
重新加载配置即可

同 docker 方案，安装 openclash

## 接入
在需要科学上网的设备上，手动指定 ip ，并将网关和 dns 指定为旁路由的 ip ，我这里为 192.168.10.2 ，即可让旁路由接管流量。
