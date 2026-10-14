import json
import wave

import pytest

from show_audio_ableton_offline import (
    OFFLINE_FAILED,
    OFFLINE_SUCCESS,
    OFFLINE_UNAVAILABLE,
    OfflineExportError,
    beats_to_bbt,
    beats_to_length_bbt,
    build_ableton_export_script,
    build_arrangement_zones,
    execute_offline_wav,
    validate_wav_file,
    wav_export_parameters,
)


MARKERS = [
    {"name": "40 - GIGI", "time": 400.0},
    {"name": "41 - NEVER", "time": 420.0},
    {"name": "42 - LOVE", "time": 440.0},
    {"name": "43 - DANCING QUEEN", "time": 460.0},
    {"name": "44 - NEXT", "time": 490.0},
]


def job_item(item_type="scene", **source):
    return {"items": [{"id": "x", "type": item_type, "source_item": source}]}


def settings():
    return {
        "sample_rate": 48000,
        "normalize": False,
        "formats": [{"format": "wav", "bit_depth": 24}],
    }


def write_wav(path, seconds=1.0, rate=48000):
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(b"\0\0\0\0" * int(seconds * rate))


def test_scene_resolves_to_next_arrangement_locator():
    zones = build_arrangement_zones(
        job_item(scene_number=41, title="NEVER", duration_seconds=10.0), MARKERS
    )
    assert zones[0]["type"] == "scene"
    assert zones[0]["start_beats"] == 420.0
    assert zones[0]["end_beats"] == 440.0


def test_medley_is_one_arrangement_zone():
    zones = build_arrangement_zones(
        job_item(
            "medley_full", scene_numbers=[40, 41, 42, 43],
            title="GIGI / NEVER / LOVE / DANCING QUEEN",
            duration_seconds=45.0,
        ),
        MARKERS,
    )
    assert len(zones) == 1
    assert zones[0]["type"] == "medley"
    assert zones[0]["scene_numbers"] == [40, 41, 42, 43]
    assert zones[0]["start_beats"] == 400.0
    assert zones[0]["end_beats"] == 490.0


def test_missing_end_locator_is_rejected():
    with pytest.raises(OfflineExportError, match="locator de fin"):
        build_arrangement_zones(job_item(scene_number=44), MARKERS)


def test_position_and_length_bbt_are_distinct():
    assert beats_to_bbt(0) == (1, 1, 1)
    assert beats_to_bbt(6.5) == (2, 3, 3)
    assert beats_to_length_bbt(6.5) == (1, 2, 2)


def test_wav_mapping_and_ax_script(tmp_path):
    assert wav_export_parameters(settings()) == {
        "sample_rate": 48000, "bit_depth": 24, "normalize": False,
    }
    script = build_ableton_export_script(
        start_bbt=(2, 1, 1), length_bbt=(8, 0, 0),
        output_path=tmp_path / "test.wav", sample_rate=48000,
        bit_depth=24, normalize=False,
    )
    for identifier in (
        "Base.RenderStartBox.RenderStart.Bars",
        "Base.RenderLengthBox.RenderLength.Bars",
        "Base.SampleRateBox.SampleRate",
        "Base.FileTypeBox.FileType",
    ):
        assert identifier in script

    assert '"filename": "test.wav"' in script

    assert 'choose("Base.RenderedTrack", "Main")' in script
    assert 'state: "export_configured", pid: live.unixId()' in script
    assert 'ExportButton", 10).click()' not in script
    assert "saveAsNameTextField" not in script
    assert "se.keyCode(48)" not in script
    bbt = script[script.index("function performAXAction"):script.index("function setToggle")]
    assert "se.keystroke" not in bbt
    numeric = bbt[bbt.index("function setAXNumericByActions"):]
    assert "se.keyCode" not in numeric
    assert bbt.count("se.keyCode(53)") == 1
    for collection in ("children", "windows", "actions", "items"):
        assert f"of {collection})" not in script
    assert "AXIncrement" in bbt
    assert "AXDecrement" in bbt


def test_native_save_contract():
    from show_audio_ableton_offline import _NATIVE_SAVE_AX_SWIFT as native
    assert '"saveAsNameTextField"' in native
    assert '"Base.FinalButtonsBox.ExportButton"' in native
    assert '"OKButton"' in native
    assert "kAXPressAction" in native
    assert "kAXEnabledAttribute" in native
    assert "AXUIElementSetAttributeValue" in native
    assert "NSRunningApplication(processIdentifier: pid)" in native
    assert 'LIVE_PROCESS_TERMINATED' in native
    assert "actual == expected || actual == noExtension" in native
    assert 'guard let current = windows()' in native
    assert 'timing("save_panel:closed")' in native
    assert 'PREEXISTING_SAVE_PANEL' in native
    assert beats_to_bbt(19390.220703125) == (4848, 3, 2)
    assert beats_to_length_bbt(64) == (16, 0, 0)


@pytest.mark.parametrize("failure", [None, "compile", "jxa", "native", "handshake"])
def test_native_process_lifecycle(monkeypatch, tmp_path, failure):
    import subprocess
    import show_audio_ableton_offline as offline
    calls = []

    def run(command, **kwargs):
        phase = ("compile", "jxa", "native")[len(calls)]
        calls.append(command)
        assert kwargs["timeout"] > 0
        assert kwargs["check"]
        if phase == failure:
            raise subprocess.CalledProcessError(1, command, output="STATE=failed", stderr="AX evidence")
        output = json.dumps({"state": "export_configured", "pid": 123}) if phase == "jxa" else "NATIVE_SAVE_OK"
        if phase == "jxa" and failure == "handshake":
            output = "unexpected"
        return subprocess.CompletedProcess(command, 0, stdout=output, stderr="")

    monkeypatch.setattr(offline.subprocess, "run", run)
    script = build_ableton_export_script(
        start_bbt=(4848, 3, 2), length_bbt=(16, 0, 0),
        output_path=tmp_path / "annonce.wav", sample_rate=48000,
        bit_depth=24, normalize=False,
    )
    if failure:
        with pytest.raises(OfflineExportError) as error:
            offline.run_macos_automation(script)
        if failure != "handshake":
            assert "AX evidence" in str(error.value)
        assert len(calls) == {"compile": 1, "jxa": 2, "native": 3, "handshake": 2}[failure]
    else:
        assert offline.run_macos_automation(script) == "NATIVE_SAVE_OK"
        assert len(calls) == 3
        assert calls[0][0] == "/usr/bin/swiftc"
        assert calls[1][0] == "/usr/bin/osascript"
        assert calls[2][1:] == ["annonce.wav", "123"]
    assert not __import__("pathlib").Path(calls[0][-1]).parent.exists()


def test_validate_wav_file(tmp_path):
    target = tmp_path / "valid.wav"
    write_wav(target, seconds=1.0)
    result = validate_wav_file(
        target, expected_duration=1.0, expected_sample_rate=48000
    )
    assert result["channels"] == 2
    assert result["duration_seconds"] == 1.0


def test_execute_success_and_failure_states(tmp_path, monkeypatch):
    import show_audio_ableton_offline as offline
    def forbidden(*args, **kwargs):
        pytest.fail("Une automation injectée ne doit lancer aucun processus")
    monkeypatch.setattr(offline.subprocess, "run", forbidden)
    target = tmp_path / "render.wav"

    def requested_filename(command):
        import json
        import re

        match = re.search(r"const spec = (\{.*?\});", command)
        assert match is not None
        return json.loads(match.group(1))["filename"]

    def success(command):
        assert "Base.RenderedTrack" in command
        render_name = requested_filename(command)
        assert render_name.startswith("render.__clrender_")
        write_wav(tmp_path / render_name, seconds=1.0)

    zone = {
        "start_beats": 4.0, "duration_beats": 2.0,
        "expected_duration_seconds": 1.0,
    }
    result = execute_offline_wav(
        zone=zone, settings=settings(), output_path=target,
        tempo=120, automation=success,
    )
    assert result["status"] == OFFLINE_SUCCESS
    assert target.is_file()
    assert result["file"]["path"] == str(target.resolve())

    # osascript peut signaler une erreur alors qu'Ableton a déjà
    # lancé et terminé correctement le rendu.
    import subprocess

    recovered_target = tmp_path / "recovered.wav"

    def render_then_jxa_error(command):
        render_name = requested_filename(command)
        write_wav(tmp_path / render_name, seconds=1.0)
        raise subprocess.CalledProcessError(
            returncode=1,
            cmd=["osascript"],
        )

    recovered = execute_offline_wav(
        zone=zone,
        settings=settings(),
        output_path=recovered_target,
        tempo=120,
        automation=render_then_jxa_error,
        timeout=5.0,
    )

    assert recovered["status"] == OFFLINE_SUCCESS
    assert recovered_target.is_file()

    unavailable = execute_offline_wav(
        zone=zone, settings=settings(), output_path=tmp_path / "none.wav",
        tempo=120, automation=lambda _: (_ for _ in ()).throw(FileNotFoundError()),
    )
    assert unavailable["status"] == OFFLINE_UNAVAILABLE
    assert unavailable["fallback"] == "realtime"

    invalid = tmp_path / "invalid.wav"

    def invalid_render(command):
        render_name = requested_filename(command)
        (tmp_path / render_name).write_bytes(b"bad")

    failed = execute_offline_wav(
        zone=zone, settings=settings(), output_path=invalid,
        tempo=120, automation=invalid_render, timeout=0.30,
    )
    assert failed["status"] == OFFLINE_FAILED


def run_ax_simulation(tmp_path, body):
    """Execute the generated JS functions, without System Events or Live."""
    import shutil
    import subprocess

    node = shutil.which("node")
    assert node, "Node is required for the generated JXA behavioral tests"
    script = build_ableton_export_script(
        start_bbt=(4848, 3, 2), length_bbt=(16, 0, 0),
        output_path=tmp_path / "annonce.wav", sample_rate=48000,
        bit_depth=24, normalize=False,
    )
    helpers = script[script.index("function isAXInvalidation"):script.index("// Live peut parfois")]
    result = subprocess.run(
        [node, "-e", 'const assert = require("assert");\n' + helpers + body],
        capture_output=True, text=True, timeout=10,
    )
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize("scenario", [
    "increment", "decrement", "before_read", "before_action", "during_before_effect",
    "during_after_effect", "control_after_action", "never_returns", "prior_changed",
    "prior_preserved", "unknown_error", "no_effect",
])
def test_transactional_bbt_behavior(tmp_path, scenario):
    run_ax_simulation(tmp_path, 'const scenario = ' + json.dumps(scenario) + r''';
const id = bbtIdentifiers[0];
const prior = bbtIdentifiers[3];
let value = scenario === "decrement" ? 8 : 3;
let available = true, fired = false, actions = 0, opens = 0, reads = 0;
let mustRead = false;
function invalid() { const e = new Error("Index non valide"); e.number = -1719; return e; }
function missing() { const e = new Error("Controle AX absent"); e.missingAXIdentifier = id; return e; }
if (scenario.startsWith("prior_")) completedBBT[prior] = 16;
numericAXValue = function(identifier) {
  reads++;
  if (identifier === prior) return scenario === "prior_changed" ? 15 : 16;
  if (scenario === "before_read" && !fired) {
    fired = true; available = false; throw invalid();
  }
  if (!available) throw missing();
  mustRead = false;
  return value;
};
performAXAction = function(identifier, action) {
  assert.strictEqual(mustRead, false, "blind replay after uncertain action");
  actions++;
  if (scenario === "unknown_error") throw new Error("permission denied");
  if (scenario === "no_effect") return;
  const fault = !fired && !["increment", "decrement", "before_read"].includes(scenario);
  if (fault) {
    fired = true; available = false; mustRead = true;
    if (["before_action", "during_before_effect", "never_returns", "prior_changed", "prior_preserved"].includes(scenario)) throw invalid();
  }
  value += action === "AXIncrement" ? 1 : -1;
  if (fault && scenario === "during_after_effect") throw invalid();
};
exportDialogControlsReady = () => available;
exportDialogIsOpen = () => false;
openExportDialog = () => { opens++; available = scenario !== "never_returns"; };
waitExportDialogReady = () => available;
if (["never_returns", "prior_changed", "unknown_error", "no_effect"].includes(scenario)) {
  const expected = {never_returns:/Limite recuperations/, prior_changed:/deja configure/, unknown_error:/permission denied/, no_effect:/sans effet/};
  assert.throws(() => setAXNumericByActions(id, 6), expected[scenario]);
  if (scenario === "never_returns") assert.strictEqual(opens, 3);
  if (["unknown_error", "no_effect"].includes(scenario)) assert.strictEqual(opens, 0);
} else {
  setAXNumericByActions(id, 6);
  assert.strictEqual(value, 6);
  assert.strictEqual(completedBBT[id], 6);
  assert.strictEqual(actions, scenario === "decrement" ? 2 :
    ["before_action", "during_before_effect", "prior_preserved"].includes(scenario) ? 4 : 3);
  assert.strictEqual(opens, ["increment", "decrement"].includes(scenario) ? 0 : 1);
  assert.ok(reads > actions);
}
''')


def test_ax_error_classification_and_dynamic_collections(tmp_path):
    run_ax_simulation(tmp_path, r'''
const stale = () => { const e = new Error("stale"); e.number = -1728; return e; };
const dynamic = new Proxy({length:2, 1:{
  attributes:{byName:() => ({value:() => "wanted"})}, uiElements:() => []
}}, {get:(obj,key) => { if (key === "0") throw stale(); return obj[key]; }});
assert.ok(findAX({uiElements:() => dynamic}, "wanted"));
assert.throws(() => findAX({uiElements:() => {throw new Error("denied");}}, "x"), /denied/);
assert.ok(isTransientBBTError(stale()));
assert.ok(isTransientBBTError(new Error("Il est impossible d’obtenir l’objet")));
assert.ok(isTransientBBTError(new Error("Index non valide")));
assert.ok(!isTransientBBTError(new Error("Cible BBT invalide: " + bbtIdentifiers[0])));
assert.ok(!isTransientBBTError({missingAXIdentifier:"unknown"}));
assert.throws(() => setAXNumericByActions("unknown", 2), /inconnu/);
assert.throws(() => setAXNumericByActions(bbtIdentifiers[0], NaN), /Cible BBT invalide/);
let performed = 0;
waitAX = () => ({actions:() => new Proxy({length:2, 1:{name:()=>"AXIncrement", perform:()=>performed++}},
 {get:(obj,key)=>{if(key==="0")throw stale();return obj[key];}})});
performAXAction(bbtIdentifiers[0], "AXIncrement");
assert.strictEqual(performed, 1);
waitAX = () => ({attributes:{byName:()=>({value:()=>null})}});
assert.throws(() => numericAXValue(bbtIdentifiers[0]), /illisible/);
''')


def test_bbt_actions_use_dynamic_bounded_budget(tmp_path):
    run_ax_simulation(tmp_path, r"""
const id = bbtIdentifiers[3];
let value = 0;
let actions = 0;

numericAXValue = () => value;

performAXAction = (_id, action) => {
  actions++;
  value += action === "AXIncrement" ? 1 : -1;
};

exportDialogControlsReady = () => true;
exportDialogIsOpen = () => true;
waitExportDialogReady = () => true;

function reset(start) {
  value = start;
  actions = 0;
  delete completedBBT[id];
}

for (const [start, target, expectedActions] of [
  [0, 256, 256],
  [0, 257, 257],
  [0, 1000, 1000],
  [1000, 238, 762],
  [42, 42, 0],
  [0, 8, 8],
  [8, 0, 8]
]) {
  reset(start);

  setAXNumericByActions(id, target);

  assert.strictEqual(value, target);
  assert.strictEqual(actions, expectedActions);
  assert.strictEqual(completedBBT[id], target);
}

reset(0);
performAXAction = () => {
  actions++;
};
assert.throws(
  () => setAXNumericByActions(id, 2),
  /reason=no_effect.*sans effet/
);

reset(0);
performAXAction = () => {
  actions++;
  value += 2;
};
assert.throws(
  () => setAXNumericByActions(id, 1),
  /reason=overshoot/
);

reset(0);
let flip = false;
performAXAction = () => {
  actions++;
  flip = !flip;
  value = flip ? 1 : 0;
};
assert.throws(
  () => setAXNumericByActions(id, 3),
  /reason=oscillation/
);

reset(0);
performAXAction = (_id, action) => {
  actions++;
  value += action === "AXIncrement" ? 1 : -1;
};
assert.throws(
  () => setAXNumericByActions(id, 10001),
  /reason=budget_exhausted/
);
assert.strictEqual(actions, 0);
""")


def test_export_start_is_set_and_verified_by_ax(tmp_path):
    script = build_ableton_export_script(
        start_bbt=(4848, 3, 2),
        length_bbt=(16, 0, 0),
        output_path=tmp_path / "annonce.wav",
        sample_rate=48000,
        bit_depth=24,
        normalize=False,
    )

    block = script[
        script.index("function configureExportBBT"):
        script.index('choose("Base.RenderedTrack"')
    ]

    assert "configure_bbt:done_start" in block

    assert (
        'assertBBT(\n'
        '    "Base.RenderStartBox.RenderStart",'
        in block
    )

    assert (
        'setBBT(\n'
        '    "Base.RenderStartBox.RenderStart",'
        in block
    )

    assert (
        'setBBT(\n'
        '    "Base.RenderLengthBox.RenderLength",'
        in block
    )


def test_bbt_to_live_loop_values_are_normalized():
    import show_audio_ableton_offline as offline

    assert (
        offline._bbt_start_to_live_beats((4848, 3, 2))
        == 19390.25
    )
    assert (
        offline._bbt_length_to_live_beats((16, 0, 0))
        == 64.0
    )


def test_default_automation_receives_render_timeout(monkeypatch, tmp_path):
    import show_audio_ableton_offline as offline

    calls = []
    prepared = []
    restored = []

    previous = {
        "loop_start": 21120.0,
        "loop_length": 3.0,
        "loop": False,
    }

    def prepare(*, start_bbt, length_bbt):
        prepared.append((start_bbt, length_bbt))
        return previous

    def restore(state):
        restored.append(state)

    def native_bbt():
        assert prepared
        return (4133, 1, 1)

    monkeypatch.setattr(offline, "_get_live_loop_start_bbt", native_bbt)

    def blocked(script, *, timeout):
        spec = json.loads(script.split("const spec = ", 1)[1].split(";", 1)[0])
        assert spec["start"] == [4133, 1, 1]
        assert spec["length"] == [16, 0, 0]
        calls.append(timeout)
        raise OfflineExportError(
            "configure_export_jxa: délai dépassé"
        )

    monkeypatch.setattr(
        offline,
        "_prepare_live_export_loop",
        prepare,
    )
    monkeypatch.setattr(
        offline,
        "_restore_live_loop_state",
        restore,
    )
    monkeypatch.setattr(
        offline,
        "run_macos_automation",
        blocked,
    )

    result = offline.execute_offline_wav(
        zone={
            "start_beats": 19390.220703125,
            "duration_beats": 64,
            "expected_duration_seconds": 32,
        },
        settings=settings(),
        output_path=tmp_path / "annonce.wav",
        tempo=120,
        timeout=7,
    )

    assert prepared == [
        ((4848, 3, 2), (16, 0, 0))
    ]
    assert calls == [7]
    assert restored == [previous]
    assert result["status"] != OFFLINE_SUCCESS


def test_native_deadline_shared_and_error_is_concise(monkeypatch, tmp_path):
    import subprocess
    import show_audio_ableton_offline as offline
    clock = [0.0]
    timeouts = []
    monkeypatch.setattr(offline.time, 'monotonic', lambda: clock[0])

    def run(command, **kwargs):
        timeouts.append(kwargs['timeout'])
        if len(timeouts) == 1:
            clock[0] = 4
            return subprocess.CompletedProcess(command, 0, stdout='', stderr='')
        raise subprocess.TimeoutExpired(command, kwargs['timeout'], stderr=b'AX: Base.RenderedTrack')

    monkeypatch.setattr(offline.subprocess, 'run', run)
    script = build_ableton_export_script(start_bbt=(4848, 3, 2), length_bbt=(16, 0, 0),
        output_path=tmp_path / 'annonce.wav', sample_rate=48000, bit_depth=24, normalize=False)
    with pytest.raises(OfflineExportError) as caught:
        offline.run_macos_automation(script, timeout=10)
    assert timeouts == [10, 6]
    assert 'configure_export_jxa' in str(caught.value)
    assert 'Base.RenderedTrack' in str(caught.value)
    assert len(str(caught.value)) < 200


def test_ax_lookup_is_scoped_to_export_dialog(tmp_path):
    script = build_ableton_export_script(start_bbt=(4848, 3, 2), length_bbt=(16, 0, 0),
        output_path=tmp_path / 'annonce.wav', sample_rate=48000, bit_depth=24, normalize=False)
    lookup = script[script.index('function waitAX'):script.index('function performAXAction')]
    assert 'findAX(dialog, identifier)' in lookup
    assert 'live.windows()' not in lookup


@pytest.mark.parametrize("failed", [False, True])
def test_automation_timings_relay_success_and_timeout(monkeypatch, tmp_path, capsys, failed):
    import subprocess
    import show_audio_ableton_offline as offline

    calls = []
    def run(command, **kwargs):
        calls.append(command)
        if len(calls) == 1:
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")
        trace = "[OFFLINE_TIMING] JXA +1.250s export_dialog:ready\n"
        if failed:
            raise subprocess.TimeoutExpired(command, kwargs["timeout"], stderr=trace.encode())
        if len(calls) == 2:
            return subprocess.CompletedProcess(command, 0, stdout=json.dumps({
                "state": "export_configured", "pid": 123,
            }), stderr=trace + "unrelated output\n")
        return subprocess.CompletedProcess(command, 0, stdout="NATIVE_SAVE_OK", stderr=(
            "[OFFLINE_TIMING] NATIVE +0.500s save_panel:closed\n"))

    monkeypatch.setattr(offline.subprocess, "run", run)
    script = build_ableton_export_script(
        start_bbt=(2, 1, 1), length_bbt=(8, 0, 0), output_path=tmp_path / "a.wav",
        sample_rate=48000, bit_depth=24, normalize=False,
    )
    if failed:
        with pytest.raises(OfflineExportError, match="configure_export_jxa"):
            offline.run_macos_automation(script)
    else:
        assert offline.run_macos_automation(script) == "NATIVE_SAVE_OK"
    output = capsys.readouterr().out
    assert "compile_native:start" in output
    assert "compile_native:done" in output
    assert "JXA +1.250s export_dialog:ready" in output
    assert "unrelated output" not in output
    assert ("configure_export_jxa:failed" if failed else "processes:complete") in output
    if not failed:
        assert "NATIVE +0.500s save_panel:closed" in output


def test_swift_modules_survive_between_automations(monkeypatch, tmp_path):
    import subprocess
    from pathlib import Path
    import show_audio_ableton_offline as offline
    commands = []
    monkeypatch.setattr(offline.tempfile, "gettempdir", lambda: str(tmp_path))

    def run(command, **kwargs):
        commands.append(command)
        output = json.dumps({"state": "export_configured", "pid": 123}) if command[0] == "/usr/bin/osascript" else "NATIVE_SAVE_OK"
        return subprocess.CompletedProcess(command, 0, stdout=output, stderr="")

    monkeypatch.setattr(offline.subprocess, "run", run)
    script = build_ableton_export_script(
        start_bbt=(2, 1, 1), length_bbt=(8, 0, 0), output_path=tmp_path / "a.wav",
        sample_rate=48000, bit_depth=24, normalize=False,
    )
    offline.run_macos_automation(script)
    modules = Path(commands[0][2])
    marker = modules / "cached-module"
    marker.write_text("retained")
    offline.run_macos_automation(script)
    assert commands[0][2] == commands[3][2]
    assert marker.read_text() == "retained"
    assert commands[0][-1] != commands[3][-1]
    assert not Path(commands[0][-1]).parent.exists()
    assert not Path(commands[3][-1]).parent.exists()


@pytest.mark.parametrize("initial_open, closes", [(True, True), (False, True), (True, False)])
def test_export_dialog_refresh_before_bbt(tmp_path, initial_open, closes):
    import shutil
    import subprocess
    script = build_ableton_export_script(
        start_bbt=(6469, 1, 2), length_bbt=(238, 0, 1),
        output_path=tmp_path / "medley.wav", sample_rate=48000,
        bit_depth=24, normalize=False,
    )
    lifecycle = script[script.index('timing("export_dialog:wait_start")'):
                       script.index('function assertBBT')]
    opener = script[script.index("function openExportDialog()"):script.index("// Live peut parfois")]
    # Exécuter ouverture et cycle réels ; aucun rendu ni appel à Live.
    harness = f"""
const assert = require('assert');
const events = [];
const live = {{frontmost: false}};
const se = {{
  keyCode: code => {{assert.equal(code, 53); events.push('close');}},
  keystroke: (key, options) => {{
    assert(live.frontmost);
    assert.deepEqual(options.using, ['command down', 'shift down']);
    assert(['l', 'r'].includes(key));
    events.push(key === 'l' ? 'select_loop' : 'open');
  }}
}};
function timing(_) {{}}
function delay(_) {{}}
function exportDialogIsOpen() {{return {str(initial_open).lower()};}}
function waitExportDialogClosed(seconds) {{
  assert.equal(seconds, 3); events.push('closed_check'); return {str(closes).lower()};
}}
{opener}
function waitExportDialogReady(_) {{events.push('ready'); return true;}}
let error = null;
try {{ {lifecycle} }} catch (e) {{error = e;}}
"""
    if initial_open and not closes:
        harness += "assert(error); assert.match(error.message, /precedent impossible/); assert.deepEqual(events, ['close', 'closed_check']);"
    else:
        expected = ["close", "closed_check", "select_loop", "open", "ready"] if initial_open else ["select_loop", "open", "ready"]
        harness += f"assert.equal(error, null); assert.deepEqual(events, {json.dumps(expected)});"
    node = shutil.which("node")
    assert node
    result = subprocess.run([node, "-e", harness], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize("outcome", ["success", "invalid_wav", "missing_wav", "restore_failure"])
def test_restore_after_render_validation(monkeypatch, tmp_path, outcome):
    import re
    import show_audio_ableton_offline as offline

    events = []
    clock = [0.0]
    render = []
    previous = {"loop_start": 33392.0, "loop_length": 1.0, "loop": False}
    class TransactionLock:
        held = False
        def __enter__(self):
            self.held = True
        def __exit__(self, *args):
            self.held = False
    lock = TransactionLock()
    monkeypatch.setattr(offline, "_LIVE_EXPORT_LOCK", lock)
    monkeypatch.setattr(offline.time, "monotonic", lambda: clock[0])
    monkeypatch.setattr(offline, "_prepare_live_export_loop", lambda **kw: previous)
    monkeypatch.setattr(offline, "_get_live_loop_start_bbt", lambda: (2, 1, 1))

    def launch(script, **kw):
        assert lock.held
        spec = json.loads(re.search(r"const spec = (\{.*?\});", script).group(1))
        render.append(tmp_path / spec["filename"])
        events.append("save_closed")

    def sleep(seconds):
        clock[0] += seconds
        assert lock.held
        assert "restore" not in events
        if clock[0] >= 0.5 and outcome != "missing_wav" and not render[0].exists():
            write_wav(render[0], seconds=2 if outcome == "invalid_wav" else 1)
            events.append("render_complete")

    validate = offline.validate_wav_file
    def validation(*args, **kwargs):
        if "restore" not in events:
            assert lock.held
            events.append("validate")
        return validate(*args, **kwargs)

    def restore(state):
        assert state == previous and lock.held
        if outcome != "missing_wav":
            assert events.index("render_complete") < events.index("validate")
        events.append("restore")
        if outcome == "restore_failure":
            raise OfflineExportError("restauration non confirmée")

    monkeypatch.setattr(offline, "run_macos_automation", launch)
    monkeypatch.setattr(offline.time, "sleep", sleep)
    monkeypatch.setattr(offline, "validate_wav_file", validation)
    monkeypatch.setattr(offline, "_restore_live_loop_state", restore)
    target = tmp_path / "final.wav"
    result = offline.execute_offline_wav(
        zone={"type": "medley", "start_beats": 4, "duration_beats": 2,
              "expected_duration_seconds": 1},
        settings=settings(), output_path=target, tempo=120, timeout=5,
    )
    assert events.count("restore") == 1
    assert not lock.held
    assert result["status"] == (OFFLINE_SUCCESS if outcome == "success" else OFFLINE_FAILED)
    assert target.exists() is (outcome == "success")


@pytest.mark.parametrize("destination", ["desktop", "parent", "direct"])
def test_render_outside_expected_directory_is_published_without_timeout(monkeypatch, tmp_path, destination):
    import re
    from pathlib import Path
    import show_audio_ableton_offline as offline

    home = tmp_path / "home"
    desktop = home / "Desktop"
    desktop.mkdir(parents=True)
    monkeypatch.setattr(Path, "home", classmethod(lambda cls: home))
    target = tmp_path / "exports" / ".cl_show_audio_masters" / "ANNONCE.wav"
    clock = [0.0]
    monkeypatch.setattr(offline.time, "monotonic", lambda: clock[0])
    monkeypatch.setattr(offline.time, "sleep", lambda seconds: clock.__setitem__(0, clock[0] + seconds))
    # Un ancien WAV portant le nom final ne doit jamais être sélectionné.
    stale = desktop / target.name
    stale.write_bytes(b"ancien rendu")
    produced = []

    def render(command):
        spec = json.loads(re.search(r"const spec = (\{.*?\});", command).group(1))
        directory = {"desktop": desktop, "parent": target.parent.parent,
                     "direct": target.parent}[destination]
        produced.append(directory / spec["filename"])
        write_wav(produced[0], seconds=1)

    result = offline.execute_offline_wav(
        zone={"start_beats": 4, "duration_beats": 2, "expected_duration_seconds": 1},
        settings=settings(), output_path=target, tempo=120, automation=render, timeout=300,
    )
    assert result["status"] == OFFLINE_SUCCESS
    assert result["render_source"] == str(produced[0])
    assert result["file"]["path"] == str(target)
    assert 1.5 <= clock[0] < 3
    assert target.is_file() and not produced[0].exists()
    assert stale.read_bytes() == b"ancien rendu"
    assert list(target.parent.iterdir()) == [target]
    assert offline.validate_wav_file(target, expected_duration=1, expected_sample_rate=48000)


def test_ambiguous_render_fails_immediately_without_replacing_master(monkeypatch, tmp_path):
    import re
    from pathlib import Path
    import show_audio_ableton_offline as offline

    desktop = tmp_path / "Desktop"
    desktop.mkdir()
    monkeypatch.setattr(Path, "home", classmethod(lambda cls: tmp_path))
    target = tmp_path / "exports" / "ANNONCE.wav"
    target.parent.mkdir()
    target.write_bytes(b"master precedent")
    monkeypatch.setattr(offline.time, "sleep", lambda seconds: pytest.fail("ambiguite doit echouer immediatement"))

    def render(command):
        spec = json.loads(re.search(r"const spec = (\{.*?\});", command).group(1))
        for directory in (desktop, target.parent):
            write_wav(directory / spec["filename"])

    result = offline.execute_offline_wav(
        zone={"start_beats": 4, "duration_beats": 2}, settings=settings(),
        output_path=target, tempo=120, automation=render,
    )
    assert result["status"] == offline.OFFLINE_FAILED
    assert "ambigu" in result["error"]
    assert target.read_bytes() == b"master precedent"


@pytest.mark.parametrize("value,expected", [
    ("4133.01.01.053", (4133, 1, 1)),
    ("42.07.04.000", (42, 7, 4)),
    ("1.1.1", (1, 1, 1)),
])
def test_native_bbt_parser(value, expected):
    import show_audio_ableton_offline as offline
    assert offline._parse_native_loop_start_bbt(value) == expected


@pytest.mark.parametrize("value", [None, "", "1.2", "0.1.1.000", "1.0.1.000", "1.1.5.000", "1.1.1.bad"])
def test_native_bbt_parser_rejects_invalid(value):
    import show_audio_ableton_offline as offline
    with pytest.raises(OfflineExportError):
        offline._parse_native_loop_start_bbt(value)


@pytest.mark.parametrize("outcome", ["ok", "error", "stale", "busy", "invalid"])
def test_native_bbt_bridge_correlates_response(monkeypatch, tmp_path, outcome):
    import show_audio_ableton_offline as offline
    monkeypatch.setattr(offline.Path, "home", lambda: tmp_path)
    bridge = tmp_path / "Documents/CL_Arrangement_Builder_Bridge"
    bridge.mkdir(parents=True)
    command = bridge / "command.json"
    status = bridge / "status.json"
    status.write_text(json.dumps({"loop_start_bbt_result": {
        "request_id": "old", "status": "ok", "bbt": "1.1.1.000",
    }}))
    if outcome == "busy":
        command.write_text('{"command":"other"}')
    clock = [0.0]
    monkeypatch.setattr(offline.time, "monotonic", lambda: clock[0])
    def sleep(seconds):
        clock[0] += seconds
        if command.exists() and outcome not in ("busy", "stale"):
            request = json.loads(command.read_text())
            assert request["command"] == "get_loop_start_bbt"
            status.write_text(json.dumps({"loop_start_bbt_result": {
                "request_id": request["request_id"],
                "status": "error" if outcome == "error" else "ok",
                "error": "getter unavailable",
                "bbt": "bad" if outcome == "invalid" else "4133.01.01.053",
                "loop_start_beats": 16528.21875,
            }}))
            command.unlink()
    monkeypatch.setattr(offline.time, "sleep", sleep)
    if outcome == "ok":
        assert offline._get_live_loop_start_bbt(timeout=0.2) == (4133, 1, 1)
    else:
        with pytest.raises(OfflineExportError):
            offline._get_live_loop_start_bbt(timeout=0.2)
    assert not list(bridge.glob("*.tmp"))
    if outcome == "busy":
        assert json.loads(command.read_text()) == {"command": "other"}


def test_native_bbt_failure_restores_loop_without_opening_export(monkeypatch, tmp_path):
    import show_audio_ableton_offline as offline
    previous = {"loop_start": 10, "loop_length": 4, "loop": False}
    restored = []
    monkeypatch.setattr(offline, "_prepare_live_export_loop", lambda **kw: previous)
    def fail():
        raise OfflineExportError("BBT natif indisponible")
    monkeypatch.setattr(offline, "_get_live_loop_start_bbt", fail)
    monkeypatch.setattr(offline, "_restore_live_loop_state", restored.append)
    monkeypatch.setattr(offline, "run_macos_automation", lambda *a, **kw: pytest.fail("export lancé"))
    result = offline.execute_offline_wav(
        zone={"start_beats": 4, "duration_beats": 2}, settings=settings(),
        output_path=tmp_path / "final.wav", tempo=120,
    )
    assert result["status"] == OFFLINE_FAILED
    assert restored == [previous]


@pytest.mark.parametrize("mismatch", [False, True])
def test_render_start_is_verified_before_length(tmp_path, mismatch):
    import shutil
    import subprocess
    script = build_ableton_export_script(
        start_bbt=(4133, 1, 1), length_bbt=(16, 0, 0),
        output_path=tmp_path / "test.wav", sample_rate=48000,
        bit_depth=24, normalize=False,
    )
    helpers = script[script.index("function assertBBT"):script.index('timing("configure_bbt:start");')]
    harness = r"""
const assert = require('assert');
const spec = {start:[4133,1,1], length:[16,0,0]};
const events = [];
function timing() {}
function setBBT(prefix, values) { events.push([prefix, values]); }
function numericAXValue(id) {
  assert.strictEqual(events.length, 1);
  assert.ok(id.startsWith('Base.RenderStartBox.RenderStart.'));
  if (mismatch) return 999;
  return spec.start[['Bars','Beats','Subdivisions'].indexOf(id.split('.').pop())];
}
if (mismatch) {
  assert.throws(configureExportBBT, /START BBT inattendu/);
  assert.strictEqual(events.length, 1);
} else {
  configureExportBBT();
  assert.deepStrictEqual(events, [
    ['Base.RenderStartBox.RenderStart', spec.start],
    ['Base.RenderLengthBox.RenderLength', spec.length],
  ]);
}
"""
    result = subprocess.run(
        [shutil.which("node"), "-e", "const mismatch = " + json.dumps(mismatch) + ";" + helpers + harness],
        capture_output=True, text=True, timeout=10,
    )
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize("busy", [False, True])
def test_bridge_publication_is_atomic_without_hardlinks_on_macos(monkeypatch, tmp_path, busy):
    import sys
    import show_audio_ableton_offline as offline
    if sys.platform != "darwin":
        pytest.skip("publication native macOS")
    temporary = tmp_path / "request.tmp"
    command = tmp_path / "command.json"
    payload = '{"command":"get_loop_start_bbt","request_id":"test"}'
    temporary.write_text(payload)
    def forbidden_link(*args):
        raise PermissionError("Operation not permitted")
    monkeypatch.setattr(offline.os, "link", forbidden_link)
    if busy:
        command.write_text("existing request")
        with pytest.raises(FileExistsError):
            offline._publish_bridge_command(temporary, command)
        assert command.read_text() == "existing request"
        assert temporary.read_text() == payload
    else:
        offline._publish_bridge_command(temporary, command)
        assert command.read_text() == payload
        assert not temporary.exists()


@pytest.mark.parametrize("start,target,expected_actions,expected_budget", [
    (0, 256, 256, 272),
    (0, 257, 257, 273),
    (0, 1000, 1000, 1016),
    (1000, 238, 762, 778),
    (42, 42, 0, 16),
    (0, 10000, 10000, 10000),
])
def test_numeric_budget_and_success_logs(tmp_path, start, target, expected_actions, expected_budget):
    run_ax_simulation(tmp_path, f"const start = {start}, target = {target}, expectedActions = {expected_actions}, expectedBudget = {expected_budget};" + r"""
const id = bbtIdentifiers[3];
let value = start, actions = 0;
const logs = [];
function timing(message) { logs.push(JSON.parse(message.slice('bbt_numeric '.length))); }
numericAXValue = () => value;
performAXAction = (_id, action) => { actions++; value += action === 'AXIncrement' ? 1 : -1; };
setAXNumericByActions(id, target);
assert.strictEqual(value, target);
assert.strictEqual(actions, expectedActions);
assert.strictEqual(logs.length, 2);
for (const log of logs) {
  assert.strictEqual(log.identifier, id);
  assert.strictEqual(log.initial, start);
  assert.strictEqual(log.target, target);
  assert.strictEqual(log.budget, expectedBudget);
}
assert.strictEqual(logs[0].last, start);
assert.strictEqual(logs[0].actions, 0);
assert.strictEqual(logs[0].reason, 'start');
assert.strictEqual(logs[1].last, target);
assert.strictEqual(logs[1].actions, expectedActions);
assert.strictEqual(logs[1].reason, 'target_reached');
""")


@pytest.mark.parametrize("scenario,reason,last,actions", [
    ("no_effect", "no_effect", 0, 1),
    ("wrong_direction", "wrong_direction", -1, 1),
    ("overshoot", "overshoot", 4, 1),
    ("oscillation", "oscillation", 0, 2),
    ("maximum", "budget_exhausted", 0, 0),
    ("invalid", "invalid_current", 0.5, 1),
])
def test_numeric_failure_stops_and_logs(tmp_path, scenario, reason, last, actions):
    run_ax_simulation(tmp_path,
        "const scenario = " + json.dumps(scenario) + "; const expectedReason = " + json.dumps(reason) +
        f"; const expectedLast = {last}, expectedActions = {actions};" + r"""
const id = bbtIdentifiers[3];
let value = 0, actions = 0;
const target = scenario === 'maximum' ? 10001 : 3;
const logs = [];
function timing(message) { logs.push(JSON.parse(message.slice('bbt_numeric '.length))); }
numericAXValue = () => value;
performAXAction = () => {
  actions++;
  if (scenario === 'wrong_direction') value--;
  if (scenario === 'overshoot') value = 4;
  if (scenario === 'oscillation') value = actions % 2;
  if (scenario === 'invalid') value = 0.5;
};
assert.throws(() => setAXNumericByActions(id, target), new RegExp('reason=' + expectedReason));
assert.strictEqual(actions, expectedActions);
assert.strictEqual(completedBBT[id], undefined);
assert.strictEqual(logs.length, 2);
assert.strictEqual(logs[0].reason, 'start');
const log = logs[1];
assert.strictEqual(log.identifier, id);
assert.strictEqual(log.initial, 0);
assert.strictEqual(log.target, target);
assert.strictEqual(log.last, expectedLast);
assert.strictEqual(log.actions, expectedActions);
assert.strictEqual(log.reason, expectedReason);
assert.strictEqual(log.budget, Math.min(10000, target + 16));
""")


@pytest.mark.parametrize("settles", [True, False])
def test_bbt_waits_for_effect_without_repeating_action(tmp_path, settles):
    run_ax_simulation(tmp_path, "const settles = " + json.dumps(settles) + r""";
const id = bbtIdentifiers[3];
let value = 0, actions = 0, waits = 0;
numericAXValue = () => value;
performAXAction = () => { actions++; };
function delay(seconds) {
  assert.strictEqual(seconds, 0.05);
  waits++;
  if (settles && waits === 3) value = 1;
}
if (settles) {
  setAXNumericByActions(id, 1);
  assert.strictEqual(waits, 3);
  assert.strictEqual(completedBBT[id], 1);
} else {
  assert.throws(() => setAXNumericByActions(id, 1), /reason=no_effect/);
  assert.strictEqual(waits, 5);
}
assert.strictEqual(actions, 1);
""")


def test_numeric_failure_does_not_reopen_dialog(tmp_path):
    import shutil
    import subprocess
    script = build_ableton_export_script(
        start_bbt=(315, 3, 3), length_bbt=(69, 3, 3),
        output_path=tmp_path / "test.wav", sample_rate=48000,
        bit_depth=24, normalize=False,
    )
    block = script[script.index('try {\n  configureExportBBT();'):script.index('timing("configure_bbt:done");')]
    harness = r"""
const assert = require('assert');
function configureExportBBT() { throw new Error('Reglage AX BBT interrompu: reason=no_effect'); }
function timing() { assert.fail('retry numérique inattendu'); }
assert.throws(() => { BLOCK }, /reason=no_effect/);
""".replace('BLOCK', block)
    result = subprocess.run([shutil.which("node"), "-e", harness], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr


def test_jxa_has_global_budget_for_large_start_delta(monkeypatch, tmp_path):
    import subprocess
    import show_audio_ableton_offline as offline
    calls = []
    def run(command, **kwargs):
        calls.append(kwargs["timeout"])
        if len(calls) == 1:
            return subprocess.CompletedProcess(command, 0, "", "")
        raise subprocess.TimeoutExpired(command, kwargs["timeout"])
    monkeypatch.setattr(offline.subprocess, "run", run)
    monkeypatch.setattr(offline.time, "monotonic", lambda: 0.0)
    script = build_ableton_export_script(
        start_bbt=(315, 3, 3), length_bbt=(69, 3, 3), output_path=tmp_path / "test.wav",
        sample_rate=48000, bit_depth=24, normalize=False,
    )
    with pytest.raises(OfflineExportError, match="configure_export_jxa"):
        offline.run_macos_automation(script, timeout=300)
    assert calls == [60, 300]


@pytest.fixture(scope="module")
def native_bbt_fixture(tmp_path_factory):
    import shutil
    import subprocess
    from pathlib import Path
    import show_audio_ableton_offline as offline
    swift = shutil.which("swiftc")
    if not swift:
        pytest.skip("Swift requis pour les tests du helper natif")
    directory = tmp_path_factory.mktemp("native_bbt")
    source = directory / "main.swift"
    source.write_text("import Foundation\n" + offline._NATIVE_BBT_ALGORITHM_SWIFT + r"""
let scenario = CommandLine.arguments[1]
var value = Int(CommandLine.arguments[2])!
let target = Int(CommandLine.arguments[3])!
var actions = 0, waits = 0
var invalid = false
var records: [[String: Any]] = []
var failure = ""
do {
    try adjustBBT(target: target, read: { invalid ? nil : value }, action: { up in
        actions += 1
        switch scenario {
        case "no_effect", "delayed": break
        case "wrong_direction": value += up ? -1 : 1
        case "overshoot": value = target + 1
        case "oscillation": value = actions % 2
        case "invalid": invalid = true
        default: value += up ? 1 : -1
        }
    }, pause: {
        waits += 1
        if scenario == "delayed" && waits == 3 { value = target }
    }, expired: { scenario == "deadline" }, log: { initial, last, count, budget, reason in
        records.append(["initial": initial, "target": target, "last": last,
                        "actions": count, "budget": budget, "reason": reason])
    })
} catch let error as BBTAdjustmentError { failure = error.reason }
let result: [String: Any] = ["value": value, "actions": actions, "waits": waits, "failure": failure, "logs": records]
print(String(data: try! JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
""")
    binary = directory / "native-bbt"
    compiled = subprocess.run([swift, "-module-cache-path", str(directory / "cache"), str(source), "-o", str(binary)],
                              capture_output=True, text=True, timeout=120)
    assert compiled.returncode == 0, compiled.stderr
    return binary


@pytest.mark.parametrize("start,target,count", [(0,256,256), (0,257,257), (0,1000,1000),
    (1000,238,762), (42,42,0), (4281,603,3678), (0,10000,10000)])
def test_native_bbt_large_moves_and_logs(native_bbt_fixture, start, target, count):
    import subprocess
    result = subprocess.run([str(native_bbt_fixture), "normal", str(start), str(target)], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert (data["value"], data["actions"], data["failure"]) == (target, count, "")
    assert [log["reason"] for log in data["logs"]] == ["start", "target_reached"]
    assert data["logs"][-1] == {"initial": start, "target": target, "last": target,
        "actions": count, "budget": min(10000, abs(target-start)+16), "reason": "target_reached"}


@pytest.mark.parametrize("scenario,target,reason,count", [
    ("no_effect",3,"no_effect",1), ("wrong_direction",3,"wrong_direction",1),
    ("overshoot",3,"overshoot",1), ("oscillation",3,"oscillation",2),
    ("normal",10001,"budget_exhausted",0), ("invalid",3,"invalid_current",1),
    ("deadline",3,"deadline_exceeded",0), ("delayed",3,"",1),
])
def test_native_bbt_safety(native_bbt_fixture, scenario, target, reason, count):
    import subprocess
    result = subprocess.run([str(native_bbt_fixture), scenario, "0", str(target)], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert data["failure"] == reason
    assert data["actions"] == count
    assert data["logs"][-1]["reason"] == (reason or "target_reached")
    if scenario == "delayed":
        assert data["waits"] == 3
    if scenario == "no_effect":
        assert data["waits"] == 25


@pytest.mark.parametrize("outcome", ["ok", "failure", "verification"])
def test_jxa_native_worker_contract(tmp_path, outcome):
    import shutil
    import subprocess
    import sys
    if sys.platform != "darwin":
        pytest.skip("ObjC JXA requis")
    worker = tmp_path / "worker"
    worker.write_text("#!/bin/sh\nprintf 'BBT_OK=1\\n'\nexit " + ("1" if outcome == "failure" else "0") + "\n")
    worker.chmod(0o700)
    script = build_ableton_export_script(start_bbt=(1,1,1),length_bbt=(1,0,0),
        output_path=tmp_path / "out.wav",sample_rate=48000,bit_depth=24,normalize=False)
    helper = script[script.index("function setAXNumericByActions"):script.index("\n\nfunction setBBT")]
    prefix = 'ObjC.import("Foundation"); const nativeBBTWorker = ' + json.dumps(str(worker)) + r""";
const live = {unixId:()=>123};
const bbtIdentifiers = ['test'];
const completedBBT = {};
let cleared = 0;
function clearBBTControlCache(){cleared++;}
""" + "function numericAXValue(){return " + ("2" if outcome == "verification" else "1") + ";}"
    assertion = r"""
let failed = false;
try { setAXNumericByActions('test', 1); } catch(e) { failed = true; }
if (failed !== EXPECTED) throw new Error('unexpected worker result');
if (!failed && (completedBBT.test !== 1 || cleared !== 1)) throw new Error('verification missing');
""".replace("EXPECTED", "false" if outcome == "ok" else "true")
    result = subprocess.run(['/usr/bin/osascript', '-l', 'JavaScript', '-e', prefix+helper+assertion],
                            capture_output=True,text=True,timeout=10)
    assert result.returncode == 0, result.stderr



def test_cancel_stops_running_export_process(tmp_path):
    import sys
    import threading
    import time
    import show_audio_ableton_offline as offline
    event = threading.Event()
    started = tmp_path / "started"
    command = [sys.executable, "-c",
               "from pathlib import Path; import time; Path(" + repr(str(started)) + ").touch(); time.sleep(30)"]
    def cancel_when_running():
        deadline = time.monotonic() + 5
        while not started.exists() and time.monotonic() < deadline:
            time.sleep(.01)
        event.set()
    thread = threading.Thread(target=cancel_when_running)
    thread.start()
    before = time.monotonic()
    try:
        with pytest.raises(offline.ExportCancelled):
            offline._run_export_process(command, cancel_event=event, capture_output=True, text=True, timeout=30)
    finally:
        event.set()
        thread.join(timeout=6)
    assert started.exists()
    assert time.monotonic() - before < 5


def test_cancel_before_launch_never_starts_process(monkeypatch):
    import threading
    import show_audio_ableton_offline as offline
    event = threading.Event()
    event.set()
    monkeypatch.setattr(offline.subprocess, "Popen", lambda *a, **kw: pytest.fail("process launched"))
    with pytest.raises(offline.ExportCancelled):
        offline._run_export_process(["unused"], cancel_event=event)


@pytest.mark.parametrize("phase", ["configure", "render_wait"])
def test_cancel_export_closes_dialog_then_restores_loop(monkeypatch, tmp_path, phase):
    import threading
    import show_audio_ableton_offline as offline
    event = threading.Event()
    previous = {"loop_start": 10, "loop_length": 4, "loop": False}
    events = []
    monkeypatch.setattr(offline, "_prepare_live_export_loop", lambda **kw: previous)
    monkeypatch.setattr(offline, "_get_live_loop_start_bbt", lambda: (315, 3, 3))
    def automation(*args, **kwargs):
        assert kwargs["cancel_event"] is event
        events.append("automation")
        event.set()
        if phase == "configure":
            raise offline.ExportCancelled("Export audio annulé")
    monkeypatch.setattr(offline, "run_macos_automation", automation)
    monkeypatch.setattr(offline, "_cancel_live_export", lambda: events.append("close_dialog"))
    monkeypatch.setattr(offline, "_restore_live_loop_state", lambda state: events.append(("restore", state)))
    target = tmp_path / "final.wav"
    target.write_bytes(b"existing audio")
    result = offline.execute_offline_wav(zone={"start_beats": 1258.5, "duration_beats": 2},
        settings=settings(), output_path=target, tempo=120, cancel_event=event)
    assert result["status"] == "cancelled"
    assert events == ["automation", "close_dialog", ("restore", previous)]
    assert target.read_bytes() == b"existing audio"



def test_cancel_stops_descendant_even_if_it_ignores_term(tmp_path):
    import sys
    import threading
    import time
    import show_audio_ableton_offline as offline
    heartbeat = tmp_path / "heartbeat"
    child = "import signal,time; from pathlib import Path; signal.signal(signal.SIGTERM,signal.SIG_IGN); p=Path(" + repr(str(heartbeat)) + ");\nwhile True: p.write_text(str(time.monotonic())); time.sleep(.02)"
    parent = "import subprocess,sys,time; subprocess.Popen([sys.executable,'-c'," + repr(child) + "],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); time.sleep(30)"
    event = threading.Event()
    def cancel():
        deadline = time.monotonic() + 5
        while not heartbeat.exists() and time.monotonic() < deadline:
            time.sleep(.01)
        event.set()
    thread = threading.Thread(target=cancel)
    thread.start()
    try:
        with pytest.raises(offline.ExportCancelled):
            offline._run_export_process([sys.executable,"-c",parent], cancel_event=event, capture_output=True,text=True,timeout=10)
    finally:
        event.set()
        thread.join(timeout=6)
    assert heartbeat.exists()
    time.sleep(.1)
    last = heartbeat.read_text()
    time.sleep(.15)
    assert heartbeat.read_text() == last


@pytest.mark.parametrize("scenario,expected_presses,failed", [
    ("none",0,False), ("export",1,False), ("save",2,False),
    ("render",1,False), ("unrelated",0,False), ("refuses",3,True),
])
def test_cancel_live_is_scoped_and_confirmed(monkeypatch, scenario, expected_presses, failed):
    import shutil
    import subprocess
    import show_audio_ableton_offline as offline
    calls = []
    monkeypatch.setattr(offline.subprocess, "run", lambda command, **kw: calls.append(command))
    offline._cancel_live_export()
    script = calls[0][-1]
    # Use a real JS runtime with only the Live window surface simulated.
    harness = "const scenario = " + json.dumps(scenario) + r""";
let presses=0;
let stages = scenario==='save' ? ['save','export'] :
             ['export','render','refuses','unrelated'].includes(scenario) ? [scenario] : [];
function windowFor(stage) { return {
  name:()=>stage==='export'||stage==='refuses' ? 'Exporter Audio/Vidéo' : stage==='render' ? 'Exportation Audio...' : 'SHOW CASSIS',
  attributes:{byName:()=>({value:()=>stage==='save' ? 'save-panel' : ''})},
  sheets:()=>[]
}; }
const process = {windows:()=>[windowFor(stages[0]||'main')]};
function Application(){return {applicationProcesses:{whose:()=>()=>[process]},
  keyCode:(key)=>{if(key!==53) throw Error('unexpected key'); presses++; if(scenario!=='refuses') stages.shift();}};}
function delay(){}
let failure=false;
try { SCRIPT } catch(e) { failure=true; }
if(presses!==EXPECTED || failure!==FAILED) throw Error('cancel scope or confirmation incorrect');
""".replace('SCRIPT', script).replace('EXPECTED',str(expected_presses)).replace('FAILED',json.dumps(failed))
    # Capture before monkeypatching the subprocess module shared by the test.
    # Popen avoids the mocked run used to capture the production script.
    process = subprocess.Popen([shutil.which("node"),"-e",harness],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    stdout,stderr=process.communicate(timeout=10)
    assert process.returncode==0,stderr


@pytest.mark.parametrize("language", ["fr", "en"])
@pytest.mark.parametrize("scenario", ["ready", "missing", "disabled", "unavailable"])
def test_export_open_uses_localized_menu_before_shortcut(tmp_path, language, scenario):
    import shutil
    import subprocess
    script = build_ableton_export_script(start_bbt=(603,3,3),length_bbt=(110,1,0),
        output_path=tmp_path / "test.wav",sample_rate=48000,bit_depth=24,normalize=False)
    opener = script[script.index("function openExportDialog()"):script.index("// Live peut parfois")]
    harness = 'const language = ' + json.dumps(language) + '; const scenario = ' + json.dumps(scenario) + r""";
const assert=require('assert');
const events=[];
const fileName=language==='fr' ? 'Fichier' : 'File';
const editName=language==='fr' ? 'Edition' : 'Edit';
function heading(name,command,kind){return {
 name:()=>name,
 click:()=>events.push('heading:'+kind),
 menus:()=>[{menuItems:()=>scenario==='missing' && kind==='export' ? [] : [{
   name:()=>command, enabled:()=>scenario!=='disabled'||kind!=='export',
   click:()=>events.push('command:'+kind)
 }]}]
};}
const live={frontmost:false,menuBars:()=>{
 if(scenario==='unavailable') throw Error('AX unavailable');
 return [{menuBarItems:()=>[
 heading(editName,language==='fr' ? 'Sélectionner la boucle' : 'Select Loop','loop'),
 heading(fileName,language==='fr' ? 'Exporter Audio/Vidéo...' : 'Export Audio/Video…','export')
 ]}];
}};
const se={keyCode:()=>events.push('close_menu'),keystroke:key=>events.push('shortcut:'+key)};
function delay(){}
function timing(){}
OPENER
if(scenario==='disabled') {
 assert.throws(openExportDialog,/Commande menu Live desactivee/);
 assert(!events.includes('shortcut:r'));
} else {
 openExportDialog();
 if(scenario==='ready') {
   assert.deepStrictEqual(events,['heading:loop','command:loop','heading:export','command:export']);
 } else if(scenario==='missing') {
   assert.deepStrictEqual(events,['heading:loop','command:loop','heading:export','close_menu','shortcut:r']);
 } else {
   assert.deepStrictEqual(events,['shortcut:l','shortcut:r']);
 }
}
""".replace('OPENER',opener)
    result = subprocess.run([shutil.which('node'),'-e',harness],capture_output=True,text=True,timeout=10)
    assert result.returncode==0,result.stderr
