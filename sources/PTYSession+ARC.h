//
//  PTYSession+ARC.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import "PTYSession.h"
#import "iTermMetadata.h"

@protocol iTermPopupWindowHosting;

NS_ASSUME_NONNULL_BEGIN

@interface PTYSession (ARC)<iTermPopupWindowPresenter>

+ (void)openPartialAttachmentsForArrangement:(NSDictionary *)arrangement
                                  completion:(void (^)(NSDictionary *))completion;

- (void)fetchAutoLogFilenameWithCompletion:(void (^)(NSString *filename))completion;
- (void)setTermIDIfPossible;

#pragma mark - Expect

- (void)watchForPasteBracketingOopsieWithPrefix:(NSString *)prefix;
- (void)addExpectation:(NSString *)regex
                 after:(nullable iTermExpectation *)predecessor
              deadline:(nullable NSDate *)deadline
            willExpect:(void (^ _Nullable)(void))willExpect
            completion:(void (^ _Nullable)(NSArray<NSString *> * _Nonnull))completion;

#pragma mark - Private

- (iTermJobManagerAttachResults)tryToFinishAttachingToMultiserverWithPartialAttachment:(id<iTermPartialAttachment>)partialAttachment;

- (void)publishNewlineWithLineBufferGeneration:(long long)lineBufferGeneration;
- (void)publishScreenCharArray:(ScreenCharArray *)array
                      metadata:(iTermImmutableMetadata)metadata
          lineBufferGeneration:(long long)lineBufferGeneration;
- (void)maybeTurnOffPasteBracketing;
- (id<iTermPopupWindowHosting>)popupHost;

@end

@interface PTYSessionPublishRequest: NSObject
@property (readonly, nonatomic, strong) ScreenCharArray *array;
@property (readonly, nonatomic) iTermImmutableMetadata metadata;
@property (readonly, nonatomic) long long lineBufferGeneration;

+ (instancetype)requestWithArray:(ScreenCharArray *)sca
                        metadata:(iTermImmutableMetadata)metadata
            lineBufferGeneration:(long long)lineBufferGeneration;

@end

NS_ASSUME_NONNULL_END
