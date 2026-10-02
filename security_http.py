"""Small Flask boundary around remote security; musical handlers stay unchanged."""
import ipaddress
import os
from pathlib import Path
from urllib.parse import urlsplit
from flask import g, jsonify, make_response, request, send_file
from remote_security import RemoteSecurity, SecurityError

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
    cookie_name='cl_admin_launcher' if launcher else 'cl_admin_backend'

    def local_admin():
        if not local_request():
            raise SecurityError('Administration réservée au serveur local')
        manager.admin(request.cookies.get(cookie_name) or request.headers.get('X-CL-Admin',''))

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
        if launcher and path in {'/quit','/stop','/open','/local-page','/open-ab','/open-arrangement','/remote-window'}:
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
        command=str(data.get('action') or path)[:120]
        g.cl_command=command; g.cl_scene=data.get('scene') if isinstance(data.get('scene'),(str,int,float,type(None))) else None
        try:
            if local_request():
                if permission=='admin':
                    local_admin(); settings_allowed()
                g.cl_device={'id':'local','role':'local','operator':''}
            else:
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
        except SecurityError as error:
            identity = manager.devices.get(request.headers.get('X-CL-Device',''))
            manager.audit(command,'refused',str(error),device=identity,scene=g.cl_scene)
            return jsonify(ok=False,error=str(error),security_required=True),403
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
                token=manager.unlock(data.get('password'))
                response=make_response(jsonify(ok=True)); response.set_cookie(cookie_name,token,max_age=300,httponly=True,samesite='Strict',secure=request.is_secure,path='/')
                return response
            local_admin()
            if operation=='lock': manager.lock_admin()
            elif operation=='password': manager.set_password(data.get('password'))
            elif operation=='mode': manager.set_mode(data.get('mode'))
            elif operation=='arm': manager.set_armed(data.get('armed') is True)
            elif operation=='revoke': manager.revoke(data.get('device_id'))
            elif operation=='role': settings_allowed(); manager.change_role(data.get('device_id'),data.get('role'))
            elif operation=='approve': manager.approve(data.get('request_id'),data.get('lifetime',43200),data.get('authorization_type','temporary'))
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
                # QR destination is operator-selected HTTPS, never derived from Host/Bonjour.
                base=str(data.get('server_url') or os.environ.get('CL_REMOTE_PUBLIC_URL','') or _tls_config(manager.directory).get('server_url','')).rstrip('/')
                parsed=urlsplit(base)
                if parsed.scheme!='https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('','/'):
                    raise SecurityError('URL serveur HTTPS explicite requise')
                code=manager.new_code(data.get('role','operator'))
                url=base+'/remote/pair#code='+code
                # Fragment avoids leaking the one-use code through server/access logs.
                import io
                import qrcode
                import qrcode.image.svg
                image=qrcode.make(url,image_factory=qrcode.image.svg.SvgPathImage)
                buffer=io.BytesIO(); image.save(buffer)
                return jsonify(ok=True,url=url,svg=buffer.getvalue().decode(),expires=manager.clock()+120)
            else: raise SecurityError('Opération inconnue')
            return jsonify(ok=True)
        except (SecurityError,TypeError,ValueError,OSError) as error:
            return jsonify(ok=False,error=str(error)),403

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
            return jsonify(ok=True,armed=manager.armed,role=device['role'])
        except SecurityError as error: return jsonify(ok=False,error=str(error)),403

    @app.route('/security/panel')
    def panel():
        if not local_request(): return jsonify(error='Local only'),403
        return send_file(Path(__file__).with_name('static')/'security-panel.html')

    @app.route('/security/diagnostics')
    def diagnostics():
        result={'http':{'state':'OK','port':5055 if launcher else 5050},
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


def start_remote_tls(app):
    """Optional secure listener: local 5050 HTTP stays compatible with launcher."""
    manager=app.extensions['cl_security']
    settings=_tls_config(manager.directory)
    cert,key=os.environ.get('CL_REMOTE_TLS_CERT',settings.get('certificate')),os.environ.get('CL_REMOTE_TLS_KEY',settings.get('private_key'))
    if not cert and not key:
        return None
    if not cert or not key:
        raise ValueError('Certificat ET clé TLS requis')
    if Path(key).stat().st_mode & 0o077:
        raise ValueError('Clé privée TLS : permissions 0600 requises')
    from werkzeug.serving import make_server
    import threading
    server=make_server('0.0.0.0',int(os.environ.get('CL_REMOTE_TLS_PORT',str(settings.get('port',8443)))),app,threaded=True,ssl_context=(cert,key))
    threading.Thread(target=server.serve_forever,name='CL Remote TLS',daemon=True).start()
    return server


def _tls_config(directory):
    import json
    path=Path(directory)/'remote-tls.json'
    return json.loads(path.read_text()) if path.exists() else {}
