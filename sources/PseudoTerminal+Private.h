//
//  PseudoTerminal+Private.h
//  iTerm2
//
//  Created by George Nachman on 2/20/17.
//
//

#import "PseudoTerminal.h"

@class iTermRootTerminalView;

@interface PseudoTerminal()

ITERM_IGNORE_PARTIAL_BEGIN
@property (nonatomic, retain) NSCustomTouchBarItem *tabsTouchBarItem;
@property (nonatomic, retain) NSCandidateListTouchBarItem<NSString *> *autocompleteCandidateListItem;
ITERM_IGNORE_PARTIAL_END
@property(nonatomic, readonly) BOOL wellFormed;

// This is a reference to the window's content view, here for convenience because it has
// the right type.
@property (nonatomic, readonly) __unsafe_unretained iTermRootTerminalView *contentView;

@end


