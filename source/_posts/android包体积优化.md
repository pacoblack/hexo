---
title: android包体积优化
toc: true
date: 2021-11-01 16:52:26
tags:
- android
categories:
- android
---
我们尝试缩小apk的体积
<!--more-->
# APK组成
- 代码相关：classes.dex
我们在项目中所编写的 java 文件，经过编译之后会生成一个 .class 文件，而这些所有的 .class 文件呢，它最终会经过 dx 工具编译生成一个 classes.dex。
- 资源相关：res、assets、编译后的二进制资源文件 resources.arsc 和 清单文件 等等。
res 和 assets 的不同在于 res 目录下的文件会在 .R 文件中生成对应的资源 ID，而 assets 不会自动生成对应的 ID，而是通过 AssetManager 类的接口来获取。此外，每当在 res 文件夹下放一个文件时，aapt 就会自动生成对应的 id 并保存在 .R 文件中，但 .R 文件仅仅只是保证编译程序不会报错，实际上在应用运行时，系统会根据 ID 寻找对应的资源路径，而 resources.arsc 文件就是用来记录这些 ID 和 资源文件位置对应关系 的文件。
- So 相关：lib 目录下的文件，这块文件的优化空间其实非常大。

此外，还有 META-INF，它存放了应用的 签名信息，其中主要有 3个文件：

- MANIFEST.MF：其中每一个资源文件都有一个对应的 SHA-256-Digest（SHA1) 签名，MANIFEST.MF 文件的 SHA256（SHA1） 经过 base64 编码的结果即为 CERT.SF 中的 SHA256（SHA1）-Digest-Manifest 值。
- CERT.SF：除了开头处定义的 SHA256（SHA1）-Digest-Manifest 值，后面几项的值是对 MANIFEST.MF 文件中的每项再次 SHA256（SHA1） 经过 base64 编码后的值。
- CERT.RSA：其中包含了公钥、加密算法等信息。首先，对前一步生成的 CERT.SF 使用了 SHA256（SHA1）生成了数字摘要并使用了 RSA 加密，接着，利用了开发者私钥进行签名。然后，在安装时使用公钥解密。最后，将其与未加密的摘要信息（MANIFEST.MF文件）进行对比，如果相符，则表明内容没有被修改。

# 分析工具
- ApkTool
`apktool d xxx.apk`
[官方文档](https://ibotpeaches.github.io/Apktool/install/)
or
`brew install apktool`
- AndroidStudio 直接查看
- android-classshark
[官方文档](https://github.com/google/android-classyshark)
打开 ClassShark.jar，拖动我们的 APK 到它的工作空间即可

# Dex介绍
Dex 是 Android 系统的可执行文件，包含 **应用程序的全部操作指令以及运行时数据**。因为 Dalvik 是一种针对嵌入式设备而特殊设计的 Java 虚拟机，所以 Dex 文件与标准的 Class 文件在结构设计上有着本质的区别。当 Java 程序被编译成 class 文件之后，还需要使用 **dx 工具将所有的 class 文件整合到一个 dex 文件中**，这样 dex 文件就将原来每个 class 文件中都有的共有信息合成了一体，这样做的目的是 保证其中的每个类都能够共享数据，这在一定程度上 降低了信息冗余，同时也使得 文件结构更加紧凑。与传统 jar 文件相比，Dex 文件的大小能够缩减 50% 左右。关于 Class 文件与 Dex 文件的结果对比图如下所示：
![对比](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/493a202586fe4ee3825813f88b67b684~tplv-k3u1fbpfcp-watermark.awebp)
[dalvik官方文档](https://source.android.com/devices/tech/dalvik)

# D8 与 R8 优化
## D8 优化
D8 的 优化效果 总的来说可以归结为如下 四点：
1）、Dex的编译时间更短。
2）、.dex文件更小。
3）、D8 编译的 .dex 文件拥有更好的运行时性能。
4）、包含 Java 8 语言支持的处理。

开启 D8只需在 Android Studio 3.0 的 gradle.properties 文件中新增:
```
android.enableD8 = true
```
Android Studio 3.1 或之后的版本 D8 将会被作为默认的 Dex 编译器。

## R8优化
R8 是 Proguard 压缩与优化部分的替代品，并且它仍然使用与 Proguard 一样的 keep 规则。如果我们仅仅想在 Android Studio 中使用 R8，当我们在 build.gradle 中打开混淆的时候，R8 就已经默认集成进 Android Gradle plugin 中了。
如果我们当前使用的是 Android Studio 3.4 或 Android Gradle 插件 3.4.0 及其更高版本，R8 会作为默认编译器。否则，我们 必须要在 gradle.properties 中配置如下代码让 App 的混淆去支持 R8，如下所示：
```
android.enableR8=true
android.enableR8.libraries=true
```
>R8 与混淆相比的优势
ProGuard 和 R8 都应用了基本名称混淆：它们 都使用简短，无意义的名称重命名类，字段和方法。他们还可以 删除调试属性。但是，R8 在 inline 内联容器类中更有效，并且在删除未使用的类，字段和方法上则更具侵略性。例如，R8 本身集成在 ProGuard V6.1.1 版本中，在压缩 apk 的大小方面，与 ProGuard 的 8.5％ 相比，使用 R8 apk 尺寸减小了约 10％。并且，随着 Kotlin 现在成为 Android 的第一语言，R8 进行了 ProGuard 尚未提供的一些 Kotlin 的特定的优化。
从表面上看，ProGuard 和 R8 非常相似。它们都使用相同的配置，因此在它们之间进行切换很容易。放大来看的话，它们之间也存在一些差异。R8 能更好地内联容器类，从而避免了对象分配。但是 ProGuard 也有其自身的优势，具体有如下几点：
1）、ProGuard 在将枚举类型简化为原始整数方面会更加强大。它还传递常量方法参数，这通常对于使用应用程序的特定设置调用的通用库很有用。ProGuard  的多次优化遍历通常可以产生一系列优化。例如，第一遍可以传递一个常量方法参数，以便下一遍可以删除该参数并进一步传递该值。删除日志代码时，多次传递的效果尤其明显。ProGuard 在删除所有跟踪（包括组成日志消息的字符串操作）方面更有效。
2）、ProGuard 中应用的模式匹配算法可以识别和替换短指令序列，从而提高代码效率并为更多优化打开了机会。在优化遍历的顺序中，尤其是数学运算和字符串运算可从中受益。
3、最后，ProGuard 具有独特的能力来优化使用 GSON 库将对象序列化或反序列化为 JSON 的代码。该库严重依赖反射，这很方便，但效率低下。而 ProGuard  的优化功能可以 通过更高效，直接的访问方式 来代替它。

# 优化策略
## Dex 分包优化
当我们的 APK 过大时，Dex 的方法数就会超过65536个，因此，必须采用 mutildex 进行分包，但是此时每一个 Dex 可能会调用到其它 Dex 中的方法，这种 跨 Dex 调用的方式会造成许多冗余信息，具体有如下两点：
1）、多余的 method id：跨 Dex 调用会导致当前dex保留被调用dex中的方法id，这种冗余会导致每一个dex中可以存放的class变少，最终又会导致编译出来的dex数量增多，而dex数据的增加又会进一步加重这个问题。
2)、其它跨dex调用造成的信息冗余：除了需要多记录被调用的method id之外，还需多记录其所属类和当前方法的定义信息，这会造成 string_ids、type_ids、proto_ids 这几部分信息的冗余。

为了减少跨 Dex 调用的情况，我们必须尽量将有调用关系的类和方法分配到同一个 Dex 中。但是各个类相互之间的调用关系是非常复杂的，所以很难做到最优的情况。

## ReDex
ReDex 的 CrossDexDefMinimizer 类分析了类之间的调用关系，并 使用了贪心算法去计算局部的最优解（编译效果和dex优化效果之间的某一个平衡点）。使用 "InterDexPass" 配置项可以把互相引用的类尽量放在同个 Dex，增加类的 pre-verify，以此提升应用的冷启动速度。
1. 配置环境
```
//Step1.安装xcode
xcode-select --install

//Step2.使用 homebrew 安装 redex 项目使用到的依赖库
brew install autoconf automake libtool python3
brew install boost jsoncpp

//Step3.从 Github 上获取 ReDex 的源码并切换到 redex 目录下
git clone https://github.com/facebook/redex.git
cd redex

//Step4.使用 autoconf 和 make 去构建 ReDex
# 如果你使用的是 gcc, 请使用 gcc-5
autoreconf -ivf && ./configure && make -j4
sudo make install
```
2. 配置Config
在 Redex 在运行的时候，它是根据 redex/config/default.config 这个配置文件中的通道 passes 中添加不同的优化项来对 APK 的 Dex 进行处理的，我们可以参考 redex/config/default.config 这个默认的配置，里面的 passes 中不同的配置项都有特定的优化。为了优化 App 的包体积，我们再加上 interdex_stripdebuginfo.config 中的配置项去删除 debugInfo 和减少跨 Dex 调用的情况，最终的 interdex_stripdebuginfo.config 配置代码 如下所示：
```
{
    "redex" : {
        "passes" : [
            "StripDebugInfoPass",
            "InterDexPass",
            "RegAllocPass"
        ]
    },
    "StripDebugInfoPass" : {
        "drop_all_dbg_info" : false,
        "drop_local_variables" : true,
        "drop_line_numbers" : false,
        "drop_src_files" : false,
        "use_whitelist" : false,
        "cls_whitelist" : [],
        "method_whitelist" : [],
        "drop_prologue_end" : true,
        "drop_epilogue_begin" : true,
        "drop_all_dbg_info_if_empty" : true
    },
    "InterDexPass" : {
        "minimize_cross_dex_refs": true,
        "minimize_cross_dex_refs_method_ref_weight": 100,
        "minimize_cross_dex_refs_field_ref_weight": 90,
        "minimize_cross_dex_refs_type_ref_weight": 100,
        "minimize_cross_dex_refs_string_ref_weight": 90
    },
    "RegAllocPass" : {
        "live_range_splitting": false
    },
    "string_sort_mode" : "class_order",
    "bytecode_sort_mode" : "class_order"
}
```
3. 执行优化命令
```
ANDROID_SDK=/Users/quchao/Library/Android/sdk redex --sign -s wan-android-key.jks -a wanandroid -p wanandroid -c ~/Desktop/interdex_stripdebuginfo.config -P app/proguard-rules.pro -o ~/Desktop/app-release-proguardwithr8-stripdebuginfo-interdex.apk ~/Desktop/app-release-proguardwithr8.apk
```
其中
>--sign：对生成的apk进行签名。
-s：配置应用的签名文件。
-a: 配置应用签名的 key_alias。
-p：配置应用签名的 key_password。
-c：指定 redex 进行 Dex 处理时需要依据的 CONFIG 配置文件。
-o：指定生成 APK 的全路径。

##  XZUtils
[官方文档](https://tukaani.org/xz/)
XZ Utils 是具有高压缩率的免费通用数据压缩软件，它同 7-Zip 一样，都是 LZMA Utils 的后继产品，内部使用了 LZMA/LZMA2 算法。LZMA 提供了高压缩比和快速解压缩，因此非常适合嵌入式应用。LZMA 的 主要功能 如下：
1）、压缩速度：在3 GHz双核CPU上为3 MB / s。
2）、减压速度：在现代3 GHz CPU（Intel，AMD，ARM）上为20-50 MB / s。在简单的1 GHz RISC - CPU（ARM，MIPS，PowerPC）上为5-15 MB / s。
3）、解压缩的较小内存要求：8-32 KB + DictionarySize。
4）、用于解压缩的代码大小：2-8 KB（取决于速度优化）。

相对于典型的压缩文件而言，XZ Utils 的输出比 gzip 小 30％，比 bzip2 小 15％。在 FaceBook 的 App 中就使用了 Dex 压缩 的方式，而且它 将 Dex 压缩后的文件都放在了 assets 目录中，如下图所示：
![](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/a19bf988566e494693a2413a71e363dd~tplv-k3u1fbpfcp-watermark.awebp)

我们先看到上图中的 classes.dex，其中仅包含了启动时要用到的类，这样可以为 Dex 压缩文件 secondary.dex.jar.xzs 的解压争取时间。
此外，在 secondary.dex.jar.xzs 文件的下面，我们注意到，有一系列的 secondary-x.dex.jar.xzs.tmp~.meta 文件，它保存了压缩前每一个 Dex 文件的映射元数据信息，在应用首次启动解压的时候我们还需要用到它。
尽管 classes.dex 为首次启动解压 Dex 压缩文件争取了时间，但是由于文件太大，在低端机上的解压时间可能会有 3~5s。
而且，当 Dex  非常多的时候会增加应用的安装时间，如果还使用了压缩 Dex 的方式，那么首次生成 ODEX 的时间可能就会超过1分钟。为了解决这个问题，Facebook 使用了 oatmeal 这套工具去 根据 ODEX 文件的格式，自己生成了一个 ODEX 文件。而在 正常的流程 下，系统会使用 fork 子进程的方式去处理 dex2oat 的过程。
但是，oatmeal 采用了 代理 dex2oat 省去 fork 进程所带来耗时 的这种方式，如果在1个 10MB 的 Dex，可以将 dex2oat 的耗时降至 100ms，而在 Android 5.0 上生成一个 ODEX 的耗时大约在 10 秒以上，在 Android 8.0 使用 speed 模式也需要 1 秒左右的时间。但是由于 每个 Android 系统版本的 ODEX 格式都有一些差异，oatmeal  需要分版本适配，因此 Dex 压缩的方案我们可以先压压箱底。

## 三方库处理
精简功能相同的三方库，去掉功能重复的库

## 移除无用代码
使用 Lint 检测无效代码
```
-> 点击菜单栏 Analyze
-> Run Inspection by Name
-> unused declaration
-> Moudule ‘app’
-> OK
```
##  优化Java access 方法
为了能提供内部类和其外部类直接访问对方的私有成员的能力，又不违反封装性要求，Java 编译器在编译过程中自动生成 package 可见性的静态 access$xxx 方法，并且在需要访问对方私有成员的地方改为调用对应的 access 方法。
- 在 ReDex 中提供了  access-marking 这个功能去除代码中的 Access 方法，
- 在 ReDex 还有 type-erasure 的功能，它与 access-marking 的优化效果一样，不仅能减少包大小，也能提升 App 的启动速度。
更加推荐 ByteX 的 access_inline 插件
### ByteX
https://github.com/bytedance/ByteX
除了 access_inlie 之外，在 ByteX 中还有 四个 很实用的代码优化 Gradle 插件可以帮助我们有效减小 Dex 文件的大小：
1、编译期间内联常量字段：const_inline。
2、编译期间移除多余赋值代码：field_assign_opt。
3、编译期间移除 Log 代码：method_call_opt。
4、编译期间内联 Get / Set 方法：getter-setter-inline-plugin。

## 冗余资源优化
APK 的资源主要包括图片、XML，与冗余代码一样，它也可能遗留了很多旧版本当中使用而新版本中不使用的资源，这点在快速开发的 App 中更可能出现。我们可以通过点击右键，选中 Refactor，然后点击 Remove Unused Resource => preview 可以预览找到的无用资源，点击 Do Refactor 可以去除冗余资源。

## 重复资源优化
每个业务团队都会为自己的 资源文件名添加前缀。这样就导致了这些资源文件虽然 内容相同，但因为 名称的不同而不能被覆盖，最终都会被集成到 APK 包中。这里，我们还是可以 在 Android 构建工具执行 `package${flavorName}Task` 之前通过修改 Compiled Resources 来实现重复资源的去除，具体放入实现原理可细分为如下三个步骤：
1）、首先，通过资源包中的每个ZipEntry的CRC-32 checksum来筛选出重复的资源。
2）、然后，通过android-chunk-utils修改resources.arsc，把这些重复的资源都重定向到同一个文件上。
3）、最后，把其它重复的资源文件从资源包中删除，仅保留第一份资源。

具体的实现代码如下所示：
```
variantData.outputs.each {
    def apFile = it.packageAndroidArtifactTask.getResourceFile();

    it.packageAndroidArtifactTask.doFirst {
        def arscFile = new File(apFile.parentFile, "resources.arsc");
        JarUtil.extractZipEntry(apFile, "resources.arsc", arscFile);

        def HashMap<String, ArrayList<DuplicatedEntry>> duplicatedResources = findDuplicatedResources(apFile);

        removeZipEntry(apFile, "resources.arsc");

        if (arscFile.exists()) {
            FileInputStream arscStream = null;
            ResourceFile resourceFile = null;
            try {
                arscStream = new FileInputStream(arscFile);

                resourceFile = ResourceFile.fromInputStream(arscStream);
                List<Chunk> chunks = resourceFile.getChunks();

                HashMap<String, String> toBeReplacedResourceMap = new HashMap<String, String>(1024);

                // 处理arsc并删除重复资源
                Iterator<Map.Entry<String, ArrayList<DuplicatedEntry>>> iterator = duplicatedResources.entrySet().iterator();
                while (iterator.hasNext()) {
                    Map.Entry<String, ArrayList<DuplicatedEntry>> duplicatedEntry = iterator.next();

                    // 保留第一个资源，其他资源删除掉
                    for (def index = 1; index < duplicatedEntry.value.size(); ++index) {
                        removeZipEntry(apFile, duplicatedEntry.value.get(index).name);

                        toBeReplacedResourceMap.put(duplicatedEntry.value.get(index).name, duplicatedEntry.value.get(0).name);
                    }
                }

                for (def index = 0; index < chunks.size(); ++index) {
                    Chunk chunk = chunks.get(index);
                    if (chunk instanceof ResourceTableChunk) {
                        ResourceTableChunk resourceTableChunk = (ResourceTableChunk) chunk;
                        StringPoolChunk stringPoolChunk = resourceTableChunk.getStringPool();
                        for (def i = 0; i < stringPoolChunk.stringCount; ++i) {
                            def key = stringPoolChunk.getString(i);
                            if (toBeReplacedResourceMap.containsKey(key)) {
                                stringPoolChunk.setString(i, toBeReplacedResourceMap.get(key));
                            }
                        }
                    }
                }

            } catch (IOException ignore) {
            } catch (FileNotFoundException ignore) {
            } finally {
                if (arscStream != null) {
                    IOUtils.closeQuietly(arscStream);
                }

                arscFile.delete();
                arscFile << resourceFile.toByteArray();

                addZipEntry(apFile, arscFile);
            }
        }
    }
}
```

## 图片压缩
我们可以 使用 [McImage](https://github.com/smallSohoSolo/McImage/blob/master/README-CN.md)、[TinyPngPlugin](https://github.com/Deemonser/TinyPngPlugin) 来对图片进行自动化批量压缩。但是，需要注意的是，在 Android 的构建流程中，AAPT 会使用内置的压缩算法来优化 `res/drawable/` 目录下的 PNG 图片，但这可能会导致本来已经优化过的图片体积变大，因此，可以通过在 build.gradle 中 设置 cruncherEnabled 来禁止 AAPT 来优化 PNG 图片，代码如下所示：
```
aaptOptions {
    cruncherEnabled = false
}
```
此外，我们还要注意对图片格式的选择，对于我们普遍使用更多的 png 或者是 jpg 格式来说，相同的图片转换为 webp 格式之后会有大幅度的压缩。对于 png 来说，它是一个无损格式，而 jpg 是有损格式。jpg 在处理颜色图片很多时候根据压缩率的不同，它有时候会去掉我们肉眼识别差距比较小的颜色，但是 png 会严格地保留所有的色彩。所以说，在图片尺寸大，或者是色彩鲜艳的时候，png 的体积会明显地大于 jpg。

## 图片格式选择
VD（纯色icon）->WebP（非纯色icon）->Png（更好效果） ->jpg（若无alpha通道）

矢量图形在 Android 中表示为 VectorDrawable 对象。它 仅仅需100字节的文件即可以生成屏幕大小的清晰图像，但是，Android 系统渲染每个 VectorDrawable 对象需要大量的时间，而较大的图像需要更长的时间。 因此，建议 只有在显示纯色小 icon 时才考虑使用矢量图形。

## 资源混淆
https://github.com/shwenzhang/AndResGuard/blob/master/README.zh-cn.md

1、首先，我们在项目的根 build.gradle 文件下加入下面的插件依赖：
```
classpath 'com.tencent.mm:AndResGuard-gradle-plugin:1.2.17'
```
2、然后，在项目 module 下的 build.gradle 文件下引入其插件：
```
apply plugin: 'AndResGuard'
```
3、接着，加入 AndroidResGuard 的配置项，如下是默认设置好的配置：
```
andResGuard {
    // mappingFile = file("./resource_mapping.txt")
    mappingFile = null
    use7zip = true
    useSign = true
    // 打开这个开关，会keep住所有资源的原始路径，只混淆资源的名字
    keepRoot = false
    // 设置这个值，会把arsc name列混淆成相同的名字，减少string常量池的大小
    fixedResName = "arg"
    // 打开这个开关会合并所有哈希值相同的资源，但请不要过度依赖这个功能去除去冗余资源
    mergeDuplicatedRes = true
    whiteList = [
        // for your icon
        "R.drawable.icon",
        // for fabric
        "R.string.com.crashlytics.*",
        // for google-services
        "R.string.google_app_id",
        "R.string.gcm_defaultSenderId",
        "R.string.default_web_client_id",
        "R.string.ga_trackingId",
        "R.string.firebase_database_url",
        "R.string.google_api_key",
        "R.string.google_crash_reporting_api_key"
    ]
    compressFilePattern = [
        "*.png",
        "*.jpg",
        "*.jpeg",
        "*.gif",
    ]
    sevenzip {
        artifact = 'com.tencent.mm:SevenZip:1.2.17'
        //path = "/usr/local/bin/7za"
    }

    /**
    * 可选： 如果不设置则会默认覆盖assemble输出的apk
    **/
    // finalApkBackupPath = "${project.rootDir}/final.apk"

    /**
    * 可选: 指定v1签名时生成jar文件的摘要算法
    * 默认值为“SHA-1”
    **/
    // digestalg = "SHA-256"
}
```
4、最后，我们点击右边的项目 `module/Tasks/andresguard/resguardRelease` Task 即可生成资源混淆过的 APK。

### AndResGuard 的资源混淆原理
资源混淆工具主要是通过 短路径的优化，以达到 减少  resources.arsc、metadata 签名文件以及 ZIP 文件大小 的效果，其效果分别如下所示：
1）、resources.arsc：它记录了资源文件的名称与路径，使用混淆后的短路径  res/s/a，可以减少文件的大小。
2）、metadata 签名文件：签名文件 MANIFEST.MF 与 CERT.SF 需要记录所有文件的路径以及它们的哈希值，使用短路径可以减少这两个文件的大小。
3）、ZIP 文件：ZIP 文件格式里面通过其索引记录了每个文件 Entry 的路径、压缩算法、CRC、文件大小等等信息。短路径的优化减少了记录文件路径的字符串大小。

### AndResGuard 的极限压缩原理
AndResGuard 使用了 7-Zip 的大字典优化，APK 的 整体压缩率可以提升 3% 左右，并且，它还支持针对 resources.arsc、PNG、JPG 以及 GIF 等文件进行强制压缩（在编译过程中，这些文件默认不会被压缩）。那么，为什么 Android 系统不会去压缩这些文件呢？主要基于以下 两点原因：
1）、压缩效果不明显：上述格式的文件大部分已经被压缩过，因此，重新做 Zip 压缩效果并不明显。比如 重新压缩 PNG 和 JPG 格式只能减少 3%～5% 的大小。
2）、基于读取时间和内存的考虑：针对于 没有进行压缩的文件，系统可以使用 mmap 的方式直接读取，而不需要一次性解压并放在内存中。

## R Field 的内联优化
直接使用 ByteX shrink_r_class 插件，它不仅可以在编译阶段对 R 文件常量进行内联，而且还可以 针对 App 中无用 Resource 和无用 assets 的资源进行检查。

参考资料：https://juejin.cn/post/6844904103131234311#heading-47
