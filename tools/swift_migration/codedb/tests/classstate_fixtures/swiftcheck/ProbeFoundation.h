// Fixture: the cases of SwiftcAgreementTest that need the SDK (generics,
// CF and system types). See Probe.h.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <os/lock.h>
#import <os/log.h>
#import <objc/runtime.h>
#import <simd/simd.h>
#import <stdarg.h>
typedef struct { char buf[8]; int n; } ArrayStruct;
typedef struct { long double ld; } LongDoubleStruct;
typedef struct { __strong id obj; } StrongStruct;
typedef struct { StrongStruct *p; } PointerToStrongStruct;
typedef struct { ArrayStruct inner; } NestedArrayStruct;
typedef struct { union { int a[2]; float f; } u; } UnionArrayStruct;
typedef void (^MutableArrayBlock)(NSMutableArray<NSString *> *);
typedef void (*MutableArrayFunction)(NSMutableArray<NSString *> *);
@protocol FProto <NSObject>
@end
@class FForward;
@protocol FForwardProto;
@interface FGen<T> : NSObject
@end
@interface FProbe : NSView
@property (nonatomic, strong) NSArray<NSString *> *strArr;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutArr;
@property (nonatomic, strong) NSArray<NSMutableArray<NSString *> *> *nestedArr;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSString *> *> *dictOfArr;
@property (nonatomic, strong) FGen<NSString *> *generic;
@property (nonatomic, strong) __kindof NSObject *kindof;
@property (nonatomic, strong) id<NSCopying> protoObj;
@property (nonatomic) CFTypeRef cfType;
@property (nonatomic) va_list vaList;
@property (nonatomic) __unsafe_unretained id *unretIdPtr;
@property (nonatomic) os_unfair_lock unfair;
@property (nonatomic) ArrayStruct arrS;
@property (nonatomic) simd_half4 h4;
@property (nonatomic, copy) void (^variadicBlock)(int, ...);
@property (nonatomic) LongDoubleStruct ldFieldS;
@property (nonatomic) PointerToStrongStruct ptrToStrongS;
@property (nonatomic, copy) void (^mutArrBlock)(NSMutableArray<NSString *> *);
@property (nonatomic, copy) MutableArrayBlock mutArrBlockTypedef;
@property (nonatomic) MutableArrayFunction mutArrFunction;
@property (nonatomic, copy) void (^genericBlock)(FGen<NSString *> *);
@property (nonatomic, copy) void (^kindofBlock)(__kindof NSView *);
@property (nonatomic) NSMutableArray<NSString *> * __autoreleasing *mutArrPtr;
@property (nonatomic, strong) NSObject<FProto> *nsobjectProto;
@property (nonatomic, strong) NSSet<id<FProto>> *protoSet;
@property (nonatomic, strong) NSDictionary<id<FProto>, NSString *> *protoKeyDict;
@property (nonatomic) int (*arrayPointer)[4];
@property (nonatomic) ArrayStruct *arrayStructPointer;
@property (nonatomic) NestedArrayStruct nested2;
@property (nonatomic) UnionArrayStruct unionArr;
@property (nonatomic) IMP imp;
@property (nonatomic) char *mcstr;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) dispatch_group_t group;
@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@property (nonatomic, strong) dispatch_source_t source;
@property (nonatomic, strong) dispatch_io_t io;
@property (nonatomic, strong) os_log_t log;
@property (nonatomic, strong) FForward *forwardClass;
@property (nonatomic, strong) id<FForwardProto> forwardProto;
@end
@interface FDeep : FProbe
@end
