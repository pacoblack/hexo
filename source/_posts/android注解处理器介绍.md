---
title: android注解处理器介绍
toc: true
date: 2021-02-03 15:43:32
tags:
- android
categories:
- android
---
通过APT（Annotation Processing Tool）技术，即注解处理器，在编译时扫描并处理注解，注解处理器最终生成处理注解逻辑的.java文件。
<!--more-->
# APT实现方案

## 自定义注解
```java
@Retention(RetentionPolicy.CLASS) //注解生命周期是编译期，存活于.class文件，当jvm加载class时就不在了
@Target(ElementType.FIELD) //目标对象是变量
public @interface BindView {

    /**
     * @return 控件变量的resourceId
     */
    int value();
}
```

## 注解处理器
1. 创建module
2. 添加配置
```
apply plugin: 'java-library'

dependencies {
    implementation fileTree(include: ['*.jar'], dir: 'libs')

    implementation project(':annotation')
    //用于自动为 JAVA Processor 生成 META-INF 信息。
    implementation 'com.google.auto.service:auto-service:1.0-rc3'
    //快速生成.java文件的库
    implementation 'com.squareup:javapoet:1.8.0'
}
```
3. 实现处理器
```java
@AutoService(Processor.class)
public class ButterKnifeProcessor extends AbstractProcessor {
    /**
     * 生成文件的工具类
     */
    private Filer filer;
    /**
     * 打印信息
     */
    private Messager messager;
    /**
     * 元素相关
     */
    private Elements elementUtils;
    private Types typeUtils;
    private Map<String, ProxyInfo> proxyInfoMap = new HashMap<>();


    /**
     * 一些初始化操作，获取一些有用的系统工具类
     *
     * @param processingEnv
     */
    @Override
    public synchronized void init(ProcessingEnvironment processingEnv) {
        super.init(processingEnv);
        filer = processingEnv.getFiler();
        messager = processingEnv.getMessager();
        elementUtils = processingEnv.getElementUtils();
        typeUtils = processingEnv.getTypeUtils();
    }

    /**
     * 设置支持的版本
     *
     * @return 这里用最新的就好
     */
    @Override
    public SourceVersion getSupportedSourceVersion() {
        return SourceVersion.latestSupported();
    }

    /**
     * 设置支持的注解类型
     *
     * @return
     */
    @Override
    public Set<String> getSupportedAnnotationTypes() {
        //添加支持的注解
        HashSet<String> set = new HashSet<>();
        set.add(BindView.class.getCanonicalName());
        return set;
    }

 /**
     * 注解内部逻辑的实现
     * <p>
     * Element代表程序的一个元素，可以是package, class, interface, method.只在编译期存在
     * TypeElement：变量；TypeElement：类或者接口
     *
     * @param annotations
     * @param roundEnv
     * @return
     */
    @Override
    public boolean process(Set<? extends TypeElement> annotations, RoundEnvironment roundEnv){}
```

4. 生成 META-INF 信息
一般是使用 `@AutoService(Processor.class)`注解来动态生成，[文档](https://github.com/google/auto/tree/master/service)可以了解更多

5. 实现process 方法
这里主要分为3步：
- 通过`getElementsAnnotatedWith()``获取要处理的注解的元素的集合，换句话说，找到所有Class中被``@BindView`注解标记的变量；
- 遍历第一步中的元素集合，由于这个注解可能会在多个类中使用，所以我们以类名为单元划分注解。具体说，新建一个ProxyInfo对象去保存一个类里面的所有被注解的元素；用proxyInfoMap去保存所有的ProxyInfo；大概是这个样子`Map<String, ProxyInfo> proxyInfoMap = new HashMap<>();`
- 在ProxyInfo中为每个使用了``@BindView`注解的类生成一个代理类；
- 遍历proxyInfoMap，通过ProxyInfo和JavaFile生成具体的代理类文件

>PackageElement 一般代表Package
TypeElement 一般代表代表类
VariableElement 一般代表成员变量
ExecutableElement 一般代表类中的方法

示例
```java
/**
* 通过javapoet API生成代理类
* @return
*/
public TypeSpec generateProxyClass() {
   //代理类实现的接口
   ClassName viewInjector = ClassName.get("com.zx.inject_api", "IViewInjector");
   //原始的注解类
   ClassName className = ClassName.get(typeElement);
   //  泛型接口，implements IViewInjector<MainActivity>
   ParameterizedTypeName parameterizedTypeName = ParameterizedTypeName.get(viewInjector, className);

   //生成接口的实现方法inject()
   MethodSpec.Builder bindBuilder = MethodSpec.methodBuilder("inject")
           .addModifiers(Modifier.PUBLIC)
           .addAnnotation(Override.class) //添加方法注解
           .addParameter(className, "target")
           .addParameter(Object.class, "source");

   for (int id : viewVariableElement.keySet()) {
       VariableElement element = viewVariableElement.get(id);
       String fieldName = element.getSimpleName().toString();
       bindBuilder.addStatement(" if (source instanceof android.app.Activity){target.$L = ((android.app.Activity) source).findViewById( $L);}" +
               "else{target.$L = ((android.view.View)source).findViewById($L);}", fieldName, id, fieldName, id);
   }

   MethodSpec bindMethodSpec = bindBuilder.build();

   //创建类
   TypeSpec typeSpec = TypeSpec.classBuilder(proxyClassName)
           .addModifiers(Modifier.PUBLIC)
           .addSuperinterface(parameterizedTypeName) //实现接口
           .addMethod(bindMethodSpec)
           .build();

   return typeSpec;
}
```
## 外部调用api
我们知道在processor中已经生成了处理注解逻辑的代理类，那接下来就是调用了。首先我们要知道代理类是在编译器动态生成的，而且会有多个，所以我们只能通过反射找到这个类，然后调用它的方法
1. 先定义接口
```java
public interface IViewInjector<T> {
    /**
     * 通过source.findViewById()
     *
     * @param target 泛型参数，调用类 activity、fragment等
     * @param source Activity、View
     */
    void inject(T target, Object source);
}
```
2. 反射获取句柄
```java
/**
 * 根据使用注解的类和约定的命名规则，通过反射找到动态生成的代理类（处理注解逻辑）
 * @param object 调用类对象
 */
private static IViewInjector findProxyActivity(Object object) {
    String proxyClassName = object.getClass().getName() + PROXY;
    Log.e(TAG, "findProxyActivity: "+proxyClassName);
    Class<?> proxyClass = null;
    try {
        proxyClass = Class.forName(proxyClassName);
//            Constructor<?> constructor = proxyClass.getConstructor(object.getClass());
        return (IViewInjector) proxyClass.newInstance();
    } catch (Exception e) {
        e.printStackTrace();
    }
    return null;
}
```
3. 封装好后等待外部调用
```java
/**
* Activity调用
*/
public static void bind(Activity activity) {
   findProxyActivity(activity).inject(activity, activity);
}

/**
* Fragment、Adapter调用
*
* @param object
* @param view
*/
public static void bind(Object object, View view) {
   findProxyActivity(object).inject(object, view);
}
```
## 项目使用
1. 首先是配置build.gradle
```
implementation project(':annotation')
implementation project(':inject_api')
//gradle3.0以上apt的实现方式
annotationProcessor project(':processor')
```

# APT工作原理
## 关于注册
1. 在编译时，java编译器（javac）会去META-INF中查找实现了的AbstractProcessor的子类，并且调用该类的process函数，最终生成.java文件。
2. 注册了processor后，处理器会主动调用注解处理类Processor，生成代理的.java 文件

## apt四要素
- 注解处理器（AbstractProcess）
- 代码处理（javaPoet）
- 处理器注册（AutoService）
- apt（annotationProcessor）

小结：
1. 用户定义了一个注解，并添加到预期使用的地方
2. 用户对代码开始编译时，java编译器会先找到注册的processor，对编译过程中遇到的注解识别，并通过processor进行处理
3. processor识别到注解后，借助JavaPoet生成业务相关代码，生成的代码是有某种规则，可以被识别
4. 定义接口，以便将代码生成的类和编码生成的类关联起来
