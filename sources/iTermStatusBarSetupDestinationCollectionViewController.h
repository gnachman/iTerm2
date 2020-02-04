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
@property (nonatomic, strong) NSColor *defaultBackgroundColor;
@property (nonatomic, strong) NSColor *defaultTextColor;
@property (nonatomic, copy) void (^onChange)(void);
// Drops from this view are accepted
@property (nonatomic, weak) NSCollectionView *sourceCollectionView;
@property (nonatomic) BOOL darkBackground;

- (void)setLayout:(iTermStatusBarLayout *)layout;
- (NSDictionary *)layoutDictionary;

- (void)deleteSelected;
- (void)configureStatusBarComponentWithIdentifier:(NSString *)identifier;

@end
