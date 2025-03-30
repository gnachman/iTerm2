//
//  iTermMetalPerFrameStateRow.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/18.
//

#import "iTermMetalPerFrameStateRow.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermColorMap.h"
#import "iTermData.h"
#import "iTermMarkRenderer.h"
#import "iTermMetalPerFrameStateConfiguration.h"
#import "iTermSelection.h"
#import "iTermTextDrawingHelper.h"
#import "PTYTextView.h"
#import "ScreenCharArray.h"
#import "VT100Screen.h"
#import "VT100ScreenMark.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermMetalPerFrameStateRow

- (instancetype)initEmptyFrom:(iTermMetalPerFrameStateRow *)source {
    self = [super init];
    if (self) {
        _date = source->_date;
        _belongsToBlock = source->_belongsToBlock;
        _screenCharLine = [ScreenCharArray emptyLineOfLength:source->_screenCharLine.length];
        _selectedIndexSet = [NSIndexSet indexSet];
        _markStyle = @(iTermMarkStyleNone);
        _hoverState = NO;
        _lineStyleMark = NO;
        _lineStyleMarkRightInset = 0;
    }
    return self;
}

- (instancetype)initWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                             textView:(PTYTextView *)textView
                               screen:(VT100Screen *)screen
                                width:(size_t)width
                  allowOtherMarkStyle:(BOOL)allowOtherMarkStyle
                    timestampsEnabled:(BOOL)timestampsEnabled
                                  row:(int)i
              totalScrollbackOverflow:(long long)totalScrollbackOverflow {
    self = [super init];
    if (self) {
        if (timestampsEnabled) {
            _date = [textView drawingHelperTimestampForLine:i];
        }
        _screenCharLine = [[screen screenCharArrayForLine:i] paddedOrTruncatedToLength:width];
#if DEBUG
        assert(_screenCharLine != nil);
#endif
        if (!_screenCharLine) {
            _screenCharLine = [[[ScreenCharArray alloc] init] paddedOrTruncatedToLength:width];
        }
        assert(_screenCharLine.line != nil);
        [_screenCharLine makeSafe];

        _selectedIndexSet = [textView.selection selectedIndexesIncludingTabFillersInAbsoluteLine:totalScrollbackOverflow + i];

        NSData *findMatches = [drawingHelper.delegate drawingHelperMatchesOnLine:i];
        if (findMatches) {
            _matches = findMatches;
        }
        _eaIndex = [[screen externalAttributeIndexForLine:i] copy];
        _belongsToBlock = _eaIndex.attributes[@0].blockIDList != nil;

        const long long absoluteLine = totalScrollbackOverflow + i;
        _underlinedRange = [drawingHelper underlinedRangeOnLine:absoluteLine];
        _x_inDeselectedRegion = drawingHelper.selectedCommandRegion.length > 0 && !NSLocationInRange(i, drawingHelper.selectedCommandRegion);
        _markStyle = @([self markStyleForLine:i
                                      enabled:drawingHelper.drawMarkIndicators
                                     textView:textView
                          allowOtherMarkStyle:allowOtherMarkStyle
                                      hasFold:[drawingHelper.folds containsIndex:i]
                                lineStyleMark:&_lineStyleMark
                      lineStyleMarkRightInset:&_lineStyleMarkRightInset]);
        _hoverState = NSLocationInRange(i, drawingHelper.highlightedBlockLineRange);
    }
    return self;
}

- (iTermMarkStyle)markStyleForLine:(int)i
                           enabled:(BOOL)enabled
                          textView:(PTYTextView *)textView
               allowOtherMarkStyle:(BOOL)allowOtherMarkStyle
                           hasFold:(BOOL)folded
                     lineStyleMark:(out BOOL *)lineStyleMark
           lineStyleMarkRightInset:(out int *)lineStyleMarkRightInset {
    id<iTermMark> genericMark = [textView.dataSource drawableMarkOnLine:i];
    id<VT100ScreenMarkReading> mark = (id<VT100ScreenMarkReading>)genericMark;
    *lineStyleMarkRightInset = 0;
    *lineStyleMark = NO;
    if (mark != nil && enabled) {
        if (mark.lineStyle) {
            // Don't draw line-style mark in selected command region or immediately after selected command region.
            // Note: that logic is in populateLineStyleMarkRendererTransientStateWithFrameData.
            *lineStyleMark = YES;
            if (mark.command.length) {
                *lineStyleMarkRightInset = iTermTextDrawingHelperLineStyleMarkRightInsetCells;
            }
        }
    }
    if (!mark) {
        if (folded) {
            // Folds without a mark should draw as folded success.
            return iTermMarkStyleFoldedSuccess;
        } else {
            return iTermMarkStyleNone;
        }
    }
    if (mark.name.length == 0) {
        if (!enabled && !folded) {
            return iTermMarkStyleNone;
        }
    }
    if (mark.code == 0) {
        return folded ? iTermMarkStyleFoldedSuccess : iTermMarkStyleRegularSuccess;
    }
    if (allowOtherMarkStyle &&
        mark.code >= 128 && mark.code <= 128 + 32) {
        return folded ? iTermMarkStyleFoldedOther : iTermMarkStyleRegularOther;
    }
    return folded ? iTermMarkStyleFoldedFailure : iTermMarkStyleRegularFailure;
}

- (iTermMetalPerFrameStateRow *)emptyCopy {
    return [[iTermMetalPerFrameStateRow alloc] initEmptyFrom:self];
}

@end

@implementation iTermMetalPerFrameStateRowFactory {
    iTermTextDrawingHelper *_drawingHelper;
    PTYTextView *_textView;
    VT100Screen *_screen;
    int _width;
    long long _totalScrollbackOverflow;
    BOOL _allowOtherMarkStyle;
    BOOL _timestampsEnabled;
}

- (instancetype)initWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                             textView:(PTYTextView *)textView
                               screen:(VT100Screen *)screen
                        configuration:(iTermMetalPerFrameStateConfiguration *)configuration
                                width:(int)width {
    self = [super init];
    if (self) {
        _drawingHelper = drawingHelper;
        _textView = textView;
        _screen = screen;
        _width = width;
        _totalScrollbackOverflow = [screen totalScrollbackOverflow];
        _allowOtherMarkStyle = [iTermAdvancedSettingsModel showYellowMarkForJobStoppedBySignal];
        _timestampsEnabled = configuration->_timestampsEnabled;
    }
    return self;
}

- (iTermMetalPerFrameStateRow *)newRowForLine:(int)line {
    return [[iTermMetalPerFrameStateRow alloc] initWithDrawingHelper:_drawingHelper
                                                            textView:_textView
                                                              screen:_screen
                                                               width:_width
                                                 allowOtherMarkStyle:_allowOtherMarkStyle
                                                   timestampsEnabled:_timestampsEnabled
                                                                 row:line
                                             totalScrollbackOverflow:_totalScrollbackOverflow];
}

@end

NS_ASSUME_NONNULL_END
