---
title: class与java
toc: true
date: 2022-11-09 15:08:12
tags:
- java
categories:
- java
---
现在我们看看class文件怎么转java
<!--more-->
# 修改jar与aar
1. 解压目标文件 ` unzip myLib.aar -d tempFolder`
2. 下载[http://java-decompiler.github.io/](http://java-decompiler.github.io/)定位要修改的文件 `java -jar xxx.jar`
3. 解压classes.jar `unzip classes.jar -d tempFolderClasses`
4. 建立模块，将class中代码复制粘贴，建立新的java文件，并修改重新编译，在build目录中找到目标class
5. 替换目标class, 使用下面命令重新打包jar/aar
```
// 注意后面的空格 与 .
jar cvf xxx.aar -C folder/ .
```

# class转换为java源文件
1. 首先去[http://varaneckas.com/jad/](http://varaneckas.com/jad/ ) 根据平台下载工具
2. 解压工具
3. 输入命令 `jad -o -r -s java -d targetFolder/ classFolder/`
