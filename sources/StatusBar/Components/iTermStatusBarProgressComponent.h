//
//  iTermStatusBarProgressComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/18.
//

#import "iTermStatusBarBaseComponent.h"

NS_ASSUME_NONNULL_BEGIN

@class PasteContext;

@protocol iTermStatusBarProgressComponentDelegate<NSObject>
- (void)statusBarProgressComponentDidCancel;
@end

@interface iTermStatusBarProgressComponent : iTermStatusBarBaseComponent

@property (nonatomic, strong) PasteContext *pasteContext;
@property (nonatomic) int bufferLength;
@property (nonatomic) int remainingLength;
@property (nonatomic, weak) id<iTermStatusBarProgressComponentDelegate> progressDelegate;

@end

NS_ASSUME_NONNULL_END
