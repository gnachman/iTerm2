//
//  iTermSelectionExtraction.h
//  iTerm2
//
//  Created by George Nachman on 2/17/22.
//

#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, iTermSelectionExtractorOptions) {
    iTermSelectionExtractorOptionsCopyLastNewline = 1 << 0,
    iTermSelectionExtractorOptionsTrimWhitespace = 1 << 1,
    iTermSelectionExtractorOptionsUseCustomBoldColor = 1 << 2,
    iTermSelectionExtractorOptionsBrightenBold = 1 << 3,
};
