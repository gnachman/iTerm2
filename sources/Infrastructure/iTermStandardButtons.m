//
//  iTermStandardButtons.m
//  iTerm2
//

#import "iTermStandardButtons.h"

NSString *iTermLocalizedOK(void) {
    return NSLocalizedStringWithDefaultValue(@"General.OK", nil, [NSBundle mainBundle], @"OK", @"OK button");
}

NSString *iTermLocalizedCancel(void) {
    return NSLocalizedStringWithDefaultValue(@"General.Cancel", nil, [NSBundle mainBundle], @"Cancel", @"Cancel button");
}

NSString *iTermLocalizedCopy(void) {
    return NSLocalizedStringWithDefaultValue(@"General.Copy", nil, [NSBundle mainBundle], @"Copy", @"Copy button");
}

NSString *iTermLocalizedYes(void) {
    return NSLocalizedStringWithDefaultValue(@"General.Yes", nil, [NSBundle mainBundle], @"Yes", @"Yes button");
}

NSString *iTermLocalizedNo(void) {
    return NSLocalizedStringWithDefaultValue(@"General.No", nil, [NSBundle mainBundle], @"No", @"No button");
}

NSString *iTermLocalizedAdd(void) {
    return NSLocalizedStringWithDefaultValue(@"General.Add", nil, [NSBundle mainBundle], @"Add", @"Add button");
}

NSString *iTermLocalizedRemove(void) {
    return NSLocalizedStringWithDefaultValue(@"General.Remove", nil, [NSBundle mainBundle], @"Remove", @"Remove button");
}

NSString *iTermLocalizedEdit(void) {
    return NSLocalizedStringWithDefaultValue(@"General.Edit", nil, [NSBundle mainBundle], @"Edit", @"Edit button");
}
