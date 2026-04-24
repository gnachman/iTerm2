//
//  iTermNotificationCenter+Protected.h
//  iTerm2
//
//  Created by George Nachman on 09/03/19.
//

#import "iTermNotificationCenter.h"

@interface iTermBaseNotification()
- (instancetype)initPrivate NS_DESIGNATED_INITIALIZER;
+ (void)internalSubscribe:(NSObject *)owner withBlock:(void (^)(id notification))block;
@end
