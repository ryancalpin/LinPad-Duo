//
//  TerminalView.h
//  iSH
//
//  Created by Theodore Dubois on 11/3/17.
//

#import <UIKit/UIKit.h>
#import "Terminal.h"

enum OverrideAppearance {
    OverrideAppearanceNone,
    OverrideAppearanceLight,
    OverrideAppearanceDark,
};

@interface TerminalView : UIView <UITextInput, WKScriptMessageHandler, UIScrollViewDelegate>

@property IBInspectable (nonatomic) BOOL canBecomeFirstResponder;

@property (nonatomic) CGFloat overrideFontSize;
@property (readonly) CGFloat effectiveFontSize;
@property (nonatomic) enum OverrideAppearance overrideAppearance;

@property (nonatomic) UIKeyboardAppearance keyboardAppearance;

@property (weak) IBOutlet UIInputView *inputAccessoryView;

/// Laptop pose's deck is up (DesktopKit's OnScreenKeyboard): it is the keyboard, so the
/// terminal keeps iOS's keyboard down while it stays first responder for the deck's keys.
@property (class, readonly) BOOL laptopDeckShown;
/// The deck is up and no hardware keyboard is attached: the terminal doesn't take first responder.
@property (class, readonly) BOOL suppressesSystemKeyboard;
@property (weak) IBOutlet UIButton *controlKey;

@property (nonatomic) Terminal *terminal;

@end
