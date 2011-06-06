//
//  GTMObjectSingleton.h
//  Macro to implement methods for a singleton
//
//  Copyright 2005-2008 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not
//  use this file except in compliance with the License.  You may obtain a copy
//  of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
//  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
//  License for the specific language governing permissions and limitations under
//  the License.
//

#import "GTMDefines.h"

/// This macro implements the various methods needed to make a safe singleton.
//
/// This Singleton pattern was taken from:
/// http://developer.apple.com/documentation/Cocoa/Conceptual/CocoaFundamentals/CocoaObjects/chapter_3_section_10.html
///
/// Sample usage:
///
/// GTMOBJECT_SINGLETON_BOILERPLATE(SomeUsefulManager, sharedSomeUsefulManager)
/// (with no trailing semicolon)
///
#define GTMOBJECT_SINGLETON_BOILERPLATE(_object_name_, _shared_obj_name_) \
static _object_name_ *z##_shared_obj_name_ = nil;  \
+ (_object_name_ *)_shared_obj_name_ {             \
  @synchronized(self) {                            \
    if (z##_shared_obj_name_ == nil) {             \
      /* Note that 'self' may not be the same as _object_name_ */                               \
      /* first assignment done in allocWithZone but we must reassign in case init fails */      \
      z##_shared_obj_name_ = [[self alloc] init];                                               \
      _GTMDevAssert((z##_shared_obj_name_ != nil), @"didn't catch singleton allocation");       \
    }                                              \
  }                                                \
  return z##_shared_obj_name_;                     \
}                                                  \
+ (id)allocWithZone:(NSZone *)zone {               \
  @synchronized(self) {                            \
    if (z##_shared_obj_name_ == nil) {             \
      z##_shared_obj_name_ = [super allocWithZone:zone]; \
      return z##_shared_obj_name_;                 \
    }                                              \
  }                                                \
                                                   \
  /* We can't return the shared instance, because it's been init'd */ \
  _GTMDevAssert(NO, @"use the singleton API, not alloc+init");        \
  return nil;                                      \
}                                                  \
- (id)retain {                                     \
  return self;                                     \
}                                                  \
- (NSUInteger)retainCount {                        \
  return NSUIntegerMax;                            \
}                                                  \
- (void)release {                                  \
}                                                  \
- (id)autorelease {                                \
  return self;                                     \
}                                                  \
- (id)copyWithZone:(NSZone *)zone {                \
  GTM_UNUSED(zone);                                \
  return self;                                     \
}                                                  \

