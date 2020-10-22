@echo off

set GIT_PATH="C:\Program Files\Git\bin\sh.exe"
set BRANCH = "origin/main"


%GIT_PATH% git branch --list -a --merged release/1.1.0 | sed 's/^..//;s/ .*//' | xargs git branch --list -a --no-merged origin/main


