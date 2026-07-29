//
//  RevealHotKeyWindowTabSelectionTests.m
//  ModernTests
//
//  Regression coverage for Issue 12902: clicking a notification posted
//  by a background tab of a dedicated hotkey window brought the hotkey
//  window forward but left the previously-selected tab in front instead
//  of selecting the source tab and pane.
//
//  Root cause: -[PTYSession reveal] guarded its
//  -sessionSelectContainingTab call with `if (!isHotKey)`, so the source
//  tab was never selected for hotkey windows.
//
//  This test drives the real -reveal against a mock delegate whose
//  parent window reports itself as a hotkey window, and asserts that
//  -sessionSelectContainingTab is invoked. Reintroducing the bug at the
//  call site (re-adding `if (!isHotKey)`) makes this test fail.
//

#import <XCTest/XCTest.h>

#import <objc/runtime.h>

#import "PTYSession.h"
#import "WindowControllerInterface.h"

#pragma mark - Permissive forwarding base

// -reveal and especially -[PTYSession setDelegate:] send a fair number
// of the (large) PTYSessionDelegate / iTermWindowController protocols to
// the delegate and its parent window. Rather than stub each method, this
// base no-ops (zero/nil return) any selector declared by a configured
// protocol (recursing into incorporated protocols) so that subclasses
// only have to implement the handful of methods they actually care
// about. Type encodings come from the protocol, so forwarded invocation
// signatures are correct.
@interface RevPermissiveMock : NSObject
@end

static struct objc_method_description RevFindMethodDescription(Protocol *proto, SEL sel) {
    struct objc_method_description empty = {NULL, NULL};
    if (proto == NULL) {
        return empty;
    }
    // Required, then optional, instance methods declared directly.
    struct objc_method_description d = protocol_getMethodDescription(proto, sel, YES, YES);
    if (d.name != NULL) {
        return d;
    }
    d = protocol_getMethodDescription(proto, sel, NO, YES);
    if (d.name != NULL) {
        return d;
    }
    // Recurse into incorporated protocols (e.g. iTermWindowController
    // adopts WindowControllerInterface, which is where -number lives).
    unsigned int count = 0;
    Protocol * __unsafe_unretained *list = protocol_copyProtocolList(proto, &count);
    for (unsigned int i = 0; i < count; i++) {
        d = RevFindMethodDescription(list[i], sel);
        if (d.name != NULL) {
            break;
        }
    }
    free(list);
    return d;
}

@implementation RevPermissiveMock

// Subclasses return the protocol whose methods should be no-op forwarded.
+ (Protocol *)rev_mockProtocol {
    return nil;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([super respondsToSelector:aSelector]) {
        return YES;
    }
    return RevFindMethodDescription([[self class] rev_mockProtocol], aSelector).name != NULL;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *sig = [super methodSignatureForSelector:aSelector];
    if (sig != nil) {
        return sig;
    }
    struct objc_method_description d =
        RevFindMethodDescription([[self class] rev_mockProtocol], aSelector);
    if (d.types != NULL) {
        return [NSMethodSignature signatureWithObjCTypes:d.types];
    }
    return nil;
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    // No-op: leave a zeroed (nil/0/NO) return value.
    NSUInteger length = invocation.methodSignature.methodReturnLength;
    if (length > 0) {
        void *buffer = calloc(1, length);
        [invocation setReturnValue:buffer];
        free(buffer);
    }
}

@end

#pragma mark - Mocks

// Stands in for the window controller -reveal asks about. The only thing
// the test pins is that it is a hotkey window; everything else is no-op
// forwarded.
@interface RevealMockHotKeyTerminal : RevPermissiveMock
@end

@implementation RevealMockHotKeyTerminal
+ (Protocol *)rev_mockProtocol {
    return @protocol(iTermWindowController);
}
- (BOOL)isHotKeyWindow {
    return YES;
}
@end

// Records the delegate calls -reveal makes after bringing the window
// forward.
@interface RevealMockSessionDelegate : RevPermissiveMock
@property (nonatomic, strong) id parentWindow;
@property (nonatomic, assign) BOOL didSelectContainingTab;
@property (nonatomic, weak) PTYSession *activatedSession;
@end

@implementation RevealMockSessionDelegate
+ (Protocol *)rev_mockProtocol {
    return @protocol(PTYSessionDelegate);
}
- (id)realParentWindow {
    return self.parentWindow;
}
- (void)setActiveSessionPreservingMaximization:(PTYSession *)session {
    self.activatedSession = session;
}
- (void)sessionSelectContainingTab {
    self.didSelectContainingTab = YES;
}
@end

#pragma mark - Tests

@interface RevealHotKeyWindowTabSelectionTests : XCTestCase
@end

@implementation RevealHotKeyWindowTabSelectionTests

// Revealing a session that lives in a dedicated hotkey window must
// select its containing tab (Issue 12902).
- (void)testRevealSelectsContainingTabForHotKeyWindow {
    PTYSession *session = [[PTYSession alloc] initSynthetic:NO];

    RevealMockSessionDelegate *delegate = [[RevealMockSessionDelegate alloc] init];
    delegate.parentWindow = [[RevealMockHotKeyTerminal alloc] init];
    // delegate is a weak property; the local strong reference keeps it
    // (and its parentWindow) alive across the -reveal call.
    session.delegate = (id)delegate;

    [session reveal];

    XCTAssertEqual(delegate.activatedSession, session,
                   @"reveal must make the revealed session active");
    XCTAssertTrue(delegate.didSelectContainingTab,
                  @"reveal must select the containing tab even in a hotkey window (Issue 12902)");
}

@end
