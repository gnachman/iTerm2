#import "SessionView+iTermLib.h"

NSString* const iTermLibSessionViewDidMoveToWindowNotification = @"iTermLibSessionViewDidMoveToWindowNotification";

@implementation SessionView (iTermLib)

- (void)viewDidMoveToWindow
{
    [NSNotificationCenter.defaultCenter postNotificationName:iTermLibSessionViewDidMoveToWindowNotification object:self];
}

@end
