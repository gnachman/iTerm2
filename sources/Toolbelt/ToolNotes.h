//
//  ToolNotes.h
//  iTerm
//
//  Created by George Nachman on 9/19/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "FutureMethods.h"
#import "iTermToolbeltView.h"

// Posted on the main thread right after a global note is actually written to notes.rtfd (a genuine
// local edit, not a sync import, which never writes through this path). Lets the settings-sync layer
// push the change live instead of only at the next unrelated autosave or at quit. Posted with the
// ToolNotes instance as the object.
extern NSString *const iTermToolNotesDidSaveGlobalNotesNotification;

@interface ToolNotes : NSView <ToolbeltTool, NSTextViewDelegate> {
    NSTextView *textView_;
    NSFileManager *filemanager_;
    BOOL ignoreNotification_;
    // Set when a reload notification's re-read of notes.rtfd failed transiently. While set, the view's
    // content may be stale relative to disk (e.g. a just-imported file), so saving it would clobber
    // the import; writeGlobalNotesToDisk retries the read first and skips the write if it still fails.
    BOOL needsReloadBeforeSave_;
    // Set when the user types while needsReloadBeforeSave_ is set (i.e. after a transient reload-read
    // failure). It means the user made a genuine edit against the current view. Whether that edit is
    // preserved on a subsequent readable file depends on viewEmptiedByFailedLoad_ below.
    BOOL editedSinceFailedReload_;
    // Distinguishes the two ways needsReloadBeforeSave_ gets set. YES when a failed LOAD read
    // (-loadGlobalNote / init) left the view EMPTY: the view is then an untrustworthy placeholder for
    // unread on-disk content, so a keystroke on it is not a real edit of the note and must not clobber
    // the (still-downloading) file. NO when a failed reload-notification read LEFT the view's real old
    // content in place: a keystroke there IS a genuine edit that writeGlobalNotesToDisk preserves.
    BOOL viewEmptiedByFailedLoad_;
    // A large (>= autosave threshold) global note isn't written on every keystroke (too slow); it is
    // flushed on a trailing debounce instead. Without any flush, a large in-view note lives only in
    // memory until dealloc, so a settings-sync pull that overwrites notes.rtfd would silently lose it
    // with no backup. largeNoteWritePending_ tracks whether a debounced write is armed; the generation
    // counter lets a superseded or cancelled armed block become a no-op (each new edit reschedules, and
    // an immediate small-note write or a flush bumps the generation to invalidate the pending block).
    BOOL largeNoteWritePending_;
    NSInteger largeNoteWriteGeneration_;
    // Consecutive times the debounced large-note write DEFERRED (notes.rtfd present-but-unreadable) and
    // rescheduled itself. Bounded so a permanently-unreadable/corrupt placeholder can't spin a 2s
    // main-queue wakeup forever. Reset when the user edits again (fresh retry budget) or a write succeeds.
    NSInteger largeNoteWriteRetryCount_;
    // A cheap stat fingerprint (dev/size/mtime.ns/ctime.ns/inode) of notes.rtfd as of the last read/write
    // this view is consistent with. Before overwriting the file, writeGlobalNotesToDisk compares the
    // current token to this: if it changed (another Notes window's debounced write, or a foreign/import
    // write), the on-disk copy is backed up before being clobbered, upholding "never destroy the only
    // copy without a backup". A plain mtime was insufficient: on the 1-2s-resolution synced/network
    // folders this feature targets, a foreign rewrite landing in the same mtime tick would compare equal
    // and skip the backup; ctime/size/inode still differ, so the richer token catches it. nil = unknown
    // (no baseline yet, e.g. the file was absent), which forces the backup.
    NSString *knownNotesFileToken_;
    // YES when the view holds a genuine local edit not yet persisted to notes.rtfd. Set on a real
    // keystroke (textDidChange in Global mode), cleared once the view is made consistent with disk (a
    // successful write, a load, or an adopt/delete import). writeGlobalNotesToDisk's normal write+DidSave
    // path is gated on this so closing a toolbelt with an UNEDITED note doesn't re-serialize it (RTFD has
    // no canonical byte form across AppKit versions/fonts) and post iTermToolNotesDidSaveGlobalNotes,
    // which would push a byte-variant to the sync folder, ping-pong across a fleet, and clobber a note a
    // still-running peer authored.
    BOOL globalNoteDirty_;
}

// Tells any open global Notes view to re-read notes.rtfd from disk. Call after the file is
// replaced out from under the view (e.g. by settings sync) so the view doesn't keep showing stale
// text and overwrite the new file on its next autosave.
+ (void)reloadGlobalNotesFromDisk;

@end
