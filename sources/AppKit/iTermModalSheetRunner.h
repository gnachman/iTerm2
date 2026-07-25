//
//  iTermModalSheetRunner.h
//  iTerm2
//
//  Shared guard for hand-rolled modal sheets.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Runs `modalWindow` (already presented as a sheet on `parentWindow` via
// -beginSheet:completionHandler:) with -[NSApplication runModalForWindow:], but aborts
// the modal if `parentWindow` closes before the sheet ends.
//
// Without this, destroying the parent while its sheet is up orphans the sheet: the
// beginSheet: completion handler never fires, nothing calls -stopModal, and the main
// thread stays blocked in the modal run loop forever (an unrecoverable, Force-Quit-only
// app hang). This is the same guard -[NSAlert(iTerm) runSheetModalForWindow:] applies to
// alert sheets, factored out so the hand-rolled beginSheet:/runModalForWindow: call sites
// (paste-special, coprocess, split, parameter, and add-account panels) can share it.
//
// Returns the modal response (NSModalResponseAbort if the parent closed).
NSModalResponse iTermRunModalForWindowAbortingIfParentCloses(NSWindow *modalWindow,
                                                             NSWindow *parentWindow);

NS_ASSUME_NONNULL_END
