//
//  NSDictionary+iTerm.h
//  iTerm
//
//  Created by George Nachman on 1/2/14.
//
//

#import <Cocoa/Cocoa.h>
#import "ITAddressBookMgr.h"
#import "VT100GridTypes.h"

@interface NSDictionary<__covariant KeyType, __covariant ObjectType> (iTerm)

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

// If the dict doesn't have an alpha component, use |alpha|.
- (NSColor *)colorValueWithDefaultAlpha:(CGFloat)alpha;

- (NSDictionary *)dictionaryByRemovingNullValues;
- (NSDictionary *)dictionaryBySettingObject:(ObjectType)object forKey:(KeyType)key;

- (NSData *)propertyListData;

@end

// A handy way of describing a hotkey. The modifier flags should be masked before
// the creation of the dictionary.
typedef NSDictionary iTermHotKeyDescriptor;

@interface NSDictionary(HotKey)
+ (iTermHotKeyDescriptor *)descriptorWithKeyCode:(NSUInteger)keyCode
                                       modifiers:(NSEventModifierFlags)modifiers;
+ (iTermHotKeyDescriptor *)descriptorWithModifierActivation:(iTermHotKeyModifierActivation)activation;

- (NSUInteger)hotKeyKeyCode;
- (NSEventModifierFlags)hotKeyModifiers;
- (iTermHotKeyModifierActivation)hotKeyModifierActivation;

@end
