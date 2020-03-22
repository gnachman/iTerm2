//
//  iTermPreferenceDidChangeNotification.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermPreferenceDidChangeNotification.h"

#import "iTermNotificationCenter+Protected.h"

@interface iTermPreferenceDidChangeNotification()
@property (nonatomic, strong, readwrite) NSString *key;
@property (nonatomic, strong, readwrite) id value;
@end

@implementation iTermPreferenceDidChangeNotification

+ (instancetype)notificationWithKey:(NSString *)key value:(id)value {
    iTermPreferenceDidChangeNotification *notif = [[self alloc] initPrivate];
    notif.key = key;
    notif.value = value;
    return notif;
}

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermPreferenceDidChangeNotification * _Nonnull))block {
    [self internalSubscribe:owner withBlock:block];
}

@end
