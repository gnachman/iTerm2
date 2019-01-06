//
//  iTermSessionPicker.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PTYSession;

@interface iTermSessionPicker : NSObject

- (PTYSession *)pickSession;

@end

NS_ASSUME_NONNULL_END
