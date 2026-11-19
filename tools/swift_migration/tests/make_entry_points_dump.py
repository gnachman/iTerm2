#!/usr/bin/env python3
"""Regenerate the captured Swift compiler output that test_entry_points.py
feeds to the code database's Swift reader: fixtures/entry_points_swift/
module.json.gz (the JSON AST dump of the Swift files of the entry-point
fixture, one document per file, with the fixture directory's absolute path
replaced by @FIXTURE@) and fixtures/entry_points_swift/COMPILER_VERSION (the
first line of `swiftc -version` of the compiler that wrote it).

Usage: python3 -B make_entry_points_dump.py --module-cache DIR
It runs the compiler xcrun finds through the same steps codedb.py update
takes (the code database's swift_fixture/make_dump.py does the same for its
own fixture): a driver command, translate_swift_command, -driver-print-jobs,
frontend_dump_job. Nothing is written outside fixtures/entry_points_swift/
except the compiler's module cache, DIR, which must not be under tmp/codedb.
Set ENTRY_POINTS_CODEDB_DIR to use another copy of the code database's
tools (as entry_points.py does).
"""

import argparse
import gzip
import os
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
CODEDB_DIR = os.environ.get('ENTRY_POINTS_CODEDB_DIR') or os.path.join(os.path.dirname(HERE), 'codedb')
sys.path.insert(0, CODEDB_DIR)
sys.path.insert(0, os.path.join(CODEDB_DIR, 'tests', 'swift_fixture'))
import swiftdb  # noqa: E402
import make_dump  # noqa: E402

FIXTURE = os.path.join(HERE, 'fixtures', 'entry_points')
OUT_DIR = os.path.join(HERE, 'fixtures', 'entry_points_swift')
SWIFT_FILES = ('sources/Panel.swift', 'sources/SDKUsers.swift')
BRIDGING_HEADER = 'sources/Fixture-Bridging-Header.h'
MODULE = 'Fix'
PLACEHOLDER = '@FIXTURE@'


def driver_command(swiftc, file_list, sdk, root):
    """The code database fixture's driver command, with this fixture's
    bridging header."""
    args = make_dump.driver_command(swiftc, file_list, sdk)
    args[args.index('-import-objc-header') + 1] = os.path.join(root, BRIDGING_HEADER)
    return args


def main():
    p = argparse.ArgumentParser(description='Regenerate the entry-point fixture dump.')
    p.add_argument('--module-cache', required=True, help="the compiler's module cache")
    opts = p.parse_args()
    swiftc = subprocess.run(['xcrun', '--find', 'swiftc'], capture_output=True, text=True, check=True).stdout.strip()
    sdk = subprocess.run(['xcrun', '--show-sdk-path'], capture_output=True, text=True, check=True).stdout.strip()
    version = swiftdb.compiler_version(swiftc)
    files = [os.path.join(FIXTURE, f) for f in SWIFT_FILES]
    with tempfile.TemporaryDirectory() as d:
        file_list = os.path.join(d, MODULE + '.SwiftFileList')
        with open(file_list, 'w') as f:
            f.write(''.join(x + '\n' for x in files))
        args, _ = swiftdb.translate_swift_command(driver_command(swiftc, file_list, sdk, FIXTURE),
                                                  opts.module_cache, sdk, file_list=file_list)
        jobs = subprocess.run(args + ['-dump-ast', '-dump-ast-format', 'json', '-driver-print-jobs'],
                              capture_output=True, text=True, check=True).stdout
        job = swiftdb.frontend_dump_job(swiftdb.parse_print_jobs(jobs), files, file_list)
        r = subprocess.run(job, capture_output=True, check=True)
    text = r.stdout.decode('utf-8').replace(FIXTURE, PLACEHOLDER)
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, 'module.json.gz'), 'wb') as raw:
        with gzip.GzipFile(fileobj=raw, mode='wb', mtime=0) as f:
            f.write(text.encode('utf-8'))
    with open(os.path.join(OUT_DIR, 'COMPILER_VERSION'), 'w') as f:
        f.write(version + '\n')
    print('wrote module.json.gz (%d bytes of JSON) from %s' % (len(text), version))


if __name__ == '__main__':
    main()
