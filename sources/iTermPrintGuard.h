//
//  iTermPrintGuard.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/22/19.
//

#import <Cocoa/Cocoa.h>
#import "ProfileModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermPrintGuard : NSObject

- (BOOL)shouldPrintWithProfile:(Profile *)profile
                      inWindow:(NSWindow *)window;

@end

NS_ASSUME_NONNULL_END
