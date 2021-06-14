//
//  iTermSizeRememberingView.h
//  iTerm
//
//  Created by George Nachman on 6/23/14.
//
//

#import <Cocoa/Cocoa.h>

@class iTermSizeRememberingView;

@protocol iTermSizeRememberingViewDelegate<NSObject>
- (void)sizeRememberingView:(iTermSizeRememberingView *)sender effectiveAppearanceDidChange:(NSAppearance *)effectiveAppearance;
@end

@interface iTermSizeRememberingView : NSView
@property(nonatomic) NSSize originalSize;
@property(nonatomic, weak) id<iTermSizeRememberingViewDelegate> delegate;

- (void)resetToOriginalSize;

@end

@interface iTermPrefsProfilesGeneralView : iTermSizeRememberingView
@end

