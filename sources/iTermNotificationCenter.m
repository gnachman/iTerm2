//
//  iTermNotificationCenter.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/1/19.
//

#import "iTermNotificationCenter.h"

#import "DebugLogging.h"
#import "NSObject+iTerm.h"

static NSString *const iTermInternalNotification = @"iTermInternalNotification";
static const char iTermNotificationTokenAssociatedObject;

@interface iTermNotificationCenterObserverUnregisterer : NSObject
- (instancetype)initWithToken:(id)token NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

// This may outlive the object it is associated with, but that's ok because the block verifies the
// owner still exists before calling its block.
@implementation iTermNotificationCenterObserverUnregisterer {
    id _token;
}

- (instancetype)initWithToken:(id)token {
    self = [super init];
    if (self) {
        _token = token;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:_token];
}

@end

@interface iTermBaseNotification()
- (instancetype)initPrivate NS_DESIGNATED_INITIALIZER;
@end

@implementation iTermBaseNotification

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    return [self initPrivate];
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
}

- (instancetype)initPrivate {
    return [super init];
}

+ (id)decodedUserInfo:(NSDictionary *)userInfo {
    NSString *class = userInfo[@"class"];
    Class theClass = NSClassFromString(class);
    if (!theClass) {
        return nil;
    }
    NSData *data = userInfo[@"data"];
    @try {
        NSKeyedUnarchiver *decoder = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
        return [[theClass alloc] initWithCoder:decoder];
    } 
    @catch (NSException *exception) {
        NSLog(@"Failed to decode notification of class %@", class);
        DLog(@"Failed to decode notification of class %@", class);
    }
    return nil;
}

+ (NSDictionary *)encodedUserInfoWithData:(NSData *)data {
    return @{ @"class": NSStringFromClass(self),
              @"data": data };
}

+ (void)internalSubscribe:(NSObject *)owner withBlock:(void (^)(id notification))block {
    __weak NSObject *weakOwner = owner;
    // This prevents infinite recursion if you cause the notification to be sent while handling it.
    __block BOOL handling = NO;
    id token = [[NSNotificationCenter defaultCenter] addObserverForName:iTermInternalNotification
                                                                 object:[self class]
                                                                  queue:nil
                                                             usingBlock:^(NSNotification * _Nonnull notification) {
                                                                 id strongOwner = weakOwner;
                                                                 if (strongOwner) {
                                                                     if (handling) {
                                                                         return;
                                                                     }
                                                                     id decoded = [self decodedUserInfo:notification.userInfo];
                                                                     assert(decoded);

                                                                     handling = YES;
                                                                     block(decoded);
                                                                     handling = NO;
                                                                 }
                                                             }];
    [owner it_setAssociatedObject:[[iTermNotificationCenterObserverUnregisterer alloc] initWithToken:token]
                           forKey:(void *)&iTermNotificationTokenAssociatedObject];
}

- (void)post {
    if (![self conformsToProtocol:@protocol(NSCoding)]) {
        assert(NO);
    }

    id<NSCoding> codingObject = (id<NSCoding>)self;
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *coder = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    coder.outputFormat = NSPropertyListBinaryFormat_v1_0;
    [codingObject encodeWithCoder:coder];
    [coder finishEncoding];

    NSDictionary *dict = [self.class encodedUserInfoWithData:data];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermInternalNotification object:[self class] userInfo:dict];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

@interface iTermPreferenceDidChangeNotification()
@property (nonatomic, strong, readwrite) NSString *key;
@property (nonatomic, strong, readwrite) id value;
@end

@implementation iTermPreferenceDidChangeNotification

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initPrivate];
    if (self) {
        self.key = [aDecoder decodeObjectForKey:@"key"];
        self.value = [aDecoder decodeObjectForKey:@"value"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.key forKey:@"key"];
    [aCoder encodeObject:self.value forKey:@"value"];
}

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
