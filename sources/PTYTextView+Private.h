//
//  PTYTextView+Private.h
//  iTerm2
//
//  Created by George Nachman on 4/15/19.
//

#import "PTYTextView.h"

#import "iTermAltScreenMouseScrollInferrer.h"
#import "iTermSelection.h"
#import "iTermSemanticHistoryController.h"
#import "iTermFindCursorView.h"
#import "iTermQuickLookController.h"
#import "iTermBadgeLabel.h"
#import "iTermTextViewAccessibilityHelper.h"
#import "iTermFindCursorView.h"
#import "iTermFindOnPageHelper.h"
#import "iTermKeyboardHandler.h"
#import "iTermSelection.h"
#import "iTermSelectionScrollHelper.h"

@class iTermURLActionHelper;

@interface PTYTextView () <
iTermAltScreenMouseScrollInferrerDelegate,
iTermBadgeLabelDelegate,
iTermTextViewAccessibilityHelperDelegate,
iTermFindCursorViewDelegate,
iTermFindOnPageHelperDelegate,
iTermKeyboardHandlerDelegate,
iTermSelectionDelegate,
iTermSelectionScrollHelperDelegate,
NSDraggingSource,
NSMenuDelegate,
NSPopoverDelegate> {
    NSCursor *cursor_;

    // Flag to make sure a Semantic History drag check is only one once per drag
    BOOL _semanticHistoryDragged;
    BOOL _committedToDrag;

    iTermURLActionHelper *_urlActionHelper;
}

@property(nonatomic, strong) iTermSelection *selection;
@property(nonatomic, strong) iTermSemanticHistoryController *semanticHistoryController;
@property(nonatomic, strong) iTermFindCursorView *findCursorView;
@property(nonatomic, strong) NSWindow *findCursorWindow;  // For find-cursor animation
@property(nonatomic, strong) iTermQuickLookController *quickLookController;
@property(strong, readwrite) NSTouchBar *touchBar NS_AVAILABLE_MAC(10_12_2);

// Set when a context menu opens, nilled when it closes. If the data source changes between when we
// ask the context menu to open and when the main thread enters a tracking runloop, the text under
// the selection can change. We want to respect what we show while the context menu is open.
// See issue 4048.
@property(nonatomic, copy) NSString *savedSelectedText;

@end

