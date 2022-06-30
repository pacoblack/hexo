---
title: gradle相关
toc: true
date: 2022-06-30 15:46:16
tags:
- android
categories:
- android
---
补充一些脚本
<!--more-->
# 本地替换远端
在根build.gradle配置如下代码
```
allprojects {
  configurations.all {
    resolutionStrategy.dependencySubstitution.all { DependencySubstitution dependency ->
        if (dependency.requested instanceof ModuleComponentSelector) {
            def moduleRequested = dependency.requested as ModuleComponentSelector
            def p = rootProject.allprojects.find { p ->
                (p.group == moduleRequested.group && p.name == moduleRequested.module)
            }
            if (p != null) {
                useTarget(project(p.path), "selected local project")
            }
        }
    }
  }
}
```
# 依赖替换
## 替换特定依赖
```
//在引入时配置，指定版本为我们引入的版本
implementation("io.reactivex.rxjava2:rxjava:2.1.6") {
    force = true
}
//在configuration 级别指定，直接指定版本
configurations.all {
    resolutionStrategy.force 'io.reactivex.rxjava2:rxjava:2.1.6'
}
```

## 禁止依赖传递
```
//在引入时配置，禁用该库的传递依赖项
    implementation("io.reactivex.rxjava2:rxkotlin:2.4.0") {
        transitive = false
    }
    //在configuration 级别指定，一杆子打死，谁也别想使用传递依赖
    configurations.all {
        transitive = false
    }
```
## 定义解析策略 dependencySubstitution
仍以rxjava举例，当Rxjava3的groupid与Rxjava2不同时，gradle的默认策略已经无法解决了，force也只能饮恨，唯exclude和transitive可堪一战。于是A库来了exclude，B库来个exclude，场面很混乱，这时我们就用到了`dependencySubstitution`

dependencySubstitution接收一系列替换规则，允许你通过substitute函数为项目中的依赖替换为你希望的依赖项，例如：
```
configurations.all {
    resolutionStrategy.dependencySubstitution {
        substitute module("io.reactivex.rxjava2:rxjava") with module("io.reactivex.rxjava3:rxjava:3.0.0-RC1")
    }
}
```
substitute的参数不一定是module()，针对外部依赖和内部依赖，你有两种选择：module()和project()，视具体情况自由组合。
官方文档示例：
```
// add dependency substitution rules
configurations.all {
  resolutionStrategy.dependencySubstitution {
    // Substitute project and module dependencies
    substitute module('org.gradle:api') with project(':api')
    substitute project(':util') with module('org.gradle:util:3.0')

    // Substitute one module dependency for another
    substitute module('org.gradle:api:2.0') with module('org.gradle:api:2.1')
  }
}
```

```
configurations.all {
    resolutionStrategy.dependencySubstitution.all { DependencySubstitution dependency ->
        // use local module
        if (dependency.requested instanceof ModuleComponentSelector && dependency.requested.group == "custom") {
            def targetProject = findProject(":test")
            if (targetProject != null) {
                dependency.useTarget targetProject
            }
        }
    }
}
```
## 定义替换规则 eachDependency
eachDependency允许你在gradle解析配置时为每个依赖项添加一个替换规则，DependencyResolveDetails类型的参数可以让你获取一个requested和使用useVersion()、useTarget()两个函数指定依赖版本和目标依赖。request中存放了依赖项的groupid、module name以及version，你可以通过这些值来筛选你想要替换的依赖项，再通过useVersion或useTarget指定你想要的依赖。咱们还是来看例子吧：
```
configurations.all {
    resolutionStrategy.eachDependency { DependencyResolveDetails details ->
        if (details.requested.name == 'rxjava') {
            //由于useVersion只能指定版本号，不适用于group不同的情况
            details.useTarget group: 'io.reactivex.rxjava3', name: 'rxjava', version: '3.0.0-RC1'
        }
    }
}
```
