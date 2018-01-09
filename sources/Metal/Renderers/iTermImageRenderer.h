#import "iTermASCIITexture.h"
#import "iTermMetalCellRenderer.h"
#import "iTermMetalGlyphKey.h"
#import "iTermTextRendererCommon.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermImageInfo;

// Describes a horizontal run of image cells for the same image.
NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalImageRun : NSObject
@property (nonatomic) VT100GridCoord startingCoordInImage;
@property (nonatomic) VT100GridCoord startingCoordOnScreen;
@property (nonatomic) int length;
@property (nonatomic) unichar code;
@property (nonatomic, strong) iTermImageInfo *imageInfo;
@end


NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermImageRendererTransientState : iTermMetalCellRendererTransientState

@property (nonatomic, readonly) NSSet<NSString *> *missingImageUniqueIdentifiers;
@property (nonatomic, readonly) NSSet<NSString *> *foundImageUniqueIdentifiers;
@property (nonatomic, readonly) NSSet<NSNumber *> *animatedLines;  // absolute line numbers

// NOTE: The driver must set this for `animatedLines` to contain proper values!
@property (nonatomic) long long firstVisibleAbsoluteLineNumber;

- (void)addRun:(iTermMetalImageRun *)imageRun;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermImageRenderer : NSObject<iTermMetalCellRenderer>

- (instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

