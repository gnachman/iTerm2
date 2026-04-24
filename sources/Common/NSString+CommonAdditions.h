//
//  NSString+CommonAdditions.h
//  iTerm2
//
//  Created by George Nachman on 2/24/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (CommonAdditions)

- (NSString *)stringByRemovingEnclosingBrackets;
- (NSString *)stringByDroppingLastCharacters:(NSInteger)count;

@end

NS_ASSUME_NONNULL_END
