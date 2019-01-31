//
//  iTermFindDriver+Internal.h
//  iTerm2
//
//  Created by George Nachman on 7/4/18.
//

#import "iTermFindDriver.h"

@interface iTermFindDriver(Internal)

- (void)setVisible:(BOOL)visible;
- (void)ceaseToBeMandatory;
- (void)loadFindStringIntoSharedPasteboard:(NSString *)stringValue;
- (void)userDidEditSearchQuery:(NSString *)updatedQuery;
- (void)backTab;
- (void)forwardTab;
- (void)copyPasteSelection;
- (void)didLoseFocus;

@end
