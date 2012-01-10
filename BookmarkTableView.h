//
//  BookmarkTableView.h
//  iTerm
//
//  Created by George Nachman on 1/9/12.
//

#import <AppKit/AppKit.h>

@protocol BookmarkTableMenuHandler

- (NSMenu *)menuForEvent:(NSEvent *)theEvent;

@end

@interface BookmarkTableView : NSTableView
{
    NSObject<BookmarkTableMenuHandler> *handler_;
}

- (void)setMenuHandler:(NSObject<BookmarkTableMenuHandler> *)handler;

@end
