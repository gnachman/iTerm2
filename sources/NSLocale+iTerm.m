//
//  NSLocale.m
//  iTerm2
//
//  Created by George Nachman on 6/23/16.
//
//

#import "NSLocale+iTerm.h"

@implementation NSLocale (iTerm)

- (BOOL)commasAndPeriodsGoInsideQuotationMarks {
    return [[self localeIdentifier] isEqualToString:@"en_US"];
}

@end
