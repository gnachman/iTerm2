//
//  iTermFlexibleView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/2/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermFlexibleView : NSView
@property(nonatomic, retain) NSColor *color;

- (instancetype)initWithFrame:(NSRect)frame color:(NSColor*)color;
- (void)setFlipped:(BOOL)value;

@end

NS_ASSUME_NONNULL_END
