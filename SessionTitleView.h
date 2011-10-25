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
- (void)beginDrag;

@end


@interface SessionTitleView : NSView {
    NSString *title_;
    NSTextField *label_;
    NSButton *closeButton_;
    NSPopUpButton *menuButton_;
    NSObject<SessionTitleViewDelegate> *delegate_;
    double dimmingAmount_;
}

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSObject<SessionTitleViewDelegate> *delegate;
@property (nonatomic, assign) double dimmingAmount;

@end
