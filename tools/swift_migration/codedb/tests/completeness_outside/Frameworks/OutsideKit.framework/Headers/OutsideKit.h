// Fixture: a framework outside the repository, imported as a module
// (test_codedb_completeness.py, SdkTablesTest).
#define IBAction void
typedef signed char BOOL;
__attribute__((objc_root_class))
@interface OKObject
- (instancetype)init;
+ (instancetype)new;
@end
@protocol OKBase
- (void)baseMethod;
@end
@protocol OKDelegate <OKBase>
- (void)requiredCallback:(id)sender;
@optional
- (void)optionalCallback:(id)sender;
@property (readonly) int optionalValue;
@end
@interface OKWindow : OKObject <OKDelegate>
@property (readonly) BOOL canBecomeMain;
@property (nonatomic, getter=isVisible, setter=setShown:) BOOL visible;
@property (class, readonly) OKWindow *shared;
- (IBAction)selectNext:(id)sender;
- (void)plain;
@end
@interface OKWindow (OKExtras) <OKBase>
- (void)extra;
#if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ >= 150000
- (void)newInFifteen;
#endif
@end
