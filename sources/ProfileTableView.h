//
//  ProfileTableView.h
//  iTerm
//
//  Created by George Nachman on 1/9/12.
//

#import <AppKit/AppKit.h>

@protocol ProfileTableMenuHandler <NSObject>

- (NSMenu *)menuForEvent:(NSEvent *)theEvent;

@end

@interface ProfileTableView : NSTableView

- (void)setMenuHandler:(id<ProfileTableMenuHandler>)handler;

@end
