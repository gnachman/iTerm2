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
@class VT100Screen;
@class iTermMetalPerFrameStateConfiguration;

@interface iTermMetalPerFrameStateRow : NSObject {
@public
    NSInteger _generation;
    NSNumber *_markStyle;
    iTermData *_screenCharLine;
    NSIndexSet *_selectedIndexSet;
    NSDate *_date;
    NSData *_matches;
    NSRange _underlinedRange;
}

- (instancetype)init NS_UNAVAILABLE;
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
