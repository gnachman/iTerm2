//
//  CPKLogging.h
//  ColorPicker
//
//  Created by George Nachman on 4/24/24.
//  Copyright © 2024 Google. All rights reserved.
//

#define CPK_VERBOSE_LOGGING 0

#if CPK_VERBOSE_LOGGING
#define CPKLog(format...) NSLog(format)
#else
#define CPKLog(format...)
#endif
