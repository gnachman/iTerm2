/*
 * Copyright (C) the libgit2 contributors. All rights reserved.
 *
 * This file is part of libgit2, distributed under the GNU GPL v2 with
 * a Linking Exception. For full terms see the included COPYING file.
 */
#ifndef INCLUDE_git_buf_h__
#define INCLUDE_git_buf_h__

#include "common.h"

/**
 * @file git2/buffer.h
 * @brief Buffer export structure
 *
 * @ingroup Git
 * @{
 */
GIT_BEGIN_DECL

/**
 * A data buffer for exporting data from libgit2
 *
 * Sometimes libgit2 wants to return an allocated data buffer to the
 * caller and have the caller take responsibility for freeing that memory.
 * This can be awkward if the caller does not have easy access to the same
 * allocation functions that libgit2 is using.  In those cases, libgit2
 * will fill in a `git_buf` and the caller can use `git_buf_dispose()` to
 * release it when they are done.
 *
 * A `git_buf` may also be used for the caller to pass in a reference to
 * a block of memory they hold.  In this case, libgit2 will not resize or
 * free the memory, but will read from it as needed.
 *
 * Some APIs may occasionally do something slightly unusual with a buffer,
 * such as setting `ptr` to a value that was passed in by the user.  In
 * those cases, the behavior will be clearly documented by the API.
 */
typedef struct {
	/**
	 * The buffer contents.
	 *
	 * `ptr` points to the start of the allocated memory.  If it is NULL,
	 * then the `git_buf` is considered empty and libgit2 will feel free
	 * to overwrite it with new data.
	 */
	char   *ptr;

	/**
	 * `asize` holds the known total amount of allocated memory if the `ptr`
	 *  was allocated by libgit2.  It may be larger than `size`.  If `ptr`
	 *  was not allocated by libgit2 and should not be resized and/or freed,
	 *  then `asize` will be set to zero.
	 */
	size_t asize;

	/**
	 * `size` holds the size (in bytes) of the data that is actually used.
	 */
	size_t size;
} git_buf;

/**
 * Static initializer for git_buf from static buffer
 */
#define GIT_BUF_INIT_CONST(STR,LEN) { (char *)(STR), 0, (size_t)(LEN) }

/**
 * Free the memory referred to by the git_buf.
 *
 * Note that this does not free the `git_buf` itself, just the memory
 * pointed to by `buffer->ptr`.  This will not free the memory if it looks
 * like it was not allocated internally, but it will clear the buffer back
 * to the empty state.
 *
 * @param buffer The buffer to deallocate
 */
GIT_EXTERN(void) git_buf_dispose(git_buf *buffer);

/**
 * Resize the buffer allocation to make more space.
 *
 * This will attempt to grow the buffer to accommodate the target size.
 *
 * If the buffer refers to memory that was not allocated by libgit2 (i.e.
 * the `asize` field is zero), then `ptr` will be replaced with a newly
 * allocated block of data.  Be careful so that memory allocated by the
 * caller is not lost.  As a special variant, if you pass `target_size` as
 * 0 and the memory is not allocated by libgit2, this will allocate a new
 * buffer of size `size` and copy the external data into it.
 *
 * Currently, this will never shrink a buffer, only expand it.
 *
 * If the allocation fails, this will return an error and the buffer will be
 * marked as invalid for future operations, invaliding the contents.
 *
 * @param buffer The buffer to be resized; may or may not be allocated yet
 * @param target_size The desired available size
 * @return 0 on success, -1 on allocation failure
 */
GIT_EXTERN(int) git_buf_grow(git_buf *buffer, size_t target_size);

/**
 * Set buffer to a copy of some raw data.
 *
 * @param buffer The buffer to set
 * @param data The data to copy into the buffer
 * @param datalen The length of the data to copy into the buffer
 * @return 0 on success, -1 on allocation failure
 */
GIT_EXTERN(int) git_buf_set(
	git_buf *buffer, const void *data, size_t datalen);

/**
* Check quickly if buffer looks like it contains binary data
*
* @param buf Buffer to check
* @return 1 if buffer looks like non-text data
*/
GIT_EXTERN(int) git_buf_is_binary(const git_buf *buf);

/**
* Check quickly if buffer contains a NUL byte
*
* @param buf Buffer to check
* @return 1 if buffer contains a NUL byte
*/
GIT_EXTERN(int) git_buf_contains_nul(const git_buf *buf);

GIT_END_DECL

/** @} */

#endif
