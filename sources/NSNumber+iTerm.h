//
//  NSNumber+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/15/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSNumber (iTerm)

- (nullable id)it_jsonSafeValue;
+ (instancetype _Nullable)coerceFrom:(id _Nullable)obj;

@end

NS_ASSUME_NONNULL_END
