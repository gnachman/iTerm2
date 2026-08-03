//
//  iTermScriptImporter.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Imports a script from a zip file.
@interface iTermScriptImporter : NSObject

// url is path to zip file
+ (void)importScriptFromURL:(NSURL *)url
              userInitiated:(BOOL)userInitiated
            offerAutoLaunch:(BOOL)offerAutoLaunch
              callbackQueue:(dispatch_queue_t)callbackQueue
                    avoidUI:(BOOL)avoidUI
                 completion:(void (^)(NSString * _Nullable errorMessage,
                                      BOOL quiet,
                                      NSURL * _Nullable location))completion;

// Recover backups left by an import interrupted between moving an existing script aside and
// restoring/cleaning it up: restore the original if it is missing, or delete a leaked
// backup if the replacement completed. Call once at launch.
+ (void)recoverStaleReplaceBackups;

@end

NS_ASSUME_NONNULL_END
