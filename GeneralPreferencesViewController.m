//
//  GeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "GeneralPreferencesViewController.h"
#import "iTermPreferences.h"

typedef enum {
    kPreferenceInfoTypeCheckbox
} PreferenceInfoType;

@interface PreferenceInfo : NSObject

@property(nonatomic, retain) NSString *key;
@property(nonatomic, assign) PreferenceInfoType type;
@property(nonatomic, retain) NSView *control;

// Called on GeneralPreferencesViewController when value changes with PreferenceInfo as object.
@property(nonatomic, assign) SEL selector;

+ (instancetype)infoForPreferenceWithKey:(NSString *)key
                                    type:(PreferenceInfoType)type
                                 control:(NSView *)control;
@end

@implementation PreferenceInfo

+ (instancetype)infoForPreferenceWithKey:(NSString *)key
                                    type:(PreferenceInfoType)type
                                 control:(NSView *)control {
    PreferenceInfo *info = [[self alloc] init];
    info.key = key;
    info.type = type;
    info.control = control;
    return info;
}

- (void)dealloc {
    [_key release];
    [_control release];
    [super dealloc];
}

@end

@implementation GeneralPreferencesViewController {
    // open bookmarks when iterm starts
    IBOutlet NSButton *_openBookmark;
    NSMapTable *_keyMap;  // Maps views to PreferenceInfo.
}

- (void)dealloc {
    [_keyMap release];
    [super dealloc];
}

- (void)awakeFromNib {
    _keyMap = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory
                                        valueOptions:NSPointerFunctionsStrongMemory
                                            capacity:16];
    [self defineControl:_openBookmark
                    key:kPreferenceKeyOpenBookmark
                   type:kPreferenceInfoTypeCheckbox];
}

- (void)defineControl:(NSView *)control key:(NSString *)key type:(PreferenceInfoType)type {
    assert(![_keyMap objectForKey:key]);
    assert(key);
    assert(control);

    [_keyMap setObject:[PreferenceInfo infoForPreferenceWithKey:key
                                                           type:type
                                                        control:control]
                forKey:control];
    switch (type) {
        case kPreferenceInfoTypeCheckbox: {
            assert([control isKindOfClass:[NSButton class]]);
            NSButton *button = (NSButton *)control;
            button.state = [iTermPreferences boolForKey:key] ? NSOnState : NSOffState;
            break;
        }
            
        default:
            assert(false);
    }
}

- (PreferenceInfo *)infoForControl:(NSView *)control {
    PreferenceInfo *info = [_keyMap objectForKey:control];
    assert(info);
    return info;
}

- (IBAction)settingChanged:(id)sender {
    PreferenceInfo *info = [self infoForControl:sender];
    if (info) {
        switch (info.type) {
            case kPreferenceInfoTypeCheckbox:
                [iTermPreferences setBool:([sender state] == NSOnState) forKey:info.key];
                break;
                
            default:
                assert(false);
        }
    }
    if (info.selector) {
        [self performSelector:info.selector withObject:info];
    }
}

@end
