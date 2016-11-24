//
//  iTermKeyMappingViewController.h
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import <Cocoa/Cocoa.h>

@class iTermKeyMappingViewController;

@protocol iTermKeyMappingViewControllerDelegate <NSObject>

- (NSDictionary *)keyMappingDictionary:(iTermKeyMappingViewController *)viewController;

- (NSArray *)keyMappingSortedKeys:(iTermKeyMappingViewController *)viewController;
- (NSArray *)keyMappingSortedTouchBarKeys:(iTermKeyMappingViewController *)viewController;

- (NSDictionary *)keyMappingTouchBarItems;

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
      didChangeKey:(NSString *)keyCombo
    isTouchBarItem:(BOOL)isTouchBarItem
           atIndex:(NSInteger)index
          toAction:(int)action
         parameter:(NSString *)parameter
             label:(NSString *)label
        isAddition:(BOOL)addition;

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
         removeKey:(NSString *)keyCombo
    isTouchBarItem:(BOOL)isTouchBarItem;

- (NSArray *)keyMappingPresetNames:(iTermKeyMappingViewController *)viewController;

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
    loadPresetsNamed:(NSString *)presetName;

@end

@interface iTermKeyMappingViewController : NSViewController <
    NSTableViewDelegate,
    NSTableViewDataSource>

@property(nonatomic, assign) IBOutlet id<iTermKeyMappingViewControllerDelegate> delegate;
@property(nonatomic, retain) IBOutlet NSView *placeholderView;

- (void)hideAddTouchBarItem;

@end
