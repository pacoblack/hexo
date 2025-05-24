---
title: FFmpeg编译android记录
toc: true
date: 2025-05-23 11:16:05
tags:
 - Android
categories:
 - FFmpeg
---
 记录一下 ffmpeg 的过程
 <!--more-->
 1、下载ffmpeg ```git clone https://git.ffmpeg.org/ffmpeg.git```,切换到分支 release/7.0
 2、下载x264 ```git clone http://git.videolan.org/git/x264.git```
 3、创建x264编译脚本
 ```bash
 #!/bin/bash

# 设置 NDK 路径，修改为你的 NDK 实际安装位置
export NDK=/Users/gang/Library/Android/sdk/ndk/22.1.7171670
export TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64

# 设置目标架构和 API 级别
export API=34
export TARGET=aarch64-linux-android
export PREFIX=$(pwd)/x264_android # 输出目录

# 设置编译器和工具链
export AR=$TOOLCHAIN/bin/llvm-ar
export AS=$TOOLCHAIN/bin/llvm-as
export CC=$TOOLCHAIN/bin/$TARGET$API-clang
export CXX=$TOOLCHAIN/bin/$TARGET$API-clang++
export LD=$TOOLCHAIN/bin/ld
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export STRIP=$TOOLCHAIN/bin/llvm-strip
export NM=$TOOLCHAIN/bin/llvm-nm
export STRINGS=$TOOLCHAIN/bin/llvm-strings


# 配置 x264 编译选项
./configure \
    --prefix=$PREFIX \
    --disable-asm \
    --enable-static \
    --enable-pic \
	--host=aarch64-linux-android  \
    --cross-prefix=$TOOLCHAIN/bin/$TARGET$API- \
    --sysroot=$TOOLCHAIN/sysroot \
    --extra-cflags="-Os -fPIC" \

# 检查 configure 的输出日志
if [ $? -ne 0 ]; then
    echo "Configuration failed"
    exit 1
fi

# 编译和安装
make -j$(nproc)
if [ $? -ne 0 ]; then
    echo "Build failed"
    exit 1
fi

make install
if [ $? -ne 0 ]; then
    echo "Installation failed"
    exit 1
fi

echo "x264 has been successfully built and installed"
 ```
 4、创建ffmpeg编译脚本
 ```bash
 #!/bin/bash

# 设置NDK路径，修改为你的NDK实际安装位置
export NDK=/Users/gang/Library/Android/sdk/ndk/22.1.7171670
export TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64

# 设置目标架构和API级别
export API=34  # 根据你的需求选择合适的API级别
export TARGET=aarch64-linux-android
export PREFIX=$(pwd)/ffmpeg_android  # 输出目录

# 设置编译器和工具链
export AR=$TOOLCHAIN/bin/llvm-ar
export AS=$TOOLCHAIN/bin/llvm-as
export CC=$TOOLCHAIN/bin/$TARGET$API-clang
export CXX=$TOOLCHAIN/bin/$TARGET$API-clang++
export LD=$TOOLCHAIN/bin/ld
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export STRIP=$TOOLCHAIN/bin/llvm-strip
export NM=$TOOLCHAIN/bin/llvm-nm

# 设置x264 pkg-config 路径
export PKG_CONFIG_PATH=/home/zzh/work/x264/x264_android/lib/pkgconfig:$PKG_CONFIG_PATH

# 配置 FFmpeg 编译选项
echo "Configuring FFmpeg..."
./configure \
    --prefix=$PREFIX \
    --disable-static \
    --enable-shared \
    --enable-gpl \
    --enable-libx264 \
    --pkg-config="pkg-config --static" \
    --extra-ldflags="-L/home/zzh/work/x264/x264_android/lib" \
    --pkg-config-flags="--static" \
    --disable-doc \
    --disable-ffmpeg \
    --disable-ffplay \
    --disable-ffprobe \
    --disable-avdevice \
    --disable-symver \
    --disable-w32threads \
    --disable-muxer=sctp \
    --disable-demuxer=sctp \
    --disable-devices \
    --disable-postproc \
    --cross-prefix=$TOOLCHAIN/bin/$TARGET$API- \
    --target-os=android \
    --arch=aarch64 \
    --enable-cross-compile \
    --sysroot=$TOOLCHAIN/sysroot \
    --strip=$STRIP \
    --nm=$NM 2>&1 | tee configure.log

if [ $? -ne 0 ]; then
    echo "Configuration failed"
    exit 1
fi

# 编译和安装
echo "Building FFmpeg..."
make -j$(nproc) 2>&1 | tee build.log

if [ $? -ne 0 ]; then
    echo "Build failed"
    exit 1
fi

make install
if [ $? -ne 0 ]; then
    echo "Installation failed"
    exit 1
fi

echo "FFmpeg has been successfully built and installed"

 ```

**注意事项**
1、环境中安装了gcc、cmake等编译工具
2、${TOOLCHAIN} 要注意选择平台，linux、mac、windows不一样
3、api版本要对应ndk的版本，低版本没有高版本的sdk
4、输出目录x264在 x264_android，ffmpeg 在 ffmpeg_android

新脚本
```bash
#!/bin/bash
API=24
NDK=/path/to/ndk
TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64

# 核心编译参数（新增安全加固和性能优化）
COMMON_FLAGS="
--target-os=android \
--enable-cross-compile \
--enable-shared \
--disable-static \
--disable-programs \
--disable-doc \
--enable-gpl \
--enable-small \
--disable-symver \
--enable-neon \
--enable-asm \
--extra-cflags='-fPIC -O3 -fstack-protector-strong -march=armv8-a' \
--extra-ldflags='-Wl,--build-id=sha1 -Wl,--exclude-libs,ALL' \
--sysroot=$TOOLCHAIN/sysroot"

# 编译arm64-v8a（新增Vulkan支持）
./configure $COMMON_FLAGS \
    --arch=aarch64 \
    --cpu=armv8-a \
    --enable-vulkan \
    --cross-prefix=$TOOLCHAIN/bin/aarch64-linux-android- \
    --cc=$TOOLCHAIN/bin/aarch64-linux-android$API-clang \
    --prefix=./android/arm64-v8a

make clean && make -j$(nproc) && make install

```
