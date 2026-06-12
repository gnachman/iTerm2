//
//  iTermThreadSafety.h
//  iTerm2
//
//  Created by George Nachman on 3/14/20.
//
// The purpose of these classes is to make it possible to write multi-threaded
// code that documents which thread each method is supposed to be called on.
// They also provide automatic checks that these rules are followed.
//
// Usage
// -----
//
// @class MyState;
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
//     _thread = [iTermThread withLabel:@"com.example"
//                         stateFactory:^MyState*(void) { return [[MyState alloc] init]; }];
//   }
//   return self;
// }
//
// - (void)incrementWithCallback:(iTermCallback<id, NSNumber *> *)callback {
//   [_thread dispatchAsync:^(MyState *state) {
//     [self reallyIncrementWithState:state];
//     [callback invokeWithObject:state.count];
//   }];
// }
//
// // The fact that this takes a MyState argument means that it must be called
// // on self.thread or else crash.
// - (void)reallyIncrementWithState:(MyState *)state {
//     state.count = @(state.count.integerValue + 1);
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
//   NSLog(@"%@", value);
// }];


#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermThreadChecker;

// This object is magic. If you retain it on a thread it's not allowed to be
// used on, it will crash immediately. T is the type that it holds. Typically,
// you'd subclass this and set T to the subclass:
//
// @class MyState;
// @interface MyState: iTermSynchronizedState<MyState *>
// @property (nonatomic, strong) id myValue;
/// @end
@interface iTermSynchronizedState<T>: NSObject
@property (atomic, readonly) T state;
@property (atomic, weak, readonly) dispatch_queue_t queue;

- (instancetype)initWithQueue:(dispatch_queue_t)queue NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)check;
@end

@class iTermMainThreadState;
@interface iTermMainThreadState: iTermSynchronizedState<iTermMainThreadState *>
+ (instancetype)sharedInstance;
@end

@class iTermThread;

// Combines a block and an iTermThread to run it on.
@interface iTermCallback<__contravariant CallerState, __covariant ObjectType>: NSObject
@property (nonatomic, readonly) iTermThread *thread;
#if DEBUG
@property (atomic) BOOL trace;
#endif

+ (instancetype)onThread:(iTermThread *)thread block:(void (^)(CallerState state, ObjectType _Nullable result))block;
- (void)invokeWithObject:(ObjectType _Nullable)object;
- (void)invokeMaybeImmediatelyWithObject:(ObjectType _Nullable)object;
- (void)waitUntilInvoked;
- (void)addDebugInfo:(NSString *)debugInfo;

@end

// 1:1 with a dispatch queue and an instance of (typically a subclass of)
// iTermSynchronizedState.
@interface iTermThread<T>: NSObject
@property (nonatomic, readonly) dispatch_queue_t queue;

// I had to add this typedef because otherwise the compiler gives me a bogus warning about the
// implementation's block not returning iTermSynchronizedState<T> 🙄
typedef iTermSynchronizedState<T> * _Nonnull (^iTermThreadStateFactoryBlockType)(dispatch_queue_t queue);

#if BETA
+ (iTermThread * _Nullable)currentThread;
#endif
+ (NSString *)uniqueQueueLabelWithName:(NSString *)label;

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
// Won't deadlock if already on the thread.
- (void)dispatchRecursiveSync:(void (^ NS_NOESCAPE)(id))block;

- (iTermCallback<T, id> *)newCallbackWithBlock:(void (^)(id state, id _Nullable value))callback;

// Will call [target selectorWithState:state value:value userInfo:userInfo];
// Does not retain target.
- (iTermCallback<T, id> *)newCallbackWithWeakTarget:(id)target selector:(SEL)selector userInfo:(id _Nullable)userInfo;
- (void)performDeferredBlocksAfter:(void (^ NS_NOESCAPE)(void))block;

@end

// Asserts that it's on the expected thread.
@interface iTermThreadChecker: NSObject

- (instancetype)initWithThread:(iTermThread *)thread NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)check;

@end

NS_ASSUME_NONNULL_END
