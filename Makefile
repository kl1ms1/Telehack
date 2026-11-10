TARGET := iphone:clang:latest:15.0
# App Store apps (Telegram included) run as arm64 processes, so arm64e is not needed.
ARCHS = arm64
INSTALL_TARGET_PROCESSES = Telegram

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TeleHack

TeleHack_FILES = Sources/Tweak.x $(wildcard Sources/*.m)
TeleHack_CFLAGS = -fobjc-arc -ISources -Wno-deprecated-declarations
TeleHack_FRAMEWORKS = UIKit Foundation Security
# Plain ObjC runtime swizzling: dylib не зависит от CydiaSubstrate/ElleKit,
# поэтому его можно просто вшить в IPA без джейлбрейка.
TeleHack_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk
