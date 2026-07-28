autowatch = 1;
inlets = 1;
outlets = 2;

// This display deliberately avoids LiveAPI. LiveAPI calls run on Live/Max's
// main thread and can interrupt audio when several monitor devices are active.
// CL Audio Controller already publishes the current scene context over OSC,
// so the MIDI path only has to latch a Program Change and render that context.

var consoleName = jsarguments.length > 1 ? String(jsarguments[1]).replace(/_/g, " ") : "CL5";
var programOffset = jsarguments.length > 2 ? parseInt(jsarguments[2], 10) : 0;
var currentSceneGeneration = 0;
var currentSceneIndex = -1;
var currentSceneName = "";
var lastProgram = null;
var sharedDisplay = new Global("CLMidiConsoleDisplayState");
var physicalConsole = consoleName.indexOf("QL1") === 0 ? "ql1" : "cl5";

function trim(value) {
    return String(value).replace(/^\s+|\s+$/g, "");
}

function cleanName(value) {
    var cleaned = trim(value);
    cleaned = cleaned.replace(/[\"“”«»]/g, "");
    cleaned = cleaned.replace(/^([0-9]+)\s*[.\-]\s*/, "$1  ");
    cleaned = cleaned.replace(/\s*;\s*BPM\s*;\s*KEY\s*;?\s*/gi, "  ");
    cleaned = cleaned.replace(/\s*;\s*/g, "  ");
    cleaned = cleaned.replace(/\s+/g, " ");
    cleaned = cleaned.replace(/\s+([0-9]+:[0-9]{2}(?::[0-9]{2})?)$/, " / $1");
    return trim(cleaned);
}

function render(program) {
    var programKey = physicalConsole + "Program";
    var nameKey = physicalConsole + "Name";
    var displayName = currentSceneName;

    if (displayName) {
        sharedDisplay[programKey] = program;
        sharedDisplay[nameKey] = displayName;
    } else if (
        parseInt(sharedDisplay[programKey], 10) === program &&
        sharedDisplay[nameKey]
    ) {
        displayName = String(sharedDisplay[nameKey]);
    } else {
        sharedDisplay[programKey] = program;
        sharedDisplay[nameKey] = "";
    }

    outlet(0, displayName ? cleanName(displayName).split(/\s+/) : "—");
    outlet(1, program);
}

function showProgram(value) {
    var program = parseInt(value, 10);
    if (isNaN(program)) {
        return;
    }
    program += programOffset;
    lastProgram = program;
    render(program);
}

function scene() {
    var values = arrayfromargs(arguments);
    var generation = values.length > 0 ? parseInt(values[0], 10) : 0;
    var sceneIndex = values.length > 1 ? parseInt(values[1], 10) : -1;
    var sceneName = values.length > 2 ? values.slice(2).join(" ") : "";

    // The controller republishes the current context periodically so devices
    // loaded late can catch up. Identical packets must remain a no-op.
    if (
        generation === currentSceneGeneration &&
        sceneIndex === currentSceneIndex &&
        sceneName === currentSceneName
    ) {
        return;
    }

    currentSceneGeneration = generation;
    currentSceneIndex = sceneIndex;
    currentSceneName = sceneName;
    if (lastProgram !== null) {
        render(lastProgram);
    }
}

function reset() {
    currentSceneGeneration = 0;
    currentSceneIndex = -1;
    currentSceneName = "";
    lastProgram = null;
    sharedDisplay[physicalConsole + "Program"] = null;
    sharedDisplay[physicalConsole + "Name"] = "";
    outlet(0, "—");
    outlet(1, "—");
}

function bang() {
    // Kept for compatibility with existing generated patches. No LiveAPI work.
}

function msg_int(value) {
    showProgram(value);
}

function list() {
    var values = arrayfromargs(arguments);
    if (values.length) {
        showProgram(values[values.length - 1]);
    }
}

function anything() {
    var values = arrayfromargs(arguments);
    if (messagename === "PGM" && values.length) {
        showProgram(values[0]);
    }
}
