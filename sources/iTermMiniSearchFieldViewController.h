//
//  iTermMiniSearchFieldViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/7/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermFindViewController.h"

@interface iTermMiniSearchFieldViewController : NSViewController<iTermFindViewController>
@property (nonatomic) BOOL canClose;

- (void)sizeToFitSize:(NSSize)size;

@end
