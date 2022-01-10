//
//  iTermPromise.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/10/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermOr<T,U>: NSObject
@property (nonatomic, readonly) BOOL hasFirst;
@property (nonatomic, readonly) BOOL hasSecond;

+ (instancetype)first:(T)object;
+ (instancetype)second:(U)object;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (void)whenFirst:(void (^ NS_NOESCAPE _Nullable)(T object))firstBlock
           second:(void (^ NS_NOESCAPE _Nullable)(U object))secondBlock;

@end

@protocol iTermPromiseSeal<NSObject>
- (void)fulfill:(id)value;
- (void)reject:(NSError *)error;
- (void)rejectWithDefaultError;
@end

@interface iTermPromise<T> : NSObject

@property(nonatomic, readonly) BOOL hasValue;
@property(nonatomic, nullable, readonly) T maybeValue;

+ (instancetype)promise:(void (^ NS_NOESCAPE)(id<iTermPromiseSeal> seal))block;
// Nil gives default error
+ (instancetype)promiseValue:(T _Nullable)value;
+ (instancetype)promiseDefaultError;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (iTermPromise<T> *)then:(void (^)(T value))block;
- (iTermPromise<T> *)catchError:(void (^)(NSError *error))block;

@end

NS_ASSUME_NONNULL_END
