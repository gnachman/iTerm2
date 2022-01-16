//
//  PTYSession+ARC.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import "PTYSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface PTYSession (ARC)<iTermPopupWindowPresenter>

+ (void)openPartialAttachmentsForArrangement:(NSDictionary *)arrangement
                                  completion:(void (^)(NSDictionary *))completion;

- (void)fetchAutoLogFilenameWithCompletion:(void (^)(NSString *filename))completion;
- (void)setTermIDIfPossible;
- (void)watchForPasteBracketingOopsieWithPrefix:(NSString *)prefix;

#pragma mark - Private

- (iTermJobManagerAttachResults)tryToFinishAttachingToMultiserverWithPartialAttachment:(id<iTermPartialAttachment>)partialAttachment;

- (void)publishNewline;
- (void)publishScreenCharArray:(ScreenCharArray *)array
                      metadata:(iTermImmutableMetadata)metadata;
- (void)maybeTurnOffPasteBracketing;


@end

NS_ASSUME_NONNULL_END
