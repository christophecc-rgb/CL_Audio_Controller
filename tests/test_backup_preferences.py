from backup_preferences import load_backup_destination, save_backup_destination


def test_destination_survives_reload_without_activation_fields(tmp_path):
    path = tmp_path / 'backup.json'
    save_backup_destination(path, '192.168.1.138', 'MacBook-Pro.local.')
    assert load_backup_destination(path) == {'host': '192.168.1.138', 'bonjour_name': 'MacBook-Pro.local'}
    assert 'mode' not in load_backup_destination(path)


def test_invalid_or_missing_preferences_do_not_restore_target(tmp_path):
    path = tmp_path / 'backup.json'
    assert load_backup_destination(path)['host'] == ''
    path.write_text('{"host":"bad"}')
    assert load_backup_destination(path)['host'] == ''
