//
//  iTermGlobalSearchResult.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

#import <Foundation/Foundation.h>
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class NSAttributedString;
@class PTYSession;
@class SearchResult;
@class iTermResilientCoordinate;

@protocol iTermGlobalSearchResultProtocol<NSObject>
@property (nonatomic, weak) PTYSession *session;
@property (nonatomic, copy) NSAttributedString *snippet;

- (void)revealWithState:(NSMutableDictionary *)state
             completion:(void (^)(NSRect))completion;
@end

@interface iTermGlobalSearchResult: NSObject<iTermGlobalSearchResultProtocol>
@property (nonatomic, readonly) BOOL isExternal;

@property (nonatomic, weak) PTYSession *session;
@property (nonatomic, strong) SearchResult *result;
@property (nonatomic, copy) NSAttributedString *snippet;
@property (nonatomic) BOOL onMainScreen;

// Resilient coordinates that automatically adjust for fold/unfold/resize.
@property (nonatomic, strong, nullable) iTermResilientCoordinate *resilientStart;
@property (nonatomic, strong, nullable) iTermResilientCoordinate *resilientEnd;

+ (void)restoreAlternateScreensWithAnnouncement:(BOOL)announce state:(NSMutableDictionary *)state;
- (void)highlightLines;
@end

@class iTermFoldSearchResult;

@interface iTermGlobalFoldSearchResult: NSObject<iTermGlobalSearchResultProtocol>
@property (nonatomic, weak) PTYSession *session;
@property (nonatomic, copy) NSAttributedString *snippet;
@property (nonatomic, strong) iTermFoldSearchResult *foldResult;

// Resilient coordinates that automatically adjust for fold/unfold/resize.
@property (nonatomic, strong, nullable) iTermResilientCoordinate *resilientStart;
@property (nonatomic, strong, nullable) iTermResilientCoordinate *resilientEnd;
@end

// A container for fold search results from a single fold.
// Expandable in the outline view. Conforms to the result protocol
// so it can live in the same results array as regular results.
@interface iTermGlobalSearchFoldGroup: NSObject<iTermGlobalSearchResultProtocol>
@property (nonatomic, weak) PTYSession *session;
@property (nonatomic, copy) NSAttributedString *snippet;
@property (nonatomic, readonly) NSArray<iTermGlobalFoldSearchResult *> *results;
- (instancetype)initWithSession:(PTYSession *)session
                        snippet:(NSAttributedString *)snippet;
- (instancetype)init NS_UNAVAILABLE;
- (void)addResult:(iTermGlobalFoldSearchResult *)result;
@end

@class iTermBrowserFindResult;

@interface iTermGlobalBrowserSearchResult: NSObject<iTermGlobalSearchResultProtocol>
@property (nonatomic, weak) PTYSession *session;
@property (nonatomic, copy) NSAttributedString *snippet;
@property (nonatomic, strong) iTermBrowserFindResult *findResult;
@end

NS_ASSUME_NONNULL_END
