//
//  iTermEval.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/30/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermEval : NSObject

// Serialized state.
@property (nonatomic, readonly) NSDictionary *dictionaryValue;

// macros gives mappings from $$NAME$$ to the replacement values.
- (instancetype)initWithMacros:(nullable NSDictionary<NSString *, NSString *> *)macros NS_DESIGNATED_INITIALIZER;

// Restores saved state. Supports restoring state from old arrangements predating iTermEval.
- (instancetype)initWithDictionaryValue:(NSDictionary *)dictionaryValue;

- (instancetype)init NS_UNAVAILABLE;

- (void)addStringWithPossibleSubstitutions:(NSString *)string;

- (BOOL)promptForMissingValuesInWindow:(NSWindow *)parent;
- (void)replaceMissingValuesWithString:(NSString *)replacement;

@end

@interface NSString(iTermEval)
- (void)it_evaluateWith:(iTermEval *)eval
                timeout:(NSTimeInterval)timeout
                 source:(NSString *(^)(NSString *))source
             completion:(void (^)(NSString *evaluatedString))completion;
@end

NS_ASSUME_NONNULL_END
