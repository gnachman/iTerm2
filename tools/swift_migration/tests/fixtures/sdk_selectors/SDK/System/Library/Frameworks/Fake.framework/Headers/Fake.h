// A fixture header in the shapes of the SDK's headers.
#import <Foundation/Foundation.h>
#if TARGET_OS_OSX
#define FAKE_MACRO(x) \
    x
#endif

NS_ASSUME_NONNULL_BEGIN

@class FKView, FKWindow;
@protocol FKForward;
@protocol FKOther, FKThird;

API_AVAILABLE(macos(10.10))
@interface FKWindow<__covariant ObjectType> : NSObject <NSCoding> {
    id _ivar;
}
- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSUInteger)style
                            backing:(NSInteger)backingStoreType
                              defer:(BOOL)flag NS_DESIGNATED_INITIALIZER;
- (IBAction)selectNextTab:(nullable id)sender API_AVAILABLE(macos(10.12));
+ (nullable FKWindow *)windowWithNumber:(NSInteger)n;
- (void)performBlock:(void (^)(BOOL finished, NSError * _Nullable error))block;
- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (BOOL)unlabeled:(id)a :(id)b;
/* - (void)commentedOut; */
// - (void)alsoCommentedOut;
@property (readonly) BOOL canBecomeMainWindow;
@property (getter=isVisible, readonly) BOOL visible;
@property (nullable, copy) NSString *title NS_SWIFT_NAME(windowTitle);
@property (setter=setTheFrame:) NSRect frame API_DEPRECATED("use bounds", macos(10.0, 10.15));
@property (class, readonly, strong) FKWindow *sharedWindow;
@property (nullable, copy) void (^handler)(NSError * _Nullable error);
@property NSInteger first, second;
@property NSInteger ID;
@end

@interface FKWindow (FKTabbing)
- (void)mergeAllWindows:(nullable id)sender;
@end

@interface FKView ()
- (void)extensionMethod;
@end

@protocol FKWindowDelegate <NSObject>
- (void)windowRequired:(FKWindow *)window;
@optional
- (void)windowDidResize:(NSNotification *)notification;
- (BOOL)tableView:(id)tableView
    shouldSelectRow:(NSInteger)row;
@property (readonly) NSString *delegateName;
@required
- (void)windowAlsoRequired;
@end

static inline void FKInline(void) {
    - (void)notAMethod;
}

NS_ASSUME_NONNULL_END
