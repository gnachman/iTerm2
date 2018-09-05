//
//  iTermStatusBarSetupDestinationCollectionViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermStatusBarSetupElement.h"

@class iTermStatusBarLayout;
@class iTermStatusBarAdvancedConfiguration;

@interface iTermStatusBarSetupDestinationCollectionViewController : NSViewController

@property (nonatomic, copy) NSArray<iTermStatusBarSetupElement *> *elements;

- (void)setLayout:(iTermStatusBarLayout *)layout;
- (NSDictionary *)layoutDictionaryWithAdvancedConfiguration:(iTermStatusBarAdvancedConfiguration *)advancedConfiguration;

- (void)deleteSelected;

@end
