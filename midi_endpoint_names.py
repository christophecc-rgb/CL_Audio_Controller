"""Canonical endpoint names; mirrored in tools/shared/CLMIDIEndpointNames.h.

Names here describe CoreMIDI endpoints, never Bonjour peers or RTP sessions.
"""
import logging

CLOCK_IAC = 'CL Ableton Clock IAC'
MTC_IAC = 'CL MTC IAC'
SHOW_IAC = 'CL Show Control IAC'
SHOW_RTP = 'CL Show Control RTP'
RETURN_RTP = 'CL Console Return RTP'
RETURN_TEST = 'CL MIDI Return Test'
DIRECT_RTP = 'CL Direct RTP'
ALIASES = {
    CLOCK_IAC: ('Gestionnaire IAC CL Ableton Clock IAC', 'IAC Driver CL Ableton Clock IAC', 'Gestionnaire IAC Ableton Clock', 'IAC Driver Ableton Clock'),
    MTC_IAC: ('Gestionnaire IAC CL MTC IAC', 'IAC Driver CL MTC IAC', 'Gestionnaire IAC MTC vers Logic', 'IAC Driver MTC vers Logic'),
    SHOW_IAC: ('Gestionnaire IAC CL Show Control IAC', 'IAC Driver CL Show Control IAC', 'Gestionnaire IAC Bus 1', 'IAC Driver Bus 1'),
    SHOW_RTP: ('Réseau CL Show Control RTP', 'Network CL Show Control RTP', 'Réseau CL Show Control', 'Network CL Show Control'),
    RETURN_RTP: ('Réseau CL Console Return RTP', 'Network CL Console Return RTP', 'Réseau RTP MB Chris', 'Network RTP MB Chris'),
    RETURN_TEST: (), DIRECT_RTP: (),
}
_logged = set()


def canonical_name(name):
    for canonical, aliases in ALIASES.items():
        if str(name).casefold() in (n.casefold() for n in (canonical, *aliases)):
            return canonical
    return name


def endpoint_matches(name, requested):
    return str(canonical_name(name)).casefold() == str(canonical_name(requested)).casefold()


def resolve_endpoint(available, requested):
    canonical = canonical_name(requested)
    for candidate in (canonical, *ALIASES.get(canonical, ())):
        for actual in available:
            if actual.casefold() == candidate.casefold():
                key = (canonical, actual)
                if actual != canonical and key not in _logged:
                    _logged.add(key)
                    logging.getLogger(__name__).info('%s : %s : %s', canonical,
                        'nom CoreMIDI préfixé' if actual.endswith(canonical) else 'fallback legacy', actual)
                return actual
    raise LookupError(f'Endpoint absent : {canonical} (alias acceptés : {", ".join(ALIASES.get(canonical, ()))})')
