#import "iTermHotkeyPreferencesWindowController.h"

#import "iTermShortcutInputView.h"
#import "NSStringITerm.h"

@implementation iTermHotkeyPreferencesModel

- (void)dealloc {
    [_characters release];
    [_charactersIgnoringModifiers release];
    [super dealloc];
}

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
    [self updateViewsEnabled];
}

#pragma mark - Private

- (void)updateViewsEnabled {
    NSArray<NSView *> *buttons =
        @[ _autoHide, _showAutoHiddenWindowOnAppActivation, _animate, _doNotShowOnDockClick,
           _alwaysShowOnDockClick, _showIfNoWindowsOpenOnDockClick ];
    for (NSButton *button in buttons) {
        button.enabled = self.model.hotKeyAssigned;
    }
}

- (void)modelDidChange {
    [_hotKey setKeyCode:_model.keyCode
              modifiers:_model.modifiers
              character:[_model.charactersIgnoringModifiers firstCharacter]];
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
    [self updateViewsEnabled];
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
    _model.characters = [event characters];
    _model.charactersIgnoringModifiers = [event charactersIgnoringModifiers];
    _model.modifiers = event.modifierFlags;
    _model.hotKeyAssigned = YES;

    [self modelDidChange];
}

@end

