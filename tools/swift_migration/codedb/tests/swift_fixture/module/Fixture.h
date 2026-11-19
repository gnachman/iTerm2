// Objective-C declarations that the Swift fixture module calls. Compiled only
// by the code database's Swift tests (test_codedb_swift.py).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FXDelegate <NSObject>
- (void)requiredThing:(NSString *)text;
@optional
- (void)fixtureDidChange:(id)sender;
- (NSInteger)optionalCount;
@end

@interface FXWidget : NSObject
@property (nonatomic) NSInteger count;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, readonly) NSInteger readOnlyValue;
@property (nonatomic, weak, nullable) id<FXDelegate> delegate;
@property (class, nonatomic) NSInteger sharedCount;
@property (nonatomic) NSRect frame;
@property (nonatomic, copy, nullable) void (NS_SWIFT_SENDABLE ^sendableHandler)(void);
@property (nonatomic, readonly) FXWidget *peer;
@property (nonatomic, copy) NSArray<NSString *> *names;

- (instancetype)initWithName:(NSString *)name;
- (instancetype)initWithName:(NSString *)name count:(NSInteger)count;
- (void)takeFocus;
- (void)doThing:(NSInteger)a with:(NSInteger)b;
- (void)drawRect:(NSRect)rect;
- (BOOL)saveToPath:(NSString *)path error:(NSError **)error;
- (void)fetchValueWithCompletion:(void (^)(NSInteger value))completion;
- (void)removeItemsAtIndexes:(NSIndexSet *)indexes;
- (void)oldName:(NSInteger)x NS_SWIFT_NAME(newName(x:));
- (void)performWithBlock:(void (^)(void))block;
+ (void)classMethodWithValue:(NSInteger)value;
+ (FXWidget *)sharedWidget;
@property (nonatomic, strong, nullable) FXWidget *sibling;
@property (nonatomic, readonly) NSRect *rectPointer;
@end

NS_ASSUME_NONNULL_END
