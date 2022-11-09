---
title: Exoplayer入门
toc: true
date: 2022-09-26 10:36:09
tags:
- android
categories:
- android
---
现在我们来学习视频播放器Exoplayer
<!--more-->
# 播放流简介
在[Exoplayer](https://github.com/google/ExoPlayer)介绍中我们看到它支持DASH、HLS和SmoothStreaming

# 初始化demo
```kotlin
private fun initPlayer(playUri: String?) {

    if (playUri == null){
        Log.d("ExoTest", "playUri is null!")
        return
    }

    /* 1.创建SimpleExoPlayer实例 */
    mPlayer = SimpleExoPlayer.Builder(this).build()

    /* 2.创建播放菜单并添加到播放器 */
    val firstLocalMediaItem = MediaItem.fromUri(playUri)
    mPlayer!!.addMediaItem(firstLocalMediaItem)

    /* 3.设置播放方式为自动播放 */
    mPlayer!!.playWhenReady = true

    /* 4.将SimpleExoPlayer实例设置到StyledPlayerView中 */
    mPlayerView!!.player = mPlayer

    /* 5，设置播放器状态为prepare */
    mPlayer!!.prepare()
}
```
# 流程分析
## Player创建和初始化
其实上面主要的流程就是三个，builder、playWhenReady、prepare
调用过程如下
![init](pic_1.png)
![struct](exo_pic_3.png)

### doSomeWork
![doSomeWork](exo_pic_4.png)
doSomeWork每次循环都会去调用具体的render类进行处理，在第一次调用的时候，会根据对应的mime type去初始化codec，在最下层的适配器中会去调用Android原生的MediaCodec接口，之后就会去不停地去生产和消耗解码后的数据了。

## play
之前doSomeWork的时候，在updatePlaybackPostions()和setPlayWhenReadInternal()之间有render()方法，现在我们来解析render方法，看数据是怎么填充进去的
![write](exo_pic_5.png)
总结：
1. drainOutputBuffer目的是按生产者-消费者模式将解码出来的数据写入到audiotrack中；
2. 第一次调用drainOutputBuffer时将会去创建audiotrack并开始尝试往里面写数据

// TODO
