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

const int kMaxContextWords = 2;

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
    context_ = [[NSMutableArray alloc] init];

    return self;
}

- (void)dealloc
{
    [context_ release];
    [prefix_ release];
    [populateTimer_ invalidate];
    [populateTimer_ release];
    [super dealloc];
}

- (void)appendContextAtX:(int)x y:(int)y into:(NSMutableArray*)context maxWords:(int)maxWords
{
    const int kMaxIterations = maxWords * 2;
    VT100Screen* screen = [[self session] SCREEN];
    NSCharacterSet* nonWhitespace = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
    for (int i = 0; i < kMaxIterations && [context count] < maxWords; ++i) {
        // Move back one position
        --x;
        if (x < 0) {
            x += [screen width];
            --y;
        }
        if (y < 0) {
            break;
        }

        int tx1, tx2, ty1, ty2;
        NSString* s = [[[self session] TEXTVIEW] getWordForX:x
                                                           y:y
                                                      startX:&tx1
                                                      startY:&ty1
                                                        endX:&tx2
                                                        endY:&ty2];
        if ([s rangeOfCharacterFromSet:nonWhitespace].location != NSNotFound) {
            // Add only if not whitespace.
            //NSLog(@"Add to context (%d/%d): %@", [context count], maxWords, s);
            [context addObject:s];
        }
        x = tx1;
    }
}

- (void)onOpen
{
    int tx1, ty1, tx2, ty2;
    VT100Screen* screen = [[self session] SCREEN];
    int x = [screen cursorX]-2;
    [context_ removeAllObjects];
    NSCharacterSet* nonWhitespace = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
    if (x < 0) {
        [prefix_ setString:@""];
    } else {
        int y = [screen cursorY] + [screen numberOfLines] - [screen height] - 1;
        NSString* s = [[[self session] TEXTVIEW] getWordForX:x
                                                           y:y
                                                      startX:&tx1
                                                      startY:&ty1
                                                        endX:&tx2
                                                        endY:&ty2];
        int maxWords = kMaxContextWords;
        if ([s rangeOfCharacterFromSet:nonWhitespace].location == NSNotFound) {
            ++maxWords;
        } else {
            [prefix_ setString:s];
        }
        //NSLog(@"Prefix is %@ starting at %d", s, tx1);
        startX_ = tx1;
        startY_ = ty1 + [screen scrollbackOverflow];

        [self appendContextAtX:tx1 y:ty1 into:context_ maxWords:maxWords];
        if (maxWords > kMaxContextWords) {
            if ([context_ count] > 0) {
                [prefix_ setString:[context_ objectAtIndex:0]];
                [context_ removeObjectAtIndex:0];
            } else {
                [prefix_ setString:@""];
            }
        }
    }
}

- (void)refresh
{
    [[self unfilteredModel] removeAllObjects];
    findContext_.substring = nil;
    VT100Screen* screen = [[self session] SCREEN];

    x_ = startX_;
    y_ = startY_ - [screen scrollbackOverflow];

    //NSLog(@"Searching for '%@'", prefix_);
    [screen initFindString:prefix_
          forwardDirection:NO
              ignoringCase:YES
               startingAtX:x_
               startingAtY:y_
                withOffset:1
                 inContext:&findContext_];

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

- (double)contextSimilarityBetweenQuery:(NSArray*)queryContext andResult:(NSArray*)resultContext
{
    NSMutableArray* scratch = [NSMutableArray arrayWithArray:resultContext];
    double similarity = 0;
    //NSLog(@"  Determining similarity score. Initialized to 0.");
    for (int i = 0; i < [queryContext count]; ++i) {
        NSString* qs = [queryContext objectAtIndex:i];
        //NSLog(@"  Looking for match for query string '%@'", qs);
        for (int j = 0; j < [scratch count]; ++j) {
            NSString* rs = [scratch objectAtIndex:j];
            // Distance is a measure of how far a word in the query context is from
            // a word in the result context. Higher distances hurt the similarity
            // score.
            double distance = abs(i - j) + 1;
            if ([qs localizedCompare:rs] == NSOrderedSame) {
                //NSLog(@"  Exact match %@ = %@. Incr similarity by %lf", rs, qs, (1.0/distance));
                similarity += 1.0 / distance;
                [scratch replaceObjectAtIndex:j withObject:@""];
                break;
            } else if ([qs localizedCaseInsensitiveCompare:rs] == NSOrderedSame) {
                //NSLog(@"  Approximate match of %@ = %@. Incr similarity by %lf", rs, qs, (0.9/distance));
                similarity += 0.9 / distance;
                [scratch replaceObjectAtIndex:j withObject:@""];
                break;
            }
        }
    }
    //NSLog(@"  Final similarity score is %lf", similarity);
    return similarity;
}

- (NSString*)formatContext:(NSArray*)context
{
    NSMutableString* s = [NSMutableString stringWithString:@""];
    for (int i = 0; i < [context count]; ++i) {
        [s appendFormat:@"'%@' ", [context objectAtIndex:i]];
    }
    return s;
}

- (double)scoreResultNumber:(int)resultNumber queryContext:(NSArray*)queryContext resultContext:(NSArray*)resultContext
{
    //NSLog(@"Score result #%d with queryContext:%@ and resultContext:%@", resultNumber, [self formatContext:queryContext], [self formatContext:resultContext]);
    double similarity = [self contextSimilarityBetweenQuery:queryContext andResult:resultContext] * 2;
    // Square similarity so that it has a strong effect if a full context match
    // is found. Likewise, add 5 to the denominator so that the result number has
    // a small influence when it's close to 0.
    double score = (1.0 + similarity * similarity)/(double)(resultNumber + 5);
    //NSLog(@"Final score is %lf", score);
    return score;
}

- (void)_doPopulateMore
{
    VT100Screen* screen = [[self session] SCREEN];
    const int kMaxOptions = 20;
    BOOL found;

    struct timeval begintime;
    gettimeofday(&begintime, NULL);
    NSCharacterSet* nonWhitespace = [[NSCharacterSet whitespaceCharacterSet] invertedSet];

    do {
        BOOL more;
        int startX;
        int startY;
        int endX;
        int endY;
        found = NO;
        do {
            findContext_.hasWrapped = YES;
            //NSLog(@"Continue search...");
            more = [screen continueFindResultAtStartX:&startX
                                             atStartY:&startY
                                               atEndX:&endX
                                               atEndY:&endY
                                                found:&found
                                            inContext:&findContext_];
            if (found) {
                //NSLog(@"Found match at %d-%d, line %d", startX, endX, startY);
                int tx1, ty1, tx2, ty2;
                // Get the word that includes the match.
                NSString* word = [[[self session] TEXTVIEW] getWordForX:startX y:startY startX:&tx1 startY:&ty1 endX:&tx2 endY:&ty2];
                NSRange range = [word rangeOfString:prefix_ options:(NSCaseInsensitiveSearch|NSAnchoredSearch)];
                if (range.location == 0) {
                    // Result has prefix_ as prefix.
                    BOOL fullMatch = (range.length == [word length]);

                    // Grab the context before the match.
                    NSMutableArray* resultContext = [NSMutableArray arrayWithCapacity:2];
                    //NSLog(@"Word before what we want is in x=[%d to %d]", startX, endX);
                    [self appendContextAtX:startX y:(int)startY into:resultContext maxWords:kMaxContextWords];

                    if (fullMatch) {
                        // Grab the word after the match (presumably containing non-word characters)
                        ++endX;
                        if (endX >= [screen width]) {
                            endX -= [screen width];
                            ++endY;
                        }
                        word = [[[self session] TEXTVIEW] getWordForX:endX y:endY startX:&tx1 startY:&ty1 endX:&tx2 endY:&ty2];
                        //NSLog(@"First candidate is at %d-%d, %d: '%@'", tx1, tx2, ty1, word);
                        if ([word rangeOfCharacterFromSet:nonWhitespace].location == NSNotFound) {
                            // word after match is all whitespace. Grab the next word.
                            if (tx2 == [screen width]) {
                                tx2 = 0;
                                ++ty2;
                            }
                            if (ty2 < [screen numberOfLines]) {
                                word = [NSString stringWithFormat:@" %@", [[[self session] TEXTVIEW] getWordForX:tx2 y:ty2 startX:&tx1 startY:&ty1 endX:&tx2 endY:&ty2]];
                                //NSLog(@"Replacement candidate is at %d-%d, %d: '%@'", tx1, tx2, ty1, word);
                            } else {
                                //NSLog(@"Hit end of screen.");
                            }
                        }
                    } else {
                        // Get suffix of word after match.
                        word = [word substringWithRange:NSMakeRange(range.length, [word length] - range.length)];
                    }

                    if ([word rangeOfCharacterFromSet:nonWhitespace].location != NSNotFound) {
                        // Found a non-whitespace word after the match.
                        //NSLog(@"Candidate suffix is '%@'", word);
                        PopupEntry* e = [PopupEntry entryWithString:word score:[self scoreResultNumber:[[self unfilteredModel] count]
                                                                                          queryContext:context_
                                                                                         resultContext:resultContext]];
                        if (!fullMatch) {
                            [e setPrefix:prefix_];
                        }
                        [[self unfilteredModel] addHit:e];
                    } else {
                        //NSLog(@"No candidate here.");
                    }
                    x_ = startX;
                    y_ = startY + [screen scrollbackOverflow];
                    //NSLog(@"Update x,y to %d,%d", x_, y_);
                } else {
                    // Match started in the middle of a word.
                    //NSLog(@"Search found %@ which doesn't start the same as our search term %@", word, prefix_);
                    x_ = startX;
                    y_ = startY + [screen scrollbackOverflow];
                }
            }
        } while (more && [[self unfilteredModel] count] < kMaxOptions);

        if (found && [[self unfilteredModel] count] < kMaxOptions) {
            if (y_ < [screen scrollbackOverflow] ||
                (x_ <= 0 && y_ == [screen scrollbackOverflow])) {
                // Last match was on the first char of the screen. All done.
                //NSLog(@"BREAK: Last match on first char");
                break;
            }

            // Begin search again before the last hit.
            //NSLog(@"Continue search at %d,%d", x_, y_);
            [screen initFindString:prefix_
                  forwardDirection:NO
                      ignoringCase:YES
                       startingAtX:x_
                       startingAtY:y_
                        withOffset:1
                         inContext:&findContext_];
        } else {
            // All done.
            //NSLog(@"BREAK: Didn't find anything or hit max");
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
