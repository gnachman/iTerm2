//
//  iTermScriptArchive.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import <Foundation/Foundation.h>

extern NSString *const iTermScriptSetupCfgName;

// Helps install archived scripts.
@interface iTermScriptArchive : NSObject
@property (nonatomic, readonly) NSString *container;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) BOOL fullEnvironment;
@property (nonatomic, readonly) NSDictionary *metadata;

+ (instancetype)archiveFromContainer:(NSString *)container
                          deprecated:(out BOOL *)deprecatedPtr;

// Trusted scripts may specify that they prefer to be in autolaunch and user will be prompted.
// If offerAutoLaunch is set, then even non-trusted scripts will prompt to move to autolaunch.
- (void)installTrusted:(BOOL)trusted
       offerAutoLaunch:(BOOL)offerAutoLaunch
               avoidUI:(BOOL)avoidUI
        withCompletion:(void (^)(NSError *, NSURL *location))completion;

@end
