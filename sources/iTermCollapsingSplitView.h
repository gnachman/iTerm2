//
//  iTermCollapsingSplitView.h
//  iTerm2
//
//  Created by George Nachman on 5/2/15.
//
//

#import <Cocoa/Cocoa.h>

@protocol iTermCollapsingSplitViewItem<NSObject>

@property(nonatomic, assign) BOOL collapsed;
@property(nonatomic, assign) NSRect tempFrame;

- (CGFloat)minimumHeight;
- (NSString *)name;

@end

@interface iTermCollapsingSplitView : NSView

@property(nonatomic, retain) NSColor *dividerColor;
@property(nonatomic, readonly) NSArray *items;

- (void)addItem:(NSView<iTermCollapsingSplitViewItem> *)item;
- (void)removeItem:(NSView<iTermCollapsingSplitViewItem> *)item;
- (void)update;
- (void)updateForHeight:(CGFloat)height;

@end
