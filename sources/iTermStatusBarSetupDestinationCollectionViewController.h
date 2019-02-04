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
@property (nonatomic, strong) iTermStatusBarAdvancedConfiguration *advancedConfiguration;

- (void)setLayout:(iTermStatusBarLayout *)layout;
- (NSDictionary *)layoutDictionary;

- (void)deleteSelected;
- (void)autoRainbowWithDarkBackground:(BOOL)darkBackground;
- (void)configureStatusBarComponentWithIdentifier:(NSString *)identifier;

@end
