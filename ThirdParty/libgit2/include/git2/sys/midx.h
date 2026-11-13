/*
 * Copyright (C) the libgit2 contributors. All rights reserved.
 *
 * This file is part of libgit2, distributed under the GNU GPL v2 with
 * a Linking Exception. For full terms see the included COPYING file.
 */
#ifndef INCLUDE_sys_git_midx_h__
#define INCLUDE_sys_git_midx_h__

#include "git2/common.h"
#include "git2/types.h"

/**
 * @file git2/sys/midx.h
 * @brief Incremental multi-pack indexes
 * @defgroup git_midx Incremental multi-pack indexes
 * @ingroup Git
 * @{
 */
GIT_BEGIN_DECL

/**
 * Options structure for `git_midx_writer_options`.
 *
 * Initialize with `GIT_MIDX_WRITER_OPTIONS_INIT`. Alternatively,
 * you can use `git_midx_writer_options_init`.
 */
typedef struct {
	unsigned int version;

#ifdef GIT_EXPERIMENTAL_SHA256
	/** The object ID type that this commit graph contains. */
	git_oid_t oid_type;
#endif
} git_midx_writer_options;

/** Current version for the `git_midx_writer_options` structure */
#define GIT_MIDX_WRITER_OPTIONS_VERSION 1

/** Static constructor for `git_midx_writer_options` */
#define GIT_MIDX_WRITER_OPTIONS_INIT { \
		GIT_MIDX_WRITER_OPTIONS_VERSION \
	}

/**
 * Initialize git_midx_writer_options structure
 *
 * Initializes a `git_midx_writer_options` with default values.
 * Equivalent to creating an instance with
 * `GIT_MIDX_WRITER_OPTIONS_INIT`.
 *
 * @param opts The `git_midx_writer_options` struct to initialize.
 * @param version The struct version; pass `GIT_MIDX_WRITER_OPTIONS_VERSION`.
 * @return Zero on success; -1 on failure.
 */
GIT_EXTERN(int) git_midx_writer_options_init(
	git_midx_writer_options *opts,
	unsigned int version);

/**
 * Create a new writer for `multi-pack-index` files.
 *
 * @param out location to store the writer pointer.
 * @param pack_dir the directory where the `.pack` and `.idx` files are. The
 * `multi-pack-index` file will be written in this directory, too.
 * @return 0 or an error code
 */
GIT_EXTERN(int) git_midx_writer_new(
		git_midx_writer **out,
		const char *pack_dir
#ifdef GIT_EXPERIMENTAL_SHA256
		, git_midx_writer_options *options
#endif
		);

/**
 * Free the multi-pack-index writer and its resources.
 *
 * @param w the writer to free. If NULL no action is taken.
 */
GIT_EXTERN(void) git_midx_writer_free(git_midx_writer *w);

/**
 * Add an `.idx` file to the writer.
 *
 * @param w the writer
 * @param idx_path the path of an `.idx` file.
 * @return 0 or an error code
 */
GIT_EXTERN(int) git_midx_writer_add(
		git_midx_writer *w,
		const char *idx_path);

/**
 * Write a `multi-pack-index` file to a file.
 *
 * @param w the writer
 * @return 0 or an error code
 */
GIT_EXTERN(int) git_midx_writer_commit(
		git_midx_writer *w);

/**
 * Dump the contents of the `multi-pack-index` to an in-memory buffer.
 *
 * @param midx Buffer where to store the contents of the `multi-pack-index`.
 * @param w the writer
 * @return 0 or an error code
 */
GIT_EXTERN(int) git_midx_writer_dump(
		git_buf *midx,
		git_midx_writer *w);

/** @} */
GIT_END_DECL

#endif
