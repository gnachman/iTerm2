/*
 * Copyright (C) the libgit2 contributors. All rights reserved.
 *
 * This file is part of libgit2, distributed under the GNU GPL v2 with
 * a Linking Exception. For full terms see the included COPYING file.
 */
#ifndef INCLUDE_git_filter_h__
#define INCLUDE_git_filter_h__

#include "common.h"
#include "types.h"
#include "oid.h"
#include "buffer.h"

/**
 * @file git2/filter.h
 * @brief Git filter APIs
 *
 * @ingroup Git
 * @{
 */
GIT_BEGIN_DECL

/**
 * Filters are applied in one of two directions: smudging - which is
 * exporting a file from the Git object database to the working directory,
 * and cleaning - which is importing a file from the working directory to
 * the Git object database.  These values control which direction of
 * change is being applied.
 */
typedef enum {
	GIT_FILTER_TO_WORKTREE = 0,
	GIT_FILTER_SMUDGE = GIT_FILTER_TO_WORKTREE,
	GIT_FILTER_TO_ODB = 1,
	GIT_FILTER_CLEAN = GIT_FILTER_TO_ODB,
} git_filter_mode_t;

/**
 * Filter option flags.
 */
typedef enum {
	GIT_FILTER_DEFAULT = 0u,

	/** Don't error for `safecrlf` violations, allow them to continue. */
	GIT_FILTER_ALLOW_UNSAFE = (1u << 0),

	/** Don't load `/etc/gitattributes` (or the system equivalent) */
	GIT_FILTER_NO_SYSTEM_ATTRIBUTES = (1u << 1),

	/** Load attributes from `.gitattributes` in the root of HEAD */
	GIT_FILTER_ATTRIBUTES_FROM_HEAD = (1u << 2),
} git_filter_flag_t;

/**
 * A filter that can transform file data
 *
 * This represents a filter that can be used to transform or even replace
 * file data.  Libgit2 includes one built in filter and it is possible to
 * write your own (see git2/sys/filter.h for information on that).
 *
 * The two builtin filters are:
 *
 * * "crlf" which uses the complex rules with the "text", "eol", and
 *   "crlf" file attributes to decide how to convert between LF and CRLF
 *   line endings
 * * "ident" which replaces "$Id$" in a blob with "$Id: <blob OID>$" upon
 *   checkout and replaced "$Id: <anything>$" with "$Id$" on checkin.
 */
typedef struct git_filter git_filter;

/**
 * List of filters to be applied
 *
 * This represents a list of filters to be applied to a file / blob.  You
 * can build the list with one call, apply it with another, and dispose it
 * with a third.  In typical usage, there are not many occasions where a
 * git_filter_list is needed directly since the library will generally
 * handle conversions for you, but it can be convenient to be able to
 * build and apply the list sometimes.
 */
typedef struct git_filter_list git_filter_list;

/**
 * Load the filter list for a given path.
 *
 * This will return 0 (success) but set the output git_filter_list to NULL
 * if no filters are requested for the given file.
 *
 * @param filters Output newly created git_filter_list (or NULL)
 * @param repo Repository object that contains `path`
 * @param blob The blob to which the filter will be applied (if known)
 * @param path Relative path of the file to be filtered
 * @param mode Filtering direction (WT->ODB or ODB->WT)
 * @param flags Combination of `git_filter_flag_t` flags
 * @return 0 on success (which could still return NULL if no filters are
 *         needed for the requested file), <0 on error
 */
GIT_EXTERN(int) git_filter_list_load(
	git_filter_list **filters,
	git_repository *repo,
	git_blob *blob, /* can be NULL */
	const char *path,
	git_filter_mode_t mode,
	uint32_t flags);

/**
 * Query the filter list to see if a given filter (by name) will run.
 * The built-in filters "crlf" and "ident" can be queried, otherwise this
 * is the name of the filter specified by the filter attribute.
 *
 * This will return 0 if the given filter is not in the list, or 1 if
 * the filter will be applied.
 *
 * @param filters A loaded git_filter_list (or NULL)
 * @param name The name of the filter to query
 * @return 1 if the filter is in the list, 0 otherwise
 */
GIT_EXTERN(int) git_filter_list_contains(
	git_filter_list *filters,
	const char *name);

/**
 * Apply filter list to a data buffer.
 *
 * See `git2/buffer.h` for background on `git_buf` objects.
 *
 * If the `in` buffer holds data allocated by libgit2 (i.e. `in->asize` is
 * not zero), then it will be overwritten when applying the filters.  If
 * not, then it will be left untouched.
 *
 * If there are no filters to apply (or `filters` is NULL), then the `out`
 * buffer will reference the `in` buffer data (with `asize` set to zero)
 * instead of allocating data.  This keeps allocations to a minimum, but
 * it means you have to be careful about freeing the `in` data since `out`
 * may be pointing to it!
 *
 * @param out Buffer to store the result of the filtering
 * @param filters A loaded git_filter_list (or NULL)
 * @param in Buffer containing the data to filter
 * @return 0 on success, an error code otherwise
 */
GIT_EXTERN(int) git_filter_list_apply_to_data(
	git_buf *out,
	git_filter_list *filters,
	git_buf *in);

/**
 * Apply a filter list to the contents of a file on disk
 *
 * @param out buffer into which to store the filtered file
 * @param filters the list of filters to apply
 * @param repo the repository in which to perform the filtering
 * @param path the path of the file to filter, a relative path will be
 * taken as relative to the workdir
 */
GIT_EXTERN(int) git_filter_list_apply_to_file(
	git_buf *out,
	git_filter_list *filters,
	git_repository *repo,
	const char *path);

/**
 * Apply a filter list to the contents of a blob
 *
 * @param out buffer into which to store the filtered file
 * @param filters the list of filters to apply
 * @param blob the blob to filter
 */
GIT_EXTERN(int) git_filter_list_apply_to_blob(
	git_buf *out,
	git_filter_list *filters,
	git_blob *blob);

/**
 * Apply a filter list to an arbitrary buffer as a stream
 *
 * @param filters the list of filters to apply
 * @param data the buffer to filter
 * @param target the stream into which the data will be written
 */
GIT_EXTERN(int) git_filter_list_stream_data(
	git_filter_list *filters,
	git_buf *data,
	git_writestream *target);

/**
 * Apply a filter list to a file as a stream
 *
 * @param filters the list of filters to apply
 * @param repo the repository in which to perform the filtering
 * @param path the path of the file to filter, a relative path will be
 * taken as relative to the workdir
 * @param target the stream into which the data will be written
 */
GIT_EXTERN(int) git_filter_list_stream_file(
	git_filter_list *filters,
	git_repository *repo,
	const char *path,
	git_writestream *target);

/**
 * Apply a filter list to a blob as a stream
 *
 * @param filters the list of filters to apply
 * @param blob the blob to filter
 * @param target the stream into which the data will be written
 */
GIT_EXTERN(int) git_filter_list_stream_blob(
	git_filter_list *filters,
	git_blob *blob,
	git_writestream *target);

/**
 * Free a git_filter_list
 *
 * @param filters A git_filter_list created by `git_filter_list_load`
 */
GIT_EXTERN(void) git_filter_list_free(git_filter_list *filters);


GIT_END_DECL

/** @} */

#endif
