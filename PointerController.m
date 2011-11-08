//
//  PointerController.m
//  iTerm
//
//  Created by George Nachman on 11/7/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "PointerController.h"

NSString *kPasteFromClipboardPointerAction = @"kPasteFromClipboardPointerAction";
NSString *kPasteFromSelectionPointerAction = @"kPasteFromSelectionPointerAction";
NSString *kOpenTargetPointerAction = @"kOpenTargetPointerAction";
NSString *kSmartSelectionPointerAction = @"kSmartSelectionPointerAction";
NSString *kContextMenuPointerAction = @"kContextMenuPointerAction";
NSString *kSelectWordPointerAction = @"kSelectWordPointerAction";
NSString *kSelectLinePointerAction = @"kSelectLinePointerAction";
NSString *kBlockSelectPointerAction = @"kBlockSelectPointerAction";
NSString *kExtendSelectionPointerAction = @"kExtendSelectionPointerAction";
NSString *kExtendSelectionByWordPointerAction = @"kExtendSelectionByWordPointerAction";
NSString *kExtendSelectionByLinePointerAction = @"kExtendSelectionByLinePointerAction";
NSString *kExtendSelectionBySmartSelectionPointerAction = @"kExtendSelectionBySmartSelectionPointerAction";
NSString *kNextTabPointerAction = @"kNextTabPointerAction";
NSString *kPrevTabPointerAction = @"kPrevTabPointerAction";
NSString *kDragPanePointerAction = @"kDragPanePointerAction";
NSString *kNoActionPointerAction = @"kNoActionPointerAction";

@implementation PointerController

@synthesize delegate = delegate_;

- (BOOL)mouseDown:(NSEvent *)event
{
    // TODO
    return NO;
}

- (void)mouseUp:(NSEvent *)event
{
  // TODO
}

- (void)mouseDrag:(NSEvent *)event
{
  // TODO
}

- (void)mouseMove:(NSEvent *)event
{
  // TODO
}


@end
