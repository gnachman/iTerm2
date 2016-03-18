// -*- mode:objc -*-
/*
 **  GlobalSearchView.m
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Logic and custom NSView subclass for searching all tabs
 **    simultaneously.
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

#import "GlobalSearch.h"
#import "PTYSession.h"
#import "PTYTextView.h"
#import "PTYTextView.h"
#import "PseudoTerminal.h"
#import "SearchResult.h"
#import "VT100Screen.h"
#import "iTermController.h"
#import "iTermExpose.h"
#import "iTermSearchField.h"
#import "iTermSelection.h"
#import "iTermTextExtractor.h"

const double GLOBAL_SEARCH_MARGIN = 10;

@interface GlobalSearch() <
    NSSearchFieldDelegate,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSTextFieldDelegate>
@end

@interface GlobalSearchInstance : NSObject
{
    PTYTextView* textView_;
    id<PTYTextViewDataSource> textViewDataSource_;
    PTYSession* theSession_;
    NSMutableArray* results_;
    BOOL more_;
    NSString* findString_;
    NSString* label_;
    FindContext *findContext_;
    NSMutableSet* matchLocations_;
}

- (instancetype)initWithSession:(PTYSession *)session
           findString:(NSString*)findString
                label:(NSString*)label;
- (BOOL)more;
- (NSArray*)results;
- (NSString*)label;
- (PTYTextView*)textView;
- (PTYSession*)session;

@end

@interface GlobalSearchResult : NSObject
{
    GlobalSearchInstance* instance_;
    NSString* context_;
    NSString* findString_;
    int x_;
    int endX_;
    long long absY_;
    long long absEndY_;
}

- (instancetype)initWithInstance:(GlobalSearchInstance*)instance context:(NSString*)theContext x:(int)x absY:(long long)absY endX:(int)endX y:(long long)absEndY findString:(NSString*)findString;
- (NSString*)context;
- (NSString*)findString;
- (GlobalSearchInstance*)instance;
- (int)x;
- (int)endX;
- (long long)absY;
- (long long)absEndY;
- (int)y;
- (int)endY;

@end


@implementation GlobalSearchResult

- (instancetype)initWithInstance:(GlobalSearchInstance*)instance
               context:(NSString*)theContext
                     x:(int)x
                  absY:(long long)absY
                  endX:(int)endX
                     y:(long long)absEndY
            findString:(NSString*)findString
{
    assert(findString);
    assert(theContext);
    self = [super init];
    if (self) {
        instance_ = [instance retain];
        context_ = [theContext copy];
        x_ = x;
        endX_ = endX;
        absY_ = absY;
        absEndY_ = absEndY;
        findString_ = [findString copy];
    }
    return self;
}

- (void)dealloc
{
    [instance_ release];
    [context_ release];
    [findString_ release];
    [super dealloc];
}

- (NSString*)context
{
    return context_;
}

- (NSString*)findString
{
    assert(findString_);
    return findString_;
}

- (GlobalSearchInstance*)instance
{
    return instance_;
}

- (int)x
{
    return x_;
}

- (int)endX
{
    return endX_;
}

- (long long)absY
{
    return absY_;
}

- (long long)absEndY
{
    return absEndY_;
}

- (int)y
{
    return absY_ - [[[instance_ textView] dataSource] totalScrollbackOverflow];
}

- (int)endY
{
    return absEndY_ - [[[instance_ textView] dataSource] totalScrollbackOverflow];
}

@end

@implementation GlobalSearchInstance

- (instancetype)initWithSession:(PTYSession *)session
            findString:(NSString*)findString
                 label:(NSString*)label
{
    assert(findString);
    assert(label);
    self = [super init];
    if (self) {
        results_ = [[NSMutableArray alloc] init];
        findString_ = [findString copy];
        more_ = YES;
        textView_ = [session textview];
        textViewDataSource_ = [session screen];
        theSession_ = session;
        label_ = [label retain];
        findContext_ = [[FindContext alloc] init];
        [textViewDataSource_ setFindString:findString_
                          forwardDirection:NO
                              ignoringCase:YES
                                     regex:NO
                               startingAtX:0
                               startingAtY:(long long)([textViewDataSource_ numberOfLines] + 1) + [textViewDataSource_ totalScrollbackOverflow]
                                withOffset:0  // 1?
                                 inContext:findContext_
                           multipleResults:NO];
        matchLocations_ = [[NSMutableSet alloc] init];
        findContext_.maxTime = 0.01;
        findContext_.hasWrapped = YES;
    }
    return self;
}

- (void)dealloc
{
    [matchLocations_ release];
    [results_ release];
    [findString_ release];
    [label_ release];
    [findContext_ release];
    [super dealloc];
}

- (BOOL)more
{
    return more_;
}

- (NSArray*)results
{
    return results_;
}

- (NSString*)label
{
    return label_;
}

- (BOOL)_emitResultFromX:(int)startX absY:(int)absY toX:(int)endX absY:(int)absEndY {
    // Don't add the same line twice.
    NSNumber* setObj = [NSNumber numberWithLongLong:absY];
    if ([matchLocations_ containsObject:setObj]) {
        return NO;
    }
    [matchLocations_ addObject:setObj];

    VT100GridCoordRange theRange =
        VT100GridCoordRangeMake(0,
                                absY,
                                [textViewDataSource_ width] - 1,
                                absEndY - [[textView_ dataSource] totalScrollbackOverflow]);
    iTermTextExtractor *extractor =
        [iTermTextExtractor textExtractorWithDataSource:textViewDataSource_];
    NSString* theContext = [extractor contentInRange:VT100GridWindowedRangeMake(theRange, 0, 0)
                                   attributeProvider:nil
                                          nullPolicy:kiTermTextExtractorNullPolicyFromStartToFirst
                                                 pad:NO
                                  includeLastNewline:NO
                              trimTrailingWhitespace:YES
                                        cappedAtSize:-1
                                   continuationChars:nil
                                              coords:nil];
    theContext = [theContext stringByReplacingOccurrencesOfString:@"\n"
                                                       withString:@" "];
    [results_ addObject:[[[GlobalSearchResult alloc] initWithInstance:self
                                                              context:theContext
                                                                    x:startX
                                                                 absY:absY
                                                                 endX:endX
                                                                    y:absEndY
                                                           findString:findString_] autorelease]];
    return YES;
}

- (int)doSearch
{
    NSMutableArray *results = [NSMutableArray array];
    more_ = [textViewDataSource_ continueFindAllResults:results inContext:findContext_];
    for (SearchResult *result in results) {
        [self _emitResultFromX:result.startX absY:result.absStartY toX:result.endX absY:result.absEndY];
    }
    // TODO Test this! It used to use the deprecated API.
    return results.count;
}

- (PTYTextView*)textView
{
    return textView_;
}

- (PTYSession*)session
{
    return theSession_;
}

@end

@implementation GlobalSearchView

- (void)drawRect:(NSRect)rect
{
    NSRect myFrame = [self frame];
    myFrame.origin.x = GLOBAL_SEARCH_MARGIN;
    myFrame.origin.y = GLOBAL_SEARCH_MARGIN;
    myFrame.size.height -= GLOBAL_SEARCH_MARGIN;
    myFrame.size.width -= 2 * GLOBAL_SEARCH_MARGIN;


    NSShadow *dropShadow = [[[NSShadow alloc] init] autorelease];
    [dropShadow setShadowColor:[NSColor colorWithCalibratedHue:0
                                                    saturation:0
                                                    brightness:0.2
                                                         alpha:1]];
    [dropShadow setShadowBlurRadius:5];
    [dropShadow setShadowOffset:NSMakeSize(0,-4)];

    NSBezierPath* thePath = [NSBezierPath bezierPath];
    [thePath appendBezierPathWithRoundedRect:NSMakeRect(myFrame.origin.x + 5,
                                                        myFrame.origin.y,
                                                        myFrame.size.width - 10,
                                                        myFrame.size.height)
                                     xRadius:10
                                     yRadius:10];
    [dropShadow set];
    [thePath fill];
    
    [[NSColor windowBackgroundColor] set];
    [thePath fill];
}

@end

@implementation GlobalSearch {
    IBOutlet iTermSearchField* searchField_;
    IBOutlet NSTableView* tableView_;
    NSTimer* timer_;
    NSMutableArray* searches_;
    NSMutableArray* combinedResults_;
    id<GlobalSearchDelegate> delegate_;
}

- (void)awakeFromNib
{
    [self view];  // make sure the view is instantiated
    [searchField_ setDelegate:self];
    [searchField_ setArrowHandler:tableView_];
    [tableView_ setDataSource:self];
    [tableView_ setDelegate:self];
    [tableView_ setDoubleAction:@selector(onDoubleClick:)];
    [tableView_ setTarget:self];
    for (NSTableColumn* aCol in [tableView_ tableColumns]) {
        [aCol setEditable:NO];
    }
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        searches_ = [[NSMutableArray alloc] init];
        combinedResults_ = [[NSMutableArray alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(removeDanglers)
                                                     name:@"iTermWindowDidClose"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(removeDanglers)
                                                     name:@"iTermNumberOfSessionsDidChange"
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [combinedResults_ release];
    [timer_ invalidate];
    [searches_ release];
    [super dealloc];
}

- (void)_resizeView
{
    NSRect viewFrame = [[self view] frame];
    const NSRect origViewFrame = viewFrame;
    double dh = viewFrame.size.height;
    
    int n = [combinedResults_ count];
    
    double newTableHeight = 1 + [[tableView_ headerView] frame].size.height + n * ([tableView_ rowHeight] + [tableView_ intercellSpacing].height);
    if (n == 0) {
        newTableHeight = 0;
    }
    viewFrame.size.height = [tableView_ frame].origin.y + newTableHeight + 70; 
    const double maxViewHeight = [[self view] frame].origin.y + [[self view] frame].size.height - 2 * GLOBAL_SEARCH_MARGIN;
    viewFrame.size.height = MIN(maxViewHeight, viewFrame.size.height);
    dh -= viewFrame.size.height;
    viewFrame.origin.y += dh;
    
    if (!NSEqualRects(viewFrame, [[self view] frame])) {
        [[self view] setFrame:viewFrame];
        [delegate_ globalSearchViewDidResize:origViewFrame];
    }
}

- (void)removeDanglers
{
    NSMutableArray* allSessions = [NSMutableArray arrayWithCapacity:100];
    for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
        [allSessions addObjectsFromArray:[term allSessions]];
    }
    for (int i = [searches_ count] - 1; i >= 0; i--) {
        GlobalSearchInstance* inst = [searches_ objectAtIndex:i];
        if ([allSessions indexOfObjectIdenticalTo:[inst session]] == NSNotFound) {
            [searches_ removeObjectAtIndex:i];
        }
    }
    
    for (int i = [combinedResults_ count] - 1; i >= 0; i--) {
        if ([searches_ indexOfObjectIdenticalTo:[[combinedResults_ objectAtIndex:i] instance]] == NSNotFound) {
            [combinedResults_ removeObjectAtIndex:i];
        }
    }
    [self _resizeView];
    [tableView_ reloadData];
}

- (void)_startSearches
{
    [combinedResults_ removeAllObjects];
    [self _resizeView];
    [tableView_ reloadData];
    timer_ = [NSTimer scheduledTimerWithTimeInterval:0.2
                                              target:self
                                            selector:@selector(_continueSearch)
                                            userInfo:nil
                                             repeats:NO];
}

- (void)_addResult:(GlobalSearchResult*)result
{
    int j = [combinedResults_ count];
    for (int i = [combinedResults_ count] - 1; i >= 0; i--) {
        GlobalSearchResult* current = [combinedResults_ objectAtIndex:i];
        if ([current instance] == [result instance]) {
            j = i;
            break;
        }
    }
    [combinedResults_ insertObject:result atIndex:j];
}

- (void)_addLastResultsToTable:(int)n fromInstance:(GlobalSearchInstance*)inst
{
    NSArray* results = [inst results];
    for (int i = [results count] - n; i < [results count]; i++) {
        [self _addResult:[results objectAtIndex:i]];
    }
    [self _resizeView];
    [tableView_ reloadData];
}

- (void)_continueSearch
{
    NSDate* begin = [NSDate date];
    const float kMaxTime = 0.1;
    while ([searches_ count]) {
        GlobalSearchInstance* inst = [searches_ objectAtIndex:0];
        [inst retain];
        [searches_ removeObjectAtIndex:0];
        int newResults = [inst doSearch];
        if ([inst more]) {
            [searches_ addObject:inst]; 
        }
        [self _addLastResultsToTable:newResults fromInstance:inst];
        [inst release];
        
        NSDate* now = [NSDate date];
        if ([now timeIntervalSinceDate:begin] > kMaxTime) {
            break;
        }
    }
    if (![searches_ count]) {
        timer_ = nil;
    } else {
        timer_ = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                  target:self
                                                selector:@selector(_continueSearch)
                                                userInfo:nil
                                                 repeats:NO];
    }        
}

- (void)_clearSearches
{
    [timer_ invalidate];
    timer_ = nil;
    [searches_ removeAllObjects];
}

- (IBAction)onDoubleClick:(id)sender
{
    [delegate_ globalSearchOpenSelection];
}

#pragma mark Search field delegate
- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector
{
    if ([[searchField_ stringValue] length] == 0 &&
        commandSelector == @selector(cancelOperation:)) {
        [delegate_ globalSearchCanceled];
        return YES;
    }
    return NO;
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    int move = [[[aNotification userInfo] objectForKey:@"NSTextMovement"] intValue];
    if (move == NSReturnTextMovement) {
        [delegate_ globalSearchOpenSelection];
    }
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    NSTextField *field = [aNotification object];
    if (field != searchField_) {
        return;
    }
    
    [self _clearSearches];
    NSString* findString = [searchField_ stringValue];
    if ([findString length] == 0) {
        [combinedResults_ removeAllObjects];
        [self _resizeView];
        [tableView_ reloadData];        
        return;
    }
    int i = 0;
    for (PseudoTerminal* aTerminal in [[iTermController sharedInstance] terminals]) {
        for (PTYSession* aSession in [aTerminal allSessions]) {
            NSArray* tabs = [aTerminal tabs];
            int j;
            for (j = 0; j < [tabs count]; ++j) {
                if ([[[tabs objectAtIndex:j] sessions] indexOfObjectIdenticalTo:aSession] != NSNotFound) {
                    break;
                }
            }
            GlobalSearchInstance* aSearch;
            aSearch = [[[GlobalSearchInstance alloc] initWithSession:aSession
                                                           findString:findString
                                                                label:[iTermExpose labelForTab:[aTerminal tabForSession:aSession]
                                                                                  windowNumber:i+1
                                                                                     tabNumber:j+1]] autorelease];
            [searches_ addObject:aSearch];
        }
        i++;
    }
    [self _startSearches];
}

- (NSString*)_tabNameForResult:(GlobalSearchResult*)theResult
{
    return [[theResult instance] label];
}

- (NSAttributedString*)_attributedSubstringOf:(NSAttributedString *)as
                                 narrowerThan:(CGFloat)maxWidth
                                     wantHead:(BOOL)wantHead
{
    // Binary search for the length that best fits.
    int minLen = 0;
    int maxLen = [as length];
    int length = [as length];
    int prev = -1;
    int cur = (minLen + maxLen) / 2;

    NSAttributedString* subString = nil;
    while (cur != prev) {
        if (wantHead) {
            subString = [as attributedSubstringFromRange:NSMakeRange(0, MIN(length, 1+cur))];
        } else {
            int start = MAX(0, length - cur - 1);
            subString = [as attributedSubstringFromRange:NSMakeRange(start, length-start)];
        }
        CGFloat w = [subString size].width;
        if (w >= maxWidth) {
            maxLen = cur;
        } else if (w < maxWidth) {
            minLen = cur;
        }
        prev = cur;
        cur = (maxLen + minLen) / 2;
    }
    return subString;
}

- (NSAttributedString*)_snippetForResult:(GlobalSearchResult*)theResult isSelected:(BOOL)isSelected maxWidth:(CGFloat)maxWidth
{
    NSMutableAttributedString* as = [[[NSMutableAttributedString alloc] init] autorelease];
    NSColor* textColor;
    if (isSelected) {
        textColor = [NSColor whiteColor];
    } else {
        textColor = [NSColor blackColor];
    }
    float size = [NSFont systemFontSize];
    NSFont* sysFont = [NSFont systemFontOfSize:size];
    NSDictionary* plainAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                     sysFont, NSFontAttributeName,
                                     textColor, NSForegroundColorAttributeName,
                                     nil];
    NSDictionary* boldAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSFont boldSystemFontOfSize:size], NSFontAttributeName,
                                    textColor, NSForegroundColorAttributeName,
                                    nil];
    
    NSString* findString = [theResult findString];
    assert(findString);
    NSMutableString* contextTail = [NSMutableString stringWithString:[theResult context]];
    
    NSAttributedString* matchStr = [[[NSAttributedString alloc] initWithString:findString attributes:boldAttributes] autorelease];
    CGFloat matchLen = [matchStr size].width;
    CGFloat maxPrefixWidth = (maxWidth - matchLen) / 2;
    if (maxPrefixWidth < 0) {
        maxPrefixWidth = maxWidth * 0.2;
    }

    while ([contextTail length]) {
        int end;
        NSRange match = [contextTail rangeOfString:findString
                                           options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch)];
        NSString* plainPart;
        NSString* matchPart;
        if (match.location != NSNotFound) {
            if (match.location > 0) {
                plainPart = [contextTail substringWithRange:NSMakeRange(0, match.location)];
            } else {
                plainPart = nil;
            }
            matchPart = [contextTail substringWithRange:match];
            end = match.location + match.length;
        } else {
            plainPart = contextTail;
            matchPart = nil;
            end = [contextTail length];
        }
        if (plainPart) {
            NSAttributedString* substr = [[[NSAttributedString alloc] initWithString:plainPart
                                                                          attributes:plainAttributes] autorelease];
            // Append the first plain part only if it doesn't take more than
            // half the space remaining after including the findString.
            if ([as length] == 0 && 
                [substr size].width > maxPrefixWidth) {
                substr = [self _attributedSubstringOf:substr
                                         narrowerThan:maxPrefixWidth
                                             wantHead:NO];
            }
            [as appendAttributedString:substr];
        }
        if (matchPart) {
            [as appendAttributedString:[[[NSAttributedString alloc] initWithString:matchPart
                                                                        attributes:boldAttributes] autorelease]];
        }
        [contextTail deleteCharactersInRange:NSMakeRange(0, end)];
    }
    
    return [self _attributedSubstringOf:as 
                           narrowerThan:maxWidth
                               wantHead:YES];
}

- (int)numResults
{
    return [combinedResults_ count];
}

#pragma mark NSTableView dataSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [combinedResults_ count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    GlobalSearchResult* theResult = [combinedResults_ objectAtIndex:rowIndex];
    
    switch ([[aTableColumn identifier] intValue]) {
        case 0:
            // Tab name
            return [self _tabNameForResult:theResult];
            
        case 1:
            // Snippet
            return [self _snippetForResult:theResult isSelected:[aTableView selectedRow]==rowIndex maxWidth:[aTableColumn width]];
        default:
            // ??
            return @"";
    }

}

- (void)setDelegate:(id<GlobalSearchDelegate>)delegate
{
    delegate_ = delegate;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    int i = [tableView_ selectedRow];
    GlobalSearchInstance* inst = nil;
    PTYTextView* tv = nil;
    GlobalSearchResult* theResult = nil;
    PTYSession* session = nil;
    if (i >= 0) {
        theResult = [combinedResults_ objectAtIndex:i];
        inst = [theResult instance];
        tv = [inst textView];
        [tv.selection clearSelection];
        VT100GridCoordRange theRange =
            VT100GridCoordRangeMake([theResult x],
                                    [theResult y],
                                    [theResult endX] + 1,
                                    [theResult endY]);
        iTermSubSelection *sub;
        sub = [iTermSubSelection subSelectionWithRange:VT100GridWindowedRangeMake(theRange, 0, 0)
                                                  mode:kiTermSelectionModeCharacter];
        [tv.selection addSubSelection:sub];
        [tv scrollToSelection];
        session = [inst session];
    } else {
        theResult = nil;
    }
    [delegate_ globalSearchSelectionChangedToSession:session];
}

- (void)abort
{
    if (timer_) {
        [timer_ invalidate];
        timer_ = nil;
    }
}

@end
