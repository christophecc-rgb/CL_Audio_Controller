autowatch = 1;
inlets = 2;
outlets = 2;

var consoleName = jsarguments.length > 1 ? String(jsarguments[1]) : "Console";
var programOffset = jsarguments.length > 2 ? parseInt(jsarguments[2], 10) : 0;
var expectedProgram = null;
var confirmedProgram = null;

function normalized(value) {
    var program = parseInt(value, 10);
    return isNaN(program) ? null : program + programOffset;
}

function requested(value) {
    var program = normalized(value);
    if (program === null) {
        return;
    }
    expectedProgram = program;
    confirmedProgram = null;
    outlet(0, ["ATTENTE", "·", "Scène", expectedProgram]);
    outlet(1, 0);
}

function confirmed(value) {
    var program = normalized(value);
    if (program === null) {
        return;
    }
    confirmedProgram = program;
    if (expectedProgram === null) {
        outlet(0, ["RETOUR", "·", "Scène", confirmedProgram]);
        outlet(1, 0);
    } else if (confirmedProgram === expectedProgram) {
        outlet(0, ["✓", "CHARGÉE", "·", "Scène", confirmedProgram]);
        outlet(1, 1);
    } else {
        outlet(0, ["⚠", "REÇUE", confirmedProgram, "·", "ATTENDUE", expectedProgram]);
        outlet(1, 0);
    }
}

function msg_int(value) {
    if (inlet === 0) {
        requested(value);
    } else {
        confirmed(value);
    }
}

function reset() {
    expectedProgram = null;
    confirmedProgram = null;
    outlet(0, "EN ATTENTE");
    outlet(1, 0);
}
