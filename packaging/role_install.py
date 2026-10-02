#!/usr/bin/env python3
"""Role installation: preflight before writes, reversible migration, no user config deletion."""
import argparse
import copy
import datetime
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
from urllib.parse import urlsplit

CATALOG_PATH = Path(__file__).with_name('installation_roles.json')
if not CATALOG_PATH.exists():
    CATALOG_PATH = Path(__file__).resolve().parent.parent / 'config/installation_roles.json'


def private_directory(path):
    missing=[];cursor=Path(path)
    while not cursor.exists():
        missing.append(cursor);cursor=cursor.parent
    for directory in reversed(missing):
        directory.mkdir(mode=0o700,exist_ok=True)


def manifest(role, features=(), custom=()):
    features, custom = tuple(features), tuple(custom)
    catalog = json.loads(CATALOG_PATH.read_text())
    result = copy.deepcopy(catalog['roles'][role])
    if role == 'custom':
        if not custom:
            raise ValueError('Installation personnalisée : sélectionner au moins un composant')
        if set(custom) - catalog['components'].keys():
            raise ValueError('Composant personnalisé inconnu')
        result['components'] = list(dict.fromkeys(custom))
    for feature in features:
        option = catalog['optional_features'][feature]
        if role not in option['roles']:
            raise ValueError('Option interdite pour ce rôle : ' + feature)
        for field in ('components', 'services', 'network_transports', 'ports'):
            result[field] = list(dict.fromkeys(result[field] + option[field]))
    for name in result['components']:
        service = catalog['components'][name].get('service')
        if service and service not in result['services']:
            result['services'].append(service)
    if role == 'custom':
        for field in ('network_transports','ports','permissions','dependencies'):
            result[field] = list(dict.fromkeys(value for name in result['components'] for value in catalog['components'][name].get(field,[])))
    result['forbidden_components'] = sorted(set(catalog['components']) - set(result['components']))
    result['forbidden_services'] = sorted({'com.claudio.midi-network-monitor','com.claudio.midi-rtp-agent'} - set(result['services']))
    result['visible_tools'] = list(result['components'])
    result['features'] = list(features)
    result['component_details'] = {name: copy.deepcopy(catalog['components'][name]) for name in result['components']}
    return result


class RoleInstaller:
    def __init__(self, home, kit, live=None, runner=subprocess.run):
        self.home = Path(home).absolute()
        self.kit = Path(kit).absolute()
        self.live = Path(live).absolute() if live else self.home / 'Music/Ableton/User Library'
        self.catalog = json.loads(CATALOG_PATH.read_text())
        self.runner = runner
        self.record = self.home / 'Library/Application Support/CL Audio Controller/role-installation.json'
        self.trash = self.home / '.Trash' / ('CL-role-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))

    def target(self, item):
        value = item['target']
        return self.live / value[6:] if value.startswith('@LIVE/') else self.home / value

    def audit(self, role_manifest):
        found = []
        for name, item in self.catalog['components'].items():
            target = self.target(item)
            if target.exists() or target.is_symlink():
                found.append({'kind':'component','component':name,'path':str(target),'required':name in role_manifest['components']})
            for pattern in (target.name + '.sauvegarde_*', target.stem + '.backup-*.app'):
                for backup in target.parent.glob(pattern):
                    found.append({'kind':'old_backup','path':str(backup),'required':False})
        for label in ['com.claudio.midi-network-monitor','com.claudio.midi-rtp-agent']:
            plist = self.home / 'Library/LaunchAgents' / (label + '.plist')
            if plist.exists():
                found.append({'kind':'agent','label':label,'path':str(plist),'required':label in role_manifest['services']})
        for root in [self.record.parent, self.home/'Library/Application Support/CL Audio Show Control', self.home/'Applications/CL Audio/CL_Transport']:
            if root.exists():
                found.append({'kind':'configuration','path':str(root),'action':'preserve'})
        for name in ['CL Audio Controller.app','CL Audio Show Control.app']:
            target = self.home/'Applications'/name
            if target.exists():
                found.append({'kind':'legacy_app','path':str(target),'required':False})
        legacy = self.record.parent/'CL_Suite_install_manifest.tsv'
        if legacy.exists() and not legacy.is_symlink():
            known = {item['path'] for item in found}
            required_paths = {str(self.target(item)) for item in role_manifest['component_details'].values()}
            for line in legacy.read_text().splitlines():
                columns = line.split('\t')
                for value in columns:
                    if not value.startswith('/'):
                        continue
                    path = Path(value)
                    # Historical manifests are data, not authority to remove arbitrary paths.
                    managed = (path.suffix=='.app' and path.is_relative_to(self.home/'Applications')) or (
                        path.is_relative_to(self.live/'Remote Scripts') and path != self.live/'Remote Scripts') or (
                        path.is_relative_to(self.live/'Presets') and path.name.startswith(('CL ','Paradis Latin AutoScene')))
                    if managed and path.exists() and str(path) not in known:
                        found.append({'kind':'legacy_component','path':str(path),'required':str(path) in required_paths})
                        known.add(str(path))
        return found

    def retire(self, path):
        path = Path(path)
        if not (path.exists() or path.is_symlink()):
            return
        # Never follow an installed symlink or remove config directories.
        self.trash.mkdir(parents=True,exist_ok=True)
        destination = self.trash / (str(len(list(self.trash.iterdir()))) + '_' + path.name)
        shutil.move(str(path), str(destination))

    def agent(self, label, enable=False):
        plist = self.home/'Library/LaunchAgents'/(label+'.plist')
        actual_home = Path.home().absolute()
        if self.home == actual_home and sys.platform == 'darwin' and os.environ.get('CL_SUITE_SKIP_POSTINSTALL') != '1':
            domain = 'gui/' + str(os.getuid())
            if not enable:
                result = self.runner(['launchctl','bootout',domain+'/'+label],capture_output=True)
                if result.returncode:
                    loaded = self.runner(['launchctl','print',domain+'/'+label],capture_output=True)
                    if loaded.returncode == 0:
                        raise RuntimeError('Service encore chargé : ' + label)
            else:
                self.runner(['launchctl','bootstrap',domain,str(plist)],check=True)
        if not enable:
            self.retire(plist)

    def preflight(self, m, url=''):
        requires_live = any(item['target'].startswith('@LIVE/') for item in m['component_details'].values())
        if requires_live:
            configured = os.environ.get('CL_SUITE_LIVE_APPS','')
            live_apps = [Path(path) for path in configured.split(':') if path] if configured else list((self.home/'Applications').glob('Ableton Live 1[12]*.app'))
            if self.home == Path.home().absolute() and not configured:
                live_apps += list(Path('/Applications').glob('Ableton Live 1[12]*.app'))
            live_apps = [path for path in live_apps if path.is_dir()]
            if not live_apps:
                raise ValueError('Ce rôle nécessite Ableton Live 11/12 ; préciser CL_SUITE_LIVE_APPS si nécessaire')
            requires_max = any('Max for Live' in item.get('dependencies',[]) for item in m['component_details'].values())
            if requires_max and os.environ.get('CL_SUITE_ASSUME_M4L') != '1' and not any('Suite' in path.name or (path/'Contents/App-Resources/Max').exists() for path in live_apps):
                raise ValueError('Max for Live requis pour les devices sélectionnés ; confirmer sa licence explicitement')
        for item in m['component_details'].values():
            if item.get('service'):
                executable = self.kit/item['source']/'Contents/MacOS'/Path(item['source']).stem
                if not executable.is_file():
                    raise FileNotFoundError('Exécutable agent absent du kit : ' + str(executable))
        for item in m['component_details'].values():
            target = self.target(item)
            if not target.resolve().is_relative_to(self.home.resolve()) and not (item['target'].startswith('@LIVE/') and target.resolve().is_relative_to(self.live.resolve())):
                raise ValueError('Destination hors installation')
            if not item.get('generated') and not (self.kit/item['source']).exists():
                raise FileNotFoundError('Composant absent du kit : ' + item['source'])
        if 'control_client' in m['components']:
            parsed = urlsplit(url)
            if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
                raise ValueError('Poste contrôle : URL serveur HTTPS explicite requise, sans identifiants')
        if 'show_backup' in m['components'] and not (self.kit/'SCENE_BACKUP_HMAC_RX_VALIDATED').exists():
            raise ValueError('Récepteur CL Show Backup externe : validation HMAC requise avant installation')
        # Verify selected artifacts against the exported kit, before any replacement.
        integrity = self.kit.parent/'COMPONENTS_SHA256.txt'
        if integrity.exists():
            import hashlib
            hashes = {}
            for line in integrity.read_text().splitlines():
                if len(line) > 66:
                    digest, name = line[:64], line[66:].lstrip('*')
                    hashes[name] = digest
            for item in m['component_details'].values():
                if item.get('generated'):
                    continue
                source = self.kit/item['source']
                paths = source.rglob('*') if source.is_dir() else [source]
                for path in paths:
                    if path.is_file() and not path.is_symlink():
                        key = str(path.relative_to(self.kit.parent))
                        if key not in hashes or hashlib.sha256(path.read_bytes()).hexdigest() != hashes[key]:
                            raise ValueError('Intégrité du kit invalide : ' + key)

    def install(self, m, migration='keep', url=''):
        self.preflight(m,url)
        if self.home == Path.home().absolute() and 'show_control' in m['components'] and sys.platform == 'darwin':
            import socket
            for port in (5050,5055):
                with socket.socket() as probe:
                    probe.settimeout(.25)
                    if probe.connect_ex(('127.0.0.1',port)) == 0:
                        raise RuntimeError('Quitter proprement Show Control avant remplacement (port '+str(port)+') ; rien remplacé')
        audit = self.audit(m)
        if migration not in ('keep','migrate','remove'):
            raise ValueError('Migration explicite requise')
        # Keep reports forbidden leftovers; it never silently enables services.
        if migration != 'keep':
            for item in audit:
                if item['kind'] == 'configuration' or item.get('required'):
                    continue
                if item['kind'] == 'agent':
                    self.agent(item['label'])
                else:
                    self.retire(item['path'])
        for name, item in m['component_details'].items():
            target = self.target(item)
            self.retire(target)
            target.parent.mkdir(parents=True,exist_ok=True)
            if item.get('generated'):
                contents = target/'Contents'; (contents/'MacOS').mkdir(parents=True)
                (contents/'Info.plist').write_bytes(plistlib.dumps({'CFBundleName':'CL Show Control Client','CFBundleIdentifier':'com.claudio.control-client','CFBundleExecutable':'CL Control Client','CFBundlePackageType':'APPL'}))
                import shlex
                script = contents/'MacOS/CL Control Client'
                script.write_text('#!/bin/sh\nexec /usr/bin/open ' + shlex.quote(url) + '\n'); script.chmod(0o755)
            else:
                source = self.kit/item['source']
                shutil.copytree(source,target,symlinks=True) if source.is_dir() else shutil.copy2(source,target)
        for label in m['services']:
            item = next(item for item in m['component_details'].values() if item.get('service') == label)
            target = self.target(item)
            executable = target/'Contents/MacOS'/target.stem
            if not executable.exists():
                raise FileNotFoundError('Exécutable agent absent : ' + str(executable))
            self.agent(label)
            plist = self.home/'Library/LaunchAgents'/(label+'.plist'); plist.parent.mkdir(parents=True,exist_ok=True)
            plist.write_bytes(plistlib.dumps({'Label':label,'ProgramArguments':[str(executable)],'RunAtLoad':True,'KeepAlive':True,'ThrottleInterval':5}))
            self.agent(label,enable=True)
        private_directory(self.record.parent)
        previous = json.loads(self.record.read_text()) if self.record.exists() else None
        record = {'manifest':m,'migration':migration,'audit_before':audit,'previous_role':previous.get('manifest',{}).get('role') if previous else None,'preserved_configurations':True,'installed_paths':[str(self.target(item)) for item in m['component_details'].values()]}
        if self.record.exists():
            shutil.copy2(self.record,self.record.with_name('role-installation.previous.json'))
        self.record.write_text(json.dumps(record,indent=2,ensure_ascii=False)); self.record.chmod(0o600)
        return self.validate(m)

    def uninstall(self, m):
        if self.home == Path.home().absolute() and 'show_control' in m['components'] and sys.platform == 'darwin':
            import socket
            for port in (5050,5055):
                with socket.socket() as probe:
                    probe.settimeout(.25)
                    if probe.connect_ex(('127.0.0.1',port)) == 0:
                        raise RuntimeError('Quitter proprement Show Control avant désinstallation ; rien retiré')
        if self.record.exists():
            recorded = json.loads(self.record.read_text()).get('manifest',{})
            if recorded.get('role') == m['role']:
                # Resolve through the trusted catalog; installed paths are never executable instructions.
                m = manifest(recorded['role'],recorded.get('features',()), recorded.get('components',()) if recorded['role']=='custom' else ())
        for label in m['services']:
            self.agent(label)
        for item in m['component_details'].values():
            self.retire(self.target(item))
        # Retain a documented record and all user configs for reinstall/recovery.
        private_directory(self.record.parent)
        self.record.with_name('role-uninstalled.json').write_text(json.dumps({'role':m['role'],'configurations':'preserved','trash':str(self.trash)},indent=2))
        return {'role':m['role'],'removed_components':m['components'],'configurations':'preserved','trash':str(self.trash)}

    def validate(self,m):
        missing = [name for name,item in m['component_details'].items() if not self.target(item).exists()]
        missing_agents = [label for label in m['services'] if not (self.home/'Library/LaunchAgents'/(label+'.plist')).exists()]
        extras = [item for item in self.audit(m) if item['kind'] != 'configuration' and not item.get('required')]
        return {'role':m['role'],'ok':not missing and not missing_agents and not extras,'missing':missing,'missing_agents':missing_agents,'migration_remaining':extras}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['plan','audit','install','uninstall','validate'])
    parser.add_argument('role',choices=json.loads(CATALOG_PATH.read_text())['roles'])
    parser.add_argument('--features',default=os.environ.get('CL_SUITE_ROLE_FEATURES',''))
    parser.add_argument('--components',default=os.environ.get('CL_SUITE_ROLE_COMPONENTS',''))
    parser.add_argument('--home',default=os.environ.get('CL_SUITE_INSTALL_HOME',str(Path.home())))
    parser.add_argument('--kit',default=str(Path(__file__).with_name('Composants')))
    parser.add_argument('--live-library',default=os.environ.get('CL_SUITE_USER_LIBRARY'))
    parser.add_argument('--server-url',default=os.environ.get('CL_SUITE_SERVER_URL',''))
    parser.add_argument('--migration',choices=['keep','migrate','remove'],default=os.environ.get('CL_SUITE_MIGRATION'))
    args=parser.parse_args()
    m=manifest(args.role,filter(None,args.features.split(',')),filter(None,args.components.split(',')))
    engine=RoleInstaller(args.home,args.kit,args.live_library)
    if args.action == 'plan': result=m
    elif args.action == 'audit': result=engine.audit(m)
    elif args.action == 'install':
        choice=args.migration
        if choice is None:
            print(json.dumps(engine.audit(m),indent=2,ensure_ascii=False))
            if os.environ.get('CL_SUITE_NONINTERACTIVE') == '1':
                raise ValueError('Choisir explicitement CL_SUITE_MIGRATION=keep|migrate|remove')
            choice=input('Migrer / Supprimer anciens composants / Conserver [migrate/remove/keep] : ').strip()
        result=engine.install(m,choice,args.server_url)
    elif args.action == 'uninstall': result=engine.uninstall(m)
    else: result=engine.validate(m)
    print(json.dumps(result,indent=2,ensure_ascii=False))
    return 0 if result.get('ok',True) else 2

if __name__ == '__main__':
    try: sys.exit(main())
    except (ValueError,KeyError,OSError,RuntimeError,subprocess.CalledProcessError) as error:
        print('ERREUR : '+str(error),file=sys.stderr); sys.exit(1)
