//
//  NSFont+iTerm.m
//  iTerm
//
//  Created by George Nachman on 4/15/14.
//
//

#import "NSFont+iTerm.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBijection.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"

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

- (BOOL)it_hasContextualAlternates {
    static char key;
    NSNumber *cached = [self it_associatedObjectForKey:&key];
    if (cached) {
        return cached.boolValue;
    }
    // Convert NSFont to CTFont
    CTFontRef ctFont = (__bridge CTFontRef)self;

    // Get the font features
    CFArrayRef features = CTFontCopyFeatures(ctFont);
    if (!features) {
        return NO;
    }

    // Check for contextual alternates (feature type 36)
    BOOL hasCalt = NO;
    for (NSDictionary *feature in (__bridge NSArray *)features) {
        NSNumber *typeIdentifier = feature[(__bridge NSString *)kCTFontFeatureTypeIdentifierKey];
        if (typeIdentifier && [typeIdentifier integerValue] == kContextualAlternatesType) {
            hasCalt = YES;
            break;
        }
    }

    // Clean up
    CFRelease(features);

    [self it_setAssociatedObject:@(hasCalt) forKey:&key];
    return hasCalt;
}

static iTermBijection<NSNumber *, NSFont *> *iTermMetalFontBijection(void) {
    static iTermBijection<NSNumber *, NSFont *> *bijection;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bijection = [[iTermBijection alloc] init];
    });
    return bijection;
}

- (int)it_metalFontID {
    iTermBijection<NSNumber *, NSFont *> *bijection = iTermMetalFontBijection();
    @synchronized(bijection) {
        NSNumber *number = [bijection objectForRight:self];
        if (number) {
            return number.intValue;
        }
        static int nextNumber;
        const int newNumber = nextNumber++;
        [bijection link:@(newNumber) to:self];
        return newNumber;
    }
}

+ (instancetype)it_fontWithMetalID:(int)metalID {
    iTermBijection<NSNumber *, NSFont *> *bijection = iTermMetalFontBijection();
    @synchronized(bijection) {
        return [bijection objectForLeft:@(metalID)];
    }
}

- (CGSize)it_pitch {
    return [@"M" sizeWithAttributes:@{ NSFontAttributeName: self }];
}

@end
