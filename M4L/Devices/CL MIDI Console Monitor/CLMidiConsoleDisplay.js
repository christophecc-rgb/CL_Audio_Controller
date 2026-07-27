autowatch = 1;
inlets = 1;
outlets = 1;

var consoleName = jsarguments.length > 1 ? String(jsarguments[1]).replace(/_/g, " ") : "CL5";
var programOffset = jsarguments.length > 2 ? parseInt(jsarguments[2], 10) : 0;
var currentSceneName = "";
var currentSceneGeneration = 0;
var currentSceneIndex = -1;
var playingSlotSceneName = "";
var lastProgram = null;
var programAwaitingSceneContext = false;
var trackObserver = null;
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
    return trim(cleaned);
}

function render(program) {
    // The QL1 CC converter can emit several Program Changes during one song
    // (for example memory 27 at the beginning, then 28 at the end). Its small
    // conversion clip is not the show title: keep the confirmed OSC scene
    // name while only the Yamaha memory number changes.
    var displayName = consoleName === "QL1 CC"
        ? (currentSceneName || playingSlotSceneName)
        : (playingSlotSceneName || currentSceneName);
    var programKey = physicalConsole + "Program";
    var nameKey = physicalConsole + "Name";
    if (displayName) {
        sharedDisplay[programKey] = program;
        sharedDisplay[nameKey] = displayName;
    } else if (
        parseInt(sharedDisplay[programKey], 10) === program &&
        sharedDisplay[nameKey]
    ) {
        // QL1 CC and QL1 PGM share one physical display. A delayed instance
        // carrying only the number must not erase a title already resolved by
        // the other path for the same Program Change.
        displayName = String(sharedDisplay[nameKey]);
    } else {
        sharedDisplay[programKey] = program;
        sharedDisplay[nameKey] = "";
    }
    if (displayName) {
        outlet(0, [cleanName(displayName), "/", "Scène", program]);
    } else {
        outlet(0, ["Scène", program]);
    }
}

function scalar(value, fallback) {
    if (value instanceof Array) {
        return value.length ? value[value.length - 1] : fallback;
    }
    return value === undefined || value === null ? fallback : value;
}

function refreshPlayingSlotScene() {
    if (!trackObserver) {
        return;
    }
    var slotIndex = parseInt(scalar(trackObserver.get("playing_slot_index"), -1), 10);
    // Program Change clips are often extremely short. Live reports their
    // playing slot only briefly, then immediately returns -1. Keep the last
    // valid row name until another Program Change or an explicit reset so the
    // confirmation does not fall back to the main scene when the clip ends.
    if (!isNaN(slotIndex) && slotIndex >= 0) {
        try {
            var sceneApi = new LiveAPI(null, "live_set scenes " + slotIndex);
            playingSlotSceneName = String(scalar(sceneApi.get("name"), ""));
        } catch (error) {
            // Preserve the last valid name when Live is between clip states.
        }
    }
    if (lastProgram !== null) {
        render(lastProgram);
    }
}

function playingSlotChanged() {
    refreshPlayingSlotScene();
}

function initializeLiveObserver() {
    try {
        trackObserver = new LiveAPI(playingSlotChanged, "this_device canonical_parent");
        trackObserver.property = "playing_slot_index";
        refreshPlayingSlotScene();
    } catch (error) {
        trackObserver = null;
    }
}

function showProgram(value) {
    var program = parseInt(value, 10);
    if (isNaN(program)) {
        return;
    }
    program += programOffset;
    lastProgram = program;
    programAwaitingSceneContext = true;
    // A new command starts a new title association. The next valid slot event
    // will be latched, while the previous manual clip title must not leak.
    playingSlotSceneName = "";
    if (!trackObserver) {
        initializeLiveObserver();
    }
    refreshPlayingSlotScene();
    render(program);
}

function scene() {
    var values = arrayfromargs(arguments);
    currentSceneGeneration = values.length > 0 ? parseInt(values[0], 10) : 0;
    currentSceneIndex = values.length > 1 ? parseInt(values[1], 10) : -1;
    currentSceneName = values.length > 2 ? values.slice(2).join(" ") : "";

    // Une confirmation OSC de scène ne doit jamais effacer une information
    // MIDI déjà affichée. Si un Program Change vient d'arriver avant le nom
    // de scène, réafficher cette même valeur avec le nouveau contexte corrige
    // l'ordre d'arrivée sans toucher aux autres lignes.
    if (programAwaitingSceneContext && lastProgram !== null) {
        programAwaitingSceneContext = false;
        render(lastProgram);
    }
}

function reset() {
    currentSceneName = "";
    currentSceneIndex = -1;
    playingSlotSceneName = "";
    lastProgram = null;
    programAwaitingSceneContext = false;
    sharedDisplay[physicalConsole + "Program"] = null;
    sharedDisplay[physicalConsole + "Name"] = "";
    outlet(0, "—");
}

function bang() {
    initializeLiveObserver();
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
