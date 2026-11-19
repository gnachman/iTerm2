// The bridging header of the swift_interface.py test fixture module (SIF).
// Objective-C declarations whose import into Swift test_swift_interface.py
// checks: names, optionality from nullability, throws and async forms,
// NS_SWIFT_NAME, NS_REFINED_FOR_SWIFT and NS_SWIFT_UNAVAILABLE.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SIFObjCThing : NSObject
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy) NSString *name;
- (instancetype)initWithName:(NSString *)name;
- (BOOL)saveToPath:(NSString *)path error:(NSError **)error;
// Imported as load(from:error:) throws: without error: it would collide
// with load(from:).
- (BOOL)loadFrom:(NSString *)path;
- (BOOL)loadFrom:(NSString *)path error:(NSError **)error;
- (void)fetchValueWithCompletion:(void (^)(NSInteger value))completion;
- (void)oldName:(NSInteger)x NS_SWIFT_NAME(newName(x:));
- (NSInteger)refinedValue NS_REFINED_FOR_SWIFT;
- (void)hiddenFromSwift NS_SWIFT_UNAVAILABLE("use something else");
@end

@interface NSString (SIFAdditions)
- (NSString *)sif_reversed;
@end

typedef NS_ENUM(NSInteger, SIFColor) {
    SIFColorRed,
    SIFColorGreen NS_SWIFT_NAME(verde),
};

NSInteger SIFAddNumbers(NSInteger a, NSInteger b) NS_SWIFT_NAME(addNumbers(_:_:));
NSString * _Nullable SIFMaybeString(void);

NS_ASSUME_NONNULL_END

@interface SIFUnannotated : NSObject
- (NSString *)describe:(NSString *)thing;
@end
