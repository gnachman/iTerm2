/*
 **  iTermDropDownFindViewController.m
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: View controller for find view. Controls the UI layer of
 **    searching a session.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "iTermDropDownFindViewController.h"

#import "DebugLogging.h"
#import "iTerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermFindDriver.h"
#import "iTermFindDriver+Internal.h"
#import "iTermFocusReportingTextField.h"
#import "iTermPreferences.h"
#import "iTermProgressIndicator.h"
#import "iTermSearchFieldCell.h"
#import "iTermSystemVersion.h"
#import "NSEvent+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTextField+iTerm.h"

// This used to be absurdly fast (.075) for reasons neither I nor revision
// history can recall. This looks nicer to my eyes.
static const float kAnimationDuration = 0.2;
static const CGFloat kFilterHeight = 30;

@interface iTermDropDownFindViewController()<iTermFocusReportingSearchFieldDelegate>
@end

@implementation iTermDropDownFindViewController {
    IBOutlet iTermFocusReportingSearchField *findBarTextField_;
    IBOutlet NSSearchField *_filterField;
    IBOutlet NSView *_filterWrapper;

    // Fades out the progress indicator.
    NSTimer *_animationTimer;
    NSTimer *_filterAnimationTimer;

    NSRect fullFrame_;
    CGFloat _baseHeight;
    NSSize _offset;
}

@synthesize driver;

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [findBarTextField_ setDelegate:self];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([iTermAdvancedSettingsModel useOldStyleDropDownViews]) {
        return;
    }

    NSShadow *shadow = [[[NSShadow alloc] init] autorelease];
    shadow.shadowOffset = NSMakeSize(2, -2);
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.3];
    shadow.shadowBlurRadius = 2;

    self.view.wantsLayer = YES;
    [self.view makeBackingLayer];
    self.view.shadow = shadow;
    [self setFilterHidden:YES];
}

#pragma mark - iTermFindViewController

- (BOOL)filterIsVisible {
    [self view];
    return !_filterWrapper.isHidden;
}

- (void)setFilterHidden:(BOOL)filterHidden {
    if (_filterWrapper.isHidden != filterHidden) {
        _filterWrapper.hidden = filterHidden;
        [self.driver invalidateFrame];
        [self.driver filterVisibilityDidChange];
    }
    if (filterHidden) {
        [self setFilterProgress:0];
    } else {
        [_filterField.window makeFirstResponder:_filterField];
    }
}

- (NSSize)desiredSize {
    return NSMakeSize(NSWidth(self.view.bounds), _baseHeight - (self.filterIsVisible ? 0 : kFilterHeight));
}
- (void)toggleFilter {
    [self setFilterHidden:!_filterWrapper.isHidden];
}

- (void)countDidChange {
    [findBarTextField_ setNeedsDisplay:YES];
}

- (BOOL)searchBarIsFirstResponder {
    return [findBarTextField_ textFieldIsFirstResponder];
}

- (void)close {
    DLog(@"Closing find view %@", self.view);
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [[self view] setHidden:YES];
        [[[[self view] window] contentView] setNeedsDisplay:YES];
        [self.driver setVisible:NO];
    }];
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    self.view.animator.alphaValue = 0;
    [NSAnimationContext endGrouping];
}

- (void)open {
    [[self view] setFrame:[self collapsedFrame]];
    [[self view] setHidden:NO];
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    DLog(@"Animate find view %@ to full size frame: %@",
         self.view, NSStringFromRect([self fullSizeFrame]));
    
    [NSAnimationContext beginGrouping];
    
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [[[[self view] window] contentView] setNeedsDisplay:YES];
    }];

    self.view.frame = self.fullSizeFrame;
    self.view.animator.alphaValue = 1.0;

    [NSAnimationContext endGrouping];
    
    DLog(@"Grab focus for find view %@", self.view);
    [[[self view] window] makeFirstResponder:findBarTextField_];
}

- (void)setProgress:(double)progress {
    iTermSearchFieldCell *cell = (iTermSearchFieldCell *)findBarTextField_.cell;
    if (round(progress * 100) != round(cell.fraction * 100)) {
        [findBarTextField_ setNeedsDisplay:YES];
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

- (NSString *)findString {
    return findBarTextField_.stringValue;
}

- (void)setFindString:(NSString *)string {
    [findBarTextField_ setStringValue:string];
}

- (NSString *)filter {
    return _filterField.stringValue;
}

- (BOOL)searchIsVisible {
    return self.viewLoaded && !self.view.isHidden;
}

- (BOOL)shouldSearchAutomatically {
    return YES;
}

- (void)setFilter:(NSString *)filter {
    const BOOL shouldBeHidden = filter.length == 0;
    if (shouldBeHidden != _filterWrapper.isHidden) {
        [self toggleFilter];
    }
    _filterField.stringValue = filter;
    if (!shouldBeHidden) {
        [_filterField.window makeFirstResponder:_filterField];
        _filterField.currentEditor.selectedRange = NSMakeRange(filter.length, 0);
    }
}

- (void)setFilterProgress:(double)progress {
    iTermSearchFieldCell *cell = [iTermMinimalFilterFieldCell castFrom:_filterField.cell];
    if (round(progress * 100) != round(cell.fraction * 100)) {
        [_filterField setNeedsDisplay:YES];
    }

    [cell setFraction:progress];
    if (cell.needsAnimation && !_filterAnimationTimer) {
        _filterAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                                 target:self
                                                               selector:@selector(redrawFilterField:)
                                                               userInfo:nil
                                                                repeats:YES];
    }
}

#pragma mark - Actions

- (IBAction)closeFindView:(id)sender {
    [self.driver close];
}

- (IBAction)searchPrevious:(id)sender {
    [self.driver searchPrevious];
}

- (IBAction)searchNext:(id)sender {
    [self.driver searchNext];
}

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

- (IBAction)eraseSearchHistory:(id)sender {
    [self.driver eraseSearchHistory];
}

- (IBAction)toggleFilter:(id)sender {
    [self.driver toggleFilter];
}

#pragma mark - NSViewController

- (void)awakeFromNib {
    _baseHeight = NSHeight(self.view.bounds);
    [super awakeFromNib];
}

- (BOOL)validateUserInterfaceItem:(NSMenuItem *)item {
    if (item.action == @selector(toggleFilter:)) {
        item.state = self.filterIsVisible ? NSControlStateValueOn : NSControlStateValueOff;
    } else {
        item.state = (item.tag == self.driver.mode) ? NSControlStateValueOn : NSControlStateValueOff;
    }
    return YES;
}

#pragma mark - NSControl

- (void)controlTextDidChange:(NSNotification *)aNotification {
    NSTextField *field = [aNotification object];
    NSTextView *fieldEditor = aNotification.userInfo[@"NSFieldEditor"];
    if (field == findBarTextField_) {
        [self.driver userDidEditSearchQuery:findBarTextField_.stringValue
                                fieldEditor:fieldEditor];
        return;
    }
    if (field == _filterField) {
        [self.driver userDidEditFilter:_filterField.stringValue
                           fieldEditor:fieldEditor];
        return;
    }
}

- (NSArray *)control:(NSControl *)control
            textView:(NSTextView *)textView
         completions:(NSArray *)words  // Dictionary words
 forPartialWordRange:(NSRange)charRange
 indexOfSelectedItem:(NSInteger *)index {
    if (control == findBarTextField_) {
        DLog(@"completions:forPartialWordRange: existing string is %@, range is %@\n%@",
             textView.string, NSStringFromRange(charRange), [NSThread callStackSymbols]);

        *index = -1;
        return [self.driver completionsForText:[textView string]
                                         range:charRange];
    }
    return @[];
}

- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
    doCommandBySelector:(SEL)commandSelector {
    DLog(@"doCommandBySelector: %@\n%@", NSStringFromSelector(commandSelector), [NSThread callStackSymbols]);
    if (control != findBarTextField_) {
        DLog(@"Wrong control. I'm %@ but was sent by %@", findBarTextField_, control);
        return NO;
    }

    if (NSApp.currentEvent.type == NSEventTypeKeyDown &&
        [NSApp.currentEvent.charactersIgnoringModifiers isEqualToString:@"["] &&
        (NSApp.currentEvent.it_modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagControl)) == NSEventModifierFlagControl) {
        // Control-[
        [self.driver close];
        return YES;
    } else if (commandSelector == @selector(cancelOperation:)) {
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
    DLog(@"controlTextDidEndEditing: %@\n%@", aNotification.userInfo, [NSThread callStackSymbols]);
    NSControl *postingObject = [aNotification object];
    if (postingObject != findBarTextField_) {
        DLog(@"Wrong object. I'm %@, but posting object is %@", self, postingObject);
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

#pragma mark - Private

- (NSRect)superframe {
    return [[[self view] superview] frame];
}

- (void)setOffsetFromTopRightOfSuperview:(NSSize)offset {
    _offset = offset;
    self.view.frame = [self fullSizeFrame];
}

- (NSRect)collapsedFrame {
    const CGFloat height = 0;
    const NSRect myFrame = self.view.frame;
    return NSMakeRect(NSMinX(myFrame) - _offset.width,
                      NSMaxY(self.superframe) - height - _offset.height,
                      NSWidth(myFrame),
                      height);
}

- (NSRect)fullSizeFrame {
    const CGFloat dy = self.filterIsVisible ? 0 : -kFilterHeight;
    const CGFloat height = _baseHeight + dy;
    const NSRect myFrame = self.view.frame;
    return NSMakeRect(NSWidth(self.superframe) - NSWidth(myFrame) - _offset.width,
                      NSHeight(self.superframe) - height - _offset.height,
                      NSWidth(myFrame),
                      height);
}

- (void)makeVisible {
    BOOL wasHidden = [[self view] isHidden];
    if (!wasHidden && [findBarTextField_ textFieldIsFirstResponder]) {
        // The bar was already visible but didn't have focus. Just set the focus.
        [[[self view] window] makeFirstResponder:findBarTextField_];
        return;
    }
    if (wasHidden) {
        [self.driver open];
    } else {
        [findBarTextField_ selectText:nil];
    }
}

- (void)redrawSearchField:(NSTimer *)timer {
    iTermSearchFieldCell *cell = findBarTextField_.cell;
    [cell willAnimate];
    if (!cell.needsAnimation) {
        [_animationTimer invalidate];
        _animationTimer = nil;
    }
    [findBarTextField_ setNeedsDisplay:YES];
}

- (void)redrawFilterField:(NSTimer *)timer {
    iTermSearchFieldCell *cell = _filterField.cell;
    [cell willAnimate];
    if (!cell.needsAnimation) {
        [_filterAnimationTimer invalidate];
        _filterAnimationTimer = nil;
    }
    [_filterField setNeedsDisplay:YES];
}

- (void)deselectFindBarTextField {
    NSText *fieldEditor = [[[self view] window] fieldEditor:YES
                                                  forObject:findBarTextField_];
    [fieldEditor setSelectedRange:NSMakeRange([[fieldEditor string] length], 0)];
    [fieldEditor setNeedsDisplay:YES];
}

#pragma mark - NSCoding

- (void)encodeWithCoder:(nonnull NSCoder *)aCoder {
}

#pragma mark - iTermFocusReportingSearchField

- (void)focusReportingSearchFieldWillBecomeFirstResponder:(iTermFocusReportingSearchField *)sender {
    [self.driver searchFieldWillBecomeFirstResponder:findBarTextField_];
}

- (NSInteger)focusReportingSearchFieldNumberOfResults:(iTermFocusReportingSearchField *)sender {
    return [self.driver numberOfResults];
}

- (NSInteger)focusReportingSearchFieldCurrentIndex:(iTermFocusReportingSearchField *)sender {
    return [self.driver currentIndex];
}

@end
