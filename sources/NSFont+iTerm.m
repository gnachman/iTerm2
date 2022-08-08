//
//  NSFont+iTerm.m
//  iTerm
//
//  Created by George Nachman on 4/15/14.
//
//

#import "NSFont+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "iTermAdvancedSettingsModel.h"

@implementation NSFont (iTerm)

- (NSString *)stringValue {
    NSString *base = [NSString stringWithFormat:@"%@ %g", [self fontName], [self pointSize]];
    NSFontDescriptor *descriptor = self.fontDescriptor;
    NSDictionary<NSFontDescriptorAttributeName, id> *attrs = descriptor.fontAttributes;
    NSArray<NSDictionary *> *settings = attrs[NSFontFeatureSettingsAttribute];
    if (settings.count == 0) {
        return base;
    }
    NSDictionary *dict = @{@"featureSettings": settings};
    NSString *json = [NSJSONSerialization it_jsonStringForObject:dict];
    return [NSString stringWithFormat:@"%@ %@", base, json];
}

- (NSFont *)it_fontByAddingToPointSize:(CGFloat)delta {
    int newSize = [self pointSize] + delta;
    if (newSize < 2) {
        newSize = 2;
    }
    if (newSize > 200) {
        newSize = 200;
    }
    CTFontRef me = (__bridge CTFontRef)self;
    CTFontDescriptorRef myDescriptorCopy = CTFontCopyFontDescriptor(me);
    CGAffineTransform matrix = CTFontGetMatrix(me);
    CTFontRef newFont = CTFontCreateCopyWithAttributes(me,
                                                       newSize,
                                                       &matrix,
                                                       myDescriptorCopy);
    CFRelease(myDescriptorCopy);
    return (__bridge_transfer NSFont *)newFont;
}

+ (NSFont *)it_toolbeltFont {
    double points = [iTermAdvancedSettingsModel toolbeltFontSize];
    if (points <= 0) {
        points = [NSFont smallSystemFontSize];
    }
    NSFont *font = [NSFont fontWithName:[iTermAdvancedSettingsModel toolbeltFont] size:points];
    if (font) {
        return font;
    }
    if (@available(macOS 10.15, *)) {
        return [NSFont monospacedSystemFontOfSize:points weight:NSFontWeightRegular];
    }
    return [NSFont fontWithName:@"Menlo" size:points];
}

- (BOOL)it_hasStylisticAlternatives {
    NSArray *settings = self.fontDescriptor.fontAttributes[NSFontFeatureSettingsAttribute];
    return settings.count > 0;
}

@end
