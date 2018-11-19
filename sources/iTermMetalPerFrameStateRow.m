//
//  iTermMetalPerFrameStateRow.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/18.
//

#import "iTermMetalPerFrameStateRow.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermData.h"
#import "iTermMarkRenderer.h"
#import "iTermMetalPerFrameStateConfiguration.h"
#import "iTermSelection.h"
#import "iTermTextDrawingHelper.h"
#import "PTYTextView.h"
#import "VT100Screen.h"
#import "VT100ScreenMark.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermMetalPerFrameStateRow

- (instancetype)initWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                             textView:(PTYTextView *)textView
                               screen:(VT100Screen *)screen
                              rowSize:(size_t)rowSize
                  allowOtherMarkStyle:(BOOL)allowOtherMarkStyle
                    timestampsEnabled:(BOOL)timestampsEnabled
                                  row:(int)i
              totalScrollbackOverflow:(long long)totalScrollbackOverflow {
    self = [super init];
    if (self) {
        if (timestampsEnabled) {
            _date = [textView drawingHelperTimestampForLine:i];
        }
        iTermData *data = [iTermScreenCharData dataOfLength:rowSize];
        screen_char_t *myBuffer = data.mutableBytes;
        screen_char_t *line = [screen getLineAtIndex:i withBuffer:myBuffer];
        _generation = [screen generationForLine:i];

        if (line != myBuffer) {
            memcpy(myBuffer, line, rowSize);
        }
        [data checkForOverrun];
        _screenCharLine = data;
        _selectedIndexSet = [textView.selection selectedIndexesOnLine:i];

        NSData *findMatches = [drawingHelper.delegate drawingHelperMatchesOnLine:i];
        if (findMatches) {
            _matches = findMatches;
        }

        const long long absoluteLine = totalScrollbackOverflow + i;
        _underlinedRange = [drawingHelper underlinedRangeOnLine:absoluteLine];
        _markStyle = @([self markStyleForLine:i
                                      enabled:drawingHelper.drawMarkIndicators
                                     textView:textView
                          allowOtherMarkStyle:allowOtherMarkStyle]);
    }
    return self;
}

- (iTermMarkStyle)markStyleForLine:(int)i
                           enabled:(BOOL)enabled
                          textView:(PTYTextView *)textView
               allowOtherMarkStyle:(BOOL)allowOtherMarkStyle {
    if (!enabled) {
        return iTermMarkStyleNone;
    }

    VT100ScreenMark *mark = [textView.dataSource markOnLine:i];
    if (!mark.isVisible) {
        return iTermMarkStyleNone;
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
                                                             rowSize:(_width + 1) * sizeof(screen_char_t)
                                                 allowOtherMarkStyle:_allowOtherMarkStyle
                                                   timestampsEnabled:_timestampsEnabled
                                                                 row:line
                                             totalScrollbackOverflow:_totalScrollbackOverflow];
}

@end

NS_ASSUME_NONNULL_END
