//
//  NSDictionary+iTerm.m
//  iTerm
//
//  Created by George Nachman on 1/2/14.
//
//

#import "NSDictionary+iTerm.h"

#import "iTermTuple.h"
#import "NSColor+iTerm.h"
#import "NSWorkspace+iTerm.h"

static NSString *const kGridCoordXKey = @"x";
static NSString *const kGridCoordYKey = @"y";
static NSString *const kGridCoordAbsYKey = @"absY";
static NSString *const kGridCoordStartKey = @"start";
static NSString *const kGridCoordEndKey = @"end";
static NSString *const kGridCoordRange = @"Coord Range";
static NSString *const kGridRange = @"Range";
static NSString *const kGridRangeLocation = @"Location";
static NSString *const kGridRangeLength = @"Length";
static NSString *const kGridSizeWidth = @"Width";
static NSString *const kGridSizeHeight = @"Height";

// Keys for hotkey dictionary
static NSString *const kHotKeyKeyCode = @"keyCode";
static NSString *const kHotKeyModifiers = @"modifiers";
static NSString *const kHotKeyModifierActivation = @"modifier activation";

static const NSEventModifierFlags iTermHotkeyModifierMask = (NSEventModifierFlagCommand |
                                                             NSEventModifierFlagControl |
                                                             NSEventModifierFlagOption |
                                                             NSEventModifierFlagShift);

@interface NSArray(SizeEstimation)
@end

@implementation NSArray(SizeEstimation)

- (NSInteger)addSizeInfoToSizes:(NSMutableDictionary<NSString *, NSNumber *> *)sizes
                         counts:(NSCountedSet<NSString *> *)counts
                        keypath:(NSString *)keypath {
    __block NSInteger total = 0;
    NSString *path = [keypath stringByAppendingString:@"[*]"];
    [self enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSInteger size;
        if ([obj respondsToSelector:_cmd]) {
            size = [(id)obj addSizeInfoToSizes:sizes counts:counts keypath:path];
        } else if ([obj isKindOfClass:[NSString class]]) {
            size = [(NSString *)obj length] * 2;
        } else if ([obj isKindOfClass:[NSData class]]) {
            size = [(NSData *)obj length];
        } else {
            // Enough space for an isa and a word. This is number, date, or null.
            size = 16;
        }
        total += size;
        NSNumber *n = sizes[path];
        n = @(n.integerValue + size);
        sizes[path] = n;
        [counts addObject:path];
    }];
    return total;
}

@end

@implementation NSDictionary (iTerm)

+ (NSDictionary *)dictionaryWithGridCoord:(VT100GridCoord)coord {
    return @{ kGridCoordXKey: @(coord.x),
              kGridCoordYKey: @(coord.y) };
}

- (VT100GridCoord)gridCoord {
    return VT100GridCoordMake([self[kGridCoordXKey] intValue],
                              [self[kGridCoordYKey] intValue]);
}

+ (NSDictionary *)dictionaryWithGridAbsCoord:(VT100GridAbsCoord)coord {
    return @{ kGridCoordXKey: @(coord.x),
              kGridCoordAbsYKey: @(coord.y) };
}

- (VT100GridAbsCoord)gridAbsCoord {
    return VT100GridAbsCoordMake([self[kGridCoordXKey] intValue],
                                 [self[kGridCoordAbsYKey] longLongValue]);
}

+ (NSDictionary *)dictionaryWithGridAbsCoordRange:(VT100GridAbsCoordRange)coordRange {
    return @{ kGridCoordStartKey: [self dictionaryWithGridAbsCoord:coordRange.start],
              kGridCoordEndKey: [self dictionaryWithGridAbsCoord:coordRange.end] };
}

- (VT100GridAbsCoordRange)gridAbsCoordRange {
    VT100GridAbsCoord start = [self[kGridCoordStartKey] gridAbsCoord];
    VT100GridAbsCoord end = [self[kGridCoordEndKey] gridAbsCoord];
    return VT100GridAbsCoordRangeMake(start.x, start.y, end.x, end.y);
}

+ (NSDictionary *)dictionaryWithGridCoordRange:(VT100GridCoordRange)coordRange {
    return @{ kGridCoordStartKey: [self dictionaryWithGridCoord:coordRange.start],
              kGridCoordEndKey: [self dictionaryWithGridCoord:coordRange.end] };
}

- (VT100GridCoordRange)gridCoordRange {
    VT100GridCoord start = [self[kGridCoordStartKey] gridCoord];
    VT100GridCoord end = [self[kGridCoordEndKey] gridCoord];
    return VT100GridCoordRangeMake(start.x, start.y, end.x, end.y);
}

+ (NSDictionary *)dictionaryWithGridWindowedRange:(VT100GridWindowedRange)range {
    return @{ kGridCoordRange: [NSDictionary dictionaryWithGridCoordRange:range.coordRange],
              kGridRange: [NSDictionary dictionaryWithGridRange:range.columnWindow] };
}

- (VT100GridWindowedRange)gridWindowedRange {
    VT100GridWindowedRange range;
    range.coordRange = [self[kGridCoordRange] gridCoordRange];
    range.columnWindow = [self[kGridRange] gridRange];
    return range;
}

+ (NSDictionary *)dictionaryWithGridRange:(VT100GridRange)range {
    return @{ kGridRangeLocation: @(range.location),
              kGridRangeLength: @(range.length) };
}

- (VT100GridRange)gridRange {
    return VT100GridRangeMake([self[kGridRangeLocation] intValue],
                              [self[kGridRangeLength] intValue]);
}

+ (NSDictionary *)dictionaryWithGridSize:(VT100GridSize)size {
    return @{ kGridSizeWidth: @(size.width),
              kGridSizeHeight: @(size.height) };
}

- (VT100GridSize)gridSize {
    return VT100GridSizeMake([self[kGridSizeWidth] intValue], [self[kGridSizeHeight] intValue]);
}

- (BOOL)boolValueDefaultingToYesForKey:(id)key
{
    id object = [self objectForKey:key];
    if (object) {
        return [object boolValue];
    } else {
        return YES;
    }
}

- (BOOL)isColorValue {
    return (self[kEncodedColorDictionaryRedComponent] != nil &&
            self[kEncodedColorDictionaryGreenComponent] != nil &&
            self[kEncodedColorDictionaryBlueComponent] != nil);
}

- (NSColor *)colorValue {
    return [self colorValueWithDefaultAlpha:1.0];
}

- (NSColor *)colorValueWithDefaultAlpha:(CGFloat)alpha {
    if ([self count] < 3) {
        return [NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:1.0];
    }

    NSNumber *alphaNumber = self[kEncodedColorDictionaryAlphaComponent];
    if (alphaNumber) {
        alpha = alphaNumber.doubleValue;
    }
    NSString *colorSpace = self[kEncodedColorDictionaryColorSpace];
    if ([colorSpace isEqualToString:kEncodedColorDictionarySRGBColorSpace]) {
        NSColor *srgb = [NSColor colorWithSRGBRed:[[self objectForKey:kEncodedColorDictionaryRedComponent] floatValue]
                                            green:[[self objectForKey:kEncodedColorDictionaryGreenComponent] floatValue]
                                             blue:[[self objectForKey:kEncodedColorDictionaryBlueComponent] floatValue]
                                            alpha:alpha];
        return srgb;
    } else {
        return [NSColor colorWithCalibratedRed:[[self objectForKey:kEncodedColorDictionaryRedComponent] floatValue]
                                         green:[[self objectForKey:kEncodedColorDictionaryGreenComponent] floatValue]
                                          blue:[[self objectForKey:kEncodedColorDictionaryBlueComponent] floatValue]
                                         alpha:alpha];
    }
}

- (NSDictionary *)dictionaryByRemovingNullValues {
    NSMutableDictionary *temp = [NSMutableDictionary dictionary];
    for (id key in self) {
        id value = self[key];
        if (![value isKindOfClass:[NSNull class]]) {
            temp[key] = value;
        }
    }
    return temp;
}

- (NSDictionary *)dictionaryBySettingObject:(id)object forKey:(id)key {
    NSMutableDictionary *temp = [self mutableCopy];
    temp[key] = object;
    return temp;
}

- (NSDictionary *)dictionaryByRemovingObjectForKey:(id)key {
    NSMutableDictionary *temp = [self mutableCopy];
    [temp removeObjectForKey:key];
    return temp;
}

- (NSData *)propertyListData {
    NSString *filename = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"DictionaryPropertyList" suffix:@"iTerm2"];
    [self writeToFile:filename atomically:NO];
    NSData *data = [NSData dataWithContentsOfFile:filename];
    [[NSFileManager defaultManager] removeItemAtPath:filename error:nil];
    return data;
}

- (NSString *)sizeInfo {
    NSMutableDictionary<NSString *, NSNumber *> *sizes = [NSMutableDictionary dictionary];
    NSCountedSet<NSString *> *counts = [[NSCountedSet alloc] init];
    sizes[@""] = @([self addSizeInfoToSizes:sizes counts:counts keypath:@""]);
    [counts addObject:@""];

    NSMutableString *result = [NSMutableString string];
    [sizes enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSNumber * _Nonnull obj, BOOL * _Nonnull stop) {
        [result appendFormat:@"%@ %@ %@\n", obj, @([counts countForObject:key]), key];
    }];
    return result;
}

- (NSDictionary *)mapValuesWithBlock:(id (^)(id, id))block {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [self enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        id mapped = block(key, obj);
        if (mapped) {
            result[key] = mapped;
        }
    }];
    return result;
}

- (NSDictionary *)mapKeysWithBlock:(id (^)(id, id))block {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [self enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        id mappedKey = block(key, obj);
        if (mappedKey) {
            result[mappedKey] = obj;
        }
    }];
    return result;
}

- (NSDictionary *)mapWithBlock:(iTermTuple *(^)(id, id))block {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [self enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        iTermTuple *tuple = block(key, obj);
        if (tuple) {
            result[tuple.firstObject] = tuple.secondObject;
        }
    }];
    return result;
}

- (NSDictionary<id, NSDictionary *> *)classifyWithBlock:(id (^NS_NOESCAPE)(id key, id object))block {
    NSMutableDictionary<id, NSMutableDictionary *> *result = [NSMutableDictionary dictionary];
    [self enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        id class = block(key, obj);
        if (class) {
            NSMutableDictionary *subdict = result[class];
            if (!subdict) {
                subdict = [NSMutableDictionary dictionary];
                result[class] = subdict;
            }
            subdict[key] = obj;
        }
    }];
    return result;
}

- (NSInteger)addSizeInfoToSizes:(NSMutableDictionary<NSString *, NSNumber *> *)sizes
                    counts:(NSCountedSet<NSString *> *)counts
                   keypath:(NSString *)keypath {
    __block NSInteger total = 0;
    [self enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        NSInteger size;
        NSString *path = [keypath stringByAppendingFormat:@".%@", key];
        if ([obj respondsToSelector:_cmd]) {
            size = [(id)obj addSizeInfoToSizes:sizes counts:counts keypath:path];
        } else if ([obj isKindOfClass:[NSString class]]) {
            size = [(NSString *)obj length] * 2;
        } else if ([obj isKindOfClass:[NSData class]]) {
            size = [(NSData *)obj length];
        } else {
            // Enough space for an isa and a word. This is number, date, or null.
            size = 16;
        }
        total += size;
        NSNumber *n = sizes[path];
        n = @(n.integerValue + size);
        sizes[path] = n;
        [counts addObject:path];
    }];
    return total;
}

- (BOOL)it_writeToXMLPropertyListAt:(NSString *)filename {
    NSOutputStream *outputStream = [NSOutputStream outputStreamToFileAtPath:filename append:NO];
    [outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [outputStream open];
    NSError *error = nil;
    [NSPropertyListSerialization writePropertyList:self
                                          toStream:outputStream
                                            format:NSPropertyListXMLFormat_v1_0
                                           options:0
                                             error:&error];
    [outputStream close];
    return error == nil;
}

@end

@implementation NSDictionary(HotKey)

+ (NSDictionary *)descriptorWithKeyCode:(NSUInteger)keyCode
                              modifiers:(NSEventModifierFlags)modifiers {
    return @{ kHotKeyKeyCode: @(keyCode),
              kHotKeyModifiers: @(modifiers & iTermHotkeyModifierMask) };
}

+ (iTermHotKeyDescriptor *)descriptorWithModifierActivation:(iTermHotKeyModifierActivation)activation {
    return @{ kHotKeyModifierActivation: @(activation) };
}

- (NSUInteger)hotKeyKeyCode {
    return [self[kHotKeyKeyCode] unsignedIntegerValue];
}

- (NSEventModifierFlags)hotKeyModifiers {
    return [self[kHotKeyModifiers] unsignedIntegerValue] & iTermHotkeyModifierMask;
}

- (iTermHotKeyModifierActivation)hotKeyModifierActivation {
    return [self[kHotKeyModifierActivation] unsignedIntegerValue];
}

- (BOOL)isEqualToDictionary:(NSDictionary *)other ignoringKeys:(NSSet *)keysToIgnore {
    NSMutableSet *allKeys = [NSMutableSet set];
    [allKeys addObjectsFromArray:self.allKeys];
    [allKeys addObjectsFromArray:other.allKeys];

    for (id key in allKeys) {
        if ([keysToIgnore containsObject:key]) {
            continue;
        }
        id myValue = self[key];
        if (![myValue isEqual:other[key]]) {
            return NO;
        }
    }
    return YES;
}

- (NSDictionary *)dictionaryByMergingDictionary:(NSDictionary *)other {
    NSMutableDictionary *temp = [self mutableCopy];
    [other enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        temp[key] = obj;
    }];
    return temp;
}

- (BOOL)isExactlyEqualToDictionary:(NSDictionary *)other {
    if (self.count != other.count) {
        return NO;
    }
    __block BOOL result = YES;
    [self enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if (other[key] != obj) {
            *stop = YES;
            result = NO;
        }
    }];
    return result;
}

@end

@implementation NSMutableDictionary (iTerm)

- (NSInteger)removeObjectsPassingTest:(BOOL (^)(id, id))block {
    NSMutableSet *keys = [NSMutableSet set];
    [self enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if (block(key, obj)) {
            [keys addObject:key];
        }
    }];
    [self removeObjectsForKeys:keys.allObjects];
    return keys.count;
}

- (void)it_mergeFrom:(NSDictionary *)other {
    assert(self != other);
    
    [other enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        self[key] = obj;
    }];
}

@end
