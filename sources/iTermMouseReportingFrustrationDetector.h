//
//  iTermMouseReportingFrustrationDetector.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/19/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermMouseReportingFrustrationDetector;

@protocol iTermMouseReportingFrustrationDetectorDelegate<NSObject>
- (void)mouseReportingFrustrationDetectorDidDetectFrustration:(iTermMouseReportingFrustrationDetector *)sender;
@end

@interface iTermMouseReportingFrustrationDetector : NSObject
@property (nonatomic, weak) id<iTermMouseReportingFrustrationDetectorDelegate> delegate;

- (void)mouseDown:(NSEvent *)event reported:(BOOL)reported;
- (void)mouseUp:(NSEvent *)event reported:(BOOL)reported;
- (void)mouseDragged:(NSEvent *)event reported:(BOOL)reported;
- (void)otherMouseEvent;
- (void)keyDown:(NSEvent *)event;
- (void)didCopyToPasteboardWithControlSequence;

@end

NS_ASSUME_NONNULL_END
