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
        _shortDescription = [component.class statusBarComponentShortDescription];
        _detailedDescription = [component.class statusBarComponentDetailedDescription];
        _componentClass = component.class;
        _component = component;
        _component.delegate = self;
    }
    return self;
}

- (instancetype)initWithComponentClass:(Class)componentClass {
    return [self initWithComponent:[[componentClass alloc] initWithConfiguration:@{}]];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@>", NSStringFromClass([self class]), self, NSStringFromClass(_componentClass)];
}

- (id)exemplar {
    return self.component.statusBarComponentExemplar;
}

- (void)setComponentClass:(Class _Nonnull)componentClass {
    _componentClass = componentClass;
}

#pragma mark - NSCopying

- (id)copyWithZone:(nullable NSZone *)zone {
    return [[iTermStatusBarSetupElement alloc] initWithComponentClass:_componentClass];
}

#pragma mark - NSCoding

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    NSString *className = [aDecoder decodeObjectOfClass:[NSString class] forKey:@"componentClassName"];
    if (!className) {
        return nil;
    }
    return [self initWithComponentClass:NSClassFromString(className)];
}


- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:NSStringFromClass(self.componentClass) forKey:@"componentClassName"];
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

