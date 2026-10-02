"""Device identity, permissions and arming. No production commands in this module."""
import base64
import hashlib
import hmac
import json
import math
import os
from pathlib import Path
import secrets
import threading
import time

PERMISSIONS = {'reader': {'read'}, 'operator': {'read','show'}, 'admin': {'read','show','admin'}}


def private_directory(path):
    # mkdir(parents=True) gives intermediate dirs 0755, which would invalidate
    # the existing target-config permission contract on a fresh installation.
    missing=[]; cursor=Path(path)
    while not cursor.exists():
        missing.append(cursor); cursor=cursor.parent
    for directory in reversed(missing):
        directory.mkdir(mode=0o700,exist_ok=True)


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def canonical_request(method, path, body, timestamp, nonce):
    return '\n'.join((method.upper(), path, str(timestamp), nonce, hashlib.sha256(body).hexdigest())).encode()


class SecurityError(ValueError):
    pass


class RemoteSecurity:
    def __init__(self, directory, clock=time.time, namespace="backend"):
        self.directory = Path(directory)
        self.state_name = "security.json" if namespace == "backend" else "launcher-security.json"
        self.password_revision = None
        self.clock = clock
        self.lock = threading.RLock()
        self.server = None
        self.session = secrets.token_hex(16)
        self.armed = False
        self.mode = 'show'
        self.admin_sessions = {}
        self.codes = {}
        self.pending = {}
        self.devices = {}
        self.nonces = {}
        self.failures = []
        self.password_record = None
        self.loaded = False
        self.runtime_seen = {}

    def load(self):
        with self.lock:
            if self.loaded:
                return
            path = self.directory/self.state_name
            if path.exists():
                data = json.loads(path.read_text())
                self.password_record = data.get('password')
                if self.password_record:
                    self.password_revision = digest(json.dumps(self.password_record,sort_keys=True))
                self.server = data['server']
                self.devices = data.get('devices',{})
                for device in self.devices.values():
                    device.setdefault('authorization_type','temporary')
                now=self.clock()
                for entry in data.get('nonces',[]):
                    if entry['expires']>now:
                        self.nonces[(entry['device'],entry['nonce'])]=entry['expires']
            else:
                self.server = secrets.token_hex(16)
            self.loaded = True
            self.refresh_password()

    def refresh_password(self):
        path = self.directory/'admin-password.json'
        if path.exists():
            record = json.loads(path.read_text())
            revision = digest(json.dumps(record,sort_keys=True))
            password_changed = self.password_revision is not None and revision != self.password_revision
            if password_changed:
                self.admin_sessions.clear(); self.codes.clear(); self.pending.clear()
                self.armed = False; self.mode = 'show'; self.session = secrets.token_hex(16)
            self.password_record = record
            self.password_revision = revision
            changed = False
            for device in self.devices.values():
                if not device['revoked'] and (password_changed or (device.get('authorization_type') == 'permanent' and device.get('password_revision') != revision)):
                    device['revoked'] = True; device['key'] = ''; changed = True
            if changed:
                self.save()

    def save(self):
        private_directory(self.directory)
        self.directory.chmod(0o700)
        path = self.directory/self.state_name
        temporary = self.directory/('security.'+secrets.token_hex(8)+'.tmp')
        fd = os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'w') as file:
            json.dump({'schema':2,'server':self.server,'password':self.password_record,'devices':self.devices,'nonces':[{'device':key[0],'nonce':key[1],'expires':expiry} for key,expiry in self.nonces.items() if expiry>self.clock() and self.devices.get(key[0],{}).get('authorization_type')=='permanent']},file)
        os.replace(temporary,path)

    def audit(self, command, result, reason='', device=None, scene=None):
        private_directory(self.directory)
        record = {'ts':self.clock(),'device':device.get('id','local') if device else 'unknown',
                  'operator':device.get('operator','') if device else '',
                  'role':device.get('role','local') if device else 'unknown',
                  'command':str(command)[:120],'scene':scene,'result':result,'reason':reason}
        # Use only selected metadata; request headers/body never go into this log.
        path = self.directory/'commands.jsonl'
        fd = os.open(path,os.O_WRONLY|os.O_APPEND|os.O_CREAT,0o600)
        with os.fdopen(fd,'a') as file:
            file.write(json.dumps(record,ensure_ascii=False)+'\n')

    def set_password(self,password, *, initial=False):
        with self.lock:
            self.load(); self.refresh_password()
            if initial and self.password_record:
                raise SecurityError('Mot de passe déjà configuré')
            if not isinstance(password,str) or len(password)<12 or len(password)>1024:
                raise SecurityError('Mot de passe : 12 caractères minimum')
            salt=secrets.token_bytes(32)
            key=hashlib.scrypt(password.encode(),salt=salt,n=32768,r=8,p=1,maxmem=64*1024*1024,dklen=32)
            self.password_record={'algorithm':'scrypt','n':32768,'r':8,'p':1,'salt':salt.hex(),'hash':key.hex()}
            private_directory(self.directory)
            temporary = self.directory/('password.'+secrets.token_hex(8)+'.tmp')
            fd = os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
            with os.fdopen(fd,'w') as file:
                json.dump(self.password_record,file)
            os.replace(temporary,self.directory/'admin-password.json')
            self.password_revision = digest(json.dumps(self.password_record,sort_keys=True))
            self.admin_sessions.clear(); self.codes.clear(); self.pending.clear(); self.armed=False
            self.session = secrets.token_hex(16)
            for device in self.devices.values():
                device['revoked']=True; device['key']=''

            self.save(); self.audit('password-set','accepted')

    def unlock(self,password):
        with self.lock:
            self.load(); self.refresh_password(); now=self.clock()
            self.failures=[stamp for stamp in self.failures if now-stamp<300]
            if len(self.failures)>=5:
                raise SecurityError('Trop de tentatives ; attendre cinq minutes')
            record=self.password_record
            valid=False
            if record and isinstance(password,str) and len(password)<=1024:
                key=hashlib.scrypt(password.encode(),salt=bytes.fromhex(record['salt']),n=record['n'],r=record['r'],p=record['p'],maxmem=64*1024*1024,dklen=32)
                valid=hmac.compare_digest(key.hex(),record['hash'])
            if not valid:
                self.failures.append(now); self.audit('admin-unlock','refused','invalid-password')
                raise SecurityError('Mot de passe invalide')
            token=secrets.token_urlsafe(32); self.admin_sessions[digest(token)]=now+300
            self.audit('admin-unlock','accepted'); return token

    def admin(self,token):
        with self.lock:
            self.load(); self.refresh_password()
            if not token or self.admin_sessions.get(digest(token),0)<=self.clock():
                raise SecurityError('Déverrouillage administrateur local requis')

    def lock_admin(self):
        with self.lock:
            self.admin_sessions.clear(); self.mode='show'; self.codes.clear()
            self.audit('admin-lock','accepted')

    def set_mode(self,mode):
        if mode not in ('show','development'):
            raise SecurityError('Mode invalide')
        with self.lock:
            self.mode=mode; self.audit('mode-'+mode,'accepted')

    def set_armed(self,armed):
        with self.lock:
            if armed and not self.password_record:
                raise SecurityError('Configurer le mot de passe administrateur')
            self.armed=bool(armed); self.audit('arm' if armed else 'disarm','accepted')

    def new_code(self,role,ttl=120):
        with self.lock:
            self.load()
            if role not in PERMISSIONS:
                raise SecurityError('Rôle inconnu')
            now=self.clock(); self.codes={k:v for k,v in self.codes.items() if v['expires']>now}
            if len(self.codes)>=32:
                raise SecurityError('Trop de QR actifs')
            code=secrets.token_urlsafe(32)
            self.codes[digest(code)]={'role':role,'expires':now+min(max(ttl,1),120),'session':self.session,'server':self.server}
            self.audit('pair-qr-'+role,'accepted'); return code

    def request_pair(self,code,name,operator=''):
        with self.lock:
            self.load(); item=self.codes.pop(digest(code),None)
            if not item or item['expires']<=self.clock() or item['session']!=self.session or item['server']!=self.server:
                raise SecurityError('QR expiré ou déjà utilisé')
            now=self.clock(); self.pending={k:v for k,v in self.pending.items() if v['expires']>now}
            request_id=secrets.token_hex(16); claim=secrets.token_urlsafe(32)
            self.pending[request_id]={'id':request_id,'name':str(name)[:80],'operator':str(operator)[:80],'role':item['role'],
                                      'claim_hash':digest(claim),'expires':now+300,'approved':False,'session':self.session}
            self.audit('pair-request','pending',device={'id':request_id,'role':item['role'],'operator':str(operator)[:80]})
            return {'request_id':request_id,'claim':claim,'expires':now+300}

    def approve(self,request_id,lifetime=43200,authorization_type='temporary'):
        with self.lock:
            self.load(); self.refresh_password()
            item=self.pending.get(request_id)
            if not item or item['expires']<=self.clock() or item['approved']:
                raise SecurityError('Demande expirée ou déjà validée')
            if authorization_type not in ('temporary','permanent'):
                raise SecurityError('Type d’autorisation invalide')
            expires = None
            if authorization_type == 'temporary':
                try:
                    duration = float(lifetime)
                except (TypeError,ValueError):
                    raise SecurityError('Prise de poste : 60 secondes à 24 heures')
                if not math.isfinite(duration) or not 60<=duration<=86400:
                    raise SecurityError('Prise de poste : 60 secondes à 24 heures')
                expires = self.clock() + duration
            device_id=secrets.token_hex(16); token=secrets.token_urlsafe(32)
            device={field:item[field] for field in ('name','operator','role')}
            device.update({'id':device_id,'key':digest(token),'expires':expires,'authorization_type':authorization_type,'password_revision':self.password_revision,'session':self.session,'revoked':False,'last_seen':None})
            self.devices[device_id]=device
            item.update({'approved':True,'device_id':device_id,'token':token})
            self.save(); self.audit('pair-approve','accepted',device=device)

    def claim(self,request_id,claim):
        with self.lock:
            item=self.pending.get(request_id)
            if not item or item['expires']<=self.clock() or not hmac.compare_digest(item['claim_hash'],digest(claim)):
                raise SecurityError('Demande expirée ou clé invalide')
            if not item['approved']:
                return {'pending':True}
            device=self.devices[item['device_id']]
            if device['revoked']:
                raise SecurityError('Appareil révoqué')
            result={'device_id':item['device_id'],'token':item['token'],'name':device['name'],'operator':device['operator'],'role':device['role'],'authorization_type':device.get('authorization_type','temporary'),'expires':device['expires'],'session':self.session,'server':self.server}
            del self.pending[request_id]
            return result

    def revoke(self,device_id=None):
        with self.lock:
            self.load(); self.refresh_password()
            if device_id and device_id not in self.devices:
                raise SecurityError('Appareil inconnu')
            for key,item in self.devices.items():
                if device_id is None or key==device_id:
                    item['revoked']=True; item['key']=''
            if device_id is None:
                self.armed=False; self.pending.clear(); self.codes.clear()
            self.save(); self.audit('revoke-one' if device_id else 'revoke-all','accepted')

    def change_role(self,device_id,role):
        with self.lock:
            self.load(); self.refresh_password()
            if role not in PERMISSIONS or device_id not in self.devices:
                raise SecurityError('Appareil ou rôle inconnu')
            self.devices[device_id]['role']=role; self.save(); self.audit('change-role','accepted',device=self.devices[device_id])

    def authorize(self,device_id,signature,method,path,body,timestamp,nonce,permission,critical=True):
        with self.lock:
            self.load(); self.refresh_password(); device=self.devices.get(device_id); now=self.clock()
            if not device or device['revoked'] or not device['key']:
                raise SecurityError('Appareil inconnu ou révoqué')
            if not self._authorization_current(device,now):
                raise SecurityError('Prise de poste expirée')
            if permission not in PERMISSIONS[device['role']]:
                raise SecurityError('Permission insuffisante')
            if critical and not self.armed:
                raise SecurityError('Télécommandes désarmées')
            try:
                stamp=float(timestamp)
            except (TypeError,ValueError):
                raise SecurityError('Horodatage invalide')
            if not math.isfinite(stamp) or abs(now-stamp)>15:
                raise SecurityError('Requête ancienne ou horloge incorrecte')
            if not isinstance(nonce,str) or not 16<=len(nonce)<=128:
                raise SecurityError('Nonce invalide')
            expected=hmac.new(bytes.fromhex(device['key']),canonical_request(method,path,body,timestamp,nonce),hashlib.sha256).hexdigest()
            if not isinstance(signature,str) or not hmac.compare_digest(expected,signature):
                raise SecurityError('Signature invalide')
            self.nonces={key:expiry for key,expiry in self.nonces.items() if expiry>now}
            key=(device_id,nonce)
            if key in self.nonces:
                raise SecurityError('Requête déjà utilisée')
            if len(self.nonces)>=8192:
                raise SecurityError('Trop de commandes ; attendre')
            self.nonces[key]=now+30; device['last_seen']=now
            self.runtime_seen[device_id]=now
            if device.get('authorization_type') == 'permanent':
                # Durable nonce consumption also prevents replay after a quick restart.
                self.save()
            return {k:v for k,v in device.items() if k not in ('key','password_revision')}

    def _authorization_current(self,device,now):
        kind = device.get('authorization_type','temporary')
        if kind == 'permanent':
            return device.get('expires') is None and bool(self.password_revision) and device.get('password_revision') == self.password_revision
        if kind != 'temporary':
            return False
        expires = device.get('expires')
        return (isinstance(expires,(int,float)) and not isinstance(expires,bool)
                and math.isfinite(expires) and expires>now and device.get('session')==self.session)

    def snapshot(self):
        with self.lock:
            self.load(); self.refresh_password(); now=self.clock()
            devices=[]
            for item in self.devices.values():
                public={k:v for k,v in item.items() if k not in ('key','password_revision')}
                public['authorization_type']=item.get('authorization_type','temporary')
                public['active']=not item['revoked'] and bool(item.get('key')) and self._authorization_current(item,now)
                public['connected']=public['active'] and item['id'] in self.runtime_seen and now-self.runtime_seen[item['id']]<10
                devices.append(public)
            return {'configured':bool(self.password_record),'server':self.server,'session':self.session,'armed':self.armed,'mode':self.mode,
                    'devices':devices,'pending':[{k:v for k,v in item.items() if k not in ('claim_hash','token')} for item in self.pending.values() if item['expires']>now]}
