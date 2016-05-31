//
//  NSArray+iTerm.m
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import "NSArray+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"

@implementation NSArray (iTerm)

- (NSArray *)objectsOfClasses:(NSArray *)classes {
    NSMutableArray *result = [NSMutableArray array];
    for (NSObject *object in self) {
        for (Class validClass in classes) {
            if ([object isKindOfClass:validClass]) {
                [result addObject:object];
                break;
            }
        }
    }
    return result;
}

- (NSAttributedString *)attributedComponentsJoinedByAttributedString:(NSAttributedString *)joiner {
    NSMutableAttributedString *result = [[[NSMutableAttributedString alloc] init] autorelease];
    for (NSAttributedString *element in self) {
        [result appendAttributedString:element];
        if (element != self.lastObject) {
            [result appendAttributedString:joiner];
        }
    }
    return result;
}

- (NSArray *)mapWithBlock:(id (^)(id anObject))block {
    NSMutableArray *temp = [NSMutableArray array];
    for (id anObject in self) {
        [temp addObject:block(anObject)];
    }
    return temp;
}

- (NSArray *)filteredArrayUsingBlock:(BOOL (^)(id anObject))block {
    NSIndexSet *indexes = [self indexesOfObjectsPassingTest:^BOOL(id  _Nonnull obj,
                                                                  NSUInteger idx,
                                                                  BOOL * _Nonnull stop) {
        return block(obj);
    }];
    return [self objectsAtIndexes:indexes];
}

- (BOOL)containsObjectBesides:(id)anObject {
    for (id object in self) {
        if (![object isEqual:anObject]) {
            return YES;
        }
    }
    return NO;
}

- (NSString *)numbersAsHexStrings {
    NSMutableString *result = [NSMutableString string];
    NSString *separator = @"";
    for (NSNumber *number in self) {
        if (![number isKindOfClass:[NSNumber class]]) {
            continue;
        }
        [result appendFormat:@"%@0x%x", separator, number.intValue];
        separator = @" ";
    }
    return result;
}

@end

@implementation NSMutableArray (iTerm)

- (void)reverse {
    if ([self count] == 0) {
        return;
    }
    NSUInteger i = 0;
    NSUInteger j = [self count] - 1;
    while (i < j) {
        [self exchangeObjectAtIndex:i withObjectAtIndex:j];
        i++;
        j--;
    }
}

@end
