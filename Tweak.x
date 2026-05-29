#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Shared/LGGlassRenderer.h"
#import "Shared/LGSharedSupport.h"

// Global UISwitch wrapper using the LiquidAss Metal glass renderer.
static NSString *const kLASGPrefsDomain = @"com.ash.liquidglassswitch";
static CFStringRef const kLASGPrefsChangedNotification = CFSTR("com.ash.liquidglassswitch/preferences.changed");

static BOOL gLASGEnabled = YES;
static const void *kLASGOverlayKey = &kLASGOverlayKey;
static const void *kLASGAppearanceKey = &kLASGAppearanceKey;
static const void *kLASGPressedKey = &kLASGPressedKey;
static const void *kLASGDidDragKey = &kLASGDidDragKey;
static const void *kLASGInitialOnKey = &kLASGInitialOnKey;
static const void *kLASGProgressKey = &kLASGProgressKey;
static const void *kLASGAnimatingTapKey = &kLASGAnimatingTapKey;
static const void *kLASGTapGenerationKey = &kLASGTapGenerationKey;
static const void *kLASGDragStartXKey = &kLASGDragStartXKey;
static const void *kLASGDragStartCenterXKey = &kLASGDragStartCenterXKey;

static CGFloat LASGClamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
    return MIN(MAX(value, minimum), maximum);
}

static CGFloat LASGSmooth(CGFloat value) {
    CGFloat t = LASGClamp(value, 0.0, 1.0);
    return t * t * (3.0 - (2.0 * t));
}

UIView *LG_findSubviewOfClass(UIView *root, Class cls) {
    if (!root || !cls) return nil;
    if ([root isKindOfClass:cls]) return root;
    for (UIView *subview in root.subviews) {
        UIView *match = LG_findSubviewOfClass(subview, cls);
        if (match) return match;
    }
    return nil;
}

void LG_updateAllGlassViewsInTree(UIView *root) { (void)root; }
void LG_registerGlassView(UIView *view, LGUpdateGroup group) { (void)view; (void)group; }
void LG_unregisterGlassView(UIView *view, LGUpdateGroup group) { (void)view; (void)group; }
void LG_updateRegisteredGlassViews(LGUpdateGroup group) { (void)group; }
BOOL LG_isFullScreenDevice(void) { return NO; }
UIWindow *LG_getHomescreenWindow(void) { return nil; }
BOOL LG_hasHomescreenWallpaperAsset(void) { return NO; }
UIImage *LG_getWallpaperImage(CGPoint *outOriginInScreenPts) { if (outOriginInScreenPts) *outOriginInScreenPts = CGPointZero; return nil; }
UIImage *LG_getHomescreenSnapshot(CGPoint *outOriginInScreenPts) { if (outOriginInScreenPts) *outOriginInScreenPts = CGPointZero; return nil; }
UIImage *LG_getHomescreenIconCompositeSnapshot(CGPoint *outOriginInScreenPts) { if (outOriginInScreenPts) *outOriginInScreenPts = CGPointZero; return nil; }
UIImage *LG_getContextMenuSnapshot(void) { return nil; }
UIImage *LG_getCachedContextMenuSnapshot(void) { return nil; }
UIImage *LG_getStrictCachedContextMenuSnapshot(void) { return nil; }
BOOL LG_imageLooksBlack(UIImage *image) { (void)image; return NO; }
void LG_cacheContextMenuSnapshot(void) {}
void LG_invalidateContextMenuSnapshot(void) {}
UIImage *LG_getFolderSnapshot(void) { return nil; }
UIImage *LG_getLockscreenSnapshot(void) { return nil; }
UIImage *LG_getRawLockscreenWallpaperImage(void) { return nil; }
CGPoint LG_getLockscreenWallpaperOrigin(void) { return CGPointZero; }
void LG_cacheFolderSnapshot(void) {}
void LG_invalidateFolderSnapshot(void) {}
void LG_refreshHomescreenSnapshot(void) {}
void LGInvalidateLockscreenSnapshotCache(void) {}

static CGSize LASGSwitchSize(void) {
    return CGSizeMake(63.0, 28.0);
}

static CGSize LASGRestThumbSize(void) {
    return CGSizeMake(36.0, 24.0);
}

static CGSize LASGExpandedThumbSize(void) {
    return CGSizeMake(54.0, 34.0);
}

static CGRect LASGTrackFrameForBounds(CGRect bounds) {
    CGSize size = LASGSwitchSize();
    return CGRectMake(floor((CGRectGetWidth(bounds) - size.width) * 0.5),
                      floor((CGRectGetHeight(bounds) - size.height) * 0.5),
                      size.width,
                      size.height);
}

static CGFloat LASGMinimumThumbCenterXForBounds(CGRect bounds) {
    CGRect trackFrame = LASGTrackFrameForBounds(bounds);
    return CGRectGetMinX(trackFrame) + 20.0;
}

static CGFloat LASGMaximumThumbCenterXForBounds(CGRect bounds) {
    CGRect trackFrame = LASGTrackFrameForBounds(bounds);
    return CGRectGetMaxX(trackFrame) - 20.0;
}

static CGFloat LASGProgressForThumbCenterX(CGRect bounds, CGFloat centerX) {
    CGFloat minX = LASGMinimumThumbCenterXForBounds(bounds);
    CGFloat maxX = LASGMaximumThumbCenterXForBounds(bounds);
    CGFloat range = maxX - minX;
    if (range <= 0.0) return 0.0;
    return (centerX - minX) / range;
}

static CGFloat LASGRubberBandedThumbCenterX(CGRect bounds, CGFloat centerX) {
    CGFloat minX = LASGMinimumThumbCenterXForBounds(bounds);
    CGFloat maxX = LASGMaximumThumbCenterXForBounds(bounds);
    if (centerX < minX) return minX - sqrt(minX - centerX);
    if (centerX > maxX) return maxX + sqrt(centerX - maxX);
    return centerX;
}

static BOOL LASGIsDarkMode(UITraitCollection *traitCollection) {
    if (@available(iOS 12.0, *)) {
        return traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

static UIColor *LASGSwitchOffTrackColor(UITraitCollection *traitCollection) {
    if (LASGIsDarkMode(traitCollection)) {
        return [UIColor colorWithWhite:1.0 alpha:0.18];
    }
    return [UIColor colorWithWhite:0.20 alpha:0.10];
}

static UIColor *LASGSwitchBackdropSheenColor(UITraitCollection *traitCollection) {
    if (LASGIsDarkMode(traitCollection)) {
        return [UIColor colorWithWhite:1.0 alpha:0.045];
    }
    return [UIColor colorWithWhite:1.0 alpha:0.12];
}

static UIColor *LASGSwitchGlassLiftColor(UITraitCollection *traitCollection) {
    (void)traitCollection;
    return [UIColor colorWithWhite:1.0 alpha:0.0];
}

static BOOL LASGColorLooksTooDarkForAccent(UIColor *color) {
    if (!color) return YES;
    CGFloat r = 0.0, g = 0.0, b = 0.0, a = 0.0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0.0;
        if ([color getWhite:&white alpha:&a]) {
            r = g = b = white;
        } else {
            return NO;
        }
    }
    return a > 0.01 && r < 0.12 && g < 0.12 && b < 0.12;
}

static void LASGPerformSwitchHaptic(void) {
    if (@available(iOS 10.0, *)) {
        UISelectionFeedbackGenerator *generator = [UISelectionFeedbackGenerator new];
        [generator prepare];
        [generator selectionChanged];
    }
}

static UIImage *LASGRenderSwitchBackdropImage(CGSize size,
                                              UIColor *backgroundColor,
                                              UIColor *trackColor,
                                              UIColor *fillColor,
                                              UIColor *sheenColor,
                                              UIColor *glassLiftColor,
                                              CGRect localTrackRect,
                                              CGFloat fillEndX,
                                              CGFloat magnification) {
    if (size.width <= 0.0 || size.height <= 0.0) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    [backgroundColor setFill];
    CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));

    CGFloat scale = fmax(magnification, 0.1);
    CGPoint canvasCenter = CGPointMake(size.width * 0.5, size.height * 0.5);
    CGRect scaledTrackRect = CGRectMake(canvasCenter.x - (CGRectGetWidth(localTrackRect) * scale * 0.5),
                                        canvasCenter.y - (CGRectGetHeight(localTrackRect) * scale * 0.5),
                                        CGRectGetWidth(localTrackRect) * scale,
                                        CGRectGetHeight(localTrackRect) * scale);
    CGFloat scaledFillEndX = CGRectGetMinX(scaledTrackRect) + ((fillEndX - CGRectGetMinX(localTrackRect)) * scale);

    CGFloat radius = CGRectGetHeight(scaledTrackRect) * 0.5;
    UIBezierPath *trackPath = [UIBezierPath bezierPathWithRoundedRect:scaledTrackRect cornerRadius:radius];
    [trackColor setFill];
    [trackPath fill];

    CGFloat clampedFillEndX = fmax(CGRectGetMinX(scaledTrackRect), fmin(scaledFillEndX, CGRectGetMaxX(scaledTrackRect)));
    CGRect fillRect = CGRectMake(CGRectGetMinX(scaledTrackRect),
                                 CGRectGetMinY(scaledTrackRect),
                                 clampedFillEndX - CGRectGetMinX(scaledTrackRect),
                                 CGRectGetHeight(scaledTrackRect));
    if (fillRect.size.width > 0.0) {
        UIBezierPath *fillPath = [UIBezierPath bezierPathWithRoundedRect:fillRect cornerRadius:radius];
        [fillColor setFill];
        [fillPath fill];
    }

    [sheenColor setFill];
    CGContextFillRect(context, CGRectMake(0, 0, size.width, fmin(12.0, size.height * 0.35)));

    if (CGColorGetAlpha(glassLiftColor.CGColor) > 0.001) {
        UIBezierPath *liftPath = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(scaledTrackRect, -30.0, -14.0)
                                                            cornerRadius:CGRectGetHeight(scaledTrackRect) * 3.0];
        [glassLiftColor setFill];
        [liftPath fill];
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@interface LASGSavedAppearance : NSObject
@property (nonatomic, strong) UIColor *tintColor;
@property (nonatomic, strong) UIColor *onTintColor;
@property (nonatomic, strong) UIColor *thumbTintColor;
@property (nonatomic, strong) UIColor *backgroundColor;
@property (nonatomic, assign) BOOL clipsToBounds;
@end

@implementation LASGSavedAppearance
@end

@interface LASGSwitchInsetShadowView : UIView
@end

@implementation LASGSwitchInsetShadowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.layer.compositingFilter = @"multiplyBlendMode";
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat shadowRadius = 3.5;
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds, -1.0, -shadowRadius * 0.5)
                                                    cornerRadius:CGRectGetHeight(self.bounds) * 0.5];
    UIBezierPath *inner = [[UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds, 0.0, shadowRadius * 0.55)
                                                      cornerRadius:CGRectGetHeight(self.bounds) * 0.5] bezierPathByReversingPath];
    [path appendPath:inner];
    self.layer.shadowPath = path.CGPath;
    self.layer.shadowColor = [UIColor colorWithWhite:0.0 alpha:1.0].CGColor;
    self.layer.shadowOpacity = 0.18;
    self.layer.shadowRadius = shadowRadius;
    self.layer.shadowOffset = CGSizeMake(0.0, shadowRadius * 0.75);
}

@end

@interface LASGSwitchOverlay : UIView
@property (nonatomic, weak) UISwitch *hostSwitch;
@property (nonatomic, strong) UIView *trackView;
@property (nonatomic, strong) UIView *fillView;
@property (nonatomic, strong) CAShapeLayer *trackCutoutMask;
@property (nonatomic, strong) UIView *contractedThumbView;
@property (nonatomic, strong) LGSharedGlassView *glassThumbView;
@property (nonatomic, strong) LASGSwitchInsetShadowView *glassInsetShadowView;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) CGFloat renderedProgress;
@property (nonatomic, assign) CGFloat targetProgress;
@property (nonatomic, assign) CGSize renderedThumbSize;
@property (nonatomic, assign) CGSize targetThumbSize;
@property (nonatomic, assign) CGFloat renderedExpansion;
@property (nonatomic, assign) CGFloat targetExpansion;
@property (nonatomic, assign) CGFloat renderedFillAlpha;
@property (nonatomic, assign) CGFloat targetFillAlpha;
@property (nonatomic, assign) CGFloat fillAnimationStartAlpha;
@property (nonatomic, assign) CFTimeInterval fillAnimationStartTime;
@property (nonatomic, assign) CFTimeInterval lastDisplayLinkTimestamp;
@property (nonatomic, assign) BOOL fillAnimating;
@property (nonatomic, assign) BOOL pressed;
@property (nonatomic, assign) BOOL hasRenderedState;
- (void)syncWithSwitch:(UISwitch *)switchView progress:(CGFloat)progress pressed:(BOOL)pressed animated:(BOOL)animated;
- (void)stopDisplayLink;
@end

@implementation LASGSwitchOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = NO;

    _renderedProgress = 0.0;
    _targetProgress = 0.0;
    _renderedThumbSize = LASGRestThumbSize();
    _targetThumbSize = _renderedThumbSize;
    _renderedExpansion = 0.0;
    _targetExpansion = 0.0;
    _renderedFillAlpha = 0.0;
    _targetFillAlpha = 0.0;

    _trackView = [[UIView alloc] initWithFrame:CGRectZero];
    _trackView.userInteractionEnabled = NO;
    [self addSubview:_trackView];

    _fillView = [[UIView alloc] initWithFrame:CGRectZero];
    _fillView.userInteractionEnabled = NO;
    [_trackView addSubview:_fillView];

    _trackCutoutMask = [CAShapeLayer layer];
    _trackCutoutMask.fillRule = kCAFillRuleEvenOdd;

    _contractedThumbView = [[UIView alloc] initWithFrame:CGRectZero];
    _contractedThumbView.userInteractionEnabled = NO;
    [self addSubview:_contractedThumbView];

    LGEnsureSharedGlassPipelinesReady();
    _glassThumbView = [[LGSharedGlassView alloc] initWithFrame:CGRectZero sourceImage:nil sourceOrigin:CGPointZero];
    _glassThumbView.userInteractionEnabled = NO;
    _glassThumbView.releasesSourceAfterUpload = YES;
    _glassThumbView.bezelWidth = 6.0;
    _glassThumbView.glassThickness = 20.0;
    _glassThumbView.refractionScale = 1.5;
    _glassThumbView.refractiveIndex = 1.5;
    _glassThumbView.specularOpacity = 0.04;
    _glassThumbView.blur = 0.0;
    _glassThumbView.sourceScale = 1.0;
    _glassThumbView.alpha = 0.0;
    _glassThumbView.hidden = YES;
    [self addSubview:_glassThumbView];

    _glassInsetShadowView = [[LASGSwitchInsetShadowView alloc] initWithFrame:_glassThumbView.bounds];
    _glassInsetShadowView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_glassThumbView addSubview:_glassInsetShadowView];

    return self;
}

- (void)dealloc {
    [self stopDisplayLink];
}

- (UIColor *)effectiveAccentColorForSwitch:(UISwitch *)switchView {
    LASGSavedAppearance *appearance = objc_getAssociatedObject(switchView, kLASGAppearanceKey);
    NSArray<UIColor *> *candidates = @[
        appearance.onTintColor ?: UIColor.clearColor,
        switchView.window.tintColor ?: UIColor.clearColor,
        switchView.superview.tintColor ?: UIColor.clearColor,
        UIColor.systemBlueColor
    ];
    for (UIColor *candidate in candidates) {
        if (!candidate || candidate == UIColor.clearColor) continue;
        if (LASGColorLooksTooDarkForAccent(candidate)) continue;
        return candidate;
    }
    return UIColor.systemBlueColor;
}

- (UIColor *)safeBackgroundColorForSwitch:(UISwitch *)switchView {
    UIColor *candidate = switchView.superview.backgroundColor ?: switchView.window.backgroundColor;
    if (candidate && CGColorGetAlpha(candidate.CGColor) > 0.01) return candidate;
    if (@available(iOS 13.0, *)) return UIColor.systemBackgroundColor;
    return UIColor.whiteColor;
}

- (void)updateMaterialColors {
    UISwitch *switchView = self.hostSwitch;
    if (!switchView) return;
    UIColor *accent = [self effectiveAccentColorForSwitch:switchView];
    BOOL darkMode = LASGIsDarkMode(switchView.traitCollection);
    self.trackView.backgroundColor = LASGSwitchOffTrackColor(switchView.traitCollection);
    self.fillView.backgroundColor = [accent colorWithAlphaComponent:darkMode ? 0.78 : 0.92];

    self.contractedThumbView.backgroundColor = UIColor.whiteColor;
    self.contractedThumbView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.contractedThumbView.layer.shadowOpacity = 0.0;
    self.contractedThumbView.layer.shadowRadius = 0.0;
    self.contractedThumbView.layer.shadowOffset = CGSizeZero;

    self.glassThumbView.layer.shadowColor = UIColor.clearColor.CGColor;
    self.glassThumbView.layer.shadowOpacity = 0.0;
    self.glassThumbView.layer.shadowRadius = 0.0;
    self.glassThumbView.layer.shadowOffset = CGSizeZero;
    self.glassThumbView.specularOpacity = darkMode ? 0.02 : 0.0;
    self.glassInsetShadowView.alpha = 0.0;
}

- (BOOL)shouldRenderGlassBackdrop {
    return self.pressed || self.targetExpansion > 0.001 || self.renderedExpansion > 0.001;
}

- (void)setFillVisible:(BOOL)visible animated:(BOOL)animated {
    CGFloat nextTarget = visible ? 1.0 : 0.0;
    if (fabs(self.targetFillAlpha - nextTarget) < 0.001 && (!animated || !self.fillAnimating)) return;
    self.targetFillAlpha = nextTarget;
    if (animated) {
        self.fillAnimationStartAlpha = self.renderedFillAlpha;
        self.fillAnimationStartTime = CACurrentMediaTime();
        self.fillAnimating = YES;
        [self startDisplayLinkIfNeeded];
    } else {
        self.renderedFillAlpha = nextTarget;
        self.fillAnimating = NO;
    }
}

- (void)syncRenderedStateImmediately {
    self.renderedProgress = self.targetProgress;
    self.renderedThumbSize = self.targetThumbSize;
    self.renderedExpansion = self.targetExpansion;
    self.renderedFillAlpha = self.targetFillAlpha;
    self.fillAnimating = NO;
    self.hasRenderedState = YES;
}

- (void)startDisplayLinkIfNeeded {
    if (self.displayLink || !self.window) return;
    self.lastDisplayLinkTimestamp = 0.0;
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleDisplayLink:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopDisplayLink {
    [self.displayLink invalidate];
    self.displayLink = nil;
    self.lastDisplayLinkTimestamp = 0.0;
}

- (void)handleDisplayLink:(CADisplayLink *)link {
    CFTimeInterval dt = self.lastDisplayLinkTimestamp > 0.0 ? (link.timestamp - self.lastDisplayLinkTimestamp) : (1.0 / 60.0);
    self.lastDisplayLinkTimestamp = link.timestamp;
    CGFloat frameFactor = fmin(MAX(dt * 60.0, 0.35), 1.4);
    CGFloat progressLerp = (self.pressed ? 0.34 : 0.22) * frameFactor;
    CGFloat sizeLerp = (self.pressed ? 0.36 : 0.24) * frameFactor;
    BOOL expanding = self.targetExpansion > self.renderedExpansion;
    CGFloat expansionLerp = ((self.pressed || expanding) ? 0.42 : 0.14) * frameFactor;

    if (!self.hasRenderedState) {
        [self syncRenderedStateImmediately];
    } else {
        self.renderedProgress += (self.targetProgress - self.renderedProgress) * progressLerp;
        self.renderedThumbSize = CGSizeMake(self.renderedThumbSize.width + (self.targetThumbSize.width - self.renderedThumbSize.width) * sizeLerp,
                                            self.renderedThumbSize.height + (self.targetThumbSize.height - self.renderedThumbSize.height) * sizeLerp);
        self.renderedExpansion += (self.targetExpansion - self.renderedExpansion) * expansionLerp;
    }

    if (self.fillAnimating) {
        CFTimeInterval elapsed = CACurrentMediaTime() - self.fillAnimationStartTime;
        CGFloat t = LASGClamp(elapsed / 0.1, 0.0, 1.0);
        CGFloat eased = LASGSmooth(t);
        self.renderedFillAlpha = self.fillAnimationStartAlpha + ((self.targetFillAlpha - self.fillAnimationStartAlpha) * eased);
        if (t >= 1.0) {
            self.renderedFillAlpha = self.targetFillAlpha;
            self.fillAnimating = NO;
        }
    }

    [self refreshGlassBackdrop];
    [self updateVisuals];

    BOOL settledProgress = fabs(self.targetProgress - self.renderedProgress) < 0.002;
    BOOL settledWidth = fabs(self.targetThumbSize.width - self.renderedThumbSize.width) < 0.05;
    BOOL settledHeight = fabs(self.targetThumbSize.height - self.renderedThumbSize.height) < 0.05;
    BOOL settledExpansion = fabs(self.targetExpansion - self.renderedExpansion) < 0.01;
    if (!self.pressed && settledProgress && settledWidth && settledHeight && settledExpansion && !self.fillAnimating) {
        [self syncRenderedStateImmediately];
        [self updateVisuals];
        [self stopDisplayLink];
    }
}

- (void)refreshGlassBackdrop {
    UISwitch *switchView = self.hostSwitch;
    if (!switchView.window || ![self shouldRenderGlassBackdrop]) {
        self.glassThumbView.sourceImage = nil;
        return;
    }
    CGRect trackFrame = LASGTrackFrameForBounds(self.bounds);
    CGRect captureRect = CGRectInset(trackFrame, -20.0, -20.0);
    UIColor *backgroundColor = UIColor.clearColor;
    UIColor *trackColor = LASGSwitchOffTrackColor(switchView.traitCollection);
    UIColor *baseFillColor = self.fillView.backgroundColor ?: [self effectiveAccentColorForSwitch:switchView];
    UIColor *sheenColor = LASGSwitchBackdropSheenColor(switchView.traitCollection);
    UIColor *liftColor = LASGSwitchGlassLiftColor(switchView.traitCollection);
    CGRect localTrackRect = CGRectOffset(trackFrame, -CGRectGetMinX(captureRect), -CGRectGetMinY(captureRect));
    UIColor *fillColor = [baseFillColor colorWithAlphaComponent:self.renderedFillAlpha];
    CGFloat fillEndX = CGRectGetMaxX(localTrackRect);
    UIImage *image = LASGRenderSwitchBackdropImage(captureRect.size,
                                                  backgroundColor,
                                                  trackColor,
                                                  fillColor,
                                                  sheenColor,
                                                  liftColor,
                                                  localTrackRect,
                                                  fillEndX,
                                                  0.75);
    self.glassThumbView.sourceImage = image;
    self.glassThumbView.sourceOrigin = [self convertPoint:captureRect.origin toView:nil];
    [self.glassThumbView scheduleDraw];
}

- (void)updateVisuals {
    CGRect trackFrame = LASGTrackFrameForBounds(self.bounds);
    self.trackView.frame = trackFrame;
    self.trackView.layer.cornerRadius = CGRectGetHeight(trackFrame) * 0.5;
    self.trackView.alpha = 1.0;

    self.fillView.frame = self.trackView.bounds;
    self.fillView.layer.cornerRadius = CGRectGetHeight(self.fillView.bounds) * 0.5;
    self.fillView.alpha = self.renderedFillAlpha;

    CGFloat centerX = LASGMinimumThumbCenterXForBounds(self.bounds) +
        ((LASGMaximumThumbCenterXForBounds(self.bounds) - LASGMinimumThumbCenterXForBounds(self.bounds)) * self.renderedProgress);
    CGRect contractedFrame = CGRectMake(centerX - 18.0,
                                        CGRectGetMidY(trackFrame) - 12.0,
                                        36.0,
                                        24.0);
    CGRect glassFrame = CGRectMake(centerX - self.renderedThumbSize.width * 0.5,
                                   CGRectGetMidY(trackFrame) - self.renderedThumbSize.height * 0.5,
                                   self.renderedThumbSize.width,
                                   self.renderedThumbSize.height);

    self.contractedThumbView.layer.cornerRadius = 12.0;
    self.glassThumbView.cornerRadius = CGRectGetHeight(glassFrame) * 0.5;
    self.glassThumbView.hidden = NO;
    self.contractedThumbView.hidden = NO;

    CGFloat visualExpansion = LASGSmooth(self.renderedExpansion);
    if (!self.pressed && visualExpansion < 0.04) {
        visualExpansion = 0.0;
        self.renderedExpansion = 0.0;
    }

    BOOL glassActive = [self shouldRenderGlassBackdrop] || visualExpansion > 0.001;
    if (glassActive && visualExpansion > 0.001) {
        CGFloat visualScale = 0.92 + (0.08 * visualExpansion);
        CGRect cutoutFrame = CGRectOffset(glassFrame, -CGRectGetMinX(trackFrame), -CGRectGetMinY(trackFrame));
        cutoutFrame = CGRectInset(cutoutFrame,
                                  -(CGRectGetWidth(cutoutFrame) * (visualScale - 1.0) * 0.5),
                                  -(CGRectGetHeight(cutoutFrame) * (visualScale - 1.0) * 0.5));
        UIBezierPath *maskPath = [UIBezierPath bezierPathWithRoundedRect:self.trackView.bounds
                                                            cornerRadius:CGRectGetHeight(self.trackView.bounds) * 0.5];
        UIBezierPath *cutoutPath = [UIBezierPath bezierPathWithRoundedRect:cutoutFrame
                                                              cornerRadius:CGRectGetHeight(cutoutFrame) * 0.5];
        [maskPath appendPath:cutoutPath];
        self.trackCutoutMask.frame = self.trackView.bounds;
        self.trackCutoutMask.path = maskPath.CGPath;
        self.trackView.layer.mask = self.trackCutoutMask;
    } else {
        self.trackView.layer.mask = nil;
    }

    self.contractedThumbView.frame = contractedFrame;
    self.glassThumbView.frame = glassFrame;
    self.glassThumbView.alpha = glassActive ? (visualExpansion * 0.90) : 0.0;
    self.contractedThumbView.alpha = 1.0 - visualExpansion;
    self.glassThumbView.transform = CGAffineTransformMakeScale(0.92 + (0.08 * visualExpansion),
                                                               0.92 + (0.08 * visualExpansion));
    self.contractedThumbView.transform = CGAffineTransformMakeScale(1.0 + (0.06 * visualExpansion),
                                                                    1.0 + (0.06 * visualExpansion));
    self.glassThumbView.hidden = !glassActive;
    self.contractedThumbView.hidden = visualExpansion > 0.99;
    if (self.glassThumbView.hidden) {
        self.glassThumbView.sourceImage = nil;
    }
    self.alpha = self.hostSwitch.enabled ? 1.0 : 0.5;
}

- (void)syncWithSwitch:(UISwitch *)switchView progress:(CGFloat)progress pressed:(BOOL)pressed animated:(BOOL)animated {
    self.hostSwitch = switchView;
    self.pressed = pressed;
    [self updateMaterialColors];

    self.targetProgress = progress;
    self.targetExpansion = pressed ? 1.0 : 0.0;
    self.targetThumbSize = pressed ? LASGExpandedThumbSize() : LASGRestThumbSize();

    BOOL initialOn = [objc_getAssociatedObject(switchView, kLASGInitialOnKey) boolValue];
    BOOL fillVisible = pressed ? (initialOn ? progress > 0.02 : progress >= 0.98) : switchView.isOn;
    [self setFillVisible:fillVisible animated:animated];

    if (!self.hasRenderedState || !animated) {
        [self syncRenderedStateImmediately];
    } else {
        [self startDisplayLinkIfNeeded];
    }

    [self refreshGlassBackdrop];
    [self updateVisuals];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self stopDisplayLink];
    [self refreshGlassBackdrop];
    [self updateVisuals];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateMaterialColors];
    if (!self.hasRenderedState) [self syncRenderedStateImmediately];
    [self refreshGlassBackdrop];
    [self updateVisuals];
}

@end

static void LASGLoadPreferences(void) {
    CFPreferencesAppSynchronize((CFStringRef)kLASGPrefsDomain);
    Boolean keyExists = false;
    Boolean enabled = CFPreferencesGetAppBooleanValue((CFStringRef)@"enabled", (CFStringRef)kLASGPrefsDomain, &keyExists);
    gLASGEnabled = keyExists ? (BOOL)enabled : YES;
    LGReloadPreferences();
}

static void LASGCaptureAppearanceIfNeeded(UISwitch *switchView) {
    if (objc_getAssociatedObject(switchView, kLASGAppearanceKey)) return;
    LASGSavedAppearance *appearance = [LASGSavedAppearance new];
    appearance.tintColor = switchView.tintColor;
    appearance.onTintColor = switchView.onTintColor;
    appearance.thumbTintColor = switchView.thumbTintColor;
    appearance.backgroundColor = switchView.backgroundColor;
    appearance.clipsToBounds = switchView.clipsToBounds;
    objc_setAssociatedObject(switchView, kLASGAppearanceKey, appearance, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void LASGRestoreAppearance(UISwitch *switchView) {
    LASGSavedAppearance *appearance = objc_getAssociatedObject(switchView, kLASGAppearanceKey);
    if (!appearance) return;
    switchView.tintColor = appearance.tintColor;
    switchView.onTintColor = appearance.onTintColor;
    switchView.thumbTintColor = appearance.thumbTintColor;
    switchView.backgroundColor = appearance.backgroundColor;
    switchView.clipsToBounds = appearance.clipsToBounds;
    objc_setAssociatedObject(switchView, kLASGAppearanceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void LASGSetSystemSubviewsHidden(UISwitch *switchView, BOOL hidden) {
    UIView *overlay = objc_getAssociatedObject(switchView, kLASGOverlayKey);
    for (UIView *subview in switchView.subviews) {
        if (subview == overlay) continue;
        subview.layer.opacity = hidden ? 0.0f : 1.0f;
    }
}

static LASGSwitchOverlay *LASGEnsureOverlay(UISwitch *switchView) {
    LASGSwitchOverlay *overlay = objc_getAssociatedObject(switchView, kLASGOverlayKey);
    if (!overlay) {
        overlay = [[LASGSwitchOverlay alloc] initWithFrame:switchView.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [switchView addSubview:overlay];
        objc_setAssociatedObject(switchView, kLASGOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    overlay.frame = switchView.bounds;
    overlay.hostSwitch = switchView;
    return overlay;
}

static void LASGRemoveOverlay(UISwitch *switchView) {
    LASGSwitchOverlay *overlay = objc_getAssociatedObject(switchView, kLASGOverlayKey);
    if (overlay) {
        [overlay stopDisplayLink];
        [overlay removeFromSuperview];
        objc_setAssociatedObject(switchView, kLASGOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    LASGSetSystemSubviewsHidden(switchView, NO);
    LASGRestoreAppearance(switchView);
    objc_setAssociatedObject(switchView, kLASGPressedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(switchView, kLASGDidDragKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(switchView, kLASGInitialOnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(switchView, kLASGProgressKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(switchView, kLASGAnimatingTapKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(switchView, kLASGTapGenerationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(switchView, kLASGDragStartXKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(switchView, kLASGDragStartCenterXKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL LASGInitialOn(UISwitch *switchView) {
    NSNumber *value = objc_getAssociatedObject(switchView, kLASGInitialOnKey);
    return value ? value.boolValue : switchView.isOn;
}

static BOOL LASGIsPressed(UISwitch *switchView) {
    return [objc_getAssociatedObject(switchView, kLASGPressedKey) boolValue];
}

static BOOL LASGDidDrag(UISwitch *switchView) {
    return [objc_getAssociatedObject(switchView, kLASGDidDragKey) boolValue];
}

static BOOL LASGIsAnimatingTap(UISwitch *switchView) {
    return [objc_getAssociatedObject(switchView, kLASGAnimatingTapKey) boolValue];
}

static CGFloat LASGCurrentProgress(UISwitch *switchView) {
    NSNumber *value = objc_getAssociatedObject(switchView, kLASGProgressKey);
    return value ? (CGFloat)value.doubleValue : (switchView.isOn ? 1.0 : 0.0);
}

static void LASGSetProgress(UISwitch *switchView, CGFloat progress) {
    objc_setAssociatedObject(switchView, kLASGProgressKey, @(progress), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static CGFloat LASGTouchProgress(UISwitch *switchView, UITouch *touch) {
    CGPoint location = [touch locationInView:switchView];
    NSNumber *startX = objc_getAssociatedObject(switchView, kLASGDragStartXKey);
    NSNumber *startCenterX = objc_getAssociatedObject(switchView, kLASGDragStartCenterXKey);
    if (!startX || !startCenterX) {
        return LASGProgressForThumbCenterX(switchView.bounds, location.x);
    }
    CGFloat translatedCenterX = startCenterX.doubleValue + (location.x - startX.doubleValue);
    CGFloat rubberCenterX = LASGRubberBandedThumbCenterX(switchView.bounds, translatedCenterX);
    return LASGProgressForThumbCenterX(switchView.bounds, rubberCenterX);
}

static void LASGApplySwitchStyling(UISwitch *switchView, BOOL animated) {
    // 优化：如果 switch 不可见（无 window），跳过 styling 减少无效计算
    if (!gLASGEnabled || !switchView.window || CGRectGetWidth(switchView.bounds) < 30.0 || CGRectGetHeight(switchView.bounds) < 20.0) {
        LASGRemoveOverlay(switchView);
        return;
    }

    LASGCaptureAppearanceIfNeeded(switchView);
    switchView.tintColor = UIColor.clearColor;
    switchView.onTintColor = UIColor.clearColor;
    switchView.thumbTintColor = UIColor.clearColor;
    switchView.backgroundColor = UIColor.clearColor;
    switchView.clipsToBounds = NO;

    LASGSwitchOverlay *overlay = LASGEnsureOverlay(switchView);
    LASGSetSystemSubviewsHidden(switchView, YES);
    [switchView bringSubviewToFront:overlay];
    [overlay syncWithSwitch:switchView
                   progress:LASGCurrentProgress(switchView)
                    pressed:LASGIsPressed(switchView)
                   animated:animated];
}

static void LASGAnimateTap(UISwitch *switchView, BOOL fromOn, BOOL toOn, BOOL updateSwitchState) {
    LASGSwitchOverlay *overlay = objc_getAssociatedObject(switchView, kLASGOverlayKey);
    if (!overlay) return;

    CGFloat startProgress = fromOn ? 1.0 : 0.0;
    CGFloat endProgress = toOn ? 1.0 : 0.0;
    NSUInteger generation = [objc_getAssociatedObject(switchView, kLASGTapGenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(switchView, kLASGTapGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(switchView, kLASGAnimatingTapKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(switchView, kLASGInitialOnKey, @(fromOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(switchView, kLASGPressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    LASGSetProgress(switchView, startProgress);
    [overlay syncWithSwitch:switchView progress:startProgress pressed:YES animated:NO];

    if (updateSwitchState && switchView.isOn != toOn) {
        [switchView setOn:toOn animated:NO];
        LASGPerformSwitchHaptic();
        [switchView sendActionsForControlEvents:UIControlEventValueChanged];
    }
    LASGSetProgress(switchView, endProgress);
    [overlay syncWithSwitch:switchView progress:endProgress pressed:YES animated:YES];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.24 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([objc_getAssociatedObject(switchView, kLASGTapGenerationKey) unsignedIntegerValue] != generation) return;
        objc_setAssociatedObject(switchView, kLASGPressedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(switchView, kLASGInitialOnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LASGSetProgress(switchView, endProgress);
        [overlay syncWithSwitch:switchView progress:endProgress pressed:NO animated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.34 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([objc_getAssociatedObject(switchView, kLASGTapGenerationKey) unsignedIntegerValue] != generation) return;
            LASGSetProgress(switchView, endProgress);
            [overlay syncWithSwitch:switchView progress:endProgress pressed:NO animated:NO];
            objc_setAssociatedObject(switchView, kLASGAnimatingTapKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(switchView, kLASGTapGenerationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        });
    });
}

static void LASGVisitSwitchesInView(UIView *view) {
    if ([view isKindOfClass:UISwitch.class]) {
        UISwitch *switchView = (UISwitch *)view;
        [switchView setNeedsLayout];
        [switchView layoutIfNeeded];
    }
    for (UIView *subview in view.subviews) {
        LASGVisitSwitchesInView(subview);
    }
}

static void LASGRefreshVisibleSwitches(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class UIApplicationClass = NSClassFromString(@"UIApplication");
        if (!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIApplication *application = [UIApplicationClass performSelector:@selector(sharedApplication)];
#pragma clang diagnostic pop
        for (UIWindow *window in LGApplicationWindows(application)) {
            LASGVisitSwitchesInView(window);
        }
    });
}

static void LASGPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    LASGLoadPreferences();
    LASGRefreshVisibleSwitches();
}

%hook UISwitch

- (void)layoutSubviews {
    %orig;
    LASGApplySwitchStyling(self, NO);
}

- (void)didMoveToWindow {
    %orig;
    LASGApplySwitchStyling(self, NO);
}

// 修复：Cell 复用时 UISwitch 被移动到新 superview，确保 overlay 同步状态
- (void)didMoveToSuperview {
    %orig;
    if (!self.superview) {
        // Switch 从视图层级移除，清理 overlay
        LASGRemoveOverlay(self);
    } else {
        // 切换到新父视图，先移除旧 overlay 再重新应用
        LASGRemoveOverlay(self);
        LASGApplySwitchStyling(self, NO);
    }
}

- (void)setEnabled:(BOOL)enabled {
    %orig;
    LASGApplySwitchStyling(self, NO);
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    BOOL wasOn = self.isOn;
    BOOL isTracking = LASGIsPressed(self) || objc_getAssociatedObject(self, kLASGInitialOnKey);
    BOOL isAnimatingTap = LASGIsAnimatingTap(self);
    %orig;
    BOOL changed = wasOn != self.isOn;
    if (isAnimatingTap) {
        return;
    }
    if (changed && animated && !isTracking && !isAnimatingTap) {
        objc_setAssociatedObject(self, kLASGProgressKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LASGApplySwitchStyling(self, NO);
        LASGAnimateTap(self, wasOn, self.isOn, NO);
    } else {
        LASGApplySwitchStyling(self, animated);
    }
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)%orig;
    CGFloat initialProgress = self.isOn ? 1.0 : 0.0;
    CGFloat startCenterX = LASGMinimumThumbCenterXForBounds(self.bounds) +
        ((LASGMaximumThumbCenterXForBounds(self.bounds) - LASGMinimumThumbCenterXForBounds(self.bounds)) * initialProgress);
    CGPoint location = [touch locationInView:self];
    objc_setAssociatedObject(self, kLASGPressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kLASGDidDragKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kLASGInitialOnKey, @(self.isOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kLASGDragStartXKey, @(location.x), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kLASGDragStartCenterXKey, @(startCenterX), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LASGSetProgress(self, initialProgress);
    LASGApplySwitchStyling(self, YES);
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)%orig;
    CGFloat progress = LASGTouchProgress(self, touch);
    LASGSetProgress(self, progress);
    objc_setAssociatedObject(self, kLASGPressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (fabs(progress - (LASGInitialOn(self) ? 1.0 : 0.0)) > 0.08) {
        objc_setAssociatedObject(self, kLASGDidDragKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    LASGApplySwitchStyling(self, NO);
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    if (LASGDidDrag(self)) {
        CGFloat finalProgress = touch ? LASGTouchProgress(self, touch) : LASGCurrentProgress(self);
        BOOL desiredOn = finalProgress >= 0.5;
        BOOL initialOn = LASGInitialOn(self);
        if (self.isOn != desiredOn) {
            [self setOn:desiredOn animated:NO];
            if (desiredOn != initialOn) {
                LASGPerformSwitchHaptic();
                [self sendActionsForControlEvents:UIControlEventValueChanged];
            }
        }
        objc_setAssociatedObject(self, kLASGPressedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kLASGDidDragKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kLASGInitialOnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kLASGDragStartXKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kLASGDragStartCenterXKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LASGSetProgress(self, desiredOn ? 1.0 : 0.0);
        LASGApplySwitchStyling(self, YES);
    } else {
        BOOL initialOn = LASGInitialOn(self);
        BOOL desiredOn = !initialOn;
        objc_setAssociatedObject(self, kLASGProgressKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kLASGDidDragKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kLASGDragStartXKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kLASGDragStartCenterXKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LASGAnimateTap(self, initialOn, desiredOn, YES);
    }
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    (void)event;
    objc_setAssociatedObject(self, kLASGPressedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kLASGDidDragKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kLASGInitialOnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kLASGProgressKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kLASGAnimatingTapKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kLASGTapGenerationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kLASGDragStartXKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kLASGDragStartCenterXKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LASGApplySwitchStyling(self, YES);
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    return CGRectContainsPoint(CGRectInset(self.bounds, -10.0, -10.0), point);
}

- (CGSize)intrinsicContentSize {
    CGSize originalSize = %orig;
    (void)originalSize;
    return LASGSwitchSize();
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize originalSize = %orig;
    (void)originalSize;
    return LASGSwitchSize();
}

%end

%ctor {
    @autoreleasepool {
        LASGLoadPreferences();
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            LGEnsureSharedGlassPipelinesReady();
        });
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        LASGPreferencesChanged,
                                        kLASGPrefsChangedNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
