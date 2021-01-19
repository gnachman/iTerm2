/*
 * Copyright (C) the libgit2 contributors. All rights reserved.
 *
 * This file is part of libgit2, distributed under the GNU GPL v2 with
 * a Linking Exception. For full terms see the included COPYING file.
 */

#ifndef INCLUDE_sys_git_alloc_h__
#define INCLUDE_sys_git_alloc_h__

#include "git2/common.h"

GIT_BEGIN_DECL

/**
 * An instance for a custom memory allocator
 *
 * Setting the pointers of this structure allows the developer to implement
 * custom memory allocators. The global memory allocator can be set by using
 * "GIT_OPT_SET_ALLOCATOR" with the `git_libgit2_opts` function. Keep in mind
 * that all fields need to be set to a proper function.
 */
typedef struct {
	/** Allocate `n` bytes of memory */
	void * GIT_CALLBACK(gmalloc)(size_t n, const char *file, int line);

	/**
	 * Allocate memory for an array of `nelem` elements, where each element
	 * has a size of `elsize`. Returned memory shall be initialized to
	 * all-zeroes
	 */
	void * GIT_CALLBACK(gcalloc)(size_t nelem, size_t elsize, const char *file, int line);

	/** Allocate memory for the string `str` and duplicate its contents. */
	char * GIT_CALLBACK(gstrdup)(const char *str, const char *file, int line);

	/**
	 * Equivalent to the `gstrdup` function, but only duplicating at most
	 * `n + 1` bytes
	 */
	char * GIT_CALLBACK(gstrndup)(const char *str, size_t n, const char *file, int line);

	/**
	 * Equivalent to `gstrndup`, but will always duplicate exactly `n` bytes
	 * of `str`. Thus, out of bounds reads at `str` may happen.
	 */
	char * GIT_CALLBACK(gsubstrdup)(const char *str, size_t n, const char *file, int line);

	/**
	 * This function shall deallocate the old object `ptr` and return a
	 * pointer to a new object that has the size specified by `size`. In
	 * case `ptr` is `NULL`, a new array shall be allocated.
	 */
	void * GIT_CALLBACK(grealloc)(void *ptr, size_t size, const char *file, int line);

	/**
	 * This function shall be equivalent to `grealloc`, but allocating
	 * `neleme * elsize` bytes.
	 */
	void * GIT_CALLBACK(greallocarray)(void *ptr, size_t nelem, size_t elsize, const char *file, int line);

	/**
	 * This function shall allocate a new array of `nelem` elements, where
	 * each element has a size of `elsize` bytes.
	 */
	void * GIT_CALLBACK(gmallocarray)(size_t nelem, size_t elsize, const char *file, int line);

	/**
	 * This function shall free the memory pointed to by `ptr`. In case
	 * `ptr` is `NULL`, this shall be a no-op.
	 */
	void GIT_CALLBACK(gfree)(void *ptr);
} git_allocator;

/**
 * Initialize the allocator structure to use the `stdalloc` pointer.
 *
 * Set up the structure so that all of its members are using the standard
 * "stdalloc" allocator functions. The structure can then be used with
 * `git_allocator_setup`.
 *
 * @param allocator The allocator that is to be initialized.
 * @return An error code or 0.
 */
int git_stdalloc_init_allocator(git_allocator *allocator);

/**
 * Initialize the allocator structure to use the `crtdbg` pointer.
 *
 * Set up the structure so that all of its members are using the "crtdbg"
 * allocator functions. Note that this allocator is only available on Windows
 * platforms and only if libgit2 is being compiled with "-DMSVC_CRTDBG".
 *
 * @param allocator The allocator that is to be initialized.
 * @return An error code or 0.
 */
int git_win32_crtdbg_init_allocator(git_allocator *allocator);

GIT_END_DECL

#endif
