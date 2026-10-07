"""Remember the last backup destination without arming its transport."""
import ipaddress
import json
import os
import tempfile
from pathlib import Path


def load_backup_destination(path):
    try:
        data = json.loads(Path(path).read_text())
        host = str(ipaddress.IPv4Address(data['host']))
        name = str(data.get('bonjour_name', ''))
        return {'host': host, 'bonjour_name': name if name.lower().endswith('.local') else ''}
    except (OSError, ValueError, KeyError, TypeError):
        return {'host': '', 'bonjour_name': ''}


def save_backup_destination(path, host, name=''):
    host = str(ipaddress.IPv4Address(host))
    name = str(name).strip().rstrip('.')
    data = {'host': host, 'bonjour_name': name if name.lower().endswith('.local') else ''}
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.backup-')
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(data, stream)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return data
