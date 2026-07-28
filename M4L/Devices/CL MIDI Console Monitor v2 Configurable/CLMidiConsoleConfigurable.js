autowatch = 1;
inlets = 4;
outlets = 4;

var trackIds = [];
var trackIndices = [];
var trackNames = [];
var selectedMenuIndex = 0;
var selectedTrackId = 0;
var selectedTrackIndex = -1;
var selectedTrackName = "";
var consoleName = "Console";
var lastProgram = null;
var lastTitle = "";
var trackObserver = null;

function scalar(value, fallback) {
    if (value instanceof Array) return value.length ? value[value.length - 1] : fallback;
    return value === undefined || value === null ? fallback : value;
}

function cleanName(value) {
    return String(value || "")
        .replace(/[\"“”«»]/g, "")
        .replace(/;\s*BPM\s*;\s*KEY\s*;/i, " / ")
        .replace(/\s+/g, " ")
        .replace(/^\s+|\s+$/g, "");
}

function refresh() {
    var previousId = selectedTrackId;
    trackIds = [];
    trackIndices = [];
    trackNames = [];
    outlet(0, "clear");
    outlet(0, "append", "Automatique");
    try {
        var song = new LiveAPI(null, "live_set");
        var count = parseInt(song.getcount("tracks"), 10);
        for (var index = 0; index < count; index++) {
            var track = new LiveAPI(null, "live_set tracks " + index);
            var name = String(scalar(track.get("name"), "Piste " + (index + 1)));
            var id = parseInt(track.id, 10);
            trackIds.push(id);
            trackIndices.push(index);
            trackNames.push(name);
            outlet(0, "append", name);
        }
    } catch (error) {
        outlet(3, "Live API indisponible");
        return;
    }
    if (previousId) {
        for (var position = 0; position < trackIds.length; position++) {
            if (trackIds[position] === previousId) {
                selectedMenuIndex = position + 1;
                break;
            }
        }
    }
    outlet(0, "set", selectedMenuIndex);
    select(selectedMenuIndex);
}

function automaticTrackIndex() {
    var needle = consoleName.toUpperCase().replace(/[^A-Z0-9]+/g, " ");
    for (var index = 0; index < trackNames.length; index++) {
        var candidate = trackNames[index].toUpperCase().replace(/[^A-Z0-9]+/g, " ");
        if (needle && candidate.indexOf(needle) >= 0 &&
            (candidate.indexOf("PGM") >= 0 || candidate.indexOf("PROGRAM") >= 0 || candidate.indexOf("RETOUR") >= 0)) {
            return trackIndices[index];
        }
    }
    return -1;
}

function select(value) {
    selectedMenuIndex = Math.max(0, parseInt(value, 10) || 0);
    if (selectedMenuIndex > 0 && selectedMenuIndex <= trackIds.length) {
        selectedTrackId = trackIds[selectedMenuIndex - 1];
        selectedTrackIndex = trackIndices[selectedMenuIndex - 1];
        selectedTrackName = trackNames[selectedMenuIndex - 1];
    } else {
        selectedTrackId = 0;
        selectedTrackIndex = automaticTrackIndex();
        selectedTrackName = selectedTrackIndex >= 0 ? "Automatique" : "";
    }
    observeTrack();
    outlet(3, selectedTrackIndex >= 0 ? [consoleName, "·", selectedTrackName] : [consoleName, "· aucune piste"]);
}

function observeTrack() {
    trackObserver = null;
    if (selectedTrackIndex < 0) return;
    try {
        trackObserver = new LiveAPI(playingSlotChanged, "live_set tracks " + selectedTrackIndex);
        trackObserver.property = "playing_slot_index";
    } catch (error) {
        trackObserver = null;
    }
}

function currentTitle() {
    if (selectedTrackIndex < 0) return "";
    try {
        var track = new LiveAPI(null, "live_set tracks " + selectedTrackIndex);
        var slot = parseInt(scalar(track.get("playing_slot_index"), -1), 10);
        if (slot < 0) return lastTitle;
        var scene = new LiveAPI(null, "live_set scenes " + slot);
        return cleanName(scalar(scene.get("name"), ""));
    } catch (error) {
        return lastTitle;
    }
}

function render() {
    if (lastProgram === null) return;
    var title = currentTitle();
    if (title) lastTitle = title;
    outlet(1, lastTitle || "—");
    outlet(2, lastProgram + 1);
}

function playingSlotChanged() { render(); }

function msg_int(value) {
    if (inlet === 0) select(value);
    else if (inlet === 1) {
        lastProgram = parseInt(value, 10);
        lastTitle = "";
        render();
    }
}

function list() {
    var values = arrayfromargs(arguments);
    if (inlet === 2) {
        consoleName = values.join(" ") || "Console";
        if (selectedMenuIndex === 0) select(0);
    }
}

function anything() {
    var values = arrayfromargs(arguments);
    if (inlet === 0 && messagename === "refresh") refresh();
    else if (inlet === 0 && messagename === "select" && values.length) select(values[0]);
    else if (inlet === 2) {
        consoleName = ([messagename].concat(values)).join(" ");
        if (selectedMenuIndex === 0) select(0);
    }
}

function bang() {
    if (inlet === 0) refresh();
    else render();
}

function reset() {
    lastProgram = null;
    lastTitle = "";
    outlet(1, "—");
    outlet(2, "—");
}
