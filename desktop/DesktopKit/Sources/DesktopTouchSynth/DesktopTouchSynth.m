#import "DesktopTouchSynth.h"
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <objc/message.h>

// MARK: IOKit SPI

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef double IOHIDFloat;

enum {
    kDTSDigitizerTransducerTypeHand = 3,
    kDTSDigitizerEventRange = 1 << 0,
    kDTSDigitizerEventTouch = 1 << 1,
    kDTSDigitizerEventPosition = 1 << 2,
    // IOHIDEventFieldBase(kIOHIDEventTypeDigitizer = 11) + 25
    kDTSFieldDigitizerIsDisplayIntegrated = (11 << 16) | 25,
};

typedef IOHIDEventRef (*DTSCreateDigitizerEvent)(CFAllocatorRef, uint64_t, uint32_t transducerType, uint32_t index,
                                                 uint32_t identity, uint32_t eventMask, uint32_t buttonMask,
                                                 IOHIDFloat x, IOHIDFloat y, IOHIDFloat z, IOHIDFloat tipPressure,
                                                 IOHIDFloat barrelPressure, Boolean range, Boolean touch, uint32_t options);
typedef IOHIDEventRef (*DTSCreateFingerEvent)(CFAllocatorRef, uint64_t, uint32_t index, uint32_t identity,
                                              uint32_t eventMask, IOHIDFloat x, IOHIDFloat y, IOHIDFloat z,
                                              IOHIDFloat tipPressure, IOHIDFloat twist, IOHIDFloat minorRadius,
                                              IOHIDFloat majorRadius, IOHIDFloat quality, IOHIDFloat density,
                                              IOHIDFloat irregularity, Boolean range, Boolean touch, uint32_t options);
typedef void (*DTSAppendEvent)(IOHIDEventRef, IOHIDEventRef, uint32_t options);
typedef void (*DTSSetIntegerValue)(IOHIDEventRef, uint32_t field, long value);

static DTSCreateDigitizerEvent createDigitizerEvent;
static DTSCreateFingerEvent createFingerEvent;
static DTSAppendEvent appendEvent;
static DTSSetIntegerValue setIntegerValue;

static BOOL LoadIOKit(void) {
    static BOOL loaded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (iokit == NULL) return;
        createDigitizerEvent = (DTSCreateDigitizerEvent)dlsym(iokit, "IOHIDEventCreateDigitizerEvent");
        createFingerEvent = (DTSCreateFingerEvent)dlsym(iokit, "IOHIDEventCreateDigitizerFingerEventWithQuality");
        appendEvent = (DTSAppendEvent)dlsym(iokit, "IOHIDEventAppendEvent");
        setIntegerValue = (DTSSetIntegerValue)dlsym(iokit, "IOHIDEventSetIntegerValue");
        loaded = createDigitizerEvent && createFingerEvent && appendEvent && setIntegerValue;
    });
    return loaded;
}

/// A hand event with one finger at `location`, as the touchscreen reports it.
static IOHIDEventRef CreateHandEvent(CGPoint location, UITouchPhase phase) {
    uint64_t time = mach_absolute_time();
    Boolean touching = phase != UITouchPhaseEnded && phase != UITouchPhaseCancelled;
    IOHIDEventRef hand = createDigitizerEvent(kCFAllocatorDefault, time, kDTSDigitizerTransducerTypeHand, 0, 0,
                                              kDTSDigitizerEventTouch, 0, 0, 0, 0, 0, 0, 0, true, 0);
    setIntegerValue(hand, kDTSFieldDigitizerIsDisplayIntegrated, 1);
    uint32_t mask = phase == UITouchPhaseMoved ? kDTSDigitizerEventPosition : (kDTSDigitizerEventRange | kDTSDigitizerEventTouch);
    IOHIDEventRef finger = createFingerEvent(kCFAllocatorDefault, time, 1, 2, mask, location.x, location.y, 0, 0, 0,
                                             5, 5, 1, 1, 1, touching, touching, 0);
    setIntegerValue(finger, kDTSFieldDigitizerIsDisplayIntegrated, 1);
    appendEvent(hand, finger, 0);
    CFRelease(finger);
    return hand;
}

// MARK: UIKit SPI

@interface UITouch (DTSPrivate)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setGestureView:(UIView *)view;
- (void)setTapCount:(NSUInteger)count;
- (void)setIsTap:(BOOL)isTap;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setPhase:(UITouchPhase)phase;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)resetPrevious;
- (void)_setIsFirstTouchForView:(BOOL)first;
- (void)_setHidEvent:(IOHIDEventRef)event;
@end

@interface UIEvent (DTSPrivate)
- (void)_clearTouches;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_setHIDEvent:(IOHIDEventRef)event;
@end

@interface UIApplication (DTSPrivate)
- (UIEvent *)_touchesEvent;
- (UIEvent *)_touchesEventForWindow:(UIWindow *)window;
@end

@interface UIView (DTSPrivate)
- (id)_hitTestWithContext:(id)context;
@end

/// The responder a real touch at `point` goes to. Since iOS 18 SwiftUI views take touches
/// through a gesture container that only `_hitTestWithContext:` returns (as KIF does);
/// `hitTest:withEvent:` gives the hosting view, which SwiftUI's gestures ignore.
static UIView *TouchTarget(UIWindow *window, CGPoint point) {
    UIView *hit = [window hitTest:point withEvent:nil] ?: window;
    static Class contextClass;
    static SEL contextSelector;
    static BOOL supported;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        contextClass = NSClassFromString(@"_UIHitTestContext");
        contextSelector = NSSelectorFromString(@"contextWithPoint:radius:");
        supported = [contextClass respondsToSelector:contextSelector]
            && [UIView instancesRespondToSelector:@selector(_hitTestWithContext:)];
    });
    if (!supported) return hit;
    id context = ((id (*)(id, SEL, CGPoint, CGFloat))objc_msgSend)(contextClass, contextSelector, point, 0);
    if (context == nil) return hit;
    for (UIView *view = hit; view != nil; view = view.superview) {
        id found = [view _hitTestWithContext:context];
        if (found != nil) return found;
    }
    return hit;
}

@implementation DTSTouch {
    BOOL _throughUIKit;
    UITouch *_touch;
    UIWindow *_window;
    CGPoint _location;
}

+ (BOOL)isAvailable {
    static BOOL available;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSString *> *touch = @[@"setWindow:", @"setView:", @"setTapCount:", @"setTimestamp:", @"setPhase:",
                                       @"_setLocationInWindow:resetPrevious:", @"_setIsFirstTouchForView:", @"_setHidEvent:"];
        // _touchesEvent returns a UITouchesEvent; the touch list methods are its own.
        NSArray<NSString *> *event = @[@"_clearTouches", @"_addTouch:forDelayedDelivery:", @"_setHIDEvent:"];
        Class touchesEvent = NSClassFromString(@"UITouchesEvent") ?: UIEvent.class;
        BOOL ok = LoadIOKit() && [UIApplication instancesRespondToSelector:@selector(_touchesEvent)];
        for (NSString *name in touch) ok = ok && [UITouch instancesRespondToSelector:NSSelectorFromString(name)];
        for (NSString *name in event) ok = ok && [touchesEvent instancesRespondToSelector:NSSelectorFromString(name)];
        available = ok;
    });
    return available;
}

+ (instancetype)beginAtPoint:(CGPoint)point inWindow:(UIWindow *)window {
    if (!self.isAvailable) return nil;
    DTSTouch *synth = [[self alloc] init];
    synth->_window = window;
    synth->_location = point;
    UITouch *touch = [[UITouch alloc] init];
    synth->_touch = touch;
    UIView *view = TouchTarget(window, point);
    [touch setWindow:window];
    [touch setTapCount:1];
    [touch _setLocationInWindow:point resetPrevious:YES];
    [touch setView:view];
    if ([touch respondsToSelector:@selector(setGestureView:)]) [touch setGestureView:view];
    [touch _setIsFirstTouchForView:YES];
    // Gone on iOS 27; older systems want it.
    if ([touch respondsToSelector:@selector(setIsTap:)]) [touch setIsTap:NO];
    [synth send:UITouchPhaseBegan];
    return synth;
}

- (void)moveToPoint:(CGPoint)point {
    if (_touch == nil) return;
    _location = point;
    [_touch _setLocationInWindow:point resetPrevious:NO];
    [self send:UITouchPhaseMoved];
}

- (void)end {
    if (_touch == nil) return;
    [self send:UITouchPhaseEnded];
    _touch = nil;
}

- (void)send:(UITouchPhase)phase {
    [_touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
    [_touch setPhase:phase];
    // The digitizer reports in the screen's fixed (native, portrait) coordinates; UIKit
    // rotates them to the interface. The Duo's inner screen runs landscape, so window
    // coordinates here would land the touch somewhere else entirely.
    CGPoint native = [_window convertPoint:_location toCoordinateSpace:_window.screen.fixedCoordinateSpace];
    IOHIDEventRef hid = CreateHandEvent(native, phase);
    [_touch _setHidEvent:hid];
    // Newer iOS keeps a touches event per window; _touchesEvent can be nil there.
    UIApplication *app = UIApplication.sharedApplication;
    UIEvent *event = [app respondsToSelector:@selector(_touchesEventForWindow:)] ? [app _touchesEventForWindow:_window] : nil;
    if (event == nil) event = [app _touchesEvent];
    // UIKit's own event goes through UIApplication, which also drives gesture recognizers.
    // UIKit makes it with the first real touch; before that (unit tests) make one, which
    // UIApplication drops, and send it to the window: views get touches, recognizers don't.
    BOOL uikitEvent = event != nil;
    if (phase == UITouchPhaseBegan) _throughUIKit = uikitEvent;
    static UIEvent *ownEvent;
    if (event == nil) {
        if (ownEvent == nil) {
            Class cls = NSClassFromString(@"UITouchesEvent");
            SEL init = NSSelectorFromString(@"_init");
            if ([cls instancesRespondToSelector:init]) ownEvent = ((id (*)(id, SEL))objc_msgSend)([cls alloc], init);
        }
        event = ownEvent;
    }
    if (event == nil) {
        CFRelease(hid);
        return;
    }
    [event _clearTouches];
    [event _setHIDEvent:hid];
    [event _addTouch:_touch forDelayedDelivery:NO];
    if (uikitEvent) {
        [app sendEvent:event];
    } else {
        [_window sendEvent:event];
    }
    CFRelease(hid);
}

- (BOOL)isDeliveredThroughUIKit {
    return _throughUIKit;
}

+ (BOOL)tapAtPoint:(CGPoint)point inWindow:(UIWindow *)window {
    DTSTouch *touch = [self beginAtPoint:point inWindow:window];
    if (touch == nil) return NO;
    [touch end];
    return touch.isDeliveredThroughUIKit;
}

@end
