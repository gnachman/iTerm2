//
//  PseudoTerminal+TouchBar.h
//  iTerm2
//
//  Created by George Nachman on 2/20/17.
//
//

#import "PseudoTerminal.h"

@interface PseudoTerminal (TouchBar) <
    NSCandidateListTouchBarItemDelegate,
    NSTouchBarDelegate,
    NSScrubberDelegate,
    NSScrubberDataSource>

- (void)updateTouchBarIfNeeded:(BOOL)force;
- (void)updateTouchBarFunctionKeyLabels;
- (void)updateTouchBarWithWordAtCursor:(NSString *)word;
- (void)updateColorPresets;

@end
