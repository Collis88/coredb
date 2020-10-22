@echo off

set /p git_command="status"

for /d %%i in (%cd%*) do (
    echo ****************************************

    echo "%%i"
    cd "%%i"

    echo ------------------------
    echo %git_command%
    git %git_command% /output.txt
    echo ------------------------

    echo ****************************************
)

cd ..