//
//  iTermThinStrokes.h
//  iTerm2
//
//  Created by George Nachman on 2/19/18.
//

// Type for KEY_THIN_STROKES
#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

// NOTE: This cannot be NSInteger because its size varies between CPU and GPU
typedef NS_ENUM(int, iTermThinStrokesSetting) {
    iTermThinStrokesSettingNever = 0,
    iTermThinStrokesSettingRetinaDarkBackgroundsOnly = 1,
    iTermThinStrokesSettingDarkBackgroundsOnly = 2,
    iTermThinStrokesSettingAlways = 3,
    iTermThinStrokesSettingRetinaOnly = 4,
};
