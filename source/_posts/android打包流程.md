---
title: android打包流程
toc: true
date: 2020-10-14 17:14:54
tags:
- android
categories:
- android
---
我们都是到android会打包成apk文件来安装到手机上，但是这个apk是怎么样生成的
<!--more-->
#整体流程
[android配置构建 官方文档](https://developer.android.com/studio/build?hl=zh-cn)
![官方简述流程](https://upload-images.jianshu.io/upload_images/5713484-b563cb71f2a58196.png)

#相关工具
![相关工具](https://upload-images.jianshu.io/upload_images/5713484-5d2b9738bd8e60cc.png)

这里补充下apkbuilder在SDK3.0之前使用~~apkbuilder~~去打包，在SDK3.0之后就弃用了，而使用sdklib.jar打包apk。

下面各个工具在打包中的用法
![各个工具打包](https://upload-images.jianshu.io/upload_images/5713484-38b0f4f8c2b97631.png)
1. 打包资源文件，生成R.java文件 和 resources.ap_文件。处理的包括 res目录、assert目录、 AndroidManifest.xml 以及 Android.jar 文件
   首先通过aapt源码目录下的`frameworks/base/tools/aapt/Resource.cpp`文件的`buildResources()`函数，处理过程如下：
   1.1. 检查AndroidManifest.xml的合法性
   1.2. 通过 `makeFileResource()` 对res目录下的资源目录进行处理，包括资源文件名的合法性检查，向资源表table添加条目等
   1.3. 调用`compileResourceFile()`函数编译res与asserts目录下的资源并生成resource.arsc文件
   1.4. 调用`parseAndAddEntry()`函数生成R.java文件，完成资源编译
   1.5. 调用`compileXmlfile()`函数对res目录的子目录下的xml文件进行编译，这样处理过的xml文件就简单的被"加密"了
   1.6. 将所有资源与编译生成的resource.arsc文件以及"加密"过的AndroidManifest.xml打包压缩成resources.ap_文件
   >- 除了assets和res/raw资源被原封不动地打包进APK之外，其它的资源都会被编译或者处理，除了assets资源之外，其他的资源都会被赋予一个资源ID。
   >- resources.arsc是清单文件，但是resources.arsc跟R.java区别还是非常大的，R.java里面的只是id列表，并且里面的id值不重复。resources.arsc里面会对所有的资源id进行组装，在apk运行时会**根据设备的情况来采用不同的资源**。resource.arsc文件的作用就是通过一样的ID，根据不同的配置索引到最佳的资源现在UI中。
   >- R.java 是我们在写代码时候引用的res资源的id表，resources.arsc是程序在运行时候用到的资源表。R.java是给程序员读的，resources.arsc是给机器读的。

![大体过程](https://upload-images.jianshu.io/upload_images/5713484-a1ead8ce61b96ecf.png)

2. 处理aidl文件，生成相应的.java文件
3. 编译工程源码，生成相应的class文件。处理文件包括src、R.java、AIDL生成的 java 文件，库jar文件
   调用了javac编译工程的src目录下所有的java源文件，生成的class文件位于工程的bin\classess目录下
4. 转换所有的class文件，生成classes.dex文件。处理文件就是上一步生成的 .class 文件
   使用dx工具将java字节码转换为dalvik字节码、压缩常量池、消除冗余信息等。
5. 打包生成apk
   这个过程的工具在3.0之前用apkbuilder工具，但是apkbuilder内部也是引用sdklib的ApkBuilderMain，所以3.0之后直接使用了sdklib的ApkBuilderMain
![class文件 VS dex文件](https://upload-images.jianshu.io/upload_images/5713484-d54a51a9ad31b72c.png)
   1. `ApkBuilderMain` 构建了一个ApkBuilder类，然后以包含resources.arsc文件为基础生成一个apk文件，这个文件一般为ap_结尾
   2. 调用 `addSourceFolder()` 函数添加工程资源，它会调用 `processFileForResource()` 函数往apk文件中添加资源，处理内容包括res目录和asserts目录中的文件
   3. 调用 `addResourceFromJar()`函数往apk文件中写入依赖库
   4. 调用 `addNativeLibraries()` 函数添加工程libs目录下的Nativie库
   5. 调用 `sealApk()`，关闭apk文件。
6. 对apk文件进行签名
   android的应用程序需要签名才能在android设备上安装，签名apk文件有两种情况:
      1. 在调试应用程序时，也就是我们通常称为的debug模式的签名，平时开发的时候，在编译调试程序时会自己使用一个debug.keystore对apk进行签名
      2. 正式发布时对应用程序打包进行签名，这种情况下需要提供一个符合android开发文档中要求的签名文件。这种签名也是分两种： JDK中提供的jarsigner工具签名 、android源码中提供的signapk工具
7. 对签名后的apk进行对齐处理
   这一步需要使用的工具为zipalign，它的主要工作是将apk包进行对齐处理，使apk包中的所有资源文件距离文件起始偏移为4字节的整数倍，这样通过内存映射访问apk时的速度会更快，验证apk文件是否对齐过的工作由ZipAlign.cpp文件的 `verify()`函数完成，处理对齐的工作则由`process()`函数完成。

#总结
![更详细的流程](https://upload-images.jianshu.io/upload_images/5713484-5fd820650bb9317b.png)
