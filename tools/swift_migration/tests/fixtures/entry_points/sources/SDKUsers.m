#import <Cocoa/Cocoa.h>
#import "Widget.h"

// Methods only the system calls, which no send in the repository names.

// An informal combo box delegate: iTermPickerOwner, another class, makes it
// the delegate.
@interface iTermPicker : NSViewController
@end

@implementation iTermPicker
- (void)comboBoxSelectionDidChange:(NSNotification *)notification {
}
- (void)unusedPickerMethod {
}
@end

@interface iTermPickerOwner : NSObject
@end

@implementation iTermPickerOwner
- (void)attachBox:(NSComboBox *)box picker:(iTermPicker *)picker {
    box.delegate = (id)picker;
}
@end

// A services method (NSServicesMenuRequestor), not formally adopted.
@interface iTermReader : NSView
@end

@implementation iTermReader
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard {
    return NO;
}
@end

// An action NSWindow declares, implemented by a window controller: the
// Window menu sends it through the responder chain.
@interface iTermTabsController : NSWindowController
@end

@implementation iTermTabsController
- (IBAction)selectNextTab:(id)sender {
}
@end

// A delegate wired in a xib (sources/Picker.xib) to a combo box.
@interface iTermXibComboOwner : NSObject
@end

@implementation iTermXibComboOwner
- (void)comboBoxWillWobble:(NSNotification *)notification {
}
- (NSString *)wobbleKey {
    return nil;
}
@end

// Scripting: the sdef's window class is iTermScriptingWindow, which forwards
// every message it does not implement to the window it wraps.
@protocol PTYWindow <NSObject>
- (void)smartLayout;
@end

@interface iTermScriptingWindow : NSObject
@end

@implementation iTermScriptingWindow {
    NSWindow *_underlyingWindow;
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [_underlyingWindow methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    [invocation invokeWithTarget:_underlyingWindow];
}
@end

@interface iTermWindow : NSWindow <PTYWindow>
@end

@implementation iTermWindow
- (void)smartLayout {
}
- (BOOL)scriptFrontmost {
    return NO;
}
- (id)handleSelectCommand:(NSScriptCommand *)command {
    return nil;
}
@end

@interface iTermCompactPanel : NSPanel <PTYWindow>
@end

@implementation iTermCompactPanel
- (void)smartLayout {
}
- (BOOL)scriptFrontmost {
    return NO;
}
@end

@implementation iTermProbe
- (void)ownerPing {
}
- (void)wobble {
}
- (void)swiftInactiveOnly {
}
- (void)objcInactiveOnly {
}
- (void)uncapturedOnly {
}
- (void)probeNeverCalled {
}
- (void)setFiles:(NSArray *)files {
}
@end

void iTermProbeInactive(iTermProbe *p) {
#if 0
    [p objcInactiveOnly];
#endif
}

// Overrides of private framework methods: the SDK headers do not declare
// them; the frameworks implement them at run time (the fixture runtime list,
// fixtures/entry_points_runtime/runtime_methods.tsv).
@interface iTermScroller : NSScrollView
@end

@implementation iTermScroller
- (NSUInteger)allowedPocketEdges {
    return 0;
}
@end

// Through a repository superclass (iTermWindow) to NSWindow, whose ancestor
// NSResponder implements the method in the fixture runtime list.
@interface iTermFancyWindow : iTermWindow
@end

@implementation iTermFancyWindow
- (BOOL)_usesCustomDrawing {
    return NO;
}
@end

// An NSObject subclass: an ordinary unused method, and one whose selector
// begins with an underscore.
@interface iTermPlainObject : NSObject
@end

@implementation iTermPlainObject
- (void)plainUnusedMethod {
}
- (void)_underscoredUnusedMethod {
}
@end

// A class whose @interface only a macro writes: no text match names its
// superclass.
#define ITERM_DECLARE_CLASS(NAME, SUPER) @interface NAME : SUPER @end
ITERM_DECLARE_CLASS(iTermMacroDeclared, NSObject)

@implementation iTermMacroDeclared
- (void)macroDeclaredUnusedMethod {
}
@end

// A category on an SDK class that only declares private API: nothing in the
// repository defines it.
@interface NSWindow (iTermFixturePrivate)
- (void)_setFixtureContentHasShadow:(BOOL)flag;
@end

// A candidate of a class whose framework ancestor (NSWindowController) the
// fixture runtime list does not have.
@implementation iTermTabsController (Unused)
- (void)tabsUnusedMethod {
}
@end

// Categories on framework classes. In the fixture runtime list NSView itself,
// its ancestor NSResponder, its framework subclass NSScrollView (an instance
// method and a class method) and an unrelated framework class each implement
// one of these selectors; one selector no framework class implements.
@implementation NSView (iTermFixtureCategory)
- (void)fixtureOwnHook {
}
- (void)fixtureAncestorHook {
}
- (void)fixtureSubclassHook {
}
- (void)fixtureClassKindHook {
}
- (void)fixtureInformalSelector {
}
- (void)fixtureNowhereView {
}
@end

// A category on the root class: an instance method of the root class also
// answers class messages sent to any class.
@implementation NSObject (iTermFixtureCategory)
- (void)fixtureRootHook {
}
- (void)fixtureRootUnused {
}
@end
