"""Small Flask boundary around remote security; musical handlers stay unchanged."""
import ipaddress
import os
import re
import subprocess
from pathlib import Path
from urllib.parse import urlsplit
from flask import g, jsonify, make_response, request, send_file
from remote_security import RemoteSecurity, SecurityError, device_permissions
from remote_tls import RemoteTLS, network_identity, prepare_certificate, read_settings, save_settings, server_address

LOCAL_HOSTS={'localhost','127.0.0.1','::1'}
LOCAL_EXEMPT={'/shutdown','/ownership/verify'}
ADMIN_ACTIONS={'console_title_mode','console_title_offset'}
READ_ONLY={'/','/ab','/arrangement','/status','/info','/ip','/server_info','/show-info',
 '/show-info/builder','/show-info/network','/show-info/clock','/show-info/status','/console-scene-title',
 '/show-info/work-assignments','/show-info/cues','/show-info/sessions','/show-info/builder/document',
 '/show-info/builder/resources','/show-info/builder/sessions/export','/show-info/builder/export.csv',
 '/show-info/builder/export.xlsx','/show-info/builder/export.pdf','/show-info/audio-test',
 '/state','/telemetry','/network-config','/api/ableton-discovery','/api/scene-backup','/api/hot-backup',
 '/api/cl-mtc-bridge/status','/api/console-simulators/status','/help','/logo','/paradis-logo',
 '/show-audio/track-hierarchy','/show-audio/tracks-bulk','/show-audio/print/preflight',
 '/show-audio/print/clip-info','/show-audio/tracks','/show-audio/scene-clips-bulk','/show-audio/scene-clips'}


def local_request():
    try:
        if not ipaddress.ip_address(request.remote_addr or '').is_loopback:
            return False
    except ValueError:
        return False
    parsed=urlsplit(request.host_url)
    if parsed.hostname not in LOCAL_HOSTS:
        return False
    origin=request.headers.get('Origin')
    if origin and origin!=request.host_url.rstrip('/'):
        return False
    if request.headers.get('Sec-Fetch-Site')=='cross-site':
        return False
    return True


def attach_security(app, *, launcher=False, directory=None):
    if directory is None:
        override = os.environ.get('CL_SECURITY_DIRECTORY')
        directory = Path(override) if override else Path.home()/'Library/Application Support/CL Audio Controller/Security'
    manager=RemoteSecurity(directory, namespace="launcher" if launcher else "backend")
    app.extensions['cl_security']=manager
    tls = None if launcher else RemoteTLS(app, manager.directory)
    if tls is not None:
        app.extensions['cl_remote_tls'] = tls
    cookie_name='cl_admin_launcher' if launcher else 'cl_admin_backend'

    def local_admin():
        if not local_request():
            raise SecurityError('Administration réservée au serveur local')
        manager.admin(request.cookies.get(cookie_name) or request.headers.get('X-CL-Admin',''), local=True)

    def settings_allowed():
        if manager.mode!='development':
            raise SecurityError('Mode spectacle : passer localement en mode développement pour modifier les réglages')

    @app.before_request
    def secure_boundary():
        path=request.path
        if path.startswith(('/security/','/remote/')) and request.content_length and request.content_length > 16384:
            return jsonify(error='Requête de sécurité trop grande'),413
        if path.startswith('/security/') or path.startswith('/remote/'):
            return None
        if launcher and path in {'/quit','/stop','/open','/local-page','/open-ab','/open-arrangement','/remote-window','/open-showq','/midi-network-assistant'}:
            if not local_request():
                return jsonify(ok=False,error='Commande locale requise'),403
            return None
        if path in LOCAL_EXEMPT and not launcher:
            # Existing ownership challenge protects these; LAN access was never needed.
            if not local_request():
                return jsonify(ok=False,error='Local ownership only'),403
            return None
        safe=request.method in ('GET','HEAD','OPTIONS') and (path in READ_ONLY or path.startswith(('/static/','/assets/')) or (path.startswith('/show-info/cues/') and path.endswith('/audio')))
        if safe:
            return None
        data=request.get_json(silent=True) or {}
        if not isinstance(data,dict):
            return jsonify(error='Objet JSON requis'),400
        permission='show' if path=='/action' and data.get('action') not in ADMIN_ACTIONS else 'admin'
        if path=='/transport/test' or path=='/show-audio/print/capture-clean':
            permission='show'
        if path == '/action' and data.get('action') == 'go':
            permission = 'go'
        cue_write = request.method == 'PUT' and re.fullmatch(r'/show-info/cues/[^/]+', path)
        note_write = request.method == 'PUT' and re.fullmatch(r'/show-info/cues/[^/]+/notes/[^/]+', path)
        if cue_write or (request.method == 'POST' and path == '/show-info/cues') or (request.method == 'DELETE' and re.fullmatch(r'/show-info/cues/[^/]+', path)):
            permission = 'edit_cues'
        if note_write:
            permission = 'edit_cues' if path.endswith('/GENERAL') else 'edit_notes'
        command=str(data.get('action') or path)[:120]
        g.cl_command=command; g.cl_scene=data.get('scene') if isinstance(data.get('scene'),(str,int,float,type(None))) else None
        try:
            if local_request():
                if permission in ('admin', 'edit_cues', 'edit_notes'):
                    local_admin()
                    if permission == 'admin': settings_allowed()
                g.cl_device={'id':'local','role':'local','operator':''}
            else:
                if permission in ('edit_cues', 'edit_notes') and not request.is_secure:
                    raise SecurityError('Administration distante : HTTPS requis')
                if permission in ('edit_cues', 'edit_notes') and isinstance(data.get('builder'), dict) and 'notes_by_post' in data['builder']:
                    raise SecurityError('Utiliser la route de note par poste')
                if permission=='admin':
                    if not request.is_secure:
                        raise SecurityError('Administration distante : HTTPS requis')
                    manager.refresh_password()
                    settings_allowed()
                    if not any(expiry > manager.clock() for expiry in manager.admin_sessions.values()):
                        raise SecurityError('Réglage sensible : déverrouillage local requis')
                g.cl_device=manager.authorize(request.headers.get('X-CL-Device',''),request.headers.get('X-CL-Signature',''),
                    request.method,request.full_path.rstrip('?'),request.get_data(),request.headers.get('X-CL-Timestamp',''),
                    request.headers.get('X-CL-Nonce',''),permission,critical=True)
                if note_write and permission == 'edit_notes' and path.rsplit('/', 1)[1] not in g.cl_device.get('posts', []):
                    raise SecurityError('Appareil non autorisé pour le poste ' + path.rsplit('/', 1)[1])
        except SecurityError as error:
            identity = manager.devices.get(request.headers.get('X-CL-Device',''))
            manager.audit(command,'refused',str(error),device=identity,scene=g.cl_scene)
            result={'ok':False,'error':str(error),'security_required':True}
            if path.startswith('/show-info/'):
                # Echo only non-sensitive identity metadata, never signature values.
                requested=request.headers.get('X-CL-Device','')
                parsed=urlsplit(request.headers.get('Origin',''))
                origin=(parsed.scheme+'://'+parsed.netloc) if parsed.scheme in ('http','https') and not parsed.username and not parsed.password else None
                result['auth_diagnostic']={'requested_device_id':requested if re.fullmatch(r'[a-f0-9]{32}',requested) else None,
                    'device_known':identity is not None,'device_revoked':bool(identity and identity.get('revoked')),
                    'origin':origin,'https':request.is_secure,
                    'headers':{name:bool(request.headers.get(name)) for name in ('X-CL-Device','X-CL-Timestamp','X-CL-Nonce','X-CL-Signature')}}
            return jsonify(result),403
        return None

    @app.after_request
    def audit_result(response):
        if hasattr(g,'cl_device'):
            result='accepted' if response.status_code<400 else 'refused'
            manager.audit(g.cl_command,result,'' if result=='accepted' else 'handler-http-'+str(response.status_code),device=g.cl_device,scene=g.cl_scene)
        if request.path.startswith(('/security/','/remote/')):
            response.headers['Cache-Control']='no-store'
            response.headers['Referrer-Policy']='no-referrer'
            response.headers['X-Content-Type-Options']='nosniff'
            response.headers['Content-Security-Policy']="default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
        return response

    @app.route('/security/status')
    def security_status():
        manager.load(); manager.refresh_password()
        if not local_request():
            return jsonify(armed=manager.armed,mode=manager.mode),200
        snapshot=manager.snapshot()
        try: local_admin(); snapshot['unlocked']=True
        except SecurityError:
            snapshot['unlocked']=False; snapshot.pop('pending'); snapshot.pop('devices')
        snapshot["admin_unlock"]=manager.admin_status(request.cookies.get(cookie_name) or request.headers.get("X-CL-Admin"))
        return jsonify(snapshot)

    @app.route('/security/admin/<operation>',methods=['POST'])
    def security_admin(operation):
        data=request.get_json(silent=True) or {}
        if not isinstance(data,dict):
            return jsonify(error='Objet JSON requis'),400
        try:
            if not local_request():
                raise SecurityError('Administration locale requise')
            if operation=='setup':
                manager.set_password(data.get('password'),initial=True)
                return jsonify(ok=True)
            if operation=='unlock':
                duration=data.get('duration','five_minutes')
                token=manager.unlock(data.get('password'),duration=duration)
                response=make_response(jsonify(ok=True)); response.set_cookie(cookie_name,token,max_age=None if duration=='session' else 300,httponly=True,samesite='Strict',secure=request.is_secure,path='/')
                return response
            local_admin()
            if operation=='lock': manager.lock_admin()
            elif operation=='password': manager.set_password(data.get('password'))
            elif operation=='mode': manager.set_mode(data.get('mode'))
            elif operation=='arm': manager.set_armed(data.get('armed') is True)
            elif operation=='revoke': manager.revoke(data.get('device_id'))
            elif operation=='permissions': settings_allowed(); manager.change_permissions(data.get('device_id'), data.get('permissions'), data.get('posts'))
            elif operation=='role': settings_allowed(); manager.change_role(data.get('device_id'),data.get('role'))
            elif operation=='approve': manager.approve(data.get('request_id'),data.get('lifetime',43200),data.get('authorization_type','temporary'))
            elif operation in ('tls-setup', 'tls-start', 'tls-enroll'):
                settings_allowed()
                if launcher:
                    raise SecurityError('Ouvrir Première configuration dans le backend local sur 5050')
                with tls.lock:
                    if operation == 'tls-setup':
                        identity = network_identity()
                        base = str(data.get('server_url') or identity['suggested_url']).rstrip('/')
                        settings = prepare_certificate(manager.directory, base, identity)
                        tls.identity = identity
                        tls.start(settings)
                        tls.probe()
                        save_settings(manager.directory, settings)
                        manager.audit('tls-setup', 'accepted')
                        return jsonify(ok=True, https=tls.snapshot(), enrollment=tls.enroll())
                    if operation == 'tls-start':
                        tls.start(read_settings(manager.directory))
                        tls.probe()
                        return jsonify(ok=True, https=tls.snapshot())
                    enrollment = tls.enroll()
                    return jsonify(ok=True, enrollment=enrollment, svg=qr_svg(enrollment['url']))
            elif operation=='tls':
                settings_allowed()
                if launcher:
                    raise SecurityError('Configurer TLS depuis le backend local')
                import ssl
                cert,key=Path(str(data.get('certificate',''))),Path(str(data.get('private_key','')))
                port=int(data.get('port',8443))
                base=str(data.get('server_url','')).rstrip('/')
                parsed=urlsplit(base)
                if not cert.is_absolute() or not key.is_absolute() or not cert.is_file() or not key.is_file():
                    raise SecurityError('Chemins absolus vers certificat et clé requis')
                if not 1<=port<=65535 or port in (5050,5055):
                    raise SecurityError('Port TLS distinct de 5050/5055 requis')
                if parsed.scheme!='https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('','/') or (parsed.port or 443)!=port:
                    raise SecurityError('URL HTTPS et port TLS incohérents')
                if key.stat().st_mode & 0o077:
                    raise SecurityError('Clé privée TLS : permissions 0600 requises')
                context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); context.load_cert_chain(cert,key)
                manager.directory.mkdir(mode=0o700,parents=True,exist_ok=True)
                target=manager.directory/'remote-tls.json'
                import json,secrets
                temporary=target.with_name('tls-'+secrets.token_hex(8)+'.tmp')
                fd=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
                with os.fdopen(fd,'w') as file:
                    json.dump({'certificate':str(cert),'private_key':str(key),'port':port,'server_url':base},file)
                os.replace(temporary,target)
                manager.audit('tls-config','accepted')
                return jsonify(ok=True,restart_required=True)
            elif operation=='qr':
                settings_allowed()
                if launcher:
                    raise SecurityError('Ouvrir la gestion des télécommandes du backend local sur 5050 : les QR appartiennent à ce serveur')
                base=str(data.get('server_url') or os.environ.get('CL_REMOTE_PUBLIC_URL','') or _tls_config(manager.directory).get('server_url','')).rstrip('/')
                tls.probe(base)
                if not tls.snapshot()['phone_verified']:
                    raise SecurityError('Vérifier d’abord HTTPS depuis l’iPhone avec le lien de test')
                code=manager.new_code(data.get('role','operator'))
                url=base+'/remote/pair#code='+code
                # Fragment avoids leaking the one-use code through server/access logs.
                return jsonify(ok=True,url=url,svg=qr_svg(url),expires=manager.clock()+120)
            else: raise SecurityError('Opération inconnue')
            return jsonify(ok=True)
        except (SecurityError,TypeError,ValueError,OSError,subprocess.SubprocessError) as error:
            return jsonify(ok=False,error=str(error)),403

    @app.route('/remote/ready')
    def remote_ready():
        if tls is None or not request.is_secure:
            return jsonify(error='HTTPS requis'),403
        return jsonify(instance=tls.instance)

    @app.route('/remote/check')
    def remote_check():
        if tls is None or not request.is_secure:
            return jsonify(error='Ouvrir le lien de test HTTPS depuis Safari'),403
        return send_file(Path(__file__).with_name('static')/'remote-check.html')

    @app.route('/remote/verify',methods=['POST'])
    def remote_verify():
        import time
        if tls is None or not request.is_secure:
            return jsonify(error='HTTPS requis'),403
        try:
            if ipaddress.ip_address(request.remote_addr or '').is_loopback:
                raise SecurityError('Effectuer le test depuis l’iPhone sur le même réseau')
        except (SecurityError,ValueError) as error:
            return jsonify(error=str(error)),403
        try:
            # DNS names are case-insensitive; Safari normalizes the Bonjour host.
            configured_origin = server_address(tls.settings.get('server_url'))
            request_origin = server_address(request.host_url)
            origin = request.headers.get('Origin')
            if request_origin != configured_origin or request.headers.get('Sec-Fetch-Site') == 'cross-site' or (origin and server_address(origin) != configured_origin):
                raise SecurityError('Origine HTTPS différente')
        except SecurityError:
            return jsonify(error='Utiliser le lien HTTPS proposé sur le Mac'),403
        tls.phone_seen=time.time()
        return jsonify(ok=True,message='Connexion sécurisée confirmée. Revenez sur le Mac.')

    @app.route('/remote/trust/<token>')
    def remote_trust(token):
        if tls is None:
            return jsonify(error='Backend requis'),403
        try:
            response=make_response(tls.profile(token))
            response.headers['Content-Type']='application/x-apple-aspen-config'
            response.headers['Content-Disposition']='attachment; filename="CL-Show-Control.mobileconfig"'
            return response
        except (SecurityError,OSError,ValueError) as error:
            return jsonify(error=str(error)),403

    @app.route('/remote/pair')
    def pair_page():
        return send_file(Path(__file__).with_name('static')/'remote-pair.html')

    @app.route('/remote/pair/request',methods=['POST'])
    def pair_request():
        if not request.is_secure:
            return jsonify(error='Appairage HTTPS requis'),403
        data=request.get_json(silent=True) or {}
        if not isinstance(data,dict):
            return jsonify(error='Objet JSON requis'),400
        try: return jsonify(manager.request_pair(str(data.get('code','')),data.get('name','Télécommande'),data.get('operator','')))
        except SecurityError as error: return jsonify(error=str(error)),403

    @app.route('/remote/pair/claim',methods=['POST'])
    def pair_claim():
        if not request.is_secure:
            return jsonify(error='HTTPS requis'),403
        data=request.get_json(silent=True) or {}
        if not isinstance(data,dict):
            return jsonify(error='Objet JSON requis'),400
        try: return jsonify(manager.claim(str(data.get('request_id','')),str(data.get('claim',''))))
        except SecurityError as error: return jsonify(error=str(error)),403

    @app.route('/remote/heartbeat',methods=['POST'])
    def heartbeat():
        try:
            device=manager.authorize(request.headers.get('X-CL-Device',''),request.headers.get('X-CL-Signature',''),request.method,
                request.full_path.rstrip('?'),request.get_data(),request.headers.get('X-CL-Timestamp',''),request.headers.get('X-CL-Nonce',''),'read',critical=False)
            return jsonify(ok=True,armed=manager.armed,role=device['role'],permissions=device_permissions(device),posts=device.get('posts', []))
        except SecurityError as error: return jsonify(ok=False,error=str(error)),403

    @app.route('/security/panel')
    def panel():
        if not local_request(): return jsonify(error='Local only'),403
        return send_file(Path(__file__).with_name('static')/'security-panel.html')

    @app.route('/security/showcue-qr')
    def showcue_qr():
        # Navigation only: no token, association, role or arm operation.
        if not local_request(): return jsonify(error='Accès réservé au Mac local'),403
        try:
            if tls is None: raise SecurityError('Ouvrir les télécommandes sur le serveur 5050')
            snapshot=tls.snapshot()
            if not snapshot.get('ready'): raise SecurityError('Préparer ou démarrer HTTPS avant d’ouvrir ShowCue')
            base=snapshot.get('server_url','').rstrip('/')
            parsed=urlsplit(base)
            if parsed.scheme!='https' or not parsed.hostname or parsed.username or parsed.password:
                raise SecurityError('Adresse HTTPS configurée invalide')
            url=base+'/show-info'
            return jsonify(url=url,svg=qr_svg(url))
        except (SecurityError,OSError,ValueError) as error:
            return jsonify(error=str(error)),403

    @app.route('/security/check-qr')
    def check_qr():
        try:
            local_admin(); settings_allowed()
            if tls is None: raise SecurityError('Backend local requis')
            tls.probe()
            return jsonify(svg=qr_svg(tls.settings['server_url']+'/remote/check'))
        except (SecurityError,OSError,ValueError) as error:
            return jsonify(error=str(error)),403

    @app.route('/security/diagnostics')
    def diagnostics():
        if not local_request(): return jsonify(error='Diagnostics réservés au Mac local'),403
        result={'http':{'state':'ACTIVE' if not request.is_secure else 'UNKNOWN', 'port':5055 if launcher else 5050},
                'https': tls.snapshot() if tls else {'state':'BACKEND 5050 REQUIRED','ready':False},
                'bonjour':{'state':'DISCOVERY ONLY','authorizes':False},
                'remote_control':{'state':'ARMED' if manager.armed else 'DISARMED'}}
        if not launcher:
            backup=app.extensions.get('cl_scene_backup')
            result['scene_backup']=backup.snapshot() if backup else {'state':'UNAVAILABLE'}
        # Unknown is explicit: absence of telemetry must not become an OK lamp.
        for transport in ('ableton_osc','rtp_midi','mtc'):
            result[transport]={'state':'UNKNOWN','owner':{'ableton_osc':'backend → configured AbletonOSC','rtp_midi':'optional launchd RTP Agent / configured CoreMIDI sessions','mtc':'owned bridge or external process'}[transport]}
        osc_status = app.extensions.get('cl_osc_status')
        if osc_status:
            snapshot = osc_status()
            result['ableton_osc'] = {'state':'OK' if snapshot['connected'] else 'DOWN',
                'host':snapshot['host'],'last_response_at':snapshot['last_response_at'],'owner':'backend OSCTransport'}
        return jsonify(result)
    return manager


def qr_svg(url):
    import io
    import qrcode
    import qrcode.image.svg
    image=qrcode.make(url,image_factory=qrcode.image.svg.SvgPathImage)
    buffer=io.BytesIO(); image.save(buffer)
    return buffer.getvalue().decode()


def start_remote_tls(app):
    """Restore only explicit persisted TLS settings; failures never disable HTTP 5050."""
    tls=app.extensions['cl_remote_tls']
    try:
        settings=read_settings(tls.directory)
        for variable,field in (('CL_REMOTE_TLS_CERT','certificate'),('CL_REMOTE_TLS_KEY','private_key'),
                               ('CL_REMOTE_TLS_PORT','port'),('CL_REMOTE_PUBLIC_URL','server_url')):
            if os.environ.get(variable): settings[field]=os.environ[variable]
        if not settings: return None
        return tls.start(settings)
    except (OSError,ValueError,SecurityError) as error:
        tls.error=str(error)
        return None


def _tls_config(directory):
    return read_settings(directory)
