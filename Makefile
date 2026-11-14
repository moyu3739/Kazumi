# Windows release build for the current checkout.
# Run from PowerShell or cmd.exe with: make

SHELL := cmd.exe
.SHELLFLAGS := /D /E:ON /V:OFF /S /C

PROJECT_DIR := D:\toy\Kazumi
OUTPUT_DIR := $(PROJECT_DIR)\build\windows\x64\runner\Release
FLUTTER := D:\dev\flutter\bin\flutter.bat
PUB_CACHE_DIR ?= D:\dev\pub-cache
VSDEVCMD ?= D:\VisualStudio\Common7\Tools\VsDevCmd.bat

# Keep app credentials in a local, ignored file so clean builds retain them.
# Environment variables may override values from .dandan.env.
-include .dandan.env

ifeq ($(strip $(DANDANAPI_APPID)),)
$(error DANDANAPI_APPID is missing; set it in .dandan.env or the environment)
endif
ifeq ($(strip $(DANDANAPI_KEY)),)
$(error DANDANAPI_KEY is missing; set it in .dandan.env or the environment)
endif

.PHONY: all windows-release clean-release

all: windows-release

windows-release:
	@taskkill /F /IM kazumi.exe >NUL 2>NUL || exit /b 0
	@if exist "$(OUTPUT_DIR)" rmdir /s /q "$(OUTPUT_DIR)"
	@if exist "$(OUTPUT_DIR)" exit /b 1
	@set "PUB_CACHE=$(PUB_CACHE_DIR)" && "$(FLUTTER)" pub get
	@if not exist "$(PROJECT_DIR)\build" mkdir "$(PROJECT_DIR)\build"
	@call "$(VSDEVCMD)" -no_logo -host_arch=x64 -arch=x64 && cl /nologo /c /O2 /Fo"$(PROJECT_DIR)\build\ech_http_link_compat.obj" "$(PROJECT_DIR)\windows\ech_http_link_compat.cpp" && lib /nologo /out:"$(PROJECT_DIR)\build\ech_http_link_compat.lib" "$(PROJECT_DIR)\build\ech_http_link_compat.obj"
	@set "PUB_CACHE=$(PUB_CACHE_DIR)" && "$(FLUTTER)" build windows --release --dart-define=DANDANAPI_APPID=$(DANDANAPI_APPID) --dart-define=DANDANAPI_KEY=$(DANDANAPI_KEY)
	@copy /Y "D:\toy\Kazumi_windows_2.3.8\ech_http.dll" "$(OUTPUT_DIR)\ech_http.dll" >NUL
	@if not exist "$(OUTPUT_DIR)\kazumi.exe" exit /b 1
	@echo Release build completed: $(OUTPUT_DIR)

clean-release:
	@taskkill /F /IM kazumi.exe >NUL 2>NUL || exit /b 0
	@if exist "$(OUTPUT_DIR)" rmdir /s /q "$(OUTPUT_DIR)"
	@if exist "$(OUTPUT_DIR)" exit /b 1
	@echo Release output removed: $(OUTPUT_DIR)
