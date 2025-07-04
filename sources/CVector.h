//
//  CVector.h
//  iTerm
//
//  Created by George Nachman on 3/5/14.
//
//

#import <Foundation/Foundation.h>

#import "iTermMalloc.h"
#import "iTermMetadata.h"
#import "ScreenChar.h"

// A vector of pointers that is fast and simple.
typedef struct {
    int capacity;
    void **elements;
    int count;
} CVector;

NS_INLINE void CVectorCreate(CVector *vector, int capacity) {
    vector->capacity = capacity;
    vector->elements = (void **)iTermMalloc(vector->capacity * sizeof(void *));
    vector->count = 0;
}

NS_INLINE void CVectorDestroy(const CVector *vector) {
    free(vector->elements);
}

NS_INLINE void *CVectorGet(const CVector *vector, int index) {
    return vector->elements[index];
}

NS_INLINE int CVectorCount(const CVector *vector) {
    return vector->count;
}

NS_INLINE id CVectorGetObject(const CVector *vector, int index) {
    return (__bridge id) vector->elements[index];
}

NS_INLINE void CVectorSet(const CVector *vector, int index, void *value) {
    vector->elements[index] = value;
}

NS_INLINE void CVectorAppend(CVector *vector, void *value) {
    if (vector->count + 1 == vector->capacity) {
        assert(vector->capacity >= 0 && vector->capacity < (1 << 27));
        vector->capacity *= 2;
        vector->elements = (void **)iTermRealloc(vector->elements, vector->capacity, sizeof(void *));
    }
    vector->elements[vector->count++] = value;
}

NS_INLINE id CVectorLastObject(const CVector *vector) {
    if (vector->count == 0) {
        return nil;
    }
    return (__bridge id)(CVectorGet(vector, vector->count - 1));
}

// Call -release on all objects in `vector`.
void CVectorReleaseObjects(const CVector *vector);

// Hacky but fast templates in C.
//
// CTVector(double) myVector;
// CTVectorCreate(&myVector, 1);
// CTVectorAppend(&myVector, 123.456);
// CTVectorAppend(&myVector, 987.654);
// NSLog(@"Value is %f", CTVectorGet(&myVector, 0));
// CTVectorDestroy(&myVector);
//
// To pass a vector:
// static void DoSomething(CTVector(double) *vector) {
//   CTVectorAppend(vector, 123.456);
// }
//
// static void Caller() {
//   CTVector(double) myVector;
//   CTVectorCreate(&myVector, 1);
//   DoSomething(&myVector);
//   ...
// }
//
// All vector types must be defined at the bottom of this file with CTVectorDefine(t).

#define CTVector(__type) CTVector_##__type

#define CTVectorDefine(__type) \
typedef struct { \
    int capacity; \
    __type *elements; \
    int count; \
} CTVector(__type)

#define CTVectorCreate(__vector, __capacity) \
do { \
  __typeof(__vector) __v = __vector; \
  \
  __v->capacity = (__capacity < 1 ? 1 : __capacity); \
  __v->elements = (__typeof(__v->elements))iTermMalloc(__v->capacity * sizeof(*__v->elements)); \
  __v->count = 0; \
} while(0)

#define CTVectorDestroy(__vector) CVectorDestroy((CVector *)(__vector))
#define CTVectorGet(__vector, __index) (__vector)->elements[(__index)]
#define CTVectorCount(__vector) (__vector)->count
#define CTVectorSet(__vector, __index, __value) (__vector)->elements[(__index)] = (__value)
#define CTVectorAppend(__vector, __value) do { \
  __typeof(__vector) __v = (__vector); \
  \
  while (__v->count + 1 >= __v->capacity) { \
    assert(__v->capacity >= 0 && __v->capacity < (1 << 27)); \
    __v->capacity *= 2; \
    __v->capacity += 1; \
    __v->elements = iTermRealloc(__v->elements, __v->capacity, sizeof(*__v->elements)); \
  } \
  __v->elements[__v->count++] = (__value); \
} while(0)
#define CTVectorElementsFromIndex(__vector, __index) (__vector)->elements + __index

typedef struct {
    int tokenIndex;
    int startOffset;
    int length;
    int startX;
    int startY;
    int endX;
    int endY;
    int hard;
} WrappedLineInfo;

typedef struct {
    const struct screen_char_t *buffer;
    int length;
    int partial;
    iTermImmutableMetadata metadata;
    screen_char_t continuation;
} iTermAppendItem;

// Registry for typed vectors.
CTVectorDefine(CGFloat);
CTVectorDefine(float);
CTVectorDefine(double);
CTVectorDefine(int);
CTVectorDefine(short);
CTVectorDefine(char);
CTVectorDefine(NSInteger);
CTVectorDefine(NSUInteger);
CTVectorDefine(WrappedLineInfo);
CTVectorDefine(iTermAppendItem);

#define CTVectorGetData(__v) \
[NSData dataWithBytes:(void *)(__v)->elements length:(__v)->count * sizeof(*(__v)->elements)]

#define CTVectorCreateFromData(__vector, __data) \
do { \
  __typeof(__vector) __v = __vector; \
  \
  __v->count = __data.length / sizeof(*__v->elements); \
  __v->capacity = __v->count; \
  __v->elements = (__typeof(__v->elements))iTermMalloc(__data.length); \
  memmove((void *)__v->elements, (void *)__data.bytes, __data.length); \
} while(0)

