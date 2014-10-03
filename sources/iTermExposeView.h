//
//  iTermExposeView.h
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import <Cocoa/Cocoa.h>
#import "GlobalSearch.h"

@class iTermExposeGridView;
@class iTermExposeTabView;
@class PTYSEssion;

@interface iTermExposeView : NSView <GlobalSearchDelegate>
{
    // Not explicitly retained, but a subview.
    iTermExposeGridView* grid_;
    GlobalSearch* search_;
    iTermExposeTabView* resultView_;
    PTYSession* resultSession_;
    double prevSearchHeight_;
}

- (id)initWithFrame:(NSRect)frameRect;
- (void)dealloc;
- (void)setGrid:(iTermExposeGridView*)grid;
- (iTermExposeGridView*)grid;
- (NSRect)searchFrame;
- (iTermExposeTabView*)resultView;
- (PTYSession*)resultSession;

#pragma mark GlobalSearchDelegate
- (void)globalSearchSelectionChangedToSession:(PTYSession*)theSession;
- (void)globalSearchOpenSelection;
- (void)globalSearchViewDidResize:(NSRect)origSize;
- (void)globalSearchCanceled;

@end

