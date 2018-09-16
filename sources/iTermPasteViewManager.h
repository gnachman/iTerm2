//
//  iTermPasteViewManager.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermStatusBarViewController;
@class PasteContext;
@class iTermVariableScope;

@protocol iTermPasteViewManagerDelegate<NSObject>

- (void)pasteViewManagerDropDownPasteViewVisibilityDidChange;
- (void)pasteViewManagerUserDidCancel;
- (iTermVariableScope *)pasteViewManagerScope;

@end

@interface iTermPasteViewManager : NSObject

@property (nonatomic, strong) PasteContext *pasteContext;
@property (nonatomic) NSUInteger bufferLength;
@property (nonatomic, readonly) BOOL dropDownPasteViewIsVisible;
@property (nonatomic, weak) id<iTermPasteViewManagerDelegate> delegate;
@property (nonatomic, assign) int remainingLength;

- (void)startWithViewForDropdown:(NSView *)dropdownSuperview
         statusBarViewController:(iTermStatusBarViewController *)statusBarController;

- (void)didStop;

@end

NS_ASSUME_NONNULL_END
