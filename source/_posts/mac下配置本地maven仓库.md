---
title: Mac下配置本地Maven仓库
toc: true
date: 2023-01-06 10:15:34
tags:
- android
categories:
- android
---
有时需要配置本地maven仓库
<!---more-->
# 安装
## 手动安装
(官网)[https://maven.apache.org/download.cgi]下载地址 解压到对应的目录
或者

## brew 安装
```
//下载
$ /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

//安装
$ brew install gradle
```

# 配置
1. 打开～/.bash_profile
2. 添加配置
```bash
#maven
export M2_HOME=/Users/xlh/Applications/apache-maven-3.5.3
export PATH=$M2_HOME/bin:$PATH
```
*要注意是否配置了Java环境变量，没有的需要配置下*
```bash
export JAVA_HOME=/xxx
```
3. 检查环境是否成功
```bash
$ source ~/.bash_profile
$ mvn -v
```
4. maven默认安装在 ～/.m2/repository 目录下，如果要修改仓库目录的话，需要在`{grade}/conf/settings.xml`  添加如下代码
```xml
<localRepository>/目标目录</localRepository>
```
还可以添加其他中央仓的镜像
```xml
<mirror>
  <id>mirrorId</id>
  <mirrorOf>repositoryId</mirrorOf>
  <name>Human Readable Name for this Mirror.</name>
  <url>http://my.repository.com/repo/path</url>
</mirror>
```

# 使用
## 配置
自定义本地路径
```
repositories {
    maven { url '/Users/xlh/.m2/repository' }
}
```
默认路径
```
repositories {
    mavenLocal()
}
```

## 上传
方式一：
```
apply plugin: 'maven'
uploadArchives{
    repositories.mavenDeployer{
        // 本地仓库路径
        repository(url:"file:///本地目录")
        // 唯一标识
        pom.groupId = "groupId"
        // 项目名称
        pom.artifactId = "artifactId"
        // 版本号
        pom.version = "version"
    }
}
```
```bash
gradlew  uploadArchives
```

方式二：
```
apply plugin: 'maven-publish'
publishing {
    publications {
        maven(MavenPublication) {
            artifact "aar所在目录"
            groupId "groupId"
            artifactId "artifactId"
            version "version"
        }
    }
}
```
```bash
gradlew  publishToMavenLocal
```

## 引用
```
implementation 'groupId:artifactId:version'
```
