//
//  NSTableView+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/14/19.
//

#import <AppKit/AppKit.h>


#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermDynamicProfileSymbolName;

@interface iTermTableCellViewWithTextField: NSTableCellView
@end

@interface NSTableView (iTerm)

- (void)it_performUpdateBlock:(void (^NS_NOESCAPE)(void))block;

+ (instancetype)toolbeltTableViewInScrollview:(NSScrollView *)scrollView
                               fixedRowHeight:(CGFloat)fixedRowHeight
                                        owner:(NSView<NSTableViewDelegate, NSTableViewDataSource> *)owner;

- (iTermTableCellViewWithTextField *)newTableCellViewWithTextFieldUsingIdentifier:(NSString *)identifier
                                                                             font:(NSFont *)font
                                                                           string:(NSString *)string;
- (iTermTableCellViewWithTextField *)newTableCellViewWithTextFieldUsingIdentifier:(NSString *)identifier
                                                                 attributedString:(NSAttributedString *)attributedString;

// value is either NSString or NSAttributedString
- (iTermTableCellViewWithTextField *)newTableCellViewWithTextFieldUsingIdentifier:(NSString *)identifier
                                                                             font:(NSFont * _Nullable)font
                                                                            value:(id)value;
+ (CGFloat)heightForTextCellUsingFont:(NSFont *)font;

@end

@interface NSOutlineView(iTerm)
+ (instancetype)toolbeltOutlineViewInScrollview:(NSScrollView *)scrollView
                                 fixedRowHeight:(CGFloat)fixedRowHeight
                                          owner:(NSView<NSOutlineViewDelegate, NSOutlineViewDataSource> *)owner;
@end

@interface NSTextField(iTermDynamicSymbol)

// Re-renders SF Symbol text attachments tagged with iTermDynamicProfileSymbolName in the
// receiver's attributed value so they tint correctly for the current selection state and
// effective appearance. Call from a table cell view's setBackgroundStyle: and
// viewDidChangeEffectiveAppearance. alpha sets the symbol opacity (e.g. 0.75 for a
// secondary look, 1 for full strength). If symbolSize is not NSZeroSize each attachment is
// forced to that size; otherwise it keeps the size it was created with.
- (void)it_retintDynamicSymbolAttachmentsForEmphasized:(BOOL)emphasized
                                                 alpha:(CGFloat)alpha
                                            symbolSize:(NSSize)symbolSize;
@end

NS_ASSUME_NONNULL_END
