#!/bin/sh


echo "进入脚本"

if [ ! -n "$1" ] ;then
    echo "you have not input commit messsage!"
    exit 0
else
    echo "the word you input is $1"
fi

echo "开始部署hexo"
hexo clean
hexo g
hexo d

git add .
git commit -m $1
git push origin hexo
