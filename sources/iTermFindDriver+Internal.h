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
// Returns NO if the value was rejected because it was too long.
- (BOOL)loadFindStringIntoSharedPasteboard:(NSString *)stringValue
                            userOriginated:(BOOL)userOriginated;
- (void)userDidEditSearchQuery:(NSString *)updatedQuery
                   fieldEditor:(NSTextView *)fieldEditor;
- (void)userDidEditFilter:(NSString *)updatedFilter
              fieldEditor:(NSTextView *)fieldEditor;
- (void)backTab;
- (void)forwardTab;
- (void)copyPasteSelection;
- (void)didLoseFocus;
- (NSArray<NSString *> *)completionsForText:(NSString *)text
                                      range:(NSRange)range;
- (void)doCommandBySelector:(SEL)selector;
- (void)searchFieldWillBecomeFirstResponder:(NSSearchField *)searchField;
- (void)eraseSearchHistory;
- (NSInteger)numberOfResults;
- (NSInteger)currentIndex;
- (void)setFilter:(NSString *)filter;

@end
