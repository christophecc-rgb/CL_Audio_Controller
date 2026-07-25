autowatch = 1;
inlets = 1;
outlets = 3;

var scenes = [];
var selectedIndex = -1;
var selectedId = 0;
var armed = false;
var fired = false;
var targetHour = 19;
var targetMinute = 30;
var targetSecond = 0;
var previousSecondOfDay = -1;
var lastClockText = "";
var lastCountdownText = "";

function loadbang() {
    post("Paradis Latin AutoScene: script charge\n");
    refresh();
    emitState("NON ARME");
}

function refresh() {
    post("Paradis Latin AutoScene: actualisation demandee\n");
    var previousId = selectedId;
    var ids = sceneIds();
    post("Paradis Latin AutoScene: " + ids.length + " scene(s) trouvee(s)\n");
    scenes = [];
    outlet(0, "clear");

    for (var i = 0; i < ids.length; i++) {
        var scene = new LiveAPI(null);
        scene.id = ids[i];
        var nameValue = scene.get("name");
        var sceneName = valueToString(nameValue);
        var label = pad2(i + 1) + " - " + (sceneName || "Scene sans nom");
        scenes.push({ id: ids[i], name: sceneName, label: label });
        outlet(0, "append", label);
    }

    selectedIndex = findSceneById(previousId);
    if (selectedIndex < 0 && scenes.length > 0) {
        selectedIndex = 0;
    }
    applySelection(selectedIndex);
    outlet(1, "scenecount", scenes.length);
}

function msg_int(index) {
    select(index);
}

function select(index) {
    index = parseInt(index, 10);
    if (index < 0 || index >= scenes.length) {
        selectedIndex = -1;
        selectedId = 0;
        outlet(1, "selection", "Aucune scene");
        return;
    }
    applySelection(index);
    armed = true;
    fired = false;
    previousSecondOfDay = secondsNow();
    emitState("ARME - " + scenes[index].label);
    outlet(2, "arm");
}

function hour(value) {
    targetHour = clamp(parseInt(value, 10), 0, 23);
    targetChanged();
}

function minute(value) {
    targetMinute = clamp(parseInt(value, 10), 0, 59);
    targetChanged();
}

function second(value) {
    targetSecond = clamp(parseInt(value, 10), 0, 59);
    targetChanged();
}

function arm(value) {
    armed = parseInt(value, 10) !== 0;
    fired = false;
    previousSecondOfDay = secondsNow();
    emitState(armed ? "ARME - EN ATTENTE" : "NON ARME");
}

function reset() {
    fired = false;
    previousSecondOfDay = secondsNow();
    emitState(armed ? "ARME - EN ATTENTE" : "NON ARME");
}

function test() {
    if (armed) {
        emitState("TEST REFUSE - DESARMER D'ABORD");
        return;
    }
    launchSelected("TEST");
}

function fire() {
    launchSelected("MANUEL");
}

function tick() {
    var now = new Date();
    var current = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();
    var target = targetSeconds();
    var clockText = pad2(now.getHours()) + ":" + pad2(now.getMinutes()) + ":" + pad2(now.getSeconds());

    if (clockText !== lastClockText) {
        lastClockText = clockText;
        outlet(1, "clock", clockText);
    }

    var remaining = target - current;
    if (remaining < 0) {
        remaining += 86400;
    }
    var countdownText = formatDuration(remaining);
    if (countdownText !== lastCountdownText) {
        lastCountdownText = countdownText;
        outlet(1, "countdown", countdownText);
    }

    if (armed && !fired && crossedTarget(previousSecondOfDay, current, target)) {
        if (launchSelected("AUTOMATIQUE")) {
            fired = true;
            armed = false;
            outlet(2, "disarm");
        }
    }
    previousSecondOfDay = current;
}

function crossedTarget(previous, current, target) {
    if (previous < 0) {
        return false;
    }
    if (current >= previous) {
        return previous < target && current >= target;
    }
    return previous < target || current >= target;
}

function launchSelected(origin) {
    if (!selectedId) {
        emitState("ERREUR - AUCUNE SCENE");
        return false;
    }
    try {
        var scene = new LiveAPI(null);
        scene.id = selectedId;
        scene.call("fire");
        emitState("DECLENCHE - " + origin + " - " + scenes[selectedIndex].label);
        outlet(2, "fired");
        return true;
    } catch (error) {
        emitState("ERREUR - ACTUALISER LES SCENES");
        post("Paradis Latin AutoScene: " + error + "\n");
        return false;
    }
}

function sceneIds() {
    try {
        var song = new LiveAPI(null, "live_set");
        var count = parseInt(song.getcount("scenes"), 10);
        var ids = [];
        for (var i = 0; i < count; i++) {
            var scene = new LiveAPI(null, "live_set scenes " + i);
            var sceneId = parseInt(scene.id, 10);
            if (sceneId > 0) {
                ids.push(sceneId);
            }
        }
        return ids;
    } catch (error) {
        emitState("ERREUR - LIVE API INDISPONIBLE");
        post("Paradis Latin AutoScene: " + error + "\n");
        return [];
    }
}

function applySelection(index) {
    selectedIndex = index;
    if (index < 0 || index >= scenes.length) {
        selectedId = 0;
        outlet(1, "selection", "Aucune scene");
        return;
    }
    selectedId = scenes[index].id;
    outlet(0, "set", index);
    outlet(1, "selection", scenes[index].label);
}

function findSceneById(id) {
    for (var i = 0; i < scenes.length; i++) {
        if (scenes[i].id === id) {
            return i;
        }
    }
    return -1;
}

function targetChanged() {
    fired = false;
    previousSecondOfDay = secondsNow();
    outlet(1, "target", pad2(targetHour) + ":" + pad2(targetMinute) + ":" + pad2(targetSecond));
}

function emitState(text) {
    outlet(1, "status", text);
}

function targetSeconds() {
    return targetHour * 3600 + targetMinute * 60 + targetSecond;
}

function secondsNow() {
    var now = new Date();
    return now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();
}

function formatDuration(total) {
    var hours = Math.floor(total / 3600);
    var minutes = Math.floor((total % 3600) / 60);
    var seconds = total % 60;
    return pad2(hours) + ":" + pad2(minutes) + ":" + pad2(seconds);
}

function valueToString(value) {
    if (value instanceof Array) {
        return value.join(" ");
    }
    return String(value);
}

function pad2(value) {
    return value < 10 ? "0" + value : String(value);
}

function clamp(value, minimum, maximum) {
    if (isNaN(value)) {
        return minimum;
    }
    return Math.max(minimum, Math.min(maximum, value));
}
