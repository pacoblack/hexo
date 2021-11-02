---
title: github部署多个账号
toc: true
date: 2021-11-02 09:26:10
tags:
categories:
---
github 配置问题
<!--more-->
# Personal Token问题
之前一直遇到这个问题
>remote: Support for password authentication was removed on August 13, 2021. Please use a personal access token instead.
remote: Please see https://github.blog/2020-12-15-token-authentication-requirements-for-git-operations/ for more information.
fatal: Authentication failed for 'https://github.com/pacoblack/pacoblack.github.io.git/'
FATAL Something's wrong. Maybe you can find the solution here: https://hexo.io/docs/troubleshooting.html

官方的解释：https://github.blog/changelog/2021-08-12-git-password-authentication-is-shutting-down/

>As previously announced, starting on August 13, 2021, at 09:00 PST, we will no longer accept account passwords when authenticating Git operations on GitHub.com. Instead, token-based authentication (for example, personal access, OAuth, SSH Key, or GitHub App installation token) will be required for all authenticated Git operations.
Please refer to this blog post for instructions on what you need to do to continue using git operations securely.
Removal

大致意思是，密码验证于2021年8月13日不再支持，也就是不能再用密码方式去提交代码。可以使用 personal access token，OAuth,SSH 或者 GitHub App 进行访问

# SSH登陆
以前我们可以用rsa
```
ssh-keygen -t rsa -b 4096 -C "email"
```
但是rsa也出了问题
>2021年09月26日发布的OpenSSH 8.8中移除了对RSA-SHA1的支持
- 最新的git for windows 2.33.1版本已使用OpenSSH 8.8
- arch和manjaro等发行版的滚动升级比较激进，使用pacman -Syu就会升级所有软件到最新版本
- 此时的表现就是之前还可以正常使用，pacman -Syu或升级到git for windows 2.33.1之后使用git pull就出现fatal: 无法读取远程仓库的提示

如果您升级到OpenSSH 8.8或以上版本，则使用ssh推拉Gitee代码时会出现校验不通过的问题
>git@github.com: Permission denied (publickey).
fatal: Could not read from remote repository.
Please make sure you have the correct access rights
and the repository exists.

我们可以改成ed25519解决问题
```
ssh-keygen -t ed25519 -C "your_email@work.com"
```

## 生成特定的publicKey
```
Enter file in which to save the key (/Users/you/.ssh/id_ed25519): ~/.ssh/work_ed25519
```

## 在远程添加生成的公钥
将xxx.pub 中的内容复制到个人设置的SSH配置中

## 将私钥添加的本地的ssh-agent中
在本地的 ~/.ssh/config 文件中添加
```
Host example.com
  HostName github.com
  User 用户名
  AddKeysToAgent yes
  IgnoreUnknown UseKeychain
  IdentityFile ~/.ssh/work_ed25519
```

## 代码拉取
修改项目的Host
```
我们把
git@github.com:公司名/项目名.git
改成
git@work.com:公司名/项目名.git
即可
```
