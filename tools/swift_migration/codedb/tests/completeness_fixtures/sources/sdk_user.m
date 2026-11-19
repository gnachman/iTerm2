// Fixture: imports modules outside the repository
// (test_codedb_completeness.py, SdkTablesTest).
@import OutsideKit;
@import plainlib;
@interface MyWindow : OKWindow <OKDelegate>
@end
@implementation MyWindow
- (void)requiredCallback:(id)sender {
}
- (void)baseMethod {
}
@end
