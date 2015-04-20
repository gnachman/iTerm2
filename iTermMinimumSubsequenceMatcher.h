//
//  iTermMinimumSubsequenceMatcher.h
//  iTerm2
//
//  Created by George Nachman on 4/19/15.
//
//

#import <Foundation/Foundation.h>

@interface iTermMinimumSubsequenceMatcher : NSObject

- (instancetype)initWithQuery:(NSString *)query;
- (NSIndexSet *)indexSetForDocument:(NSString *)document;

@end
