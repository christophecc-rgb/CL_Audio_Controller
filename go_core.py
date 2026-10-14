"""Shared GO transaction; optional consumers own all product-specific effects."""
from dataclasses import dataclass
from typing import Any, Callable
import time


@dataclass(frozen=True)
class GoLaunch:
    request_id: str
    generation: int
    scene_index: int
    scene_name: str
    next_scene: int
    started_at: float


@dataclass
class GoContext:
    state: dict
    lock: Any
    scene_transaction_lock: Any
    completed_go_requests: dict
    ableton_transport: Any
    clamp_scene_number: Callable
    generation_is_current: Callable
    send: Callable
    _query_with_query_lock_held: Callable
    write_keyboard_diagnostic: Callable


class LocalGoConsumer:
    """No external dependencies, work, timers or consumers in LOCAL_LIGHT."""
    def before_launch(self, event):
        pass

    def after_send(self, event):
        pass

    def update_state_locked(self, event):
        pass

    def after_commit(self, event):
        pass


def execute_go_core(context, consumer, request_id, expected_generation, scene_number):
    scene_index = context.clamp_scene_number(scene_number)
    if scene_index is None:
        return False, "Numéro de scène invalide"

    request_key = (int(expected_generation), request_id)
    with context.scene_transaction_lock:
        with context.lock:
            cached = context.completed_go_requests.get(request_key)
            if cached is not None:
                return bool(cached["ok"]), str(cached["message"])
            if int(context.state.get("set_generation", 0)) != int(expected_generation):
                return False, "Génération de Live Set obsolète"
            if not context.state.get("set_ready", False):
                return False, "Live Set en cours de chargement"
            scenes_snapshot = dict(context.state.get("scenes", {}))
            requested_name = scenes_snapshot.get(scene_index)

        if requested_name is None:
            return False, "Scène absente du Live Set courant"

        confirmed = False
        confirmation_wait_started = time.monotonic()
        last_confirmation = None

        with context.ableton_transport.serialized_queries(priority=True):
            # Metadata queries may occupy this lock after NEXT/PREV. Their wait
            # must not consume the budget before GO can even query Live.
            confirmation_lock_wait_ms = round((time.monotonic() - confirmation_wait_started) * 1000, 2)
            confirmation_deadline = time.monotonic() + 0.8
            while time.monotonic() < confirmation_deadline:
                if not context.generation_is_current(expected_generation):
                    return False, "Live Set modifié pendant le GO"
                with context.lock:
                    if not context.state.get("set_ready", False):
                        return False, "Live Set en cours de chargement"

                context.send("/live/view/set/selected_scene", scene_index)
                response = context._query_with_query_lock_held(
                    "/live/view/get/selected_scene",
                    expected_generation=expected_generation,
                    apply_response=False,
                )
                last_confirmation = response
                if response:
                    try:
                        confirmed = int(response[0]) == scene_index
                    except (TypeError, ValueError, IndexError):
                        confirmed = False
                if confirmed:
                    break

            if not confirmed:
                context.write_keyboard_diagnostic({
                    "event": "go-selection-confirmation-failed",
                    "requestId": request_id,
                    "requestedSceneIndex": scene_index,
                    "lastConfirmation": last_confirmation,
                    "queryLockWaitMs": confirmation_lock_wait_ms,
                })
                return False, "Sélection de scène non confirmée par Ableton"
            if not context.generation_is_current(expected_generation):
                return False, "Live Set modifié pendant le GO"

            event = GoLaunch(request_id, expected_generation, scene_index,
                             requested_name,
                             scene_index + 1 if scene_index + 1 in scenes_snapshot else scene_index,
                             time.time())
            consumer.before_launch(event)
            context.send("/live/scene/fire_as_selected", scene_index)
            context.write_keyboard_diagnostic({
                "event": "go-scene-command-sent",
                "requestId": request_id,
                "requestedSceneIndex": scene_index,
                "queryLockWaitMs": confirmation_lock_wait_ms,
                "confirmationElapsedMs": round((time.monotonic() - confirmation_wait_started) * 1000, 2),
            })

            consumer.after_send(event)

        with context.lock:
            if (
                int(context.state.get("set_generation", 0)) != int(expected_generation)
                or not context.state.get("set_ready", False)
            ):
                return False, "Live Set modifié pendant le GO"

            context.state["last_fired_scene"] = scene_index
            context.state["last_fired_scene_name"] = requested_name
            context.state["playing_scene"] = scene_index
            context.state["playing_scene_name"] = requested_name
            context.state["current_scene"] = scene_index
            context.state["has_show_started"] = True
            context.state["play_mode"] = "session"
            context.state["is_playing"] = True
            context.state["is_paused"] = False
            context.state["selected_scene"] = event.next_scene
            context.state["next_scene"] = event.next_scene
            context.state["selected_scene_name"] = scenes_snapshot.get(event.next_scene, requested_name)
            context.state["message"] = f"Scène {scene_index + 1} lancée"
            consumer.update_state_locked(event)
            context.completed_go_requests[request_key] = {
                "ok": True,
                "message": context.state["message"],
            }

        consumer.after_commit(event)

        return True, f"Scène {scene_index + 1} lancée"
