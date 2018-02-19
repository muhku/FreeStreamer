#! /bin/sh
set -e
xcodebuild -project FreeStreamerMobile/FreeStreamerMobile.xcodeproj \
	-scheme "FreeStreamerMobile" build \
	-sdk iphonesimulator -arch i386 ONLY_ACTIVE_ARCH=NO
xcodebuild -project FreeStreamerDesktop/FreeStreamerDesktop.xcodeproj \
	-scheme "FreeStreamerDesktop" build \
	-arch x86_64 ONLY_ACTIVE_ARCH=NO
