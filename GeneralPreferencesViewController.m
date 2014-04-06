//
//  GeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "GeneralPreferencesViewController.h"

#import "CommandHistory.h"
#import "iTermApplicationDelegate.h"
#import "iTermPreferences.h"
#import "PasteboardHistory.h"
#import "WindowArrangements.h"

typedef enum {
    kPreferenceInfoTypeCheckbox,
    kPreferenceInfoTypeIntegerTextField
} PreferenceInfoType;

@interface PreferenceInfo : NSObject

@property(nonatomic, retain) NSString *key;
@property(nonatomic, assign) PreferenceInfoType type;
@property(nonatomic, retain) NSControl *control;

// A function that indicates if the control should be enabled. If nil, then the control is always
// enabled.
@property(nonatomic, copy) BOOL (^shouldBeEnabled)();

// Called when value changes with PreferenceInfo as object.
@property(nonatomic, assign) void (^onChange)();

+ (instancetype)infoForPreferenceWithKey:(NSString *)key
                                    type:(PreferenceInfoType)type
                                 control:(NSControl *)control;

@end

@implementation PreferenceInfo

+ (instancetype)infoForPreferenceWithKey:(NSString *)key
                                    type:(PreferenceInfoType)type
                                 control:(NSControl *)control {
    PreferenceInfo *info = [[self alloc] init];
    info.key = key;
    info.type = type;
    info.control = control;
    return info;
}

- (void)dealloc {
    [_key release];
    [_control release];
    [_shouldBeEnabled release];
    [super dealloc];
}

@end

@implementation GeneralPreferencesViewController {
    // open bookmarks when iterm starts
    IBOutlet NSButton *_openBookmark;
    
    // Open saved window arrangement at startup
    IBOutlet NSButton *_openArrangementAtStartup;

    // Quit when all windows are closed
    IBOutlet NSButton *_quitWhenAllWindowsClosed;

    // Confirm closing multiple sessions
    IBOutlet id _confirmClosingMultipleSessions;

    // Warn when quitting
    IBOutlet id _promptOnQuit;

    // Instant replay memory usage.
    IBOutlet NSTextField *_irMemory;

    // Save copy paste history
    IBOutlet NSButton *_savePasteHistory;

    // Enable bonjour
    IBOutlet NSButton *_enableBonjour;

    // Check for updates automatically
    IBOutlet NSButton *_checkUpdate;

    NSMapTable *_keyMap;  // Maps views to PreferenceInfo.
}

- (void)dealloc {
    [_keyMap release];
    [super dealloc];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(savedArrangementChanged:)
                                                     name:kSavedArrangementDidChangeNotification
                                                   object:nil];
        
    }
    return self;
}

- (void)awakeFromNib {
    _keyMap = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory
                                        valueOptions:NSPointerFunctionsStrongMemory
                                            capacity:16];
    
    PreferenceInfo *info;
    
    [self defineControl:_openBookmark
                    key:kPreferenceKeyOpenBookmark
                   type:kPreferenceInfoTypeCheckbox];
    
    info = [self defineControl:_openArrangementAtStartup
                           key:kPreferenceKeyOpenArrangementAtStartup
                          type:kPreferenceInfoTypeCheckbox];
    info.shouldBeEnabled = ^BOOL() { return [WindowArrangements count] > 0; };

    [self defineControl:_quitWhenAllWindowsClosed
                    key:kPreferenceKeyQuitWhenAllWindowsClosed
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_confirmClosingMultipleSessions
                    key:kPreferenceKeyConfirmClosingMultipleTabs
                   type:kPreferenceInfoTypeCheckbox];
    
    [self defineControl:_promptOnQuit
                    key:kPreferenceKeyPromptOnQuit
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_irMemory
                    key:kPreferenceKeyInstantReplayMemoryMegabytes
                   type:kPreferenceInfoTypeIntegerTextField];

    info = [self defineControl:_savePasteHistory
                           key:kPreferenceKeySavePasteAndCommandHistory
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        if (![iTermPreferences boolForKey:kPreferenceKeySavePasteAndCommandHistory]) {
            [[PasteboardHistory sharedInstance] eraseHistory];
            [[CommandHistory sharedInstance] eraseHistory];
        }
    };
    
    [self defineControl:_enableBonjour
                    key:kPreferenceKeyAddBonjourHostsToProfiles
                            type:kPreferenceInfoTypeCheckbox];
    
    [self defineControl:_checkUpdate
                    key:kPreferenceKeyCheckForUpdatesAutomatically
                   type:kPreferenceInfoTypeCheckbox];
}

- (void)updateValueForInfo:(PreferenceInfo *)info {
    switch (info.type) {
        case kPreferenceInfoTypeCheckbox: {
            assert([info.control isKindOfClass:[NSButton class]]);
            NSButton *button = (NSButton *)info.control;
            button.state = [iTermPreferences boolForKey:info.key] ? NSOnState : NSOffState;
            break;
        }
            
        case kPreferenceInfoTypeIntegerTextField: {
            assert([info.control isKindOfClass:[NSTextField class]]);
            NSTextField *field = (NSTextField *)info.control;
            field.intValue = [iTermPreferences intForKey:info.key];
            break;
        }
            
        default:
            assert(false);
    }
}

- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                             type:(PreferenceInfoType)type {
    assert(![_keyMap objectForKey:key]);
    assert(key);
    assert(control);
    assert([iTermPreferences keyHasDefaultValue:key]);

    PreferenceInfo *info = [PreferenceInfo infoForPreferenceWithKey:key
                                                               type:type
                                                            control:control];
    [_keyMap setObject:info forKey:control];
    [self updateValueForInfo:info];
    
    return info;
}

- (PreferenceInfo *)infoForControl:(NSControl *)control {
    PreferenceInfo *info = [_keyMap objectForKey:control];
    assert(info);
    return info;
}

- (IBAction)settingChanged:(id)sender {
    PreferenceInfo *info = [self infoForControl:sender];
    assert(info);

    switch (info.type) {
        case kPreferenceInfoTypeCheckbox:
            [iTermPreferences setBool:([sender state] == NSOnState) forKey:info.key];
            break;
            
        case kPreferenceInfoTypeIntegerTextField:
            [iTermPreferences setInt:[sender intValue] forKey:info.key];
            break;

        default:
            assert(false);
    }
    if (info.onChange) {
        info.onChange();
    }
}

- (void)updateEnabledStateForInfo:(PreferenceInfo *)info {
    if (info.shouldBeEnabled) {
        [info.control setEnabled:info.shouldBeEnabled()];
    }
}

- (void)updateEnabledState {
    for (NSControl *control in _keyMap) {
        PreferenceInfo *info = [self infoForControl:control];
        [self updateEnabledStateForInfo:info];
    }
}

#pragma mark - Notifications

- (void)savedArrangementChanged:(id)sender {
    PreferenceInfo *info = [self infoForControl:_openArrangementAtStartup];
    [self updateValueForInfo:info];
    [self updateEnabledStateForInfo:info];
}


@end
