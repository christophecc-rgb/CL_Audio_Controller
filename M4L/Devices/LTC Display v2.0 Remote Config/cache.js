outlets = 2;

var cache = [];
var lastPos = 0;

function pos(p) {
	lastPos = Number(p);
}

function tc(t, f) {
	cache = cache.filter(function(e) {
		return e.tc != t;
	});

	cache.push({pos: lastPos, tc: t, fps: f});
}

function size() {
	post("cache contains " + cache.length + " frames\n");
}

function get(p) {
	var pos = Number(p);
	post("getting cache at pos " + pos + "\n");

	var applicable = cache.filter(function(e) {
		return e.pos <= pos;
	});

	var closest = applicable[0];

	if (!closest) {
		outlet(0, "00:00:00:00", "--");
		return;
	}

	for (var i = 0; i < applicable.length; i++) {
		var e = applicable[i];
		if (pos - e.pos < pos - closest.pos) {
			closest = e;
		}
	}

	if (pos - closest.pos > 1) {
		outlet(0, "00:00:00:00", "--");
	} else {
		outlet(0, closest.tc, closest.fps);
	}
}

function getPos(tc) {
	var match = null;

	post("looking for tc " + tc + "\n");

	for (var i = 0; i < cache.length; i++) {
		if (cache[i].tc == tc) {
			match = cache[i];
			break;
		}
	}

	post("match: " + JSON.stringify(match) + "\n");

	if (match) {
		outlet(1, match.pos);
	} else {
		post("didn't find match!\n");
	}
}