#!/usr/bin/env bash

set -e

stack exec site clean
stack exec site build

mkdir .deploy
cd .deploy
echo 'timhabermaas.com' > CNAME
git init
git remote add origin git@github.com:timhabermaas/timhabermaas.github.io.git

rsync -a ../_site/ .
git add .
git commit -m 'Publish'
git push -f origin master

cd .. && rm -rf .deploy
