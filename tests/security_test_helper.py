import tempfile
from contextlib import contextmanager
from pathlib import Path

from remote_security import RemoteSecurity

TEST_ADMIN_PASSWORD = "Phase2 local test password"


def _manager(app_module, manager_attr=None):
    if manager_attr:
        return getattr(app_module, manager_attr), manager_attr

    if hasattr(app_module, "remote_security"):
        return app_module.remote_security, "remote_security"

    if hasattr(app_module, "launcher_security"):
        return app_module.launcher_security, "launcher_security"

    raise AttributeError("Aucun gestionnaire de sécurité trouvé")


def _fresh_security(directory, manager_attr):
    kwargs = {}
    if manager_attr == "launcher_security":
        kwargs["namespace"] = "launcher"
    return RemoteSecurity(Path(directory) / "Security", **kwargs)


def prepare_security(testcase, app_module, manager_attr=None):
    temporary = tempfile.TemporaryDirectory(prefix="cl-test-security-")
    testcase.addCleanup(temporary.cleanup)

    manager, resolved_attr = _manager(app_module, manager_attr)
    saved = dict(manager.__dict__)

    fresh = _fresh_security(temporary.name, resolved_attr)
    manager.__dict__.clear()
    manager.__dict__.update(fresh.__dict__)

    def restore():
        manager.__dict__.clear()
        manager.__dict__.update(saved)

    testcase.addCleanup(restore)
    manager.set_password(TEST_ADMIN_PASSWORD)


def admin_client(app_module, manager_attr=None):
    client = app_module.app.test_client()

    response = client.post(
        "/security/admin/unlock",
        json={"password": TEST_ADMIN_PASSWORD},
    )
    assert response.status_code == 200, response.data

    response = client.post(
        "/security/admin/mode",
        json={"mode": "development"},
    )
    assert response.status_code == 200, response.data

    return client


@contextmanager
def isolated_admin_client(app_module, manager_attr=None):
    temporary = tempfile.TemporaryDirectory(prefix="cl-test-security-")
    manager, resolved_attr = _manager(app_module, manager_attr)
    saved = dict(manager.__dict__)

    try:
        fresh = _fresh_security(temporary.name, resolved_attr)
        manager.__dict__.clear()
        manager.__dict__.update(fresh.__dict__)
        manager.set_password(TEST_ADMIN_PASSWORD)

        yield admin_client(
            app_module,
            manager_attr=resolved_attr,
        )
    finally:
        manager.__dict__.clear()
        manager.__dict__.update(saved)
        temporary.cleanup()
