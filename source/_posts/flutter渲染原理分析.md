---
title: flutter渲染原理分析
toc: true
date: 2019-12-04 19:00:41
tags:
- flutter
- 原理分析
categories:
- flutter
- 原理分析
---
flutter UI 渲染原理
<!---more-->

# 控件库（Widgets）
Flutter的控件库提供了非常丰富的控件，包括最基本的文本、图片、容器、输入框和动画等等。在Flutter中“一切皆是控件”，通过组合、嵌套不同类型的控件，就可以构建出任意功能、任意复杂度的界面。它包含的最主要的几个类有：
```
// WidgetsFlutterBinding 是Flutter的控件框架和Flutter引擎的胶水层, 基于Flutter控件系统开发的程序都需要使用
class WidgetsFlutterBinding extends BindingBase with GestureBinding, ServicesBinding, SchedulerBinding,
            PaintingBinding, RendererBinding, WidgetsBinding { ... }

// Widget就是所有控件的基类，它本身所有的属性都是只读的。
abstract class Widget extends DiagnosticableTree { ... }

// StatelessWidget和StatefulWidget并不会直接影响RenderObject的创建，它们只负责创建对应的RenderObjectWidget
// StatelessElement和StatefulElement也是类似的功能。
abstract class StatelessWidget extends Widget { ... }
abstract class StatefulWidget extends Widget { ... }

// RenderObjectWidget所有的实现类则负责提供配置信息并创建具体的RenderObjectElement。
abstract class RenderObjectWidget extends Widget { ... }

// Element是Flutter用来分离控件树和真正的渲染对象的中间层，控件用来描述对应的element属性，控件重建后可能会复用同一个element。
abstract class Element extends DiagnosticableTree implements BuildContext { ... }
class StatelessElement extends ComponentElement { ... }
class StatefulElement extends ComponentElement { ... }

// RenderObjectElement持有真正负责布局、绘制和碰撞测试（hit test）的RenderObject对象。
abstract class RenderObjectElement extends Element { ... }
```
它们之间的关系如下图：
![image](https://upload-images.jianshu.io/upload_images/16327616-940826fdfb956056?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
- 如果控件的**属性**发生了变化（因为控件的属性是只读的，所以变化也就意味着重新创建了新的控件树），但是其树上每个节点的类型没有变化时，element树和render树可以完全重用原来的对象（因为element和render object的属性都是可变的）
- 如果控件树中的某个节点的**类型**发生了变化，则 element树和 render树中对应的节点也需要重新创建


# 渲染(Render)
render树创建完成后就会进入渲染阶段，在Flutter界面渲染过程分为三个阶段：布局、绘制、合成，**布局和绘制** 在Flutter框架中完成，**合成则交由引擎负责**。
![渲染过程](https://upload-images.jianshu.io/upload_images/16327616-d75ff50bb1f286dd?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

控件树中的每个控件通过实现`RenderObjectWidget.createRenderObject(BuildContext context)` → `RenderObject`方法来创建对应的不同类型的`RenderObject`对象，组成渲染对象树。因为Flutter极大地简化了布局的逻辑，所以整个布局过程中只需要 **深度遍历** 一次：
![image](https://upload-images.jianshu.io/upload_images/16327616-fbe8c021342ea448?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
render树中的每个对象都会在布局过程中 **接受父对象的Constraints参数，决定自己的大小**，然后父对象就可以按照自己的逻辑决定各个子对象的位置，完成布局过程。
**子对象不存储自己在容器中的位置**，所以在它的位置发生改变时并不需要重新布局或者绘制。子对象的位置信息存储在它**自己的parentData字段中**，但是该字段**由它的父对象负责维护**，自身并不关心该字段的内容。同时也因为这种简单的布局逻辑，Flutter可以在某些节点设置布局边界（Relayout boundary），即当边界内的任何对象发生重新布局时，不会影响边界外的对象，反之亦然.

布局完成后，渲染对象树中的每个节点都有了明确的尺寸和位置，Flutter会把所有对象绘制到 **不同的图层** 上：
![image](https://upload-images.jianshu.io/upload_images/16327616-31e69abd95ec9efb?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
因为绘制节点时也是 **深度遍历** ，可以看到第二个节点在绘制它的背景和前景不得不绘制在不同的图层上，因为第四个节点切换了图层（因为“4”节点是一个需要独占一个图层的内容，比如视频），而第六个节点也一起绘制到了红色图层。这样会导致第二个节点的前景（也就是“5”）部分需要重绘时，和它在逻辑上毫不相干但是处于同一图层的第六个节点也必须重绘。为了避免这种情况，Flutter提供了另外一个“重绘边界”的概念：在进入和走出重绘边界时，Flutter会强制 **切换新的图层**，这样就可以避免边界内外的互相影响。典型的应用场景就是ScrollView，当滚动内容重绘时，一般情况下其他内容是不需要重绘的。虽然重绘边界可以在任何节点手动设置，但是一般不需要我们来实现，Flutter提供的控件默认会在需要设置的地方自动设置。

# Framework
![framework](https://upload-images.jianshu.io/upload_images/16327616-fb0d37e3a5f34b12?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
Framework底层是Flutter引擎，引擎主要负责图形绘制（Skia）、文字排版（libtxt）和提供Dart运行时，引擎全部使用C++实现，Framework层使我们可以用Dart语言调用引擎的强大能力。
- Framework的最底层叫做Foundation，其中定义的大都是非常基础的、提供给其他所有层使用的工具类和方法。
- 绘制库（Painting）封装了Flutter Engine提供的绘制接口，主要是为了在绘制控件等固定样式的图形时提供更直观、更方便的接口，比如绘制缩放后的位图、绘制文本、插值生成阴影以及在盒子周围绘制边框等等。
- Animation是动画相关的类，提供了类似Android系统的ValueAnimator的功能，并且提供了丰富的内置插值器。
- Gesture提供了手势识别相关的功能，包括触摸事件类定义和多种内置的手势识别器。GestureBinding类是Flutter中处理手势的抽象服务类，继承自BindingBase类。Binding系列的类在Flutter中充当着类似于Android中的SystemService系列（ActivityManager、PackageManager）功能，每个Binding类都提供一个服务的单例对象，App最顶层的Binding会包含所有相关的Bingding抽象类。如果使用Flutter提供的控件进行开发，则需要使用WidgetsFlutterBinding，如果不使用Flutter提供的任何控件，而直接调用Render层，则需要使用RenderingFlutterBinding。
- 渲染库（Rendering）
    Flutter的控件树在实际显示时会转换成对应的渲染对象（RenderObject）树来实现布局和绘制操作。渲染库主要提供的功能类有：
```
// RendererBinding 渲染树和Flutter引擎的胶水层，负责管理帧重绘、窗口尺寸和渲染相关参数变化的监听。
abstract class RendererBinding extends BindingBase with ServicesBinding, SchedulerBinding, HitTestable { ... }

// RenderObject 渲染树中所有节点的基类，定义了布局、绘制和合成相关的接口。
abstract class RenderObject extends AbstractNode with DiagnosticableTreeMixin implements HitTestTarget { ... }

// RenderBox和其三个常用的子类RenderParagraph、RenderImage、RenderFlex则是具体布局和绘制逻辑的实现类。
abstract class RenderBox extends RenderObject { ... }
class RenderParagraph extends RenderBox { ... }
class RenderImage extends RenderBox { ... }
class RenderFlex extends RenderBox with ContainerRenderObjectMixin<RenderBox, FlexParentData>,
                                        RenderBoxContainerDefaultsMixin<RenderBox, FlexParentData>,
                                        DebugOverflowIndicatorMixin { ... }
```
