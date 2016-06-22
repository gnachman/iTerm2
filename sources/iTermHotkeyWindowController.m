//
//  iTermHotkeyWindowController.m
//  iTerm2
//
//  Created by George Nachman on 6/21/16.
//
//

#import "iTermHotkeyWindowController.h"
#import "iTermHotKeyModel.h"
#import "iTermKeyBindingMgr.h"
#import "iTermShortcutInputView.h"

@interface iTermHotkeyWindowController ()<iTermShortcutInputViewDelegate>

@property(nonatomic, assign) IBOutlet iTermShortcutInputView *hotkey;
@property(nonatomic, assign) IBOutlet NSButton *autoHide;
@property(nonatomic, assign) IBOutlet NSButton *showAfterAutoHiding;
@property(nonatomic, assign) IBOutlet NSButton *revealOnDockClick;
@property(nonatomic, assign) IBOutlet NSButton *revealOnDockClickOnlyIfNoOpenWindowsExist;
@property(nonatomic, assign) IBOutlet NSButton *animate;
@end

@implementation iTermHotkeyWindowController

- (instancetype)init {
    return [super initWithWindowNibName:NSStringFromClass(self.class)];
}

- (void)dealloc {
    [_model release];
    [super dealloc];
}

- (void)awakeFromNib {
    _hotkey.stringValue = self.model.keyCombination ? [iTermKeyBindingMgr formatKeyCombination:self.model.keyCombination] : @"";
    self.autoHide.state = self.model.autoHide ? NSOnState : NSOffState;
    self.showAfterAutoHiding.state = self.model.showAfterAutoHiding ? NSOnState : NSOffState;
    self.revealOnDockClick.state = self.model.revealOnDockClick ? NSOnState : NSOffState;
    self.revealOnDockClickOnlyIfNoOpenWindowsExist.state = self.model.revealOnDockClickOnlyIfNoOpenWindowsExist ? NSOnState : NSOffState;
    self.animate.state = self.model.animate ? NSOnState : NSOffState;
    [self updateEnabledStates];
}

#pragma mark - Private

- (void)updateEnabledStates {
    BOOL haveHotKey = self.model.keyCombination.length > 0;
    self.autoHide.enabled = haveHotKey;
    self.showAfterAutoHiding.enabled = _autoHide.state == NSOnState && haveHotKey;
    self.revealOnDockClick.enabled = haveHotKey;
    self.revealOnDockClickOnlyIfNoOpenWindowsExist.enabled = self.revealOnDockClick.state == NSOnState && haveHotKey;
    self.animate.enabled = haveHotKey;
}

#pragma mark - Actions

- (IBAction)ok:(id)sender {
    self.model.autoHide = self.autoHide.state == NSOnState;
    self.model.showAfterAutoHiding = self.showAfterAutoHiding.state == NSOnState;
    self.model.revealOnDockClick = self.revealOnDockClick.state == NSOnState;
    self.model.revealOnDockClickOnlyIfNoOpenWindowsExist = self.revealOnDockClickOnlyIfNoOpenWindowsExist.state == NSOnState;
    self.model.animate = self.animate.state == NSOnState;
    [self.delegate hotKeyWindowController:self didFinishWithOK:YES];
}

- (IBAction)cancel:(id)sender {
    [self.delegate hotKeyWindowController:self didFinishWithOK:NO];
}

- (IBAction)settingChanged:(id)sender {
    [self updateEnabledStates];
}

#pragma mark - iTermShortcutInputViewDelegate

// Note: This is called directly by iTermHotKeyController when the action requires key remapping
// to be disabled so the shortcut can be input properly. In this case, |view| will be nil.
- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    unsigned int keyMods;
    unsigned short keyCode;
    NSString *unmodkeystr;
    
    keyMods = [event modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    keyCode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    
    // turn off all the other modifier bits we don't care about
    unsigned int theModifiers = (keyMods &
                                 (NSAlternateKeyMask | NSControlKeyMask | NSShiftKeyMask |
                                  NSCommandKeyMask | NSNumericPadKeyMask));
    
    // On some keyboards, arrow keys have NSNumericPadKeyMask bit set; manually set it for keyboards that don't
    if (keyCode >= NSUpArrowFunctionKey && keyCode <= NSRightArrowFunctionKey) {
        theModifiers |= NSNumericPadKeyMask;
    }
    self.model.keyCombination = [NSString stringWithFormat:@"0x%x-0x%x", keyCode, theModifiers];
    
    [self.hotkey setStringValue:[iTermKeyBindingMgr formatKeyCombination:self.model.keyCombination]];
    [self updateEnabledStates];
}

@end
