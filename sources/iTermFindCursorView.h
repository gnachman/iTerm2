//
//  FindCursorView.h
//  iTerm
//
//  Created by George Nachman on 12/26/13.
//
//

#import <Cocoa/Cocoa.h>

extern const double kFindCursorHoldTime;

@protocol iTermFindCursorViewDelegate <NSObject>

- (void)findCursorViewDismiss;

@end

// This is the superclass for a class cluster.
@interface iTermFindCursorView : NSView

@property(nonatomic, assign) id<iTermFindCursorViewDelegate> delegate;
@property(nonatomic, assign) NSPoint cursorPosition;
@property(nonatomic, assign) BOOL autohide;
@property(nonatomic, assign) BOOL stopping;

+ (instancetype)newFireworksViewWithFrame:(NSRect)frameRect;

- (void)startTearDownTimer;
- (void)stopTearDownTimer;

@end
