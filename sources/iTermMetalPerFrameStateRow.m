//
//  iTermMetalPerFrameStateRow.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/18.
//

#import "iTermMetalPerFrameStateRow.h"

#import "DebugLogging.h"
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
        _belongsToBlock = _eaIndex.attributes[@0].blockID != nil;

        const long long absoluteLine = totalScrollbackOverflow + i;
        _underlinedRange = [drawingHelper underlinedRangeOnLine:absoluteLine];
        _inDeselectedRegion = drawingHelper.selectedCommandRegion.length > 0 && !NSLocationInRange(i, drawingHelper.selectedCommandRegion);
        _markStyle = @([self markStyleForLine:i
                                      enabled:drawingHelper.drawMarkIndicators
                                     textView:textView
                          allowOtherMarkStyle:allowOtherMarkStyle
                                lineStyleMark:&_lineStyleMark
                      lineStyleMarkRightInset:&_lineStyleMarkRightInset]);
    }
    return self;
}

- (iTermMarkStyle)markStyleForLine:(int)i
                           enabled:(BOOL)enabled
                          textView:(PTYTextView *)textView
               allowOtherMarkStyle:(BOOL)allowOtherMarkStyle
                     lineStyleMark:(out BOOL *)lineStyleMark
           lineStyleMarkRightInset:(out int *)lineStyleMarkRightInset {
    if (!enabled) {
        return iTermMarkStyleNone;
    }

    id<VT100ScreenMarkReading> mark = [textView.dataSource markOnLine:i];
    if (!mark) {
        return iTermMarkStyleNone;
    }
    *lineStyleMark = mark.lineStyle;
    if (mark.command.length && mark.lineStyle) {
        *lineStyleMarkRightInset = 9;
    } else {
        *lineStyleMarkRightInset = 0;
    }
    if (mark.code == 0) {
        return iTermMarkStyleSuccess;
    }
    if (allowOtherMarkStyle &&
        mark.code >= 128 && mark.code <= 128 + 32) {
        return iTermMarkStyleOther;
    }
    return iTermMarkStyleFailure;

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
