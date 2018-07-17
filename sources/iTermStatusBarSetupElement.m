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
                                   knobs:(NSDictionary *)knobs {
    return [self initWithComponent:[factory newComponentWithKnobs:knobs]];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@>", NSStringFromClass([self class]), self, NSStringFromClass(_component.class)];
}

- (id)exemplar {
    return self.component.statusBarComponentExemplar;
}

#pragma mark - NSCopying

- (id)copyWithZone:(nullable NSZone *)zone {
    NSDictionary *knobs = _component.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [[iTermStatusBarSetupElement alloc] initWithComponent:[_component.statusBarComponentFactory newComponentWithKnobs:knobs]];
}

#pragma mark - NSCoding

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    id<iTermStatusBarComponentFactory> factory = [aDecoder decodeObjectForKey:@"componentFactory"];
    if (!factory) {
        return nil;
    }
    NSDictionary *knobs = [aDecoder decodeObjectOfClass:[NSDictionary class] forKey:@"knobs"];
    return [self initWithComponentFactory:factory knobs:knobs];
}


- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_component.statusBarComponentFactory forKey:@"componentFactory"];
    NSDictionary *knobs = _component.configuration[iTermStatusBarComponentConfigurationKeyKnobValues] ?: @{};
    [aCoder encodeObject:knobs
                  forKey:@"knobs"];
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

@end

NS_ASSUME_NONNULL_END

