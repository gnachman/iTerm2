//
//  SolidColorView.h
//  iTerm
//
//  Created by George Nachman on 12/6/11.
//

#import <Cocoa/Cocoa.h>

@protocol iTermSolidColorView<NSObject>
@property(nonatomic, retain) NSColor *color;

- (instancetype)initWithFrame:(NSRect)frame color:(NSColor*)color;
- (void)setFlipped:(BOOL)value;
@end

@interface SolidColorView : NSView<iTermSolidColorView>
@end

@interface iTermLayerBackedSolidColorView : NSView<iTermSolidColorView>
@end

