#!/usr/bin/env python3
"""Opt-in addition to an existing AbletonOSC; preserves every other source file."""
import argparse
import ast
from pathlib import Path
import shutil


def install(target):
    init = target / '__init__.py'
    manager = target / 'manager.py'
    source = init.read_text(encoding='utf-8')
    tree = ast.parse(source)
    manager_source = manager.read_text(encoding='utf-8')
    if 'class Manager(' not in manager_source or 'def disconnect(' not in manager_source:
        raise ValueError('Version AbletonOSC non reconnue : aucune modification effectuée')
    imports = [node for node in ast.walk(tree) if isinstance(node, ast.ImportFrom)
               and node.level == 1 and node.module == 'manager'
               and len(node.names) == 1 and node.names[0].name == 'Manager'
               and node.names[0].asname is None]
    installed = any(isinstance(node, ast.ImportFrom) and node.level == 1
                    and node.module == 'cl_bonjour' for node in ast.walk(tree))
    if not installed and len(imports) != 1:
        raise ValueError('Import Manager ambigu : aucune modification effectuée')
    if not installed:
        node = imports[0]
        lines = source.splitlines(keepends=True)
        if node.end_lineno != node.lineno:
            raise ValueError('Import multiligne non pris en charge')
        indent = lines[node.lineno - 1][:node.col_offset]
        lines[node.lineno - 1] = indent + 'from .cl_bonjour import BonjourManager as Manager\n'
        updated = ''.join(lines)
        ast.parse(updated)
        backup = target / '__init__.py.before-cl-bonjour'
        if backup.exists():
            raise ValueError('Sauvegarde déjà présente : vérifier avant de réinstaller')
        shutil.copy2(init, backup)
    shutil.copy2(Path(__file__).with_name('cl_bonjour.py'), target / 'cl_bonjour.py')
    if not installed:
        init.write_text(updated, encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Ajouter Bonjour à AbletonOSC existant (Live fermé).')
    parser.add_argument('--target', type=Path, default=Path.home() / 'Music/Ableton/User Library/Remote Scripts/AbletonOSC')
    args = parser.parse_args()
    install(args.target)
    print('Bonjour installé. Redémarrer Live avec la surface AbletonOSC active.')
