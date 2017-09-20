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
    [_key release];
    [_control release];
    [_shouldBeEnabled release];
    [_onChange release];
    [_customSettingChangedHandler release];
    [_willChange release];
    [_controlTextDidEndEditing release];
    [_onUpdate release];
    [_observer release];
    [super dealloc];
}

- (void)setObserver:(void (^)(void))observer {
    [_observer autorelease];
    _observer = [observer copy];
}

- (void)clearBlocks {
    self.shouldBeEnabled = nil;
    self.observer = nil;
    self.onChange = nil;
    self.willChange = nil;
    self.onUpdate = nil;
    self.customSettingChangedHandler = nil;
    self.controlTextDidEndEditing = nil;    
}

#pragma mark - Notifications

- (void)preferencePanelDidLoad:(NSNotification *)notification {
    if (self.observer) {
        self.observer();
    }
}

@end
