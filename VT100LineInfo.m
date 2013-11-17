//
//  VT100LineInfo.m
//  iTerm
//
//  Created by George Nachman on 11/17/13.
//
//

#import "VT100LineInfo.h"

@implementation VT100LineInfo {
    char *dirty_;
    int width_;
    BOOL anyCharPossiblyDirty_;  // No means nothing is dirty. Yes means MAYBE something is dirty.
    NSTimeInterval timestamp_;
}

- (id)initWithWidth:(int)width {
    self = [super init];
    if (self) {
        width_ = width;
        dirty_ = realloc(dirty_, width);
        [self setDirty:NO inRange:VT100GridRangeMake(0, width)];
        [self updateTimestamp];
    }
    return self;
}

- (void)dealloc {
    free(dirty_);
    [super dealloc];
}

- (void)setDirty:(BOOL)dirty inRange:(VT100GridRange)range {
#ifdef ITERM_DEBUG
    assert(range.location >= 0);
    assert(range.length >= 0);
    assert(range.location + range.length <= width_);
#endif
    if (dirty) {
        anyCharPossiblyDirty_ = YES;
        timestamp_ = [NSDate timeIntervalSinceReferenceDate];
    } else if (range.location == 0 && range.length == width_) {
        anyCharPossiblyDirty_ = NO;
    }
    int n = MAX(0, MIN(range.length, width_ - range.location));
    memset(dirty_ + range.location, dirty, n);
}

- (VT100GridRange)dirtyRange {
    VT100GridRange range = VT100GridRangeMake(-1, 0);
    if (!anyCharPossiblyDirty_) {
        return range;
    }
    for (int i = 0; i < width_; i++) {
        if (dirty_[i]) {
            range.location = i;
            break;
        }
    }
    if (range.location >= 0) {
        for (int i = width_ - 1; i >= 0; i--) {
            if (dirty_[i]) {
                range.length = i - range.location + 1;
                break;
            }
        }
    }
    if (range.location == -1) {
        anyCharPossiblyDirty_ = NO;
    }
    return range;
}

- (NSTimeInterval)timestamp {
    return timestamp_;
}

- (void)updateTimestamp {
    timestamp_ = [NSDate timeIntervalSinceReferenceDate];
}

- (BOOL)isDirtyAtOffset:(int)x {
#if DEBUG
    assert(x >= 0 && x < width_);
#else
    x = MIN(width_ - 1, MAX(0, x));
#endif
    return dirty_[x];
}

- (BOOL)anyCharIsDirty {
    if (!anyCharPossiblyDirty_) {
        return NO;
    } else {
        for (int i = 0; i < width_; i++) {
            if (dirty_[i]) {
                return YES;
            }
        }
        return NO;
    }
}

- (id)copyWithZone:(NSZone *)zone {
    VT100LineInfo *theCopy = [[VT100LineInfo alloc] initWithWidth:width_];
    memmove(theCopy->dirty_, dirty_, width_);
    theCopy->anyCharPossiblyDirty_ = anyCharPossiblyDirty_;
    theCopy->timestamp_ = timestamp_;
    
    return theCopy;
}

@end
