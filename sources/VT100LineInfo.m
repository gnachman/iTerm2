//
//  VT100LineInfo.m
//  iTerm
//
//  Created by George Nachman on 11/17/13.
//
//

#import "VT100LineInfo.h"

#import "iTermMalloc.h"
#import "iTermScreenCharAttachment.h"

@implementation VT100LineInfo {
    int width_;
    NSTimeInterval timestamp_;
    int start_;
    int bound_;
    iTermMutableScreenCharAttachmentsArray *_attachments;
    iTermScreenCharAttachmentRunArray *_attachmentRunArray;
}

static NSInteger VT100LineInfoNextGeneration = 1;

@synthesize timestamp = timestamp_;

- (instancetype)initWithWidth:(int)width {
    self = [super init];
    if (self) {
        width_ = width;
        start_ = -1;
        bound_ = -1;
        [self setDirty:NO inRange:VT100GridRangeMake(0, width) updateTimestamp:NO];
    }
    return self;
}

- (iTermScreenCharAttachmentRunArray *)attachmentRunArray {
    if (!_attachmentRunArray) {
        [self runLengthEncode];
    }
    return _attachmentRunArray;
}

- (void)runLengthEncode {
    if (!_attachments) {
        return;
    }
    iTermScreenCharAttachmentRun *runs = iTermMalloc(sizeof(iTermScreenCharAttachmentRun) * width_);
    runs = iTermMalloc(width_ * sizeof(*runs));
    __block int count = 0;
    __block int i = -1;
    __block int lastIndex = -1;
    const iTermScreenCharAttachment *attachments = _attachments.attachments;
    [_attachments.validAttachments enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        const iTermScreenCharAttachment *attachment = &attachments[idx];
        if (lastIndex == -1 ||  // Always start a run for the first index
            lastIndex + 1 != idx ||  // Start a run if there was a cap
            memcmp(attachment, &attachments[lastIndex], sizeof(*attachment))) {  // Start a run if the attachment is different than the last
            i = count;
            count += 1;
            runs[i].offset = idx;
            runs[i].length = 1;
        } else {
            runs[i].length += 1;
        }
        lastIndex = idx;
    }];
    _attachmentRunArray = [iTermScreenCharAttachmentRunArray runArrayWithRuns:runs count:count];
}

- (iTermScreenCharAttachment *)attachmentAt:(int)x createIfNeeded:(BOOL)createIfNeeded {
    if (![_attachments.validAttachments containsIndex:x]) {
        if (!createIfNeeded) {
            return nil;
        }
        if (!_attachments) {
            _attachments = [[iTermMutableScreenCharAttachmentsArray alloc] initWithCount:width_];
        }
    }
    _attachmentRunArray = nil;
    return &_attachments.mutableAttachments[x];
}

- (const iTermScreenCharAttachment *)constAttachmentAt:(int)x {
    return &_attachments.attachments[x];
}

- (void)removeAttachmentAt:(int)x {
    [_attachments.mutableValidAttachments removeIndex:x];
    _attachmentRunArray = nil;
}

- (void)setAttachmentRuns:(id<iTermScreenCharAttachmentRunArray>)attachments {
    if (!attachments) {
        _attachments = nil;
        return;
    }
    _attachments = [[iTermMutableScreenCharAttachmentsArray alloc] initWithCount:width_];

    const iTermScreenCharAttachmentRun *runs = attachments.runs;
    const NSUInteger count = attachments.count;
    iTermScreenCharAttachment *outArray = _attachments.mutableAttachments;

    // Foreach run
    for (NSUInteger i = 0; i < count; i++) {
        const iTermScreenCharAttachmentRun *run = &runs[i];
        int offset = run->offset;
        assert(offset + run->length < width_);
        // Foreach cell affected by run
        for (int j = 0; j < run->length; j++) {
            memmove(&outArray[offset + j], &run->attachment, sizeof(run->attachment));
            [_attachments.mutableValidAttachments addIndex:offset + j];
        }
    }
}

- (id<iTermScreenCharAttachmentsArray>)attachments {
    return _attachments;
}

- (void)setDirty:(BOOL)dirty inRange:(VT100GridRange)range updateTimestamp:(BOOL)updateTimestamp {
#ifdef ITERM_DEBUG
    assert(range.location >= 0);
    assert(range.length >= 0);
    assert(range.location + range.length <= width_);
#endif
    const VT100GridRange before = [self dirtyRange];
    if (dirty && updateTimestamp) {
        [self updateTimestamp];
    }
    if (dirty) {
        if (start_ < 0) {
            start_ = range.location;
            bound_ = range.location + range.length;
        } else {
            start_ = MIN(start_, range.location);
            bound_ = MAX(bound_, range.location + range.length);
        }
    } else if (start_ >= 0) {
        // Unset part of the dirty region.
        int clearBound = range.location + range.length;
        if (range.location <= start_) {
            if (clearBound >= bound_) {
                start_ = bound_ = -1;
            } else if (clearBound > start_) {
                start_ = clearBound;
            }
        } else if (range.location < bound_ && clearBound >= bound_) {
            // Clear the right-hand part of the dirty region
            bound_ = range.location;
        }
    }
    const VT100GridRange after = [self dirtyRange];
    if (dirty && !VT100GridRangeEqualsRange(before, after)) {
        _generation = VT100LineInfoNextGeneration++;
    }
}

- (VT100GridRange)dirtyRange {
    return VT100GridRangeMake(start_, bound_ - start_);
}

- (void)updateTimestamp {
    self.timestamp = [NSDate timeIntervalSinceReferenceDate];
}

- (BOOL)isDirtyAtOffset:(int)x {
#if ITERM_DEBUG
    assert(x >= 0 && x < width_);
#else
    x = MIN(width_ - 1, MAX(0, x));
#endif
    return x >= start_ && x < bound_;
}

- (NSIndexSet *)dirtyIndexes {
    return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(start_, bound_ - start_)];
}

- (BOOL)anyCharIsDirty {
    return start_ >= 0;
}

- (id)copyWithZone:(NSZone *)zone {
    VT100LineInfo *theCopy = [[VT100LineInfo alloc] initWithWidth:width_];
    theCopy->start_ = start_;
    theCopy->bound_ = bound_;
    theCopy->timestamp_ = timestamp_;

    return theCopy;
}

@end
