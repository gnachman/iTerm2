//
//  iTermStatusBarComponentKnob.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import <Cocoa/Cocoa.h>

// Do not reorder or delete
typedef NS_ENUM(NSUInteger, iTermStatusBarComponentKnobType) {
    iTermStatusBarComponentKnobTypeCheckbox,
    iTermStatusBarComponentKnobTypeText,
    iTermStatusBarComponentKnobTypeDouble,
    iTermStatusBarComponentKnobTypeColor,
    iTermStatusBarComponentKnobTypeAction,
    iTermStatusBarComponentKnobTypeInvocation  // Text but suggests function calls
};

NS_ASSUME_NONNULL_BEGIN

@protocol iTermStatusBarKnobViewController<NSObject>
- (id)value;
- (void)setValue:(id)value;
- (void)setDescription:(NSString *)description placeholder:(NSString *)placeholder;
- (CGFloat)controlOffset;
- (void)sizeToFit;
@end

// Describes a configurable property of a status bar component.
@interface iTermStatusBarComponentKnob : NSObject

@property (nonatomic, readonly, nullable) NSString *labelText;
@property (nonatomic, readonly) iTermStatusBarComponentKnobType type;
@property (nonatomic, readonly, nullable) NSString *placeholder;
@property (nonatomic, readonly, nullable) NSString *stringValue;  // aliases `value`
@property (nonatomic, readonly, nullable) NSNumber *numberValue;  // aliases `value`
@property (nonatomic, readonly) NSString *key;
@property (nonatomic, strong, nullable) id value;

- (instancetype)initWithLabelText:(nullable NSString *)labelText
                             type:(iTermStatusBarComponentKnobType)type
                      placeholder:(nullable NSString *)placeholder
                     defaultValue:(nullable id)defaultValue
                              key:(NSString *)key NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
