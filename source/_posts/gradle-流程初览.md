---
title: gradle 流程初览
toc: true
date: 2020-12-10 14:25:49
tags:
- android
categories:
- android
---
在我们的android 工程中，经常要配置
```
buildscript {
    repositories {
        google()
        jcenter()
        maven {//添加repo本地仓库
            url uri("repo")
        }
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:3.4.0'
    }
}
```
然后在app或其他模块中加入
```
apply plugin: 'com.android.application'
```
或
```
apply plugin: 'com.android.library'
```
这些到底在干什么
<!--more-->
# 认识
首先我们构建的时候需要执行
```
./gradlew android-gradle-plugin-source:assembleDebug --console=plain
```
输出结果如下
>:android-gradle-plugin-source:preBuild UP-TO-DATE
:android-gradle-plugin-source:preDebugBuild
:android-gradle-plugin-source:compileDebugAidl
:android-gradle-plugin-source:compileDebugRenderscript
:android-gradle-plugin-source:checkDebugManifest
:android-gradle-plugin-source:generateDebugBuildConfig
:android-gradle-plugin-source:prepareLintJar UP-TO-DATE
:android-gradle-plugin-source:generateDebugResValues
:android-gradle-plugin-source:generateDebugResources
:android-gradle-plugin-source:mergeDebugResources
:android-gradle-plugin-source:createDebugCompatibleScreenManifests
:android-gradle-plugin-source:processDebugManifest
:android-gradle-plugin-source:splitsDiscoveryTaskDebug
:android-gradle-plugin-source:processDebugResources
:android-gradle-plugin-source:generateDebugSources
:android-gradle-plugin-source:javaPreCompileDebug
:android-gradle-plugin-source:compileDebugJavaWithJavac
:android-gradle-plugin-source:compileDebugNdk NO-SOURCE
:android-gradle-plugin-source:compileDebugSources
:android-gradle-plugin-source:mergeDebugShaders
:android-gradle-plugin-source:compileDebugShaders
:android-gradle-plugin-source:generateDebugAssets
:android-gradle-plugin-source:mergeDebugAssets
:android-gradle-plugin-source:transformClassesWithDexBuilderForDebug
:android-gradle-plugin-source:transformDexArchiveWithExternalLibsDexMergerForDebug
:android-gradle-plugin-source:transformDexArchiveWithDexMergerForDebug
:android-gradle-plugin-source:mergeDebugJniLibFolders
:android-gradle-plugin-source:transformNativeLibsWithMergeJniLibsForDebug
:android-gradle-plugin-source:transformNativeLibsWithStripDebugSymbolForDebug
:android-gradle-plugin-source:processDebugJavaRes NO-SOURCE
:android-gradle-plugin-source:transformResourcesWithMergeJavaResForDebug
:android-gradle-plugin-source:validateSigningDebug
:android-gradle-plugin-source:packageDebug
:android-gradle-plugin-source:assembleDebug

我们知道这些就是gradle task，其实这些task就是被注册在 `com.android.application` 或 `com.android.library` 中的
首先我们需要知道的是android的组件都是注册在xxxx.properties 中的，当我们在工程中查找 com.android.application.properties 时，我们就会发现里面注册的
`implementation-class=com.android.build.gradle.AppPlugin`,这个就是android gradle plugin的入口
接下来就简单了，我们开始追踪代码

# AppPlugin
`AppPlugin -> AbstractAppPlugin -> BasePlugin` 这个是AppPlugin 的继承结构，`AppPlugin` 和 `AbstractAppPlugin` 做的工作不多，包括 `registerModelBuilder()` `createTaskManager()` `createExtension()`, 主要工作还是在 `BasePlugin.apply()`中

## 初始化插件
- basePluginApply()
```java
...
// 检查版本
checkGradleVersion(project, getLogger(), projectOptions);
DependencyResolutionChecks.registerDependencyCheck(project, projectOptions);

project.getPluginManager().apply(AndroidBasePlugin.class);

checkPathForErrors();
// 检查 module 是否重名
checkModulesForErrors();

PluginInitializer.initialize(project);
ProfilerInitializer.init(project, projectOptions);
threadRecorder = ThreadRecorder.get();

// initialize our workers using the project's options.
// 初始化插件信息
Workers.INSTANCE.initFromProject(
       projectOptions,
       // possibly, in the future, consider using a pool with a dedicated size
       // using the gradle parallelism settings.
       ForkJoinPool.commonPool());

ProcessProfileWriter.getProject(project.getPath())
       .setAndroidPluginVersion(Version.ANDROID_GRADLE_PLUGIN_VERSION)
       .setAndroidPlugin(getAnalyticsPluginType())
       .setPluginGeneration(GradleBuildProject.PluginGeneration.FIRST)
       .setOptions(AnalyticsUtil.toProto(projectOptions));
...
```
- pluginSpecificApply()

## configProject

- 创建 AndroidBuilder和 DataBindingBuilder
```java
AndroidBuilder androidBuilder =
        new AndroidBuilder(
                project == project.getRootProject() ? project.getName() : project.getPath(),
                creator,
                new GradleProcessExecutor(project),
                new GradleJavaProcessExecutor(project),
                extraModelInfo.getSyncIssueHandler(),
                extraModelInfo.getMessageReceiver(),
                getLogger());
dataBindingBuilder = new DataBindingBuilder();
```
- 引入 java plugin 和 jacoco plugin
```java
project.getPlugins().apply(JavaBasePlugin.class);
```
- 添加了 BuildListener，在 buildFinished 回调里做缓存清理工作

## configureExtension
- 创建 AppExtension，也就是 build.gradle 里用到的 android {}
```java
extension =
        createExtension(
                project,
                projectOptions,
                globalScope,
                sdkHandler,
                buildTypeContainer,
                productFlavorContainer,
                signingConfigContainer,
                buildOutputs,
                sourceSetManager,
                extraModelInfo);
```
- 创建依赖管理，ndk管理，任务管理，variant管理
```java
taskManager =
        createTaskManager(
                globalScope,
                project,
                projectOptions,
                dataBindingBuilder,
                extension,
                sdkHandler,
                variantFactory,
                registry,
                threadRecorder);
```
- 注册新增配置的回调函数，包括 signingConfig，buildType，productFlavor
```java
// map the whenObjectAdded callbacks on the containers.
signingConfigContainer.whenObjectAdded(variantManager::addSigningConfig);

buildTypeContainer.whenObjectAdded(
        buildType -> {
            if (!this.getClass().isAssignableFrom(DynamicFeaturePlugin.class)) {
                SigningConfig signingConfig =
                        signingConfigContainer.findByName(BuilderConstants.DEBUG);
                buildType.init(signingConfig);
            } else {
                // initialize it without the signingConfig for dynamic-features.
                buildType.init();
            }
            variantManager.addBuildType(buildType);
        });

productFlavorContainer.whenObjectAdded(variantManager::addProductFlavor);
```
- 创建默认的 debug 签名，创建 debug 和 release 两个 buildType
```java
// create default Objects, signingConfig first as its used by the BuildTypes.
variantFactory.createDefaultComponents(
        buildTypeContainer, productFlavorContainer, signingConfigContainer);
```
```java
//ApplicationVariantFactory.java
@Override
public void createDefaultComponents(
        @NonNull NamedDomainObjectContainer<BuildType> buildTypes,
        @NonNull NamedDomainObjectContainer<ProductFlavor> productFlavors,
        @NonNull NamedDomainObjectContainer<SigningConfig> signingConfigs) {
    // must create signing config first so that build type 'debug' can be initialized
    // with the debug signing config.
    signingConfigs.create(DEBUG);
    buildTypes.create(DEBUG);
    buildTypes.create(RELEASE);
}
```

## createTasks
1. 创建不依赖 flavor 的 task
```java
public void createTasksBeforeEvaluate() {
    taskFactory.register(
            UNINSTALL_ALL,
            uninstallAllTask -> {
                uninstallAllTask.setDescription("Uninstall all applications.");
                uninstallAllTask.setGroup(INSTALL_GROUP);
            });

    taskFactory.register(
            DEVICE_CHECK,
            deviceCheckTask -> {
                deviceCheckTask.setDescription(
                        "Runs all device checks using Device Providers and Test Servers.");
                deviceCheckTask.setGroup(JavaBasePlugin.VERIFICATION_GROUP);
            });

    taskFactory.register(
            CONNECTED_CHECK,
            connectedCheckTask -> {
                connectedCheckTask.setDescription(
                        "Runs all device checks on currently connected devices.");
                connectedCheckTask.setGroup(JavaBasePlugin.VERIFICATION_GROUP);
            });

    // Make sure MAIN_PREBUILD runs first:
    taskFactory.register(MAIN_PREBUILD);

    taskFactory.register(
            EXTRACT_PROGUARD_FILES,
            ExtractProguardFiles.class,
            task -> task.dependsOn(MAIN_PREBUILD));

    taskFactory.register(new SourceSetsTask.CreationAction(extension));

    taskFactory.register(
            ASSEMBLE_ANDROID_TEST,
            assembleAndroidTestTask -> {
                assembleAndroidTestTask.setGroup(BasePlugin.BUILD_GROUP);
                assembleAndroidTestTask.setDescription("Assembles all the Test applications.");
            });

    taskFactory.register(new LintCompile.CreationAction(globalScope));

    // Lint task is configured in afterEvaluate, but created upfront as it is used as an
    // anchor task.
    createGlobalLintTask();
    configureCustomLintChecksConfig();

    globalScope.setAndroidJarConfig(createAndroidJarConfig(project));

    if (buildCache != null) {
        taskFactory.register(new CleanBuildCache.CreationAction(globalScope));
    }

    // for testing only.
    taskFactory.register(
            "resolveConfigAttr", ConfigAttrTask.class, task -> task.resolvable = true);
    taskFactory.register(
            "consumeConfigAttr", ConfigAttrTask.class, task -> task.consumable = true);
}
```
2. 创建构建 task
```java
// 所有的模块配置完成之后才执行 createAndroidTasks
project.afterEvaluate(
        CrashReporting.afterEvaluate(
                p -> {
                    sourceSetManager.runBuildableArtifactsActions();

                    threadRecorder.record(
                            ExecutionType.BASE_PLUGIN_CREATE_ANDROID_TASKS,
                            project.getPath(),
                            null,
                            this::createAndroidTasks);
                }));
```
具体的createAndroidTasks委托给了 `VariantManager.createAndroidTasks()`,会先通过 populateVariantDataList 生成 flavor 相关的数据结构，然后调用 createTasksForVariantData 创建 flavor 对应的 task。

- `populateVariantDataList` 先根据 flavor 和 dimension 创建对应的组合，存放在 flavorComboList 里，之后调用 createVariantDataForProductFlavors 创建对应的 VariantData。创建出来的 VariantData 都是 BaseVariantData 的子类，里面保存了一些 Task
```java
public abstract class BaseVariantData implements TaskContainer {
    private final GradleVariantConfiguration variantConfiguration;
    private VariantDependencies variantDependency;
    private final VariantScope scope;
    public Task preBuildTask;
    public Task sourceGenTask;
    public Task resourceGenTask; // 资源处理
    public Task assetGenTask;
    public CheckManifest checkManifestTask; // 检测manifest
    public AndroidTask<PackageSplitRes> packageSplitResourcesTask; // 打包资源
    public AndroidTask<PackageSplitAbi> packageSplitAbiTask;
    public RenderscriptCompile renderscriptCompileTask;
    public MergeResources mergeResourcesTask; // 合并资源
    public ManifestProcessorTask processManifest; // 处理 manifest
    public MergeSourceSetFolders mergeAssetsTask; // 合并 assets
    public GenerateBuildConfig generateBuildConfigTask; // 生成 BuildConfig
    public GenerateResValues generateResValuesTask;
    public Sync processJavaResourcesTask;
    public NdkCompile ndkCompileTask; // ndk 编译
    public JavaCompile javacTask;
    public Task compileTask;
    public Task javaCompilerTask; // java 文件编译
    // ...
}
```
 - `createTasksForVariantData` 创建完 variant 数据，就要给 每个 variantData 创建对应的 task，对应的 task 有 assembleXXXTask，prebuildXXX，generateXXXSource，generateXXXResources，generateXXXAssets，processXXXManifest 等等
```java
// 创建 assembleXXXTask
taskManager.createAssembleTask(variantData);
// 是一个抽象类，具体实现在 ApplicationTaskManager.createTasksForVariantScope()
taskManager.createTasksForVariantScope(variantScope);
```

```java
//ApplicationTaskManager.java
@Override
public void createTasksForVariantScope(@NonNull final VariantScope variantScope) {
    createAnchorTasks(variantScope);
    // 检测 manifest
    createCheckManifestTask(variantScope);

    handleMicroApp(variantScope);

    // Create all current streams (dependencies mostly at this point)
    createDependencyStreams(variantScope);

    // Add a task to publish the applicationId.
    createApplicationIdWriterTask(variantScope);

    taskFactory.register(new MainApkListPersistence.CreationAction(variantScope));
    createBuildArtifactReportTask(variantScope);

    // Add a task to process the manifest(s)
    createMergeApkManifestsTask(variantScope);

    // Add a task to create the res values
    createGenerateResValuesTask(variantScope);

    // Add a task to compile renderscript files.
    createRenderscriptTask(variantScope);

    // Add a task to merge the resource folders
    // 合并资源文件
    createMergeResourcesTask(
            variantScope,
            true,
            Sets.immutableEnumSet(MergeResources.Flag.PROCESS_VECTOR_DRAWABLES));

    // Add tasks to compile shader
    createShaderTask(variantScope);

    // Add a task to merge the asset folders
    createMergeAssetsTask(variantScope);

    // Add a task to create the BuildConfig class
    createBuildConfigTask(variantScope);

    // Add a task to process the Android Resources and generate source files
    createApkProcessResTask(variantScope);

    // Add a task to process the java resources
    createProcessJavaResTask(variantScope);

    // 处理 aidl
    createAidlTask(variantScope);

    // Add external native build tasks
    createExternalNativeBuildJsonGenerators(variantScope);
    createExternalNativeBuildTasks(variantScope);

    // Add a task to merge the jni libs folders
    createMergeJniLibFoldersTasks(variantScope);

    ...

    // Add data binding tasks if enabled
    createDataBindingTasksIfNecessary(variantScope, MergeType.MERGE);

    // Add a compile task
    createCompileTask(variantScope);

    createStripNativeLibraryTask(taskFactory, variantScope);


    if (variantScope.getVariantData().getMultiOutputPolicy().equals(MultiOutputPolicy.SPLITS)) {
        if (extension.getBuildToolsRevision().getMajor() < 21) {
            throw new RuntimeException(
                    "Pure splits can only be used with buildtools 21 and later");
        }

        createSplitTasks(variantScope);
    }


    TaskProvider<BuildInfoWriterTask> buildInfoWriterTask =
            createInstantRunPackagingTasks(variantScope);
    createPackagingTask(variantScope, buildInfoWriterTask);

    // Create the lint tasks, if enabled
    createLintTasks(variantScope);

    taskFactory.register(new FeatureSplitTransitiveDepsWriterTask.CreationAction(variantScope));

    createDynamicBundleTask(variantScope);
}

protected void createCompileTask(@NonNull VariantScope variantScope) {
    TaskProvider<? extends JavaCompile> javacTask = createJavacTask(variantScope);
    addJavacClassesStream(variantScope);
    setJavaCompilerTask(javacTask, variantScope);
    // 处理 Android Transform
    createPostCompilationTasks(variantScope);
}
```
