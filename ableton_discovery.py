"""Bounded macOS DNS-SD discovery, separate from legacy RTP discovery.

No OSC packets, configuration writes or target adoption. Each scan replaces the
previous snapshot; cached records are never used as an offline fallback.
"""
import concurrent.futures
import ipaddress
import re
import socket
import subprocess
import threading
import time

SERVICE_TYPE = '_cl-ableton._udp'
CACHE_SECONDS = 30
MAX_READERS = 32


def usable_ipv4(value):
    try:
        ip = ipaddress.IPv4Address(value)
        return not (ip.is_link_local or ip.is_loopback or ip.is_multicast
                    or ip.is_unspecified or ip.is_reserved or str(ip).startswith('0.'))
    except (ValueError, TypeError):
        return False


def command_output(args, timeout):
    """Read a bounded command and always reap it, including timeout/failure."""
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding='utf-8', errors='replace')
    try:
        output, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.terminate()
        try:
            output, _ = proc.communicate(timeout=1)
        except subprocess.TimeoutExpired:
            proc.kill()
            output, _ = proc.communicate()
    return output or ''


def network_interfaces(run=command_output):
    """Only active Ethernet/Wi-Fi interfaces with usable IPv4; fail closed.

macOS service labels reveal explicitly named Dante interfaces. Auto-IP, virtual,
VPN, peer-to-peer and unknown interfaces are not discovery candidates.
    """
    services = run(['/usr/sbin/networksetup', '-listnetworkserviceorder'], 2)
    addresses = run(['/sbin/ifconfig', '-a'], 2)
    labels = {}
    label = ''
    for line in services.splitlines():
        if re.match(r'^\(\d+\)', line):
            label = line
        match = re.search(r'Hardware Port: (.*), Device: ([^)]+)', line)
        if match:
            labels[match[2]] = label + ' ' + match[1]
    allowed, ignored = {}, []
    for block in re.split(r'(?m)(?=^[\w]+: flags=)', addresses):
        match = re.match(r'(\w+): flags=', block)
        if not match:
            continue
        name = match[1]
        ips = re.findall(r'\binet (\d+\.\d+\.\d+\.\d+)', block)
        label = labels.get(name, '')
        safe = (name.startswith('en') and label and 'dante' not in label.lower()
                and 'auto-ip' not in label.lower() and 'status: active' in block
                and any(usable_ipv4(ip) for ip in ips))
        if safe:
            try:
                allowed[socket.if_nametoindex(name)] = name
            except OSError:
                ignored.append(name + ' · interface disparue')
        elif ips:
            ignored.append(name + ' · ' + (label or 'interface non utilisable'))
    return allowed, ignored


def parse_browse(output, interfaces):
    """Apply Add/Rmv events within this snapshot, keeping interface identity."""
    found = {}
    pattern = r'^\S+\s+(Add|Rmv)\s+\S+\s+(\d+)\s+local\.\s+_cl-ableton\._udp\.?\s+(.+?)\s*$'
    for line in output.splitlines():
        match = re.match(pattern, line)
        if not match:
            continue
        action, index, name = match.groups()
        index = int(index)
        key = (index, name)
        if action == 'Rmv':
            found.pop(key, None)
        elif index in interfaces:
            found[key] = (index, name)
    return list(found.values())[:MAX_READERS]


def parse_resolution(output):
    match = re.search(r'can be reached at\s+([A-Za-z0-9_.-]+):(\d+)', output)
    if not match:
        return None
    host, port = match[1].rstrip('.'), int(match[2])
    # A dedicated service still requires the role/protocol contract.
    if (not host.lower().endswith('.local') or not 1 <= port <= 65535
            or not re.search(r'\brole=ableton\b', output)
            or not re.search(r'\bprotocol=abletonosc\b', output)):
        return None
    return host, port


def parse_addresses(output, index, host):
    addresses = set()
    # dns-sd -G: timestamp Add/Rmv flags interface hostname address TTL
    pattern = r'^\S+\s+(Add|Rmv)\s+\S+\s+(\d+)\s+(\S+)\s+(\d+\.\d+\.\d+\.\d+)\s+\d+'
    for line in output.splitlines():
        match = re.match(pattern, line)
        if not match:
            continue
        action, iface, hostname, ip = match.groups()
        if int(iface) != index or hostname.rstrip('.').lower() != host.lower():
            continue
        if action == 'Rmv':
            addresses.discard(ip)
        elif usable_ipv4(ip):
            addresses.add(ip)
    return sorted(addresses)


def merge_readers(records):
    readers = {}
    for record in records:
        if not record:
            continue
        key = (record['host'].lower(), record['port'])
        if key not in readers:
            readers[key] = {**record, 'addresses': [], 'interfaces': []}
        row = readers[key]
        row['addresses'] = sorted(set(row['addresses'] + record['addresses']))
        row['interfaces'] = sorted(set(row['interfaces'] + record['interfaces']))
        row['state'] = 'resolved' if row['addresses'] else 'discovered'
    return sorted(readers.values(), key=lambda row: (row['host'].lower(), row['port']))


def scan_readers(run=command_output, interface_provider=network_interfaces):
    interfaces, ignored = interface_provider()
    if not interfaces:
        return {'readers': [], 'ignored_interfaces': ignored,
                'error': 'Aucune interface LAN IPv4 utilisable'}
    output = run(['/usr/bin/dns-sd', '-B', SERVICE_TYPE, 'local.'], 3)
    if 'DNSServiceBrowse failed' in output:
        raise OSError('Bonjour indisponible')

    def resolve(service):
        index, name = service
        output = run(['/usr/bin/dns-sd', '-i', str(index), '-L', name,
                      SERVICE_TYPE, 'local.'], 2)
        target = parse_resolution(output)
        if not target:
            return None
        host, port = target
        ips = parse_addresses(run(['/usr/bin/dns-sd', '-i', str(index),
                                   '-G', 'v4', host], 2), index, host)
        return {'name': name, 'host': host, 'port': port, 'addresses': ips,
                'interfaces': [interfaces[index]], 'state': 'resolved' if ips else 'discovered'}

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        readers = merge_readers(pool.map(resolve, parse_browse(output, interfaces)))
    return {'readers': readers, 'ignored_interfaces': ignored, 'error': None}


class DiscoveryCache:
    def __init__(self, scanner=scan_readers, clock=time.monotonic):
        self.scanner, self.clock = scanner, clock
        self.lock = threading.Lock()
        self.updated = None
        self.result = {'readers': [], 'ignored_interfaces': [], 'error': None}

    def snapshot(self):
        with self.lock:
            if self.updated is None or self.clock() - self.updated >= CACHE_SECONDS:
                try:
                    self.result = self.scanner()
                except Exception as exc:
                    self.result = {'readers': [], 'ignored_interfaces': [], 'error': str(exc)}
                self.updated = self.clock()
                self.refreshed_at = time.time()
            return {**self.result, 'service': SERVICE_TYPE,
                    'refreshed_at': self.refreshed_at, 'cache_seconds': CACHE_SECONDS}
