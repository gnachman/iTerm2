/*
 **  FindCommandHandler.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Implements the find functions.
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

#import <iTerm/iTermController.h>
#import <iTerm/PTYTextView.h>
#import <iTerm/PseudoTerminal.h>
#import <iTerm/PTYSession.h>
#import <iTerm/FindCommandHandler.h>

#define DEBUG_ALLOC     0

@implementation FindCommandHandler : NSObject

- (id)init;
{
    self = [super init];

    _ignoresCase = [[NSUserDefaults standardUserDefaults] objectForKey:@"findIgnoreCase_iTerm"] ?
        [[NSUserDefaults standardUserDefaults] boolForKey:@"findIgnoreCase_iTerm"] : YES;
    _regex = [[NSUserDefaults standardUserDefaults] boolForKey:@"findRegex_iTerm"];

    return self;
}

- (void)dealloc;
{
    [_searchString release];

    [super dealloc];
}

+ (id)sharedInstance;
{
    static id shared = nil;
    
    if (!shared)
        shared = [[FindCommandHandler alloc] init];
    
    return shared;
}

- (PTYTextView*)currentTextView;
{
    id obj = [[NSApp mainWindow] firstResponder];
    return (obj && [obj isKindOfClass:[PTYTextView class]]) ? obj : nil;
}

- (BOOL)findNext
{
    return [self findSubString:_searchString
              forwardDirection:YES
                  ignoringCase:_ignoresCase
                         regex:_regex
                    withOffset:1];
}

- (BOOL)findPreviousWithOffset:(int)offset
{
    return [self findSubString:_searchString
              forwardDirection:NO
                  ignoringCase:_ignoresCase
                         regex:_regex
                    withOffset:offset];
}

- (void)jumpToSelection
{
    PTYTextView* textView = [self currentTextView];
    if (textView) {
        [textView scrollToSelection];
    } else {
        NSBeep();
    }
}

- (BOOL)findSubString:(NSString *)subString
     forwardDirection:(BOOL)direction
         ignoringCase:(BOOL)caseCheck
                regex:(BOOL)regex
           withOffset:(int)offset
{
    PseudoTerminal* pseudoTerminal = [[iTermController sharedInstance] currentTerminal];
    PTYSession* session = [pseudoTerminal currentSession];
    PTYTextView* textView = [session TEXTVIEW];
    if (textView) {
        if ([subString length] <= 0) {
            NSBeep();
            return NO;
        }

        return [textView findString:subString
                   forwardDirection:direction
                       ignoringCase:caseCheck
                              regex:regex
                         withOffset:offset];
    }
    return NO;
}

- (NSString*)searchString;
{
    return _searchString;
}

- (void) setSearchString: (NSString *) aString
{
            
    [_searchString release];
    _searchString = [aString retain];
}

- (BOOL)ignoresCase;
{    
    return _ignoresCase;
}

- (void)setIgnoresCase:(BOOL)set;
{
    _ignoresCase = set;
    [[NSUserDefaults standardUserDefaults] setBool:set forKey:@"findIgnoreCase_iTerm"];
}

- (BOOL)regex
{
    return _regex;
}

- (void)setRegex:(BOOL)set;
{
    _regex = set;
    [[NSUserDefaults standardUserDefaults] setBool:set forKey:@"findRegex_iTerm"];
}

@end


