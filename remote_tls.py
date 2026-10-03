"""Local HTTPS onboarding. No musical commands, system trust changes or private-key downloads."""
import hashlib
import http.client
import ipaddress
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import socket
import ssl
import subprocess
import threading
import time
from urllib.parse import urlsplit

from remote_security import SecurityError, private_directory


def server_address(value, port=None):
    try:
        parsed = urlsplit(str(value))
        host = parsed.hostname
        actual_port = parsed.port or 443
        if parsed.scheme != 'https' or not host or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('', '/'):
            raise ValueError()
        if port is not None and actual_port != int(port):
            raise ValueError()
        if actual_port in (5050, 5055) or not 1 <= actual_port <= 65535:
            raise ValueError()
        try:
            ipaddress.ip_address(host)
        except ValueError:
            if not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?', host) or any(not part or len(part) > 63 or part.startswith('-') or part.endswith('-') for part in host.split('.')):
                raise ValueError()
        return host, actual_port
    except (ValueError, TypeError):
        raise SecurityError('Adresse HTTPS invalide : utiliser https://nom-du-mac.local:8443, sans chemin ni identifiants')


def _command(arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=15).stdout.strip()


def network_identity():
    """OS-owned Bonjour identity and active Ethernet/Wi-Fi IPv4 addresses; never Host headers."""
    hostname = ''
    interfaces = []
    primary = ''
    try:
        hostname = _command(['/usr/sbin/scutil', '--get', 'LocalHostName']) + '.local'
        server_address('https://' + hostname + ':8443')
    except (OSError, subprocess.SubprocessError, SecurityError):
        hostname = ''
    try:
        route = _command(['/sbin/route', '-n', 'get', 'default'])
        match = re.search(r'interface:\s+(\w+)', route)
        primary = match.group(1) if match else ''
    except (OSError, subprocess.SubprocessError):
        pass
    try:
        for name in _command(['/sbin/ifconfig', '-l']).split():
            if not re.fullmatch(r'en\d+', name):
                continue
            try:
                address = str(ipaddress.IPv4Address(_command(['/usr/sbin/ipconfig', 'getifaddr', name])))
                interfaces.append({'name': name, 'address': address, 'primary': name == primary})
            except (ValueError, OSError, subprocess.SubprocessError):
                continue
    except (OSError, subprocess.SubprocessError):
        pass
    interfaces.sort(key=lambda entry: not entry['primary'])
    return {'bonjour_name': hostname, 'interfaces': interfaces,
            'suggested_url': 'https://' + (hostname or (interfaces[0]['address'] if interfaces else '')) + ':8443' if hostname or interfaces else ''}


def read_settings(directory):
    path = Path(directory) / 'remote-tls.json'
    data = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(data, dict):
        raise SecurityError('Configuration HTTPS illisible')
    return data


def save_settings(directory, settings):
    private_directory(directory)
    path = Path(directory) / ('tls-' + secrets.token_hex(8) + '.tmp')
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as file:
        json.dump(settings, file)
    os.replace(path, Path(directory) / 'remote-tls.json')


def _private_write(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as file:
        file.write(data)


def prepare_certificate(directory, url, identity):
    host, port = server_address(url)
    root = Path(directory) / 'https'
    private_directory(root)
    ca_cert, ca_key = root / 'ca.pem', root / 'ca-key.pem'
    if ca_cert.exists() != ca_key.exists():
        raise SecurityError('Autorité locale incomplète : restaurer les fichiers HTTPS ; aucune autorité remplacée automatiquement')
    if not ca_cert.exists():
        ca_name = 'CL Show Control ' + host + ' ' + secrets.token_hex(6)
        ca_config = root / ('ca-' + secrets.token_hex(6) + '.conf')
        _private_write(ca_config, ('[req]\ndistinguished_name=dn\nx509_extensions=ca\n[dn]\n[ca]\nbasicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n').encode())
        _command(['/usr/bin/openssl', 'req', '-config', str(ca_config), '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-days', '3650',
                  '-subj', '/CN=' + ca_name, '-keyout', str(ca_key), '-out', str(ca_cert)])
        ca_key.chmod(0o600)
    if ca_key.stat().st_mode & 0o077:
        raise SecurityError('Clé de la CA : permissions privées requises')
    # Reuse the CA on reconfiguration so enrolled phones keep their trust anchor.
    generation = root / secrets.token_hex(8)
    private_directory(generation)
    cert, key = generation / 'server.pem', generation / 'server-key.pem'
    names = [host]
    if host == identity.get('bonjour_name'):
        names += [item['address'] for item in identity.get('interfaces', [])]
    sans = []
    for name in dict.fromkeys(names):
        try: sans.append('IP:' + str(ipaddress.ip_address(name)))
        except ValueError: sans.append('DNS:' + name)
    config = generation / 'certificate.conf'
    _private_write(config, ('[req]\nprompt=no\ndistinguished_name=dn\n[dn]\nCN=' + host + '\n[server]\n'
        'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n'
        'extendedKeyUsage=serverAuth\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\nsubjectAltName=' + ','.join(sans) + '\n').encode())
    csr = generation / 'request.pem'
    _command(['/usr/bin/openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-config', str(config), '-keyout', str(key), '-out', str(csr)])
    key.chmod(0o600)
    _command(['/usr/bin/openssl', 'x509', '-req', '-in', str(csr), '-CA', str(ca_cert), '-CAkey', str(ca_key),
              '-set_serial', '0x' + secrets.token_hex(16), '-days', '365', '-sha256', '-extfile', str(config), '-extensions', 'server', '-out', str(cert)])
    return {'certificate': str(cert), 'private_key': str(key), 'ca_certificate': str(ca_cert), 'port': port, 'server_url': url.rstrip('/'), 'managed': True}


class RemoteTLS:
    def __init__(self, app, directory):
        self.app, self.directory = app, Path(directory)
        self.server = None
        self.context = None
        self.settings = {}
        self.error = ''
        self.lock = threading.RLock()
        self.instance = secrets.token_hex(16)
        self.phone_seen = 0
        self.enrollment_token = ''
        self.enrollment_expires = 0
        self.identity = network_identity()

    def start(self, settings):
        """Only invoked by persisted explicit configuration or an unlocked local admin."""
        with self.lock:
            cert, key = settings.get('certificate'), settings.get('private_key')
            if not cert or not key or not Path(cert).is_file() or not Path(key).is_file():
                raise SecurityError('Certificat ou clé HTTPS absent : utiliser Première configuration')
            if Path(key).stat().st_mode & 0o077:
                raise SecurityError('Clé privée TLS : permissions 0600 requises')
            port = int(settings.get('port', 8443))
            if not 1 <= port <= 65535 or port in (5050, 5055):
                raise SecurityError('Port HTTPS distinct de 5050/5055 requis')
            if settings.get('server_url'):
                server_address(settings['server_url'], port)
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            context.load_cert_chain(cert, key)
            if self.server and self.server.server_port == port:
                # The listening SSLSocket keeps this context: replace its certificate in place.
                self.context.load_cert_chain(cert, key)
            else:
                from werkzeug.serving import make_server
                # Bind the new port first; failure preserves an existing working listener.
                try:
                    server = make_server('0.0.0.0', port, self.app, threaded=True, ssl_context=context)
                except SystemExit:
                    raise SecurityError('Port HTTPS indisponible : une autre application utilise peut-être ce port')
                old = self.server
                self.server, self.context = server, context
                threading.Thread(target=server.serve_forever, name='CL Remote TLS', daemon=True).start()
                if old:
                    old.shutdown(); old.server_close()
            self.settings = dict(settings)
            self.error = ''
            self.phone_seen = 0
        return self.server

    def stop(self):
        with self.lock:
            if self.server:
                self.server.shutdown(); self.server.server_close()
                self.server = None
            self.phone_seen = 0

    def probe(self, url=None):
        """Verify chain, hostname and this backend through a real TLS handshake, without DNS redirects."""
        base = url or self.settings.get('server_url', '')
        host, port = server_address(base)
        if base.rstrip('/') != self.settings.get('server_url', '').rstrip('/') or not self.server or self.server.server_port != port:
            raise SecurityError('HTTPS non démarré pour cette adresse')
        context = ssl.create_default_context(cafile=self.settings.get('ca_certificate'))
        with socket.create_connection(('127.0.0.1', port), timeout=2) as raw:
            with context.wrap_socket(raw, server_hostname=host) as stream:
                stream.sendall(('GET /remote/ready HTTP/1.1\r\nHost: ' + host + '\r\nConnection: close\r\n\r\n').encode('ascii'))
                response = http.client.HTTPResponse(stream)
                response.begin()
                data = json.loads(response.read(4096))
                if response.status != 200 or data.get('instance') != self.instance:
                    raise SecurityError('Le port HTTPS ne répond pas avec ce serveur CL')
        return True

    def snapshot(self):
        result = {'state': 'INACTIVE', 'ready': False, 'phone_verified': time.time() - self.phone_seen < 120,
                  'server_url': self.settings.get('server_url', ''), 'port': self.settings.get('port', 8443),
                  'network': self.identity, 'error': self.error, 'certificate_valid': False, 'hostname_valid': False}
        try:
            settings = self.settings or read_settings(self.directory)
            result['server_url'] = settings.get('server_url', '')
            result['certificate_present'] = bool(settings.get('certificate') and Path(settings['certificate']).is_file())
            result['private_key_present'] = bool(settings.get('private_key') and Path(settings['private_key']).is_file())
            if not self.server:
                result['error'] = self.error or 'HTTPS non configuré ou arrêté : utiliser Première configuration'
                return result
            self.probe()
            result.update(state='HTTPS PRÊT', ready=True, certificate_valid=True, hostname_valid=True)
        except (OSError, ValueError, SecurityError) as error:
            result.update(error=str(error), certificate_valid=False, hostname_valid=False)
        return result

    def enroll(self):
        if not self.settings.get('managed'):
            raise SecurityError('Certificat fourni manuellement : utiliser son autorité de certification habituelle')
        self.enrollment_token = secrets.token_urlsafe(24)
        self.enrollment_expires = time.time() + 900
        host, _ = server_address(self.settings['server_url'])
        authority = '[' + host + ']' if ':' in host else host
        der = ssl.PEM_cert_to_DER_cert(Path(self.settings['ca_certificate']).read_text())
        return {'url': 'http://' + authority + ':5050/remote/trust/' + self.enrollment_token,
                'fingerprint': hashlib.sha256(der).hexdigest().upper(), 'expires': self.enrollment_expires,
                'check_url': self.settings['server_url'] + '/remote/check'}

    def profile(self, token):
        if not self.enrollment_token or not secrets.compare_digest(token, self.enrollment_token) or time.time() >= self.enrollment_expires:
            raise SecurityError('Lien de certificat expiré : le recréer depuis le Mac')
        der = ssl.PEM_cert_to_DER_cert(Path(self.settings['ca_certificate']).read_text())
        authority_id = hashlib.sha256(der).hexdigest()
        host, _ = server_address(self.settings['server_url'])
        import uuid
        payload = {'PayloadType': 'com.apple.security.root', 'PayloadVersion': 1, 'PayloadIdentifier': 'com.claudio.remote.ca.' + authority_id[:16],
                   'PayloadUUID': str(uuid.uuid4()), 'PayloadDisplayName': 'CA CL Show Control ' + host + ' ' + authority_id[:12], 'PayloadContent': der}
        return plistlib.dumps({'PayloadType': 'Configuration', 'PayloadVersion': 1, 'PayloadIdentifier': 'com.claudio.remote.trust.' + authority_id[:16],
                'PayloadUUID': str(uuid.uuid4()), 'PayloadDisplayName': 'Confiance CL Show Control', 'PayloadContent': [payload]})
