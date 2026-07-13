//
//  iTermInProcessAPIConnection.m
//  iTerm2
//

#import "iTermInProcessAPIConnection.h"

@implementation iTermInProcessAPIConnection {
    id _key;
    NSString *_guid;
    void (^_responseHandler)(NSData *);
}

- (instancetype)initWithKey:(id)key
            responseHandler:(void (^)(NSData *responseData))responseHandler {
    self = [super init];
    if (self) {
        _key = key;
        _guid = [[NSUUID UUID] UUIDString];
        _responseHandler = [responseHandler copy];
    }
    return self;
}

- (id)key {
    return _key;
}

- (NSString *)guid {
    return _guid;
}

- (void)sendBinary:(NSData *)binaryData completion:(void (^)(void))completion {
    if (_responseHandler) {
        _responseHandler(binaryData);
    }
    if (completion) {
        completion();
    }
}

- (void)abortWithCompletion:(void (^)(void))completion {
    if (_onAbort) {
        _onAbort();
    }
    if (completion) {
        completion();
    }
}

@end
