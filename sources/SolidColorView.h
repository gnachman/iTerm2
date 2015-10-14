//
//  SolidColorView.h
//  iTerm
//
//  Created by George Nachman on 12/6/11.
//

#import <Cocoa/Cocoa.h>

@interface SolidColorView : NSView

@property(nonatomic, retain) NSColor *color;

- (instancetype)initWithFrame:(NSRect)frame color:(NSColor*)color;
- (void)drawRect:(NSRect)dirtyRect;
- (void)setFlipped:(BOOL)value;

@end
