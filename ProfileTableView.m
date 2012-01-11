//
//  ProfileTableView.m
//  iTerm
//
//  Created by George Nachman on 1/9/12.
//

#import "ProfileTableView.h"

@implementation ProfileTableView

- (void)setMenuHandler:(NSObject<ProfileTableMenuHandler> *)handler
{
    handler_ = handler;
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    if ([handler_ respondsToSelector:@selector(menuForEvent:)]) {
        return [handler_ menuForEvent:theEvent];
    }
    return nil;
}

@end
