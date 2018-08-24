//
//  iTermMetaFrustrationDetector.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/23/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermMetaFrustrationDetector<NSObject>
- (void)metaFrustrationDetectorDidDetectFrustrationForLeftOption;
- (void)metaFrustrationDetectorDidDetectFrustrationForRightOption;
@end

@interface iTermMetaFrustrationDetector : NSObject

@property (nonatomic, weak) id<iTermMetaFrustrationDetector> delegate;

- (void)didSendKeyEvent:(NSEvent *)event;

@end

NS_ASSUME_NONNULL_END
