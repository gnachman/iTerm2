//
//  PTYSession+ARC.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import "PTYSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface PTYSession (ARC)

- (void)fetchAutoLogFilenameSynchronously:(BOOL)synchronous
                               completion:(void (^)(NSString *filename))completion;

@end

NS_ASSUME_NONNULL_END
