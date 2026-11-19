#import <Cocoa/Cocoa.h>

@protocol iTermWidgetDelegate <NSObject>
@optional
- (void)widgetDidChange:(id)widget;
@end

@interface iTermWidget : NSView <NSWindowDelegate>
@property (nonatomic, copy) NSString *fooBar;
@property (nonatomic, strong) IBOutlet NSButton *button;
- (IBAction)biggerFont:(id)sender;
- (void)go;
- (void)timerFired:(NSTimer *)timer;
- (void)noteChanged:(NSNotification *)note;
- (void)performedOnly;
- (void)stringPerformed;
- (void)macroCalled;
- (void)neverCalled;
- (void)contextMenuActionOpen:(id)sender;
- (void)swiftOnlyCalled NS_SWIFT_NAME(renamed());
- (void)openThing:(NSPasteboard *)pboard userData:(NSString *)data error:(NSString **)error;
@end

@interface iTermSubWidget : iTermWidget
@end

@interface iTermThingMO : NSObject
@end

@interface iTermWidget (Declared)
- (void)declaredOnly;
@end

static inline void WidgetInline(iTermWidget *w) {
    [w stringPerformed];
}

// Probes of the method table: a protocol property that Swift reads and
// writes through the protocol, a protocol method that Swift calls through
// the protocol (iTermProbe implements both without adopting the protocol),
// a method that witnesses a Swift protocol requirement, and methods named
// only in code that is not compiled.
@protocol iTermPanelOwnerProtocol <NSObject>
@property (nonatomic, retain, nullable) id panelDelegate;
- (void)ownerPing;
@end

@interface iTermProbe : NSObject
@property (nonatomic, retain, nullable) id panelDelegate;
- (void)ownerPing;
- (void)wobble;
- (void)swiftInactiveOnly;
- (void)objcInactiveOnly;
- (void)uncapturedOnly;
- (void)probeNeverCalled;
- (void)setFiles:(NSArray *)files;
@end
