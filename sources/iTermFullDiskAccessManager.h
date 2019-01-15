//
//  iTermFullDiskAccessManager.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/20/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermFullDiskAccessManager : NSObject

+ (BOOL)willRequestFullDiskAccess;
+ (void)maybeRequestFullDiskAccess NS_AVAILABLE_MAC(10_14);

@end

NS_ASSUME_NONNULL_END
