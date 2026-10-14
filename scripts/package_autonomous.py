"""Assemble a minimal offline Mac kit from a freshly built Show Control bundle."""
import argparse, json, pathlib, shutil, subprocess, sys, zipfile
root = pathlib.Path(__file__).resolve().parents[1]
def package(app, output):
    output.mkdir(parents=True, exist_ok=False)
    bundle = output / 'CL Show Control.app'
    shutil.copytree(app, bundle, symlinks=True)
    (bundle/'Contents/Resources/autonomous-mode.json').write_text(json.dumps({'mode':'autonomous','version':1})+'\n')
    osc = output/'AbletonOSC'; osc.mkdir()
    archive = subprocess.check_output(['git','-C',str(root.parent/'AbletonOSC'),'archive','--format=tar','HEAD'])
    subprocess.run(['tar','-xf','-','-C',str(osc)],input=archive,check=True)
    for helper in ('install_bonjour.py','install_fast_poll.py'):
        subprocess.run([sys.executable,str(root/'INSTALLER_AbletonOSC'/helper),'--target',str(osc)],check=True)
    subprocess.run(['codesign','--force','--deep','--sign','-',str(bundle)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(bundle)],check=True)
    shutil.copy2(root/'packaging/Installer_CL_Autonome.command',output/'Installer CL Autonome.command')
    (output/'Installer CL Autonome.command').chmod(0o755)
    (output/'LISEZ-MOI.txt').write_text('CL SHOW CONTROL — MAC AUTONOME\n\nFermez Ableton Live et CL Show Control, puis ouvrez Installer CL Autonome.command.\nLe kit contient uniquement Show Control et AbletonOSC ; Ableton Live 11/12 doit être installé séparément.\nDans Live : Réglages > Link/Tempo/MIDI > surface de contrôle AbletonOSC, entrée/sortie None.\nOuvrez Show Control, choisissez ce Mac pour le serveur et le lecteur Ableton, appliquez puis testez la connexion.\nSession, Arrangement et A/B restent disponibles. Les retours consoles, le backup et le LTC sont masqués.\nPour un iPhone, conservez le mécanisme habituel HTTPS, appairage et armement.\nLes anciennes applications et le script AbletonOSC sont conservés avec un suffixe de sauvegarde.\nPour revenir à la version complète : fermez les applications et remettez la copie sauvegardée de Show Control à son nom initial.\n')
    shutil.make_archive(str(output),'zip',root_dir=output.parent,base_dir=output.name)
    print(output)
if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('app',type=pathlib.Path);p.add_argument('output',type=pathlib.Path)
    args=p.parse_args();package(args.app,args.output)
