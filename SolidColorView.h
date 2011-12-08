//
//  SolidColorView.h
//  iTerm
//
//  Created by George Nachman on 12/6/11.
//

#import <Cocoa/Cocoa.h>

@interface SolidColorView : NSView
{
    NSColor* color_;
    BOOL isFlipped_;
}

- (id)initWithFrame:(NSRect)frame color:(NSColor*)color;
- (void)drawRect:(NSRect)dirtyRect;
- (void)setColor:(NSColor*)color;
- (NSColor*)color;
- (void)setFlipped:(BOOL)value;

@end
