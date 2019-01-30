//
//  iTermScriptArchive.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import <Foundation/Foundation.h>

extern NSString *const iTermScriptSetupPyName;

// Helps install archived scripts.
@interface iTermScriptArchive : NSObject
@property (nonatomic, readonly) NSString *container;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) BOOL fullEnvironment;
@property (nonatomic, readonly) NSDictionary *metadata;

+ (instancetype)archiveFromContainer:(NSString *)container;
- (void)installTrusted:(BOOL)trusted withCompletion:(void (^)(NSError *, NSURL *location))completion;

@end
