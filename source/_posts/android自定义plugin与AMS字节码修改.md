---
title: android自定义plugin与ASM字节码修改
toc: true
date: 2020-12-07 14:41:08
tags:
- android
categories:
- android
---
先介绍一下 AOP 和 ASM 的概念，AOP 是一种面向切面编程，通过预编译方式和运行期动态代理实现程序功能的统一维护的一种技术。
和面向对象编程 的 OOP 相同。ASM 是一个框架可以看作 AOP 的工具，当然 AOP 也有其他工具，比如用的比较多的 AspectJ 、Javassist 、Xposed 和 Dexposed 等
<!--more-->
# 自定义plugin
Gradle从1.5开始，Gradle插件包含了一个叫Transform的API，这个API允许第三方插件在class文件转为为dex文件前操作编译好的class文件，这个API的目标是简化自定义类操作，而不必处理Task，并且在操作上提供更大的灵活性。并且可以更加灵活地进行操作。官方文档：http://google.github.io/android-gradle-dsl/javadoc/

# ASM框架
[ASM](https://asm.ow2.io/) 是一个通用的Java字节码操作和分析框架。它可以直接以二进制形式用于修改现有类或动态生成类。 ASM提供了一些常见的字节码转换和分析算法，可以从中构建定制的复杂转换和代码分析工具。 ASM提供与其他Java字节码框架类似的功能，但侧重于性能。因为它的设计和实现是尽可能的小和尽可能快，所以它非常适合在动态系统中使用

# 插桩
插桩就是将一段代码通过某种策略插入到另一段代码，或替换另一段代码。这里的代码可以分为源码和字节码，而我们所说的插桩一般指字节码插桩。
下图是Android开发者常见的一张图，我们编写的源码（.java）通过javac编译成字节码（.class），然后通过dx/d8编译成dex文件。
![](https://upload-images.jianshu.io/upload_images/2118143-cb08495e5bfa4210.png)
插桩就是在.class转为.dex之前，修改.class文件从而达到修改或替换代码的目的。

# 实例
1. 创建一个Java Module，删除src/main 目录下的所有目录文件，并新建 groovy 和 resources 两个目录
2. resources 目录下创建 META-INF/gradle-plugins/xxxx.properties.这里的xxx 就是将来 apply plugin: 'xxxx' 中要用到的名字
3. 配置module的build.gradle 文件
```
apply plugin: 'java-library'
//支持 groovy
apply plugin: 'groovy'
//支持 maven
apply plugin: 'maven'

dependencies {
    implementation fileTree(dir: 'libs', include: ['*.jar'])
    //添加依赖
    implementation gradleApi()
    implementation localGroovy()
    implementation 'com.android.tools.build:transform-api:1.5.0'
    implementation 'com.android.tools.build:gradle:3.4.0'
}

//通过maven将插件发布到本地的脚本配置，根据自己的要求来修改
uploadArchives {
    repositories.mavenDeployer {
        pom.version = '1.0.0'
        pom.artifactId = 'hmlifecyclepluginlocal'
        pom.groupId = 'com.heima.iou'
        // 这里是将仓库定义在本地，也可以修改为其他，视情况而定
        repository(url: uri('../repo'))
    }
}
```
4. 实现plugin接口
```groovy
public class LifeCyclePlugin implements Plugin<Project>{
    @Override
    void apply(Project project) {
        AppExtension appExtension = project.getExtensions().findByType(AppExtension.class);
        assert appExtension != null;
        println "------LifeCycle plugin entrance------- "
    }
}
```
5. 在xxx.properties 中增加配置
```
implementation-class=yyyy.plugin.LifeCyclePlugin
```
6. 实现了这些就已经完成了，接下来是发布，执行 uploadArchives 任务，就会在repo中部署
7. 接入,在根gradle 中配置,在模块gradle中配置
```
apply plugin: 'com.android.application'

buildscript {
    repositories {
        google()
        jcenter()
        //自定义插件maven地址，替换成你自己的maven地址
        maven {//添加repo本地仓库
            url uri("repo")
        }
    }
    dependencies {
        //通过maven加载自定义插件
        classpath 'com.heima.iou:hmlifecyclepluginlocal:1.0.0'
    }
}
```
```
apply plugin: 'xxxx'
```
# Extension
 Android 应用的 Gradle 配置代码
 ```
 android {
    compileSdkVersion 26
    defaultConfig {
        applicationId "com.hm.iou.thinapk.demo"
        minSdkVersion 19
        targetSdkVersion 26
        versionCode 1
        versionName "1.0"
        testInstrumentationRunner "android.support.test.runner.AndroidJUnitRunner"
    }
    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
        }
    }
}
 ```
 上面这个 android 打包配置，就是 Gradle 的 Extension，翻译成中文意思就叫扩展。它的作用就是通过实现自定义的 Extension，可以在 Gradle 脚本中增加类似 android 这样命名空间的配置，Gradle 可以识别这种配置，并读取里面的配置内容。

## 创建Extension
```
//先定义一个普通的java类，包含2个属性
class Foo {
    int age
    String username

    String toString() {
        return "name = ${username}, age = ${age}"
    }
}
//创建一个名为 foo 的Extension
getExtensions().create("foo", Foo)

//配置Extension
foo {
    age = 30
    username = "hjy"
}

task testExt << {
    //能直接通过 project 获取到自定义的 Extension
    println project.foo
}
```
```
/**
 * publicType：创建的 Extension 实例暴露出来的类类型；
 * name：要创建的Extension的名字，可以是任意符合命名规则的字符串，不能与已有的重复，否则会抛异常；
 * instanceType：该Extension的类类型；
 * constructionArguments：类的构造函数参数值
**/
<T> T create​(String name, Class<T> type, Object... constructionArguments)
<T> T create​(Class<T> publicType, String name, Class<? extends T> instanceType, Object... constructionArguments)
```
## 添加Extension
```
void add​(Class<T> publicType, String name, T extension)
void add​(String name, T extension)
```
```
getExtensions().add(Pig, "mypig", new Pig(5, "kobe"))
mypig {
    username = "MyPig"
    legs = 4
    age = 1
}
task testExt << {
    def aPig = project.getExtensions().getByName("mypig")
    println aPig
}
```
## 嵌套Extension
```
class OuterExt {

    String outerName
    String msg
    InnerExt innerExt = new InnerExt()

    void outerName(String name) {
        outerName = name
    }

    void msg(String msg) {
        this.msg = msg
    }

    //创建内部Extension，名称为方法名 inner
    void inner(Action<InnerExt> action) {
        action.execute(inner)
    }

    //创建内部Extension，名称为方法名 inner
    void inner(Closure c) {
        org.gradle.util.ConfigureUtil.configure(c, innerExt)
    }

    String toString() {
        return "OuterExt[ name = ${outerName}, msg = ${msg}] " + innerExt
    }

}


class InnerExt {

    String innerName
    String msg

    void innerName(String name) {
        innerName = name
    }

    void msg(String msg) {
        this.msg = msg
    }

    String toString() {
        return "InnerExt[ name = ${innerName}, msg = ${msg}]"
    }

}

def outExt = getExtensions().create("outer", OuterExt)

outer {

    outerName "outer"
    msg "this is a outer message."

    inner {
        innerName "inner"
        msg "This is a inner message."
    }

}

task testExt << {
    println outExt
}
```
运行结果如下：
>OuterExt[ name = outer, msg = this is a outer message.] InnerExt[ name = inner, msg = This is a inner message.]

# Transform
transform 函数是用来将源文件拷贝到目标文件，在这期间可以对class进行操作
1. 首先先在jar文件中查找到目标class文件
```groovy
static List<String> scanJar(File jarFile, File destFile) {
    def file = new JarFile(jarFile)
    Enumeration<JarEntry> enumeration = file.entries()
    List<String> list = null
    while (enumeration.hasMoreElements()) {
        JarEntry jarEntry = enumeration.nextElement()
        String entryName = jarEntry.getName()
        if (entryName == REGISTER_CLASS_FILE_NAME) {
            //标记这个jar包包含 AppLifeCycleManager.class
            //扫描结束后，我们会生成注册代码到这个文件里
            FILE_CONTAINS_INIT_CLASS = destFile
        } else {
            if (entryName.startsWith(PROXY_CLASS_PACKAGE_NAME)) {
                if (list == null) {
                    list = new ArrayList<>()
                }
                list.addAll(entryName.substring(entryName.lastIndexOf("/") + 1))
            }
        }
    }
    return list
}
```
2. 遍历源jar文件中的class，修改目标class的字节码
```groovy
void execute() {
    println("开始执行ASM方法======>>>>>>>>")

    File srcFile = ScanUtil.FILE_CONTAINS_INIT_CLASS
    //创建一个临时jar文件，要修改注入的字节码会先写入该文件里
    def optJar = new File(srcFile.getParent(), srcFile.name + ".opt")
    if (optJar.exists())
        optJar.delete()
    def file = new JarFile(srcFile)
    Enumeration<JarEntry> enumeration = file.entries()
    JarOutputStream jarOutputStream = new JarOutputStream(new FileOutputStream(optJar))
    while (enumeration.hasMoreElements()) {
        JarEntry jarEntry = enumeration.nextElement()
        String entryName = jarEntry.getName()
        ZipEntry zipEntry = new ZipEntry(entryName)
        InputStream inputStream = file.getInputStream(jarEntry)
        jarOutputStream.putNextEntry(zipEntry)

        //找到需要插入代码的class，通过ASM动态注入字节码
        if (ScanUtil.REGISTER_CLASS_FILE_NAME == entryName) {
            println "insert register code to class >> " + entryName

            ClassReader classReader = new ClassReader(inputStream)
            // 构建一个ClassWriter对象，并设置让系统自动计算栈和本地变量大小
            ClassWriter classWriter = new ClassWriter(ClassWriter.COMPUTE_MAXS)
            ClassVisitor classVisitor = new AppLikeClassVisitor(classWriter)
            //开始扫描class文件
            classReader.accept(classVisitor, ClassReader.EXPAND_FRAMES)

            byte[] bytes = classWriter.toByteArray()
            //将注入过字节码的class，写入临时jar文件里
            jarOutputStream.write(bytes)
        } else {
            //不需要修改的class，原样写入临时jar文件里
            jarOutputStream.write(IOUtils.toByteArray(inputStream))
        }
        inputStream.close()
        jarOutputStream.closeEntry()
    }

    jarOutputStream.close()
    file.close()

    //删除原来的jar文件
    if (srcFile.exists()) {
        srcFile.delete()
    }
    //重新命名临时jar文件，新的jar包里已经包含了我们注入的字节码了
    optJar.renameTo(srcFile)
}
```
3. 修改字节码
- 通过 `ClassWriter` 构建 `ClassVisitor`
```groovy
ClassReader classReader = new ClassReader(inputStream)
// 构建一个ClassWriter对象，并设置让系统自动计算栈和本地变量大小
ClassWriter classWriter = new ClassWriter(ClassWriter.COMPUTE_MAXS)
ClassVisitor classVisitor = new AppLikeClassVisitor(classWriter)
//开始扫描class文件
classReader.accept(classVisitor, ClassReader.EXPAND_FRAMES)

byte[] bytes = classWriter.toByteArray()
//将注入过字节码的class，写入临时jar文件里
jarOutputStream.write(bytes)
```
- 自定义 `ClassVisitor` 实现
```groovy
class AppLikeClassVisitor extends ClassVisitor {
    AppLikeClassVisitor(ClassVisitor classVisitor) {
        super(Opcodes.ASM5, classVisitor)
    }

    @Override
    MethodVisitor visitMethod(int access, String name,
                              String desc, String signature,
                              String[] exception) {
        println "visit method: " + name
        MethodVisitor mv = super.visitMethod(access, name, desc, signature, exception)
        //找到 AppLifeCycleManager里的loadAppLike()方法
        if ("loadAppLike" == name) {
            mv = new LoadAppLikeMethodAdapter(mv, access, name, desc)
        }
        return mv
    }
}
```
- 根据需求进行字节码的修改，如 `visitMethod()`, `visitField()`, `visitInnerClass()`, 例子中重写的 `visitMethod()`,返回自定义的 `AdviceAdapter`
```groovy
class LoadAppLikeMethodAdapter extends AdviceAdapter {

    LoadAppLikeMethodAdapter(MethodVisitor mv, int access, String name, String desc) {
        super(Opcodes.ASM5, mv, access, name, desc)
    }

    @Override
    protected void onMethodEnter() {
        super.onMethodEnter()
        println "-------onMethodEnter------"
        proxyAppLikeClassList.forEach({proxyClassName ->
            println "开始注入代码：${proxyClassName}"
            def fullName = ScanUtil.PROXY_CLASS_PACKAGE_NAME.replace("/", ".") + "." + proxyClassName.substring(0, proxyClassName.length() - 6)
            println "full classname = ${fullName}"
            mv.visitLdcInsn(fullName)
            mv.visitMethodInsn(INVOKESTATIC, "com/jd/ad/plugin/asm/AppLifeCycleManager", "registerAppLike", "(Ljava/lang/String;)V", false);
        })
    }

    @Override
    protected void onMethodExit(int opcode) {
        super.onMethodExit(opcode)
        println "-------onMethodEnter------"
    }
}
```

# 参考
https://github.com/Leaking/Hunter
