//
//  NSHost+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSHost(iTerm)

// For localhost. It's too hard to do this as an instance method, and I don't need to get fancy.
+ (NSString *)fullyQualifiedDomainName;

@end

NS_ASSUME_NONNULL_END
