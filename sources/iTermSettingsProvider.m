//
//  iTermSettingsProvider.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/20/20.
//

#import "iTermSettingsProvider.h"
#import "ProfileModel.h"
@implementation iTermSettingsProviderProfile

- (instancetype)initWithGUID:(NSString *)guid
                profileModel:(ProfileModel *)profileModel {
    self = [super init];
    if (self) {
        _guid = [guid copy];
        _profileModel = profileModel;
    }
    return self;
}
- (id)objectForKey:(NSString *)key {
    return [[_profileModel bookmarkWithGuid:_guid]  objectForKey:key];
}

- (void)setObject:(id)object forKey:(NSString *)key {
    MutableProfile *profile = [[_profileModel bookmarkWithGuid:_guid] mutableCopy];
    profile[key] = object;
    [_profileModel setBookmark:profile withGuid:_guid];
}

@end


@implementation iTermSettingsProviderGlobal

+ (instancetype)sharedInstance {
    static iTermSettingsProviderGlobal *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[iTermSettingsProviderGlobal alloc] init];
    });
    return instance;
}

- (id)objectForKey:(NSString *)key {
    return [[NSUserDefaults standardUserDefaults] objectForKey:key];
}
- (void)setObject:(id)object forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setObject:object forKey:key];
}

@end
