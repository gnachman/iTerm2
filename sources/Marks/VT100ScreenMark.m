//
//  VT100ScreenMark.m
//  iTerm
//
//  Created by George Nachman on 12/5/13.
//
//

#import "VT100ScreenMark.h"
#import "CapturedOutput.h"
#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "ScreenCharArray.h"
#import "iTermPromise.h"
#import "iTerm2SharedARC-Swift.h"

static NSString *const kScreenMarkIsPrompt = @"Is Prompt";
static NSString *const kMarkCapturedOutputKey = @"Captured Output";
// Legacy key — maps to firstLineOfCommand for back-compat with pre-PR4
// serialized marks. The new fullCommand value is serialized under
// kMarkFullCommandKey below.
static NSString *const kMarkCommandKey = @"Command";
static NSString *const kMarkFullCommandKey = @"FullCommand";
static NSString *const kMarkCodeKey = @"Code";
static NSString *const kMarkPromptDetectedByTrigger = @"Prompt Detected by Trigger";
static NSString *const kMarkLineStyleKey = @"Line Style";
static NSString *const kMarkHasCode = @"Has Code";
static NSString *const kMarkStartDateKey = @"Start Date";
static NSString *const kMarkEndDateKey = @"End Date";
static NSString *const kMarkNameKey = @"Name";
static NSString *const kMarkSessionGuidKey = @"Session Guid";
// Legacy abs-coord encodings. Kept for back-compat: existing saved
// sessions store the plain VT100GridAbsCoordRange / VT100GridAbsCoord
// shape under these keys. Decode falls back to them when the RC-format
// keys (below) are absent.
static NSString *const kMarkPromptRange = @"Prompt Range";
static NSString *const kMarkPromptText = @"Prompt Text";
static NSString *const kMarkCommandRange = @"Command Range";
static NSString *const kMarkOutputStart = @"Output Start";
// RC-format encodings. Preserve the full ResilientCoordinate Location
// enum (.coord / .fold / .porthole / .invalid + their unresolved twins
// referencing target mark guids). fixUpDeserializedIntervalTree:
// resolves fold/porthole references once the target marks have been
// restored into the same tree.
static NSString *const kMarkPromptRangeRC = @"Prompt Range RC";
static NSString *const kMarkCommandRangeRC = @"Command Range RC";
static NSString *const kMarkOutputStartRC = @"Output Start RC";
static NSString *const kMarkKind = @"Prompt Kind";
static NSString *const kMarkAid = @"Aid";
static NSString *const kMarkParentAid = @"Parent Aid";
static NSString *const kMarkAncestorAids = @"Ancestor Aids";
static NSString *const kMarkExcludedSubranges = @"Excluded Subranges";

// Declare iTermResilientCoordinateHolder conformance here, where the
// Swift-generated header that defines the protocol is imported, instead
// of in VT100ScreenMark.h (which can only forward-declare it).
@interface VT100ScreenMark () <iTermResilientCoordinateHolder>
@end

@implementation VT100ScreenMark {
    NSMutableArray<CapturedOutput *> *_capturedOutput;
    iTermPromise<NSNumber *> *_returnCodePromise;
    id<iTermPromiseSeal> _codeSeal;
    // ResilientCoordinate-backed storage for the public promptRange /
    // commandRange / outputStart fields. nil means "never set" — the
    // getter returns the (-1,-1,...) sentinel in that case. When non-nil
    // these may be either unbound (created by the setter before the mark
    // is added to a tree) or bound to a pool's data source (after
    // bindUnresolvedResilientCoordinatesToDataSource: runs).
    iTermResilientCoordinateRange *_promptRangeRC;
    iTermResilientCoordinateRange *_commandRangeRC;
    iTermResilientCoordinate *_outputStartRC;
}

@synthesize isPrompt = _isPrompt;
@synthesize clearCount = _clearCount;
@synthesize capturedOutput = _capturedOutput;
@synthesize code = _code;
@synthesize promptDetectedByTrigger = _promptDetectedByTrigger;
@synthesize lineStyle = _lineStyle;
@synthesize hasCode = _hasCode;
@synthesize firstLineOfCommand = _firstLineOfCommand;
@synthesize fullCommand = _fullCommand;
@synthesize startDate = _startDate;
@synthesize name = _name;
@synthesize endDate = _endDate;
@synthesize sessionGuid = _sessionGuid;
@synthesize promptText = _promptText;
@synthesize kind = _kind;
@synthesize aid = _aid;
@synthesize parentAid = _parentAid;
@synthesize ancestorAids = _ancestorAids;
@synthesize excludedSubranges = _excludedSubranges;

+ (NSMapTable *)registry {
    static NSMapTable *registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [[NSMapTable alloc] initWithKeyOptions:(NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality)
                                             valueOptions:(NSPointerFunctionsWeakMemory | NSPointerFunctionsOpaquePersonality)
                                                 capacity:1024];
    });
    return registry;
}

+ (id<VT100ScreenMarkReading>)markWithGuid:(NSString *)guid
                         forMutationThread:(BOOL)forMutationThread {
    @synchronized([VT100ScreenMark class]) {
        VT100ScreenMark *mark = [self.registry objectForKey:guid];
        if (forMutationThread) {
            return mark;
        }
        return [mark doppelganger];
    }
}

- (instancetype)init {
    return [self initRegistered:YES];
}

- (instancetype)initRegistered:(BOOL)shouldRegister {
    self = [super init];
    if (self) {
        if (shouldRegister) {
            @synchronized([VT100ScreenMark class]) {
                [[self.class registry] setObject:self forKey:self.guid];
            }
        }
        // ARC zero-inits the RC ivars; their nil-means-sentinel getters
        // already produce (-1,-1) without explicit initialization here.

        // .unknown is "this field doesn't apply" — VT100ScreenMark is also
        // used for non-prompt user bookmarks (Edit > Set Mark). Prompt marks
        // override this in setPromptStartLine:.
        _kind = VT100PromptKindUnknown;
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    return [self initWithDictionary:dict shouldRegister:YES];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict shouldRegister:(BOOL)shouldRegister {
    self = [super initWithDictionary:dict];
    if (self) {
        _code = [dict[kMarkCodeKey] intValue];
        _promptDetectedByTrigger = [dict[kMarkPromptDetectedByTrigger] boolValue];
        _lineStyle = [dict[kMarkLineStyleKey] boolValue];
        _hasCode = [dict[kMarkHasCode] boolValue];
        if (_code && !_hasCode) {
            // Not so great way of migrating old marks. Misses those with a value of 0 :(
            _hasCode = YES;
        }
        _isPrompt = [dict[kScreenMarkIsPrompt] boolValue];
        _sessionGuid = [dict[kMarkSessionGuidKey] copy];
        NSTimeInterval start = [dict[kMarkStartDateKey] doubleValue];
        if (start > 0) {
            _startDate = [NSDate dateWithTimeIntervalSinceReferenceDate:start];
        }
        NSTimeInterval end = [dict[kMarkEndDateKey] doubleValue];
        if (end > 0) {
            _endDate = [NSDate dateWithTimeIntervalSinceReferenceDate:end];
        }
        _name = [dict[kMarkNameKey] copy];
        NSMutableArray *array = [NSMutableArray array];
        _capturedOutput = array;
        for (NSDictionary *capturedOutputDict in dict[kMarkCapturedOutputKey]) {
            [array addObject:[CapturedOutput capturedOutputWithDictionary:capturedOutputDict]];
        }
        if ([dict[kMarkCommandKey] isKindOfClass:[NSString class]]) {
            _firstLineOfCommand = [dict[kMarkCommandKey] copy];
        }
        if ([dict[kMarkFullCommandKey] isKindOfClass:[NSString class]]) {
            _fullCommand = [dict[kMarkFullCommandKey] copy];
        } else {
            // Pre-PR4 marks didn't capture fullCommand. Fall back to the
            // first-line value so consumers that newly switch to
            // fullCommand still get something sensible (just missing the
            // multi-line PS2 stripping).
            _fullCommand = [_firstLineOfCommand copy];
        }
        // Decoded RCs are always unbound — fixUpDeserializedIntervalTree:
        // calls bindUnresolvedResilientCoordinatesToDataSource: on the
        // mutation-thread side, and the doppelganger gets bound by the
        // tree's add hook on the main thread. Pre-feature dicts without
        // these keys leave the corresponding RC nil; the getter returns
        // the sentinel.
        //
        // Prefer the RC-format keys (which preserve .fold / .porthole /
        // .invalid). Fall back to the legacy abs-coord keys when the RC
        // keys are missing — that's how older saved sessions encoded the
        // three fields, and we still load them.
        if ([dict[kMarkPromptRangeRC] isKindOfClass:[NSDictionary class]]) {
            _promptRangeRC = [iTermResilientCoordinateRange rangeFromDictionary:dict[kMarkPromptRangeRC]];
        } else if (dict[kMarkPromptRange]) {
            const VT100GridAbsCoordRange r = [dict[kMarkPromptRange] gridAbsCoordRange];
            _promptRangeRC = [[iTermResilientCoordinateRange alloc] initUnboundWithAbsRange:r];
        }
        if (dict[kMarkPromptText]) {
            NSArray<NSDictionary *> *dicts = dict[kMarkPromptText];
            _promptText = [dicts mapWithBlock:^id _Nullable(NSDictionary * _Nonnull dict) {
                return [[ScreenCharArray alloc] initWithDictionary:dict];
            }];
        } else {
            _promptText = nil;
        }
        if ([dict[kMarkCommandRangeRC] isKindOfClass:[NSDictionary class]]) {
            _commandRangeRC = [iTermResilientCoordinateRange rangeFromDictionary:dict[kMarkCommandRangeRC]];
        } else if (dict[kMarkCommandRange]) {
            const VT100GridAbsCoordRange r = [dict[kMarkCommandRange] gridAbsCoordRange];
            _commandRangeRC = [[iTermResilientCoordinateRange alloc] initUnboundWithAbsRange:r];
        }
        if ([dict[kMarkOutputStartRC] isKindOfClass:[NSDictionary class]]) {
            _outputStartRC = [iTermResilientCoordinate coordinateFromDictionary:dict[kMarkOutputStartRC]];
        } else if (dict[kMarkOutputStart]) {
            const VT100GridAbsCoord c = [dict[kMarkOutputStart] gridAbsCoord];
            _outputStartRC = [[iTermResilientCoordinate alloc] initUnboundWithAbsCoord:c];
        }
        if (dict[kMarkKind]) {
            // Clamp to the known enum range. A future writer may emit a
            // value outside VT100PromptKind (corrupt file, version skew,
            // future enum addition that this build doesn't know about);
            // coerce to .unknown rather than letting a bogus integer leak
            // into consumers' code paths.
            const NSInteger raw = [dict[kMarkKind] integerValue];
            if (raw >= VT100PromptKindInitial && raw <= VT100PromptKindUnknown) {
                _kind = (VT100PromptKind)raw;
            } else {
                _kind = VT100PromptKindUnknown;
            }
        } else {
            // Pre-feature dicts don't store kind. We over-broadly infer
            // .initial for any isPrompt=YES mark, but consumers should
            // treat .initial on a legacy mark as "primary prompt mark of
            // unspecified provenance" rather than "an OSC 133;A definitely
            // fired" — there are other paths that set isPrompt=YES (some
            // trigger flows, FinalTerm OSC 1337 shell integration) that
            // didn't go through setPromptStartLine:. Non-prompt user
            // bookmarks load with .unknown — the field doesn't apply.
            _kind = _isPrompt ? VT100PromptKindInitial : VT100PromptKindUnknown;
        }
        // OSC 133 aid= / parentAid. Skipped when nil on write (no key set
        // in dict); on load we accept the key but only when it's a string.
        // Pre-feature dicts and shells that never emit aid both produce nil.
        if ([dict[kMarkAid] isKindOfClass:[NSString class]]) {
            _aid = [dict[kMarkAid] copy];
        }
        if ([dict[kMarkParentAid] isKindOfClass:[NSString class]]) {
            _parentAid = [dict[kMarkParentAid] copy];
        }
        if ([dict[kMarkAncestorAids] isKindOfClass:[NSArray class]]) {
            NSArray *raw = dict[kMarkAncestorAids];
            NSMutableArray<NSString *> *strings = [NSMutableArray array];
            for (id obj in raw) {
                if ([obj isKindOfClass:[NSString class]]) {
                    [strings addObject:[obj copy]];
                }
            }
            _ancestorAids = strings.count > 0 ? [strings copy] : nil;
        }
        NSArray *excludedDicts = dict[kMarkExcludedSubranges];
        if ([excludedDicts isKindOfClass:[NSArray class]] && excludedDicts.count > 0) {
            // Decoded RCs come back unbound (`.unresolvedCoord` /
            // `.unresolvedFold` / `.unresolvedPorthole` / `.invalid`).
            // fixUpDeserializedIntervalTree: binds them to the
            // mutation-thread pool's dataSource (via the holder protocol)
            // and resolves any fold/porthole targets in a second pass.
            // The EventuallyConsistentIntervalTree's add hook binds the
            // doppelganger's copies to the main-thread pool.
            NSMutableArray<iTermResilientCoordinateRange *> *ranges = [NSMutableArray array];
            for (NSDictionary *d in excludedDicts) {
                if (![d isKindOfClass:[NSDictionary class]]) {
                    continue;
                }
                iTermResilientCoordinateRange *rcRange =
                    [iTermResilientCoordinateRange rangeFromDictionary:d];
                if (rcRange) {
                    [ranges addObject:rcRange];
                }
            }
            _excludedSubranges = ranges.count > 0 ? [ranges copy] : nil;
        } else {
            _excludedSubranges = nil;
        }
        if (shouldRegister) {
            @synchronized([VT100ScreenMark class]) {
                [[self.class registry] setObject:self forKey:self.guid];
            }
        }
    }
    return self;
}

// Note that this assumes the copy will be a doppelganger (since it uses CapturedOutput doppelgangers).
- (instancetype)copyWithZone:(NSZone *)zone {
    assert(!self.isDoppelganger);

    // Doppelgangers should not be registered. They take the GUID of the progenitor.
    VT100ScreenMark *mark = [[VT100ScreenMark alloc] initRegistered:NO];

    mark->_code = _code;
    mark->_promptDetectedByTrigger = _promptDetectedByTrigger;
    mark->_lineStyle = _lineStyle;
    mark->_hasCode = _hasCode;
    mark->_isPrompt = _isPrompt;
    [mark copyGuidFrom:self];
    mark->_sessionGuid = [_sessionGuid copy];
    mark->_startDate = _startDate;
    mark->_name = [_name copy];
    mark->_endDate = _endDate;
    mark->_capturedOutput = [[_capturedOutput mapWithBlock:^id(CapturedOutput *capturedOutput) {
        return [capturedOutput doppelganger];
    }] mutableCopy];
    mark->_firstLineOfCommand = [_firstLineOfCommand copy];
    mark->_fullCommand = [_fullCommand copy];
    // Doppelganger pool segregation: clone each RC field via -unboundCopy
    // so the main-thread side holds its own RC (not the progenitor's
    // mutation-pool RC). The EventuallyConsistentIntervalTree's add hook
    // calls bindUnresolvedResilientCoordinatesToDataSource: with the
    // main-thread pool's DS after this copy returns, finishing the bind.
    mark->_promptRangeRC = [_promptRangeRC unboundCopy];
    mark->_promptText = [_promptText copy];
    mark->_commandRangeRC = [_commandRangeRC unboundCopy];
    mark->_outputStartRC = [_outputStartRC unboundCopy];
    mark->_kind = _kind;
    mark->_aid = [_aid copy];
    mark->_parentAid = [_parentAid copy];
    mark->_ancestorAids = [_ancestorAids copy];

    // Doppelganger pool segregation: the doppelganger must NOT share the
    // progenitor's mutation-thread ResilientCoordinateRanges (a main-thread
    // read of mark.excludedSubranges[i].absRange would race the mutation
    // thread's resize / clear-to-end handlers). Produce structural unbound
    // twins via `-unboundCopy`: `.coord` becomes `.unresolvedCoord`,
    // fold/porthole stay structurally identical with the same WeakBox.
    // The EventuallyConsistentIntervalTree's add side effect then calls
    // `bindUnresolvedResilientCoordinatesToDataSource:` with the main-thread
    // pool's dataSource, finishing the bind on the main thread.
    if (_excludedSubranges.count > 0) {
        NSMutableArray<iTermResilientCoordinateRange *> *unbound =
            [NSMutableArray arrayWithCapacity:_excludedSubranges.count];
        for (iTermResilientCoordinateRange *src in _excludedSubranges) {
            [unbound addObject:[src unboundCopy]];
        }
        mark->_excludedSubranges = [unbound copy];
    } else {
        mark->_excludedSubranges = nil;
    }

    return mark;
}

// MARK: - promptRange / commandRange / outputStart (RC-backed)

// Translate a coord whose value came back from RC as invalid
// (VT100GridAbsCoordInvalid: INT_MIN / LONG_LONG_MIN) into the legacy
// (-1, -1) sentinel that consumers gate on (start.x >= 0). Valid coords
// pass through unchanged.
static VT100GridAbsCoord SentinelizeAbsCoord(VT100GridAbsCoord c) {
    if (c.x == VT100GridAbsCoordInvalid.x && c.y == VT100GridAbsCoordInvalid.y) {
        return VT100GridAbsCoordMake(-1, -1);
    }
    return c;
}

static VT100GridAbsCoordRange SentinelizeAbsRange(VT100GridAbsCoordRange r) {
    const VT100GridAbsCoord s = SentinelizeAbsCoord(r.start);
    const VT100GridAbsCoord e = SentinelizeAbsCoord(r.end);
    return VT100GridAbsCoordRangeMake(s.x, s.y, e.x, e.y);
}

// YES if the RC currently points at content consumers can act on.
//
// `StatusValid` and `StatusUnresolved` (the just-after-setter case) are
// trivially usable.
//
// `StatusScrolledOff` / `StatusTruncatedBelow` / `StatusInFold` /
// `StatusInPorthole` mean the row is no longer in the live buffer or
// the location can't be resolved to an abs row — return sentinel.
// Matches the pre-migration behavior where the explicit resize
// handler reset outputStart to (-1, -1) when the abs fell out of the
// linebuffer.
//
// `StatusInvalid` is overloaded by ResilientCoordinate: it surfaces
// both when the location truly is `.invalid` (dataSource gone or
// explicitly invalidated) AND when the location is `.coord(c)` but
// `c.x` is out of `[0, rcWidth)`. promptRange / commandRange use
// exclusive end coords, so `end.x == width` is a legitimate value
// that incorrectly trips the x bounds check. Disambiguate by
// inspecting `bestEffortAbsCoord`: it returns the real abs for
// `.coord` (the "x at width" case), and `VT100GridAbsCoordInvalid`
// for the truly-invalid case. The first is usable; the second isn't.
static BOOL IT_RC_STATUS_IS_USABLE(iTermResilientCoordinate *rc) {
    switch (rc.status) {
        case StatusValid:
        case StatusUnresolved:
            return YES;
        case StatusScrolledOff:
        case StatusTruncatedBelow:
        case StatusInFold:
        case StatusInPorthole:
            return NO;
        case StatusInvalid: {
            const VT100GridAbsCoord c = rc.bestEffortAbsCoord;
            return !(c.x == VT100GridAbsCoordInvalid.x &&
                     c.y == VT100GridAbsCoordInvalid.y);
        }
    }
    return NO;
}

- (VT100GridAbsCoordRange)promptRange {
    if (!_promptRangeRC) {
        return VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
    }
    // bestEffortAbsRange returns the abs we set even before the RC has
    // been bound to a data source, satisfying setter-then-getter
    // roundtrips. After binding, valid coords return the shifted abs;
    // non-usable statuses (scrolled off, in fold, etc.) collapse to the
    // (-1, -1) sentinel.
    if (!IT_RC_STATUS_IS_USABLE(_promptRangeRC.start) ||
        !IT_RC_STATUS_IS_USABLE(_promptRangeRC.end)) {
        return VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
    }
    return SentinelizeAbsRange(_promptRangeRC.bestEffortAbsRange);
}

- (void)setPromptRange:(VT100GridAbsCoordRange)range {
    _promptRangeRC =
        [[iTermResilientCoordinateRange alloc] initUnboundWithAbsRange:range];
}

- (VT100GridAbsCoordRange)commandRange {
    if (!_commandRangeRC) {
        return VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
    }
    if (!IT_RC_STATUS_IS_USABLE(_commandRangeRC.start) ||
        !IT_RC_STATUS_IS_USABLE(_commandRangeRC.end)) {
        return VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
    }
    return SentinelizeAbsRange(_commandRangeRC.bestEffortAbsRange);
}

- (void)setCommandRange:(VT100GridAbsCoordRange)range {
    _commandRangeRC =
        [[iTermResilientCoordinateRange alloc] initUnboundWithAbsRange:range];
}

- (VT100GridAbsCoord)outputStart {
    if (!_outputStartRC) {
        return VT100GridAbsCoordMake(-1, -1);
    }
    if (!IT_RC_STATUS_IS_USABLE(_outputStartRC)) {
        return VT100GridAbsCoordMake(-1, -1);
    }
    return SentinelizeAbsCoord(_outputStartRC.bestEffortAbsCoord);
}

- (void)setOutputStart:(VT100GridAbsCoord)coord {
    _outputStartRC = [[iTermResilientCoordinate alloc] initUnboundWithAbsCoord:coord];
}

// MARK: - iTermResilientCoordinateHolder

- (void)bindUnresolvedResilientCoordinatesToDataSource:(id<iTermResilientCoordinateDataSource>)dataSource {
    // Idempotent: already-bound RCs are no-op'd by -[ResilientCoordinate
    // bindToDataSource:]. Called once on the progenitor by
    // fixUpDeserializedIntervalTree: (with the mutation-thread DS) and
    // once on each newly-minted doppelganger by EventuallyConsistentIntervalTree's
    // add/mutate hook (with the main-thread DS).
    for (iTermResilientCoordinateRange *rcRange in _excludedSubranges) {
        [rcRange bindToDataSource:dataSource];
    }
    [_promptRangeRC bindToDataSource:dataSource];
    [_commandRangeRC bindToDataSource:dataSource];
    [_outputStartRC bindToDataSource:dataSource];
}

- (void)rebindResilientCoordinatesToDataSource:(id<iTermResilientCoordinateDataSource>)dataSource {
    // Detach each RC from its current dataSource (if any) and re-bind
    // to `dataSource`. Called by interval-tree migration code (e.g.
    // swapOnscreenIntervalTreeObjects) so the mark's RCs start
    // observing the destination tree's pool guid.
    for (iTermResilientCoordinateRange *rcRange in _excludedSubranges) {
        [rcRange rebindToDataSource:dataSource];
    }
    [_promptRangeRC rebindToDataSource:dataSource];
    [_commandRangeRC rebindToDataSource:dataSource];
    [_outputStartRC rebindToDataSource:dataSource];
}

- (void)resolveUnresolvedRCsWithFoldMarkLookup:(iTermFoldMark *_Nullable(^)(NSString *))foldMarkLookup
                            portholeMarkLookup:(PortholeMark *_Nullable(^)(NSString *))portholeMarkLookup {
    for (iTermResilientCoordinateRange *rcRange in _excludedSubranges) {
        [rcRange resolveUnresolvedWithFoldMarkLookup:foldMarkLookup
                                  portholeMarkLookup:portholeMarkLookup];
    }
    [_promptRangeRC resolveUnresolvedWithFoldMarkLookup:foldMarkLookup
                                     portholeMarkLookup:portholeMarkLookup];
    [_commandRangeRC resolveUnresolvedWithFoldMarkLookup:foldMarkLookup
                                      portholeMarkLookup:portholeMarkLookup];
    [_outputStartRC resolveUnresolvedWithFoldMarkLookup:foldMarkLookup
                                     portholeMarkLookup:portholeMarkLookup];
}

- (void)dealloc {
    // If the promise was created but setCode: was never called (e.g., session terminated while a
    // command was running), reject it so iTermPromiseSeal's dealloc assertion doesn't fire.
    // Hop to the main queue: dealloc can run on any thread, but observers (e.g.
    // CommandInfoViewController) consume the promise via raw then:/catchError: which deliver
    // callbacks synchronously on the rejecting thread. The seal retains its promise, so capturing
    // it keeps both alive until the block runs.
    id<iTermPromiseSeal> seal = _codeSeal;
    _codeSeal = nil;
    if (seal) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [seal rejectWithDefaultError];
        });
    }
    @synchronized([VT100ScreenMark class]) {
        // I think this is not needed because we use weak pointers but I also don't trust
        // NSMapTable to ever remove dead objects. Do this to avoid a possible waste of memory.
        [[self.class registry] removeObjectForKey:self.guid];
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p guid=%@ lineStyle=%@ name=%@ command=%@ name=%@ %@>",
            NSStringFromClass([self class]),
            self,
            self.guid,
            @(_lineStyle),
            _name,
            _firstLineOfCommand,
            _name,
            self.isDoppelganger ? @"IsDop" : @"NotDop"];
}

- (NSInteger)namedMarkSort {
    return self.entry.interval.location;
}


- (NSArray *)capturedOutputDictionaries {
    NSMutableArray *array = [NSMutableArray array];
    for (CapturedOutput *capturedOutput in _capturedOutput) {
        [array addObject:capturedOutput.dictionaryValue];
    }
    return array;
}

- (NSDictionary *)dictionaryValue {
    NSMutableDictionary *dict = [[super dictionaryValue] mutableCopy];
    dict[kScreenMarkIsPrompt] = @(_isPrompt);
    dict[kMarkCapturedOutputKey] = [self capturedOutputDictionaries];
    dict[kMarkHasCode] = @(_hasCode);
    dict[kMarkCodeKey] = @(_code);
    dict[kMarkPromptDetectedByTrigger] = @(_promptDetectedByTrigger);
    dict[kMarkLineStyleKey] = @(_lineStyle);
    if (_firstLineOfCommand) {
        dict[kMarkCommandKey] = _firstLineOfCommand;
    }
    if (_fullCommand) {
        dict[kMarkFullCommandKey] = _fullCommand;
    }
    dict[kMarkStartDateKey] = @([self.startDate timeIntervalSinceReferenceDate]);
    if (_name) {
        dict[kMarkNameKey] = _name;
    }
    dict[kMarkEndDateKey] = @([self.endDate timeIntervalSinceReferenceDate]);
    if (self.sessionGuid) {
        dict[kMarkSessionGuidKey] = self.sessionGuid;
    }
    dict[kMarkPromptText] = [_promptText mapWithBlock:^id _Nullable(ScreenCharArray *sca) {
        return sca.dictionaryValue;
    }];
    // RC-format encoding preserves the full Location enum (.coord /
    // .fold / .porthole / .invalid). Decoders still accept the legacy
    // kMarkPromptRange / kMarkCommandRange / kMarkOutputStart abs-coord
    // keys (for pre-feature saved sessions) but we no longer write them:
    // they collapse fold/porthole references to (-1, -1) via the getter,
    // which would silently drop data on a fold-folded save reloaded by an
    // older build, AND they're redundant on every same-version reload.
    if (_promptRangeRC) {
        dict[kMarkPromptRangeRC] = _promptRangeRC.dictionaryValue;
    }
    if (_commandRangeRC) {
        dict[kMarkCommandRangeRC] = _commandRangeRC.dictionaryValue;
    }
    if (_outputStartRC) {
        dict[kMarkOutputStartRC] = _outputStartRC.dictionaryValue;
    }
    // Always write kind so post-feature dicts can carry .initial / .unknown /
    // future values explicitly. Pre-feature dicts (missing the key) load
    // with the inferred default based on isPrompt — see initWithDictionary.
    dict[kMarkKind] = @(_kind);
    // aid / parentAid are skipped when nil (the common case) to keep the
    // dict small. Non-nil values round-trip as plain strings.
    if (_aid) {
        dict[kMarkAid] = _aid;
    }
    if (_parentAid) {
        dict[kMarkParentAid] = _parentAid;
    }
    if (_ancestorAids.count > 0) {
        dict[kMarkAncestorAids] = _ancestorAids;
    }
    if (_excludedSubranges.count > 0) {
        // Codable-backed encode preserves the full Location enum — `.coord`
        // / `.fold` / `.porthole` / `.unresolved*` / `.invalid` — including
        // the guid of the FoldMark / PortholeMark a fold or porthole
        // endpoint points at. Decoding re-creates `.unresolved*` cases that
        // fixUpDeserializedIntervalTree: resolves once the target marks
        // have been restored into the same interval tree.
        NSMutableArray<NSDictionary *> *ranges = [NSMutableArray array];
        for (iTermResilientCoordinateRange *rcRange in _excludedSubranges) {
            [ranges addObject:rcRange.dictionaryValue];
        }
        dict[kMarkExcludedSubranges] = ranges;
    }

    return dict;
}

- (void)appendExcludedSubrange:(iTermResilientCoordinateRange *)range {
    // VT100ScreenMark intentionally does NOT implement -generation. The
    // IntervalTree graph encoder treats marks without that method as
    // iTermGenerationAlwaysEncode (see -encodeWithGraphEncoder: in
    // IntervalTree.m's gen lookup for IntervalTreeObject classes), so any
    // append to excludedSubranges is automatically picked up by the next
    // save pass. No explicit counter bump needed.
    if (_excludedSubranges) {
        _excludedSubranges = [_excludedSubranges arrayByAddingObject:range];
    } else {
        _excludedSubranges = @[range];
    }
}

- (void)addCapturedOutput:(CapturedOutput *)capturedOutput {
    if (!_capturedOutput) {
        _capturedOutput = [[NSMutableArray alloc] init];
    } else if ([self mergeCapturedOutputIfPossible:capturedOutput]) {
        return;
    }
    [_capturedOutput addObject:capturedOutput];
}

- (BOOL)mergeCapturedOutputIfPossible:(CapturedOutput *)capturedOutput {
    CapturedOutput *last = _capturedOutput.lastObject;
    if (![last canMergeFrom:capturedOutput]) {
        return NO;
    }
    [last mergeFrom:capturedOutput];
    return YES;
}

- (void)setFirstLineOfCommand:(NSString *)command {
    RLog(@"Set firstLineOfCommand of %@ to %@", self.guid, command);
    if (!_firstLineOfCommand) {
        // Mark just became a command mark; notify exactly once. The
        // fullCommand setter doesn't re-fire because both fields are
        // populated together at FTCS C-time and the second setter sees
        // _firstLineOfCommand already set on entry.
        [self.delegate markDidBecomeCommandMark:self];
    }
    _firstLineOfCommand = [command copy];
    self.startDate = [NSDate date];
}

- (void)setFullCommand:(NSString *)command {
    RLog(@"Set fullCommand of %@ to %@", self.guid, command);
    _fullCommand = [command copy];
}

- (void)setCode:(int)code {
    _code = code;
    _hasCode = YES;
    [_codeSeal fulfill:@(code)];
    _codeSeal = nil;
}

- (void)markAbandoned {
    // No exit code to report — the command's parent died and we're
    // cascade-closing. Settle the promise as a rejection so awaiters
    // resolve now instead of waiting until dealloc.
    RLog(@"markAbandoned: %@ aid=%@ hadSeal=%@",
         self.guid, _aid, @(_codeSeal != nil));
    id<iTermPromiseSeal> seal = _codeSeal;
    _codeSeal = nil;
    [seal rejectWithDefaultError];
}

- (void)incrementClearCount {
    _clearCount += 1;
}

- (id<VT100ScreenMarkReading>)doppelganger {
    return (id<VT100ScreenMarkReading>)[super doppelganger];
}

- (NSString *)shortDebugDescription {
    return [NSString stringWithFormat:@"[ScreenMark prompt=%@ code=%@ cmd=%@]",
            @(_isPrompt), @(_code), _firstLineOfCommand];
}


- (iTermPromise<NSNumber *> *)returnCodePromise {
    if (!_returnCodePromise) {
        _returnCodePromise = [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
            _codeSeal = seal;
        }];
    }
    return _returnCodePromise;
}

- (BOOL)hasNonEmptyCommand {
    return _fullCommand.length > 0;
}

- (BOOL)isRunning {
    return self.hasNonEmptyCommand && _endDate == nil;
}

@end
