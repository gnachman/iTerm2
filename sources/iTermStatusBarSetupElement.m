//
//  iTermStatusBarSetupElement.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarSetupElement.h"
#import "iTermStatusBarComponent.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const iTermStatusBarElementPasteboardType = @"com.iterm2.status-bar-element";

@interface iTermStatusBarSetupElement() <iTermStatusBarComponentDelegate>
@end

@implementation iTermStatusBarSetupElement {
    id<iTermStatusBarComponent> _component;
}

- (instancetype)initWithComponent:(id<iTermStatusBarComponent>)component {
    self = [super init];
    if (self) {
        _shortDescription = [component statusBarComponentShortDescription];
        _detailedDescription = [component statusBarComponentDetailedDescription];
        _component = component;
        _component.delegate = self;
    }
    return self;
}

- (instancetype)initWithComponentFactory:(id<iTermStatusBarComponentFactory>)factory
                         layoutAlgorithm:(iTermStatusBarLayoutAlgorithmSetting)layoutAlgorithm
                                   knobs:(NSDictionary *)knobs {
    return [self initWithComponent:[factory newComponentWithKnobs:knobs
                                                  layoutAlgorithm:layoutAlgorithm
                                                            scope:nil]];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@>", NSStringFromClass([self class]), self, NSStringFromClass(_component.class)];
}

- (NSAttributedString *)exemplarWithBackgroundColor:(NSColor *)defaultBackgroundColor
                                          textColor:(NSColor *)defaultTextColor
                                        defaultFont:(NSFont *)defaultFont {
    NSColor *backgroundColor = self.component.statusBarBackgroundColor ?: defaultBackgroundColor;
    NSColor *textColor = self.component.statusBarTextColor;
    if (textColor == [NSColor labelColor] || textColor == nil) {
        textColor = defaultTextColor;
    }
    id object = [self.component statusBarComponentExemplarWithBackgroundColor:backgroundColor
                                                                    textColor:textColor];
    if ([object isKindOfClass:[NSAttributedString class]]) {
        return object;
    }

    NSFont *font = defaultFont ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
    NSDictionary *attributes = @{ NSFontAttributeName: font,
                                  NSForegroundColorAttributeName: textColor ?: [NSColor labelColor],
                                  NSBackgroundColorAttributeName: [NSColor clearColor] };
    return [[NSAttributedString alloc] initWithString:object attributes:attributes];
}


#pragma mark - NSCopying

- (id)copyWithZone:(nullable NSZone *)zone {
    NSDictionary *knobs = _component.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    NSDictionary *dict = _component.configuration[iTermStatusBarComponentConfigurationKeyLayoutAdvancedConfigurationDictionaryValue];
    iTermStatusBarAdvancedConfiguration *advancedConfiguration = [iTermStatusBarAdvancedConfiguration advancedConfigurationFromDictionary:dict];
    return [[iTermStatusBarSetupElement alloc] initWithComponent:[_component.statusBarComponentFactory newComponentWithKnobs:knobs
                                                                                                             layoutAlgorithm:advancedConfiguration.layoutAlgorithm
                                                                                                                       scope:nil]];
}

#pragma mark - NSCoding

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    id<iTermStatusBarComponentFactory> factory = [aDecoder decodeObjectForKey:@"componentFactory"];
    if (!factory) {
        return nil;
    }
    NSDictionary *knobs = [aDecoder decodeObjectOfClass:[NSDictionary class] forKey:@"knobs"];
    return [self initWithComponentFactory:factory
                          layoutAlgorithm:[aDecoder decodeIntegerForKey:@"layoutAlgorithm"]
                                    knobs:knobs];
}


- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_component.statusBarComponentFactory forKey:@"componentFactory"];
    NSDictionary *knobs = _component.configuration[iTermStatusBarComponentConfigurationKeyKnobValues] ?: @{};
    [aCoder encodeObject:knobs
                  forKey:@"knobs"];
    NSDictionary *dict = _component.configuration[iTermStatusBarComponentConfigurationKeyLayoutAdvancedConfigurationDictionaryValue];
    iTermStatusBarAdvancedConfiguration *advancedConfiguration = [iTermStatusBarAdvancedConfiguration advancedConfigurationFromDictionary:dict];
    [aCoder encodeInteger:advancedConfiguration.layoutAlgorithm forKey:@"layoutAlgorithm"];
}

#pragma mark - NSPasteboardWriting

- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
    return @[ iTermStatusBarElementPasteboardType ];
}


- (nullable id)pasteboardPropertyListForType:(NSString *)type {
    // I am using the bundleID as a type
    if (![type isEqualToString:iTermStatusBarElementPasteboardType]) {
        return nil;
    }

    return [NSKeyedArchiver archivedDataWithRootObject:self];
}

#pragma mark - NSPasteboardReading

+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard {
    return @[ iTermStatusBarElementPasteboardType ];
}

- (nullable instancetype)initWithPasteboardPropertyList:(id)propertyList ofType:(NSString *)type {
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:propertyList];
    return [self initWithCoder:unarchiver];
}

#pragma mark - iTermStatusBarComponentDelegate

- (void)statusBarComponentKnobsDidChange:(id<iTermStatusBarComponent>)component {
    [self.delegate itermStatusBarSetupElementDidChange:self];
}

- (BOOL)statusBarComponentIsInSetupUI:(id<iTermStatusBarComponent>)component {
    return YES;
}

- (void)statusBarComponentPreferredSizeDidChange:(id<iTermStatusBarComponent>)component {
}

- (NSColor *)statusBarComponentDefaultTextColor {
    return [NSColor labelColor];
}

- (BOOL)statusBarComponentIsVisible:(id<iTermStatusBarComponent>)component {
    // Say no so that git components don't do work for no reason.
    return NO;
}

- (NSFont *)statusBarComponentTerminalFont:(id<iTermStatusBarComponent>)component {
    return [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

- (void)statusBarComponent:(id<iTermStatusBarComponent>)component writeString:(NSString *)string {
}

- (BOOL)statusBarComponentTerminalBackgroundColorIsDark:(id<iTermStatusBarComponent>)component {
    return NO;
}

- (void)statusBarComponentOpenStatusBarPreferences:(id<iTermStatusBarComponent>)component {
    assert(NO);
}

@end

NS_ASSUME_NONNULL_END

