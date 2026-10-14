"""Product boundary: Light reuses the common host with explicit capabilities."""
from app_mode import AppMode, capabilities_for
from contextvars import ContextVar

_common_host = ContextVar("common_engine_capabilities", default=None)

def host_capabilities():
    return _common_host.get() or capabilities_for()



def create_selected_app(mode=None):
    capabilities = capabilities_for(mode)
    if capabilities.mode is AppMode.LOCAL_LIGHT:
        import os
        if os.environ.get("CL_LIGHT_ENGINE") == "legacy":
            from light_runtime import create_light_app
            return create_light_app()
        from common_light_runtime import create_common_light_app
        return create_common_light_app()
    import app
    return app.app


def require_full_runtime():
    """Fail closed if an embedding host bypasses the selected backend factory."""
    if capabilities_for().mode is not AppMode.FULL and _common_host.get() is None:
        raise RuntimeError('LOCAL_LIGHT: utiliser runtime_startup.create_selected_app()')


def run_light_entry(entry):
    """Return without side effects in FULL; own only local services in Light."""
    if capabilities_for().mode is not AppMode.LOCAL_LIGHT:
        return False
    import os
    if os.environ.get("CL_LIGHT_ENGINE") == "legacy":
        from light_runtime import run_light
    else:
        from common_light_runtime import run_light
    import sys
    run_light(window=entry == "launcher" and "--serve" not in sys.argv)
    return True


def create_common_light_controller(runtime, timing, go_context, consumer):
    """Internal migration factory; shares an existing host, starts no services."""
    from ableton_runtime import CommonLightController
    return CommonLightController(runtime, timing, go_context, consumer)
