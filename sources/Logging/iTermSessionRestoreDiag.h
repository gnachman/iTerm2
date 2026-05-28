//
//  iTermSessionRestoreDiag.h
//  iTerm2
//
//  Always-on diagnostic logger for issue 12866 (session restoration loses the
//  working directory for some panes). Writes to
//  ~/Library/Application Support/iTerm2/SessionRestoreDiag.log. The log is
//  append-only and never rotated or truncated: dropping events risks losing
//  the one line that explains the bug, and disk is cheap. Persists across
//  iTerm2 restarts so we can compare what was written at save time with what's
//  read at restore time, without requiring the user to enable full debug
//  logging.
//
//  This build traces the full graph-db save/restore path (one line per SQL
//  write, raw row read, transformer node, recovery, orphan deletion, and lazy
//  load), so the file can grow large. Safe to delete manually; remove this
//  whole facility once 12866 is resolved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern void iTermSessionRestoreDiagLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

NS_ASSUME_NONNULL_END
