---
title: gradle自定义task
toc: true
date: 2020-12-10 20:27:48
tags:
- android
categories:
- android
---
我们已经了解了插件和gradle执行流程，现在我们学习下自定义task
<!--more-->
以下过程没有验证过，做了解用
1. 创建module，修改build.gradle
```
apply plugin: 'java'

repositories {
	mavenCentral()
}

dependencies {
   compile gradleApi()
}

jar {
	baseName = 'testSelfTask'
	version =  '1.0'
}
```
2. 编写task SayHello.java
```java
import org.gradle.api.DefaultTask;
import org.gradle.api.tasks.Optional;
import org.gradle.api.tasks.TaskAction;

public class SayHello extends DefaultTask{

	@Optional
	private String msg;

	@TaskAction
	public void say(){
		System.out.println("say " + msg);
	}

	public String getMsg() {
		return msg;
	}

	public void setMsg(String msg) {
		this.msg = msg;
	}

}
```
3. 生成jar包 `gradle build`
4. 引入task，修改build.gradle
```
buildscript {
	repositories {
    // jar包路径
		flatDir(dir:"自定义任务jar的全路径")
	}

	dependencies {
    // jar包版本信息
		classpath ':testSelfTask:1.0'
	}
}

apply plugin: 'java'

// 使用task
task say(type: c.SayHello){
	msg "java !"
}
```
使用task `gradle say`
5. 在自定义插件中使用
```java
public class TestPlugin implements Plugin<Project> {
    @Override
    public void apply(Project project) {
        project.getTasks().create("hello", MyTest.class, new Action<MyTest>() {
            @Override
            public void execute(MyTest myTest) {
                myTest.str = "aaaaaaaaaaaaaaaa";
                myTest.say();
                myTest.str = "hello";
            }
        });
    }
}
```
运行如下命令使用`gradlew hello`
