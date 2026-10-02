"""Local console recovery; deliberately has no HTTP reset endpoint."""
import getpass
import sys
from pathlib import Path
from remote_security import RemoteSecurity


def reset_admin_password():
    if not sys.stdin.isatty():
        raise RuntimeError('Réinitialisation réservée au terminal local interactif')
    print('Réinitialisation locale : les télécommandes seront révoquées et désarmées.')
    if input('Saisir RESET pour confirmer : ').strip()!='RESET':
        return
    password=getpass.getpass('Nouveau mot de passe administrateur (12 caractères minimum) : ')
    if password!=getpass.getpass('Confirmer : '):
        raise ValueError('Les mots de passe diffèrent')
    RemoteSecurity(Path.home()/'Library/Application Support/CL Audio Controller/Security').set_password(password)
    print('Mot de passe remplacé. Refaire les prises de poste.')

if __name__=='__main__': reset_admin_password()
