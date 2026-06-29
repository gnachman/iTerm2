//
//  iTermCoreSearch.h
//  iTerm2
//
//  Created by George Nachman on 10/27/25.
//

#import <Foundation/Foundation.h>
#import "FindContext.h"
#import "LineBufferHelpers.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    NSString *needle;
    FindOptions options;
    iTermFindMode mode;
    NSString *haystack;
    const int *deltas;
} CoreSearchRequest;

NSArray<ResultRange *> *CoreSearch(const CoreSearchRequest *request);

NS_ASSUME_NONNULL_END
