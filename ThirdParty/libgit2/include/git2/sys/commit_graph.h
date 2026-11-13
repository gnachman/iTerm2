/*
 * Copyright (C) the libgit2 contributors. All rights reserved.
 *
 * This file is part of libgit2, distributed under the GNU GPL v2 with
 * a Linking Exception. For full terms see the included COPYING file.
 */
#ifndef INCLUDE_sys_git_commit_graph_h__
#define INCLUDE_sys_git_commit_graph_h__

#include "git2/common.h"
#include "git2/types.h"

/**
 * @file git2/sys/commit_graph.h
 * @brief Commit graphs store information about commit relationships
 * @defgroup git_commit_graph Commit graphs
 * @ingroup Git
 * @{
 */
GIT_BEGIN_DECL

/**
 * Options structure for `git_commit_graph_open_new`.
 *
 * Initialize with `GIT_COMMIT_GRAPH_OPEN_OPTIONS_INIT`. Alternatively,
 * you can use `git_commit_graph_open_options_init`.
 */
typedef struct {
	unsigned int version;

#ifdef GIT_EXPERIMENTAL_SHA256
	/** The object ID type that this commit graph contains. */
	git_oid_t oid_type;
#endif
} git_commit_graph_open_options;

/** Current version for the `git_commit_graph_open_options` structure */
#define GIT_COMMIT_GRAPH_OPEN_OPTIONS_VERSION 1

/** Static constructor for `git_commit_graph_open_options` */
#define GIT_COMMIT_GRAPH_OPEN_OPTIONS_INIT { \
		GIT_COMMIT_GRAPH_OPEN_OPTIONS_VERSION \
	}

/**
 * Initialize git_commit_graph_open_options structure
 *
 * Initializes a `git_commit_graph_open_options` with default values.
 * Equivalent to creating an instance with
 * `GIT_COMMIT_GRAPH_OPEN_OPTIONS_INIT`.
 *
 * @param opts The `git_commit_graph_open_options` struct to initialize.
 * @param version The struct version; pass `GIT_COMMIT_GRAPH_OPEN_OPTIONS_VERSION`.
 * @return Zero on success; -1 on failure.
 */
GIT_EXTERN(int) git_commit_graph_open_options_init(
	git_commit_graph_open_options *opts,
	unsigned int version);


/**
 * Opens a `git_commit_graph` from a path to an objects directory.
 *
 * This finds, opens, and validates the `commit-graph` file.
 *
 * @param cgraph_out the `git_commit_graph` struct to initialize.
 * @param objects_dir the path to a git objects directory.
 * @return Zero on success; -1 on failure.
 */
GIT_EXTERN(int) git_commit_graph_open(
	git_commit_graph **cgraph_out,
	const char *objects_dir
#ifdef GIT_EXPERIMENTAL_SHA256
	, const git_commit_graph_open_options *options
#endif
	);

/**
 * Frees commit-graph data. This should only be called when memory allocated
 * using `git_commit_graph_open` is not returned to libgit2 because it was not
 * associated with the ODB through a successful call to
 * `git_odb_set_commit_graph`.
 *
 * @param cgraph the commit-graph object to free. If NULL, no action is taken.
 */
GIT_EXTERN(void) git_commit_graph_free(git_commit_graph *cgraph);


/**
 * The strategy to use when adding a new set of commits to a pre-existing
 * commit-graph chain.
 */
typedef enum {
	/**
	 * Do not split commit-graph files. The other split strategy-related option
	 * fields are ignored.
	 */
	GIT_COMMIT_GRAPH_SPLIT_STRATEGY_SINGLE_FILE = 0
} git_commit_graph_split_strategy_t;

/**
 * Options structure for `git_commit_graph_writer_new`.
 *
 * Initialize with `GIT_COMMIT_GRAPH_WRITER_OPTIONS_INIT`. Alternatively,
 * you can use `git_commit_graph_writer_options_init`.
 */
typedef struct {
	unsigned int version;

#ifdef GIT_EXPERIMENTAL_SHA256
	/** The object ID type that this commit graph contains. */
	git_oid_t oid_type;
#endif

	/**
	 * The strategy to use when adding new commits to a pre-existing commit-graph
	 * chain.
	 */
	git_commit_graph_split_strategy_t split_strategy;

	/**
	 * The number of commits in level N is less than X times the number of
	 * commits in level N + 1. Default is 2.
	 */
	float size_multiple;

	/**
	 * The number of commits in level N + 1 is more than C commits.
	 * Default is 64000.
	 */
	size_t max_commits;
} git_commit_graph_writer_options;

/** Current version for the `git_commit_graph_writer_options` structure */
#define GIT_COMMIT_GRAPH_WRITER_OPTIONS_VERSION 1

/** Static constructor for `git_commit_graph_writer_options` */
#define GIT_COMMIT_GRAPH_WRITER_OPTIONS_INIT { \
		GIT_COMMIT_GRAPH_WRITER_OPTIONS_VERSION \
	}

/**
 * Initialize git_commit_graph_writer_options structure
 *
 * Initializes a `git_commit_graph_writer_options` with default values. Equivalent to
 * creating an instance with `GIT_COMMIT_GRAPH_WRITER_OPTIONS_INIT`.
 *
 * @param opts The `git_commit_graph_writer_options` struct to initialize.
 * @param version The struct version; pass `GIT_COMMIT_GRAPH_WRITER_OPTIONS_VERSION`.
 * @return Zero on success; -1 on failure.
 */
GIT_EXTERN(int) git_commit_graph_writer_options_init(
	git_commit_graph_writer_options *opts,
	unsigned int version);

/**
 * Create a new writer for `commit-graph` files.
 *
 * @param out Location to store the writer pointer.
 * @param objects_info_dir The `objects/info` directory.
 * The `commit-graph` file will be written in this directory.
 * @param options The options for the commit graph writer.
 * @return 0 or an error code
 */
GIT_EXTERN(int) git_commit_graph_writer_new(
		git_commit_graph_writer **out,
		const char *objects_info_dir,
		const git_commit_graph_writer_options *options);

/**
 * Free the commit-graph writer and its resources.
 *
 * @param w The writer to free. If NULL no action is taken.
 */
GIT_EXTERN(void) git_commit_graph_writer_free(git_commit_graph_writer *w);

/**
 * Add an `.idx` file (associated to a packfile) to the writer.
 *
 * @param w The writer.
 * @param repo The repository that owns the `.idx` file.
 * @param idx_path The path of an `.idx` file.
 * @return 0 or an error code
 */
GIT_EXTERN(int) git_commit_graph_writer_add_index_file(
		git_commit_graph_writer *w,
		git_repository *repo,
		const char *idx_path);

/**
 * Add a revwalk to the writer. This will add all the commits from the revwalk
 * to the commit-graph.
 *
 * @param w The writer.
 * @param walk The git_revwalk.
 * @return 0 or an error code
 */
GIT_EXTERN(int) git_commit_graph_writer_add_revwalk(
		git_commit_graph_writer *w,
		git_revwalk *walk);

/**
 * Write a `commit-graph` file to a file.
 *
 * @param w The writer
 * @return 0 or an error code
 */
GIT_EXTERN(int) git_commit_graph_writer_commit(
		git_commit_graph_writer *w);

/**
 * Dump the contents of the `commit-graph` to an in-memory buffer.
 *
 * @param[out] buffer Buffer where to store the contents of the `commit-graph`.
 * @param w The writer.
 * @return 0 or an error code
 */
GIT_EXTERN(int) git_commit_graph_writer_dump(
		git_buf *buffer,
		git_commit_graph_writer *w);

/** @} */
GIT_END_DECL

#endif
