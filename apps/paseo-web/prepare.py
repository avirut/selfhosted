#!/usr/bin/env python3
"""Prepare a private, version-checked web UI release; never edit the installed package."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream', required=True, type=Path)
    parser.add_argument('--hosts', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parent
    compat = json.loads((source / 'compatibility.json').read_text())
    bundle = args.upstream / compat['bundle']
    if hashlib.sha256(bundle.read_bytes()).hexdigest() != compat['sha256']:
        raise ValueError('Unreviewed Paseo bundle: review compatibility and run browser tests first')
    if args.output.exists():
        raise ValueError('Output already exists; prepare a new release directory')
    if args.hosts.stat().st_mode & 0o077:
        raise ValueError('Host configuration must be owner-only')
    config = json.loads(args.hosts.read_text())
    validation = subprocess.run(
        ['node', '--input-type=module', '-e',
         "import {validateConfiguration} from './managed-hosts.mjs';"
         "let input='';for await(const chunk of process.stdin)input+=chunk;"
         "validateConfiguration(JSON.parse(input));"],
        cwd=source, input=json.dumps(config), text=True, capture_output=True)
    if validation.returncode:
        raise ValueError('Host configuration validation failed')
    html = (args.upstream / 'index.html').read_text()
    original = f'<script src="/{compat["bundle"]}" defer></script>'
    if html.count(original) != 1:
        raise ValueError('Unexpected upstream HTML entrypoint')
    replacement = (f'<script type="module" src="/_kroacnet/bootstrap.mjs" '
                   f'data-paseo-bundle="/{compat["bundle"]}"></script>')
    # Every generated file stays outside Git. In particular, never stage hosts.json.
    os.umask(0o077)
    shutil.copytree(args.upstream, args.output)
    (args.output / 'index.html').write_text(html.replace(original, replacement))
    for suffix in ('.gz', '.br'):
        (args.output / ('index.html' + suffix)).unlink(missing_ok=True)
    private = args.output / '_kroacnet'
    private.mkdir(mode=0o700)
    for name in ('bootstrap.mjs', 'managed-hosts.mjs'):
        shutil.copyfile(source / name, private / name)
    (private / 'hosts.json').write_text(json.dumps(config) + '\n')
    for path in args.output.rglob('*'):
        path.chmod(0o700 if path.is_dir() else 0o600)
    args.output.chmod(0o700)
    print(json.dumps({'prepared': str(args.output), 'hosts': len(config['hosts']),
                      'paseoVersion': compat['paseoVersion']}))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        # Error messages never include configuration contents.
        print(str(error), file=sys.stderr)
        sys.exit(1)
