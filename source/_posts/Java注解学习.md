---
title: Java注解学习
toc: true
date: 2019-11-19 14:51:59
tags:
- Java
- 教程
categories:
- Java
- 教程
---
学习一下java 注解
<!--more-->
# 元注解
## @Documented
用于描述其它类型的annotation应该被作为被标注的程序成员的公共API，因此可以被例如javadoc此类的工具文档化。
```java
@Documented
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
public @interface DocumentA {
}

//没有使用@Documented
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
public @interface DocumentB {
}

//使用注解
@DocumentA
@DocumentB
public class DocumentDemo {
    public void A(){
    }
}
```
使用 javadoc 命令生成文档
>zejian@zejiandeMBP annotationdemo$ javadoc DocumentDemo.java DocumentA.java DocumentB.java

## @Inherited

@Inherited 元注解是一个标记注解，@Inherited阐述了某个被标注的类型是被继承的。如果一个使用了@Inherited修饰的annotation类型被用于一个class，则这个annotation将被用于该class的子类。

*注意：@Inherited annotation类型是被标注过的class的子类所继承。类并不从它所实现的接口继承annotation，方法并不从它所重载的方法继承annotation。*

## @Target
表示 Annotation 所修饰的对象范围，取值(ElementType)有：
1. CONSTRUCTOR:用于描述构造器
2. FIELD:用于描述域
3. LOCAL_VARIABLE:用于描述局部变量
4. METHOD:用于描述方法
5. PACKAGE:用于描述包
6. PARAMETER:用于描述参数
7. TYPE:用于描述类、接口(包括注解类型) 或enum声明

## @Retention
这个元注解表示一个注解会被保留到什么时候，主要有以下三种：
- SOURCE. 表示在编译时会被移除，不会在编译后的class文件中出现
- CLASS. 表示会被包含在class文件中，在运行时会被移除
- RUNTIME. 表示在运行时的JVM中也可以访问到

### RUNTIME 运行时注解

运行时注解一般和反射机制配合使用，相比编译时注解性能比较低，但灵活性好，实现起来比较简单
```java
@Retention(RUNTIME)
//是一个ElementType类型的数组，用来指定注解所使用的对象范围
@Target(value = FIELD)
public @interface Add {
    float ele1() default 0f;
    float ele2() default 0f;
}

public class InjectorProcessor {
    public void process(final Object object) {
        Class class1 = object.getClass();
        //找到类里所有变量Field
        Field[] fields = class1.getDeclaredFields();
        //遍历Field数组
        for(Field field:fields){
            //找到相应的拥有Add注解的Field
            Add addMethod = field.getAnnotation(Add.class);
            if (addMethod != null){
                if(object instanceof Activity){
                    //获取注解中ele1和ele2两个数字，然后把他们相加
                    double d = addMethod.ele1() + addMethod.ele2();
                    try {
                        //把相加结果的值赋给该Field
                        field.setDouble(object,d);
                    }catch (Exception e){

                    }

                }
            }
        }

    }
}
```
```java
public class ComputeActivity extends AppCompatActivity {
    @Add(ele1 = 10f, ele2 = 1000f)
    public double ele;

    @Add(ele1 = 5f, ele2 = 5000f)
    public double total;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        InjectorProcessor injectorProcessor = new InjectorProcessor();
        injectorProcessor.process(this);
    }
}
```

### CLASS 编译时注解
 在某些代码元素上（如类型、函数、字段等）添加注解，在编译时编译器会检查AbstractProcessor的子类，并且调用该类型的process函数，然后将添加了注解的所有元素都传递到process函数中，使得开发人员可以在编译器进行相应的处理，例如，根据注解生成新的Java类

# APT
APT(Annotation Processor Tool)是一种处理注解的工具，确切的说它是javac的一个工具，它用来在编译时扫描和处理注解，一个注解的注解处理器，以java代码(或者编译过的字节码)作为输入，生成.java文件作为输出，核心是交给自己定义的处理器去处理。

不过随着android-apt的退出不再维护，现在利用Android studio的官方插件annotationProcessor 进行处理
```java
public @interface BindLayout {
    int viewId();
}

@AutoService(Processor.class)
public class MyProcessor extends AbstractProcessor {
    private Types typesUtils;//类型工具类
    private Elements elementsUtils;//节点工具类
    private Filer filerUtils;//文件工具类
    private Messager messager;//处理器消息输出（注意它不是Log工具）

    //init初始化方法，processingEnvironment会提供很多工具类，这里获取Types、Elements、Filer、Message常用工具类。
    @Override
    public synchronized void init(ProcessingEnvironment processingEnvironment) {
        super.init(processingEnvironment);
        typesUtils = processingEnvironment.getTypeUtils();
        elementsUtils = processingEnvironment.getElementUtils();
        filerUtils = processingEnvironment.getFiler();
        messager = processingEnvironment.getMessager();
    }

    //这里扫描、处理注解，生成Java文件。
    @Override
    public boolean process(Set<? extends TypeElement> set, RoundEnvironment roundEnvironment) {
        //拿到所有被BindLayout注解的节点
        Set<? extends Element> elements = roundEnvironment.getElementsAnnotatedWith(BindLayout.class);
        for (Element element : elements) {
            //输出警告信息
            processingEnv.getMessager().printMessage(Diagnostic.Kind.WARNING, "element name：" + element.getSimpleName(), element);

            //判断是否 用在类上
            if (element.getKind().isClass()) {
                //新文件名  类名_Bind.java
                String className = element.getSimpleName() + "_Bind";
                try {
                    //拿到注解值
                    int viewId = element.getAnnotation(BindLayout.class).viewId();

                    //创建文件 包名com.example.processor.    
                    JavaFileObject source = filerUtils.createSourceFile("com.example.processor." + className);
                    Writer writer = source.openWriter();

                    //文件内容
                    writer.write("package com.example.processor;\n" +
                            "\n" +
                            "import android.app.Activity;\n" +
                            "\n" +
                            "public class " + className + " {  \n" +
                            "\n" +
                            "    public static void init(Activity activity){\n" +
                            "        activity.setContentView(" + viewId + ");\n" +
                            "    }\n" +
                            "}");
                    writer.flush();
                    //完成写入
                    writer.close();
                } catch (IOException e) {
                    e.printStackTrace();
                }
            }
        }
        return false;
    }

    //要扫描哪些注解
    @Override
    public Set<String> getSupportedAnnotationTypes() {
        Set<String> annotationSet = new HashSet<>();
        annotationSet.add(BindLayout.class.getCanonicalName());
        return annotationSet;
    }

    //支持的JDK版本，建议使用latestSupported()
    @Override
    public SourceVersion getSupportedSourceVersion() {
        return SourceVersion.latestSupported();
    }
}
```
这里介绍一下 `AutoService` 注解，在process注解前需要引入 `annotations` 和 `processors` 两个库，如果只是这样，是看不到任何输出信息的，还需要一下一些操作：
1. 在 processors 库的 main 目录下新建 resources 资源文件夹；
2. 在 resources 文件夹下建立 META-INF/services 目录文件夹；
3. <p align="left">在 META-INF/services 目录文件夹下创建 javax.annotation.processing.Processor 文件；</p>
4. 在 javax.annotation.processing.Processor 文件写入注解处理器的全称，包括包路径；
5. 在 项目中添加 @processor名 注解，重新编译工程即可。

添加了 `AutoService` 就没有以上那些过程，方便了很多。

# JavaPoet
我们用 APT 可以生成java文件，但是很是繁琐，这个时候我们就可以使用JavPoet这个库。
```java
@Override
public boolean process(Set<? extends TypeElement> set, RoundEnvironment roundEnvironment) {
    Set<? extends Element> elements = roundEnvironment.getElementsAnnotatedWith(BindLayout.class);
    for (Element element : elements) {
        processingEnv.getMessager().printMessage(Diagnostic.Kind.WARNING, "element name：" +element.getSimpleName(), element);
        if (element.getKind().isClass()) {
            String className = element.getSimpleName() + "_Bind";
            try {
                int viewId = element.getAnnotation(BindLayout.class).viewId();

                //得到android.app.Activity这个类
                ClassName activityClass = ClassName.get("android.app", "Activity");

                //创建一个方法
                MethodSpec initMethod = MethodSpec.methodBuilder("init")
                        .addModifiers(Modifier.PUBLIC, Modifier.STATIC)//修饰符
                        .addParameter(activityClass, "activity")//参数
                        .returns(TypeName.VOID)//返回值
                        .addStatement("activity.setContentView(" + viewId + ");")//方法体
                        .build();

                //创建一个类        
                TypeSpec typeSpec = TypeSpec.classBuilder(className)//类名
                        .addModifiers(Modifier.PUBLIC)//修饰符
                        .addMethod(initMethod)//将方法加入到这个类
                        .build();

                //创建java文件，指定包名类        
                JavaFile javaFile = JavaFile.builder("com.example.processor", typeSpec)
                        .build();

                javaFile.writeTo(filerUtils);

            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }
    return false;
}
```
