//
//  NSLocale.h
//  iTerm2
//
//  Created by George Nachman on 6/23/16.
//
//

#import <Foundation/Foundation.h>

@interface NSLocale (iTerm)

// Is the locale one that writes "foo." instead of "foo".?
- (BOOL)commasAndPeriodsGoInsideQuotationMarks;

@end
