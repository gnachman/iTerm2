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

+ (instancetype)archiveFromContainer:(NSString *)container;
- (void)installWithCompletion:(void (^)(NSError *))completion;

@end
