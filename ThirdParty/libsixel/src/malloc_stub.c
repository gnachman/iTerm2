/*
 * Copyright (c) 2014-2016 Hayaki Saito
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#include "config.h"

#if STDC_HEADERS
# include <stdlib.h>
#endif  /* STDC_HEADERS */
#if HAVE_SYS_TYPES_H
# include <sys/types.h>
#endif  /* HAVE_SYS_TYPES_H */
#if HAVE_ERRNO_H
# include <errno.h>
#endif  /* HAVE_ERRNO_H */
#if HAVE_MEMORY_H
# include <memory.h>
#endif  /* HAVE_MEMORY_H */

#if !HAVE_MALLOC
#undef malloc
void *
rpl_malloc(size_t n)
{
    if(n == 0) {
        n = 1;
    }
    return (void *)malloc(n);
}
#endif /* !HAVE_MALLOC */

#if !HAVE_REALLOC
#undef realloc
void *
rpl_realloc(void *p, size_t n)
{
    if (n == 0) {
        n = 1;
    }
    if (p == 0) {
        return malloc(n);
    }
    return (void *)realloc(p, n);
}
#endif /* !HAVE_REALLOC */

#if 0
int
rpl_posix_memalign(void **memptr, size_t alignment, size_t size)
{
#if HAVE_POSIX_MEMALIGN
    return posix_memalign(memptr, alignment, size);
#elif HAVE_ALIGNED_ALLOC
    *memptr = aligned_alloc(alignment, size);
    return *memptr ? 0: ENOMEM;
#elif HAVE_MEMALIGN
    *memptr = memalign(alignment, size);
    return *memptr ? 0: ENOMEM;
#elif HAVE__ALIGNED_MALLOC
    return _aligned_malloc(size, alignment);
#else
# error
#endif /* _MSC_VER */
}
#endif

/* emacs Local Variables:      */
/* emacs mode: c               */
/* emacs tab-width: 4          */
/* emacs indent-tabs-mode: nil */
/* emacs c-basic-offset: 4     */
/* emacs End:                  */
/* vim: set expandtab ts=4 sts=4 sw=4 : */
/* EOF */
