// Fixture: macros of every kind. Line numbers are part of the expectations.
#pragma once
#import "mbase.h"
#import <sdkmacros.h>
#define LIMIT 10
#define SQUARE(x) ((x) * (x))
#define LOGF(fmt, ...) Logf(fmt, __VA_ARGS__)
#define NAME_OF(x) #x
#define GETTER(name) get_##name
#define SEND_LOG(obj, text) [obj log:text]
#define CALL(obj, sel) [obj sel]
#define SELF_COUNT (self->_count + _count)
#define RETURN_IF(c) do { if (c) return 0; } while (0)
#define LOOP_BREAK for (;;) { break; }
#define ESCAPE_BREAK break
#define WHERE __FILE__, __LINE__, __func__
#define TWICE(e) SQUARE(e)
#define ITBetaAssert(condition, args...) do { if (!(condition)) { LogObj(args); } } while (0)
#define ITNonnilLock(lockExpression) \
  ({ \
    id it_nonnilLock_ = (lockExpression); \
    ITBetaAssert(it_nonnilLock_ != nil, @"@synchronized(%s) at %s:%d has a nil lock and runs unprotected", \
                 #lockExpression, __FILE__, __LINE__); \
    it_nonnilLock_; \
  })
#define DEFINE_GETTER(name) + (int)name { return LIMIT; }
#define DECLARE_CLASS(name) @interface name : MRoot @end
#define NOT_RETAINED __attribute__((objc_method_family(none)))
#define LEAKY(name) static int name##_storage = 0;
#define AS_TYPE(T, v) ((T)(v) + sizeof(T))
#define FIRST_ONLY(a, b) (a)
#define RUN_BLOCK(x) ^{ x; }
#define LOCKED(o, s) @synchronized(o) { s; }
#define SETTER_FOR(Name) [self set##Name:0]
#define REDEFINED 1
#undef REDEFINED
#define REDEFINED 2
#if MODE == 1
#define KIND 1
#elif MODE == 2
#define KIND 2
#else
#define KIND 3
#endif
#if 0
#define NEVER 1
#endif
#if __has_include(<sdkmacros.h>)
#define HAS_SDK 1
#endif
#if __has_include("missing_header.h")
#define HAS_MISSING 1
#endif
#ifdef MODE
#define HAS_MODE 1
#endif
#define PING_SELECTOR @selector(ping)
#define CMD_NAME _cmd
#define BLOCK_OF(x) [^id() { return [self x]; } copy]
void Logf(const char *fmt, ...);
void LogObj(NSString *fmt, ...);
