---
title: Flutter 框架
toc: true
date: 2019-09-29 17:41:19
tags:
  - Flutter
categories:
  - Flutter
---
Flutter 的构成,
//TODO: https://juejin.im/post/5c7cd2f4e51d4537b05b0974
<!--more-->
# 总览

![Vsync 流](/images/Vsync_single.jpg)

在Flutter框架中存在着一个渲染流水线（Rendering pipline）。这个渲染流水线是由垂直同步信号（Vsync）驱动的，而Vsync信号是由系统提供的，如果你的Flutter app是运行在Android上的话，那Vsync信号就是我们熟悉的Android的那个Vsync信号。当Vsync信号到来以后，Flutter 框架会按照图里的顺序执行一系列动作: 动画（Animate）、构建（Build）、布局（Layout）和绘制（Paint），最终生成一个场景（Scene）之后送往底层，由GPU绘制到屏幕上。

Flutter整体框架如下：
![](https://raw.githubusercontent.com/pacoblack/BlogImages/master/flutter_base/flutter1.webp)

可见整个Flutter架构是分为两部分的。上层的框架（Framework）部分和底层的引擎（Engine）部分。

- 框架（Framework）部分是用Dart语言写的，也是本系列文章主要涉及的部分。
- 引擎（Engine）部分是用C++实现的。引擎为框架提供支撑，也是连接框架和系统（Android/iOS）的桥梁。

触发渲染流水线的Vsync信号是来自引擎，渲染完成以后的场景也是要送入引擎来显示，并且Vsync信号的调度也是框架通过引擎来通知系统的。渲染流程从框架和引擎交互的角度用一个示意图来表示就是下面这个样子：
![](https://raw.githubusercontent.com/pacoblack/BlogImages/master/flutter_base/flutter2.webp)

1. 框架通知引擎（scheduleFrame）需要调度一帧。
2. 在系统的Vsync信号到来以后，引擎会首先会回调框架的_beginFrame函数。此时框架的渲染流水线进入动画（Animate）阶段，
3. 在动画（Animate）阶段阶段完成以后。引擎会处理完微任务队列，接着再回调框架的_drawFrame函数。渲染流水线继续按序运行构建、布局和绘制。
4. 绘制结束以后，框架调用render将绘制完成的场景送入引擎以显示到屏幕上。

# 初始化
Flutter app的入口就是函数runApp(),那么我们就从函数runApp()入手，看看这个函数被调用以后发生了什么。
runApp()的函数体位于 `widgets/binding.dart` 。长这样：
```dart
void runApp(Widget app) {
  WidgetsFlutterBinding.ensureInitialized()
    ..attachRootWidget(app)
    ..scheduleWarmUpFrame();
}
```
从调用的函数名称就可以看出来，它做了3件事，

- 确保WidgetsFlutterBinding被初始化。
- 把你的Widget贴到什么地方去。
- 然后调度一个“热身”帧。

## ensureInitialized()
```Dart
class WidgetsFlutterBinding extends BindingBase with GestureBinding, ServicesBinding, SchedulerBinding, PaintingBinding, SemanticsBinding, RendererBinding, WidgetsBinding {
  static WidgetsBinding ensureInitialized() {
    if (WidgetsBinding.instance == null)
      WidgetsFlutterBinding();
    return WidgetsBinding.instance;
  }
}
```
这个类继承自`BindingBase`,静态函数`ensureInitialized()`所做的就是返回一个`WidgetsBinding.instance`单例。
关于抽象类BindingBase需要注意两点
- 一个是在其构造的时候会调用函数initInstances()。
- 另一个就是BindingBase有一个getter，返回的是window。

我们挨个看一下这几个绑定类在调用initInstances()的时候做了什么的吧。
### GestureBinding 手势绑定
```dart
mixin GestureBinding on BindingBase implements HitTestable, HitTestDispatcher, HitTestTarget {
  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
    window.onPointerDataPacket = _handlePointerDataPacket;
  }
```
在调用initInstances()的时候，主要做的事情就是给window设置了一个手势处理的回调函数。所以这个绑定主要是负责管理手势事件的。

### ServicesBinding 服务绑定
```Dart
mixin ServicesBinding on BindingBase {
 @override
 void initInstances() {
   super.initInstances();
   _instance = this;
   window
     ..onPlatformMessage = BinaryMessages.handlePlatformMessage;
   initLicenses();
 }
```
这个绑定主要是给window设置了处理Platform Message的回调。

### SchedulerBinding 调度绑定
```Dart
mixin SchedulerBinding on BindingBase, ServicesBinding {
@override
void initInstances() {
  super.initInstances();
  _instance = this;
  window.onBeginFrame = _handleBeginFrame;
  window.onDrawFrame = _handleDrawFrame;
  SystemChannels.lifecycle.setMessageHandler(_handleLifecycleMessage);
}
```
这个绑定主要是给window设置了onBeginFrame和onDrawFrame的回调，回忆之前讲渲染流水线的时候，当Vsync信号到来的时候engine会回调Flutter的来启动渲染流程，这两个回调就是在SchedulerBinding管理的。

### PaintingBinding 绘制绑定
```Dart
mixin PaintingBinding on BindingBase, ServicesBinding {
@override
void initInstances() {
  super.initInstances();
  _instance = this;
  _imageCache = createImageCache();
}
```
这个绑定只是创建了个图片缓存。

### SemanticsBinding 辅助功能绑定
```Dart
mixin SemanticsBinding on BindingBase {
@override
void initInstances() {
  super.initInstances();
  _instance = this;
  _accessibilityFeatures = window.accessibilityFeatures;
}
```
这个绑定管理辅助功能。

### RendererBinding渲染绑定(比较重要)
```Dart
mixin RendererBinding on BindingBase, ServicesBinding, SchedulerBinding, GestureBinding, SemanticsBinding, HitTestable {
 @override
 void initInstances() {
   super.initInstances();
   _instance = this;
   _pipelineOwner = PipelineOwner(
     onNeedVisualUpdate: ensureVisualUpdate,
     onSemanticsOwnerCreated: _handleSemanticsOwnerCreated,
     onSemanticsOwnerDisposed: _handleSemanticsOwnerDisposed,
   );
   window
     ..onMetricsChanged = handleMetricsChanged
     ..onTextScaleFactorChanged = handleTextScaleFactorChanged
     ..onPlatformBrightnessChanged = handlePlatformBrightnessChanged
     ..onSemanticsEnabledChanged = _handleSemanticsEnabledChanged
     ..onSemanticsAction = _handleSemanticsAction;
   initRenderView();
   _handleSemanticsEnabledChanged();
   assert(renderView != null);
   addPersistentFrameCallback(_handlePersistentFrameCallback);
   _mouseTracker = _createMouseTracker();
 }
```
这个绑定是负责管理渲染流程的，初始化的时候做的事情也比较多。
- 首先是实例化了一个PipelineOwner类。这个类负责管理驱动我们之前说的渲染流水线。
- 随后给window设置了一系列回调函数，处理屏幕尺寸变化，亮度变化等。
- 接着调用initRenderView()。
```Dart
  void initRenderView() {
   assert(renderView == null);
   renderView = RenderView(configuration: createViewConfiguration(), window: window);
   renderView.scheduleInitialFrame();
 }
```
>这个函数实例化了一个RenderView类。RenderView继承自RenderObject。我们都知道Flutter框架中存在这一个渲染树（render tree）。这个RenderView就是渲染树（render tree）的根节点，这一点可以通过打开"Flutter Inspector"看到，在"Render Tree"这个Tab下，最根部的红框里就是这个RenderView。

- 最后调用addPersistentFrameCallback添加了一个回调函数。请大家记住这个回调，渲染流水线的主要阶段都会在这个回调里启动。

### WidgetsBinding 组件绑定
```Dart
mixin WidgetsBinding on BindingBase, SchedulerBinding, GestureBinding, RendererBinding, SemanticsBinding {
  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
    buildOwner.onBuildScheduled = _handleBuildScheduled;
    window.onLocaleChanged = handleLocaleChanged;
    window.onAccessibilityFeaturesChanged = handleAccessibilityFeaturesChanged;
    SystemChannels.navigation.setMethodCallHandler(_handleNavigationInvocation);
    SystemChannels.system.setMessageHandler(_handleSystemMessage);
  }
```
这个绑定的初始化先给buildOwner设置了个onBuildScheduled回调，还记得渲染绑定里初始化的时候实例化了一个PipelineOwner吗？这个BuildOwner是在组件绑定里实例化的。它主要负责管理Widget的重建，记住这两个"owner"。他们将会Flutter框架里的核心类。
接着给window设置了两个回调，因为和渲染关系不大，就不细说了。
最后设置SystemChannels.navigation和SystemChannels.system的消息处理函数。这两个回调一个是专门处理路由的，另一个是处理一些系统事件，比如剪贴板，震动反馈，系统音效等等。

## attachRootWidget(app)
```Dart
void attachRootWidget(Widget rootWidget) {
  _renderViewElement = RenderObjectToWidgetAdapter<RenderBox>(
    container: renderView,
    debugShortDescription: '[root]',
    child: rootWidget
  ).attachToRenderTree(buildOwner, renderViewElement);
}
```
在之前说的RendererBinding的初始化的时候，我们得到了一个RenderView的实例，render tree的根节点。
RenderView是继承自RenderObject的，而RenderObject需要有对应的Widget和Element。
上述代码中的RenderObjectToWidgetAdapter就是这个Widget。而对应的Element就是RenderObjectToWidgetElement了，既然是要关联到render tree的根节点，那它自然也就是element tree的根节点了。
从上述分析我们可以得出结论：

- 渲染绑定（RendererBinding）通过pipelineOwner间接持有render tree的根节点RenderView。
- 组件绑定（WidgetsBinding）持有element tree的根节点RenderObjectToWidgetElement。

那么RenderObjectToWidgetElement是怎么和RenderView关联起来的呢，那自然是通过一个Widget做到的了，看下RenderObjectToWidgetAdapter的代码：
```Dart
class RenderObjectToWidgetAdapter<T extends RenderObject> extends RenderObjectWidget {
  /// Creates a bridge from a [RenderObject] to an [Element] tree.
  ///
  /// Used by [WidgetsBinding] to attach the root widget to the [RenderView].
  RenderObjectToWidgetAdapter({
    this.child,
    this.container,
    this.debugShortDescription
  }) : super(key: GlobalObjectKey(container));

  @override
  RenderObjectToWidgetElement<T> createElement() => RenderObjectToWidgetElement<T>(this);

  @override
  RenderObjectWithChildMixin<T> createRenderObject(BuildContext context) => container;
  ...
  }
```
你看，createElement()返回的就是RenderObjectToWidgetElement，而createRenderObject返回的container就是构造这个Widget传入的RenderView了。而我们自己的MyApp作为一个子widget存在于RenderObjectToWidgetAdapter之中。
最后调用的attachToRenderTree做的事情属于我们之前说的渲染流水线的构建（Build）阶段，这时会根据我们自己的widget生成element tree和render tree。构建（Build）阶段完成以后，那自然是要进入布局（Layout）阶段和绘制（Paint）阶段了。怎么进呢？那就是runApp里的最后一个函数调用了。

## scheduleWarmUpFrame()
```Dart
void scheduleWarmUpFrame() {
  ...
  Timer.run(() {
    ...
    handleBeginFrame(null);
    ...
  });
  Timer.run(() {
    ...
    handleDrawFrame();
    ...
  });
}
```
这个函数其实就调了两个函数，就是之前我们讲window的时候说的两个回调函数onBeginFrame和onDrawFrame吗？这里其实就是在具体执行这两个回调。最后渲染出来首帧场景送入engine显示到屏幕。这里使用Timer.run()来异步运行两个回调，是为了在它们被调用之前有机会处理完微任务队列（microtask queue）。

总结起来的要点这么几个：

- 3个重要绑定：SchedulerBinding，RendererBinding和WidgetsBinding。
- 2个“owner”：PipelineOwner和BuildOwner。
- 2颗树的根节点：render tree根节点RenderView；element tree根节点RenderObjectToWidgetElement。

# 绘制组件
```Dart
void main() {
  runApp(MyWidget());
}

class MyWidget extends StatelessWidget {
  final String _message = "Flutter框架分析";
  @override
  Widget build(BuildContext context) => ErrorWidget(_message);
}
```
我们以这个最简单的demo为例，来分析整个的绘制过程
首先用Flutter Inspector查看:
![](https://raw.githubusercontent.com/pacoblack/BlogImages/master/flutter_base/flutter3.webp)
从上图可见就三个层级 `root` -> `MyWidget` -> `ErrorWidget`。这里的root就是上面提到的 `RenderObjectToWidgetAdapter`.
Element Tree其实是 `RenderObjectToWidgetElement` -> `StatelessElement` -> `LeafRenderObjectElement`,其中 RenderObjectToWidgetElement是element tree的根节点， 这个根节点是持有render tree的根节点`RenderView`的。它的子节点就是我们自己写的MyWidget对应的 `StatelessElement`。而这个element是不持有`RenderObject`的。只有最下面的ErrorWidget对应的`LeafRenderObjectElement`才持有第二个RenderObject。所以 render tree是只有两层的: `RenderView` -> `RenderErrorBox` 。
![](https://raw.githubusercontent.com/pacoblack/BlogImages/master/flutter_base/flutter4.webp)
图中绿色连接线表示的是element tree的层级关系。黄色的连接线表示render tree的层级关系。

从上面这个例子可以看出来，Widget是用来描述对应的Element的描述或配置。Element都是从Widget中生成的。每个Widget都会对应一个Element。但是并非每个Widget/Element会对应一个RenderObject。只有这个Widget继承自RenderObjectWidget的时候才会有对应的RenderObject。

- Widget是对Element的配置或描述。Flutter app开发者主要的工作都是在和Widget打交道。我们不需要关心树的维护更新，只需要专注于对Widget状态的维护就可以了，大大减轻了开发者的负担。
- Element负责维护element tree。Element不会去管具体的颜色，字体大小，显示内容等等这些UI的配置或描述，也不会去管布局，绘制这些事，它只管自己的那棵树。Element的主要工作都处于渲染流水线的构建（build）阶段。
- RenderObject负责具体布局，绘制这些事情。也就是渲染流水线的布局（layout）和 绘制（paint）阶段。

## Widget
```Dart
@immutable
abstract class Widget extends DiagnosticableTree {

  const Widget({ this.key });
  ...
  @protected
  Element createElement();
  ...
}
```
方法createElement()负责实例化对应的Element.

### StatelessWidget
```Dart
abstract class StatelessWidget extends Widget {
  /// Initializes [key] for subclasses.
  const StatelessWidget({ Key key }) : super(key: key);

  @override
  StatelessElement createElement() => StatelessElement(this);

  @protected
  Widget build(BuildContext context);
}
```
StatelessWidget对Flutter开发者来讲再熟悉不过了。它的createElement方法返回的是一个StatelessElement实例。
StatelessWidget没有生成RenderObject的方法。所以StatelessWidget只是个中间层，它需要实现build方法来返回子Widget。

### StatefulWidget
```Dart
abstract class StatefulWidget extends Widget {
  @override
  StatefulElement createElement() => StatefulElement(this);

  @protected
  State createState();
}
```
StatefulWidget对Flutter开发者来讲非常熟悉了。createElement方法返回的是一个StatefulElement实例。方法createState()构建对应于这个StatefulWidget的State。
StatefulWidget没有生成RenderObject的方法。所以StatefulWidget也只是个中间层，它需要对应的State实现build方法来返回子Widget。

### State
说到StatefulWidget就不能不说说State。
```Dart
abstract class State<T extends StatefulWidget> extends Diagnosticable {
  T get widget => _widget;
  T _widget;

  BuildContext get context => _element;
  StatefulElement _element;

  // 用来判断这个State是不是关联到element tree中的某个Element。如果当前State不是在mounted == true的状态，你去调用setState()是会crash的。
  bool get mounted => _element != null;

  void initState() { }

  void didUpdateWidget(covariant T oldWidget) { }

  void setState(VoidCallback fn) {
    final dynamic result = fn() as dynamic;
    _element.markNeedsBuild();
  }

  void deactivate() { }

  void dispose() { }

  // 这里的context 返回的其实是上面 get 的Element
  Widget build(BuildContext context);

  void didChangeDependencies() { }
}
```
### InheritedWidget
InheritedWidget既不是StatefullWidget也不是StatelessWidget。它是用来向下传递数据的。在InheritedWidget之下的子节点都可以通过调用 BuildContext.inheritFromWidgetOfExactType() 来获取这个 InheritedWidget。它的createElement()函数返回的是一个InheritedElement。
```Dart
abstract class InheritedWidget extends ProxyWidget {
  const InheritedWidget({ Key key, Widget child })
    : super(key: key, child: child);

  @override
  InheritedElement createElement() => InheritedElement(this);

  @protected
  bool updateShouldNotify(covariant InheritedWidget oldWidget);
}
```
### RenderObjectWidget
RenderObjectWidget用来配置RenderObject。其createElement()函数返回RenderObjectElement。由其子类实现。相对于上面说的其他Widget。这里多了一个createRenderObject()方法。用来实例化RenderObject。
```Dart
abstract class RenderObjectWidget extends Widget {

  const RenderObjectWidget({ Key key }) : super(key: key);

  @override
  RenderObjectElement createElement();

  @protected
  RenderObject createRenderObject(BuildContext context);

  @protected
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) { }

  @protected
  void didUnmountRenderObject(covariant RenderObject renderObject) { }
}
```
RenderObjectWidget只是个配置，当配置发生变化需要应用到现有的RenderObject上的时候，Flutter框架会调用updateRenderObject()来把新的配置设置给相应的RenderObject。
RenderObjectWidget有三个比较重要的子类：
- LeafRenderObjectWidget这个Widget 配置的节点处于树的最底层，它是没有孩子的。对应 LeafRenderObjectElement。
- SingleChildRenderObjectWidget， 只含有一个孩子。对应 SingleChildRenderObjectElement。
- MultiChildRenderObjectWidget， 有多个孩子。对应 MultiChildRenderObjectElement。

## Element
Element构成了element tree。这个类主要在做的事情就是维护这棵树。
从上面对Widget的分析我们可以看出，好像每个特别的Widget都会有一个对应的Element。特别是对于RenderObjectWidget。如果我有一个XXXRenderObjectWidget，它的createElement()通常会返回一个XXXRenderObjectElement。为简单起见。我们的分析就仅限于比较基础的一些Element。
首先来看一下基类Element。
```Dart
abstract class Element extends DiagnosticableTree implements BuildContext {
    Element _parent;
    Widget _widget;
    BuildOwner _owner;
    dynamic _slot;

    void visitChildren(ElementVisitor visitor) { }

    Element updateChild(Element child, Widget newWidget, dynamic newSlot) {

    }

    void mount(Element parent, dynamic newSlot) {

    }

    void unmount() {

    }

    void update(covariant Widget newWidget) {

    }

    @protected
    Element inflateWidget(Widget newWidget, dynamic newSlot) {
    ...
      final Element newChild = newWidget.createElement();
      newChild.mount(this, newSlot);
      return newChild;
    }

    void markNeedsBuild() {
      if (dirty)
        return;
      _dirty = true;
      owner.scheduleBuildFor(this);
    }

    void rebuild() {
      if (!_active || !_dirty)
        return;
      performRebuild();
    }

    @protected
    void performRebuild();
}
```
Element持有当前的Widget，还有BuildOwner。这个BuildOwner是之前在WidgetsBinding里实例化的。
Element是树结构，它会持有父节点_parent。_slot由父Element设置，目的是告诉当前Element在父节点的什么位置。由于Element基类不知道子类会如何管理孩子节点。所以函数visitChildren()由子类实现以遍历孩子节点。
函数updateChild()比较重要，用来更新一个孩子节点。更新有四种情况：
- 新Widget为空，老Widget也为空。则啥也不做。
- 新Widget为空，老Widget不为空。这个Element被移除。
- 新Widget不为空，老Widget为空。则调用inflateWidget()以这个Wiget为配置实例化一个Element。
- 新Widget不为空，老Widget不为空。调用update()函数更新子Element。update()函数由子类实现。

新Element被实例化以后会调用`mount()`来把自己加入element tree。要移除的时候会调用unmount()。

函数`markNeedsBuild()`用来标记Element为“脏”(dirty)状态。表明渲染下一帧的时候这个Element需要被重建。

函数`rebuild()`在渲染流水线的构建（build）阶段被调用。具体的重建在函数performRebuild()中，由Element子类实现。
Widget有一些比较重要的子类，对应的Element也有一些比较重要的子类。
### ComponentElement
ComponentElement表示当前这个Element是用来组合其他Element的。
```Dart
abstract class ComponentElement extends Element {
  ComponentElement(Widget widget) : super(widget);

  Element _child;

  @override
  void performRebuild() {
    Widget built;
    built = build();
    _child = updateChild(_child, built, slot);
  }

  Widget build();
}
```
ComponentElement继承自Element。是个抽象类。_child是其孩子。在函数performRebuild()中会调用build()来实例化一个Widget。build()函数由其子类实现。

### StatelessElement
StatelessElement对应的Widget是我们熟悉的StatelessWidget。
```Dart
class StatelessElement extends ComponentElement {

  @override
  Widget build() => widget.build(this);

  @override
  void update(StatelessWidget newWidget) {
    super.update(newWidget);
    _dirty = true;
    rebuild();
  }
}
```
build()函数直接调用的就是StatelessWidget.build()。现在你知道你写在StatelessWidget里的build()是在哪里被调用的了吧。而且你看，build()函数的入参是this。我们都知道这个函数的入参应该是BuildContext类型的。这个入参其实就是这个StatelessElement。

### StatefulElement
StatefulElement对应的Widget是我们熟悉的StatefulWidget。
```Dart
class StatefulElement extends ComponentElement {
  /// Creates an element that uses the given widget as its configuration.
  StatefulElement(StatefulWidget widget)
      : _state = widget.createState(),
        super(widget) {
    _state._element = this;
    _state._widget = widget;
  }

  @override
  Widget build() => state.build(this);

   @override
  void _firstBuild() {
    final dynamic debugCheckForReturnedFuture = _state.initState()
    _state.didChangeDependencies();
    super._firstBuild();
  }

  @override
  void deactivate() {
    _state.deactivate();
    super.deactivate();
  }

  @override
  void unmount() {
    super.unmount();
    _state.dispose();
    _state._element = null;
    _state = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state.didChangeDependencies();
  }
}
```
在StatefulElement构造的时候会调用对应StatefulWidget的createState()函数。也就是说State是在实例化StatefulElement的时候被实例化的。并且State实例会被这个StatefulElement实例持有。从这里也可以看出为什么StatefulWidget的状态要由单独的State管理，每次刷新的时候可能会有一个新的StatefulWidget被创建，但是State实例是不变的。
build()函数调用的是我们熟悉的State.build(this)，现在你也知道了State的build()函数是在哪里被调用的了吧。而且你看，build()函数的入参是this。我们都知道这个函数的入参应该是BuildContext类型的。这个入参其实就是这个StatefulElement。
我们都知道State有状态，当状态改变时对应的回调函数会被调用。这些回调函数其实都是在StatefulElement里被调用的。
在函数_firstBuild()里会调用State.initState()和State.didChangeDependencies()。
在函数deactivate()里会调用State.deactivate()。
在函数unmount()里会调用State.dispose()。
在函数didChangeDependencies()里会调用State.didChangeDependencies()。

### InheritedElement
InheritedElement对应的Widget是InheritedWidget。其内部实现主要是在维护对其有依赖的子Element的Map，以及在需要的时候调用子Element对应的didChangeDependencies()回调，这里就不贴代码了，大家感兴趣的话可以自己去看一下源码。

### RenderObjectElement
RenderObjectElement对应的Widget是RenderObjectWidget。
```Dart
abstract class RenderObjectElement extends Element {
  RenderObject _renderObject;

  @override
  void mount(Element parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    _renderObject = widget.createRenderObject(this);
    attachRenderObject(newSlot);
    _dirty = false;
  }

  @override
  void unmount() {
    super.unmount();
    widget.didUnmountRenderObject(renderObject);
  }

  @override
  void update(covariant RenderObjectWidget newWidget) {
    super.update(newWidget);
    widget.updateRenderObject(this, renderObject);
    _dirty = false;
  }

  @override
  void performRebuild() {
    widget.updateRenderObject(this, renderObject);
    _dirty = false;
  }

  @protected
  void insertChildRenderObject(covariant RenderObject child, covariant dynamic slot);

  @protected
  void moveChildRenderObject(covariant RenderObject child, covariant dynamic slot);

  @protected
  void removeChildRenderObject(covariant RenderObject child);

}
```
函数mount()被调用的时候会调用RenderObjectWidget.createRenderObject()来实例化RenderObject。
函数update()和performRebuild()被调用的时候会调用RenderObjectWidget.updateRenderObject()。
函数unmount()被调用的时候会调用RenderObjectWidget.didUnmountRenderObject()。

## RenderObject
RenderObject负责渲染流水线布局（layout）阶段和绘制（paint）阶段的工作。同时也维护render tree。对render tree的维护方法是来自基类AbstractNode。这里我们主要关注和渲染流水线相关的一些方法。
```Dart
abstract class RenderObject extends AbstractNode with DiagnosticableTreeMixin implements HitTestTarget {

  void markNeedsLayout() {
      ...
  }

  void markNeedsPaint() {
      ...
  }

  void layout(Constraints constraints, { bool parentUsesSize = false }) {
    ...  
    if (sizedByParent) {
        performResize();
    }
    ...
    performLayout();
    ...
  }

  void performResize();

  void performLayout();

  void paint(PaintingContext context, Offset offset) { }
}
```
markNeedsLayout()标记这个RenderObject需要重新做布局。markNeedsPaint标记这个RenderObject需要重绘。这两个函数只做标记。标记之后Flutter框架会调度一帧，在下一个Vsync信号到来之后才真正做布局和绘制。
真正的布局在函数layout()中进行。这个函数会做一次判断，如果sizedByParent为true。则会调用performResize()。表明这个RenderObject的尺寸仅由其父节点决定。然后会调用performLayout()做布局。performResize()和performLayout()都需要RenderObject的子类去实现。

# flutter运行框架
Flutter的渲染流水线，这个过程大致可以分为两段操作。第一段是从State.setState()到去engine那里请求一帧，第二段就是Vsync信号到来以后渲染流水线开始重建新的一帧最后送入engine去显示。

## State.setState()
```Dart
void setState(VoidCallback fn) {

    final dynamic result = fn() as dynamic;

    _element.markNeedsBuild();
  }
```
这里会调用到Element的markNeedsBuild()函数。
```Dart
void markNeedsBuild() {
    if (!_active)
      return;
    if (dirty)
      return;
    _dirty = true;
    owner.scheduleBuildFor(this);
  }
```
Element首先看自己是不是active的状态，不是的话就直接返回了，如果是“脏”（dirty）的状态也直接返回，不是的话会置上这个状态然后调用BuildOwner的scheduleBuildFor()函数，这个BuildOwner我们之前介绍过，它的实例是在WidgetsBinding初始化的时候构建的。每个Element的都会持有BuildOwner的引用。由其父Element在mount的时候设置。
```Dart
void scheduleBuildFor(Element element) {
  if (element._inDirtyList) {
    _dirtyElementsNeedsResorting = true;
    return;
  }
  if (!_scheduledFlushDirtyElements && onBuildScheduled != null) {
    _scheduledFlushDirtyElements = true;
    onBuildScheduled();
  }
  _dirtyElements.add(element);
  element._inDirtyList = true;
}
```
BuildOwner会维护一个_dirtyElements列表，所有被标记为“脏”（dirty）的element都会被添加进去。
在此之前会调用onBuildScheduled()。这个函数是WidgetsBinding初始化的时候设置给BuildOwner的，对应的是WidgetsBinding._handleBuildScheduled()。
```Dart
void _handleBuildScheduled() {
    ensureVisualUpdate();
  }
```
这里会调用到ensureVisualUpdate()。这个函数定义在SchedulerBinding里的
```Dart
void ensureVisualUpdate() {
    switch (schedulerPhase) {
      case SchedulerPhase.idle:
      case SchedulerPhase.postFrameCallbacks:
        scheduleFrame();
        return;
      case SchedulerPhase.transientCallbacks:
      case SchedulerPhase.midFrameMicrotasks:
      case SchedulerPhase.persistentCallbacks:
        return;
    }
  }
```
函数ensureVisualUpdate()会判断当前调度所处的状态，如果是在idle（空闲）或者postFrameCallbacks运行状态则调用scheduleFrame()。其他状态则直接返回。下面这三个状态正是渲染流水线运行的时候。

```Dart
void scheduleFrame() {
    if (_hasScheduledFrame || !_framesEnabled)
      return;
    window.scheduleFrame();
    _hasScheduledFrame = true;
  }
```
在函数scheduleFrame()里我们看到了熟悉的window。
这里就是通知engine去调度一帧的地方了。调度之后会置上_hasScheduledFrame标志位，避免重复请求。另外一个标志位_framesEnabled是代表当前app的状态，或者说其所处的生命周期是否允许刷新界面。这个状态有四种：resumed，inactive，paused和suspending。

- resumed：app可见且可以响应用户输入。
- inactive：app不能响应用户输入，例如在Android上弹出系统对话框。
- paused：app对用户不可见。
- suspending：app挂起？？这个状态貌似Android和iOS都没有上报。

_framesEnabled只有在resumed和inactive状态下才为true。也就是说，只有在这两个状态下Flutter框架才会刷新页面。

第一阶段的主要工作就是把需要重建的Element放入_dirtyElements列表。
接下来Flutter框架会等待Vsync信号到来以后engine回调框架，这就是第二段要做的事情了。

## Vsync信号接收
Vsync信号到来之后，engin会按顺序回调window的两个回调函数：onBeginFrame()和onDrawFrame()。
这两个回调是SchedulerBinding初始化的时候设置给window的。对应的是SchedulerBinding.handleBeginFrame()和SchedulerBinding.handleDrawFrame()。

### onBeginFrame
这个回调会直接走到SchedulerBinding.handleBeginFrame()。
```Dart
  void handleBeginFrame(Duration rawTimeStamp) {
   ...
    _hasScheduledFrame = false;
    try {
      // TRANSIENT FRAME CALLBACKS
      _schedulerPhase = SchedulerPhase.transientCallbacks;
      final Map<int, _FrameCallbackEntry> callbacks = _transientCallbacks;
      _transientCallbacks = <int, _FrameCallbackEntry>{};
      callbacks.forEach((int id, _FrameCallbackEntry callbackEntry) {
        if (!_removedIds.contains(id))
          _invokeFrameCallback(callbackEntry.callback, _currentFrameTimeStamp, callbackEntry.debugStack);
      });
      _removedIds.clear();
    } finally {
      _schedulerPhase = SchedulerPhase.midFrameMicrotasks;
    }
  }
```
这个函数主要是在依次回调“Transient”回调函数，这些回调函数是在调度之前设置在SchedulerBinding里的，这里的“Transient”意思是临时的，或者说是一次性的。原因是这些回调函数只会被调用一次。
注意看代码里_transientCallbacks被置为空Map了。如果想在下一帧再次调用的话需要提前重新设置回调。这些回调主要和动画有关系。也就是渲染流水线里的第一阶段，动画（Animate）阶段。
在运行回调之前_schedulerPhase的状态被设置为SchedulerPhase.transientCallbacks。回调处理完以后状态更新至SchedulerPhase.midFrameMicrotasks意思是接下来会处理微任务队列。处理完微任务以后，engine会接着回调onDrawFrame()。

### onDrawFrame
这个回调会直接走到SchedulerBinding.handleDrawFrame()。
```Dart
void handleDrawFrame() {
    try {
      // PERSISTENT FRAME CALLBACKS
      _schedulerPhase = SchedulerPhase.persistentCallbacks;
      for (FrameCallback callback in _persistentCallbacks)
        _invokeFrameCallback(callback, _currentFrameTimeStamp);

      // POST-FRAME CALLBACKS
      _schedulerPhase = SchedulerPhase.postFrameCallbacks;
      final List<FrameCallback> localPostFrameCallbacks =
          List<FrameCallback>.from(_postFrameCallbacks);
      _postFrameCallbacks.clear();
      for (FrameCallback callback in localPostFrameCallbacks)
        _invokeFrameCallback(callback, _currentFrameTimeStamp);
    } finally {
      _schedulerPhase = SchedulerPhase.idle;
      _currentFrameTimeStamp = null;
    }
  }
```
在handleDrawFrame里按顺序处理了两类回调，一类叫“Persistent”回调，另一类叫“Post-Frame”回调。
“Persistent”字面意思是永久的。这类回调一旦注册以后是不能取消的。主要用来驱动渲染流水线。渲染流水线的构建（build），布局（layout）和绘制（paint）阶段都是在其中一个回调里的。
“Post-Frame”回调主要是在新帧渲染完成以后的一类调用，此类回调只会被调用一次。
在运行“Persistent”回调之前_schedulerPhase状态变为SchedulerPhase.persistentCallbacks。在运行“Post-Frame”回调之前_schedulerPhase状态变为SchedulerPhase.postFrameCallbacks。最终状态变为SchedulerPhase.idle。
这里我们主要关注一个“Persistent”回调：WidgetsBinding.drawFrame()。这个函数是在RendererBinding初始化的时候加入到“Persistent”回调的。
```Dart
void drawFrame() {
   try {
    if (renderViewElement != null)
      buildOwner.buildScope(renderViewElement);
    super.drawFrame();
    buildOwner.finalizeTree();
  } finally {
     ...
  }
}
```
这里首先会调用buildOwner.buildScope(renderViewElement)。其入参renderViewElement是element tree的根节点。此时渲染流水线就进入了构建（build）阶段。接下来调用了super.drawFrame()。这个函数定义在RendererBinding中。
```Dart
void drawFrame() {
  pipelineOwner.flushLayout();
  pipelineOwner.flushCompositingBits();
  pipelineOwner.flushPaint();
  renderView.compositeFrame(); // this sends the bits to the GPU
  pipelineOwner.flushSemantics(); // this also sends the semantics to the OS.
}
```
可以看出渲染流水线的接力棒传到了pipelineOwner的手里，渲染流水线就进入了布局（layout）阶段和绘制（paint）阶段。
关于最后这两个阶段本篇不做详细介绍。这里大家只要知道绘制完成以后Flutter框架最终会调用window.render(scene)将新帧的数据送入engine显示到屏幕。
最后调用buildOwner.finalizeTree()。这个函数的作用是清理不再需要的Element节点。在element tree更新以后可能有些节点就不再需要挂载在树上了，在finalizeTree()的时候会将这些节点及其子节点unmount。

### build 构建阶段
```Dart
void buildScope(Element context, [VoidCallback callback]) {
    try {
      _scheduledFlushDirtyElements = true;
      _dirtyElements.sort(Element._sort);
      _dirtyElementsNeedsResorting = false;
      int dirtyCount = _dirtyElements.length;
      int index = 0;
      while (index < dirtyCount) {
        try {
          _dirtyElements[index].rebuild();
        } catch (e, stack) {
          ...
        }
        index += 1;
      }

    } finally {
      for (Element element in _dirtyElements) {
        element._inDirtyList = false;
      }
      _dirtyElements.clear();
      _scheduledFlushDirtyElements = false;
      _dirtyElementsNeedsResorting = null;

    }
  }
```
还记得在调度帧之前会把需要更新的Element标记为“脏”（dirty）并放入BuildOwner的_dirtyElements列表。这里Flutter会先按照深度给这个列表排个序。因为Element在重建的时候其子节点也都会重建，这样如果父节点和子节点都为“脏”的话，先重建父节点就避免了子节点的重复重建。

排完序就是遍历_dirtyElements列表。依次调用Element.rebuild()。这个函数又会调用到Element.performRebuild()。我们之前介绍Element的时候说过performRebuild()由其子类实现。

我们之前的出发点是State.setState()。那就先看看StatefulElement如何做的。它的performRebuild()是在其父类ComponentElement里：
```Dart
void performRebuild() {
    Widget built;
    built = build();
    try {
      _child = updateChild(_child, built, slot);
    } catch (e, stack) {
      ...
    }
  }
```

回忆一下ComponentElement。这个build()函数最终会调用到State.build()了。返回的就是我们自己实例化的Widget。拿到这个新Widget就去调用updateChild()。之前在讲Element的时候我们介绍过updateChild()这个函数。由增，删，改这么几种情况，对于MyWidget，从State.setState()过来是属于改的情况。此时会调用child.update(newWidget)。这个update()函数又是由各个Element子类实现的。这里我们只列举几个比较典型的。
StatefulElement和StatelessElement的update()函数最终都会调用基类Element的rebuild()函数。好像在兜圈圈的感觉。。。
RenderObjectElement的update()函数就比较简单了
```Dart
void update(covariant RenderObjectWidget newWidget) {
    super.update(newWidget);
    widget.updateRenderObject(this, renderObject);
    _dirty = false;
  }
```
更新只是调用了一下RenderObjectWidget.updateRenderObject()。这个函数我们之前介绍过，只是把新的配置设置到现有的RenderObject上。
回到上面那个兜圈圈的问题。理清这里的调用关系的关键就是要搞清楚是此时的Element是在对自己进行操作还是对孩子进行操作。假设我们有这样的一个三层element tree进行更新重建。
- 父(StatefulElement)

- 子(StatefulElement)

- 孙(LeafRenderObjectElement)

那么从父节点开始，调用顺序如下：
父.rebuild()--->父.performRebuild()--->父.updateChild()--->子.update()--->子.rebuild()--->子.performRebuild()--->子.updateChild()--->孙.update()

至此渲染流水线的构建（build）阶段就跑完了。接下来就由pipelineOwner驱动开始布局（layout）和绘制（paint）阶段了。

# 动画
//TODO

# Layout 布局
Flutter框架的布局采用的是盒子约束（Box constraints）模型。其布局流程如下图所示：
![](https://raw.githubusercontent.com/pacoblack/BlogImages/master/flutter_base/flutter5.webp)
图中的树是render tree。每个节点都是一个RenderObject。从根节点开始，每个父节点启动子节点的布局流程，在启动的时候会传入Constraits，也即“约束”。Flutter使用最多的是盒子约束（Box constraints）。盒子约束包含4个域：最大宽度（maxWidth）最小宽度（minWidth）最大高度（maxHeight）和最小高度（minHeight）。子节点布局完成以后会确定自己的尺寸（size）。size包含两个域：宽度（width）和高度（height）。父节点在子节点布局完成以后需要的时候可以获取子节点的尺寸（size）整体的布局流程可以描述为一下一上，一下就是约束从上往下传递，一上是指尺寸从下往上传递。这样Flutter的布局流程只需要一趟遍历render tree即可完成。具体布局过程是如何运行的，我们通过分析源码来进一步分析一下。
在之前的分析中，我们知道在drawFrame 中，我们会走到 RenderBinding中
```Dart
void drawFrame() {
  pipelineOwner.flushLayout();
  pipelineOwner.flushCompositingBits();
  pipelineOwner.flushPaint();
  renderView.compositeFrame(); // this sends the bits to the GPU
  pipelineOwner.flushSemantics(); // this also sends the semantics to the OS.
}
```
其中 pipelineOwner.flushLayout()便是布局阶段
```Dart
void flushLayout() {
      while (_nodesNeedingLayout.isNotEmpty) {
        final List<RenderObject> dirtyNodes = _nodesNeedingLayout;
        _nodesNeedingLayout = <RenderObject>[];
        for (RenderObject node in dirtyNodes..sort((RenderObject a, RenderObject b) => a.depth - b.depth)) {
          if (node._needsLayout && node.owner == this)
            node._layoutWithoutResize();
        }
      }
  }
```
这里会遍历dirtyNodes数组。这个数组里放置的是需要重新做布局的RenderObject。遍历之前会对dirtyNodes数组按照其在render tree中的深度做个排序。这里的排序和我们在构建（build）阶段遇到的对element tree的排序一样。排序以后会优先处理上层节点。因为布局的时候会递归处理子节点，这样如果先处理上层节点的话，就避免了后续重复布局下层节点。
之后就会调用RenderObject._layoutWithoutResize()来让节点自己做布局了。
```Dart
void _layoutWithoutResize() {
    try {
      performLayout();
      markNeedsSemanticsUpdate();
    } catch (e, stack) {
      ...
    }
    _needsLayout = false;
    markNeedsPaint();
  }
```
在RenderObject中，函数performLayout()需要其子类自行实现。因为有各种各样的布局，就需要子类个性化的实现自己的布局逻辑。在布局完成以后，会将自身的_needsLayout标志置为false。回头看一下上一个函数，在循环体里，只有_needsLayout是true的情况下才会调用_layoutWithoutResize()。
我们知道在Flutter中布局，渲染都是由RenderObject完成的,更具体的说应该是RenderBox。大部分页面元素使用的是盒子约束。
那么参数是如何传递到RenderBox的呢？
Container.build() 会返回一个 ConstrainedBox
```Dart
class ConstrainedBox extends SingleChildRenderObjectWidget {

  ConstrainedBox({
    Key key,
    @required this.constraints,
    Widget child,
  }) : assert(constraints != null),
       assert(constraints.debugAssertIsValid()),
       super(key: key, child: child);

  /// The additional constraints to impose on the child.
  final BoxConstraints constraints;

  @override
  RenderConstrainedBox createRenderObject(BuildContext context) {
    return RenderConstrainedBox(additionalConstraints: constraints);
  }

  @override
  void updateRenderObject(BuildContext context, RenderConstrainedBox renderObject) {
    renderObject.additionalConstraints = constraints;
  }

}
```
ConstrainedBox 会创建 RenderConstrainedBox
```Dart
class RenderConstrainedBox extends RenderProxyBox {

  RenderConstrainedBox({
    RenderBox child,
    @required BoxConstraints additionalConstraints,
  }) :
       _additionalConstraints = additionalConstraints,
       super(child);

  BoxConstraints _additionalConstraints;

  @override
  void performLayout() {
    if (child != null) {
      child.layout(_additionalConstraints.enforce(constraints), parentUsesSize: true);
      size = child.size;
    } else {
      size = _additionalConstraints.enforce(constraints).constrain(Size.zero);
    }
  }
}
```
走到这里，其实这个RenderConstrainedBox就是相应的RnderBox，会通过performLayout 进行布局。
当有孩子节点的时候，这里会调用child.layout()请求孩子节点做布局。调用时要传入对孩子节点的约束constraints。

# paint 绘制
Flutter框架中render tree负责布局和渲染。在渲染的时候，Flutter会遍历需要重绘的RenderObject子树来逐一绘制。我们在屏幕上看到的Flutter app页面其实是由不同的图层（layers）组合（compsite）而成的。这些图层是以树的形式组织起来的，也就是我们在Flutter中见到的又一个比较重要的树：layer tree。

![](https://raw.githubusercontent.com/pacoblack/BlogImages/master/flutter_base/flutter6.webp)
上图是Flutter框架渲染机制的一个示意图。上方绿色方框里的内容可以认为就是本系列文章的关注所在。也就是Flutter框架渲染流水线运行的地方。可见，整个渲染流水线是运行在UI线程里的，以Vsync信号为驱动，在框架渲染完成之后会输出layer tree。layer tree被送入engine，engine会把layer tree调度到GPU线程，在GPU线程内合成（compsite）layer tree，然后由Skia 2D渲染引擎渲染后送入GPU显示。这里提到layer tree是因为我们即将要分析的渲染流水线绘制阶段最终输出就是这样的layer tree。所以绘制阶段并不是简单的调用paint()函数这么简单了，而是很多地方都涉及到layer tree的管理。

## layer
```Dart
abstract class Layer extends AbstractNode with DiagnosticableTreeMixin {

  @override
  ContainerLayer get parent => super.parent;

  Layer get nextSibling => _nextSibling;
  Layer _nextSibling;

  Layer get previousSibling => _previousSibling;
  Layer _previousSibling;
}
```
类Layer是个抽象类，和RenderObject一样，继承自AbstractNode。表明它也是个树形结构。属性parent代表其父节点，类型是ContainerLayer。这个类继承自Layer。只有ContainerLayer类型及其子类的图层可以拥有孩子，其他类型的Layer子类都是叶子图层。nextSibling和previousSibling表示同一图层的前一个和后一个兄弟节点，也就是图层孩子节点们是用双向链表存储的。
```Dart
class ContainerLayer extends Layer {
  Layer _firstChild;
  Layer _lastChild;

  void append(Layer child) {
    adoptChild(child);
    child._previousSibling = lastChild;
    if (lastChild != null)
      lastChild._nextSibling = child;
    _lastChild = child;
    _firstChild ??= child;
  }

  void _removeChild(Layer child) {
    if (child._previousSibling == null) {
      _firstChild = child._nextSibling;
    } else {
      child._previousSibling._nextSibling = child.nextSibling;
    }
    if (child._nextSibling == null) {
      _lastChild = child.previousSibling;
    } else {
      child.nextSibling._previousSibling = child.previousSibling;
    }
    child._previousSibling = null;
    child._nextSibling = null;
    dropChild(child);
  }

  void removeAllChildren() {
    Layer child = firstChild;
    while (child != null) {
      final Layer next = child.nextSibling;
      child._previousSibling = null;
      child._nextSibling = null;
      dropChild(child);
      child = next;
    }
    _firstChild = null;
    _lastChild = null;
  }

}
```
ContainerLayer增加了头和尾两个孩子节点属性，并提供了新增及删除孩子节点的方法。
ContainerLayer的子类有OffsetLayer,ClipRectLayer等等。
叶子类型的图层有TextureLayer,PlatformViewLayer, PerformanceOverlayLayer，PictureLayer等等，框架中大部分RenderObject的绘制的目标图层都是PictureLayer。

## flushCompositingBits()
这个方法是在drawFrame中被调用的，也是绘制需要进行的第一步。这个调用是用来更新render tree 中RenderObject的_needsCompositing标志位的。
通过方法markNeedsCompositingBitsUpdate()完成
```Dart
void markNeedsCompositingBitsUpdate() {
    if (_needsCompositingBitsUpdate)
      return;
    _needsCompositingBitsUpdate = true;
    if (parent is RenderObject) {
      final RenderObject parent = this.parent;
      if (parent._needsCompositingBitsUpdate)
        return;
      if (!isRepaintBoundary && !parent.isRepaintBoundary) {
        parent.markNeedsCompositingBitsUpdate();
        return;
      }
    }
    if (owner != null)
      owner._nodesNeedingCompositingBitsUpdate.add(this);
  }
```
这个调用会从当前节点往上找，把所有父节点的_needsCompositingBitsUpdate标志位都置位true。直到自己或者父节点的isRepaintBoundary为true。最后会把自己加入到PipelineOwner的_nodesNeedingCompositingBitsUpdate列表里面。而函数调用pipelineOwner.flushCompositingBits()正是用来处理这个列表的。

flushCompositingBits()源码如下：
```Dart
void flushCompositingBits() {

    _nodesNeedingCompositingBitsUpdate.sort((RenderObject a, RenderObject b) => a.depth - b.depth);
    for (RenderObject node in _nodesNeedingCompositingBitsUpdate) {
      if (node._needsCompositingBitsUpdate && node.owner == this)
        node._updateCompositingBits();
    }
    _nodesNeedingCompositingBitsUpdate.clear();
  }
```
首先把列表_nodesNeedingCompositingBitsUpdate按照节点在树中的深度排序。然后遍历调用node._updateCompositingBits().
_updateCompositingBits()做的事情是从当前节点往下找，如果某个子节点isRepaintBoundary为true或alwaysNeedsCompositing为true则设置_needsCompositing为true。子节点这个标志位为true的话，那么父节点的该标志位也会被设置为true。如果_needsCompositing发生了变化，那么会调用markNeedsPaint()通知渲染流水线本RenderObject需要重绘了。为啥要重绘呢？原因是`RenderObject`所在的图层(layer)可能发生了变化。

### RenderObject的标志位
>bool _needsCompositing：标志自身或者某个孩子节点有合成层（compositing layer）。如果当前节点需要合成，那么所有祖先节点也都需要合成。
bool _needsCompositingBitsUpdate：标志当前节点是否需要更新_needsCompositing。这个标志位由下方的markNeedsCompositingBitsUpdate()函数设置。
bool get isRepaintBoundary => false;：标志当前节点是否与父节点分开来重绘。当这个标志位为true的时候，父节点重绘的时候子节点不一定也需要重绘，同样的，当自身重绘的时候父节点不一定需要重绘。此标志位为true的RenderObject有render tree的根节点RenderView，有我们熟悉的RenderRepaintBoundary，TextureBox等。
bool get alwaysNeedsCompositing => false;：标志当前节点是否总是需要合成。这个标志位为true的话意味着当前节点绘制的时候总是会新开合成层（composited layer）。例如TextureBox, 以及我们熟悉的显示运行时性能的RenderPerformanceOverlay等。

## flushPaint()
函数flushPaint()处理的是之前加入到列表_nodesNeedingPaint里的节点。当某个RenderObject需要被重绘的时候会调用markNeedsPaint()

函数markNeedsPaint()首先做的是把自己的标志位_needsPaint设置为true。然后会向上查找最近的一个isRepaintBoundary为true的祖先节点。直到找到这样的节点，才会把这个节点加入到_nodesNeedingPaint列表中，也就是说，并不是任意一个需要重绘的RenderObject就会被加入这个列表，而是往上找直到找到最近的一个isRepaintBoundary为true才会放入这个列表，换句话说，这个列表里只有isRepaintBoundary为true这种类型的节点。也就是说重绘的起点是从“重绘边界”开始的。
```Dart
void flushPaint() {
  try {
    final List<RenderObject> dirtyNodes = _nodesNeedingPaint;
    _nodesNeedingPaint = <RenderObject>[];
    // Sort the dirty nodes in reverse order (deepest first).
    for (RenderObject node in dirtyNodes..sort((RenderObject a, RenderObject b) => b.depth - a.depth)) {
      if (node._needsPaint && node.owner == this) {
        if (node._layer.attached) {
          PaintingContext.repaintCompositedChild(node);
        } else {
          node._skippedPaintingOnLayer();
        }
      }
    }
  } finally {
    ...
  }
}
```
在处理需要重绘的节点的时候，会先给这些节点做个排序，这里需要注意的是，和之前flushLayout()里的排序不同，这里的排序是深度度深的节点在前。在循环体里，会判断当前节点的_layer属性是否处于attached的状态。如果_layer.attached为true的话调用PaintingContext.repaintCompositedChild(node);去做绘制，否则的话调用node._skippedPaintingOnLayer()将自身以及到上层绘制边界之间的节点的_needsPaint全部置为true。这样在下次_layer.attached变为true的时候会直接绘制。

从上述代码也可以看出，重绘边界相当于把Flutter的绘制做了分块处理，重绘的从上层重绘边界开始，到下层重绘边界为止，在此之间的RenderObject都需要重绘，而边界之外的就可能不需要重绘，这也是一个性能上的考虑，尽量避免不必要的绘制。所以如何合理安排RepaintBoundary是我们在做Flutter app的性能优化时候需要考虑的一个方向。
这里的_layer属性就是我们之前说的图层，这个属性只有绘制边界的RenderObject才会有值。一般的RenderObject这个属性是null。
```Dart
  static void _repaintCompositedChild(
    RenderObject child, {
    bool debugAlsoPaintedParent = false,
    PaintingContext childContext,
  }) {
    if (child._layer == null) {
      child._layer = OffsetLayer();
    } else {
      child._layer.removeAllChildren();
    }
    childContext ??= PaintingContext(child._layer, child.paintBounds);
    child._paintWithContext(childContext, Offset.zero);
    childContext.stopRecordingIfNeeded();
  }
```
函数_repaintCompositedChild()会先检查RenderObject的图层属性，为空则新建一个OffsetLayer实例。如果图层已经存在的话就把孩子清空。
如果没有PaintingContext的话会新建一个，然后让开始绘制。我们先来看一下PaintingContext这个类：
```Dart
class PaintingContext extends ClipContext {
  @protected
  PaintingContext(this._containerLayer, this.estimatedBounds)

  final ContainerLayer _containerLayer;

  final Rect estimatedBounds;

  PictureLayer _currentLayer;
  ui.PictureRecorder _recorder;
  Canvas _canvas;

  @override
  Canvas get canvas {
    if (_canvas == null)
      _startRecording();
    return _canvas;
  }

  void _startRecording() {
    _currentLayer = PictureLayer(estimatedBounds);
    _recorder = ui.PictureRecorder();
    _canvas = Canvas(_recorder);
    _containerLayer.append(_currentLayer);
  }

   void stopRecordingIfNeeded() {
    if (!_isRecording)
      return;
    _currentLayer.picture = _recorder.endRecording();
    _currentLayer = null;
    _recorder = null;
    _canvas = null;
  }
```
类PaintingContext字面意思是绘制上下文，其属性_containerLayer是容器图层，来自构造时的入参。也就是说PaintingContext是和容器图层关联的。接下来还有PictureLayer类型的_currentLayer属性, ui.PictureRecorder类型的_recorder属性和我们熟悉的Canvas类型的属性_canvas。函数_startRecording() 实例化了这几个属性。_recorder用来录制绘制命令，_canvas绑定一个录制器。最后，_currentLayer会作为子节点加入到_containerLayer中。有开始那么就会有结束，stopRecordingIfNeeded()用来结束当前绘制的录制。结束时会把绘制完毕的Picture赋值给当前的PictureLayer.picture。
有了PaintingContext以后，就可以调用RenderObject._paintWithContext()开始绘制了，这个函数会直接调用到我们熟悉的RenderObject.paint(context, offset)，我们知道函数paint()由RenderObject子类自己实现。从之前的源码分析我们知道绘制起点都是“绘制边界”。这里我们就拿我们熟悉的一个“绘制边界”，RenderRepaintBoundary，为例来走一下绘制流程，它的绘制函数的实现在RenderProxyBoxMixin类中：
```Dart
  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null)
      context.paintChild(child, offset);
  }
```
这个调用又回到了PaintingContext的paintChild()方法：
```Dart
  void paintChild(RenderObject child, Offset offset) {
    if (child.isRepaintBoundary) {
      stopRecordingIfNeeded();
      _compositeChild(child, offset);
    } else {
      child._paintWithContext(this, offset);
    }
  }
```
这里会检查子节点是不是绘制边界，如果不是的话，就是普通的绘制了，接着往下调用_paintWithContext()，继续往当前的PictureLayer上绘制。如果是的话就把当前的绘制先停掉。然后调用_compositeChild(child, offset);
```Dart
  void _compositeChild(RenderObject child, Offset offset) {
    if (child._needsPaint) {
      repaintCompositedChild(child, debugAlsoPaintedParent: true);
    }
    child._layer.offset = offset;
    appendLayer(child._layer);
  }
```
如果这个子绘制边界被标记为需要重绘的话，那么就调用repaintCompositedChild()来重新生成图层然后重绘。如果这个子绘制边界没有被标记为需要重绘的话，就跳过了重新生成图层和重绘。最后只需要把子图层加入到当前容器图层中就行了。
上面说的是子节点是绘制边界的时候的绘制流程，那如果子节点是普通的一个RenderObject呢？这里就拿Flutter app出错控件的绘制做个例子：
```Dart
void paint(PaintingContext context, Offset offset) {
    try {
      context.canvas.drawRect(offset & size, Paint() .. color = backgroundColor);
      double width;
      if (_paragraph != null) {
        // See the comment in the RenderErrorBox constructor. This is not the
        // code you want to be copying and pasting. :-)
        if (parent is RenderBox) {
          final RenderBox parentBox = parent;
          width = parentBox.size.width;
        } else {
          width = size.width;
        }
        _paragraph.layout(ui.ParagraphConstraints(width: width));

        context.canvas.drawParagraph(_paragraph, offset);
      }
    } catch (e) {
      // Intentionally left empty.
    }
  }
```
这看起来就像个正常的绘制了，我们会用来自PaintingContext的画布canvas来绘制矩形，绘制文本等等。从前面的分析也可以看出，这里的绘制都是在一个PictureLayer的图层上所做的。
至此 pipelineOwner.flushPaint();这个函数的调用就跑完了，通过分析我们可以知道，绘制工作其实主要是在这个函数中完成的。接下来我们再来看一下绘制流程的最后一个重要的函数调用：

## compositeFrame()
这里的renderView就是我们之前说的render tree的根节点。这个函数调用主要是把整个layer tree生成scene送到engine去显示。
```Dart
void compositeFrame() {
    try {
      final ui.SceneBuilder builder = ui.SceneBuilder();
      final ui.Scene scene = layer.buildScene(builder);
      if (automaticSystemUiAdjustment)
        _updateSystemChrome();
      _window.render(scene);
      scene.dispose();
    } finally {
      Timeline.finishSync();
    }
  }
```
ui.SceneBuilder()最终调用Native方法SceneBuilder_constructor。也就是说ui.SceneBuilder实例是由engine创建的。接下来就是调用layer.buildScene(builder)方法，这个方法会返回一个ui.Scene实例。由于方法compositeFrame()的调用者是renderView。所以这里这个layer是来自renderView的属性，我们前面说过只有绘制边界节点才有layer。所以可见render tree的根节点renderView也是一个绘制边界。那么这个layer是从哪里来的呢？在之前的初始化中我们提到过，框架初始化的过程中renderView会调度开天辟地的第一帧：
```Dart
void scheduleInitialFrame() {
    scheduleInitialLayout();
    scheduleInitialPaint(_updateMatricesAndCreateNewRootLayer());
    owner.requestVisualUpdate();
  }

  Layer _updateMatricesAndCreateNewRootLayer() {
    _rootTransform = configuration.toMatrix();
    final ContainerLayer rootLayer = TransformLayer(transform: _rootTransform);
    rootLayer.attach(this);
    return rootLayer;
  }

  void scheduleInitialPaint(ContainerLayer rootLayer) {
    _layer = rootLayer;
    owner._nodesNeedingPaint.add(this);
  }

```
在方法_updateMatricesAndCreateNewRootLayer()中，我们看到这里实例化了一个TransformLayer。TransformLayer继承自OffsetLayer。构造时需要传入Matrix4类型的参数transform。这个Matrix4其实和我们在Android中见到的Matrix是一回事。代表着矩阵变换。这里的transform来自我们之前讲过的ViewConfiguration，它就是把设备像素比例转化成了矩阵的形式。最终这个layer关联上了renderView。所以这里这个TransformLayer其实也是layer tree的根节点了。
回到我们的绘制流程。layer.buildScene(builder);这个调用我们自然是去TransformLayer里找了，但这个方法是在其父类OffsetLayer内，从这个调用开始就都是对图层进行操作，最终把layer tree转换为场景scene：
```dart
ui.Scene buildScene(ui.SceneBuilder builder) {
    List<PictureLayer> temporaryLayers;
    updateSubtreeNeedsAddToScene();
    addToScene(builder);
    final ui.Scene scene = builder.build();
    return scene;
  }
```
函数调用updateSubtreeNeedsAddToScene();会遍历layer tree来设置_subtreeNeedsAddToScene标志位，如果有任意子图层的添加、删除操作，则该子图层及其祖先图层都会被置上_subtreeNeedsAddToScene标志位。然后会调用addToScene(builder);
```dart
   @override
  ui.EngineLayer addToScene(ui.SceneBuilder builder, [ Offset layerOffset = Offset.zero ]) {
    _lastEffectiveTransform = transform;
    final Offset totalOffset = offset + layerOffset;
    if (totalOffset != Offset.zero) {
      _lastEffectiveTransform = Matrix4.translationValues(totalOffset.dx, totalOffset.dy, 0.0)
        ..multiply(_lastEffectiveTransform);
    }
    builder.pushTransform(_lastEffectiveTransform.storage);
    addChildrenToScene(builder);
    builder.pop();
    return null; // this does not return an engine layer yet.
  }
```
builder.pushTransform会调用到engine层。相当于告诉engine这里我要加一个变换图层。然后调用ddChildrenToScene(builder)将子图层加入场景中，完了还要把之前压栈的变换图层出栈。
```dart
void addChildrenToScene(ui.SceneBuilder builder, [ Offset childOffset = Offset.zero ]) {
    Layer child = firstChild;
    while (child != null) {
      if (childOffset == Offset.zero) {
        child._addToSceneWithRetainedRendering(builder);
      } else {
        child.addToScene(builder, childOffset);
      }
      child = child.nextSibling;
    }
  }
```
这就是遍历添加子图层的调用。主要还是逐层向下的调用addToScene()。这个方法不同的图层会有不同的实现，对于容器类图层而言，主要就是做三件事：1.添加自己图层的效果然后入栈，2.添加子图层，3. 出栈。
在所有图层都处理完成之后。回到renderView.compositeFrame()，可见最后会把处理完得到的场景通过_window.render(scene);调用送入engine去显示了。
至此渲染流水线的绘制(paint)阶段就算是跑完了。
等等，好像缺了点什么，在分析绘制的过程中我们看到有个主要的调用pipelineOwner.flushCompositingBits()是在更新render tree里节点的_needsCompositing标志位的。但是我们这都把流程说完了，貌似没有看到这个标志位在哪里用到啊。这个标志位肯定在哪里被用到了，否则我们费这么大劲更新有啥用呢？回去再研究一下代码......
这个标志位某些RenderObject在其paint()函数中会用到，作用呢，就体现在PaintingContext的这几个函数的调用上了：
```dart
  void pushClipRect(bool needsCompositing, Offset offset, Rect clipRect, PaintingContextCallback painter, { Clip clipBehavior = Clip.hardEdge }) {
    final Rect offsetClipRect = clipRect.shift(offset);
    if (needsCompositing) {
      pushLayer(ClipRectLayer(clipRect: offsetClipRect, clipBehavior: clipBehavior), painter, offset, childPaintBounds: offsetClipRect);
    } else {
      clipRectAndPaint(offsetClipRect, clipBehavior, offsetClipRect, () => painter(this, offset));
    }
  }

  void pushClipRRect(bool needsCompositing, Offset offset, Rect bounds, RRect clipRRect, PaintingContextCallback painter, { Clip clipBehavior = Clip.antiAlias }) {
    final Rect offsetBounds = bounds.shift(offset);
    final RRect offsetClipRRect = clipRRect.shift(offset);
    if (needsCompositing) {
      pushLayer(ClipRRectLayer(clipRRect: offsetClipRRect, clipBehavior: clipBehavior), painter, offset, childPaintBounds: offsetBounds);
    } else {
      clipRRectAndPaint(offsetClipRRect, clipBehavior, offsetBounds, () => painter(this, offset));
    }
  }


  void pushClipPath(bool needsCompositing, Offset offset, Rect bounds, Path clipPath, PaintingContextCallback painter, { Clip clipBehavior = Clip.antiAlias }) {
    final Rect offsetBounds = bounds.shift(offset);
    final Path offsetClipPath = clipPath.shift(offset);
    if (needsCompositing) {
      pushLayer(ClipPathLayer(clipPath: offsetClipPath, clipBehavior: clipBehavior), painter, offset, childPaintBounds: offsetBounds);
    } else {
      clipPathAndPaint(offsetClipPath, clipBehavior, offsetBounds, () => painter(this, offset));
    }
  }

  void pushTransform(bool needsCompositing, Offset offset, Matrix4 transform, PaintingContextCallback painter) {
    final Matrix4 effectiveTransform = Matrix4.translationValues(offset.dx, offset.dy, 0.0)
      ..multiply(transform)..translate(-offset.dx, -offset.dy);
    if (needsCompositing) {
      pushLayer(
        TransformLayer(transform: effectiveTransform),
        painter,
        offset,
        childPaintBounds: MatrixUtils.inverseTransformRect(effectiveTransform, estimatedBounds),
      );
    } else {
      canvas
        ..save()
        ..transform(effectiveTransform.storage);
      painter(this, offset);
      canvas
        ..restore();
    }
  }
```
needsCompositing作为这几个函数的入参，从代码可见其作用主要是控制这几种特殊的绘制操作的具体实现方式，如果needsCompositing为true的话，则会调用pushLayer，参数我们之前见过的各种图层
```Dart
  void pushLayer(ContainerLayer childLayer, PaintingContextCallback painter, Offset offset, { Rect childPaintBounds }) {
    stopRecordingIfNeeded();
    appendLayer(childLayer);
    final PaintingContext childContext = createChildContext(childLayer, childPaintBounds ?? estimatedBounds);
    painter(childContext, offset);
    childContext.stopRecordingIfNeeded();
  }

  @protected
  PaintingContext createChildContext(ContainerLayer childLayer, Rect bounds) {
    return PaintingContext(childLayer, bounds);
  }
```
流程基本上和我们之前看到的重绘的时候新增一个图层的操作是一样的。
而如果needsCompositing为false的话则走的是canvas的各种变换了。大家感兴趣的话可以去看一下源码，这里就不细说了。
