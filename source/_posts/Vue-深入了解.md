---
title: Vue-深入了解
toc: true
date: 2019-10-24 20:57:11
tags:
- Vue
categories:
- Vue
---
一些原理的东西
<!--more-->
# 生命周期
![Vue生命周期](https://raw.githubusercontent.com/pacoblack/BlogImages/master/vue/lifecycle.png)

# 使用模版

1. 节点内的值可以使用`双括号`引用 data 中的属性，并转换为文本，如果是 HTML 则需要 v-html 指令，如
`<p>Using v-html directive: <span v-html="rawHtml"></span></p>`
2. 指令是以 v- 开头，如`<a v-bind:[attributeName]="url"> ... </a>`, attributeName 会是不同的值，可以是data 属性的值，会在生成dom时产生影响，参数只有一个，如果是不合法的参数，这个属性不会被渲染出来
3. 属性可以添加修饰符，如`<form v-on:submit.prevent="onSubmit">...</form>`,以半角句号 . 指明的特殊后缀，用于指出一个指令应该以特殊方式绑定。例如，.prevent 修饰符告诉 v-on 指令对于触发的事件调用 event.preventDefault()
    - .stop
    - .prevent
    - .capture
    - .self
    - .once
    - .passive

# 计算属性
可以使用 methods 来替代 computed，效果上两个都是一样的，但是 computed 是基于它的依赖缓存，只有相关依赖发生改变时才会重新取值，多适用于数据监听。而使用 methods ，在重新渲染的时候，函数总会重新调用执行。

watch适合比较耗时的操作，比如网络异步请求，一个变量改变触发网络请求。watch可以看做一个onchange事件，computed可以看做几个变量的组合体。

# CSS和Style绑定
```html
<div v-bind:class="{ active: isActive, 'text-danger': hasError }"></div>
```
这个表示 class 是否可用取决于冒号后的布尔值，同时可以添加多个class

当在一个自定义组件上使用 class 属性时，这些 class 将被添加到该组件的根元素上面。这个元素上已经存在的 class 不会被覆盖。

注意：由于 JavaScript 的限制，Vue 不能检测以下变动：
1. 当你利用索引直接设置一个数组项时，例如：vm.items[indexOfItem] = newValue
2. 当你修改数组的长度时，例如：vm.items.length = newLength
3. Vue 不能检测对象属性的添加或删除

# 组件相关
自定义事件也可以用于创建支持 v-model 的自定义输入组件,其中：
`<input v-model="searchText">`
等价于：
```html
<input
  v-bind:value="searchText"
  v-on:input="searchText = $event.target.value"
/>
```
当用在组件上时，v-model 则会这样：
```html
<custom-input
  v-bind:value="searchText"
  v-on:input="searchText = $event"
></custom-input>
```
为了让它正常工作，这个组件内的 \<input\> 必须：

1. 将其 value 特性绑定到一个名叫 value 的 prop 上
2. 在其 input 事件被触发时，将新的值通过自定义的 input 事件抛出

写成代码之后是这样的：
```JavaScript
Vue.component('custom-input', {
  props: ['value'],
  template: `
    <input
      v-bind:value="value"
      v-on:input="$emit('input', $event.target.value)"
    >
  `
})
```
现在 v-model 就应该可以在这个组件上完美地工作起来了：
```HTML
<custom-input v-model="searchText"></custom-input>
```
