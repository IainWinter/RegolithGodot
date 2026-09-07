@echo off
set VCVARS="C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if not defined VSINSTALLDIR call %VCVARS%
cd /d %~dp0
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DGODOTCPP_USE_HOT_RELOAD=ON
cmake --build build
