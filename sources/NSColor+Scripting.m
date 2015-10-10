//
//  NSColor+Scripting.m
//  iTerm2
//
//  Created by George Nachman on 8/19/14.
//
//

#import "NSColor+Scripting.h"

static const CGFloat kRGBColorCoefficient = 65535;

@implementation NSColor (Scripting)

- (NSAppleEventDescriptor *)scriptingRGBColorDescriptor {
    // Make it safe to access red, green, and blue components.
    NSColor *theColor = [self colorUsingColorSpaceName:NSCalibratedRGBColorSpace];

    // Convert self to a QuickDraw RGBColor
    RGBColor rgbColor = {
        .red = (unsigned short)([theColor redComponent] * kRGBColorCoefficient),
        .green = (unsigned short)([theColor greenComponent] * kRGBColorCoefficient),
        .blue = (unsigned short)([theColor blueComponent] * kRGBColorCoefficient)
    };

    // Build a descriptor from it.
    return [NSAppleEventDescriptor descriptorWithDescriptorType:typeRGBColor
                                                          bytes:&rgbColor
                                                         length:sizeof(RGBColor)];
}

+ (NSColor *)scriptingRGBColorWithDescriptor:(NSAppleEventDescriptor *)descriptor {
    // Make sure the descriptor is what we think it is...
    NSAppleEventDescriptor *coercedDescriptor =
        [descriptor coerceToDescriptorType:typeRGBColor];
    if (!coercedDescriptor) {
        return nil;
    }

    NSData *data = [coercedDescriptor data];
    if (sizeof(RGBColor) != [data length]) {
        return nil;
    }

    // And turn it into a NSColor.
    const RGBColor *rgbColor = (const RGBColor *)data.bytes;
    return [NSColor colorWithCalibratedRed:(CGFloat)rgbColor->red / kRGBColorCoefficient
                                     green:(CGFloat)rgbColor->green / kRGBColorCoefficient
                                      blue:(CGFloat)rgbColor->blue / kRGBColorCoefficient
                                     alpha:1.0];
}

@end
