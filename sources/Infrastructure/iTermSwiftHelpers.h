//
//  iTermSwiftHelpers.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Returns a unique, monotonically increasing generation number.
// This is thread-safe and can be used for delta encoding purposes.
NSInteger iTermAllocateObjectGeneration(void);

@interface ObjC: NSObject

+ (BOOL)catching:(void (^ NS_NOESCAPE)(void))block
           error:(NSError * _Nullable __autoreleasing * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
