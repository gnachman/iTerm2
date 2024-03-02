//
//  iTermMiniSearchFieldViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/7/18.
//

#import "iTermMiniSearchFieldViewController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermFindDriver+Internal.h"
#import "iTermFocusReportingTextField.h"
#import "iTermSearchFieldCell.h"
#import "iTermStoplightHotbox.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PSMTabBarControl.h"

@interface iTermMiniSearchFieldViewController ()

@end

@implementation iTermMiniSearchField

- (BOOL)it_preferredFirstResponder {
    return YES;
}

- (BOOL)becomeFirstResponder {
    [self.window.contentView setNeedsDisplay:YES];
    return [super becomeFirstResponder];
}

#pragma mark -- iTermHotboxSuppressing

- (BOOL)supressesHotbox {
    return YES;
}

@end

@interface iTermMiniSearchFieldView : NSSearchField
@end

@implementation iTermMiniSearchFieldView

- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
}
@end

@implementation iTermMiniSearchFieldViewController {
    IBOutlet NSSearchField *_searchField;
    IBOutlet NSSegmentedControl *_arrowsControl;
    IBOutlet NSButton *_closeButton;
    NSTimer *_animationTimer;
}

@synthesize driver;

- (void)sizeToFitSize:(NSSize)size {
    NSSize searchFieldSize = [_searchField sizeThatFits:NSMakeSize(size.width, self.view.frame.size.height)];

    size.height = MAX(searchFieldSize.height, _arrowsControl.frame.size.height);
    NSRect rect = self.view.frame;
    rect.size = size;
    self.view.frame = rect;
    
    [self updateSubviews];
}

- (void)awakeFromNib {
    [self updateSubviews];
}

- (void)viewWillLayout {
    [super viewWillLayout];
    [self updateSubviews];
}

- (BOOL)shouldUseLargeControls {
    if (@available(macOS 11.0, *)) {
        return (iTermAdvancedSettingsModel.statusBarHeight >= 32);
    }
    return NO;
}

- (void)updateSubviews {
    NSSize size = self.view.frame.size;
    NSSize searchFieldSize = _searchField.frame.size;
    [_searchField sizeToFit];
    searchFieldSize.height = _searchField.frame.size.height;

    // Shift everything down by this amount.
    const CGFloat globalOffset = PSMShouldExtendTransparencyIntoMinimalTabBar() ? -0.5 : 0;

    // This makes the arrows and close buttons line up visually.
    CGFloat verticalOffset = 1 + globalOffset;

    if ([self shouldUseLargeControls]) {
        verticalOffset = (searchFieldSize.height - _arrowsControl.frame.size.height) / 2.0;
    }

    CGFloat closeWidth = 0;
    if (self.canClose) {
        _closeButton.hidden = NO;
        _closeButton.frame = NSMakeRect(size.width - _closeButton.frame.size.width,
                                        verticalOffset,
                                        _closeButton.frame.size.width,
                                        searchFieldSize.height);
        closeWidth = _closeButton.frame.size.width;
    } else {
        _closeButton.hidden = YES;
    }
    _arrowsControl.frame = NSMakeRect(size.width - _arrowsControl.frame.size.width - closeWidth,
                                      verticalOffset,
                                      _arrowsControl.frame.size.width,
                                      _arrowsControl.frame.size.height);
    const CGFloat margin = 3;
    const CGFloat leftMargin = 2;
    const CGFloat used = leftMargin + _arrowsControl.frame.size.width + closeWidth + margin;
    if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
        _searchField.frame = NSMakeRect(leftMargin, 1 + globalOffset, self.view.frame.size.width - used, searchFieldSize.height);
    } else {
        _searchField.frame = NSMakeRect(leftMargin, globalOffset, self.view.frame.size.width - used, searchFieldSize.height);
    }
}

- (void)setFont:(NSFont *)font {
    _searchField.font = font;
    if (@available(macOS 11.0, *)) {
        if ([self shouldUseLargeControls]) {
            _searchField.controlSize = NSControlSizeLarge;
            _arrowsControl.controlSize = NSControlSizeLarge;
            _closeButton.controlSize = NSControlSizeLarge;
        }
    }
    [self updateSubviews];
}

#pragma mark - iTermFindViewController

- (void)countDidChange {
    [_searchField setNeedsDisplay:YES];
}

- (BOOL)searchBarIsFirstResponder {
    return [_searchField textFieldIsFirstResponder];
}

- (void)close {
    if (self.canClose) {
        [self.driver setVisible:NO];
    } else {
        [self.driver ceaseToBeMandatory];
    }
}

- (void)open {
    [[[self view] window] makeFirstResponder:_searchField];
}

- (void)setProgress:(double)progress {
    iTermSearchFieldCell *cell = (iTermSearchFieldCell *)_searchField.cell;
    if (round(progress * 100) != round(cell.fraction * 100)) {
        [_searchField setNeedsDisplay:YES];
    }
    
    [cell setFraction:progress];
    if (cell.needsAnimation && !_animationTimer) {
        _animationTimer = [NSTimer scheduledTimerWithTimeInterval:1/60.0
                                                           target:self
                                                         selector:@selector(redrawSearchField:)
                                                         userInfo:nil
                                                          repeats:YES];
    }
}

- (void)deselectFindBarTextField {
    NSText *fieldEditor = [self.view.window fieldEditor:YES
                                              forObject:_searchField];
    [fieldEditor setSelectedRange:NSMakeRange(fieldEditor.string.length, 0)];
    [fieldEditor setNeedsDisplay:YES];
}

- (void)makeVisible {
    [self.view.window makeFirstResponder:_searchField];
    [_searchField selectText:nil];
}

- (void)setFilterHidden:(BOOL)filterHidden {
}

- (void)setFilterProgress:(double)progress {
}

- (void)setOffsetFromTopRightOfSuperview:(NSSize)offset {
}

- (void)toggleFilter {
}

- (BOOL)filterIsVisible {
    return NO;
}

- (BOOL)searchIsVisible {
    return YES;
}

- (BOOL)shouldSearchAutomatically {
    return [_searchField textFieldIsFirstResponder];
}

- (NSString *)filter {
    return nil;
}

- (void)setFilter:(NSString *)filter {
}

- (void)setFrameOrigin:(NSPoint)p {
}

- (void)redrawSearchField:(NSTimer *)timer {
    iTermSearchFieldCell *cell = _searchField.cell;
    [cell willAnimate];
    if (!cell.needsAnimation) {
        [_animationTimer invalidate];
        _animationTimer = nil;
    }
    [_searchField setNeedsDisplay:YES];
}

- (NSString *)findString {
    return _searchField.stringValue;
}

- (void)setFindString:(NSString *)string {
    [_searchField setStringValue:string];
}

- (void)setCanClose:(BOOL)canClose {
    _canClose = canClose;
    [self view];
}

#pragma mark - Actions

- (IBAction)searchNextPrev:(id)sender {
    if ([sender selectedSegment] == 0) {
        [self.driver searchPrevious];
    } else {
        [self.driver searchNext];
    }
    [sender setSelected:NO
             forSegment:[sender selectedSegment]];
}

- (IBAction)changeMode:(id)sender {
    self.driver.mode = (iTermFindMode)[sender tag];
}

- (IBAction)closeButton:(id)sender {
    [self.driver close];
}

- (IBAction)eraseSearchHistory:(id)sender {
    [self.driver eraseSearchHistory];
}

#pragma mark - NSViewController

- (BOOL)validateUserInterfaceItem:(NSMenuItem *)item {
    item.state = (item.tag == self.driver.mode) ? NSControlStateValueOn : NSControlStateValueOff;
    return YES;
}

#pragma mark - iTermFocusReportingSearchField

- (void)focusReportingSearchFieldWillBecomeFirstResponder:(iTermFocusReportingSearchField *)sender {
    [self.driver searchFieldWillBecomeFirstResponder:sender];
}

- (NSInteger)focusReportingSearchFieldNumberOfResults:(iTermFocusReportingSearchField *)sender {
    return [self.driver numberOfResults];
}

- (NSInteger)focusReportingSearchFieldCurrentIndex:(iTermFocusReportingSearchField *)sender {
    return [self.driver currentIndex];
}

#pragma mark - NSControl

- (void)controlTextDidChange:(NSNotification *)aNotification {
    NSTextField *field = [aNotification object];
    if (field != _searchField) {
        return;
    }

    [self.driver userDidEditSearchQuery:_searchField.stringValue
                            fieldEditor:aNotification.userInfo[@"NSFieldEditor"]];
}

- (NSArray *)control:(NSControl *)control
            textView:(NSTextView *)textView
         completions:(NSArray *)words  // Dictionary words
 forPartialWordRange:(NSRange)charRange
 indexOfSelectedItem:(NSInteger *)index {
    *index = -1;
    return [self.driver completionsForText:[textView string]
                                     range:charRange];
}

- (BOOL)becomeFirstResponder {
    [self.driver searchFieldWillBecomeFirstResponder:_searchField];
    return [super becomeFirstResponder];
}

- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)commandSelector {
    if (control != _searchField) {
        return NO;
    }

    if (commandSelector == @selector(cancelOperation:)) {
        // Have the esc key close the find bar instead of erasing its contents.
        [self.driver close];
        return YES;
    } else if (commandSelector == @selector(insertBacktab:)) {
        [self.driver backTab];
        return YES;
    } else if (commandSelector == @selector(insertTab:)) {
        [self.driver forwardTab];
        return YES;
    } else if (commandSelector == @selector(insertNewlineIgnoringFieldEditor:)) {
        // Alt-enter
        [self.driver copyPasteSelection];
        return YES;
    } else {
        [self.driver doCommandBySelector:commandSelector];
        return NO;
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification {
    NSControl *postingObject = [aNotification object];
    if (postingObject != _searchField) {
        return;
    }

    int move = [[[aNotification userInfo] objectForKey:@"NSTextMovement"] intValue];
    switch (move) {
        case NSOtherTextMovement:
            // Focus lost
            [self.driver didLoseFocus];
            break;
        case NSReturnTextMovement: {
            // Return key
            const BOOL shiftPressed = !!([[NSApp currentEvent] it_modifierFlags] & NSEventModifierFlagShift);
            const BOOL swap = [iTermAdvancedSettingsModel swapFindNextPrevious];
            if  (!shiftPressed ^ swap) {
                [self.driver searchNext];
            } else {
                [self.driver searchPrevious];
            }
            break;
        }
    }
    return;
}

- (void)encodeWithCoder:(nonnull NSCoder *)aCoder {
}

@end
