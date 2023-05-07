//
//  iTermScriptExporter.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SIGIdentity;

@interface iTermScriptExporter : NSObject

+ (void)exportScriptAtURL:(NSURL *)url
          signingIdentity:(SIGIdentity * _Nullable)sigIdentity
            callbackQueue:(dispatch_queue_t)callbackQueue
              destination:(NSURL * _Nullable)destination
               completion:(void (^)(NSString * _Nullable errorMessage, NSURL * _Nullable zipURL))completion;
+ (BOOL)urlIsScript:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
