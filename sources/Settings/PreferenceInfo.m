//
//  PreferenceInfo.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "PreferenceInfo.h"
#import "PreferencePanel.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermUserDefaultsObserver.h"

@implementation PreferenceInfo {
    iTermUserDefaultsObserver *_userDefaultsObserver;
    iTermProfilePreferenceObserver *_profileObserver;
}

+ (instancetype)infoForPreferenceWithKey:(NSString *)key
                                    type:(PreferenceInfoType)type
                                 control:(NSView *)control {
    PreferenceInfo *info = [[self alloc] init];
    info.key = key;
    info.type = type;
    info.control = control;
    info->_searchKeywords = @[ key ];
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
    if (_observer) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:kPreferencePanelDidLoadNotification
                                                      object:nil];
    }
}

- (void)setObserver:(void (^)(void))observer {
    // The observer block is invoked once when the preference panel finishes loading (so the current
    // profile has a chance to be set first) and thereafter whenever the control's value changes.
    // Register for the panel-did-load notification only while there is a block to invoke — most
    // PreferenceInfos have no observer, and a per-instance registration makes teardown O(N²) when
    // the keyMap is cleared on close.
    if (observer && !_observer) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(preferencePanelDidLoad:)
                                                     name:kPreferencePanelDidLoadNotification
                                                   object:nil];
    } else if (!observer && _observer) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:kPreferencePanelDidLoadNotification
                                                      object:nil];
    }
    _observer = [observer copy];
}

- (void)addShouldBeEnabledDependencyOnSetting:(NSString *)key controller:(id<PreferenceController>)controller {
    __weak __typeof(controller) weakController = controller;
    __weak __typeof(self) weakSelf = self;
    if ([controller profileModel]) {
        if (!_profileObserver) {
            _profileObserver = [controller profileObserver];
        }
        [_profileObserver observeKey:key block:^(id before, id after) {
            __strong __typeof(self) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            [weakController updateEnabledStateForInfo:strongSelf];
        }];
        return;
    }
    if (!_userDefaultsObserver) {
        _userDefaultsObserver = [[iTermUserDefaultsObserver alloc] init];
    }
    [_userDefaultsObserver observeKey:key block:^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [weakController updateEnabledStateForInfo:strongSelf];
    }];
}

#pragma mark - Notifications

- (void)preferencePanelDidLoad:(NSNotification *)notification {
    if (self.observer) {
        self.observer();
    }
}

@end
