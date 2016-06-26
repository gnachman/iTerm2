#import "iTermHotkeyPreferencesWindowController.h"

#import "iTermCarbonHotKeyController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermShortcutInputView.h"
#import "NSStringITerm.h"

@implementation iTermHotkeyPreferencesModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _autoHide = YES;
        _animate = YES;
    }
    return self;
}

- (void)dealloc {
    [_characters release];
    [_charactersIgnoringModifiers release];
    [super dealloc];
}

- (NSDictionary<NSString *, id> *)dictionaryValue {
    if (self.hotKeyAssigned) {
        return @{ KEY_HOTKEY_KEY_CODE: @(self.keyCode),
                  KEY_HOTKEY_CHARACTERS: self.characters ?: @"",
                  KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS: self.charactersIgnoringModifiers ?: @"",
                  KEY_HOTKEY_MODIFIER_FLAGS: @(self.modifiers),
                  KEY_HOTKEY_AUTOHIDE: @(self.autoHide),
                  KEY_HOTKEY_REOPEN_ON_ACTIVATION: @(self.showAutoHiddenWindowOnAppActivation),
                  KEY_HOTKEY_ANIMATE: @(self.animate),
                  KEY_HOTKEY_DOCK_CLICK_ACTION: @(self.dockPreference),
                  KEY_HAS_HOTKEY: @YES };
    } else {
        return @{ KEY_HAS_HOTKEY: @NO };
    }
}

@end

@interface iTermHotkeyPreferencesWindowController()<iTermShortcutInputViewDelegate>
@property(nonatomic, copy) NSString *pendingExplanation;
@end

@implementation iTermHotkeyPreferencesWindowController {
    IBOutlet iTermShortcutInputView *_hotKey;
    IBOutlet NSButton *_ok;
    IBOutlet NSTextField *_explanation;
    IBOutlet NSTextField *_duplicateWarning;

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
    [_pendingExplanation release];
    [super dealloc];
}

- (void)awakeFromNib {
    if (_pendingExplanation) {
        _explanation.stringValue = _pendingExplanation;
        self.pendingExplanation = nil;
    }
}

#pragma mark - APIs

- (void)setModel:(iTermHotkeyPreferencesModel *)model {
    [self window];
    [_model autorelease];
    _model = [model retain];
    [self modelDidChange];
    [self updateViewsEnabled];
}

- (void)setExplanation:(NSString *)explanation {
    if (_explanation) {
        _explanation.stringValue = explanation;
    } else {
        self.pendingExplanation = explanation;
    }
}

#pragma mark - Private

- (void)updateViewsEnabled {
    NSArray<NSView *> *buttons =
        @[ _autoHide, _showAutoHiddenWindowOnAppActivation, _animate, _doNotShowOnDockClick,
           _alwaysShowOnDockClick, _showIfNoWindowsOpenOnDockClick, _ok ];
    for (NSButton *button in buttons) {
        button.enabled = self.model.hotKeyAssigned;
    }
    _duplicateWarning.hidden = ![self.descriptorsInUseByOtherProfiles containsObject:self.descriptor];
    _showAutoHiddenWindowOnAppActivation.enabled = (_autoHide.state == NSOnState);
}

- (iTermHotKeyDescriptor *)descriptor {
    return [iTermHotKeyDescriptor descriptorWithKeyCode:self.model.keyCode
                                              modifiers:self.model.modifiers];
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
    _model.modifiers = (event.modifierFlags & kCarbonHotKeyModifiersMask);
    _model.hotKeyAssigned = YES;

    [self modelDidChange];
    NSString *identifier = [iTermKeyBindingMgr identifierForCharacterIgnoringModifiers:[event.charactersIgnoringModifiers firstCharacter]
                                                                             modifiers:event.modifierFlags];
    [view setStringValue:[iTermKeyBindingMgr formatKeyCombination:identifier]];
}

@end

