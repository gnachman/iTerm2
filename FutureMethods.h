//
//  FutureMethods.h
//  iTerm
//
//  Created by George Nachman on 8/29/11.
//

#import <Cocoa/Cocoa.h>

#ifdef BLOCKS_NOT_AVAILABLE
// OS 10.5 Compatibility

@protocol NSControlTextEditingDelegate
@end

@protocol NSMenuDelegate
@end

@protocol NSNetServiceBrowserDelegate
@end

@protocol NSNetServiceDelegate
@end

@protocol NSSplitViewDelegate
@end

@protocol NSTableViewDataSource
@end

@protocol NSTableViewDelegate
@end

@protocol NSTextFieldDelegate
@end

@protocol NSTextViewDelegate
@end

@protocol NSTokenFieldDelegate
@end

@protocol NSToolbarDelegate
@end

@protocol NSWindowDelegate
@end

#endif

// From proc_info.h, available on 10.7 and 10.8 only.
#define FUTURE_PROC_PIDT_SHORTBSDINFO		13
#define FUTURE_MAXCOMLEN 16
struct future_proc_bsdshortinfo {
  uint32_t                pbsi_pid;		/* process id */
  uint32_t                pbsi_ppid;		/* process parent id */
  uint32_t                pbsi_pgid;		/* process perp id */
  int32_t                pbsi_status;		/* p_stat value, SZOMB, SRUN, etc */
  char                    pbsi_comm[FUTURE_MAXCOMLEN];	/* upto 16 characters of process name */
  uint32_t                pbsi_flags;              /* 64bit; emulated etc */
  uid_t                   pbsi_uid;		/* current uid on process */
  gid_t                   pbsi_gid;		/* current gid on process */
  uid_t                   pbsi_ruid;		/* current ruid on process */
  gid_t                   pbsi_rgid;		/* current tgid on process */
  uid_t                   pbsi_svuid;		/* current svuid on process */
  gid_t                   pbsi_svgid;		/* current svgid on process */
  uint32_t                pbsi_rfu;		/* reserved for future use*/
};

extern const int FutureNSWindowCollectionBehaviorStationary;

@interface NSView (Future)
- (void)futureSetAcceptsTouchEvents:(BOOL)value;
- (void)futureSetWantsRestingTouches:(BOOL)value;
- (NSRect)futureConvertRectToScreen:(NSRect)rect;
- (NSRect)futureConvertRectFromScreen:(NSRect)rect;
@end

@interface NSEvent (Future)
- (NSArray *)futureTouchesMatchingPhase:(int)phase inView:(NSView *)view;
@end

@interface NSWindow (Future)
- (void)futureSetRestorable:(BOOL)value;
- (void)futureSetRestorationClass:(Class)class;
- (void)futureInvalidateRestorableState;
@end

enum {
    FutureNSScrollerStyleLegacy       = 0,
    FutureNSScrollerStyleOverlay      = 1
};
typedef NSInteger FutureNSScrollerStyle;

@interface NSScroller (Future)
- (FutureNSScrollerStyle)futureScrollerStyle;
@end

@interface NSScrollView (Future)
- (FutureNSScrollerStyle)futureScrollerStyle;
@end

@interface CIImage (Future)
@end

@interface NSObject (Future)
- (BOOL)performSelectorReturningBool:(SEL)selector withObjects:(NSArray *)objects;
@end

@interface NSScroller (future)
- (void)futureSetKnobStyle:(NSInteger)newKnobStyle;
@end
