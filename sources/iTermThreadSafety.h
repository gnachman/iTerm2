//
//  iTermThreadSafety.h
//  iTerm2
//
//  Created by George Nachman on 3/14/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermThreadChecker;

// This object is magic. If you retain it on a thread it's not allowed to be used on, it will crash
// immediately.
@interface iTermSynchronizedState<T>: NSObject
@property (atomic, readonly) T state;

- (instancetype)initWithQueue:(dispatch_queue_t)queue NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)check;
@end

@class iTermMainThreadState;
@interface iTermMainThreadState: iTermSynchronizedState<iTermMainThreadState *>
+ (instancetype)sharedInstance;
@end

@class iTermThread;

@interface iTermCallback<__contravariant CallerState, __covariant ObjectType>: NSObject
@property (nonatomic, readonly) iTermThread *thread;

+ (instancetype)onThread:(iTermThread *)thread block:(void (^)(CallerState state, ObjectType _Nullable result))block;
- (void)invokeWithObject:(ObjectType _Nullable)object;
- (void)waitUntilInvoked;

@end

// Usage
//
// @interface MyState: iTermSynchronizedState<MyState *>
// @property (nonatomic, strong) NSNumber *count;
// @end
//
// @implementation MyClass {
//   iTermThread<MyState *> *_thread;
// }
//
// - (instancetype)init {
//   self = [super init];
//   if (self) {
//     MyState *state = [[MyState alloc] init];
//     _thread = [iTermThread withLabel:@"com.example" state:state];
//   }
//   return self;
// }
//
// - (void)incrementWithCallback:(iTermCallback<id, NSNumber *> *)callback {
//   [_thread dispatchAsync:^(MyState *state) {
//     state.count = @(state.count.integerValue + 1);
//     [callback invokeWithObject:state.count];
//   }];
// }
//
// - (NSInteger)count {
//   __block NSNumber *result;
//   [_thread dispatchSync:^(MyState *state) {
//     result = state.count;
//   }];
//   return result;
// }
//
// // Call site
// [myObject incrementWithCallback:[_otherThread newCallbackWithBlock:^(OtherState *state, NSNumber *value) {
//   // This is called on _otherThread
// }];

@interface iTermThread<T>: NSObject
@property (nonatomic, readonly) dispatch_queue_t queue;

// I had to add this typedef because otherwise the compiler gives me a bogus warning about the
// implementation's block not returning iTermSynchronizedState<T> 🙄
typedef iTermSynchronizedState<T> * _Nonnull (^iTermThreadStateFactoryBlockType)(dispatch_queue_t queue);

+ (iTermThread<iTermMainThreadState *> *)main;
+ (instancetype)withLabel:(NSString *)label
             stateFactory:(iTermThreadStateFactoryBlockType)stateFactory;

- (instancetype)initWithLabel:(NSString *)label
                 stateFactory:(iTermThreadStateFactoryBlockType)stateFactory;

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                 stateFactory:(iTermThreadStateFactoryBlockType)stateFactory NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)dispatchAsync:(void (^)(T _Nullable state))block;
- (void)dispatchSync:(void (^ NS_NOESCAPE)(T _Nullable state))block;
- (void)dispatchRecursiveSync:(void (^ NS_NOESCAPE)(id))block;

- (iTermCallback<T, id> *)newCallbackWithBlock:(void (^)(id state, id _Nullable value))callback;

// Will call [target selectorWithState:state value:value userInfo:userInfo];
// Does not retain target.
- (iTermCallback<T, id> *)newCallbackWithWeakTarget:(id)target selector:(SEL)selector userInfo:(id _Nullable)userInfo;

@end

@interface iTermThreadChecker: NSObject

- (instancetype)initWithThread:(iTermThread *)thread NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)check;

@end

NS_ASSUME_NONNULL_END
