//
//  PreferenceInfo.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "PreferenceInfo.h"

extern NSString *const kPreferencePanelDidLoadNotification;

@implementation PreferenceInfo

+ (instancetype)infoForPreferenceWithKey:(NSString *)key
                                    type:(PreferenceInfoType)type
                                 control:(NSControl *)control {
    PreferenceInfo *info = [[[self alloc] init] autorelease];
    info.key = key;
    info.type = type;
    info.control = control;
    return info;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _range = NSMakeRange(0, INT_MAX);
    }
    return self;
}

- (void)dealloc {
    [_key release];
    [_control release];
    [_shouldBeEnabled release];
    [_onChange release];
    [_customSettingChangedHandler release];
    [_onUpdate release];
    [_observer release];
    [super dealloc];
}

- (void)setObserver:(void (^)())observer {
    [_observer autorelease];
    _observer = [observer copy];
    // wait until the control is properly set up and then update its value
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_preferencePanelDidLoad:)
                                                 name:kPreferencePanelDidLoadNotification
                                               object:nil];
}

- (void)_preferencePanelDidLoad:(NSNotification *)notification
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kPreferencePanelDidLoadNotification object:nil];
    if (self.observer) {
        self.observer();
    }
}

@end
