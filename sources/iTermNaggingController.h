//
//  iTermNaggingController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/11/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermNaggingControllerDelegate<NSObject>
- (BOOL)naggingControllerCanShowMessageWithIdentifier:(NSString *)identifier;
- (void)naggingControllerShowMessage:(NSString *)message
                          identifier:(NSString *)identifier
                             options:(NSArray<NSString *> *)options
                          completion:(void (^)(int))completion;
@end

@interface iTermNaggingController : NSObject
@property (nonatomic, weak) id<iTermNaggingControllerDelegate> delegate;

- (BOOL)permissionToReportVariableNamed:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
