//
//  VT100ScreenMark.h
//  iTerm
//
//  Created by George Nachman on 12/5/13.
//
//

#import <Foundation/Foundation.h>
#import "iTermMark.h"
#import "VT100GridTypes.h"
#import "VT100PromptKind.h"

NS_ASSUME_NONNULL_BEGIN

@class CapturedOutput;
@protocol CapturedOutputReading;
@class ScreenCharArray;
@protocol VT100ScreenMarkReading;
@class iTermPromise<T>;
@class iTermResilientCoordinateRange;
@protocol iTermResilientCoordinateDataSource;
@protocol iTermResilientCoordinateHolder;
@class iTermFoldMark;
@class PortholeMark;

@protocol iTermGenericNamedMarkReading
@property (nonatomic, readonly, nullable, copy) NSString *name;
@property (nonatomic, readonly) NSInteger namedMarkSort;
@property (nonatomic, readonly) NSString *guid;
@end

@protocol iTermMarkDelegate <NSObject>
- (void)markDidBecomeCommandMark:(id<VT100ScreenMarkReading>)mark;
@end

@protocol VT100ScreenMarkReading<NSObject, IntervalTreeImmutableObject, iTermMark, iTermGenericNamedMarkReading>
@property(nonatomic, readonly) BOOL isPrompt;
@property(nonatomic, readonly) NSInteger clearCount;

// Array of CapturedOutput objects.
@property(nonatomic, readonly, nullable) NSArray<id<CapturedOutputReading>> *capturedOutput;

// Return code of command on the line for this mark.
@property(nonatomic, readonly) int code;
@property(nonatomic, readonly) BOOL hasCode;

// First line of the user-typed command for this mark, with PS2 prefixes
// NOT subtracted. Captured at FTCS C-time by extracting the cells between
// commandRange.start and commandRange.end via -commandInRange: (which
// truncates at the first \n). Suitable for single-line UI surfaces
// (context-menu titles, status-bar previews, command-history popover)
// where multi-line text would render badly. For surfaces that need the
// real shell-pasteable command (Share URL, AI command extraction, Copy
// Command, API GetPromptResponse), use -fullCommand instead.
//
// Renamed from -command in PR 4 to force a per-callsite audit; if you're
// porting a callsite from -command, decide whether the consumer wants
// the truncated preview (this property) or the real command
// (-fullCommand).
@property(nonatomic, copy, readonly, nullable) NSString *firstLineOfCommand;

// Multi-line user-typed command with PS2 prefixes (and any other cells
// covered by excludedSubranges) removed. Captured at FTCS C-time by
// walking commandRange cell-by-cell, skipping cells in excludedSubranges,
// and joining rows with \n. The result is shell-paste-back-able: feeding
// it to a fresh shell reproduces the user's input. For pre-PR4
// serialized marks that lack a stored FullCommand key, this falls back
// to -firstLineOfCommand on load.
@property(nonatomic, copy, readonly, nullable) NSString *fullCommand;

// YES iff fullCommand contains at least one character. Prefer this over
// checking firstLineOfCommand.length, because for multi-line input
// captured by the auto-composer (and any future paste-back flow) the
// first line can legitimately be empty while later lines hold the real
// command. Returns NO when there is no command captured at all.
@property(nonatomic, readonly) BOOL hasNonEmptyCommand;

// Time the command was set at (and presumably began running).
@property(nonatomic, strong, readonly, nullable) NSDate *startDate;

// Time the command finished running. nil if no command or if it hasn't finished.
@property(nonatomic, strong, readonly, nullable) NSDate *endDate;

// The session this mark belongs to.
@property(nonatomic, strong, readonly, nullable) NSString *sessionGuid;

@property(nonatomic, readonly) VT100GridAbsCoordRange promptRange;
@property(nonatomic, copy, readonly, nullable) NSArray<ScreenCharArray *> *promptText;
@property(nonatomic, readonly) VT100GridAbsCoordRange commandRange;
@property(nonatomic, readonly) VT100GridAbsCoord outputStart;
@property(nonatomic, readonly) iTermPromise<NSNumber *> *returnCodePromise;
@property(nonatomic, readonly) BOOL promptDetectedByTrigger;
@property(nonatomic, readonly) BOOL lineStyle;
@property(nonatomic, readonly, copy, nullable) NSString *name;

// OSC 133 `k=` kind of the primary `A` that created this mark. Always
// .initial on marks today; the receiver routes non-initial kinds to a
// non-mark-creating path. The field is kept here so future readers know
// which `k=` produced the mark.
@property(nonatomic, readonly) VT100PromptKind kind;

// OSC 133 `aid=` value seen on this mark's primary A / B / C / D markers.
// Identifies one logical command across nested shell-integration sessions
// (the local-shell-then-ssh-to-remote case, REPLs that emit their own
// 133 markers, etc.). nil for marks from shells that don't emit aid (the
// common case) and for marks restored from saved sessions written before
// this field shipped.
@property(nonatomic, readonly, copy, nullable) NSString *aid;

// The aid of the deepest-open command at the moment this mark's first
// OSC 133 marker was processed. Used for cascade-close: when D;aid=outer
// arrives, every still-open mark whose parentAid chain leads back to
// outer also closes (no exit-code claim — just endDate set). Without
// this, a remote shell whose ssh tunnel dies would leak an open mark
// forever.
//
// nil when there was no aid open at first-marker time (top-level commands
// in any session), or when this mark itself has no aid.
@property(nonatomic, readonly, copy, nullable) NSString *parentAid;

// Full chain of ancestor aids, captured at A time (a snapshot of the
// open-aid stack at the moment this mark's first OSC 133 marker was
// processed). Outermost ancestor at index 0; deepest (== parentAid) at
// .lastObject. Used by range-computation consumers that need to ask "is
// X an ancestor of this mark?" without walking the interval tree (which
// would fail under folds or after a parent gets pruned from scrollback).
// nil when this mark itself has no aid or had no open aid above it.
@property(nonatomic, readonly, copy, nullable) NSArray<NSString *> *ancestorAids;

// Cell regions inside the mark's command area that are NOT part of the
// user's typed command (PS2 prefixes on continuation rows, right-prompt
// text). Selection / share-URL / API consumers should subtract these
// from commandRange to get the actual user input. nil when there are
// none (the common case). Each range is half-open [start, end). The
// ResilientCoordinateRange wrapper adjusts these automatically on
// resize / scrollback overflow / fold / porthole / dataSource dealloc.
//
// Restore-time invariant: between IntervalTree graph restore and the
// completion of fixUpDeserializedIntervalTree:, a mark's RCs may be in
// `.unresolved*` states (unbound to a pool, or with an unresolved fold/
// porthole target). The fixup pass binds them to the mutation-thread
// pool's dataSource; the EventuallyConsistentIntervalTree's add hook
// binds the doppelganger's RCs to the main-thread pool. Until that
// completes, status reads return `.unresolved`.
@property(nonatomic, copy, readonly, nullable) NSArray<iTermResilientCoordinateRange *> *excludedSubranges;

@property(nonatomic, readonly) BOOL isRunning;

- (id<VT100ScreenMarkReading>)progenitor;
- (id<VT100ScreenMarkReading>)doppelganger;

@end

// Visible marks that can be navigated.
//
// iTermResilientCoordinateHolder conformance is declared in a class
// extension in VT100ScreenMark.m (which imports the Swift-generated
// header that defines the protocol) rather than here, because this
// header can only forward-declare the protocol and declaring
// conformance against a forward declaration warns ("cannot find
// protocol definition"). The required methods are still declared below.
@interface VT100ScreenMark : iTermMark<VT100ScreenMarkReading, IntervalTreeObject>

@property(nonatomic, readwrite) BOOL isPrompt;

@property(nonatomic, weak, readwrite, nullable) id<iTermMarkDelegate> delegate;

// Return code of command on the line for this mark.
@property(nonatomic, readwrite) int code;

// See the readonly declarations on VT100ScreenMarkReading for semantics.
@property(nonatomic, copy, readwrite, nullable) NSString *firstLineOfCommand;
@property(nonatomic, copy, readwrite, nullable) NSString *fullCommand;

// Time the command was set at (and presumably began running).
@property(nonatomic, strong, readwrite, nullable) NSDate *startDate;

// Time the command finished running. nil if no command or if it hasn't finished.
@property(nonatomic, strong, readwrite, nullable) NSDate *endDate;

// The session this mark belongs to.
@property(nonatomic, strong, readwrite) NSString *sessionGuid;

@property(nonatomic, copy, readwrite, nullable) NSString *name;

@property(nonatomic, readwrite) VT100GridAbsCoordRange promptRange;
@property(nonatomic, copy, nullable) NSArray<ScreenCharArray *> *promptText;
@property(nonatomic, readwrite) VT100GridAbsCoordRange commandRange;
@property(nonatomic, readwrite) VT100GridAbsCoord outputStart;
@property(nonatomic) BOOL promptDetectedByTrigger;
@property(nonatomic) BOOL lineStyle;

@property(nonatomic, readwrite) VT100PromptKind kind;
@property(nonatomic, copy, readwrite, nullable) NSString *aid;
@property(nonatomic, copy, readwrite, nullable) NSString *parentAid;
@property(nonatomic, copy, readwrite, nullable) NSArray<NSString *> *ancestorAids;
@property(nonatomic, copy, readwrite, nullable) NSArray<iTermResilientCoordinateRange *> *excludedSubranges;

// Appends `range` to excludedSubranges (creating the array if nil). The
// appended range is typically unbound; on the doppelganger side the
// EventuallyConsistentIntervalTree's add/mutate hook binds it to the
// main-thread pool's dataSource after the user closure runs.
- (void)appendExcludedSubrange:(iTermResilientCoordinateRange *)range;

// Cascade-close path: the command ended (e.g. its parent ssh died) but
// we have no exit code to report. Settles the returnCodePromise as a
// rejection so awaiters resolve at close-time rather than at dealloc.
// hasCode stays NO; setCode: was not called.
- (void)markAbandoned;

// iTermResilientCoordinateHolder conformance: bind every contained unbound
// ResilientCoordinate to `dataSource`. Declared here (in addition to the
// Swift-side protocol) so Swift call sites that only see this ObjC header
// can invoke it without importing the Swift-generated header (which would
// create an import cycle).
- (void)bindUnresolvedResilientCoordinatesToDataSource:(id<iTermResilientCoordinateDataSource>)dataSource;

// iTermResilientCoordinateHolder conformance: detach every contained
// RC from its current dataSource and rebind to `dataSource`. Used by
// tree migration (swapOnscreenIntervalTreeObjects) so the mark
// observes notifications on the destination tree's pool guid instead
// of the source tree's. Idempotent if the new dataSource equals the
// current one.
- (void)rebindResilientCoordinatesToDataSource:(id<iTermResilientCoordinateDataSource>)dataSource;

// Resolve every contained ResilientCoordinate whose location is
// `.unresolvedFold` / `.unresolvedPorthole`, upgrading them to bound
// `.fold` / `.porthole` references using the supplied lookups. Called
// from fixUpDeserializedIntervalTree: once FoldMark / PortholeMark
// targets have been restored into the same interval tree, so the
// guids stored on each RC can be resolved to actual mark instances.
// Idempotent for RCs that are already resolved or in non-unresolved
// states.
- (void)resolveUnresolvedRCsWithFoldMarkLookup:(iTermFoldMark *_Nullable(^)(NSString *))foldMarkLookup
                            portholeMarkLookup:(PortholeMark *_Nullable(^)(NSString *))portholeMarkLookup;

// Returns a reference to an existing mark with the given GUID.
+ (id<VT100ScreenMarkReading>)markWithGuid:(NSString *)guid
                         forMutationThread:(BOOL)forMutationThread;

// Add an object to self.capturedOutput.
- (void)addCapturedOutput:(CapturedOutput *)capturedOutput;
- (void)incrementClearCount;

- (id<VT100ScreenMarkReading>)doppelganger;

@end

NS_ASSUME_NONNULL_END
