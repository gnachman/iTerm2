//
//  iTermQuotedRecognizer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/12/18.
//

#import <CoreParse/CoreParse.h>

// This is exactly a CPQuotedRecognizer but it tolerates an end quote that begins with the escape
// string.
@interface iTermQuotedRecognizer : CPQuotedRecogniser

@end
