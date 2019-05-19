//
//  iTermReflection.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/18/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermReflectionMethodArgumentType) {
    iTermReflectionMethodArgumentTypeObject,
    iTermReflectionMethodArgumentTypeClass,
    iTermReflectionMethodArgumentTypeScalar,
    iTermReflectionMethodArgumentTypeVoid,
    iTermReflectionMethodArgumentTypePointer,
    iTermReflectionMethodArgumentTypeSelector,
    iTermReflectionMethodArgumentTypeStruct,
    iTermReflectionMethodArgumentTypeUnion,
    iTermReflectionMethodArgumentTypeBitField,
    iTermReflectionMethodArgumentTypeArray,
    iTermReflectionMethodArgumentTypeBlock,
    iTermReflectionMethodArgumentTypeUnknown
};

@interface iTermReflectionMethodArgument : NSObject

@property (nonatomic, readonly) NSString *argumentName;
@property (nonatomic, readonly) iTermReflectionMethodArgumentType type;
@property (nonatomic, readonly) NSString *className;  // Only for type of .object

@end

@interface iTermReflection : NSObject

@property (nonatomic, readonly) NSArray<iTermReflectionMethodArgument *> *arguments;

- (instancetype)initWithClass:(Class)theClass
                     selector:(SEL)selector NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
