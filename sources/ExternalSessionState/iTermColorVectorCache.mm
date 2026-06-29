//
//  iTermColorVectorCache.mm
//  iTerm2
//
//  Created by Claude on 2025-01-10.
//

#import "iTermColorVectorCache.h"
#import "unordered_dense/unordered_dense.h"

extern "C" {
#import "DebugLogging.h"
}

// C++ class for efficient color space caching
class ColorSpaceCache {
private:
    struct CacheSlot {
        NSColorSpace* __weak colorSpace;
        ankerl::unordered_dense::map<iTermColorMapKey, vector_float4> cache;
        
        CacheSlot() : colorSpace(nil) {}
        
        // Move constructor
        CacheSlot(CacheSlot&& other) noexcept 
            : colorSpace(other.colorSpace), cache(std::move(other.cache)) {
            other.colorSpace = nil;
        }
        
        // Move assignment
        CacheSlot& operator=(CacheSlot&& other) noexcept {
            if (this != &other) {
                colorSpace = other.colorSpace;
                cache = std::move(other.cache);
                other.colorSpace = nil;
            }
            return *this;
        }
        
        // Delete copy operations
        CacheSlot(const CacheSlot&) = delete;
        CacheSlot& operator=(const CacheSlot&) = delete;
    };
    
    CacheSlot slots[2];

public:
    ColorSpaceCache() {}
    
    // Returns true if found, false if cache miss
    bool lookup(iTermColorMapKey key, NSColorSpace* colorSpace, vector_float4& result) {
        // Try slot 0 (most recent)
        if (slots[0].colorSpace == colorSpace) {
            auto it = slots[0].cache.find(key);
            if (it != slots[0].cache.end()) {
                result = it->second;
                return true;
            }
            return false;
        }
        
        // Try slot 1
        if (slots[1].colorSpace == colorSpace) {
            auto it = slots[1].cache.find(key);
            if (it != slots[1].cache.end()) {
                result = it->second;
                // Promote to slot 0 (LRU)
                promote();
                return true;
            }
            // After promotion, we'll want to store in slot 0
            promote();
            return false;
        }
        
        // Complete cache miss - evict and log
        logEviction(colorSpace);
        evict(colorSpace);
        return false;
    }
    
    void store(iTermColorMapKey key, NSColorSpace* colorSpace, vector_float4 value) {
        // Find or create slot for this color space
        if (slots[0].colorSpace == colorSpace) {
            slots[0].cache[key] = value;
        } else if (slots[1].colorSpace == colorSpace) {
            slots[1].cache[key] = value;
        } else {
            // Evict and store in slot 0
            logEviction(colorSpace);
            evict(colorSpace);
            slots[0].cache[key] = value;
        }
    }
    
    void clear() {
        slots[0] = CacheSlot();
        slots[1] = CacheSlot();
    }
    
    void clearKey(iTermColorMapKey key) {
        slots[0].cache.erase(key);
        slots[1].cache.erase(key);
    }
    
private:
    void promote() {
        // Move slot 1 to slot 0
        std::swap(slots[0], slots[1]);
    }
    
    void evict(NSColorSpace* newColorSpace) {
        // Move slot 0 to slot 1, clear slot 0 for new color space
        slots[1] = std::move(slots[0]);
        slots[0] = CacheSlot();
        slots[0].colorSpace = newColorSpace;
    }
    
    void logEviction(NSColorSpace* newColorSpace) {
        NSColorSpace* space1 = slots[0].colorSpace;
        NSColorSpace* space2 = slots[1].colorSpace;
        
        BOOL wouldEqualSpace1 = space1 && [newColorSpace isEqual:space1];
        BOOL wouldEqualSpace2 = space2 && [newColorSpace isEqual:space2];
        DLog(@"Color space cache eviction. Old space 1: %@, Old space 2: %@, New space: %@, isEqual would match space1: %@, space2: %@",
             space1, space2, newColorSpace,
             wouldEqualSpace1 ? @"YES" : @"NO", wouldEqualSpace2 ? @"YES" : @"NO");
    }
};

@implementation iTermColorVectorCache {
    ColorSpaceCache _cache;
}

- (vector_float4)vectorForColor:(NSColor *)color
                     colorSpace:(NSColorSpace *)colorSpace {
    NSColor *colorInTargetSpace = [color colorUsingColorSpace:colorSpace];
    
    return (vector_float4){
        (float)colorInTargetSpace.redComponent,
        (float)colorInTargetSpace.greenComponent, 
        (float)colorInTargetSpace.blueComponent,
        (float)colorInTargetSpace.alphaComponent
    };
}

- (void)storeVector:(vector_float4)vector
            forKey:(iTermColorMapKey)key
         colorSpace:(NSColorSpace *)colorSpace {
    _cache.store(key, colorSpace, vector);
}

- (BOOL)getVector:(vector_float4 *)outVector
           forKey:(iTermColorMapKey)key
       colorSpace:(NSColorSpace *)colorSpace {
    return _cache.lookup(key, colorSpace, *outVector);
}

- (void)clear {
    _cache.clear();
}

- (void)clearKey:(iTermColorMapKey)key {
    _cache.clearKey(key);
}

@end
