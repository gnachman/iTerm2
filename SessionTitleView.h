//
//  SessionTitleView.h
//  iTerm
//
//  Created by George Nachman on 10/21/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol SessionTitleViewDelegate

- (NSMenu *)menu;
- (void)close;

@end


@interface SessionTitleView : NSView {
    NSString *title_;
    NSTextField *label_;
    NSButton *closeButton_;
    NSPopUpButton *menuButton_;
    NSObject<SessionTitleViewDelegate> *delegate_;
}

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSObject<SessionTitleViewDelegate> *delegate;
@end
