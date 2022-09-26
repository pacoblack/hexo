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
其实上面主要的流程就是三个，builder、playWhenReady、prepare
