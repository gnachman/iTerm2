//
//  PointerController.h
//  iTerm
//
//  Created by George Nachman on 11/7/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol PointerControllerDelegate

- (void)pasteFromClipboardWithEvent:(NSEvent *)event;
- (void)pasteFromSelectionWithEvent:(NSEvent *)event;
- (void)openTargetWithEvent:(NSEvent *)event;
- (void)openTargetInBackgroundWithEvent:(NSEvent *)event;
- (void)smartSelectWithEvent:(NSEvent *)event;
- (void)openContextMenuWithEvent:(NSEvent *)event;
- (void)nextTabWithEvent:(NSEvent *)event;
- (void)previousTabWithEvent:(NSEvent *)event;
- (void)nextWindowWithEvent:(NSEvent *)event;
- (void)previousWindowWithEvent:(NSEvent *)event;
- (void)movePaneWithEvent:(NSEvent *)event;

@end

@interface PointerController : NSObject {
    NSObject<PointerControllerDelegate> *delegate_;
    int mouseDownButton_;
}

@property (nonatomic, assign) NSObject<PointerControllerDelegate> *delegate;

- (void)mouseDown:(NSEvent *)event withTouches:(int)numTouches;
- (void)mouseUp:(NSEvent *)event withTouches:(int)numTouches;
- (void)swipeWithEvent:(NSEvent *)event;

@end
