#import "iTermHotkeyPreferencesWindowController.h"

#import "iTermShortcutInputView.h"
#import "NSStringITerm.h"

@implementation iTermHotkeyPreferencesModel
@end

@interface iTermHotkeyPreferencesWindowController()<iTermShortcutInputViewDelegate>
@end

@implementation iTermHotkeyPreferencesWindowController {
    IBOutlet iTermShortcutInputView *_hotKey;
    
    // Check boxes
    IBOutlet NSButton *_autoHide;
    IBOutlet NSButton *_showAutoHiddenWindowOnAppActivation;
    IBOutlet NSButton *_animate;
    
    // Radio buttons
    IBOutlet NSButton *_doNotShowOnDockClick;
    IBOutlet NSButton *_alwaysShowOnDockClick;
    IBOutlet NSButton *_showIfNoWindowsOpenOnDockClick;
}

- (instancetype)init {
    return [super initWithWindowNibName:NSStringFromClass([self class])];
}

- (void)dealloc {
    [_model release];
    [super dealloc];
}

#pragma mark - APIs

- (void)setModel:(iTermHotkeyPreferencesModel *)model {
    [self window];
    [_model autorelease];
    _model = [model retain];
    [self modelDidChange];
}

#pragma mark - Private

- (void)modelDidChange {
    [_hotKey setKeyCode:_model.keyCode modifiers:_model.modifiers character:_model.character];
    _autoHide.state = _model.autoHide ? NSOnState : NSOffState;
    _showAutoHiddenWindowOnAppActivation.enabled = _model.autoHide;
    _showAutoHiddenWindowOnAppActivation.state = _model.showAutoHiddenWindowOnAppActivation ? NSOnState : NSOffState;
    _animate.state = _model.animate ? NSOnState : NSOffState;

    switch (_model.dockPreference) {
        case iTermHotKeyDockPreferenceDoNotShow:
            _doNotShowOnDockClick.state = NSOnState;
            break;
            
        case iTermHotKeyDockPreferenceAlwaysShow:
            _alwaysShowOnDockClick.state = NSOnState;
            break;
            
        case iTermHotKeyDockPreferenceShowIfNoOtherWindowsOpen:
            _showIfNoWindowsOpenOnDockClick.state = NSOnState;
            break;
    }
}

#pragma mark - Actions

- (IBAction)settingChanged:(id)sender {
    _model.autoHide = _autoHide.state == NSOnState;
    _model.showAutoHiddenWindowOnAppActivation = _showAutoHiddenWindowOnAppActivation.state == NSOnState;
    _model.animate = _animate.state == NSOnState;

    
    if (_showIfNoWindowsOpenOnDockClick.state == NSOnState) {
        _model.dockPreference = iTermHotKeyDockPreferenceShowIfNoOtherWindowsOpen;
    } else if (_alwaysShowOnDockClick.state == NSOnState) {
        _model.dockPreference = iTermHotKeyDockPreferenceAlwaysShow;
    } else {
        _model.dockPreference = iTermHotKeyDockPreferenceDoNotShow;
    }
    
    [self modelDidChange];
}

- (IBAction)ok:(id)sender {
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender {
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseCancel];
}

#pragma mark - iTermShortcutInputViewDelegate

- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    _model.keyCode = event.keyCode;
    _model.character = [[event charactersIgnoringModifiers] firstCharacter];
    _model.modifiers = event.modifierFlags;
    
    [self modelDidChange];
}

@end

