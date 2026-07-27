autowatch = 1;
inlets = 1;
outlets = 2;

var consoleName = jsarguments.length > 1 ? String(jsarguments[1]).replace(/_/g, " ") : "CL5";
var programOffset = jsarguments.length > 2 ? parseInt(jsarguments[2], 10) : 0;
var currentSceneName = "";
var currentSceneGeneration = 0;
var currentSceneIndex = -1;
var playingSlotSceneName = "";
var selectedStoppedSceneName = "";
var latchedProgramName = "";
var lastProgram = null;
var programAwaitingSceneContext = false;
var trackObserver = null;
var observedTrackIndex = -1;
var sharedDisplay = new Global("CLMidiConsoleDisplayState");
var physicalConsole = consoleName.indexOf("QL1") === 0 ? "ql1" : "cl5";
var sourceTracks = null;

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
    // Prefer the Session row that actually emitted the Program Change. This
    // also covers manual launches made outside the main show flow. OSC remains
    // the fallback when Live no longer exposes a playing slot (short clips or
    // a Program Change occurring later in the current song).
    var directlyResolvedName = playingSlotSceneName || selectedStoppedSceneName;
    if (directlyResolvedName) {
        latchedProgramName = directlyResolvedName;
    }
    var displayName = latchedProgramName || currentSceneName;
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
        outlet(0, cleanName(displayName).split(/\s+/));
    } else {
        outlet(0, "—");
    }
    outlet(1, program);
}

function refreshSelectedStoppedScene() {
    selectedStoppedSceneName = "";
    if (physicalConsole !== "ql1") {
        return;
    }
    try {
        var songApi = new LiveAPI(null, "live_set");
        var isPlaying = parseInt(scalar(songApi.get("is_playing"), 0), 10);
        if (isPlaying) {
            return;
        }
        var selectedSceneApi = new LiveAPI(null, "live_set view selected_scene");
        selectedStoppedSceneName = String(scalar(selectedSceneApi.get("name"), ""));
    } catch (error) {
        selectedStoppedSceneName = "";
    }
}

function normalizedTrackName(value) {
    return trim(value).toUpperCase().replace(/[^A-Z0-9]+/g, " ");
}

function discoverSourceTracks() {
    var discovered = {cl5: [], ql1cc: [], ql1pgm: []};
    try {
        var songApi = new LiveAPI(null, "live_set");
        var trackCount = parseInt(songApi.getcount("tracks"), 10);
        for (var index = 0; index < trackCount; index++) {
            var trackApi = new LiveAPI(null, "live_set tracks " + index);
            var name = normalizedTrackName(scalar(trackApi.get("name"), ""));
            if (!name) {
                continue;
            }
            var isProgram = name.indexOf("PGM") >= 0 || name.indexOf("PROGRAM") >= 0;
            if (name.indexOf("CL5") >= 0 && isProgram && name.indexOf("CHANGE") >= 0) {
                discovered.cl5.push(index);
            } else if (name.indexOf("QL1") >= 0 && name.indexOf("CC") >= 0) {
                discovered.ql1cc.push(index);
            } else if (name.indexOf("QL1") >= 0 && isProgram && name.indexOf("CHANGE") >= 0) {
                discovered.ql1pgm.push(index);
            }
        }
    } catch (error) {
        return null;
    }
    return discovered;
}

function sourceTrackIndicesForConsole() {
    if (!sourceTracks) {
        sourceTracks = discoverSourceTracks();
    }
    if (!sourceTracks) {
        return [];
    }
    if (consoleName === "QL1 CC") {
        return sourceTracks.ql1cc;
    }
    if (consoleName === "QL1 PGM") {
        return sourceTracks.ql1pgm;
    }
    return sourceTracks.cl5;
}

function trackHasClip(trackIndex, sceneIndex) {
    try {
        var slotApi = new LiveAPI(
            null,
            "live_set tracks " + trackIndex + " clip_slots " + sceneIndex
        );
        return parseInt(scalar(slotApi.get("has_clip"), 0), 10) !== 0;
    } catch (error) {
        return false;
    }
}

function anySourceTrackHasClip(trackIndices, sceneIndex) {
    for (var index = 0; index < trackIndices.length; index++) {
        if (trackHasClip(trackIndices[index], sceneIndex)) {
            return true;
        }
    }
    return false;
}

function clearProgramDisplay() {
    playingSlotSceneName = "";
    selectedStoppedSceneName = "";
    latchedProgramName = "";
    lastProgram = null;
    programAwaitingSceneContext = false;
    sharedDisplay[physicalConsole + "Program"] = null;
    sharedDisplay[physicalConsole + "Name"] = "";
    outlet(0, "__CL_EMPTY__");
    outlet(1, "—");
}

function clearWhenSceneHasNoProgram(sceneIndex) {
    if (isNaN(sceneIndex) || sceneIndex < 0) {
        return;
    }
    if (!sourceTracks) {
        sourceTracks = discoverSourceTracks();
    }
    if (!sourceTracks) {
        return;
    }
    if (physicalConsole === "cl5") {
        // Unknown source names are fail-safe: never erase existing information.
        if (sourceTracks.cl5.length && !anySourceTrackHasClip(sourceTracks.cl5, sceneIndex)) {
            clearProgramDisplay();
        }
        return;
    }
    var ql1Tracks = sourceTracks.ql1cc.concat(sourceTracks.ql1pgm);
    if (ql1Tracks.length && !anySourceTrackHasClip(ql1Tracks, sceneIndex)) {
        clearProgramDisplay();
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
        var trackIndices = sourceTrackIndicesForConsole();
        if (!trackIndices.length) {
            trackObserver = null;
            observedTrackIndex = -1;
            return;
        }
        observedTrackIndex = trackIndices[0];
        trackObserver = new LiveAPI(
            playingSlotChanged,
            "live_set tracks " + observedTrackIndex
        );
        trackObserver.property = "playing_slot_index";
        refreshPlayingSlotScene();
    } catch (error) {
        trackObserver = null;
        observedTrackIndex = -1;
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
    latchedProgramName = "";
    refreshSelectedStoppedScene();
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
    clearWhenSceneHasNoProgram(currentSceneIndex);

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
    selectedStoppedSceneName = "";
    latchedProgramName = "";
    lastProgram = null;
    programAwaitingSceneContext = false;
    sharedDisplay[physicalConsole + "Program"] = null;
    sharedDisplay[physicalConsole + "Name"] = "";
    sourceTracks = null;
    trackObserver = null;
    observedTrackIndex = -1;
    outlet(0, "—");
    outlet(1, "—");
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
