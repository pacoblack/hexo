---
title: Vue 入门学习
toc: true
date: 2019-10-23 10:46:38
tags:
- Vue
categories:
- 笔记
---
入门笔记
```
$ cd my-project
$ cnpm install
$ cnpm run dev
```
<!--more-->

# 构建过程
## package.json
```json
{
"scripts": {
   "dev": "webpack-dev-server --inline --progress --config build/webpack.dev.conf.js",
   "start": "npm run dev",
   "unit": "jest --config test/unit/jest.conf.js --coverage",
   "e2e": "node test/e2e/runner.js",
   "test": "npm run unit && npm run e2e",
   "lint": "eslint --ext .js,.vue src test/unit test/e2e/specs",
   "build": "node build/build.js"
 }
}
```

1. 运行`npm run dev`的时候执行的是build/webpack.dev.conf.js文件
2. 运行`npm run build`的时候执行的是build/build.js文件

所以当在命令行输入npm run dev时，主要做以下事情:

- 查找本地package.json中scripts是否配置了dev,并且验证启动命令是否正确
- 检查node及npm相关版本是否正确
- 引入相关webpack插件及配置
- 挂载代理服务器-proxyTable
- 启动监听端口port 默认8080
- 如果autoOpenBrowser配置为true则自动打开浏览器

首先是 `cnpm run dev`，这里最先执行 `build/build.js`
## build.js
```javascript
'use strict'
// 检查 node 和 npm 版本
require('./check-versions')()

process.env.NODE_ENV = 'production'

// 可以在终端显示spinner的插件
const ora = require('ora')

// 用于删除文件或文件夹的插件
const rm = require('rimraf')

// 用于处理文件路径的插件
const path = require('path')

// 用于在控制台输出带颜色字体的插件
const chalk = require('chalk')

// webpack 核心功能包
const webpack = require('webpack')

// 获取基本配置
const config = require('../config')
const webpackConfig = require('./webpack.prod.conf')

const spinner = ora('building for production...')
// 开启 loading 动画
spinner.start()

// 首先将整个dist文件夹以及里面的内容删除，删除完成后开始 webpack 构建打包
rm(path.join(config.build.assetsRoot, config.build.assetsSubDirectory), err => {
  if (err) throw err
  webpack(webpackConfig, (err, stats) => {
    spinner.stop()
    if (err) throw err
    // 执行webpack构建完成之后在终端输出构建完成的相关信息或者输出报错信息并退出程序
    process.stdout.write(stats.toString({
      colors: true,
      modules: false,
      children: false, // If you are using ts-loader, setting this to true will make TypeScript errors show up during build.
      chunks: false,
      chunkModules: false
    }) + '\n\n')

    if (stats.hasErrors()) {
      console.log(chalk.red('  Build failed with errors.\n'))
      process.exit(1)
    }

    console.log(chalk.cyan('  Build complete.\n'))
    console.log(chalk.yellow(
      '  Tip: built files are meant to be served over an HTTP server.\n' +
      '  Opening index.html over file:// won\'t work.\n'
    ))
  })
})
```
这里主要完成下面几件事
- 检查 node 和 npm 版本，引入插件和配置对象，也就是spinner.start之前的代码
- 构建 loading 动画
- 清理目标文件夹
- 编译 webpack
- 输出编译信息

## webpack.dev.conf.js
这里主要是开发环境下 webpack 的相关配置，在 package.json 中被加载
主要功能是：
- 合并基础 webpack 配置
- 创建 Source Maps
- 配置静态资源
- 加载 styleLoaders
- 模块热替换
- 挂载代理服务
- 启动服务器特定端口(8080) 等

## webpack.prod.conf.js
- 合并 webpack 基础配置
    - 检测环境
    - 加载 styleLoaders
    - 压缩 css， js 代码
- webpack-bundle 打包情况分析

## webpack.base.conf.js
vue-cli 的脚手架基础配置，是dev和prod两个文件抽离出来的公共代码，通过将dev和pro两个文件夹merge，可以实现不同环境中配置不同代码

## utils.js
```javascript
// 根据当前环境来配置 assetsSubDirectory
exports.assetsPath = function (_path) {
  const assetsSubDirectory = process.env.NODE_ENV === 'production'
    ? config.build.assetsSubDirectory
    : config.dev.assetsSubDirectory

  return path.posix.join(assetsSubDirectory, _path)
}

// 创建 cssLoaders
exports.cssLoaders = function (options) {
  options = options || {}

  const cssLoader = {
    loader: 'css-loader',
    options: {
      sourceMap: options.sourceMap
    }
  }

  const postcssLoader = {
    loader: 'postcss-loader',
    options: {
      sourceMap: options.sourceMap
    }
  }

  // 生成与 plugin 一起使用的 loader
  function generateLoaders (loader, loaderOptions) {
    const loaders = options.usePostCSS ? [cssLoader, postcssLoader] : [cssLoader]

    if (loader) {
      loaders.push({
        loader: loader + '-loader',
        options: Object.assign({}, loaderOptions, {
          sourceMap: options.sourceMap
        })
      })
    }

    // Extract CSS when that option is specified
    // (which is the case during production build)
    if (options.extract) {
      return ExtractTextPlugin.extract({
        use: loaders,
        fallback: 'vue-style-loader'
      })
    } else {
      return ['vue-style-loader'].concat(loaders)
    }
  }

  // https://vue-loader.vuejs.org/en/configurations/extract-css.html
  return {
    css: generateLoaders(),
    postcss: generateLoaders(),
    less: generateLoaders('less'),
    sass: generateLoaders('sass', { indentedSyntax: true }),
    scss: generateLoaders('sass'),
    stylus: generateLoaders('stylus'),
    styl: generateLoaders('stylus')
  }
}

// 创建 styleLoaders
exports.styleLoaders = function (options) {
  const output = []
  const loaders = exports.cssLoaders(options)

  for (const extension in loaders) {
    const loader = loaders[extension]
    output.push({
      test: new RegExp('\\.' + extension + '$'),
      use: loader
    })
  }

  return output
}

exports.createNotifierCallback = () => {
  const notifier = require('node-notifier')

  return (severity, errors) => {
    if (severity !== 'error') return

    const error = errors[0]
    const filename = error.file && error.file.split('!').pop()

    notifier.notify({
      title: packageConfig.name,
      message: severity + ': ' + error.name,
      subtitle: filename || '',
      icon: path.join(__dirname, 'logo.png')
    })
  }
}
```
代码的主要功能是：
- 配置静态资源路径
- 生成cssLoaders 用于加载.vue 中的样式
- 生成 styleLoaders 加载不在 .vue 文件中存在的样式文件

## vue-loader.conf.js
```javascript
const utils = require('./utils')
const config = require('../config')
const isProduction = process.env.NODE_ENV === 'production'
const sourceMapEnabled = isProduction
  ? config.build.productionSourceMap
  : config.dev.cssSourceMap

// 导出 vue-loader 配置
module.exports = {
  loaders: utils.cssLoaders({
    sourceMap: sourceMapEnabled,
    extract: isProduction
  }),
  cssSourceMap: sourceMapEnabled,
  cacheBusting: config.dev.cacheBusting,
  // 在模版编译的过程中，编译器可以将某些属性，如 src 转换为 require
  // 由于在模版中直接使用 src引用静态资源是会报错的，如<img src="/assets/images/a.png">
  transformToRequire: {
    video: ['src', 'poster'],
    source: 'src',
    img: 'src',
    image: 'xlink:href'
  }
}
```

接下来就是程序入口 main.js ->APP.vue, index.js -> HelloWorld.vue
