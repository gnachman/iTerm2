//
//  AsyncHostLookupController.h
//  iTerm
//
//  Created by George Nachman on 12/14/13.
//
//

#import <Foundation/Foundation.h>

// Verify whether host names are valid. Runs in a separate thread and provides asynchronous results.
// Caches very aggressively.
@interface AsyncHostLookupController : NSObject

+ (instancetype)sharedInstance;

// Calls back to completion indicating whether |host| is an extant hostname. The BOOL is YES if the
// hostname resolves. |host| is passed as the second argument to completion. Does not block.
- (void)getAddressForHost:(NSString *)host
               completion:(void (^)(BOOL, NSString*))completion;

// Cancels the lookup for |hostname|.
- (void)cancelRequestForHostname:(NSString *)hostname;

@end
