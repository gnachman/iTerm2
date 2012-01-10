//
//  BookmarkTableView.m
//  iTerm
//
//  Created by George Nachman on 1/9/12.
//

#import "BookmarkTableView.h"

@implementation BookmarkTableView

- (void)setMenuHandler:(NSObject<BookmarkTableMenuHandler> *)handler
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
