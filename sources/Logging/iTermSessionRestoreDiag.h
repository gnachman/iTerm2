//
//  iTermSessionRestoreDiag.h
//  iTerm2
//
//  Always-on diagnostic logger for issue 12866 (session restoration loses the
//  working directory for some panes). Writes to
//  ~/Library/Application Support/iTerm2/SessionRestoreDiag.log, capped at
//  ~256 KB. Persists across iTerm2 restarts so we can compare what was written
//  at save time with what's read at restore time, without requiring the user
//  to enable full debug logging.
//
//  Volume is one short line per session save and one per session restore, so
//  the performance cost is negligible. Safe to remove once 12866 is resolved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern void iTermSessionRestoreDiagLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

NS_ASSUME_NONNULL_END
