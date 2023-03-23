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

@property (nonatomic, readonly) T _Nullable maybeFirst;
@property (nonatomic, readonly) U _Nullable maybeSecond;

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
@property(nonatomic, nullable, readonly) NSError *maybeError;

+ (instancetype)promise:(void (^ NS_NOESCAPE)(id<iTermPromiseSeal> seal))block;
// Nil gives default error
+ (instancetype)promiseValue:(T _Nullable)value;
+ (instancetype)promiseDefaultError;
+ (void)gather:(NSArray<iTermPromise<T> *> *)promises
         queue:(dispatch_queue_t)queue
    completion:(void (^)(NSArray<iTermOr<T, NSError *> *> *values))completion;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (iTermPromise<T> *)then:(void (^)(T value))block;
- (iTermPromise<T> *)catchError:(void (^)(NSError *error))block;


- (iTermPromise<T> *)onQueue:(dispatch_queue_t)queue then:(void (^)(T value))block;
- (iTermPromise<T> *)onQueue:(dispatch_queue_t)queue catchError:(void (^)(NSError *error))block;

- (iTermOr<T, NSError *> *)wait;

@end

@interface iTermRenegablePromise<T>: iTermPromise<T>
@property (nonatomic, readonly, copy) void (^renegeBlock)(void);

+ (instancetype)promise:(void (^ NS_NOESCAPE)(id<iTermPromiseSeal> seal))block NS_UNAVAILABLE;
+ (instancetype)promise:(void (^ NS_NOESCAPE)(id<iTermPromiseSeal> seal))block
                renege:(void (^)(void))renege;

- (void)renege;

@end


NS_ASSUME_NONNULL_END
