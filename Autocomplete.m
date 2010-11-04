// -*- mode:objc -*-
/*
 **  Autocomplete.m
 **
 **  Copyright (c) 2010
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Implements the Autocomplete UI. It grabs the word behind the
 **      cursor and opens a popup window with likely suffixes. Selecting one
 **      appends it, and you can search the list Quicksilver-style.
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

#include <wctype.h>
#import "Autocomplete.h"
#import "iTerm/iTermController.h"
#import "iTerm/VT100Screen.h"
#import "iTerm/PTYTextView.h"
#import "LineBuffer.h"
@implementation AutocompleteWindow

- (id)initWithContentRect:(NSRect)contentRect
                styleMask:(NSUInteger)aStyle
                  backing:(NSBackingStoreType)bufferingType
                    defer:(BOOL)flag
{
    self = [super initWithContentRect:contentRect
                            styleMask:NSBorderlessWindowMask
                              backing:bufferingType
                                defer:flag];
    [self setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    
    return self;
}

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
    id cont = [self windowController];
    if (cont && [cont respondsToSelector:@selector(keyDown:)]) {
        [cont keyDown:event];
    }
}

@end

@implementation AutocompleteView

- (id)init
{
    self = [super initWithWindowNibName:@"Autocomplete"];
    if (!self) {
        return nil;
    }
    
    prefix_ = [[NSMutableString alloc] init];
    substring_ = [[NSMutableString alloc] init];
    model_ = [[NSMutableArray alloc] init];
    [self window];
    return self;
}

- (void)updatePrefix
{
    int tx1, ty1, tx2, ty2;
    VT100Screen* screen = [dataSource_ SCREEN];
    int x = [screen cursorX]-2;
    if (x < 0) {
        [prefix_ setString:@""];
    } else {
        NSString* s = [[dataSource_ TEXTVIEW] getWordForX:x 
                                                        y:[screen cursorY] + [screen numberOfLines] - [screen height] - 1 
                                                   startX:&tx1 
                                                   startY:&ty1 
                                                     endX:&tx2 
                                                     endY:&ty2];
        [prefix_ setString:s];
        startX_ = tx1;
        startY_ = ty1;
    }
    [self refresh];
}

- (void)setDataSource:(PTYSession*)dataSource
{
    dataSource_ = dataSource;
}

- (void)dealloc
{
    [model_ release];
    [prefix_ release];
    [substring_ release];
    [super dealloc];
}

- (void)refresh
{
    [self _populateModel];
    [table_ reloadData];
    
    NSRect frame = [[self window] frame];
    float diff = frame.size.height;
    frame.size.height = [[table_ headerView] frame].size.height + [model_ count] * ([table_ rowHeight] + [table_ intercellSpacing].height);    
    diff -= frame.size.height;
    if (!onTop_) {
        frame.origin.y += diff;
    }
    [[self window] setFrame:frame display:NO];
    [table_ sizeToFit];
    [[table_ enclosingScrollView] setHasHorizontalScroller:NO];
    
    if ([table_ selectedRow] == -1 && [table_ numberOfRows] > 0) {
        NSIndexSet* indexes = [NSIndexSet indexSetWithIndex:0];
        [table_ selectRowIndexes:indexes byExtendingSelection:NO];
    }
}

- (void)setOnTop:(BOOL)onTop
{
    onTop_ = onTop;
}

- (void)windowDidResignKey:(NSNotification *)aNotification
{
    [[self window] close];
    clearFilterOnNextKeyDown_ = NO;
    if (timer_) {
        [timer_ invalidate];
        timer_ = nil;
    }
    [substring_ setString:@""];
    [self refresh];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    clearFilterOnNextKeyDown_ = NO;
    if (timer_) {
        [timer_ invalidate];
        timer_ = nil;
    }
    [substring_ setString:@""];
    [self refresh];
    if ([table_ numberOfRows] > 0) {
        NSIndexSet* indexes = [NSIndexSet indexSetWithIndex:[table_ numberOfRows] - 1];
        [table_ selectRowIndexes:indexes byExtendingSelection:NO];
    }
}


// DataSource methods
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    NSLog(@"Table view has %d rows", [model_ count]);
    return [model_ count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    NSLog(@"Row %d is %@", rowIndex, [model_ objectAtIndex:rowIndex]);
    return [NSString stringWithFormat:@"%@%@", prefix_, [model_ objectAtIndex:rowIndex]];
}

- (void)rowSelected:(id)sender;
{
    if ([table_ selectedRow] >= 0) {
        [dataSource_ insertText:[model_ objectAtIndex:[table_ selectedRow]]];
        [[self window] close];
    }
}

- (void)keyDown:(NSEvent*)event
{
    unichar c = [[event characters] characterAtIndex:0];
    if (c == '\r') {
        [self rowSelected:self];
    } else if (c == 8 || c == 127) {
        // backspace
        if (timer_) {
            [timer_ invalidate];
            timer_ = nil;
        }
        clearFilterOnNextKeyDown_ = NO;
        [substring_ setString:@""];
        [self refresh];
    } else if (!iswcntrl(c)) {
        if (clearFilterOnNextKeyDown_) {
            [substring_ setString:@""];
            clearFilterOnNextKeyDown_ = NO;
        }
        [substring_ appendString:[event characters]];
        [self refresh];
        if (timer_) {
            [timer_ invalidate];
        }
        timer_ = [NSTimer scheduledTimerWithTimeInterval:4
                                                  target:self
                                                selector:@selector(_setClearFilterOnNextKeyDownFlag:)
                                                userInfo:nil
                                                 repeats:NO];
    } else if (c == 27) {
        // Escape
        [[self window] close];
    }
}

- (void)_setClearFilterOnNextKeyDownFlag:(id)sender
{
    clearFilterOnNextKeyDown_ = YES;
    timer_ = nil;
}

- (BOOL)_word:(NSString*)temp matchesFilter:(NSString*)filter
{
    for (int i = 0; i < [filter length]; ++i) {
        unichar wantChar = [filter characterAtIndex:i];
        NSRange r = [temp rangeOfString:[NSString stringWithCharacters:&wantChar length:1] options:NSCaseInsensitiveSearch];
        if (r.location == NSNotFound) {
            return NO;
        }
        r.length = [temp length] - r.location - 1;
        ++r.location;
        temp = [temp substringWithRange:r];
    }
    return YES;
}

- (void)_populateModel
{
    [model_ removeAllObjects];
    FindContext context;
    context.substring = nil;
    VT100Screen* screen = [dataSource_ SCREEN];

    int x = startX_;
    int y = startY_;
    // TODO: not using absolute y positions. but if screen moves we should close autocomplete anyway.
    
    BOOL found;
    do {
        NSLog(@"Begin search at %d, %d", x, y);
        [screen initFindString:prefix_ 
              forwardDirection:NO 
                  ignoringCase:YES 
                   startingAtX:x
                   startingAtY:y
                    withOffset:1
                     inContext:&context];
        BOOL more;
        int startX;
        int startY;
        int endX;
        int endY;
        found = NO;
//        const int kMaxOptions = 20;
        do {
            NSLog(@"execute search iteration...");
            context.hasWrapped = YES;
            more = [screen continueFindResultAtStartX:&startX 
                                             atStartY:&startY 
                                               atEndX:&endX 
                                               atEndY:&endY 
                                                found:&found
                                            inContext:&context];
            if (found) {
                int tx1, ty1, tx2, ty2;
                NSString* word = [[dataSource_ TEXTVIEW] getWordForX:endX y:endY startX:&tx1 startY:&ty1 endX:&tx2 endY:&ty2];
                NSLog(@"Found word %@ at %d,%d", word, startX, startY);
                ++endX;
                if (endX == [screen width]) {
                    endX = 0;
                    ++endY;
                }
                // TODO: I think this breaks if the selection ends on the very last char on the screen.
                NSString* result = [[dataSource_ TEXTVIEW] contentFromX:endX Y:endY ToX:tx2 Y:ty2 pad:NO];
                if ([result length] > 0 &&
                    [model_ indexOfObject:result] == NSNotFound &&
                    [self _word:result matchesFilter:substring_]) {
                    
                    [model_ addObject:result];
                }
                x = startX;
                y = startY;
            }
        } while (more);
    } while (found);
}

@end
