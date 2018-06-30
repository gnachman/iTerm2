//
//  iTermStatusBarComponentKnob.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import <Cocoa/Cocoa.h>

// Do not reorder or delete
typedef NS_ENUM(NSUInteger, iTermStatusBarComponentKnobType) {
    iTermStatusBarComponentKnobTypeText,
    iTermStatusBarComponentKnobTypeDouble,
};

NS_ASSUME_NONNULL_BEGIN

// Describes a configurable property of a status bar component.
@interface iTermStatusBarComponentKnob : NSObject

@property (nonatomic, readonly, nullable) NSString *labelText;
@property (nonatomic, readonly) iTermStatusBarComponentKnobType type;
@property (nonatomic, readonly, nullable) NSString *placeholder;
@property (nonatomic, readonly, nullable) id value;
@property (nonatomic, readonly, nullable) NSString *stringValue;  // aliases `value`
@property (nonatomic, readonly, nullable) NSNumber *numberValue;  // aliases `value`
@property (nonatomic, readonly) NSView *inputView;
@property (nonatomic, readonly) NSString *key;

- (instancetype)initWithLabelText:(nullable NSString *)labelText
                             type:(iTermStatusBarComponentKnobType)type
                      placeholder:(nullable NSString *)placeholder
                     defaultValue:(nullable id)defaultValue
                              key:(NSString *)key NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

// Gives a text field
@interface iTermStatusBarComponentKnobText : iTermStatusBarComponentKnob
@end

extern NSString *const iTermStatusBarComponentKnobMinimumWidthKey;

// Gives a draggable width-setting control.
@interface iTermStatusBarComponentKnobMinimumWidth : iTermStatusBarComponentKnob
@end

NS_ASSUME_NONNULL_END
