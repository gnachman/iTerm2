#import "iTermHotkeyPreferencesWindowController.h"

#import "iTermAdditionalHotKeyObjectValue.h"
#import "iTermCarbonHotKeyController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermShortcutInputView.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSStringITerm.h"

@interface iTermHotkeyPreferencesWindowController()<iTermShortcutInputViewDelegate, NSTableViewDelegate, NSTableViewDataSource>
@property(nonatomic, copy) NSString *pendingExplanation;
@end

@implementation iTermHotkeyPreferencesWindowController {
    IBOutlet iTermShortcutInputView *_hotKey;
    IBOutlet NSButton *_ok;
    IBOutlet NSTextField *_explanation;
    IBOutlet NSTextField *_duplicateWarning;
    IBOutlet NSTextField *_duplicateWarningForModifierActivation;

    IBOutlet NSButton *_activateWithModifier;
    IBOutlet NSPopUpButton *_modifierActivation;

    // Check boxes
    IBOutlet NSButton *_pinned;
    IBOutlet NSButton *_showAutoHiddenWindowOnAppActivation;
    IBOutlet NSButton *_animate;
    IBOutlet NSButton *_floats;
    
    // Radio buttons
    IBOutlet NSButton *_doNotShowOnDockClick;
    IBOutlet NSButton *_alwaysShowOnDockClick;
    IBOutlet NSButton *_showIfNoWindowsOpenOnDockClick;
    
    IBOutlet NSButton *_editAdditionalButton;
    IBOutlet NSButton *_removeAdditional;
    IBOutlet NSPanel *_editAdditionalWindow;
    IBOutlet NSTableView *_tableView;
    NSMutableArray<iTermShortcut *> *_mutableShortcuts;  // Model for _tableView. Only nonnil while additional shortcuts sheet is open.
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
        @[ _pinned, _showAutoHiddenWindowOnAppActivation, _animate, _floats, _doNotShowOnDockClick,
           _alwaysShowOnDockClick, _showIfNoWindowsOpenOnDockClick ];
    for (NSButton *button in buttons) {
        button.enabled = self.model.hotKeyAssigned;
    }
    _duplicateWarning.hidden = ![self.descriptorsInUseByOtherProfiles containsObject:self.model.primaryShortcut.descriptor];
    _duplicateWarningForModifierActivation.hidden = ![self.descriptorsInUseByOtherProfiles containsObject:self.modifierActivationDescriptor];
    _showAutoHiddenWindowOnAppActivation.enabled = (self.model.hotKeyAssigned && _pinned.state == NSOffState);
    _modifierActivation.enabled = (_activateWithModifier.state == NSOnState);
    _editAdditionalButton.enabled = self.model.primaryShortcut.isAssigned;
}

- (iTermHotKeyDescriptor *)modifierActivationDescriptor {
    if (self.model.hasModifierActivation) {
        return [iTermHotKeyDescriptor descriptorWithModifierActivation:self.model.modifierActivation];
    } else {
        return nil;
    }
}

- (void)modelDidChange {
    _activateWithModifier.state = _model.hasModifierActivation ? NSOnState : NSOffState;
    [_modifierActivation selectItemWithTag:_model.modifierActivation];
    [_hotKey setShortcut:_model.primaryShortcut];

    _pinned.state = _model.autoHide ? NSOffState : NSOnState;
    _showAutoHiddenWindowOnAppActivation.enabled = _model.autoHide;
    _showAutoHiddenWindowOnAppActivation.state = _model.showAutoHiddenWindowOnAppActivation ? NSOnState : NSOffState;
    _animate.state = _model.animate ? NSOnState : NSOffState;
    _floats.state = _model.floats ? NSOnState : NSOffState;

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

- (void)updateAdditionalHotKeysViews {
    _removeAdditional.enabled = _tableView.numberOfSelectedRows > 0;
}

#pragma mark - Actions

- (IBAction)settingChanged:(id)sender {
    _model.hasModifierActivation = _activateWithModifier.state == NSOnState;
    _model.modifierActivation = [_modifierActivation selectedTag];

    _model.autoHide = _pinned.state == NSOffState;
    _model.showAutoHiddenWindowOnAppActivation = _showAutoHiddenWindowOnAppActivation.state == NSOnState;
    _model.animate = _animate.state == NSOnState;
    _model.floats = _floats.state == NSOnState;

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
    [[sender window].sheetParent endSheet:[sender window] returnCode:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender {
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseCancel];
}

- (IBAction)editAdditionalHotKeys:(id)sender {
    _mutableShortcuts = [self.model.alternateShortcuts mutableCopy];
    [_tableView reloadData];
    [self.window beginSheet:_editAdditionalWindow completionHandler:^(NSModalResponse returnCode) {
        self.model.alternateShortcuts = [_mutableShortcuts filteredArrayUsingBlock:^BOOL(iTermShortcut *shortcut) {
            return shortcut.charactersIgnoringModifiers.length > 0;
        }];
        [_mutableShortcuts release];
        _mutableShortcuts = nil;
    }];
    [self updateAdditionalHotKeysViews];
}

- (IBAction)addAdditionalShortcut:(id)sender {
    [_mutableShortcuts addObject:[[[iTermShortcut alloc] init] autorelease]];
    [_tableView reloadData];
    [self updateAdditionalHotKeysViews];
}

- (IBAction)removeAdditionalShortcut:(id)sender {
    [_mutableShortcuts removeObjectsAtIndexes:_tableView.selectedRowIndexes];
    [_tableView reloadData];
    [self updateAdditionalHotKeysViews];
}

#pragma mark - iTermShortcutInputViewDelegate

- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    if (!event && _model.alternateShortcuts.count) {
        _model.primaryShortcut = _model.alternateShortcuts.firstObject;
        [view setStringValue:_model.primaryShortcut.stringValue];
        _model.alternateShortcuts = [_model.alternateShortcuts arrayByRemovingFirstObject];
        [self modelDidChange];
    } else {
        _model.primaryShortcut = event ? [iTermShortcut shortcutWithEvent:event] : nil;
        [self modelDidChange];
    }
    [self updateViewsEnabled];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    _removeAdditional.enabled = _tableView.selectedRow != -1;
    [self updateAdditionalHotKeysViews];
}

#pragma mark - NSTableViewDatasource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _mutableShortcuts.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    return [iTermAdditionalHotKeyObjectValue objectValueWithShortcut:_mutableShortcuts[row]
                                                    inUseDescriptors:self.descriptorsInUseByOtherProfiles];
}

@end

