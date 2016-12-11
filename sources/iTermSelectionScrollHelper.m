//
//  iTermSelectionScrollHelper.m
//  iTerm2
//
//  Created by George Nachman on 11/24/14.
//
//

#import "iTermSelectionScrollHelper.h"
#import "iTermAdvancedSettingsModel.h"
#import "DebugLogging.h"
#import "PTYTextView.h"

typedef NS_ENUM(NSInteger, iTermSelectionScrollDirection) {
    kiTermSelectionScrollDirectionStopped = 0,
    kiTermSelectionScrollDirectionUp = -1,
    kiTermSelectionScrollDirectionDown = 1
};

@implementation iTermSelectionScrollHelper {
    // Indicates if a selection that scrolls the window is in progress.
    // Negative value: scroll up.
    // Positive value: scroll down.
    // Zero: don't scroll.
    iTermSelectionScrollDirection _selectionScrollDirection;
    NSTimeInterval _lastSelectionScroll;

    // Scrolls view when you drag a selection to top or bottom of view.
    BOOL _scrolling;
    double _prevScrollDelay;
    VT100GridCoord _scrollingCoord;
    NSPoint _scrollingLocation;
}

- (void)scheduleSelectionScroll {
    if (_scrolling) {
        if (_prevScrollDelay > 0.001) {
            // Maximum speed hasn't been reached so accelerate scrolling speed by 5%.
            _prevScrollDelay *= 0.95;
        }
    } else {
        // Set a slow initial scrolling speed.
        _prevScrollDelay = 0.1;
    }

    _lastSelectionScroll = [[NSDate date] timeIntervalSince1970];
    _scrolling = YES;
    [self performSelector:@selector(updateSelectionScroll) withObject:nil afterDelay:_prevScrollDelay];
}

// Scroll the screen up or down a line for a selection drag scroll.
- (void)updateSelectionScroll {
    double actualDelay = [[NSDate date] timeIntervalSince1970] - _lastSelectionScroll;
    const int kMaxLines = 100;
    int numLines = MIN(kMaxLines, MAX(1, actualDelay / _prevScrollDelay));
    NSRect visibleRect = _delegate.visibleRect;
    CGFloat lineHeight = _delegate.lineHeight;
    int y = 0;

    switch (_selectionScrollDirection) {
        case kiTermSelectionScrollDirectionStopped:
            _scrolling = NO;
            return;

        case kiTermSelectionScrollDirectionUp:
            visibleRect.origin.y -= lineHeight * numLines;
            // Allow the origin to go as far as y=-VMARGIN so the top border is shown when the first
            // line is on screen.
            if (visibleRect.origin.y >= -[iTermAdvancedSettingsModel terminalVMargin]) {
                [_delegate scrollRectToVisible:visibleRect];
            }
            y = visibleRect.origin.y / lineHeight;
            break;

        case kiTermSelectionScrollDirectionDown:
            visibleRect.origin.y += lineHeight * numLines;
            if (visibleRect.origin.y + visibleRect.size.height > _delegate.frame.size.height) {
                visibleRect.origin.y = _delegate.frame.size.height - visibleRect.size.height;
            }
            [_delegate scrollRectToVisible:visibleRect];
            y = (visibleRect.origin.y + visibleRect.size.height - [_delegate excess]) / lineHeight;
            break;
    }

    [_delegate moveSelectionEndpointToX:_scrollingCoord.x
                                      Y:y
                     locationInTextView:_scrollingLocation];

    [self scheduleSelectionScroll];
}

- (void)mouseUp {
    _selectionScrollDirection = 0;
}

- (void)mouseDraggedTo:(NSPoint)locationInTextView coord:(VT100GridCoord)coord {
    iTermSelectionScrollDirection previousDirection = _selectionScrollDirection;
    NSRect visibleRect = [_delegate visibleRect];
    if (locationInTextView.y <= visibleRect.origin.y) {
        DLog(@"selection scroll up");
        _selectionScrollDirection = kiTermSelectionScrollDirectionUp;
        _scrollingCoord = coord;
        _scrollingLocation = locationInTextView;
    } else if (locationInTextView.y >= visibleRect.origin.y + visibleRect.size.height) {
        DLog(@"selection scroll down");
        _selectionScrollDirection = kiTermSelectionScrollDirectionDown;
        _scrollingCoord = coord;
        _scrollingLocation = locationInTextView;
    } else {
        DLog(@"selection scroll off");
        _selectionScrollDirection = kiTermSelectionScrollDirectionStopped;
    }
    if (_selectionScrollDirection && previousDirection == kiTermSelectionScrollDirectionStopped) {
        DLog(@"selection scroll scheduling");
        [self.delegate selectionScrollWillStart];
        [self scheduleSelectionScroll];
    }
}


@end
