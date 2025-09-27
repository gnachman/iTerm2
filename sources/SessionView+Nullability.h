//
//  SessionView+Nullability.h
//  iTerm2
//
//  Created by George Nachman on 9/26/25.
//

#import <AppKit/AppKit.h>
#import "SessionView.h"

NS_ASSUME_NONNULL_BEGIN

@interface SessionView()
@property (nullable, nonatomic, readonly) iTermBrowserViewController *browserViewController;
@end

NS_ASSUME_NONNULL_END
