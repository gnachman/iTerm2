//
//  iTermMiniSearchFieldViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/7/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermFindViewController.h"
#import "iTermFocusReportingTextField.h"
#import "iTermStoplightHotbox.h"

@interface iTermMiniSearchField : iTermFocusReportingSearchField<iTermHotboxSuppressing>
@end

@interface iTermMiniSearchFieldViewController : NSViewController<iTermFindViewController>
@property (nonatomic) BOOL canClose;
@property (nonatomic) BOOL hasLineRange;

- (void)sizeToFitSize:(NSSize)size;
- (void)setFont:(NSFont *)font;

@end
