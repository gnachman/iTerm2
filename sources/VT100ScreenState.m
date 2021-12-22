//
//  VT100ScreenState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/10/21.
//

#import "VT100ScreenState.h"

#import "IntervalTree.h"
#import "iTermOrderEnforcer.h"
#import "LineBuffer.h"
#import "NSDictionary+iTerm.h"

static const int kDefaultMaxScrollbackLines = 1000;

@implementation VT100ScreenMutableState

- (instancetype)init {
    self = [super init];
    if (self) {
        _animatedLines = [NSMutableIndexSet indexSet];
        _setWorkingDirectoryOrderEnforcer = [[iTermOrderEnforcer alloc] init];
        _currentDirectoryDidChangeOrderEnforcer = [[iTermOrderEnforcer alloc] init];
        _intervalTree = [[IntervalTree alloc] init];
        _savedIntervalTree = [[IntervalTree alloc] init];
        _findContext = [[FindContext alloc] init];
        _commandStartCoord = VT100GridAbsCoordMake(-1, -1);
        _markCache = [[NSMutableDictionary alloc] init];
        _maxScrollbackLines = kDefaultMaxScrollbackLines;
        _tabStops = [[NSMutableSet alloc] init];
        _charsetUsesLineDrawingMode = [NSMutableSet set];
        _cursorVisible = YES;
        _lastCommandOutputRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        _startOfRunningCommandOutput = VT100GridAbsCoordMake(-1, -1);
        _initialSize = VT100GridSizeMake(-1, -1);
        _linebuffer = [[LineBuffer alloc] init];
        _colorMap = [[iTermColorMap alloc] init];
        _temporaryDoubleBuffer = [[iTermTemporaryDoubleBufferedGridController alloc] init];
        _fakePromptDetectedAbsLine = -1;
    }
    return self;
}

- (instancetype)initWithState:(VT100ScreenMutableState *)source {
    self = [super init];
    if (self) {
        _audibleBell = source.audibleBell;
        _showBellIndicator = source.showBellIndicator;
        _flashBell = source.flashBell;
        _postUserNotifications = source.postUserNotifications;
        _cursorBlinks = source.cursorBlinks;
        _collectInputForPrinting = source.collectInputForPrinting;
        _printBuffer = [source.printBuffer copy];
        _allowTitleReporting = source.allowTitleReporting;
        _lastBell = source.lastBell;
        _wraparoundMode = source.wraparoundMode;
        _ansi = source.ansi;
        _insert = source.insert;
        _unlimitedScrollback = source.unlimitedScrollback;
        _scrollbackOverflow = source.scrollbackOverflow;
        _commandStartCoord = source.commandStartCoord;
        _maxScrollbackLines = source.maxScrollbackLines;
        _savedFindContextAbsPos = source.savedFindContextAbsPos;
        _lastCharacter = source.lastCharacter;
        _lastCharacterIsDoubleWidth = source.lastCharacterIsDoubleWidth;
        _lastExternalAttribute = source.lastExternalAttribute;
        _saveToScrollbackInAlternateScreen = source.saveToScrollbackInAlternateScreen;
        _cursorVisible = source.cursorVisible;
        _shellIntegrationInstalled = source.shellIntegrationInstalled;
        _lastCommandOutputRange = source.lastCommandOutputRange;
        _currentPromptRange = source.currentPromptRange;
        _startOfRunningCommandOutput = source.startOfRunningCommandOutput;
        _protectedMode = source.protectedMode;
        _initialSize = source.initialSize;
        _cumulativeScrollbackOverflow = source.cumulativeScrollbackOverflow;
        _trackCursorLineMovement = source.trackCursorLineMovement;
        _appendToScrollbackWithStatusBar = source.appendToScrollbackWithStatusBar;
        _normalization = source.normalization;
        _fakePromptDetectedAbsLine = source.fakePromptDetectedAbsLine;

        _intervalTreeObserver = source.intervalTreeObserver;
#warning TODO: I need a read-only protocol for VT100ScreenMark
        _lastCommandMark = [source.lastCommandMark copy];

        _linebuffer = [source.linebuffer copy];
        [source.markCache enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id<iTermMark>  _Nonnull obj, BOOL * _Nonnull stop) {
            NSDictionary *encoded = [obj dictionaryValue];
            Class theClass = [obj class];
            // TODO: This is going to be really slow. Marks being mutable is going to be a problem.
            // I think that very few kinds of marks are actually mutable, and in those cases a journal
            // might provide a cheap way to update an existing copy.
            self.markCache[key] = [[theClass alloc] initWithDictionary:encoded];
        }];

        _animatedLines = [source.animatedLines copy];
        _pasteboardString = [source.pasteboardString copy];
        _intervalTree = [source.intervalTree copy];
        _savedIntervalTree = [source.savedIntervalTree copy];
        _findContext = [source.findContext copy];
        _tabStops = [source.tabStops copy];
        _charsetUsesLineDrawingMode = [source.charsetUsesLineDrawingMode copy];
        _colorMap = [source.colorMap copy];
        _temporaryDoubleBuffer = [source.temporaryDoubleBuffer copy];
    }
    return self;
}

- (void)dealloc {
    [_temporaryDoubleBuffer reset];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[VT100ScreenMutableState alloc] initWithState:self];
}

- (id<VT100ScreenState>)copy {
    return [self copyWithZone:nil];
}

@end
