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
#import "iTermSearchFieldCell.h"
#import "NSColor+iTerm.h"
#import "NSTextField+iTerm.h"

@interface iTermMiniSearchFieldViewController ()

@end

@interface iTermMiniSearchField : NSSearchField
@end

@implementation iTermMiniSearchField

- (BOOL)becomeFirstResponder {
    [self.window.contentView setNeedsDisplay:YES];
    return [super becomeFirstResponder];
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

- (void)updateSubviews {
    NSSize size = self.view.frame.size;
    NSSize searchFieldSize = _searchField.frame.size;

    // This makes the arrows and close buttons line up visually.
    const CGFloat verticalOffset = 1;

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
    _searchField.frame = NSMakeRect(leftMargin, 0, self.view.frame.size.width - used, searchFieldSize.height);
}

#pragma mark - iTermFindViewController

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

#pragma mark - NSViewController

- (BOOL)validateUserInterfaceItem:(NSMenuItem *)item {
    item.state = (item.tag == self.driver.mode) ? NSOnState : NSOffState;
    return YES;
}

#pragma mark - NSControl

- (void)controlTextDidChange:(NSNotification *)aNotification {
    NSTextField *field = [aNotification object];
    if (field != _searchField) {
        return;
    }
    
    [self.driver userDidEditSearchQuery:_searchField.stringValue];
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
            const BOOL shiftPressed = !!([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagShift);
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
