---
title: ffmpeg常用命令
toc: true
date: 2025-05-27 16:31:52
tags:
- ffmpeg
categories:
- ffmpeg
---
ffmpeg常用命令
 <!--more-->
 [官方地址](https://ffmpeg.org/ffmpeg.html#Description)

# 基本介绍
## Demuxer
一般通过 -i 选项创建 Demuxer，并将编码后的数据包发送到后续的decoder或muxer。
在其他文献中，Demuxer 有时被称为 splitters，因为它们的主要功能是将文件拆分成基本流（尽管有些文件只包含一个基本流）。

解复用器的示意图如下所示：
```
┌──────────┬───────────────────────┐
│ demuxer  │                       │ packets for stream 0
╞══════════╡ elementary stream 0   ├──────────────────────►
│          │                       │
│  global  ├───────────────────────┤
│properties│                       │ packets for stream 1
│   and    │ elementary stream 1   ├──────────────────────►
│ metadata │                       │
│          ├───────────────────────┤
│          │                       │
│          │     ...........       │
│          │                       │
│          ├───────────────────────┤
│          │                       │ packets for stream N
│          │ elementary stream N   ├──────────────────────►
│          │                       │
└──────────┴───────────────────────┘
     ▲
     │
     │ read from file, network stream,
     │     grabbing device, etc.
     │
```
## Decoders
Decoders 接收音频、视频或字幕基本流的编码（压缩）数据包，并将其解码为原始帧（视频为像素阵列，音频为 PCM）。解码器通常与 demuxer 中的基本流关联（并从其接收输入），但有时也可能独立存在（参见环回解码器）。
解码器的示意图如下：
```
          ┌─────────┐
 packets  │         │ raw frames
─────────►│ decoder ├────────────►
          │         │
          └─────────┘
```
## Filtergraphs(滤光器)
处理和转换原始音频或视频帧。FilterGraph 由一个或多个链接到滤镜图的独立滤镜组成。滤镜图有两种类型：简单滤镜图和复杂滤镜图，分别使用 -filter 和 -filter_complex 选项配置。
简单滤镜图与输出基本流相关联；它从 decoder 接收待过滤的输入，并将过滤后的输出发送到该输出流的 encoder.
- 简单的滤光器
A simple video filtergraph that performs deinterlacing (using the yadif deinterlacer) followed by resizing (using the scale filter) can look like this:
```
             ┌────────────────────────┐
             │  simple filtergraph    │
frames from  ╞════════════════════════╡ frames for
a decoder    │  ┌───────┐  ┌───────┐  │ an encoder
────────────►├─►│ yadif ├─►│ scale ├─►│────────────►
             │  └───────┘  └───────┘  │
             └────────────────────────┘
```
- 复杂滤光器
复杂滤镜图是独立的，不与任何特定的流关联。它可能有多个（或零个）输入，输入类型可能不同（音频或视频），每个输入都从 decoder 或另一个复杂滤镜图（complex filtergraph）的输出接收数据。它还有一个或多个输出，用于馈送 encoder 或另一个复杂滤镜图的输入。

以下示例图展示了一个包含 3 个输入和 2 个输出（均为视频）的复杂滤镜图：
```
          ┌─────────────────────────────────────────────────┐
          │               complex filtergraph               │
          ╞═════════════════════════════════════════════════╡
 frames   ├───────┐  ┌─────────┐      ┌─────────┐  ┌────────┤ frames
─────────►│input 0├─►│ overlay ├─────►│ overlay ├─►│output 0├────────►
          ├───────┘  │         │      │         │  └────────┤
 frames   ├───────┐╭►│         │    ╭►│         │           │
─────────►│input 1├╯ └─────────┘    │ └─────────┘           │
          ├───────┘                 │                       │
 frames   ├───────┐ ┌─────┐ ┌─────┬─╯              ┌────────┤ frames
─────────►│input 2├►│scale├►│split├───────────────►│output 1├────────►
          ├───────┘ └─────┘ └─────┘                └────────┤
          └─────────────────────────────────────────────────┘
```
## Encoders
接收原始音频、视频或字幕帧，并将其编码为编码数据包。编码（压缩）过程通常是有损的——它会降低流质量以减小输出；有些编码器是无损的，但代价是输出尺寸会大得多。视频或音频 encoder从某个滤镜图的输出接收输入
字幕编码器从解码器接收输入（因为字幕滤镜功能尚不支持）。每个编码器都与某个复用器的输出基本流相关联，并将其输出发送到该复用器。
编码器的示意图如下所示：
```
             ┌─────────┐
 raw frames  │         │ packets
────────────►│ encoder ├─────────►
             │         │
             └─────────┘
```

## Muxers
从编码器（转码路径）或直接从解复用器（流复制路径）接收基本流的编码数据包，对它们进行交织（interleave them）（当存在多个基本流时），并将生成的字节写入输出文件（或管道、网络流等）。
```
                       ┌──────────────────────┬───────────┐
 packets for stream 0  │                      │   muxer   │
──────────────────────►│  elementary stream 0 ╞═══════════╡
                       │                      │           │
                       ├──────────────────────┤  global   │
 packets for stream 1  │                      │properties │
──────────────────────►│  elementary stream 1 │   and     │
                       │                      │ metadata  │
                       ├──────────────────────┤           │
                       │                      │           │
                       │     ...........      │           │
                       │                      │           │
                       ├──────────────────────┤           │
 packets for stream N  │                      │           │
──────────────────────►│  elementary stream N │           │
                       │                      │           │
                       └──────────────────────┴─────┬─────┘
                                                    │
                     write to file, network stream, │
                         grabbing device, etc.      │
                                                    │
                                                    ▼
```
