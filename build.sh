#! /bin/sh
set -e
xctool project FreeStreamerMobile.xcodeproj -scheme "FreeStreamerMobile" build -sdk iphonesimulator7.0 -arch i386 ONLY_ACTIVE_ARCH=NO
xctool project FreeStreamerDesktop.xcodeproj -scheme "FreeStreamerDesktop" build -arch x86_64 ONLY_ACTIVE_ARCH=NO
