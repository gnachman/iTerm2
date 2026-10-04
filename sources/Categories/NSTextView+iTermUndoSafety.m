#import "NSTextView+iTermUndoSafety.h"

#import "DebugLogging.h"
#import <objc/runtime.h>

@implementation NSTextView (iTermUndoSafety)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SEL originalSelector = @selector(viewWillMoveToWindow:);

        // method_exchangeImplementations mutates whatever Method
        // class_getInstanceMethod resolves to, which is the INHERITED method if
        // NSTextView doesn't implement viewWillMoveToWindow: itself. On current
        // macOS it does (verified), but guard anyway: if a future OS drops the
        // override, swizzling would corrupt NSView's shared IMP for every view.
        // Detect that by comparing our IMP to our superclass's and bail if equal.
        if (class_getMethodImplementation(self, originalSelector) ==
            class_getMethodImplementation([self superclass], originalSelector)) {
            DLog(@"NSTextView does not override viewWillMoveToWindow:; skipping undo-safety swizzle");
            return;
        }

        SEL replacementSelector = @selector(iterm_undoSafety_viewWillMoveToWindow:);
        Method originalMethod = class_getInstanceMethod(self, originalSelector);
        Method replacementMethod = class_getInstanceMethod(self, replacementSelector);
        if (originalMethod && replacementMethod) {
            method_exchangeImplementations(originalMethod, replacementMethod);
        }
    });
}

- (void)iterm_undoSafety_viewWillMoveToWindow:(NSWindow *)newWindow {
    // Only scrub when the text view is leaving its window for good (newWindow ==
    // nil, i.e. about to be torn down). When it moves to another live window (a
    // tab tear-off or split re-parent) its text storage and undo actions are
    // still valid, so discarding them would wipe undo history the user still
    // wants. Gate on allowsUndo too: a text view that never registers undo has
    // nothing to scrub, and this avoids lazily creating a window undo manager.
    //
    // Scrub the WINDOW's undo manager specifically -- not self.undoManager. The
    // window's manager is the only one that can outlive this view, so it is the
    // only place a dangling text-storage target can accumulate. A view that owns
    // a private undo manager (or has one vended by a delegate) is deliberately
    // NOT scrubbed: that manager dies with the view, and such a view can survive
    // this newWindow==nil transition (e.g. the composer across a tab switch), so
    // clearing its history here would be a bug. See NSTextView+iTermUndoSafety.h.
    if (newWindow == nil && self.allowsUndo) {
        NSWindow *currentWindow = self.window;
        NSTextStorage *textStorage = self.textStorage;
        NSUndoManager *undoManager = currentWindow.undoManager;
        if (undoManager != nil && textStorage != nil) {
            DLog(@"iTermUndoSafety: scrub textStorage %@ from %@ as %@ leaves window %@",
                 textStorage, undoManager, self, currentWindow);
            [undoManager removeAllActionsWithTarget:textStorage];
        }
    }
    // Call through to the original implementation (swapped by the exchange).
    [self iterm_undoSafety_viewWillMoveToWindow:newWindow];
}

@end
