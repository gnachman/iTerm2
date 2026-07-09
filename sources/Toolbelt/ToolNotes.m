//
//  ToolNotes.m
//  iTerm
//
//  Created by George Nachman on 9/19/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolNotes.h"

#import "iTermSetFindStringNotification.h"
#import "iTermToolWrapper.h"
#import "NSFileManager+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSWindow+iTerm.h"
#import "PTYTab.h"
#import "PTYWindow.h"
#import "PseudoTerminal.h"
#import "iTerm2SharedARC-Swift.h"

static NSString *kToolNotesSetTextNotification = @"kToolNotesSetTextNotification";
NSString *const iTermToolNotesDidSaveGlobalNotesNotification = @"iTermToolNotesDidSaveGlobalNotesNotification";

typedef NS_ENUM(NSInteger, ToolNotesMode) {
    ToolNotesModeGlobal = 0,
    ToolNotesModeSession = 1,
};

@interface iTermUnformattedTextView : NSTextView
@end

@implementation iTermUnformattedTextView

- (void)paste:(id)sender {
    [self pasteAsPlainText:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(performFindPanelAction:)) {
        if (menuItem.tag == NSFindPanelActionSetFindString) {
            return self.selectedRanges.count > 0 || self.selectedRange.length > 0;
        }
    }
    return [super validateMenuItem:menuItem];
}

- (void)performFindPanelAction:(id)sender {
    NSMenuItem *menuItem = [NSMenuItem castFrom:sender];
    if (!menuItem) {
        return;
    }
    if (menuItem.tag == NSFindPanelActionSetFindString) {
        NSString *string = [self.string substringWithRange:self.selectedRange];
        if (string.length == 0) {
            return;
        }
        [[iTermSetFindStringNotification notificationWithString:string] post];
    }
    [super performFindPanelAction:sender];
}

@end

@interface ToolNotes () {
    NSSegmentedControl *modeControl_;
    NSScrollView *scrollView_;
    ToolNotesMode mode_;
    iTermSessionNoteModel *sessionNoteModel_;
    BOOL ignoreSessionNoteNotification_;
}
- (NSString *)filename;
@end

@implementation ToolNotes

+ (void)reloadGlobalNotesFromDisk {
    // Open global Notes views observe this and re-read notes.rtfd in -globalTextDidChange:.
    [[NSNotificationCenter defaultCenter] postNotificationName:kToolNotesSetTextNotification
                                                        object:nil];
}

- (BOOL)isFlipped {
    return YES;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        filemanager_ = [[NSFileManager alloc] init];
        mode_ = ToolNotesModeGlobal;

        // Mode selector
        modeControl_ = [NSSegmentedControl segmentedControlWithLabels:@[@"Global", @"Session"]
                                                         trackingMode:NSSegmentSwitchTrackingSelectOne
                                                               target:self
                                                               action:@selector(modeChanged:)];
        [modeControl_ retain];
        modeControl_.selectedSegment = 0;
        modeControl_.controlSize = NSControlSizeSmall;
        [modeControl_ sizeToFit];
        [self addSubview:modeControl_];

        scrollView_ = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        if (@available(macOS 10.16, *)) {
            [scrollView_ setBorderType:NSLineBorder];
            scrollView_.scrollerStyle = NSScrollerStyleOverlay;
        } else {
            [scrollView_ setBorderType:NSBezelBorder];
        }
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        scrollView_.drawsBackground = NO;

        NSSize contentSize = [scrollView_ contentSize];
        textView_ = [[iTermUnformattedTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        [textView_ setAllowsUndo:YES];
        [textView_ setRichText:NO];
        [textView_ setImportsGraphics:NO];
        [textView_ setMinSize:NSMakeSize(0.0, contentSize.height)];
        [textView_ setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
        [textView_ setVerticallyResizable:YES];
        [textView_ setHorizontallyResizable:NO];
        [textView_ setAutoresizingMask:NSViewWidthSizable];

        [[textView_ textContainer] setContainerSize:NSMakeSize(contentSize.width, FLT_MAX)];
        [[textView_ textContainer] setWidthTracksTextView:YES];
        [textView_ setDelegate:self];

        // Route the initial load through -loadGlobalNote (not a bare readRTFDFromFile:) so a
        // transiently-unreadable notes.rtfd at launch (a dataless iCloud/Dropbox placeholder) sets
        // needsReloadBeforeSave_ and can't be clobbered by the first keystroke. mode_ is Global here.
        [self loadGlobalNote];
        textView_.automaticSpellingCorrectionEnabled = NO;
        textView_.automaticDashSubstitutionEnabled = NO;
        textView_.automaticQuoteSubstitutionEnabled = NO;
        textView_.automaticDataDetectionEnabled = NO;
        textView_.automaticLinkDetectionEnabled = NO;
        textView_.smartInsertDeleteEnabled = NO;

        [scrollView_ setDocumentView:textView_];
        [self addSubview:scrollView_];

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self
               selector:@selector(windowAppearanceDidChange:)
                   name:iTermWindowAppearanceDidChange
                 object:nil];
        [nc addObserver:self
               selector:@selector(globalTextDidChange:)
                   name:kToolNotesSetTextNotification
                 object:nil];
        [nc addObserver:self
               selector:@selector(activeSessionDidChange:)
                   name:iTermSessionBecameKey
                 object:nil];
        [nc addObserver:self
               selector:@selector(sessionNoteModelTextDidChange:)
                   name:iTermSessionNoteModel.textDidChangeNotification
                 object:nil];

        [self relayout];
    }
    return self;
}

// Writes the global notes to disk, but does NOT recreate the file when the view is empty and the
// file is already gone. Otherwise a sync-propagated deletion (which cleared the view) would be undone
// by writing back an empty notes.rtfd, which then gets pushed back to other machines.
- (void)writeGlobalNotesToDisk {
    NSString *path = [self filename];
    if (needsReloadBeforeSave_) {
        // A prior read failed transiently (an import notification, OR -loadGlobalNote/init which CLEARS
        // the view before reading), so the view may be stale or an accidentally-emptied placeholder.
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            // The file is genuinely gone (a real deletion; placeholders still report existing).
            if (editedSinceFailedReload_) {
                // The user typed genuine new content after the note went away: treat it as a new note
                // and write it below. (Applies whether the base view was real old content or emptied:
                // once the file is gone there is nothing to clobber, so the user's content wins.)
                [self clearStaleViewFlags];
            } else {
                // No user edit and the file is gone: the view is known-stale/emptied. Discard it so it
                // can't recreate a deleted note; the empty-view guard below then suppresses the write.
                [textView_ setString:@""];
                needsReloadBeforeSave_ = NO;
                viewEmptiedByFailedLoad_ = NO;
            }
        } else if (editedSinceFailedReload_ && !viewEmptiedByFailedLoad_) {
            // The user made a genuine edit on top of the view's REAL old content (the failed reload
            // left it in place), so their edit wins over the on-disk copy: preserve it, per the
            // editedSinceFailedReload_ contract. Skip the re-read (which would discard it).
            [self clearStaleViewFlags];
        } else {
            // File present, view untrustworthy (an emptied placeholder, or unedited). Snapshot any
            // typing BEFORE the read replaces the view, so if we adopt the on-disk note over it we can
            // stash the discarded typing (recoverable), matching the sync's "never destroy the only
            // copy" philosophy. Only capture the ADOPT case, not the defer case, so a placeholder that
            // stays unreadable across many keystrokes doesn't stash a backup per keystroke.
            NSData *typedRTFD = nil;
            if (editedSinceFailedReload_ && [[textView_ textStorage] length] > 0) {
                typedRTFD = [self currentViewRTFD];
            }
            if ([textView_ readRTFDFromFile:path]) {
                // Present and now readable: the on-disk note is authoritative. Adopt it, dropping any
                // keystroke typed onto the emptied placeholder (backed up first). This prevents a
                // transient read failure plus one keystroke from destroying the real note. Adopting means
                // the view now matches disk, so there is nothing to write - return so we don't fall
                // through and re-serialize it (RTFD round-tripping is not byte-identical, which could
                // ping-pong content) or post the save notification that arms a push of content that just
                // came FROM the folder.
                [self adoptOnDiskGlobalNoteDiscardingTypedRTFD:typedRTFD];
                return;
            }
            if (![self globalNoteFileHasReadableBytesAtPath:path]) {
                // Present but its bytes are not materialized (a dataless iCloud/Dropbox placeholder mid-
                // download, or otherwise unreadable): content unknown, so never overwrite it. Defer the
                // write until a read succeeds. (dealloc stashes typed content, so quitting while still
                // downloading doesn't lose it.)
                DLog(@"Global notes present-but-unreadable (placeholder); skipping write to avoid clobbering it");
                return;
            }
            if ([textView_ readRTFDFromFile:path]) {
                // The bytes just materialized (a download race: the first read saw the dataless file,
                // then probing readable bytes above pulled it down). It IS a valid note after all - adopt
                // it rather than treating it as corrupt and overwriting a good, just-downloaded note.
                [self adoptOnDiskGlobalNoteDiscardingTypedRTFD:typedRTFD];
                return;
            }
            // The bytes are readable but still don't parse as RTFD: the file is genuinely corrupt/
            // malformed (a truncated write, a non-RTFD file at this path, or a bad copy synced from
            // another Mac), NOT an undownloaded placeholder.
            if (typedRTFD == nil) {
                // No genuine typed content to preserve (the view was an unedited emptied placeholder):
                // leave the bad file untouched (the user may still recover it) rather than blanking it. A
                // later keystroke snapshots real content and re-enters here to heal. (Gate on the pre-read
                // snapshot, not the live view length, which the failed reads above may have perturbed.)
                DLog(@"Global notes present-but-corrupt with no pending edit; leaving file as-is");
                return;
            }
            // The user has typed real content. Deferring forever would permanently wedge global-note
            // saving (regression: before this sync feature, textDidChange overwrote unconditionally and
            // self-healed on the next keystroke). Restore the typed content (the failed reads may have
            // perturbed the view), clear the placeholder flags so the write path below backs up the
            // corrupt file (knownNotesFileToken_ == nil forces the backup) and overwrites it, self-healing.
            // globalNoteDirty_ is already YES (the user edited), so the DidSave post fires - correct, this
            // is a genuine local edit.
            DLog(@"Global notes present-but-corrupt; healing by overwriting with typed content after backup");
            [textView_ replaceCharactersInRange:NSMakeRange(0, [[textView_ textStorage] length])
                                        withRTFD:typedRTFD];
            [self clearStaleViewFlags];
            // fall through to the write below.
        }
    }
    if ([[textView_ textStorage] length] == 0 &&
        ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return;
    }
    if (!globalNoteDirty_) {
        // The view was loaded/adopted from disk and hasn't been edited since (a plain open+close, or an
        // edit that already saved). Re-serializing here would write byte-variant RTFD (AppKit's RTFD
        // writer has no canonical fixed point across OS/AppKit versions or default fonts) and post
        // iTermToolNotesDidSaveGlobalNotesNotification, arming a data-file push of content that differs
        // from the folder's copy only by serialization noise. Across a heterogeneous fleet that has no
        // common fixed point, so it ping-pongs forever and can overwrite a note a still-running peer
        // authored. Skip both the write and the post when there's nothing genuinely new to persist.
        return;
    }
    // Never destroy the only copy without a backup: before overwriting, back up the on-disk note if
    // either we've never successfully read it (knownNotesFileToken_ == nil but a file is present - it
    // appeared via an import we couldn't read, so its content is unknown and worth protecting) OR it
    // changed since this view last read/wrote it (another Notes window's debounced write, or a foreign/
    // import write - detected by the stat token, not mtime alone, so a same-tick foreign rewrite on a
    // synced folder can't slip through). A brand-new note (file absent) fails the fileExists check, so
    // its first write isn't spuriously backed up.
    if ([[NSFileManager defaultManager] fileExistsAtPath:path] &&
        (knownNotesFileToken_ == nil || ![[self notesFileStatToken] isEqualToString:knownNotesFileToken_])) {
        [self backUpOnDiskGlobalNoteForRecovery];
    }
    [textView_ writeRTFDToFile:path atomically:NO];
    [self captureKnownNotesFileToken];
    // The view is now persisted, so it is consistent with disk again.
    globalNoteDirty_ = NO;
    // notes.rtfd just changed on disk from a genuine local edit (imports reload through
    // -globalTextDidChange:, which reads, not this write path). Tell the settings-sync layer so it can
    // push the change live instead of waiting for the next unrelated autosave or app quit.
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermToolNotesDidSaveGlobalNotesNotification
                                                        object:self];
}

// Adopt the on-disk global note that -readRTFDFromFile: just loaded into the view: back up any typed
// draft being dropped, clear the undo stack (a Cmd-Z could otherwise revert toward the discarded draft
// and, via textDidChange, clobber and republish it fleet-wide), reset the stale-view flags, and record
// the file mtime. The view now matches disk, so it is not dirty.
- (void)adoptOnDiskGlobalNoteDiscardingTypedRTFD:(NSData *)typedRTFD {
    [self backUpDiscardedGlobalNoteRTFD:typedRTFD];
    [[textView_ undoManager] removeAllActions];
    [self clearStaleViewFlags];
    globalNoteDirty_ = NO;
    [self captureKnownNotesFileToken];
}

// YES if the file at path can be fully read into memory right now (its bytes are materialized), even if
// it does not parse as valid RTFD. Distinguishes a present-but-CORRUPT notes.rtfd (readable bytes, bad
// format - a truncated write, a non-RTFD file, or a bad synced copy) from an undownloaded dataless
// placeholder (bytes not local). A dataless iCloud item is caught by the cheap, non-blocking resource
// check first so we never trigger a synchronous network download on the main thread; only then does the
// NSFileWrapper read (which is local and fast for a real corrupt file) run.
- (BOOL)globalNoteFileHasReadableBytesAtPath:(NSString *)path {
    NSURL *url = [NSURL fileURLWithPath:path];
    NSNumber *isUbiquitous = nil;
    if ([url getResourceValue:&isUbiquitous forKey:NSURLIsUbiquitousItemKey error:NULL] &&
        isUbiquitous.boolValue) {
        NSString *status = nil;
        if ([url getResourceValue:&status forKey:NSURLUbiquitousItemDownloadingStatusKey error:NULL] &&
            [status isEqualToString:NSURLUbiquitousItemDownloadingStatusNotDownloaded]) {
            // An iCloud item whose bytes aren't local: reading them would block on a download. Defer.
            return NO;
        }
    }
    NSError *error = nil;
    NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithURL:url
                                                       options:NSFileWrapperReadingImmediate
                                                         error:&error];
    const BOOL readable = (wrapper != nil);
    [wrapper release];
    return readable;
}

// Stash typed-but-unsaved global-note content that is about to be dropped (we're adopting the
// downloaded on-disk copy over it, or quitting while a placeholder is still unreadable) into the same
// "Settings Sync Backups" root the sync uses, so the discard is recoverable. Best-effort; a nil/empty
// snapshot or an unavailable backup folder is a no-op. rtfdData is flattened RTFD (recoverable via
// NSAttributedString's RTFD reader).
- (void)backUpDiscardedGlobalNoteRTFD:(NSData *)rtfdData {
    if (rtfdData.length == 0) {
        return;
    }
    NSString *backupFolder = [iTermRemoteDataFileSync makeRecoveryBackupFolder];
    if (!backupFolder) {
        return;
    }
    NSString *backupPath = [backupFolder stringByAppendingPathComponent:@"discarded-notes.rtfd"];
    NSError *error = nil;
    if (![rtfdData writeToFile:backupPath options:0 error:&error]) {
        DLog(@"Failed to back up discarded global note: %@", error);
        return;
    }
    DLog(@"Backed up discarded global-note typing to %@", backupPath);
}

// A cheap stat fingerprint of notes.rtfd (dev/size/mtime.ns/ctime.ns/inode), or nil if it's
// absent/unreadable. Reuses the settings-sync layer's token (same fields it uses for change detection)
// so the two can't drift. Richer than mtime alone so a foreign rewrite that lands in the same coarse
// mtime tick (common on synced/network folders) is still detected via ctime (updated on any write,
// cannot be forced back), size, or inode (on an atomic replace).
- (NSString *)notesFileStatToken {
    return [iTermRemoteDataFileSync statTokenForFileAtPath:[self filename]];
}

// Flattened RTFD of the ENTIRE current view. The "never destroy the only copy" backups all snapshot the
// whole view this way; centralizing the range construction removes the risk of a copy-pasted range that
// silently omits a piece and backs up truncated content.
- (NSData *)currentViewRTFD {
    return [textView_ RTFDFromRange:NSMakeRange(0, [[textView_ textStorage] length])];
}

// Clear the three "the view may be stale relative to disk" flags together. They form one state ("view is
// no longer an untrustworthy placeholder / stale reload"), so resetting them in lockstep here keeps a
// future edit from clearing two of three and leaving a stuck placeholder. Only clears; the sites that
// ENTER the stale state (set needsReloadBeforeSave_ = YES) stay explicit.
- (void)clearStaleViewFlags {
    needsReloadBeforeSave_ = NO;
    editedSinceFailedReload_ = NO;
    viewEmptiedByFailedLoad_ = NO;
}

- (void)setKnownNotesFileToken:(NSString *)token {
    if (token == knownNotesFileToken_) {
        return;
    }
    [knownNotesFileToken_ release];
    knownNotesFileToken_ = [token copy];
}

// Record that this view is now consistent with the current on-disk notes.rtfd (call after a successful
// read of it or after writing it), so the overwrite guard can later detect a foreign change.
- (void)captureKnownNotesFileToken {
    [self setKnownNotesFileToken:[self notesFileStatToken]];
}

// Copy the current on-disk notes.rtfd package into the Settings Sync Backups root, so overwriting a
// copy that changed under us stays recoverable. Best-effort.
- (void)backUpOnDiskGlobalNoteForRecovery {
    NSString *path = [self filename];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return;
    }
    NSString *backupFolder = [iTermRemoteDataFileSync makeRecoveryBackupFolder];
    if (!backupFolder) {
        return;
    }
    NSString *backupPath = [backupFolder stringByAppendingPathComponent:@"notes.rtfd"];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:path toPath:backupPath error:&error]) {
        DLog(@"Failed to back up on-disk global note: %@", error);
        return;
    }
    DLog(@"Backed up clobbered on-disk global note to %@", backupPath);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (mode_ == ToolNotesModeGlobal) {
        // Quitting with typed-but-unsaved content over an unread placeholder: writeGlobalNotesToDisk
        // will either adopt the (now-readable) disk note over it or defer without writing, dropping the
        // typing either way. Stash a recovery copy first (harmless if it turns out to be redundant).
        if (needsReloadBeforeSave_ && editedSinceFailedReload_ && [[textView_ textStorage] length] > 0) {
            [self backUpDiscardedGlobalNoteRTFD:[self currentViewRTFD]];
        }
        [self writeGlobalNotesToDisk];
    }
    [modeControl_ release];
    [scrollView_ release];
    [sessionNoteModel_ release];
    [filemanager_ release];
    [knownNotesFileToken_ release];
    [super dealloc];
}

+ (ProfileType)supportedProfileTypes {
    return ProfileTypeBrowser | ProfileTypeTerminal;
}

- (NSString *)filename {
    // Reference the sync allowlist's constant rather than a bare literal so this on-disk name and the
    // synced allowlist can never drift apart silently (a rename is a single edit that moves both).
    return [NSString stringWithFormat:@"%@/%@", [filemanager_ applicationSupportDirectory], iTermRemoteDataFileSync.notesPackageName];
}

#pragma mark - Layout

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self relayout];
}

- (void)relayout {
    NSRect frame = self.frame;
    CGFloat controlHeight = modeControl_.frame.size.height;
    CGFloat kMargin = 4;
    modeControl_.frame = NSMakeRect(0, 0, frame.size.width, controlHeight);
    CGFloat scrollY = controlHeight + kMargin;
    scrollView_.frame = NSMakeRect(0, scrollY, frame.size.width,
                                   frame.size.height - scrollY);
}

#pragma mark - Mode Switching

- (void)modeChanged:(NSSegmentedControl *)sender {
    ToolNotesMode newMode = (ToolNotesMode)sender.selectedSegment;
    if (newMode == mode_) {
        return;
    }
    if (mode_ == ToolNotesModeGlobal) {
        if (largeNoteWritePending_) {
            // Leaving Global with a large-note edit still only in the view: flush it synchronously now.
            // Otherwise the pending debounced block would see mode_ == Session and drop the write, and
            // dealloc's writeGlobalNotesToDisk is also gated on Global, so the >= 100KB edit would be
            // lost. Bump the generation so the armed block becomes a no-op instead of rewriting later.
            largeNoteWritePending_ = NO;
            largeNoteWriteGeneration_ += 1;
            [self writeGlobalNotesToDisk];
        }
        // A small edit typed onto an unreadable placeholder was immediately written but DEFERRED (the
        // placeholder is unreadable), so it lives only in the view. -loadSessionNote below will setString
        // and wipe it, and dealloc's backup only fires at quit. Stash a recovery copy first, same as
        // dealloc, so the mode switch can't silently destroy an unsaved edit.
        if (needsReloadBeforeSave_ && editedSinceFailedReload_ && [[textView_ textStorage] length] > 0) {
            [self backUpDiscardedGlobalNoteRTFD:[self currentViewRTFD]];
        }
    }
    mode_ = newMode;
    [[textView_ undoManager] removeAllActions];
    if (mode_ == ToolNotesModeGlobal) {
        [self loadGlobalNote];
    } else {
        [self loadSessionNote];
    }
}

- (void)loadGlobalNote {
    [sessionNoteModel_ release];
    sessionNoteModel_ = nil;
    // Clear first so a missing/unreadable notes.rtfd (e.g. deleted by a sync import) doesn't leave the
    // previous mode's session-note text in the view as if it were the global note. Otherwise the next
    // keystroke would run textDidChange -> writeGlobalNotesToDisk and re-create the deleted file with
    // session-note content, which would then sync to every machine.
    [textView_ setString:@""];
    // loadGlobalNote replaces the whole view from disk, so any prior "user edited a stale view" state
    // no longer applies.
    editedSinceFailedReload_ = NO;
    NSString *path = [self filename];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        // No file on disk: an empty view is the truth, so it's safe to save.
        needsReloadBeforeSave_ = NO;
        viewEmptiedByFailedLoad_ = NO;
        [self setKnownNotesFileToken:nil];
    } else if ([textView_ readRTFDFromFile:path]) {
        // Loaded the current on-disk note, so the view matches disk and a stale flag is cleared.
        needsReloadBeforeSave_ = NO;
        viewEmptiedByFailedLoad_ = NO;
        [self captureKnownNotesFileToken];
    } else {
        // The file exists but couldn't be read (a transient failure, e.g. a not-yet-downloaded
        // placeholder). The view is now EMPTY but disk still holds the real note, so mark stale AND
        // mark the empty view as an untrustworthy placeholder: writeGlobalNotesToDisk must retry the
        // read, must not clobber the file, and must not treat a keystroke on this empty view as a real
        // edit that wins over the (still-downloading) note.
        needsReloadBeforeSave_ = YES;
        viewEmptiedByFailedLoad_ = YES;
        [self setKnownNotesFileToken:nil];
    }
    // The view was wholesale-replaced from disk (or emptied), so it reflects the load attempt and holds
    // no unpersisted edit: closing now must not re-serialize and push it.
    globalNoteDirty_ = NO;
    // The view was wholesale-replaced from disk, so pre-load undo actions no longer correspond to it;
    // an undo could otherwise reintroduce stale text and (via textDidChange) republish it.
    [[textView_ undoManager] removeAllActions];
    textView_.font = [NSFont it_toolbeltFont];
}

- (void)loadSessionNote {
    [sessionNoteModel_ release];
    id<iTermToolbeltViewDelegate> delegate = [[self toolWrapper] delegate].delegate;
    sessionNoteModel_ = [[delegate toolbeltCurrentSessionNoteModel] retain];
    [textView_ setString:sessionNoteModel_.text ?: @""];
    textView_.font = [NSFont it_toolbeltFont];
}

#pragma mark - NSTextViewDelegate

- (void)textDidChange:(NSNotification *)aNotification {
    if (mode_ == ToolNotesModeGlobal) {
        // A genuine keystroke: the view now holds an unpersisted edit, so the write+DidSave path is
        // allowed to run (see the globalNoteDirty_ gate in -writeGlobalNotesToDisk).
        globalNoteDirty_ = YES;
        if (needsReloadBeforeSave_) {
            // The user is typing after a transient reload-read failure, so the view now holds genuine
            // new edits (not stale pre-import text). Record that so writeGlobalNotesToDisk preserves
            // them rather than re-reading disk over them.
            editedSinceFailedReload_ = YES;
        }
        // Writing on every keystroke is too slow for a large note, so below the threshold write
        // immediately and above it flush on a debounce instead of not at all. Persisting large notes
        // (even lazily) keeps them visible to settings-sync and avoids a sync pull silently clobbering
        // an unsaved in-view note that never reached disk.
        if ([[textView_ textStorage] length] < 100 * 1024) {
            // Below the threshold: write immediately, and cancel any armed large-note debounce (the
            // note just shrank), since this write already persisted the current content. Bumping the
            // generation makes the pending block a no-op so it doesn't rewrite + re-post redundantly.
            largeNoteWritePending_ = NO;
            largeNoteWriteGeneration_ += 1;
            largeNoteWriteRetryCount_ = 0;
            [self writeGlobalNotesToDisk];
            ignoreNotification_ = YES;
            // Post with self as the object so sibling Notes windows can tell this routine per-window save
            // from a sync-layer import (which posts object:nil) and not force-clobber their own unsaved
            // edits (see -globalTextDidChange:).
            [[NSNotificationCenter defaultCenter] postNotificationName:kToolNotesSetTextNotification
                                                                object:self];
            ignoreNotification_ = NO;
        } else {
            // Fresh large edit: reset the retry budget for the deferred-write case.
            largeNoteWriteRetryCount_ = 0;
            [self scheduleDebouncedGlobalNotesWrite];
        }
    } else {
        if (!sessionNoteModel_) {
            id<iTermToolbeltViewDelegate> delegate = [[self toolWrapper] delegate].delegate;
            sessionNoteModel_ = [[delegate toolbeltEnsureCurrentSessionNoteModel] retain];
        }
        if (sessionNoteModel_) {
            ignoreSessionNoteNotification_ = YES;
            sessionNoteModel_.text = textView_.string;
            ignoreSessionNoteNotification_ = NO;
        }
    }
    [textView_ breakUndoCoalescing];
}

// Trailing debounce for large global notes (see textDidChange:): flush the in-view note to disk a
// short time after the LAST edit, so it reaches disk (and thus settings-sync) without paying a write
// on every keystroke. Each edit reschedules by bumping the generation, so the write fires once the
// user pauses rather than on a fixed cadence from the first edit; a superseded block (later edit,
// shrink below threshold, or an explicit flush) sees a stale generation and does nothing.
- (void)scheduleDebouncedGlobalNotesWrite {
    largeNoteWritePending_ = YES;
    largeNoteWriteGeneration_ += 1;
    const NSInteger generation = largeNoteWriteGeneration_;
    __weak __typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ToolNotes *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf->largeNoteWriteGeneration_) {
            // Superseded by a later edit, a shrink-below-threshold immediate write, or a flush.
            return;
        }
        if (strongSelf->mode_ != ToolNotesModeGlobal) {
            strongSelf->largeNoteWritePending_ = NO;
            return;
        }
        [strongSelf writeGlobalNotesToDisk];
        if (strongSelf->needsReloadBeforeSave_) {
            // writeGlobalNotesToDisk DEFERRED (notes.rtfd is a present-but-unreadable placeholder), so
            // the large note is not yet on disk. Reschedule so the write is retried once the placeholder
            // becomes readable (leaving largeNoteWritePending_ set keeps globalTextDidChange's
            // clobber-guard armed), but BOUND the retries: a permanently-unreadable/corrupt placeholder
            // must not spin a 2s wakeup forever. The count resets whenever the user edits again.
            static const NSInteger kMaxLargeNoteWriteRetries = 60;   // ~2 minutes at 2s
            if (strongSelf->largeNoteWriteRetryCount_ < kMaxLargeNoteWriteRetries) {
                strongSelf->largeNoteWriteRetryCount_ += 1;
                [strongSelf scheduleDebouncedGlobalNotesWrite];
            } else {
                DLog(@"Giving up the debounced large-note write; notes.rtfd stayed unreadable across %ld retries",
                     (long)strongSelf->largeNoteWriteRetryCount_);
                strongSelf->largeNoteWritePending_ = NO;
            }
            return;
        }
        strongSelf->largeNoteWriteRetryCount_ = 0;
        strongSelf->largeNoteWritePending_ = NO;
        strongSelf->ignoreNotification_ = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:kToolNotesSetTextNotification
                                                            object:strongSelf];
        strongSelf->ignoreNotification_ = NO;
    });
}

#pragma mark - Notifications

- (void)globalTextDidChange:(NSNotification *)aNotification {
    if (mode_ != ToolNotesModeGlobal) {
        return;
    }
    if (!ignoreNotification_) {
        if (largeNoteWritePending_ && [aNotification.object isKindOfClass:[ToolNotes class]]) {
            // The notification came from a SIBLING Notes window's routine per-window save (it posts with
            // itself as object; the sync layer's import posts object:nil). Do NOT force-reconcile my
            // still-unsaved large in-view edit just because a different window typed: that would discard
            // the user's active composition (recoverable only from backups) for an unrelated keystroke.
            // A genuine on-disk import (object:nil) falls through and reconciles below.
            return;
        }
        if (largeNoteWritePending_) {
            // A large in-view note edit hasn't been flushed yet (see scheduleDebouncedGlobalNotesWrite).
            // This is a sync-layer import (object:nil) - the on-disk file genuinely changed - so keeping
            // the pending write would either clobber the import or, on a deletion, resurrect the note,
            // both with NO backup. Cancel the pending write and stash the unsaved in-view edit
            // (recoverable), then fall through to reconcile against disk (adopt it, or honor a deletion).
            largeNoteWritePending_ = NO;
            largeNoteWriteGeneration_ += 1;
            largeNoteWriteRetryCount_ = 0;
            if ([[textView_ textStorage] length] > 0) {
                [self backUpDiscardedGlobalNoteRTFD:[self currentViewRTFD]];
            }
        }
        NSString *path = [self filename];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            // The file was removed (e.g. a settings-sync import propagated a deletion). If the user had a
            // genuine unsaved draft (typed over an emptied placeholder), stash it first so honoring the
            // deletion doesn't silently destroy the only copy - matching the file-present adopt branch.
            if (editedSinceFailedReload_ && [[textView_ textStorage] length] > 0) {
                [self backUpDiscardedGlobalNoteRTFD:[self currentViewRTFD]];
            }
            // Clear the view so the stale text isn't written back on the next keystroke, which would
            // resurrect the deleted notes. Clear the undo stack too: an undo could otherwise restore the
            // deleted text and republish it.
            [textView_ setString:@""];
            [[textView_ undoManager] removeAllActions];
            [self clearStaleViewFlags];
            [self setKnownNotesFileToken:nil];
            // The view now reflects the propagated deletion (empty); closing must not re-create + push it.
            globalNoteDirty_ = NO;
        } else {
            // File present. Snapshot any typing BEFORE the read replaces the view, so if we adopt the
            // just-imported note over a draft typed onto an emptied placeholder we can stash it
            // (recoverable), mirroring -writeGlobalNotesToDisk. Only when there was a genuine edit, so a
            // benign import doesn't churn a backup.
            NSData *typedRTFD = nil;
            if (editedSinceFailedReload_ && [[textView_ textStorage] length] > 0) {
                typedRTFD = [self currentViewRTFD];
            }
            if ([textView_ readRTFDFromFile:path]) {
                // Adopt the just-imported note (backs up any dropped draft, clears the undo stack so a
                // Cmd-Z can't revert toward the pre-import text and republish it, and marks the view
                // consistent with disk so closing won't re-push it).
                [self adoptOnDiskGlobalNoteDiscardingTypedRTFD:typedRTFD];
            } else {
                // The file exists but couldn't be read this time (a transient cause: a mid-download
                // placeholder, a momentary lock during an atomic replace, a transiently malformed
                // RTFD). Leave the current view content intact but mark that it may be stale relative
                // to the just-imported file, so writeGlobalNotesToDisk retries the read and won't write
                // back pre-import text (which would clobber the import and then sync the stale copy
                // out). Only reset the edit tracking on a FRESH failure (NO -> YES). If we were already
                // pending, a genuine edit may be sitting in the view; clearing editedSinceFailedReload_
                // here would forget it and later discard it. If the current view is EMPTY (the file was
                // absent at launch, so there's no "real old content"), treat it as an emptied placeholder
                // for the now-present file, so a keystroke on it routes through the protective adopt path
                // rather than overwriting the just-imported note.
                if (!needsReloadBeforeSave_) {
                    needsReloadBeforeSave_ = YES;
                    editedSinceFailedReload_ = NO;
                    viewEmptiedByFailedLoad_ = ([[textView_ textStorage] length] == 0);
                }
            }
        }
    }
}

- (void)activeSessionDidChange:(NSNotification *)notification {
    if (mode_ != ToolNotesModeSession) {
        return;
    }
    id<iTermToolbeltViewDelegate> delegate = [[self toolWrapper] delegate].delegate;
    iTermSessionNoteModel *newModel = [delegate toolbeltCurrentSessionNoteModel];
    if (newModel == sessionNoteModel_) {
        return;
    }
    [self loadSessionNote];
}

- (void)sessionNoteModelTextDidChange:(NSNotification *)notification {
    if (mode_ != ToolNotesModeSession) {
        return;
    }
    if (ignoreSessionNoteNotification_) {
        return;
    }
    iTermSessionNoteModel *model = notification.object;
    if (model != sessionNoteModel_) {
        return;
    }
    [textView_ setString:model.text ?: @""];
}

#pragma mark - ToolbeltTool

- (void)shutdown {
}

- (CGFloat)minimumHeight {
    return 68;
}

#pragma mark - Appearance

- (void)updateAppearance {
    if (!self.window) {
        return;
    }
    textView_.drawsBackground = NO;
    textView_.textColor = [NSColor textColor];
}

- (void)viewDidMoveToWindow {
    [self updateAppearance];
}

- (void)windowAppearanceDidChange:(NSNotification *)notification {
    [self updateAppearance];
}

@end
