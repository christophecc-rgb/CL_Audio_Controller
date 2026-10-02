"""Scene-only HMAC V1 protocol. Session pinned locally, never inferred from packets."""
import hashlib
import hmac
import ipaddress
import json
import math
import secrets
import threading
import time

FIELDS={'v','show','session','seq','scene','ts','auth'}


def unicast_ipv4(value):
    address=ipaddress.IPv4Address(value)
    # Unknown subnet mask: directed broadcasts must additionally be excluded
    # by the operator's explicit peer/subnet configuration.
    if address.is_multicast or address.is_unspecified or str(address)=='255.255.255.255' or address.is_reserved or int(address) & 255 in (0,255):
        raise ValueError('Adresse IPv4 unicast requise')
    return str(address)


def canonical(packet):
    return json.dumps({k:v for k,v in packet.items() if k!='auth'},sort_keys=True,separators=(',',':'),allow_nan=False).encode()


def sign(packet,secret):
    if not isinstance(secret,str) or len(secret)<32:
        raise ValueError('Secret partagé : 32 caractères minimum, aléatoire recommandé')
    value=dict(packet); value['auth']=hmac.new(secret.encode(),canonical(value),hashlib.sha256).hexdigest()
    return value


class SceneBackupReceiver:
    def __init__(self,show,session,secret,*,allowed_source=None,max_age=0.5,clock=time.time):
        if not show or not session:
            raise ValueError('Show et session explicites requis')
        sign({},secret)
        self.show,self.session,self.secret=show,session,secret
        self.allowed_source=unicast_ipv4(allowed_source) if allowed_source else None
        self.max_age=float(max_age); self.clock=clock; self.seq=0; self.lock=threading.Lock()
        self.last_received=None

    def rotate(self,session,secret):
        """Coordinated local rotation: new session, no grace for old GO packets."""
        sign({},secret)
        with self.lock:
            if not session or session==self.session:
                raise ValueError('Nouvelle session obligatoire lors de la rotation')
            self.session,self.secret,self.seq=session,secret,0; self.last_received=None

    def accept(self,raw,source):
        with self.lock:
            if isinstance(raw,bytes):
                if len(raw)>2048: raise ValueError('Paquet trop grand')
                packet=json.loads(raw)
            else: packet=raw
            if not isinstance(packet,dict) or set(packet)!=FIELDS:
                raise ValueError('Champs de protocole invalides')
            if self.allowed_source and source!=self.allowed_source:
                raise ValueError('Source non autorisée')
            if type(packet['v']) is not int or packet['v']!=1 or packet['show']!=self.show or packet['session']!=self.session:
                raise ValueError('Show/version/session invalide')
            if type(packet['seq']) is not int or packet['seq']<=self.seq or packet['seq']>2**63-1:
                raise ValueError('Séquence ancienne ou invalide')
            if type(packet['scene']) is not int or not 1<=packet['scene']<=2**31-1:
                raise ValueError('Scène invalide')
            if type(packet['ts']) not in (float,int) or not math.isfinite(packet['ts']) or abs(self.clock()-packet['ts'])>self.max_age:
                raise ValueError('Paquet ancien ou horloge incorrecte')
            signature=packet['auth']
            expected=hmac.new(self.secret.encode(),canonical(packet),hashlib.sha256).hexdigest()
            if not isinstance(signature,str) or not hmac.compare_digest(expected,signature):
                raise ValueError('HMAC invalide')
            self.seq=packet['seq']; self.last_received=self.clock()
            return packet['scene']

    def acknowledgment(self):
        """Signed liveness proof; contains no scene command and cannot trigger GO."""
        with self.lock:
            return sign({'v':1,'type':'ack','show':self.show,'session':self.session,'seq':self.seq,'ts':self.clock()},self.secret)

    def status(self):
        return 'BACKUP LINK OK' if self.last_received and self.clock()-self.last_received<3 else 'BACKUP LINK DOWN'

    def handle(self,raw,source):
        """Return (scene, reply). Ping/pong are never scene commands."""
        if not isinstance(raw,bytes) or len(raw)>2048:
            raise ValueError('Paquet invalide')
        packet=json.loads(raw)
        if isinstance(packet,dict) and packet.get('type')=='ping':
            with self.lock:
                if set(packet)!={'v','type','show','session','nonce','ts','auth'}:
                    raise ValueError('Sonde invalide')
                if self.allowed_source and source!=self.allowed_source:
                    raise ValueError('Source non autorisée')
                if packet['v']!=1 or packet['show']!=self.show or packet['session']!=self.session:
                    raise ValueError('Session invalide')
                if type(packet['ts']) not in (int,float) or not math.isfinite(packet['ts']) or abs(self.clock()-packet['ts'])>2:
                    raise ValueError('Sonde ancienne')
                if not isinstance(packet['nonce'],str) or not 16<=len(packet['nonce'])<=128:
                    raise ValueError('Nonce invalide')
                expected=hmac.new(self.secret.encode(),canonical(packet),hashlib.sha256).hexdigest()
                if not isinstance(packet['auth'],str) or not hmac.compare_digest(expected,packet['auth']):
                    raise ValueError('HMAC invalide')
                reply=sign({'v':1,'type':'pong','show':self.show,'session':self.session,'nonce':packet['nonce'],'ts':self.clock()},self.secret)
                self.last_received=self.clock()
                return None,json.dumps(reply,separators=(',',':')).encode()
        return self.accept(packet,source),None
