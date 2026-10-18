// Declarations for the ExtensionKit screensaver classes that ScreenSaver.framework exports
// (see the SDK's ScreenSaver.tbd) but does not declare in its public headers.
// After AerialScreensaver/AppexSaverMinimal (MIT).

#import <AppKit/AppKit.h>
#import <ScreenSaver/ScreenSaver.h>

NS_ASSUME_NONNULL_BEGIN

/// Principal class (NSExtensionPrincipalClass).
@interface ScreenSaverExtension : NSObject
- (instancetype)init;
@end

/// Main view controller (ScreenSaverViewControllerClass).
@interface ScreenSaverViewController : NSViewController
@property (nonatomic, weak, nullable) ScreenSaverView *representedView;
@property (nonatomic, getter=isAnimating) BOOL animating;
- (void)loadViewForFrame:(NSRect)frame isPreview:(BOOL)isPreview NS_SWIFT_NAME(loadView(forFrame:isPreview:));
@end

/// Options sheet controller (ScreenSaverConfigurationSheetViewControllerClass).
@interface ScreenSaverConfigurationViewController : NSViewController
/// Closes the remotely presented sheet (Apple's Flurry and Hello call this from their OK/Cancel actions).
- (void)configureSheetDidEnd;
@end

NS_ASSUME_NONNULL_END
