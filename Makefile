THEOS ?= /opt/theos

export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:15.0
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiquidGlassSwitch

LiquidGlassSwitch_FILES = Tweak.x Shared/LGSharedSupport.m Shared/LGMetalShaderSource.m Shared/LGGlassRenderer.m Runtime/LGLiquidGlassRuntime.m
LiquidGlassSwitch_CFLAGS = -fobjc-arc
LiquidGlassSwitch_FRAMEWORKS = UIKit QuartzCore CoreGraphics Metal MetalKit MetalPerformanceShaders CoreVideo
LiquidGlassSwitch_EXTRA_FRAMEWORKS =

include $(THEOS_MAKE_PATH)/tweak.mk
