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

@protocol iTermGlobalSearchResultProtocol<NSObject>
@property (nonatomic, weak) PTYSession *session;
@property (nonatomic, copy) NSAttributedString *snippet;

- (void)revealWithState:(NSMutableDictionary *)state
             completion:(void (^)(NSRect))completion;
@end

@interface iTermGlobalSearchResult: NSObject<iTermGlobalSearchResultProtocol>
@property (nonatomic, readonly) BOOL isExternal;
@property (nonatomic, readonly) VT100GridCoordRange internalCoordRange;

@property (nonatomic, weak) PTYSession *session;
@property (nonatomic, strong) SearchResult *result;
@property (nonatomic, copy) NSAttributedString *snippet;
@property (nonatomic) BOOL onMainScreen;

+ (void)restoreAlternateScreensWithAnnouncement:(BOOL)announce state:(NSMutableDictionary *)state;
- (void)highlightLines;
@end

@class iTermBrowserFindResult;

@interface iTermGlobalBrowserSearchResult: NSObject<iTermGlobalSearchResultProtocol>
@property (nonatomic, weak) PTYSession *session;
@property (nonatomic, copy) NSAttributedString *snippet;
@property (nonatomic, strong) iTermBrowserFindResult *findResult;
@end

NS_ASSUME_NONNULL_END
