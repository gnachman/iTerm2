//
//  PointerController.h
//  iTerm
//
//  Created by George Nachman on 11/7/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

extern NSString *kPasteFromClipboardPointerAction;
extern NSString *kPasteFromSelectionPointerAction;
extern NSString *kOpenTargetPointerAction;
extern NSString *kSmartSelectionPointerAction;
extern NSString *kContextMenuPointerAction;
extern NSString *kSelectWordPointerAction;
extern NSString *kSelectLinePointerAction;
extern NSString *kBlockSelectPointerAction;
extern NSString *kExtendSelectionPointerAction;
extern NSString *kExtendSelectionByWordPointerAction;
extern NSString *kExtendSelectionByLinePointerAction;
extern NSString *kExtendSelectionBySmartSelectionPointerAction;
extern NSString *kNextTabPointerAction;
extern NSString *kPrevTabPointerAction;
extern NSString *kDragPanePointerAction;
extern NSString *kNoActionPointerAction;

@protocol PointerControllerDelegate

- (NSPoint)charCoordOfEventLocation:(NSPoint)eventLocation;

@end

@interface PointerController : NSObject {
    NSObject<PointerControllerDelegate> *delegate_;
}

@property (nonatomic, assign) NSObject<PointerControllerDelegate> *delegate;

// Returns true if [super mouseDown] should be run by caller.
- (BOOL)mouseDown:(NSEvent *)event;
- (void)mouseUp:(NSEvent *)event;
- (void)mouseDrag:(NSEvent *)event;
- (void)mouseMove:(NSEvent *)event;

@end
