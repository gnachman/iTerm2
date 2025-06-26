//
//  iTermPreferencesSearch.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/28/19.
//

#import <Foundation/Foundation.h>
#import "ProfileModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermPreferencesSearchDocument : NSObject<NSCopying>
@property (nonatomic, readonly) NSArray<NSString *> *keywordPhrases;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSArray<NSString *> *allKeywords;
@property (nonatomic, readonly) NSNumber *docid;
@property (nonatomic, strong) NSString *ownerIdentifier;
@property (nonatomic) double queryIndependentScore;
@property (nonatomic, readonly) ProfileType profileTypes;

+ (instancetype)documentWithDisplayName:(NSString *)displayName
                             identifier:(NSString *)identifier
                         keywordPhrases:(NSArray<NSString *> *)keywordPhrases
                           profileTypes:(ProfileType)profileTypes;

- (instancetype)init NS_UNAVAILABLE;
@end

@interface iTermPreferencesSearchEngine : NSObject
- (void)addDocumentToIndex:(iTermPreferencesSearchDocument *)document;
- (NSArray<iTermPreferencesSearchDocument *> *)documentsMatchingQuery:(NSString *)query;
- (nullable iTermPreferencesSearchDocument *)documentWithKey:(NSString *)key;
@end

NS_ASSUME_NONNULL_END
