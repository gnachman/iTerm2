//
//  ToastWindowController.h
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//
//

#import <Cocoa/Cocoa.h>

@interface ToastWindowController : NSWindowController {
    BOOL hiding_;
    NSTimer *hideTimer_;
}

+ (void)showToastWithMessage:(NSString *)message;
+ (void)showToastWithMessage:(NSString *)message duration:(NSInteger)duration;

@end
