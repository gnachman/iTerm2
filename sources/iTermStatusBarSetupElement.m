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

@implementation iTermStatusBarSetupElement

- (instancetype)initWithComponentClass:(Class)componentClass {
    self = [super init];
    if (self) {
        _exemplar = [componentClass statusBarComponentExemplar];
        _shortDescription = [componentClass statusBarComponentShortDescription];
        _detailedDescription = [componentClass statusBarComponentDetailedDescription];
        _componentClass = componentClass;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@>", NSStringFromClass([self class]), self, NSStringFromClass(_componentClass)];
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

@end

NS_ASSUME_NONNULL_END
