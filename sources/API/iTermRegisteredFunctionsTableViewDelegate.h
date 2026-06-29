//
//  iTermRegisteredFunctionsTableViewDelegate.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermRegisteredFunctionsTableViewDelegate : NSObject<NSTableViewDataSource, NSTableViewDelegate>

- (void)reload;

@end

NS_ASSUME_NONNULL_END
