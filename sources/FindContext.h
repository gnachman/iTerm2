//
//  FindContext.h
//  iTerm
//
//  Created by George Nachman on 10/26/13.
//
//

#import <Foundation/Foundation.h>
#import "iTermFindDriver.h"
#import "VT100GridTypes.h"

typedef NS_OPTIONS(NSUInteger, FindOptions) {
    FindOptBackwards        = (1 << 0),
    FindMultipleResults     = (1 << 1),
    FindOneResultPerRawLine = (1 << 2),
    FindOptEmptyQueryMatches = (1 << 3)
};

typedef NS_ENUM(NSInteger, FindContextStatus) {
    Searching,
    Matched,
    NotFound
};

@class ResultRange;

@protocol iTermFindContextReading<NSObject>
@property(nonatomic, strong, readonly) NSMutableArray<ResultRange *> *results;
@property(nonatomic, readonly) BOOL hasWrapped;
@property(nonatomic, readonly) double progress;
@property(nonatomic, readonly) BOOL includesPartialLastLine;
@end

@interface FindContext : NSObject<iTermFindContextReading, NSCopying>

// Current absolute block number being searched.
@property(nonatomic) int absBlockNum;

// The substring to search for.
@property(nonatomic, copy) NSString *substring;

// A bitwise OR of the options defined above.
@property(nonatomic) FindOptions options;

// How to perform the search.
@property(nonatomic) iTermFindMode mode;

// 1: search forward. -1: search backward.
@property(nonatomic) int dir;

// The offset within a block to begin searching. -1 means the end of the
// block.
@property(nonatomic) int offset;

// The offset within a block at which to stop searching. No results
// with an offset at or beyond this position will be returned.
@property(nonatomic) int stopAt;

// Searching: a search is in progress and this context can be used to search.
// Matched: At least one result has been found. This context can be used to
//   search again.
// NotFound: No results were found and the end of the buffer was reached.
@property(nonatomic) FindContextStatus status;
@property(nonatomic) int matchLength;

// used for multiple results
@property(nonatomic, strong, readwrite) NSMutableArray<ResultRange *> *results;

// for client use. Not read or written by LineBuffer.
@property(nonatomic, readwrite) BOOL hasWrapped;

@property(nonatomic) NSTimeInterval maxTime;

// Estimate of fraction of work done.
@property(nonatomic, readwrite) double progress;

// Do the results include anything from the last line which is also partial?
@property(nonatomic, readwrite) BOOL includesPartialLastLine;

// Remembers where the search began so we can stop after wrapping.
@property(nonatomic) VT100GridAbsCoord initialStart;

- (void)copyFromFindContext:(FindContext *)other;

- (void)reset;
- (void)removeResults;

- (FindContext *)copy;

@end
