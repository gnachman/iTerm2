#import <Cocoa/Cocoa.h>

// App-wide safety net for a long-standing AppKit crash (Apple bug rdar://23443090,
// unfixed for ~a decade): an NSTextView with allowsUndo=YES registers its
// text-editing undo actions against its NSTextStorage on the *window's* undo
// manager. NSUndoManager holds action targets unretained, so a text view that is
// shorter-lived than its window (a per-session editor, a split pane, a toolbelt
// tool, the browser address bar, …) leaves dangling registrations behind when it
// and its text storage are deallocated. The next Undo then messages freed memory
// and crashes in objc_msgSend / -[NSUndoManager undoNestedGroup]. NSTextView is
// supposed to call -[NSUndoManager removeAllActionsWithTarget:] with its text
// storage on teardown and fails to.
//
// This category installs (via +load) a scoped swizzle of -viewWillMoveToWindow:
// that scrubs the text view's text-storage-targeted actions from the departing
// window's undo manager. viewWillMoveToWindow: is the last moment where both the
// old window and the still-live text storage are reachable (by dealloc time the
// view has already left the window, so self.window is nil there).
//
// Scope and the invariant it relies on: this scrubs the WINDOW's undo manager
// only, because that is the only manager that can outlive the text view (the
// window persists while sessions/panes/views come and go). A text view that uses
// its own manager instead is not covered, and does not need to be:
//
//   * A view that owns a private NSUndoManager (overrides -undoManager, e.g.
//     ComposerTextView, PlaceholderTextView) -- the manager dies with the view,
//     so its registrations can never dangle. Scrubbing must NOT touch it, since
//     such views can survive a detach (a tab switch sends viewWillMoveToWindow:
//     with newWindow == nil while the view lives on) and wiping their history
//     would be a bug.
//   * A view given a manager by a delegate's -undoManagerForTextView: (e.g.
//     PTYNoteViewController) -- safe in iTerm because that manager is owned by
//     and dies with the controller/view. Not scrubbed here. NOTE: this is the
//     one gap in the "app-wide" net -- a hypothetical delegate that vends a
//     manager OUTLIVING the text view would still dangle. No such case exists in
//     iTerm; if one is added, that editor must own the manager's lifetime.
//
// Contract for new code: any long-lived NSTextView-based editor that can outlive
// its window (survive a tab switch / re-parent) MUST own a private undo manager
// (override -undoManager). That makes it immune to the crash by construction and
// keeps this scrub a no-op for it.
@interface NSTextView (iTermUndoSafety)
@end
