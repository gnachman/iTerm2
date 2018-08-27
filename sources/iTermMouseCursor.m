//
//  iTermCursor.m
//  iTerm
//
//  Created by George Nachman on 5/11/14.
//
//

#import "iTermMouseCursor.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSImage+iTerm.h"

@interface NSCursor ()
// This is an Apple private method that, when overridden, allows you to use
// cursors that are otherwise not available. Using internal cursors is
// preferable because they scale up nicely when "cursor zoom" is enabled in
// accessibility.
- (long long)_coreCursorType;
@end

// These constants are Cocoa's internal values for different cursor types.
// Copied from Chromium's src/content/common/cursors/webcursor_mac.mm.
enum {
    kArrowCursor = 0,
    kIBeamCursor = 1,
    kMakeAliasCursor = 2,
    kOperationNotAllowedCursor = 3,
    kBusyButClickableCursor = 4,
    kCopyCursor = 5,
    kClosedHandCursor = 11,
    kOpenHandCursor = 12,
    kPointingHandCursor = 13,
    kCountingUpHandCursor = 14,
    kCountingDownHandCursor = 15,
    kCountingUpAndDownHandCursor = 16,
    kResizeLeftCursor = 17,
    kResizeRightCursor = 18,
    kResizeLeftRightCursor = 19,
    kCrosshairCursor = 20,
    kResizeUpCursor = 21,
    kResizeDownCursor = 22,
    kResizeUpDownCursor = 23,
    kContextualMenuCursor = 24,
    kDisappearingItemCursor = 25,
    kVerticalIBeamCursor = 26,
    kResizeEastCursor = 27,
    kResizeEastWestCursor = 28,
    kResizeNortheastCursor = 29,
    kResizeNortheastSouthwestCursor = 30,
    kResizeNorthCursor = 31,
    kResizeNorthSouthCursor = 32,
    kResizeNorthwestCursor = 33,
    kResizeNorthwestSoutheastCursor = 34,
    kResizeSoutheastCursor = 35,
    kResizeSouthCursor = 36,
    kResizeSouthwestCursor = 37,
    kResizeWestCursor = 38,
    kMoveCursor = 39,
    kHelpCursor = 40,  // Present on >= 10.7.3.
    kCellCursor = 41,  // Present on >= 10.7.3.
    kZoomInCursor = 42,  // Present on >= 10.7.3.
    kZoomOutCursor = 43  // Present on >= 10.7.3.
};

@implementation iTermMouseCursor {
    long long _type;  // Valid only if _hasImage is NO.
    BOOL _hasImage;
}

+ (instancetype)mouseCursorOfType:(iTermMouseCursorType)cursorType {
    static NSMutableDictionary *cursors;
    @synchronized([iTermMouseCursor class]) {
        if (!cursors) {
            cursors = [[NSMutableDictionary alloc] init];
        }
        if (!cursors[@(cursorType)]) {
            cursors[@(cursorType)] =
                [[[self alloc] initWithType:cursorType] autorelease];
        }
        return cursors[@(cursorType)];
    }
}

- (instancetype)initWithType:(iTermMouseCursorType)cursorType {
    switch (cursorType) {
        case iTermMouseCursorTypeIBeamWithCircle:
            self = [super initWithImage:[NSImage it_imageNamed:@"IBarCursorXMR" forClass:self.class]
                                hotSpot:NSMakePoint(4, 8)];
            if (self) {
                _hasImage = YES;
            }
            break;

        case iTermMouseCursorTypeIBeam:
            if ([iTermAdvancedSettingsModel useSystemCursorWhenPossible]) {
                self = [super init];
                if (self) {
                    _type = kIBeamCursor;
                }
            } else {
                self = [super initWithImage:[NSImage it_imageNamed:@"IBarCursor" forClass:self.class]
                                    hotSpot:NSMakePoint(4, 8)];
                if (self) {
                    _hasImage = YES;
                }
            }
            break;

        case iTermMouseCursorTypeNorthwestSoutheastArrow:
            self = [super init];
            if (self) {
                _type = kResizeNorthwestSoutheastCursor;
            }
            break;

        case iTermMouseCursorTypeArrow:
            self = [super init];
            if (self) {
                _type = kArrowCursor;
            }
            break;

    }
    return self;
}

// This overrides a private API and lets us use otherwise inaccessible system
// cursors.
- (long long)_coreCursorType {
    if (_hasImage) {
        return [super _coreCursorType];
    } else {
        return _type;
    }
}

@end
