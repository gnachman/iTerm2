//
//  iTermScriptExporter.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import <Foundation/Foundation.h>

@class SIGIdentity;

@interface iTermScriptExporter : NSObject

+ (void)exportScriptAtURL:(NSURL *)url
          signingIdentity:(SIGIdentity *)sigIdentity
               completion:(void (^)(NSString *errorMessage, NSURL *zipURL))completion;
+ (BOOL)urlIsScript:(NSURL *)url;

@end
