//
//  iTermKeystroke.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/20/20.
//

#import <Cocoa/Cocoa.h>
#import "iTermPromise.h"

typedef NS_ENUM(NSUInteger, iTermEventModifierFlags) {
    // Pray that Apple never uses this. If they do I will have a gnarly migration to deal with.
    iTermLeaderModifierFlag = 1 << 24
};

NS_ASSUME_NONNULL_BEGIN

@interface iTermKeystroke: NSObject<NSCopying>
@property (nonatomic) BOOL hasVirtualKeyCode;

// The virtual key code is not used in ordering or comparison. Its only purpose is to improve the
// quality of the formatted string. See iTermKeystrokeFormatter.
@property (nonatomic) int virtualKeyCode;
@property (nonatomic) NSEventModifierFlags modifierFlags;
@property (nonatomic) unsigned int character;
@property (nonatomic, readonly) UTF32Char modifiedCharacter;
@property (nonatomic, readonly) NSString *serialized;
@property (nonatomic, readonly) BOOL touchbar;
@property (nonatomic, readonly) BOOL isValid;

+ (instancetype)backspace;
+ (instancetype)withEvent:(NSEvent *)event;
+ (instancetype)withCharacter:(unichar)character
                modifierFlags:(NSEventModifierFlags)modifierFlags;
+ (instancetype)withTmuxKey:(NSString *)key;

- (instancetype)initWithSerialized:(NSString *)serialized;
- (instancetype)initWithVirtualKeyCode:(int)virtualKeyCode
                            hasKeyCode:(BOOL)hasKeyCode
                         modifierFlags:(NSEventModifierFlags)modifierFlags
                             character:(unsigned int)character
                     modifiedCharacter:(UTF32Char)modifiedCharacter NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSString * _Nullable)keyInBindingDictionary:(NSDictionary<NSString *, NSDictionary *> *)dict;
- (NSDictionary * _Nullable)valueInBindingDictionary:(NSDictionary<NSString *, NSDictionary *> *)dict;
- (iTermKeystroke *)keystrokeWithoutVirtualKeyCode;

@end

@interface iTermTouchbarItem: NSObject<NSCopying>
@property (nonatomic, readonly) NSString *identifier;

- (instancetype)initWithIdentifier:(NSString *)identifier NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (nullable NSString *)keyInDictionary:(NSDictionary *)dict;

@end

@interface NSDictionary(Keystrokes)
- (NSDictionary<iTermKeystroke *, id> *)it_withDeserializedKeystrokeKeys;
- (NSDictionary *)it_withSerializedKeystrokeKeys;

// self and other should have serialized keystroke keys. Result will have serialized keystroke keys.
- (NSDictionary *)it_dictionaryByMergingSerializedKeystrokeKeyedDictionary:(NSDictionary *)other;
@end

@interface NSString(iTermKeystroke)
- (NSComparisonResult)compareSerializedKeystroke:(NSString *)other;
@end

typedef iTermOr<iTermKeystroke *, iTermTouchbarItem *> iTermKeystrokeOrTouchbarItem;

NS_ASSUME_NONNULL_END
