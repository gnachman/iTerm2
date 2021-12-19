//
//  VT100ScreenState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/10/21.
//

#import "VT100ScreenState.h"

#import "IntervalTree.h"
#import "iTermOrderEnforcer.h"
#import "NSDictionary+iTerm.h"

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
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[VT100ScreenMutableState alloc] initWithState:self];
}

- (id<VT100ScreenState>)copy {
    return [self copyWithZone:nil];
}

@end
