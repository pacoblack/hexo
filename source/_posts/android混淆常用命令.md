---
title: android混淆常用命令
toc: true
date: 2020-09-03 11:50:08
tags:
- android
- 混淆
categories:
- android
- 混淆
---
混淆器的作用不仅仅是保护代码，它也有精简编译后程序大小的作用。
<!--more-->
# 混淆的配置
```groovy
android{
  buildTypes{
    release {
       // 是否进行混淆  
       minifyEnabled true  
       // 混淆文件的位置，其中'proguard-android.txt'为sdk默认的混淆配置，
       //'proguard-rules.pro' 是该模块下的混淆配置
       // sdk/tool/proguard/目录下
       proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'  
    }
  }
}
```
# 混淆的步骤
![步骤](https://blog.si-yee.com/2019/04/12/Android%E6%B7%B7%E6%B7%86-Proguard-%E8%AF%A6%E8%A7%A3/proguard.png)
1. 压缩（shrink）
  移除未使用的类、方法、字段等；
2. 优化（optimize）
  优化字节码、简化代码等操作；
3. 混淆（obfuscate）
  使用简短的、无意义的名称重全名类名、方法名、字段等；
4. 预校验（preverify）
  为class添加预校验信息。

# 混淆的常用命令
## 基本指令
```groovy
-dontshrink
# 声明不进行压缩操作，默认情况下，除了-keep配置（下详）的类及其直接或间接引用到的类，都会被移除。

#---------------------------------------------- shrink

-dontoptimize
# 不对class进行优化，默认开启优化。
# 注意：由于优化会进行类合并、内联等多种优化，-applymapping可能无法完全应用，需使用热修复的应用，建议使用此# 配置关闭优化。

-optimizationpasses n
# 执行优化的次数，默认1次，多次能达到更好的优化效果。

-optimizations optimization_filter
#优化配置，可进行字段优化、内联、类合并、代码简化、算法指令精简等操作。

#只进行 移除未使用的局部变量、算法指令精简
-optimizations code/removal/variable,code/simplification/arithmetic

#进行除 算法指令精简、字段、类合并外的所有优化
-optimizations !code/simplification/arithmetic,!field/*,!class/merging/*

#---------------------------------------------- optimize

-dontobfuscate
# 不进行混淆，默认开启混淆。除-keep指定的类及成员外，都会被替换成简短、随机的名称，以达到混淆的目的。

-applymapping filename
# 根据指定的mapping映射文件进行混淆。

-obfuscationdictionary filename
# 指定字段、方法名的混淆字典，默认情况下使用abc等字母组合，比如根据自己的喜好指定中文、特殊字符进行混淆命名。

-classobfuscationdictionary filename
# 指定类名混淆字典。

-packageobfuscationdictionary filename
# 指定包名混淆字典。

-useuniqueclassmembernames
# 指定相同的混淆名称对应不同类的相同成员，不同的混淆名称对应不同的类成员。在没有指定这个选项时，不同类的不同方法都可能映射到a,b,c。

# 有一种情况，比如两个不同的接口，拥有相同的方法签名，在没有指定这个选项时，这两个接口的方法可能混淆成不同的名称。但如果新增一个类同时实现这两个接口，并且利用-applymapping指定之前的mapping映射文件时，这两个接口的方法必须混淆成相同的名称，这时就和之前的mapping冲突了。

# 在某此热修复场景下需要指定此选项。

-dontusemixedcaseclassnames
# 指定不使用大小写混用的类名，默认情况下混淆后的类名可能同时包含大写小字母。这在某些对大小写不敏感的系统（如windowns）上解压时，可能存在文件被相互覆盖的情况。

-keeppackagenames [package_filter]
# 指定不混淆指定的包名，多个包名可以用逗号分隔，可以使用? * **通配符，并且可以使用否定符（!）。

-keepattributes [attribute_filter]
# 指定保留属性，多个属性可以用多个-keepattributes配置，也可以用逗号分隔，可以使用? * **通配符，并且可以使用否定符（!）。
# 比如，在混淆ibrary库时，应该至少keep Exceptions, InnerClasses, Signature；如果在追踪代码，还需要keep符号表；使用到注解时也需要keep。
-keepattributes Exceptions,InnerClasses,Signature
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*

-keepparameternames
# 指定keep已经被keep的方法的参数类型和参数名称，在混淆library库时非常有用，可供IDE帮助用户进行信息提示和代码自动填充。

#---------------------------------------------- obfuscate

-dontpreverify
# 指定不对class进行预校验，默认情况下，在编译版本为micro或者1.6或更高版本时是开启的。但编译成Android版本时，预校验是不必须的，配置这个选项可以节省一点编译时间。（Android会把class编译成dex，并对dex文件进行校验，对class进行预校验是多余的。）

#---------------------------------------------- preverify
```

## keep配置
```groovy
# -keep [,modifier,...] class_specification
# 指定类及类成员作为代码入口，保护其不被proguard，如：
-keep class com.rush.Test
-keep interface com.rush.InterfaceTest
-keep class com.rush.** {
    <init>;
    public <fields>;
    public <methods>;
    public *** get*();
    void set*(***);
}
```

## 一些详细指令
```groovy
# 代码混淆压缩比，在 0~7 之间
-optimizationpasses 5

# 不提示警告
-dontwarn

# 混合时不使用大小写混合，混合后的类名为小写
-dontusemixedcaseclassnames

# 指定不忽略非公共库的类和类成员
-dontskipnonpubliclibraryclasses
-dontskipnonpubliclibraryclassmembers

# 这句话能够使我们的项目混淆后产生映射文件
# 包含有类名->混淆后类名的映射关系
-verbose

# 不做预校验，preverify是proguard的四个步骤之一，Android不需要preverify，去掉这一步能够加快混淆速度
-dontpreverify

# 保留Annotation不混淆
-keepattributes *Annotation*,InnerClasses

# 避免混淆泛型
-keepattributes Signature

# 抛出异常时保留代码行号
-keepattributes SourceFile,LineNumberTable

# 指定混淆是采用的算法，后面的参数是一个过滤器
# 这个过滤器是 Google 推荐的算法，一般不做修改
-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*

# 是否允许改变作用域的，可以提高优化效果
# 但是，如果你的代码是一个库的话，最好不要配置这个选项，因为它可能会导致一些 private 变量被改成 public，谨慎使用
#-allowaccessmodification

# 指定一些接口可能会被合并，即使一些子类没有同时实现两个接口的方法。这种情况在java源码中是不允许存在的，但是在java字节码中是允许存在的。
# 它的作用是通过合并接口减少类的数量，从而达到减少输出文件体积的效果。仅在 optimize 阶段有效。
# 如果在开启后没有任何影响可以使用，这项配置对于一些虚拟机的65535方法数限制是有一定效果的，谨慎使用
#-mergeinterfacesaggressively

# 输出所有找不到引用和一些其它错误的警告，但是继续执行处理过程。不处理警告有些危险，所以在清楚配置的具体作用的时候再使用
-ignorewarnings
-include {filename}     #从给定的文件中读取配置参数
-basedirectory {directoryname}    #指定基础目录为以后相对的档案名称
-injars {class_path}    #指定要处理的应用程序jar,war,ear和目录
-outjars {class_path}     #指定处理完后要输出的jar,war,ear和目录的名称
-libraryjars {classpath}     #指定要处理的应用程序jar,war,ear和目录所需要的程序库文件
-dontskipnonpubliclibraryclasses     #指定不去忽略非公共的库类。
-dontskipnonpubliclibraryclassmembers     #指定不去忽略包可见的库类的成员。

 #保留选项
-keep {Modifier} {class_specification}     #保护指定的类文件和类的成员
-keepclassmembers {modifier} {class_specification}     #保护指定类的成员，如果此类受到保护他们会保护的更好
-keepclasseswithmembers {class_specification}     #保护指定的类和类的成员，但条件是所有指定的类和类成员是要存在。
-keepnames {class_specification}     #保护指定的类和类的成员的名称（如果他们不会压缩步骤中删除）
-keepclassmembernames {class_specification}     #保护指定的类的成员的名称（如果他们不会压缩步骤中删除）
-keepclasseswithmembernames {class_specification}     #保护指定的类和类的成员的名称，如果所有指定的类成员出席（在压缩步骤之后）
-printseeds {filename}     #列出类和类的成员-keep选项的清单，标准输出到给定的文件

 #压缩
-dontshrink     #不压缩输入的类文件
-printusage {filename}
-whyareyoukeeping {class_specification}

 #优化
-dontoptimize     #不优化输入的类文件
-assumenosideeffects {class_specification}     #优化时假设指定的方法，没有任何副作用
-allowaccessmodification     #优化时允许访问并修改有修饰符的类和类的成员

 #混淆
-dontobfuscate     #不混淆输入的类文件
-printmapping {filename}
-applymapping {filename}     #重用映射增加混淆
-obfuscationdictionary {filename}     #使用给定文件中的关键字作为要混淆方法的名称
-overloadaggressively     #混淆时应用侵入式重载
-useuniqueclassmembernames     #确定统一的混淆类的成员名称来增加混淆
-flattenpackagehierarchy {package_name}     #重新包装所有重命名的包并放在给定的单一包中
-repackageclass {package_name}     #重新包装所有重命名的类文件中放在给定的单一包中
-dontusemixedcaseclassnames     #混淆时不会产生形形色色的类名
-keepattributes {attribute_name,...}     #保护给定的可选属性，例如LineNumberTable, LocalVariableTable, SourceFile, Deprecated, Synthetic, Signature, and

 #InnerClasses.
-renamesourcefileattribute {string}     #设置源文件中给定的字符串常量
```

## 日志指令

```groovy
# APK 包内所有 class 的内部结构
-dump proguard/class_files.txt
# 未混淆的类和成员
-printseeds proguard/seeds.txt
# 列出从 APK 中删除的代码
-printusage proguard/unused.txt
# 混淆前后的映射，这个文件在追踪异常的时候是有用的
-printmapping proguard/mapping.txt
```

## 自定义混淆规则

```groovy
# JavaBean 实体类不能混淆，一般会将实体类统一放到一个包下，you.package.path 请改成你自己的项目路径
-keep public class com.frame.mvp.entity.** {
    *;
}

# 网页中的 JavaScript 进行交互，you.package.path 请改成你自己的项目路径
#-keepclassmembers class you.package.path.JSInterface {
#    <methods>;
#}

# 需要通过反射来调用的类，没有可忽略，you.package.path 请改成你自己的项目路径
#-keep class you.package.path.** { *; }
```

## 不是很常用但比较实用的混淆命令

```groovy
# 所有重新命名的包都重新打包，并把所有的类移动到所给定的包下面。如果没有指定 packagename，那么所有的类都会被移动到根目录下
# 如果需要从目录中读取资源文件，移动包的位置可能会导致异常，谨慎使用
# you.package.path 请改成你自己的项目路径
-flatternpackagehierarchy

# 所有重新命名过的类都重新打包，并把他们移动到指定的packagename目录下。如果没有指定 packagename，同样把他们放到根目录下面。
# 这项配置会覆盖-flatternpackagehierarchy的配置。它可以代码体积更小，并且更加难以理解。
# you.package.path 请改成你自己的项目路径
-repackageclasses you.package.path

# 指定一个文本文件用来生成混淆后的名字。默认情况下，混淆后的名字一般为 a、b、c 这种。
# 通过使用配置的字典文件，可以使用一些非英文字符做为类名。成员变量名、方法名。字典文件中的空格，标点符号，重复的词，还有以'#'开头的行都会被忽略。
# 需要注意的是添加了字典并不会显著提高混淆的效果，只不过是更不利与人类的阅读。正常的编译器会自动处理他们，并且输出出来的jar包也可以轻易的换个字典再重新混淆一次。
# 最有用的做法一般是选择已经在类文件中存在的字符串做字典，这样可以稍微压缩包的体积。
# 字典文件的格式：一行一个单词，空行忽略，重复忽略
-obfuscationdictionary

# 指定一个混淆类名的字典，字典格式与 -obfuscationdictionary 相同
#-classobfuscationdictionary
# 指定一个混淆包名的字典，字典格式与 -obfuscationdictionary 相同
-packageobfuscationdictionary

# 混淆的时候大量使用重载，多个方法名使用同一个混淆名，但是他们的方法签名不同。这可以使包的体积减小一部分，也可以加大理解的难度。仅在混淆阶段有效。
# 这个参数在 JDK 版本上有一定的限制，可能会导致一些未知的错误，谨慎使用
-overloadaggressively

# 方法同名混淆后亦同名，方法不同名混淆后亦不同名。不使用该选项时，类成员可被映射到相同的名称。因此该选项会增加些许输出文件的大小。
-useuniqueclassmembernames

# 指定在混淆的时候不使用大小写混用的类名。默认情况下，混淆后的类名可能同时包含大写字母和小写字母。
# 这样生成jar包并没有什么问题。只有在大小写不敏感的系统（例如windows）上解压时，才会涉及到这个问题。
# 因为大小写不区分，可能会导致部分文件在解压的时候相互覆盖。如果有在windows系统上解压输出包的需求的话，可以加上这个配置。
-dontusemixedcaseclassnames
```

## 不需要混淆指令

```groovy
# Android 四大组件相关
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Appliction
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider
-keep public class * extends android.app.backup.BackupAgentHelper
-keep public class * extends android.preference.Preference
-keep public class * extends android.view.View
-keep public class com.android.vending.licensing.ILicensingService

# Fragment
-keep public class * extends android.support.v4.app.Fragment
-keep public class * extends android.app.Fragment

# 保留support下的所有类及其内部类
-keep class android.support.** { *; }
-keep interface android.support.** { *; }
-dontwarn android.support.**

# 保留 R 下面的资源
-keep class **.R$* {*;}
-keepclassmembers class **.R$* {
    public static <fields>;
}

# 保留本地 native 方法不被混淆
-keepclasseswithmembernames class * {
    native <methods>;
}

# 保留在 Activity 中的方法参数是 view 的方法，
# 这样以来我们在 layout 中写的 onClick 就不会被影响
-keepclassmembers class * extends android.app.Activity{
    public void *(android.view.View);
}

# 保留枚举类不被混淆
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# 保留自定义控件（继承自View）不被混淆
-keep public class * extends android.view.View{
    *** get*();
    void set*(***);
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
}

# 保留 Parcelable 序列化类不被混淆
-keep class * implements android.os.Parcelable {
  public static final android.os.Parcelable$Creator *;
}

# 保留 Serializable 序列化的类不被混淆
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# 对于带有回调函数的 onXXEvent 的，不能被混淆
-keepclassmembers class * {
    void *(**On*Event);
}

# WebView，没有使用 WebView 请注释掉
-keepclassmembers class fqcn.of.javascript.interface.for.webview {
   public *;
}
-keepclassmembers class * extends android.webkit.webViewClient {
    public void *(android.webkit.WebView, java.lang.String, android.graphics.Bitmap);
    public boolean *(android.webkit.WebView, java.lang.String);
}
-keepclassmembers class * extends android.webkit.webViewClient {
    public void *(android.webkit.webView, jav.lang.String);
}

# 不混淆使用了 @Keep 注解相关的类
-keep class android.support.annotation.Keep

-keep @android.support.annotation.Keep class * {*;}

-keepclasseswithmembers class * {
    @android.support.annotation.Keep <methods>;
}

-keepclasseswithmembers class * {
    @android.support.annotation.Keep <fields>;
}

-keepclasseswithmembers class * {
    @android.support.annotation.Keep <init>(...);
}

# 删除代码中 Log 相关的代码，如果删除了一些预料之外的代码，很容易就会导致代码崩溃，谨慎使用
-assumenosideeffects class android.util.Log{
   public static boolean isLoggable(java.lang.String,int);
   public static int v(...);
   public static int i(...);
   public static int w(...);
   public static int d(...);
   public static int e(...);
}

# 删除自定义Log工具
-assumenosideeffects class com.example.Log.Logger{
   public static int v(...);
   public static int i(...);
   public static int w(...);
   public static int d(...);
   public static int e(...);
}
```
