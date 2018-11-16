//
//  NSNumber+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/15/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSNumber (iTerm)

- (id)it_jsonSafeValue;

@end

NS_ASSUME_NONNULL_END
