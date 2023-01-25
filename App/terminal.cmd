@echo off

set GLAB_BIN_DIR=%~dp0GitlabCli\bin
set PATH=%GLAB_BIN_DIR%;%PATH%

mkdir %GLAB_CONFIG_DIR%

start "Gitlab Cli Terminal"