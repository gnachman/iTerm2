//
//  iTermStatusBarSetupDestinationCollectionViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermStatusBarSetupElement.h"

@interface iTermStatusBarSetupDestinationCollectionViewController : NSViewController

@property (nonatomic, copy) NSArray<iTermStatusBarSetupElement *> *elements;
@property (nonatomic, copy) NSDictionary *layoutDictionary;

- (void)deleteSelected;

@end
