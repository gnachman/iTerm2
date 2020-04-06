//
//  iTermSearchResultsMinimapView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/14/20.
//

#import <Cocoa/Cocoa.h>
#import "iTermTuple.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermSearchResultsMinimapView;

NS_CLASS_AVAILABLE_MAC(10_14)
@protocol iTermSearchResultsMinimapViewDelegate<NSObject>
- (NSIndexSet *)searchResultsMinimapViewLocations:(iTermSearchResultsMinimapView *)view;
- (NSRange)searchResultsMinimapViewRangeOfVisibleLines:(iTermSearchResultsMinimapView *)view;
@end

@interface iTermBaseMinimapView: NSView
- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;

- (void)invalidate;
@end

NS_CLASS_AVAILABLE_MAC(10_14)
@interface iTermSearchResultsMinimapView : iTermBaseMinimapView
@property (nonatomic, weak) id<iTermSearchResultsMinimapViewDelegate> delegate;
@end

@interface iTermIncrementalMinimapView: iTermBaseMinimapView

// (outline color, fill color)
- (instancetype)initWithColors:(NSArray<iTermTuple<NSColor *, NSColor *> *> *)colors NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)addObjectOfType:(NSInteger)objectType onLine:(NSInteger)line;
- (void)removeObjectOfType:(NSInteger)objectType fromLine:(NSInteger)line;
- (void)setFirstVisibleLine:(NSInteger)firstVisibleLine
       numberOfVisibleLines:(NSInteger)numberOfVisibleLines;
- (void)removeAllObjects;
- (void)setLines:(NSMutableIndexSet *)lines forType:(NSInteger)type;

@end

NS_ASSUME_NONNULL_END
