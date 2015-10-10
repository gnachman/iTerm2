//
//  AsyncHostLookupController.m
//  iTerm
//
//  Created by George Nachman on 12/14/13.
//
//

#import "AsyncHostLookupController.h"
#import "DebugLogging.h"
#include <netdb.h>

@implementation AsyncHostLookupController {
    // Created at initialization and used to perform blocking gethostbyname calls.
    dispatch_queue_t _queue;

    // Set of hostnames waiting to be looked up. If a hostname is removed from
    // this set then it won't be looked up when its turn comes around.
    NSMutableSet *_pending;

    // Maps hostname -> @YES or @NO, indicating if it resolved.
    NSMutableDictionary *_cache;
}

+ (instancetype)sharedInstance {
    static AsyncHostLookupController *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("AsyncHostLookupControllerQueue", NULL);
        _pending = [[NSMutableSet alloc] init];
        _cache = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    // The logic for cleaning up the dispatch queue isn't written, so just make sure the singleton
    // never gets dealloced.
    assert(false);
    [super dealloc];
}

- (void)getAddressForHost:(NSString *)hostname
               completion:(void (^)(BOOL, NSString *))completion {
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    @synchronized(self) {
        if ([_pending containsObject:hostname]) {
            DLog(@"Already pending %@", hostname);
            return;
        }
        NSNumber *okNumber = _cache[hostname];
        if (okNumber) {
            completion([okNumber boolValue], hostname);
            return;
        }
        [_pending addObject:hostname];
    }
    dispatch_async(_queue, ^() {
        @synchronized(self) {
            if (![_pending containsObject:hostname]) {
                DLog(@"Abort nslookup for %@", hostname);
                return;
            }
        }
        
        struct hostent *hbuf;
        // On Mac OS this is thread-safe (it uses TLS for the hostent), and gethostbyname_r is not
        // defined.
        hbuf = gethostbyname([hostname UTF8String]);
        BOOL ok = (hbuf != NULL);
        @synchronized(self) {
            _cache[hostname] = @(ok);
        }
        dispatch_async(dispatch_get_main_queue(), ^() {
            @synchronized(self) {
                if (![_pending containsObject:hostname]) {
                    DLog(@"Finished nslookup but don't call block for %@", hostname);
                    return;
                }
                [_pending removeObject:hostname];
            }
            DLog(@"Host %@: %@", hostname, ok ? @"OK" : @"Unknown");
            completion(ok, hostname);
        });
    });
    DLog(@"Blocked main thread for %f sec", [NSDate timeIntervalSinceReferenceDate] - start);
}

- (void)cancelRequestForHostname:(NSString *)hostname {
    @synchronized(self) {
        [_pending removeObject:hostname];
    }
}

@end
