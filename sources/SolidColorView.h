//
//  SolidColorView.h
//  iTerm
//
//  Created by George Nachman on 12/6/11.
//

#import <Cocoa/Cocoa.h>

@interface iTermBaseSolidColorView : NSView
@property (nonatomic, strong) NSColor *color;

- (instancetype)initWithFrame:(NSRect)frame color:(NSColor*)color;
- (void)setFlipped:(BOOL)value;
@end

// Users a layer on 10.14+
@interface SolidColorView : iTermBaseSolidColorView
@end

// Never uses a layer
@interface iTermLegacySolidColorView: iTermBaseSolidColorView
@end

// Always uses a layer
@interface iTermLayerBackedSolidColorView : iTermBaseSolidColorView
@end

