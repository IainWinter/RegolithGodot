@echo off
set EMSDK=C:\dev\Source\Packages\emsdk-4.0.11
call %EMSDK%\emsdk_env.bat >nul
cd /d %~dp0
cmake -S . -B build-web -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=%EMSDK%\upstream\emscripten\cmake\Modules\Platform\Emscripten.cmake -DGODOTCPP_THREADS=OFF
cmake --build build-web
