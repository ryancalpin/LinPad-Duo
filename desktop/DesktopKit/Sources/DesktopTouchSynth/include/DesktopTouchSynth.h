#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Real one-finger touches for the iPhone Duo's on-screen trackpad: a click outside Linux
/// windows becomes a finger touch at the pointer, so SwiftUI buttons (in scroll views too),
/// web content and UIKit controls respond exactly as to a tap.
///
/// iOS has no public API for this. It uses the UIKit and IOKit SPI that UI-testing tools
/// (KIF, EarlGrey) use: a UITouch with its private setters, an IOHIDEvent describing the
/// finger, and UIApplication's touches event. Sideloaded builds only, never the App Store.
@interface DTSTouch : NSObject

/// Whether this iOS has every private method the synthesizer needs.
@property (class, nonatomic, readonly) BOOL isAvailable;

/// A finger touching down at `point` (window coordinates). Nil if unavailable.
+ (nullable instancetype)beginAtPoint:(CGPoint)point inWindow:(UIWindow *)window NS_SWIFT_NAME(begin(at:in:));

/// The finger moving to `point` (window coordinates).
- (void)moveToPoint:(CGPoint)point NS_SWIFT_NAME(move(to:));

/// The finger lifting.
- (void)end;

/// Touch down and lift at `point`. Returns NO if unavailable.
+ (BOOL)tapAtPoint:(CGPoint)point inWindow:(UIWindow *)window NS_SWIFT_NAME(tap(at:in:));

@end

NS_ASSUME_NONNULL_END
