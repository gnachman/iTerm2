#!/usr/bin/env python3
"""Regenerate the captured compiler output that test_codedb_swift.py feeds
to the reader: module.json.gz (the JSON AST dump of the fixture module in
module/, one document per file, with the module directory's absolute path
replaced by @FIXTURE@) and COMPILER_VERSION (the first line of `swiftc
-version` of the compiler that wrote it).

Usage: python3 -B make_dump.py [--module-cache DIR]
It runs the compiler xcrun finds, through the same steps codedb.py update
takes: a driver command, translate_swift_command, -driver-print-jobs,
frontend_dump_job. Nothing is written outside this directory except the
compiler's module cache: tmp/codedb/test-swift-modcache, or DIR.
"""

import argparse
import gzip
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))
import swiftdb  # noqa: E402

MODULE_DIR = os.path.join(HERE, 'module')
FILES = ('Calls.swift', 'Decls.swift', 'Properties.swift', 'Selectors.swift')
PLACEHOLDER = '@FIXTURE@'


def driver_command(swiftc, file_list, sdk, extra=()):
    """A driver command shaped like the ones Xcode runs, with the flags the
    translation drops."""
    return [swiftc, '-module-name', 'Fix', '-Onone', '@' + file_list, '-import-objc-header',
            os.path.join(MODULE_DIR, 'Fixture.h'), '-sdk', sdk, '-target', 'arm64-apple-macos13.0', '-g',
            '-c', '-j8', '-enable-batch-mode', '-incremental', '-emit-module', '-emit-module-path', '/nonexistent/Fix'
            '.swiftmodule', '-module-cache-path', '/nonexistent/ModuleCache.noindex', '-output-file-map',
            '/nonexistent/map.json', '-serialize-diagnostics', '-emit-dependencies', '-warnings-as-errors',
            '-Xcc', '-ivfsstatcache', '-Xcc', '/nonexistent/sdk.sdkstatcache', '-Xfrontend',
            '-serialize-debugging-options', '-Xcc', '-fmodules-prune-interval=86400'] + list(extra)


def main():
    p = argparse.ArgumentParser(description='Regenerate the fixture dump.')
    p.add_argument('--module-cache', help='the compiler\'s module cache (default: tmp/codedb/test-swift-modcache)')
    opts = p.parse_args()
    swiftc = subprocess.run(['xcrun', '--find', 'swiftc'], capture_output=True, text=True, check=True).stdout.strip()
    sdk = subprocess.run(['xcrun', '--show-sdk-path'], capture_output=True, text=True, check=True).stdout.strip()
    version = swiftdb.compiler_version(swiftc)
    root = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..', '..'))
    cache = opts.module_cache or os.path.join(root, 'tmp', 'codedb', 'test-swift-modcache')
    files = [os.path.join(MODULE_DIR, f) for f in FILES]
    with tempfile.TemporaryDirectory() as d:
        file_list = os.path.join(d, 'Fix.SwiftFileList')
        with open(file_list, 'w') as f:
            f.write(''.join(x + '\n' for x in files))
        args, _ = swiftdb.translate_swift_command(driver_command(swiftc, file_list, sdk), cache, sdk,
                                                  file_list=file_list)
        jobs = subprocess.run(args + ['-dump-ast', '-dump-ast-format', 'json', '-driver-print-jobs'],
                              capture_output=True, text=True, check=True).stdout
        job = swiftdb.frontend_dump_job(swiftdb.parse_print_jobs(jobs), files, file_list)
        r = subprocess.run(job, capture_output=True, check=True)
    text = r.stdout.decode('utf-8').replace(MODULE_DIR, PLACEHOLDER)
    with open(os.path.join(HERE, 'module.json.gz'), 'wb') as raw:
        with gzip.GzipFile(fileobj=raw, mode='wb', mtime=0) as f:
            f.write(text.encode('utf-8'))
    with open(os.path.join(HERE, 'COMPILER_VERSION'), 'w') as f:
        f.write(version + '\n')
    print('wrote module.json.gz (%d bytes of JSON) from %s' % (len(text), version))


if __name__ == '__main__':
    main()
