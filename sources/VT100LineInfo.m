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
    BOOL _dirty;
    iTermMutableScreenCharAttachmentsArray *_attachments;
}

static NSInteger VT100LineInfoNextGeneration = 1;

@synthesize timestamp = timestamp_;

- (instancetype)initWithWidth:(int)width {
    self = [super init];
    if (self) {
        width_ = width;
    }
    return self;
}

- (void)setAttachments:(id<iTermScreenCharAttachmentsArray>)source {
    if (!source || source.count == 0) {
        _attachments = nil;
        return;
    }

    assert(source.count == width_);
    _attachments = [[iTermMutableScreenCharAttachmentsArray alloc] initWithCount:width_];
    [_attachments copyAttachmentsInRange:NSMakeRange(0, width_)
                                    from:source];
}

- (iTermMutableScreenCharAttachmentsArray *)maybeAttachments {
    return _attachments;
}

- (BOOL)hasAttachments {
    if (!_attachments) {
        return NO;
    }
    return _attachments.validAttachments.count > 0;
}

- (id<iTermScreenCharAttachmentsArray>)attachments {
    if (!_attachments) {
        _attachments = [[iTermMutableScreenCharAttachmentsArray alloc] initWithCount:width_];
    }
    return _attachments;
}

- (void)setDirty:(BOOL)dirty {
    if (dirty) {
        _dirty = NO;
        _attachments.dirty = NO;
        return;
    }
    _dirty = YES;
    self.timestamp = [NSDate timeIntervalSinceReferenceDate];
    _generation = VT100LineInfoNextGeneration++;
}

- (void)markDirtyWithoutUpdatingTimestamp {
    _dirty = YES;
    _generation = VT100LineInfoNextGeneration++;
}

- (BOOL)isDirty {
    return _dirty || _attachments.dirty;
}

- (id)copyWithZone:(NSZone *)zone {
    VT100LineInfo *theCopy = [[VT100LineInfo alloc] initWithWidth:width_];
    theCopy->_dirty = _dirty;
    theCopy->timestamp_ = timestamp_;
    theCopy->_attachments = self.hasAttachments ? [_attachments mutableCopy] : nil;
    return theCopy;
}

@end
