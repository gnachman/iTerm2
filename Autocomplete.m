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

@implementation AutocompleteView

- (id)init
{
    self = [super initWithWindowNibName:@"Autocomplete"
                               tablePtr:&table_
                                  model:[[[PopupModel alloc] init] autorelease]];
    if (!self) {
        return nil;
    }

    prefix_ = [[NSMutableString alloc] init];
    return self;
}

- (void)dealloc
{
    [prefix_ release];
    [populateTimer_ invalidate];
    [populateTimer_ release];
    [super dealloc];
}

- (void)onOpen
{
    int tx1, ty1, tx2, ty2;
    VT100Screen* screen = [[self session] SCREEN];
    int x = [screen cursorX]-2;
    if (x < 0) {
        [prefix_ setString:@""];
    } else {
        NSString* s = [[[self session] TEXTVIEW] getWordForX:x
                                                           y:[screen cursorY] + [screen numberOfLines] - [screen height] - 1
                                                      startX:&tx1
                                                      startY:&ty1
                                                        endX:&tx2
                                                        endY:&ty2];
        [prefix_ setString:s];
        startX_ = tx1;
        startY_ = ty1 + [screen scrollbackOverflow];
    }
    [self refresh];
}

- (void)refresh
{
    [[self unfilteredModel] removeAllObjects];
    context_.substring = nil;
    VT100Screen* screen = [[self session] SCREEN];

    x_ = startX_;
    y_ = startY_ - [screen scrollbackOverflow];

    [screen initFindString:prefix_
          forwardDirection:NO
              ignoringCase:YES
               startingAtX:x_
               startingAtY:y_
                withOffset:1
                 inContext:&context_];

    [self _doPopulateMore];
}

- (void)onClose
{
    if (populateTimer_) {
        [populateTimer_ invalidate];
        populateTimer_ = nil;
    }
    [super onClose];
}

- (NSAttributedString*)attributedStringForValue:(NSString*)value
{
    NSMutableAttributedString* as = [[[NSMutableAttributedString alloc] init] autorelease];
    NSDictionary* plainAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName,
                                     nil];
    NSAttributedString* attributedSubstr;
    attributedSubstr = [[[NSAttributedString alloc] initWithString:prefix_
                                                        attributes:plainAttributes] autorelease];
    [as appendAttributedString:attributedSubstr];
    [as appendAttributedString:[super attributedStringForValue:value]];
    return as;
}

- (void)rowSelected:(id)sender
{
    if ([table_ selectedRow] >= 0) {
        PopupEntry* e = [[self model] objectAtIndex:[self convertIndex:[table_ selectedRow]]];
        [[self session] insertText:[e mainValue]];
        [super rowSelected:sender];
    }
}

- (void)_populateMore:(id)sender
{
    if (populateTimer_ == nil) {
        return;
    }
    populateTimer_ = nil;
    [self _doPopulateMore];
}

- (void)_doPopulateMore
{
    VT100Screen* screen = [[self session] SCREEN];

    int x = x_;
    int y = y_ - [screen scrollbackOverflow];
    const int kMaxOptions = 20;
    BOOL found;

    struct timeval begintime;
    gettimeofday(&begintime, NULL);

    do {
        BOOL more;
        int startX;
        int startY;
        int endX;
        int endY;
        found = NO;
        do {
            context_.hasWrapped = YES;
            more = [screen continueFindResultAtStartX:&startX
                                             atStartY:&startY
                                               atEndX:&endX
                                               atEndY:&endY
                                                found:&found
                                            inContext:&context_];
            if (found) {
                int tx1, ty1, tx2, ty2;
                NSString* word = [[[self session] TEXTVIEW] getWordForX:endX y:endY startX:&tx1 startY:&ty1 endX:&tx2 endY:&ty2];
                if (tx1 == startX && [word rangeOfString:prefix_ options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location == 0) {
                    ++endX;
                    if (endX > [screen width]) {
                        endX = 1;
                        ++endY;
                    }

                    // Grab the last part of the word after the prefix.
                    NSString* result = [[[self session] TEXTVIEW] contentFromX:endX Y:endY ToX:tx2 Y:ty2 pad:NO];
                    PopupEntry* e = [PopupEntry entryWithString:result];
                    if ([result length] > 0 && [[self unfilteredModel] indexOfObject:e] == NSNotFound) {
                        [[self unfilteredModel] addObject:e];
                    }
                }
                x = x_ = startX;
                y = startY;
                y_ = y + [screen scrollbackOverflow];
            }
        } while (more && [[self unfilteredModel] count] < kMaxOptions);

        if (found && [[self unfilteredModel] count] < kMaxOptions) {
            if (x_ == 0 && y_ <= [screen scrollbackOverflow]) {
                // Last match was on the first char of the screen. All done.
                NSLog(@"Last match on first char");
                break;
            }

            // Begin search again before the last hit.
            [screen initFindString:prefix_
                  forwardDirection:NO
                      ignoringCase:YES
                       startingAtX:x_
                       startingAtY:y_
                        withOffset:1
                         inContext:&context_];
        } else {
            // All done.
            NSLog(@"Didn't find anything or hit max");
            break;
        }

        // Don't spend more than 100ms outside of event loop.
        struct timeval endtime;
        gettimeofday(&endtime, NULL);
        int ms_diff = (endtime.tv_sec - begintime.tv_sec) * 1000 +
            (endtime.tv_usec - begintime.tv_usec) / 1000;
        if (ms_diff > 100) {
            // Out of time. Reschedule and try again.
            populateTimer_ = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                              target:self
                                                            selector:@selector(_populateMore:)
                                                            userInfo:nil
                                                             repeats:NO];
            break;
        }
    } while (found && [[self unfilteredModel] count] < kMaxOptions);
    [self reloadData:YES];
}

@end
