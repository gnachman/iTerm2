//
//  PreferenceInfo.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "PreferenceInfo.h"

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
    [super dealloc];
}

- (void)setObserver:(void (^)())observer {
    [_observer autorelease];
    _observer = [observer copy];
    // Call the observer after a delayed perform so that the current profile can be set and then the
    // control's value gets initialized.
    [self performSelector:@selector(callObserver) withObject:nil afterDelay:0];
}

- (void)callObserver {
    if (self.observer) {
        self.observer();
    }
}

@end
