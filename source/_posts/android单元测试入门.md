---
title: android单元测试入门
toc: true
date: 2020-11-03 10:24:13
tags:
- android
- 单元测试
categories:
- android
---
android测试分为：单元测试、集成测试、UI测试
<!--more-->
![测试金字塔](https://developer.android.com/images/training/testing/pyramid_2x.png)
通常建议各类测试所占比例如下：小型测试占 70%，中型测试占 20%，大型测试占 10%。

# 单元测试
用于验证应用的行为，一次验证一个类。
此类测试旨在测试语法，异常，逻辑是否如我们所设计的一样被执行,并不能说明程序就没有错误,提前发现错误

## 本地单元测试
Robolectric 会模拟 Android 4.1（API 级别 16）或更高版本的运行时环境，并提供由社区维护的虚假对象（称为“影子”）。通过此功能，您可以测试依赖于框架的代码，而无需使用模拟器或模拟对象。Robolectric 支持 Android 平台的以下几个方面：
- 组件生命周期
- 事件循环
- 所有资源

## 插桩单元测试
可以在物理设备或模拟器上运行插桩单元测试。不过，这种形式的测试所用的执行时间明显多于本地单元测试，因此，最好只有在必须根据实际设备硬件评估应用的行为时才依靠此方法。
运行插桩测试时，AndroidX Test 会使用以下线程：
- 主线程，也称为“界面线程”或“Activity 线程”，界面交互和 Activity 生命周期事件发生在此线程上。
- 插桩线程，大多数测试都在此线程上运行。当您的测试套件开始时，AndroidJUnitTest 类将启动此线程。

如果您需要在主线程上执行某个测试，请使用 @UiThreadTest 注释该测试。

# 集成测试
用于验证模块内堆栈级别之间的互动或相关模块之间的互动
这种测试被运行在真机或者模拟器中，用于测试你的程序真的可以正常工作。

您可以根据应用的结构和以下中型测试示例（按范围递增的顺序）来定义表示应用中的单元组的最佳方式：
1. 视图和视图模型之间的互动，如测试 Fragment 对象、验证布局 XML 或评估 ViewModel 对象的数据绑定逻辑。
2. 应用的代码库层中的测试，验证不同数据源和数据访问对象 (DAO) 是否按预期进行互动。
3. 应用的垂直切片，测试特定屏幕上的互动。此类测试目的在于验证应用堆栈的所有各层的互动。
4. 多 Fragment 测试，评估应用的特定区域。与本列表中提到的其他类型的中型测试不同，这种类型的测试通常需要真实设备，因为被测互动涉及多个界面元素。

如需执行这些测试，请执行以下操作：
1. 使用 Espresso-Intents 库中的方法。如需简化传入这些测试的信息，请使用虚假对象和打桩。
2. 结合使用 IntentSubject 和基于 Truth 的断言来验证捕获的 intent。

## Espresso
当在设备或 Robolectric 上执行类似于下面的界面互动时，Espresso 有助于使任务保持同步：
- 对 View 对象执行操作。
- 评估具有无障碍功能需求的用户如何使用您的应用。
- 找到并激活 RecyclerView 和 AdapterView 对象中的项。
- 验证传出 intent 的状态。
- 验证 WebView 对象中 DOM 的结构。

# UI测试
用于验证跨越了应用的多个模块的用户操作流程
了支持中型插桩测试之外，Espresso 还支持UI测试

# JUnit
## 常用注解
- @Test
说明该方法是测试方法。测试方法必须是public void，可以抛出异常。
- @Before
它会在每个测试方法执行前都调用一次。
- @After
与@Before对应，它会在每个测试方法执行完后都调用一次。
- @BeforeClass
它会在所有的测试方法执行之前调用一次。与@Before的差别是：@Before注解的方法在每个方法执行前都会调用一次，有多少个测试方法就会掉用多少次；而@BeforeClass注解的方法只会执行一次，在所有的测试方法执行前调用一次。注意该注解的测试方法必须是public static void修饰的。
- @AfterClass
与@BeforeClass对应，它会在所有的测试方法执行完成后调用一次。注意该注解的测试方法必须是public static void修饰的。
- @Ignore
忽略该测试方法，有时我们不想运行某个测试方法时，可以加上该注解。
- @RunWith
指定该测试类使用某个运行器
- @Parameters
指定测试类的测试数据集合
- @Rule
重新制定测试类中方法的行为
- @FixMethodOrder
指定测试类中方法的执行顺序
执行顺序：@BeforeClass –> @Before –> @Test –> @After –> @AfterClass

## 常用断言
- `assertEquals`
断言传入的预期值与实际值是相等的
- `assertNotEquals`
断言传入的预期值与实际值是不相等的
- `assertArrayEquals`
断言传入的预期数组与实际数组是相等的
- `assertNull`
断言传入的对象是为空
- `assertNotNull`
断言传入的对象是不为空
- `assertTrue`
断言条件为真
- `assertFalse`
断言条件为假
- `assertSame`
断言两个对象引用同一个对象，相当于“==”
- `assertNotSame`
断言两个对象引用不同的对象，相当于“!=”
- `assertThat`
断言实际值是否满足指定的条件

## 示例
```java
public class TestJUnitLifeCycle {

    @BeforeClass
    public static void init() {
        System.out.println("------init()------");
    }

    @Before
    public void setUp() {
        System.out.println("------setUp()------");
    }

    @After
    public void tearDown() {
        System.out.println("------tearDown()------");
    }

    @AfterClass
    public static void finish() {
        System.out.println("------finish()------");
    }

    @Test
    public void test1() {
        System.out.println("------test1()------");
    }

    @Test
    public void test2() {
        System.out.println("------test2()------");
    }
}
```
执行后打印结果如下：
>>
------init()------
------setUp()------
------test1()------
------tearDown()------
------setUp()------
------test2()------
------tearDown()------
------finish()------

## Hamcrest
Hamcrest是一个表达式类库，它提供了一套匹配符Matcher，且看其官网的说明：
>>
Hamcrest is a library of matchers, which can be combined in to create flexible expressions of intent in tests. They've also been used for other purposes.

前面提到的那些断言方法，大家使用起来会可能会碰到一个问题：

断言通常必须使用一个固定的expected值，如果测试数据稍微有一点变化，测试就可能不通过，这使得测试非常脆弱。例如我们断言assertEquals(0, code)，只能判断code是不是为0，如果code不等于0则测试失败，如果code = 0或者 code = 1都是符合我的预期的呢？那又该如何测试。

JUnit4结合Hamcrest提供了一个全新的断言语法：assertThat，结合Hamcrest提供的匹配符，可以表达全部的测试思想，上面提到的问题也迎刃而解。
使用gradle引入JUnit4.12时已经包含了hamcrest-core.jar、hamcrest-library.jar、hamcrest-integration.jar这三个jar包，所以我们无需额外再单独导入hamcrest相关类库。
assertThat定义如下：
```java
public static <T> void assertThat(String reason, T actual,
            Matcher<? super T> matcher)
```
用法如下:
```java
//文本
assertThat("android studio", startsWith("and"));
assertThat("android studio", endsWith("dio"));
assertThat("android studio", containsString("android"));
assertThat("android studio", equalToIgnoringCase("ANDROID studio"));
assertThat("android studio ", equalToIgnoringWhiteSpace(" android studio "));

//数字
//测试数字在某个范围之类，10.6在[10.5-0.2, 10.5+0.2]范围之内
assertThat(10.6, closeTo(10.5, 0.2));
//测试数字大于某个值
assertThat(10.6, greaterThan(10.5));
//测试数字小于某个值
assertThat(10.6, lessThan(11.0));
//测试数字小于等于某个值
assertThat(10.6, lessThanOrEqualTo(10.6));
//测试数字大于等于某个值
assertThat(10.6, greaterThanOrEqualTo(10.6));

//集合类测试
Map<String, String> map = new HashMap<String, String>();
map.put("a", "hello");
map.put("b", "world");
map.put("c", "haha");
//测试map包含某个entry
assertThat(map, hasEntry("a", "hello"));
//测试map是否包含某个key
assertThat(map, hasKey("a"));
//测试map是否包含某个value
assertThat(map, hasValue("hello"));
List<String> list = new ArrayList<String>();
list.add("a");
list.add("b");
list.add("c");
//测试list是否包含某个item
assertThat(list, hasItem("a"));
assertThat(list, hasItems("a", "b"));
//测试数组是否包含某个item
String[] array = new String[]{"a", "b", "c", "d"};
assertThat(array, hasItemInArray("a"));

//测试对象
//测试对象不为null
assertThat(new Object(), notNullValue());
Object obj = null;
//测试对象为null
assertThat(obj, nullValue());
String str = null;
assertThat(str, nullValue(String.class));
obj = new Object();
Object obj2 = obj;
//测试2个引用是否指向的通一个对象
assertThat(obj, sameInstance(obj2));
str = "abc";
assertThat(str, instanceOf(String.class));

//测试JavaBean对象是否有某个属性
assertThat(new UserInfo(), hasProperty("name"));
assertThat(new UserInfo(), hasProperty("age"));

//-------组合逻辑测试--------
//两者都满足，a && b
assertThat(10.4, both(greaterThan(10.0)).and(lessThan(10.5)));
//所有的条件都满足，a && b && c...
assertThat(10.4, allOf(greaterThan(10.0), lessThan(10.5)));
//任一条件满足，a || b || c...
assertThat(10.4, anyOf(greaterThan(10.3), lessThan(10.4)));
//两者满足一个即可，a || b
assertThat(10.4, either(greaterThan(10.0)).or(lessThan(10.2)));
assertThat(10.4, is(10.4));
assertThat(10.4, is(equalTo(10.4)));
assertThat(10.4, is(greaterThan(10.3)));
str = new String("abc");
assertThat(str, is(instanceOf(String.class)));
assertThat(str, isA(String.class));
assertThat(10.4, not(10.5));
assertThat(str, not("abcd"));

assertThat(str, any(String.class));
assertThat(str, anything());
```

## Test Runners
JUnit没有main()方法，那它是怎么开始执行的呢？众所周知，不管是什么程序，都必须有一个程序执行入口，而这个入口通常是main()方法。显然，JUnit能直接执行某个测试方法，那么它肯定会有一个程序执行入口。没错，其实在org.junit.runner包下，有个JUnitCore.java类，这个类有一个标准的main()方法，这个其实就是JUnit程序的执行入口，其代码如下：
```java
public static void main(String... args) {
    Result result = new JUnitCore().runMain(new RealSystem(), args);
    System.exit(result.wasSuccessful() ? 0 : 1);
}
```
通过分析里面的runMain()方法，可以找到最终的执行代码如下：
```java
public Result run(Runner runner) {
    Result result = new Result();
    RunListener listener = result.createListener();
    notifier.addFirstListener(listener);
    try {
        notifier.fireTestRunStarted(runner.getDescription());
        runner.run(notifier);
        notifier.fireTestRunFinished(result);
    } finally {
        removeListener(listener);
    }
    return result;
}
```
可以看到，所有的单元测试方法都是通过Runner来执行的。Runner只是一个抽象类，它是用来跑测试用例并通知结果的，JUnit提供了很多Runner的实现类，可以根据不同的情况选择不同的test runner。
通过@RunWith注解，可以为我们的测试用例选定一个特定的Runner来执行。
- 默认的test runner是 BlockJUnit4ClassRunner。
- @RunWith(JUnit4.class)，使用的依然是默认的test runner，实质上JUnit4继承自BlockJUnit4ClassRunner。

## Suite
Suite翻译过来是测试套件，意思是让我们将一批其他的测试类聚集在一起，然后一起执行，这样就达到了同时运行多个测试类的目的。

假设我们有3个测试类：TestLogin, TestLogout, TestUpdate，使用Suite编写一个TestSuite类，我们可以将这3个测试类组合起来一起执行。TestSuite类代码如下：
```java
@RunWith(Suite.class)
@Suite.SuiteClasses({
        TestLogin.class,
        TestLogout.class,
        TestUpdate.class
})
public class TestSuite {
    //不需要有任何实现方法
}
```
执行运行TestSuite，相当于同时执行了这3个测试类。
Suite还可以进行嵌套，即一个测试Suite里包含另外一个测试Suite。
```java
@RunWith(Suite.class)
@Suite.SuiteClasses(TestSuite.class)
public class TestSuite2 {
}
```

## Rule
@Rule是JUnit4的新特性，它能够灵活地扩展每个测试方法的行为，为他们提供一些额外的功能。下面是JUnit提供的一些基础的的test rule，所有的rule都实现了TestRule这个接口类。除此外，可以自定义test rule。

### TestName Rule
在测试方法内部能知道当前的方法名。
```java
public class NameRuleTest {
   //用@Rule注解来标记一个TestRule，注意必须是public修饰的
  @Rule
  public final TestName name = new TestName();

  @Test
  public void testA() {
    assertEquals("testA", name.getMethodName());
  }

  @Test
  public void testB() {
    assertEquals("testB", name.getMethodName());
  }
}
```
### Timeout Rule
与@Test注解里的属性timeout类似，但这里是针对同一测试类里的所有测试方法都使用同样的超时时间。
```java
public class TimeoutRuleTest {

    @Rule
    public final Timeout globalTimeout = Timeout.millis(20);

    @Test
    public void testInfiniteLoop1() {
        for(;;) {...}
    }

    @Test
    public void testInfiniteLoop2() {
        for(;;) {...}
    }
}
```
### ExpectedException Rules
与@Test的属性expected作用类似，用来测试异常，但是它更灵活方便。
```java
public class ExpectedExceptionTest {

    @Rule
    public final ExpectedException exception = ExpectedException.none();

    //不抛出任何异常
    @Test
    public void throwsNothing() {
    }

    //抛出指定的异常
    @Test
    public void throwsIndexOutOfBoundsException() {
        exception.expect(IndexOutOfBoundsException.class);
        new ArrayList<String>().get(0);
    }

    @Test
    public void throwsNullPointerException() {
        exception.expect(NullPointerException.class);
        exception.expectMessage(startsWith("null pointer"));
        throw new NullPointerException("null pointer......oh my god.");
    }

}
```
### TemporaryFolder Rule
该rule能够创建文件以及文件夹，并且在测试方法结束的时候自动删除掉创建的文件，无论测试通过或者失败。
```java
public class TemporaryFolderTest {

    @Rule
    public final TemporaryFolder folder = new TemporaryFolder();

    private static File file;

    @Before
    public void setUp() throws IOException {
        file = folder.newFile("test.txt");
    }

    @Test
    public void testFileCreation() throws IOException {
        System.out.println("testFileCreation file exists : " + file.exists());
    }

    @After
    public void tearDown() {
        System.out.println("tearDown file exists : " + file.exists());
    }

    @AfterClass
    public static void finish() {
        System.out.println("finish file exists : " + file.exists());
    }

}
```
测试执行后打印结果如下：
>>
testFileCreation file exists : true
tearDown file exists : true
finish file exists : false    //说明最后文件被删除掉了

### ExternalResource Rules
实现了类似@Before、@After注解提供的功能，能在方法执行前与结束后做一些额外的操作。
```Java
public class UserExternalTest {

    @Rule
    public final ExternalResource externalResource = new ExternalResource() {
        @Override
        protected void after() {
            super.after();
            System.out.println("---after---");
        }

        @Override
        protected void before() throws Throwable {
            super.before();
            System.out.println("---before---");
        }
    };

    @Test
    public void testMethod() throws IOException {
        System.out.println("---test method---");
    }

}
```
执行后打印结果如下：
>>
---before---
---test method---
---after---

### Custom Rule
假如我们一直需要某些提示，那是不是需要每次在测试类中去实现它。这样就会比较麻烦。这时你就可以使用@Rule来解决这个问题，它甚至比@Before与@After还要强大。
自定义@Rule很简单，就是实现TestRule 接口，实现apply方法。代码如下：
```Java
public class RepeatRule implements TestRule {

    //这里定义一个注解，用于动态在测试方法里指定重复次数
    @Retention(RetentionPolicy.RUNTIME)
    @Target({ElementType.METHOD})
    public @interface Repeat {
        int count();
    }

    @Override
    public Statement apply(final Statement base, final Description description) {
        Statement repeatStatement =  new Statement() {
            @Override
            public void evaluate() throws Throwable {
                Repeat repeat = description.getAnnotation(Repeat.class);
                //如果有@Repeat注解，则会重复执行指定次数
                if(repeat != null) {
                    for(int i=0; i < repeat.count(); i++) {
                        base.evaluate();
                    }
                } else {
                    //如果没有注解，则不会重复执行
                    base.evaluate();
                }
            }
        };
        return repeatStatement;
    }
}
```
然后使用这个Rule:
```Java
public class RepeatTest {

    @Rule
    public final RepeatRule repeatRule = new RepeatRule();

    //该方法重复执行5次
    @RepeatRule.Repeat(count = 5)
    @Test
    public void testMethod() throws IOException {
        System.out.println("---test method---");
    }

    @Test
    public void testMethod2() throws IOException {
        System.out.println("---test method2---");
    }
}
```
执行结果如下：
>>
---test method2---
---test method---
---test method---
---test method---
---test method---
---test method---

# Mockito
在写单元测试的时候，我们会遇到某个测试类有很多依赖，这些依赖类或对象又有别的依赖，这样会形成一棵巨大的依赖树，要在单元测试的环境中完整地构建这样的依赖，是及其困难的，有时候甚至因为运行环境的关系，几乎不可能完整地构建出这些依赖。如下图所示：
![依赖](https://upload-images.jianshu.io/upload_images/5955727-9a4bb263c5395f17.png)
Mockito框架就是为了解决这个问题而设计的。
## 验证
```java
@Test
public void testMock() {
    //创建一个mock对象
    List list = mock(List.class);

    //使用mock对象
    list.add("one");
    list.clear();

    //验证mock对象的行为
    verify(list).add("one");  //验证有add("one")行为发生
    verify(list).clear();          //验证有clear()行为发生
}
```
### Stubbing
```Java
@Test
public void testMock2() {
    //不仅可以针对接口mock, 还可以针对具体类
    LinkedList list = mock(LinkedList.class);

    //设置返回值，当调用list.get(0)时会返回"first"
    when(list.get(0)).thenReturn("first");
    //当调用list.get(1)时会抛出异常
    when(list.get(1)).thenThrow(new RuntimeException());

    //会打印"print"
    System.out.println(list.get(0));
    //会抛出RuntimeException
    System.out.println(list.get(1));
    //会打印 null
    System.out.println(list.get(99));

    verify(list).get(0);
}
```
### Argument Matchers
```Java
@Test
public void testMock3() {
    List list = mock(List.class);
    //使用anyInt(), anyString(), anyLong()等进行参数匹配
    when(list.get(anyInt())).thenReturn("item");

    //将会打印出"item"
    System.out.println(list.get(100));

    verify(list).get(anyInt());
}
```
### 验证调用次数
```Java
@Test
public void testMock4() {
    List list = mock(List.class);
    list.add("once");
    list.add("twice");
    list.add("twice");
    list.add("triple");
    list.add("triple");
    list.add("triple");

    //执行1次
    verify(list, times(1)).add("once");
    //执行2次
    verify(list, times(2)).add("twice");
    verify(list, times(3)).add("triple");

    //从不执行, never()等同于times(0)
    verify(list, never()).add("never happened");

    //验证至少执行1次
    verify(list, atLeastOnce()).add("twice");
    //验证至少执行2次
    verify(list, atLeast(2)).add("twice");
    //验证最多执行4次
    verify(list, atMost(4)).add("triple");
}
```
### spy
```Java
@Test
public void testMock10(){
    List list = new ArrayList();
    List spy = spy(list);

    //subbing方法，size()并不会真实调用，这里返回10
    when(spy.size()).thenReturn(10);

    //使用spy对象会调用真实的方法
    spy.add("one");
    spy.add("two");

    //会打印出"one"
    System.out.println(spy.get(0));
    //会打印出"10"，与前面的stubbing方法对应
    System.out.println(spy.size());

    //对spy对象依旧可以来验证其行为
    verify(spy).add("one");
    verify(spy).add("two");
}
```

# Robolectric
Android程序员都知道，在Android模拟器或者真机设备上运行测试是很慢的。执行一次测试需要编译、部署、启动app等一系列步骤，往往需要花几分钟或者更久的时间。
Robolectric框架就可解决这个问题，它实现了一套JVM能运行的Android SDK，从而能够脱离Android环境进行测试，将原来运行一次测试的时间从几分钟缩短到几秒钟。
1. 基础设置
```groovy
//这里版本已经很旧了，看个意思
testCompile "org.robolectric:robolectric:3.3.2"
testCompile 'org.robolectric:shadows-support-v4:3.3.2'
testCompile 'org.robolectric:shadows-multidex:3.3.2'
```
2. 添加test runner
```Java
@RunWith(RobolectricTestRunner.class)
@Config(constants = BuildConfig.class, sdk = 23)
public class RobolectricSampleActivityTest {
    //必须指定test runner为RobolectricTestRunner
    //通过@Config注解来配置运行参数
}
```
3. android studio 3.0 注意
```groovy
android {
  testOptions {
    unitTests {
      includeAndroidResources = true
    }
  }
}
```
## 测试生命周期
```Java
public class MainActivity extends Activity {

    Button mBtn;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        mBtn = (Button) findViewById(R.id.btn_main);
        mBtn.setText("onCreate");
        mBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent intent = new Intent(MainActivity.this, RobolectricSampleActivity.class);
                startActivity(intent);
            }
        });
    }

    @Override
    protected void onStart() {
        super.onStart();
        mBtn.setText("onStart");
    }

    @Override
    protected void onResume() {
        super.onResume();
        mBtn.setText("onResume");
    }

    @Override
    protected void onPause() {
        super.onPause();
        mBtn.setText("onPause");
    }

    @Override
    protected void onStop() {
        super.onStop();
        mBtn.setText("onStop");
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        mBtn.setText("onDestroy");
    }
}
```
测试代码如下：
```Java
@Test
public void testActivityLifeCycle() {
    ActivityController<MainActivity> controller = Robolectric.buildActivity(MainActivity.class);
    //会调用Activity的onCreate()方法
    controller.create();
    Button btn = (Button) controller.get().findViewById(R.id.btn_main);
    System.out.println(btn.getText().toString());
    controller.start();
    System.out.println(btn.getText().toString());
    controller.resume();
    System.out.println(btn.getText().toString());
    controller.pause();
    System.out.println(btn.getText().toString());
    controller.stop();
    System.out.println(btn.getText().toString());
    controller.destroy();
    System.out.println(btn.getText().toString());
}
```
控制台打印结果如下所示：
>>
onCreate
onStart
onResume
onPause
onStop
onDestroy

## 测试Toast
```Java
//点击button弹出toast信息
mBtn.setOnClickListener(new View.OnClickListener() {
    @Override
    public void onClick(View v) {
        Toast.makeText(MainActivity.this, "toast sample", Toast.LENGTH_SHORT).show();
    }
});
```
测试代码如下:
```java    
@Test
public void testToast() {
    MainActivity activity = Robolectric.setupActivity(MainActivity.class);
    Button btn = (Button) activity.findViewById(R.id.btn_main);
    btn.performClick();
    Assert.assertNotNull(ShadowToast.getLatestToast());
    Assert.assertEquals("toast sample", ShadowToast.getTextOfLatestToast());
}
```
## 测试Dialog
```Java
@Test
public void testDialog() {
    MainActivity activity = Robolectric.setupActivity(MainActivity.class);
    Button btn = (Button) activity.findViewById(R.id.btn_main);
    btn.performClick();
    Assert.assertNotNull(ShadowAlertDialog.getLatestAlertDialog());
}
```
## 测试资源文件
```Java
@Test
public void testApplication() {
    Application app = RuntimeEnvironment.application;
    Context shadow = ShadowApplication.getInstance().getApplicationContext();
    Assert.assertSame(shadow, app);     
    System.out.println(shadow.getResources().getString(R.string.app_name));
}
```
## 测试Fragment
```Java
@Test
public void testFragment() {
    TestFragment fragment = new TestFragment();
    //该方法会添加Fragment到Activity中
    SupportFragmentTestUtil.startFragment(fragment);
    Assert.assertThat(fragment.getView(), CoreMatchers.notNullValue());
}
```

# 异步代码测试
当我们想要测试如下代码：
```Java
public class DataManager {

    public interface OnDataListener {

        public void onSuccess(List<String> dataList);

        public void onFail();
    }

    public void loadData(final OnDataListener listener) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    Thread.sleep(1000);

                    List<String> dataList = new ArrayList<String>();
                    dataList.add("11");
                    dataList.add("22");
                    dataList.add("33");

                    if(listener != null) {
                        listener.onSuccess(dataList);
                    }
                } catch (InterruptedException e) {
                    e.printStackTrace();
                    if(listener != null) {
                        listener.onFail();
                    }
                }
            }
        }).start();
    }
}
```
1. 使用CountDownLatch
```Java
@Test
public void testGetData() {
   final List<String> list = new ArrayList<String>();
   DataManager dataManager = new DataManager();
   final CountDownLatch latch = new CountDownLatch(1);
   dataManager.loadData(new DataManager.OnDataListener() {
       @Override
       public void onSuccess(List<String> dataList) {
           if(dataList != null) {
               list.addAll(dataList);
           }
           //callback方法执行完毕侯，唤醒测试方法执行线程
           latch.countDown();
       }

       @Override
       public void onFail() {
       }
   });
   try {
       //测试方法线程会在这里暂停, 直到loadData()方法执行完毕, 才会被唤醒继续执行
       latch.await();
   } catch (InterruptedException e) {
       e.printStackTrace();
   }
   Assert.assertEquals(3, list.size());
}
```
或者
```Java
@Test
public void testGetData() {
    final List<String> list = new ArrayList<String>();
    DataManager dataManager = new DataManager();
    final Object lock = new Object();
    dataManager.loadData(new DataManager.OnDataListener() {
        @Override
        public void onSuccess(List<String> dataList) {
            if(dataList != null) {
                list.addAll(dataList);
            }
            synchronized (lock) {
                lock.notify();
            }
        }

        @Override
        public void onFail() {
        }
    });
    try {
        synchronized (lock) {
            lock.wait();
        }

    } catch (InterruptedException e) {
        e.printStackTrace();
    }
    Assert.assertEquals(3, list.size());
}
```
2. 将异步变成同步
```Java
@Before
public void setup() {
    RxJavaPlugins.reset();
    //设置Schedulers.io()返回的线程
    RxJavaPlugins.setIoSchedulerHandler(new Function<Scheduler, Scheduler>() {
        @Override
        public Scheduler apply(Scheduler scheduler) throws Exception {
            //返回当前的工作线程，这样测试方法与之都是运行在同一个线程了，从而实现异步变同步。
            return Schedulers.trampoline();
        }
    });
}

@Test
public void testGetDataAsync() {    
    final List<String> list = new ArrayList<String>();
    DataManager dataManager = new DataManager();
    dataManager.loadData().subscribe(new Consumer<List<String>>() {
        @Override
        public void accept(List<String> dataList) throws Exception {
            if(dataList != null) {
                list.addAll(dataList);
            }
        }
    }, new Consumer<Throwable>() {
        @Override
        public void accept(Throwable throwable) throws Exception {

        }
    });
    Assert.assertEquals(3, list.size());
}
```

# Espresso
## 依赖库
>>
espresso-core 包含基础的视图匹配器，操作和断言库
espresso-web 包含webview的测试库
espresso-idling-resource 包含和后台作业的同步的机制
espresso-contrib 包括DatePicker, RecyclerView and Drawer actions, accessibility checks, and CountingIdlingResource这些的扩展库
espresso-intent 包括与意图有关的测试库
espresso-remote Espresso多处理功能的位置

## 基础配置
在app/build.gradle文件中添加依赖
```
androidTestImplementation 'androidx.test.espresso:espresso-core:3.2.0'
androidTestImplementation 'androidx.test:runner:1.2.0'
androidTestImplementation 'androidx.test:rules:1.2.0'
```
在app/build.gradle文件中的android.defaultConfig中添加
```
testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"
```
注意：上面的依赖只能实现基本功能，如果你想使用所有的功能，则按下面的配置：
所有依赖
```
    androidTestImplementation 'androidx.test.ext:junit:1.1.1'
    androidTestImplementation 'androidx.test.ext:truth:1.2.0'
    androidTestImplementation 'androidx.test.espresso:espresso-core:3.2.0'
    androidTestImplementation 'androidx.test.espresso:espresso-contrib:3.2.0'
    androidTestImplementation 'androidx.test:runner:1.2.0'
    androidTestImplementation 'androidx.test:rules:1.2.0'
    androidTestImplementation 'androidx.test.espresso:espresso-intents:3.2.0'
    implementation 'androidx.recyclerview:recyclerview:1.1.0'
    implementation 'androidx.test.espresso:espresso-idling-resource:3.2.0'
```

## API组件
Espresso 的主要组件包括：
- Espresso - 用于与视图交互（通过 onView() 和 onData()）的入口点。此外，还公开不一定与任何视图相关联的 API，如 pressBack()。
- ViewMatchers - 实现 Matcher<? super View> 接口的对象的集合。您可以将其中一个或多个对象传递给 onView() 方法，以在当前视图层次结构中找到某个视图。
- ViewActions - 可以传递给 ViewInteraction.perform() 方法的 ViewAction 对象的集合，例如 click()。
- ViewAssertions - 可以通过 ViewInteraction.check() 方法传递的 ViewAssertion 对象的集合。在大多数情况下，您将使用 matches 断言，它使用视图匹配器断言当前选定视图的状态。
```Java
// withId(R.id.my_view) is a ViewMatcher
// click() is a ViewAction
// matches(isDisplayed()) is a ViewAssertion
onView(withId(R.id.my_view))
    .perform(click())
    .check(matches(isDisplayed()));
```
更直观一点的：
<embed width="100%" height="900px" src="https://android.github.io/android-test/downloads/espresso-cheat-sheet-2.1.0.pdf"></embed>

### 查找视图
```Java
onView(withId(R.id.my_view));

onView(allOf(withId(R.id.my_view), withText("Hello!")));

onView(allOf(withId(R.id.my_view), not(withText("Unwanted"))));
```
### 操作视图
```Java
onView(...).perform(click());
//perform 调用来执行多项操作
onView(...).perform(typeText("Hello"), click());
//视图位于 ScrollView（垂直或水平）内
onView(...).perform(scrollTo(), click());
```
### 检查断言
```Java
onView(...).check(matches(withText("Hello!")));

// 先去匹配非唯一视图，然后使用hasSibling()匹配器缩小选择范围。
onView(allOf(withText(7), hasSibling(withText("item: 0")))).perform(click());

//匹配Actionbar正常的操作栏里边的视图
openActionBarOverflowOrOptionsMenu(getInstrumentation().getTargetContext());
onView(withText("World")).perform(click());

//匹配Actionbar上下文相关的操作栏里边的视图
openContexturlActionModeOverflowMenu();
onView(withText("Hello")).perform(click());

//断言view是否显示
onView(withId(R.id.test)).check(matches(not(isDisplayed())));

//断言view是否存在
onView(withId(R.id.test)).check(doesNotExist());
```

### 自定义断言
#### 自定义故障处理程序
espresso允许开发者自定义FailureHandler用于错误处理，常见的做法有收集错误信息，截图或者传递额外的调试信息。
```Java
private static class CustomFailureHandler implements FailureHandler {
    private final FailureHandler delegate;
    public CustomFailureHandler(Context targetContext) {
        delegate = new DefaultFailureHandler(targetContext);
    }

    @Override
    public void handle(Throwable error, Matcher<View> viewMatcher){
        try {
            delegate.handle(error, viewMatcher);
        } catch (NoMatchingViewException e) {
            throw new MySpecialException(e);
        }
    }
}
```
需要自己定义Exception，并且在test中setFailureHandler();一般在setUp()中定义。

#### 定位非默认窗口
```Java
onView(withText("south china sea"))
    .inRoot(withDecorView(not(is(getActivity().getWindow().getDecorView()))))
    .perform(click());
```
#### 在列表视图中匹配页眉和页脚
想要匹配页眉和页脚，必须在listview.addFooter()或者listview.addHeader()中传递第二个参数。这个参数起到关联作用。例如：
```Java
public static final String FOOTER = "FOOTER";
...
View footerView = layoutInflater.inflate(R.layout.list_item, listView, false);
((TextView) footerView.findViewById(R.id.item_content)).setText("count:");
((TextView) footerView.findViewById(R.id.item_size)).setText(String.valueOf(data.size()));
listView.addFooterView(footerView, FOOTER, true);
```
测试代码：
```Java
public static Matcher<Object> isFooter(){
    return allOf(is(instanceOf(String.class)), is(FOOTER));
}

public void testFooter(){
    onData(isFooter()).perform(click());
}
```
## 支持多进程
espresso允许跨进程测试，但是只是在Android 8.0及以上版本。所以请注意以下两点：
>>
应用最低版本为8.0，也就是API 26。
只能测试应用内的进程，无法测试外部进程。

使用步骤
1. 在build.gradle中引用espresso-remote库
```
dependencies {
...
androidTestImplementation 'com.android.support.test.espresso:espresso-remote:3.0.2'
}
```
2. 需要在androidTest的Manifest文件中添加以下代码：
```
<instrumentation android:name="android.support.test.runner.AndroidJUnitRunner"
android:targetPackage="android.support.mytestapp"
android:targetProcesses="xxx"/>

<meta-data
android:name="remoteMethod"
android:value="android.support.test.espresso.remote.EspressoRemote#remoteInit" />
```

## 列表
列表分为两种adapterview和recyclerview。

### adapterview列表项的交互
```Java
//要点击包含“item: 50”的行
onData(allOf(is(instanceOf(Map.class)), hasEntry(equalTo("STR"), is("item: 50"))));
```
注意，Espresso会根据需要自动滚动列表。

我们分析上边的代码，首先is(instanceOf(Map.class))会将搜索范围缩小到map集合，然后hasEntry()会去匹配集合里key为“str”和value为”item: 50”的条目。

我们可以自定义matcher去match
```Java
private static Matcher<Object> withItemContent(String expectedText) {
    checkNotNull(expectedText);
    return withItemContent(equalTo(expectedText));
}

private static Matcher<Object> withItemContent(Matcher<Object> itemTextMatcher) {
    return new BoundedMatcher<>(Map.class){
        @Override
        public boolean matchesSafely(Map map) {
            return hasEntry(equalTo("STR"), itemTextMatcher).matches(map);
        }

        @Override
        public void describeTo(Description description) {
            description.appendText("with item content: ");
            itemTextMatcher.describeTo(description);
        }
    }
}
```
这样就可以简单的调用了
```Java
onData(withItemContent("xxx")).perform(click());
```
### 操作特定子view
```java
onData(withItemContent("xxx")).onChildView(withId(R.id.tst)).perform(click());
```
### recyclerview的条目交互
espresso-contrib库中包含一系列recyclerviewactions。
>>
scrollTo 滚动到匹配的view
scrollToHolder 滚动到匹配的viewholder
scrollToPosition 滚动到指定的position
actionOnHolderItem 在匹配到的view holder中进行操作
actionOnItem 在匹配到的item view上进行操作
actionOnItemAtPosition 在指定位置的view上进行操作

实例：
```Java
@Test
public void scrollToItemBelowFold_checkItsText() {
    // First, scroll to the position that needs to be matched and click on it.
    onView(ViewMatchers.withId(R.id.recyclerView))
            .perform(RecyclerViewActions.actionOnItemAtPosition(ITEM_BELOW_THE_FOLD,
            click()));

    // Match the text in an item below the fold and check that it's displayed.
    String itemElementText = mActivityRule.getActivity().getResources()
            .getString(R.string.item_element_text)
            + String.valueOf(ITEM_BELOW_THE_FOLD);
    onView(withText(itemElementText)).check(matches(isDisplayed()));
}
@Test
public void itemInMiddleOfList_hasSpecialText() {
    // First, scroll to the view holder using the isInTheMiddle() matcher.
    onView(ViewMatchers.withId(R.id.recyclerView))
            .perform(RecyclerViewActions.scrollToHolder(isInTheMiddle()));

    // Check that the item has the special text.
    String middleElementText =
            mActivityRule.getActivity().getResources()
            .getString(R.string.middle);
    onView(withText(middleElementText)).check(matches(isDisplayed()));
}
```
## intent
```Java
assertThat(intent).hasAction(Intent.ACTION_VIEW);
assertThat(intent).categories().containsExactly(Intent.CATEGORY_BROWSABLE);
assertThat(intent).hasData(Uri.parse("www.google.com"));
assertThat(intent).extras().containsKey("key1");
assertThat(intent).extras().string("key1").isEqualTo("value1");
assertThat(intent).extras().containsKey("key2");
assertThat(intent).extras().string("key2").isEqualTo("value2");

//断言已看到的给定 intent
intented(toPackage("com.android.phone"));
```

## 插桩
当我们需要调用startActivityForResult()方法去启动照相机获取照片时，如果使用一般的方式，我们就需要手动去点击拍照，这样就不算自动化测试了。
Espresso-Intents 提供了intending()方法来解决这个问题，它可以为使用 startActivityForResult() 启动的 Activity 提供桩响应。简单来说就是，它不会去启动照相机，而是返回你自己定义的Intent。
```Java
@Test
public void activityResult_DisplaysContactsPhoneNumber() {
    // 1.构建要在启动特定 Activity 时返回的结
    Intent resultData = new Intent();
    String phoneNumber = "123-345-6789";
    resultData.putExtra("phone", phoneNumber);
    ActivityResult result =
        new ActivityResult(Activity.RESULT_OK, resultData);

    // 2.指示 Espresso 提供桩结果对象来响应“contacts”intent 的所有调用
    intending(toPackage("com.android.contacts")).respondWith(result);

    // 启动activity，期待能够返回 phoneNumber
    // Launching activity expects phoneNumber to be returned and displayed.
    onView(withId(R.id.pickButton)).perform(click());

    // 3. 验证用于启动该 Activity 的操作是否产生了预期的桩结果，
    // 在本例中，该示例测试会检查当启动“contacts”Activity 时是否返回并显示了电话号码“123-345-6789”
    onView(withId(R.id.phoneNumber)).check(matches(withText(phoneNumber)));
}
```
[这里可以查看很多官方的例子](https://github.com/android/testing-samples)
