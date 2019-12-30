---
title: Flutter引入笔记
toc: true
date: 2019-12-17 16:26:31
tags:
- Flutter
- 笔记
categories:
- Flutter
- 笔记
---
引入Flutter过程
<!--more-->

# 创建 Flutter Module
1. 创建模块
```
flutter create -t module my_flutter
```
2. 引入依赖
```groovy
// settings.gradle
include ':app'
//加入下面配置
setBinding(new Binding([gradle: this]))
evaluate(new File(
        settingsDir.parentFile,
        'my_flutter/.android/include_flutter.groovy'
))
```
```groovy
//build.gradle
...
dependencies {
    ...
    // 加入下面配置
    implementation project(':flutter')
}
```

# settings.gradle 设置不识别
设置完上面后会出现错误
`A problem occurred evaluating settings 'xxx'. (~/flutter_module/.android/include_flutter.groovy)`

```groovy
setBinding(new Binding([gradle: this]))
evaluate(new File(
        settingsDir,                         
        'flutter_module/.android/include_flutter.groovy'
))
```
# appProject为空
```
What went wrong:
A problem occurred configuring root project 'xxxx'.
> A problem occurred configuring project ':flutter'.
   > Failed to notify project evaluation listener.
      > assert appProject != null
               |          |
               null       false
```
这个时候要注意，请把你的主module 改名为 app

**大体过程：关闭project，修改目录，删除x.iml 文件，重新打开工程， 即可**
