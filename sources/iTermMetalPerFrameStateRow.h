//
//  iTermMetalPerFrameStateRow.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermData;
@class iTermTextDrawingHelper;
@class PTYTextView;
@class ScreenCharArray;
@class VT100Screen;
@protocol iTermExternalAttributeIndexReading;
@class iTermMetalPerFrameStateConfiguration;

@interface iTermMetalPerFrameStateRow : NSObject {
@public
    NSNumber *_markStyle;
    BOOL _lineStyleMark;
    ScreenCharArray *_screenCharLine;
    NSIndexSet *_selectedIndexSet;
    NSDate *_date;
    BOOL _belongsToBlock;
    NSData *_matches;
    NSRange _underlinedRange;  // Underline for semantic history
    id<iTermExternalAttributeIndexReading> _eaIndex;
}

- (instancetype)init NS_UNAVAILABLE;
- (iTermMetalPerFrameStateRow *)emptyCopy;

@end


@interface iTermMetalPerFrameStateRowFactory : NSObject

- (instancetype)initWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                             textView:(PTYTextView *)textView
                               screen:(VT100Screen *)screen
                        configuration:(iTermMetalPerFrameStateConfiguration *)configuration
                                width:(int)width NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (iTermMetalPerFrameStateRow *)newRowForLine:(int)line;

@end

NS_ASSUME_NONNULL_END
