//
//  iTermSnippetsModel.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/14/20.
//

#import <Foundation/Foundation.h>

#import "iTermNotificationCenter.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermSnippet : NSObject
@property (nonatomic, readonly) NSDictionary *dictionaryValue;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) NSString *value;
@property (nonatomic, readonly) NSString *guid;
@property (nonatomic, readonly) id actionKey;
@property (nonatomic, readonly) BOOL useCompatibilityEscaping;

// Title suitable for display. Works nicely if the title is empty by using a prefix of the value.
@property (nonatomic, readonly) NSString *displayTitle;

- (instancetype)initWithTitle:(NSString *)title
                        value:(NSString *)value
                         guid:(NSString *)guid
     useCompatibilityEscaping:(BOOL)useCompatibilityEscaping NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
                             index:(NSInteger)index;

- (instancetype)init NS_UNAVAILABLE;

- (NSString *)trimmedValue:(NSInteger)maxLength;
- (NSString *)trimmedTitle:(NSInteger)maxLength;
- (BOOL)titleEqualsValueUpToLength:(NSInteger)maxLength;
- (BOOL)matchesActionKey:(id)actionKey;

@end

@interface iTermSnippetsModel : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, readonly) NSArray<iTermSnippet *> *snippets;

- (void)addSnippet:(iTermSnippet *)snippet;
- (void)removeSnippets:(NSArray<iTermSnippet *> *)snippets;
- (void)replaceSnippet:(iTermSnippet *)snippetToReplace
           withSnippet:(iTermSnippet *)replacement;
- (void)moveSnippetsWithGUIDs:(NSArray<NSString *> *)guids
                      toIndex:(NSInteger)row;
- (void)setSnippets:(NSArray<iTermSnippet *> *)snippets;
- (iTermSnippet *)snippetWithGUID:(NSString *)guid;
- (nullable iTermSnippet *)snippetWithActionKey:(id)actionKey;

@end

@interface iTermSnippetsDidChangeNotification : iTermBaseNotification

typedef NS_ENUM(NSUInteger, iTermSnippetsDidChangeMutationType) {
    iTermSnippetsDidChangeMutationTypeInsertion,
    iTermSnippetsDidChangeMutationTypeDeletion,
    iTermSnippetsDidChangeMutationTypeEdit,
    iTermSnippetsDidChangeMutationTypeMove,
    iTermSnippetsDidChangeMutationTypeFullReplacement
};

@property (nonatomic, readonly) iTermSnippetsDidChangeMutationType mutationType;
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly) NSIndexSet *indexSet;  // for move only

+ (instancetype)notificationWithMutationType:(iTermSnippetsDidChangeMutationType)mutationType
                                       index:(NSInteger)index;
+ (instancetype)moveNotificationWithRemovals:(NSIndexSet *)removals
                            destinationIndex:(NSInteger)destinationIndex;
+ (instancetype)fullReplacementNotification;
+ (instancetype)removalNotificationWithIndexes:(NSIndexSet *)indexes;

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermSnippetsDidChangeNotification * _Nonnull notification))block;
@end


NS_ASSUME_NONNULL_END
