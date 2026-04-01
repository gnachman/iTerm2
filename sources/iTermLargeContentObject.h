//
//  iTermLargeContentObject.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/18/26.
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"

NS_ASSUME_NONNULL_BEGIN

/// Protocol for fetching large content data on demand.
/// iTermGraphDatabase conforms to this protocol.
@protocol iTermLargeContentProvider <NSObject>

/// Load large content data for a given metadata dictionary.
/// @param metadata Dictionary containing rowid and other info needed to fetch data.
/// @return The large content dictionary, or nil if unavailable.
- (NSDictionary * _Nullable)loadLargeContentWithMetadata:(NSDictionary *)metadata;

@end

/// Protocol for interval tree objects that support split encoding.
/// Objects conforming to this protocol can have their large data stored separately
/// and loaded lazily during restoration.
@protocol iTermLargeContentObject <IntervalTreeObject>

/// Small metadata (loaded immediately during restoration).
- (NSDictionary *)smallDictionaryValue;

/// Large data (stored separately, loaded on demand).
- (NSDictionary * _Nullable)largeDictionaryValue;

/// Initialize with small data + optional large content provider for lazy loading.
/// @param smallDict Immediately-available metadata
/// @param largeContent The large content dict (already loaded), or nil
/// @param provider Provider for lazy loading, or nil if large content already loaded
/// @param metadata Metadata for lazy loading via provider, or nil
- (nullable instancetype)initWithSmallDictionary:(NSDictionary *)smallDict
                                    largeContent:(NSDictionary * _Nullable)largeContent
                                        provider:(id<iTermLargeContentProvider> _Nullable)provider
                                        metadata:(NSDictionary * _Nullable)metadata;

@end

NS_ASSUME_NONNULL_END
