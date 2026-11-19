#import <Foundation/Foundation.h>

@class Bar;

typedef NS_ENUM(NSInteger, FooMode) {
    FooModeA,
    FooModeB
};

typedef enum {
    kPlainA,
    kPlainB
} FooPlainEnum;

typedef struct {
    int x;
    int y;
} FooPoint;

typedef struct {
    id object;
    int count;
} FooStrongStruct;

@interface Foo : NSObject <NSCoding> {
    @public
    int _publicCounter;
}

@property (nonatomic, copy) NSString *name;
@property (nonatomic) NSInteger plain;
@property (atomic) NSInteger atomicValue;
@property (nonatomic, readonly) int doubled;
@property (nonatomic, strong) Bar *bar;
@property (nonatomic, retain) NSString *retained;

@end
