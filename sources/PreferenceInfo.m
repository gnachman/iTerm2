//
//  PreferenceInfo.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "PreferenceInfo.h"
#import "PreferencePanel.h"

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

- (instancetype)init {
    self = [super init];
    if (self) {
        _range = NSMakeRange(0, INT_MAX);
        // Observers' initial execution happens from the notification because it gives the current
        // profile a chance to get set before the observer runs.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(preferencePanelDidLoad:)
                                                     name:kPreferencePanelDidLoadNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setObserver:(void (^)(void))observer {
    _observer = [observer copy];
}

#pragma mark - Notifications

- (void)preferencePanelDidLoad:(NSNotification *)notification {
    if (self.observer) {
        self.observer();
    }
}

@end
