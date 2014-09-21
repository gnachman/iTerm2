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

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
    didChangeKeyCombo:(NSString *)keyCombo
              atIndex:(NSInteger)index
             toAction:(int)action
            parameter:(NSString *)parameter
           isAddition:(BOOL)addition;

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
    removeKeyCombo:(NSString *)keyCombo;

- (NSArray *)keyMappingPresetNames:(iTermKeyMappingViewController *)viewController;

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
    loadPresetsNamed:(NSString *)presetName;

@end

@interface iTermKeyMappingViewController : NSViewController <
    NSTableViewDelegate,
    NSTableViewDataSource>

@property(nonatomic, assign) IBOutlet id<iTermKeyMappingViewControllerDelegate> delegate;
@property(nonatomic, retain) IBOutlet NSView *placeholderView;

@end
