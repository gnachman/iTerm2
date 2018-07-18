//
//  iTermMetalDebugInfo.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/28/18.
//

#import <Foundation/Foundation.h>

#import <MetalKit/MetalKit.h>

NS_CLASS_AVAILABLE(10_11, NA)
@protocol iTermMetalDebugInfoFormatter<NSObject>

@optional
- (void)writeVertexBuffer:(id<MTLBuffer>)buffer index:(NSUInteger)index toFolder:(NSURL *)folder;
- (void)writeFragmentBuffer:(id<MTLBuffer>)buffer index:(NSUInteger)index toFolder:(NSURL *)folder;
- (void)writeFragmentTexture:(id<MTLTexture>)texture index:(NSUInteger)index toFolder:(NSURL *)folder;

@end

@class iTermMetalRowData;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalDebugDrawInfo : NSObject

@property (nonatomic, copy) NSString *fragmentFunctionName;
@property (nonatomic, copy) NSString *vertexFunctionName;
@property (nonatomic, weak) id<iTermMetalDebugInfoFormatter> formatter;
@property (nonatomic, copy) NSString *name;

- (void)setVertexBuffer:(id<MTLBuffer>)buffer atIndex:(NSUInteger)index;
- (void)setFragmentBuffer:(id<MTLBuffer>)buffer atIndex:(NSUInteger)index;
- (void)setFragmentTexture:(id <MTLTexture>)texture atIndex:(NSUInteger)index;
- (void)drawWithVertexCount:(NSUInteger)vertexCount
              instanceCount:(NSUInteger)instanceCount;

@end

@protocol iTermMetalCellRenderer;
@class iTermMetalRendererTransientState;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalDebugInfo : NSObject

@property (nonatomic, readonly) NSUInteger numberOfRecordedDraws;

- (void)setRenderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor;
- (void)setPostmultipliedRenderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor NS_AVAILABLE_MAC(10_14);
- (void)setIntermediateRenderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor;
- (void)setTemporaryRenderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor;
- (void)addRowData:(iTermMetalRowData *)rowData;
- (void)addTransientState:(iTermMetalRendererTransientState *)tState;
- (void)addCellRenderer:(id<iTermMetalCellRenderer>)renderer;
- (iTermMetalDebugDrawInfo *)newDrawWithFormatter:(id<iTermMetalDebugInfoFormatter>)formatter;
- (void)addRenderOutputData:(NSData *)data
                       size:(CGSize)size
             transientState:(iTermMetalRendererTransientState *)tState;

- (NSData *)newArchive;

@end
