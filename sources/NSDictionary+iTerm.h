//
//  NSDictionary+iTerm.h
//  iTerm
//
//  Created by George Nachman on 1/2/14.
//
//

#import <Cocoa/Cocoa.h>

#import "ITAddressBookMgr.h"
#import "iTermTuple.h"
#import "VT100GridTypes.h"

@class iTermTuple;
@class NSAppearance;

@interface NSDictionary<__covariant KeyType, __covariant ObjectType> (iTerm)

+ (CGFloat)defaultAlphaForColorPresetKey:(NSString *)key;

+ (NSDictionary *)dictionaryWithGridCoord:(VT100GridCoord)coord;
- (VT100GridCoord)gridCoord;

+ (NSDictionary *)dictionaryWithGridAbsCoord:(VT100GridAbsCoord)coord;
- (VT100GridAbsCoord)gridAbsCoord;

+ (NSDictionary *)dictionaryWithGridAbsCoordRange:(VT100GridAbsCoordRange)coordRange;
- (VT100GridAbsCoordRange)gridAbsCoordRange;

+ (NSDictionary *)dictionaryWithGridCoordRange:(VT100GridCoordRange)coordRange;
- (VT100GridCoordRange)gridCoordRange;

+ (NSDictionary *)dictionaryWithGridWindowedRange:(VT100GridWindowedRange)range;
- (VT100GridWindowedRange)gridWindowedRange;

+ (NSDictionary *)dictionaryWithGridRange:(VT100GridRange)range;
- (VT100GridRange)gridRange;

+ (NSDictionary *)dictionaryWithGridSize:(VT100GridSize)size;
- (VT100GridSize)gridSize;

- (BOOL)boolValueDefaultingToYesForKey:(id)key;
- (NSColor *)colorValue;
- (BOOL)isColorValue;

// Uses the key to choose the default alpha value.
- (NSColor *)colorValueForKey:(NSString *)key;


- (NSDictionary *)dictionaryByRemovingNullValues;
- (NSDictionary *)dictionaryBySettingObject:(ObjectType)object forKey:(KeyType)key;
- (NSDictionary *)dictionaryByRemovingObjectForKey:(KeyType)key;
- (NSDictionary<KeyType, ObjectType> *)dictionaryKeepingOnlyKeys:(NSArray<KeyType> *)keys;

- (NSData *)propertyListData;
- (NSString *)sizeInfo;

// Returns a dictionary with changed values. If the block returns nil the
// entry is omitted.
- (NSDictionary *)mapValuesWithBlock:(id (^)(KeyType key, ObjectType object))block;
- (NSDictionary *)mapKeysWithBlock:(KeyType (^)(KeyType key, ObjectType object))block;
// tuple is iTermTuple<KeyType, ObjectType>. Compiler won't let me write this.
- (NSDictionary *)mapWithBlock:(iTermTuple * (^)(KeyType key, ObjectType object))block;
- (NSDictionary<id, NSDictionary<KeyType, ObjectType> *> *)classifyWithBlock:(id (^NS_NOESCAPE)(KeyType key, ObjectType object))block;

- (BOOL)it_writeToXMLPropertyListAt:(NSString *)path;

- (NSDictionary *)it_attributesDictionaryWithAppearance:(NSAppearance *)appearance;

@end

// A handy way of describing the essential parts of a hotkey, as far as being a uniquely registered
// keystroke goes. Does not include any nonessential information could is not related to the
// bare-metal mechanics of a keypress. The modifier flags should be masked before the creation of
// the dictionary.
typedef NSDictionary iTermHotKeyDescriptor;

@interface NSDictionary(HotKey)
+ (iTermHotKeyDescriptor *)descriptorWithKeyCode:(NSUInteger)keyCode
                                       modifiers:(NSEventModifierFlags)modifiers;
+ (iTermHotKeyDescriptor *)descriptorWithModifierActivation:(iTermHotKeyModifierActivation)activation;

- (NSUInteger)hotKeyKeyCode;
- (NSEventModifierFlags)hotKeyModifiers;
- (iTermHotKeyModifierActivation)hotKeyModifierActivation;

- (BOOL)isEqualToDictionary:(NSDictionary *)other ignoringKeys:(NSSet *)keysToIgnore;
- (NSDictionary *)dictionaryByMergingDictionary:(NSDictionary *)other;

// Compares pointers only
- (BOOL)isExactlyEqualToDictionary:(NSDictionary *)other;

@end

@interface NSMutableDictionary<KeyType, ObjectType> (iTerm)
- (NSInteger)removeObjectsPassingTest:(BOOL (^)(KeyType key, ObjectType obj))block;
- (void)it_mergeFrom:(NSDictionary<KeyType, ObjectType> *)other;
- (void)it_addObject:(id)object toMutableArrayForKey:(KeyType)key;
@end

