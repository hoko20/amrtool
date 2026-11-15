@echo off
chcp 65001 >nul
cd /d "%~dp0"

set REPO=https://github.com/hoko20/amrtool.git
set GIT=git

echo ==========================================
echo   语音转 AMR - 推送到 GitHub 并触发构建
echo   仓库: %REPO%
echo ==========================================
echo.

rem 优先用 PATH 里的 git，否则在常见安装位置找
where git >nul 2>nul
if errorlevel 1 (
  for %%G in (
    "%ProgramFiles%\Git\cmd\git.exe"
    "%ProgramFiles(x86)%\Git\cmd\git.exe"
    "%LOCALAPPDATA%\Programs\Git\cmd\git.exe"
    "%USERPROFILE%\scoop\shims\git.exe"
  ) do (
    if exist "%%~G" if "%GIT%"=="git" set "GIT=%%~G"
  )
)

"%GIT%" --version >nul 2>nul
if errorlevel 1 (
  echo [错误] 这台机器没装 git。
  echo        在 PowerShell 里执行下面这条安装后重开本窗口：
  echo        winget install --id Git.Git -e --source winget
  echo        或者到 https://git-scm.com/download/win 下载安装。
  echo.
  echo        不想装 git 的话，用 GitHub 网页 Upload files 也能上传，
  echo        但必须把 .github\workflows\build-ipa.yml 一起传上去。
  pause
  exit /b 1
)

if not exist ".github\workflows\build-ipa.yml" (
  echo [错误] 当前目录缺少 .github\workflows\build-ipa.yml
  echo        请确认这个 bat 放在「编译amr ipa」项目根目录里。
  pause
  exit /b 1
)

if not exist ".git" (
  echo ==^> 初始化仓库
  "%GIT%" init
  if errorlevel 1 goto :fail
)

"%GIT%" config --get user.name >nul 2>nul
if errorlevel 1 "%GIT%" config user.name "hoko20"
"%GIT%" config --get user.email >nul 2>nul
if errorlevel 1 "%GIT%" config user.email "hoko20@users.noreply.github.com"

echo ==^> 暂存文件
"%GIT%" add -A
if errorlevel 1 goto :fail

"%GIT%" diff --cached --quiet
if errorlevel 1 (
  echo ==^> 提交
  "%GIT%" commit -m "feat: AMR converter iOS app (mp3/mp4 to amr)"
  if errorlevel 1 goto :fail
) else (
  echo ==^> 没有新的改动，跳过提交
)

"%GIT%" branch -M main

"%GIT%" remote get-url origin >nul 2>nul
if errorlevel 1 (
  echo ==^> 添加远程 origin
  "%GIT%" remote add origin %REPO%
) else (
  "%GIT%" remote set-url origin %REPO%
)
if errorlevel 1 goto :fail

"%GIT%" ls-remote --exit-code --heads origin main >nul 2>nul
if errorlevel 1 (
  echo ==^> 远端还没有 main 分支，直接推送
) else (
  echo ==^> 先同步远端 main
  "%GIT%" pull origin main --rebase --allow-unrelated-histories
  if errorlevel 1 (
    echo [提示] rebase 失败，改用普通合并
    "%GIT%" rebase --abort >nul 2>nul
    "%GIT%" pull origin main --no-rebase --allow-unrelated-histories
    if errorlevel 1 goto :fail
  )
)

echo ==^> 推送到 GitHub
"%GIT%" push -u origin main
if errorlevel 1 (
  echo [提示] 普通推送被拒绝，尝试 --force-with-lease
  "%GIT%" push -u origin main --force-with-lease
  if errorlevel 1 goto :fail
)

echo.
echo 推送完成，Actions 会自动开始构建：
echo   https://github.com/hoko20/amrtool/actions
echo 构建成功后在该次 run 页面底部 Artifacts 下载 AMRConverter-IPA。
echo.
pause
exit /b 0

:fail
echo.
echo [失败] 上面的命令出错了，把这段输出发给我。
echo 常见原因：
echo   1. 首次推送要在浏览器里登录 GitHub 授权
echo   2. 仓库不存在或没有权限，确认 https://github.com/hoko20/amrtool 能打开
echo   3. 访问 GitHub 需要代理
echo.
pause
exit /b 1
