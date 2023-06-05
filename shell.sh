#!/bin/sh

echo "进入脚本"

if [ ! -n "$1" ] ;then
    echo "you have not input commit messsage!"
    exit 0
else
    echo "开始部署hexo"
fi

hexo clean
hexo g
hexo d

git add .
git commit -m $1
git push origin hexo
