//
//  iTermInitialDirectory.m
//  iTerm2
//
//  Created by George Nachman on 8/14/16.
//
//

#import "iTermInitialDirectory.h"

#import "iTermExpressionEvaluator.h"
#import "iTermProfilePreferences.h"

@implementation iTermInitialDirectory {
    NSString *_evaluated;
}

+ (iTermInitialDirectoryMode)modeForString:(NSString *)modeString
                                objectType:(iTermObjectType)objectType
                                   profile:(Profile *)profile
                           customDirectory:(NSString **)customDirectory {
    if ([modeString isEqualToString:kProfilePreferenceInitialDirectoryCustomValue]) {
        if (customDirectory) {
            *customDirectory = [iTermProfilePreferences stringForKey:KEY_WORKING_DIRECTORY inProfile:profile];
        }
        return iTermInitialDirectoryModeCustom;
    } else if ([modeString isEqualToString:kProfilePreferenceInitialDirectoryRecycleValue]) {
        return iTermInitialDirectoryModeRecycle;
    } else if ([modeString isEqualToString:kProfilePreferenceInitialDirectoryHomeValue]) {
        return iTermInitialDirectoryModeHome;
    } else if ([modeString isEqualToString:kProfilePreferenceInitialDirectoryAdvancedValue]) {
        NSString *key = nil;
        switch (objectType) {
            case iTermTabObject:
                key = [iTermProfilePreferences stringForKey:KEY_AWDS_TAB_OPTION inProfile:profile];
                if (customDirectory) {
                    *customDirectory = [iTermProfilePreferences stringForKey:KEY_AWDS_TAB_DIRECTORY inProfile:profile];
                }
                break;
            case iTermPaneObject:
                key = [iTermProfilePreferences stringForKey:KEY_AWDS_PANE_OPTION inProfile:profile];
                if (customDirectory) {
                    *customDirectory = [iTermProfilePreferences stringForKey:KEY_AWDS_PANE_DIRECTORY inProfile:profile];
                }
                break;
            case iTermWindowObject:
                key = [iTermProfilePreferences stringForKey:KEY_AWDS_WIN_OPTION inProfile:profile];
                if (customDirectory) {
                    *customDirectory = [iTermProfilePreferences stringForKey:KEY_AWDS_WIN_DIRECTORY inProfile:profile];
                }
                break;
        }
        assert(key);
        return [self modeForString:key
                        objectType:objectType
                           profile:profile
                   customDirectory:nil];
    }
    assert(false);
    return iTermInitialDirectoryModeHome;
}

+ (instancetype)initialDirectoryFromProfile:(Profile *)profile
                                 objectType:(iTermObjectType)objectType {
    iTermInitialDirectory *initialDirectory = [[iTermInitialDirectory alloc] init];
    NSString *customDirectorySetting = [iTermProfilePreferences stringForKey:KEY_CUSTOM_DIRECTORY inProfile:profile];
    NSString *customDirectory = nil;
    initialDirectory.mode = [self modeForString:customDirectorySetting
                                     objectType:objectType
                                        profile:profile
                                customDirectory:&customDirectory];
    if (initialDirectory.mode == iTermInitialDirectoryModeCustom) {
        initialDirectory.customDirectoryFormat = customDirectory;
    }
    return initialDirectory;
}

- (void)evaluateWithOldPWD:(NSString *)oldPWD
                     scope:(iTermVariableScope *)scope
               synchronous:(BOOL)synchronous
                completion:(void (^)(NSString *))completion {
    if (_evaluated) {
        completion(_evaluated);
        return;
    }
    switch (self.mode) {
        case iTermInitialDirectoryModeCustom:
            break;
        case iTermInitialDirectoryModeHome:
            _evaluated = NSHomeDirectory();
            break;
        case iTermInitialDirectoryModeRecycle:
            _evaluated = oldPWD;
            break;
    }
    if (_evaluated) {
        completion(_evaluated);
        return;
    }

    iTermExpressionEvaluator *evaluator = [[iTermExpressionEvaluator alloc] initWithInterpolatedString:self.customDirectoryFormat
                                                                                                 scope:scope];
    [evaluator evaluateWithTimeout:synchronous ? 0 : 5 completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
        self->_evaluated = evaluator.value;
        completion(evaluator.value);
    }];
}

@end
