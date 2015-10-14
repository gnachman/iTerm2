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

@property (nonatomic, assign) iTermExposeGridView *grid;
@property (readonly) NSRect searchFrame;

- (instancetype)initWithFrame:(NSRect)frameRect;
- (iTermExposeTabView*)resultView;
- (PTYSession*)resultSession;

#pragma mark GlobalSearchDelegate
- (void)globalSearchSelectionChangedToSession:(PTYSession*)theSession;
- (void)globalSearchOpenSelection;
- (void)globalSearchViewDidResize:(NSRect)origSize;
- (void)globalSearchCanceled;

@end

