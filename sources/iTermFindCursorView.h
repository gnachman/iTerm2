//
//  FindCursorView.h
//  iTerm
//
//  Created by George Nachman on 12/26/13.
//
//

#import <Cocoa/Cocoa.h>

@protocol iTermFindCursorViewDelegate <NSObject>

- (void)findCursorViewDismiss;
- (void)findCursorBlink;

@end

@interface iTermFindCursorView : NSView {
    NSPoint cursor;
}

@property(nonatomic, assign) id<iTermFindCursorViewDelegate> delegate;
@property(nonatomic, assign) NSPoint cursor;
@property(nonatomic, assign) BOOL autohide;
@property(nonatomic, assign) BOOL stopping;

- (void)startTearDownTimer;
- (void)stopTearDownTimer;
- (void)startBlinkNotifications;
- (void)stopBlinkNotifications;

@end
