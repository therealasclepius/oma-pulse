#!/usr/bin/env python3
"""Create private first-run storage without replacing an existing workspace."""
import json
import os
from pathlib import Path


def initialize(folder):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = folder / 'workspace.json'
    state = {'version': 1, 'tasks': [], 'notes': {}, 'activity': {},
             'focus': {'title': 'Open focus', 'duration': 1500, 'elapsed': 0, 'running': False}}
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return
    with os.fdopen(fd, 'w') as stream:
        json.dump(state, stream)
        stream.write('\n')


if __name__ == '__main__':
    initialize(Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share') / 'omaowl')
