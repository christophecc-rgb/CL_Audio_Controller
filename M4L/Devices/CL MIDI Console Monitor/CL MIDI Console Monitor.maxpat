{
  "patcher": {
    "fileversion": 1,
    "appversion": {
      "major": 9,
      "minor": 1,
      "revision": 4,
      "architecture": "x64",
      "modernui": 1
    },
    "classnamespace": "box",
    "rect": [
      70.0,
      70.0,
      960.0,
      680.0
    ],
    "openinpresentation": 1,
    "devicewidth": 540.0,
    "description": "Three-console MIDI Program Change monitor",
    "digest": "Transparent MIDI monitor for CL5 and QL1 control tracks",
    "title": "CL MIDI Console Monitor",
    "project": {
      "version": 1,
      "creationdate": 0,
      "modificationdate": 0,
      "viewrect": [
        0.0,
        0.0,
        300.0,
        500.0
      ],
      "autoorganize": 1,
      "hideprojectwindow": 1,
      "showdependencies": 1,
      "autolocalize": 0,
      "contents": {
        "patchers": {}
      },
      "layout": {},
      "searchpath": {},
      "detailsvisible": 0,
      "amxdtype": 1835887981,
      "readonly": 0,
      "devpathtype": 0,
      "devpath": ".",
      "sortmode": 0,
      "viewmode": 0
    },
    "bgcolor": [
      0.04,
      0.05,
      0.07,
      1.0
    ],
    "boxes": [
      {
        "box": {
          "id": "midi-in",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            30.0,
            250.0,
            45.0,
            22.0
          ],
          "text": "midiin",
          "outlettype": [
            "int"
          ]
        }
      },
      {
        "box": {
          "id": "midi-out",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            30.0,
            325.0,
            50.0,
            22.0
          ],
          "text": "midiout"
        }
      },
      {
        "box": {
          "id": "midi-parse",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 8,
          "patching_rect": [
            110.0,
            325.0,
            65.0,
            22.0
          ],
          "text": "midiparse",
          "outlettype": [
            "",
            "",
            "",
            "int",
            "int",
            "",
            "int",
            ""
          ]
        }
      },
      {
        "box": {
          "id": "event-gate",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 5,
          "patching_rect": [
            180.0,
            510.0,
            48.0,
            22.0
          ],
          "text": "gate 5"
        }
      },
      {
        "box": {
          "id": "lookup-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            35.0,
            525.0,
            220.0,
            22.0
          ],
          "text": "js CLMidiConsoleDisplay.js CL5 1"
        }
      },
      {
        "box": {
          "id": "lookup-ql1-cc",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            200.0,
            525.0,
            235.0,
            22.0
          ],
          "text": "js CLMidiConsoleDisplay.js QL1_CC 1"
        }
      },
      {
        "box": {
          "id": "lookup-ql1-pgm",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            365.0,
            525.0,
            245.0,
            22.0
          ],
          "text": "js CLMidiConsoleDisplay.js QL1_PGM 1"
        }
      },
      {
        "box": {
          "id": "scene-udp",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            610.0,
            250.0,
            108.0,
            22.0
          ],
          "text": "udpreceive 9002"
        }
      },
      {
        "box": {
          "id": "scene-route",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 3,
          "patching_rect": [
            610.0,
            285.0,
            290.0,
            22.0
          ],
          "text": "route /cl/midi-monitor/scene /cl/midi-monitor/reset"
        }
      },
      {
        "box": {
          "id": "scene-prepend",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            610.0,
            320.0,
            92.0,
            22.0
          ],
          "text": "prepend scene"
        }
      },
      {
        "box": {
          "id": "scene-reset",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            720.0,
            320.0,
            72.0,
            22.0
          ],
          "text": "reset"
        }
      },
      {
        "box": {
          "id": "scene-send",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            610.0,
            355.0,
            210.0,
            22.0
          ],
          "text": "s CL_MIDI_MON_SCENE_CONTEXT"
        }
      },
      {
        "box": {
          "id": "scene-recv",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            610.0,
            395.0,
            210.0,
            22.0
          ],
          "text": "r CL_MIDI_MON_SCENE_CONTEXT"
        }
      },
      {
        "box": {
          "id": "status-plus-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            35.0,
            575.0,
            32.0,
            22.0
          ],
          "text": "+ 1"
        }
      },
      {
        "box": {
          "id": "status-plus-ql1-cc",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            195.0,
            575.0,
            32.0,
            22.0
          ],
          "text": "+ 1"
        }
      },
      {
        "box": {
          "id": "status-plus-ql1-pgm",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            370.0,
            575.0,
            32.0,
            22.0
          ],
          "text": "+ 1"
        }
      },
      {
        "box": {
          "id": "status-label-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            35.0,
            700.0,
            150.0,
            22.0
          ],
          "text": "prepend MIDI · CL5 · Scène"
        }
      },
      {
        "box": {
          "id": "status-label-ql1-cc",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            195.0,
            700.0,
            175.0,
            22.0
          ],
          "text": "prepend MIDI · QL1 via CC · Scène"
        }
      },
      {
        "box": {
          "id": "status-label-ql1-pgm",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            370.0,
            700.0,
            185.0,
            22.0
          ],
          "text": "prepend MIDI · QL1 direct · Scène"
        }
      },
      {
        "box": {
          "id": "status-send",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            610.0,
            700.0,
            165.0,
            22.0
          ],
          "text": "s CL_MIDI_MON_STATUS"
        }
      },
      {
        "box": {
          "id": "status-recv",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            610.0,
            735.0,
            165.0,
            22.0
          ],
          "text": "r CL_MIDI_MON_STATUS"
        }
      },
      {
        "box": {
          "id": "status-set",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            785.0,
            735.0,
            72.0,
            22.0
          ],
          "text": "prepend set"
        }
      },
      {
        "box": {
          "id": "send-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            80.0,
            550.0,
            125.0,
            22.0
          ],
          "text": "s CL_MIDI_MON_CL5"
        }
      },
      {
        "box": {
          "id": "send-ql1-cc",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            215.0,
            550.0,
            145.0,
            22.0
          ],
          "text": "s CL_MIDI_MON_QL1"
        }
      },
      {
        "box": {
          "id": "send-ql1-pgm",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            370.0,
            550.0,
            155.0,
            22.0
          ],
          "text": "s CL_MIDI_MON_QL1"
        }
      },
      {
        "box": {
          "id": "send-cl5-program",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            80.0,
            575.0,
            180.0,
            22.0
          ],
          "text": "s CL_MIDI_MON_CL5_PROGRAM"
        }
      },
      {
        "box": {
          "id": "send-ql1-cc-program",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            270.0,
            575.0,
            180.0,
            22.0
          ],
          "text": "s CL_MIDI_MON_QL1_PROGRAM"
        }
      },
      {
        "box": {
          "id": "send-ql1-pgm-program",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            460.0,
            575.0,
            180.0,
            22.0
          ],
          "text": "s CL_MIDI_MON_QL1_PROGRAM"
        }
      },
      {
        "box": {
          "id": "request-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            35.0,
            780.0,
            185.0,
            22.0
          ],
          "text": "s CL_MIDI_MON_CL5_REQUEST"
        }
      },
      {
        "box": {
          "id": "request-ql1-cc",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            230.0,
            780.0,
            185.0,
            22.0
          ],
          "text": "s CL_MIDI_MON_QL1_REQUEST"
        }
      },
      {
        "box": {
          "id": "request-ql1-pgm",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            425.0,
            780.0,
            185.0,
            22.0
          ],
          "text": "s CL_MIDI_MON_QL1_REQUEST"
        }
      },
      {
        "box": {
          "id": "confirm-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            620.0,
            780.0,
            190.0,
            22.0
          ],
          "text": "s CL_MIDI_MON_CL5_CONFIRM"
        }
      },
      {
        "box": {
          "id": "confirm-ql1",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            820.0,
            780.0,
            190.0,
            22.0
          ],
          "text": "s CL_MIDI_MON_QL1_CONFIRM"
        }
      },
      {
        "box": {
          "id": "confirm-plus-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            620.0,
            700.0,
            32.0,
            22.0
          ],
          "text": "+ 1"
        }
      },
      {
        "box": {
          "id": "confirm-plus-ql1",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            820.0,
            700.0,
            32.0,
            22.0
          ],
          "text": "+ 1"
        }
      },
      {
        "box": {
          "id": "confirm-label-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            620.0,
            735.0,
            180.0,
            22.0
          ],
          "text": "prepend RETOUR · CL5 · Scène"
        }
      },
      {
        "box": {
          "id": "confirm-label-ql1",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            820.0,
            735.0,
            180.0,
            22.0
          ],
          "text": "prepend RETOUR · QL1 · Scène"
        }
      },
      {
        "box": {
          "id": "request-recv-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            35.0,
            825.0,
            185.0,
            22.0
          ],
          "text": "r CL_MIDI_MON_CL5_REQUEST"
        }
      },
      {
        "box": {
          "id": "confirm-recv-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            35.0,
            860.0,
            185.0,
            22.0
          ],
          "text": "r CL_MIDI_MON_CL5_CONFIRM"
        }
      },
      {
        "box": {
          "id": "confirmation-js-cl5",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 2,
          "patching_rect": [
            230.0,
            825.0,
            245.0,
            22.0
          ],
          "text": "js CLMidiConsoleConfirmation.js CL5 1"
        }
      },
      {
        "box": {
          "id": "request-recv-ql1",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            500.0,
            825.0,
            185.0,
            22.0
          ],
          "text": "r CL_MIDI_MON_QL1_REQUEST"
        }
      },
      {
        "box": {
          "id": "confirm-recv-ql1",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            500.0,
            860.0,
            185.0,
            22.0
          ],
          "text": "r CL_MIDI_MON_QL1_CONFIRM"
        }
      },
      {
        "box": {
          "id": "confirmation-js-ql1",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 2,
          "patching_rect": [
            695.0,
            825.0,
            245.0,
            22.0
          ],
          "text": "js CLMidiConsoleConfirmation.js QL1 1"
        }
      },
      {
        "box": {
          "id": "confirm-set-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            230.0,
            860.0,
            72.0,
            22.0
          ],
          "text": "prepend set"
        }
      },
      {
        "box": {
          "id": "confirm-set-ql1",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            695.0,
            860.0,
            72.0,
            22.0
          ],
          "text": "prepend set"
        }
      },
      {
        "box": {
          "id": "confirm-match-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            315.0,
            860.0,
            36.0,
            22.0
          ],
          "text": "sel 1"
        }
      },
      {
        "box": {
          "id": "confirm-match-ql1",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            780.0,
            860.0,
            36.0,
            22.0
          ],
          "text": "sel 1"
        }
      },
      {
        "box": {
          "id": "role-menu",
          "maxclass": "live.menu",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            330.0,
            250.0,
            170.0,
            22.0
          ],
          "parameter_enable": 1,
          "presentation": 1,
          "presentation_rect": [
            348.0,
            6.0,
            178.0,
            24.0
          ],
          "varname": "console_role",
          "items": [
            "CL5",
            "QL1 CC",
            "QL1 PGM",
            "CL5 retour",
            "QL1 retour"
          ],
          "saved_attribute_attributes": {
            "valueof": {
              "parameter_enum": [
                "CL5",
                "QL1 CC",
                "QL1 PGM",
                "CL5 retour",
                "QL1 retour"
              ],
              "parameter_longname": "Console surveillée",
              "parameter_shortname": "Console",
              "parameter_type": 2
            }
          }
        }
      },
      {
        "box": {
          "id": "role-index",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            330.0,
            285.0,
            30.0,
            22.0
          ],
          "text": "+ 1"
        }
      },
      {
        "box": {
          "id": "role-default",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            380.0,
            285.0,
            75.0,
            22.0
          ],
          "text": "loadmess 1"
        }
      },
      {
        "box": {
          "id": "role-loadbang",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            465.0,
            285.0,
            60.0,
            22.0
          ],
          "text": "loadbang"
        }
      },
      {
        "box": {
          "id": "role-defer",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            465.0,
            320.0,
            58.0,
            22.0
          ],
          "text": "deferlow"
        }
      },
      {
        "box": {
          "id": "recv-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            35.0,
            605.0,
            125.0,
            22.0
          ],
          "text": "r CL_MIDI_MON_CL5"
        }
      },
      {
        "box": {
          "id": "recv-ql1",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            195.0,
            605.0,
            145.0,
            22.0
          ],
          "text": "r CL_MIDI_MON_QL1"
        }
      },
      {
        "box": {
          "id": "recv-cl5-program",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            350.0,
            605.0,
            180.0,
            22.0
          ],
          "text": "r CL_MIDI_MON_CL5_PROGRAM"
        }
      },
      {
        "box": {
          "id": "recv-ql1-program",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            540.0,
            605.0,
            180.0,
            22.0
          ],
          "text": "r CL_MIDI_MON_QL1_PROGRAM"
        }
      },
      {
        "box": {
          "id": "set-cl5-program",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            350.0,
            630.0,
            72.0,
            22.0
          ],
          "text": "prepend set"
        }
      },
      {
        "box": {
          "id": "set-ql1-program",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            540.0,
            630.0,
            72.0,
            22.0
          ],
          "text": "prepend set"
        }
      },
      {
        "box": {
          "id": "route-empty-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            35.0,
            630.0,
            135.0,
            22.0
          ],
          "text": "route __CL_EMPTY__"
        }
      },
      {
        "box": {
          "id": "route-empty-ql1",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            195.0,
            630.0,
            135.0,
            22.0
          ],
          "text": "route __CL_EMPTY__"
        }
      },
      {
        "box": {
          "id": "empty-cl5",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            35.0,
            655.0,
            38.0,
            22.0
          ],
          "text": "set"
        }
      },
      {
        "box": {
          "id": "empty-ql1",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            195.0,
            655.0,
            38.0,
            22.0
          ],
          "text": "set"
        }
      },
      {
        "box": {
          "id": "set-cl5",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            35.0,
            640.0,
            72.0,
            22.0
          ],
          "text": "prepend set"
        }
      },
      {
        "box": {
          "id": "set-ql1",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            195.0,
            640.0,
            72.0,
            22.0
          ],
          "text": "prepend set"
        }
      },
      {
        "box": {
          "id": "floating-message",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            610.0,
            440.0,
            500.0,
            22.0
          ],
          "text": "window flags float nogrow close nozoom, window size 180 120 720 270, window exec, presentation 1, locked 1, front"
        }
      },
      {
        "box": {
          "id": "thispatcher",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 2,
          "patching_rect": [
            610.0,
            475.0,
            76.0,
            22.0
          ],
          "text": "thispatcher",
          "save": [
            "#N",
            "thispatcher",
            ";",
            "#Q",
            "end",
            ";"
          ]
        }
      },
      {
        "box": {
          "id": "auto-window-select",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            700.0,
            475.0,
            36.0,
            22.0
          ],
          "text": "sel 1"
        }
      },
      {
        "box": {
          "id": "auto-window-delay",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            745.0,
            475.0,
            58.0,
            22.0
          ],
          "text": "delay 800"
        }
      },
      {
        "box": {
          "id": "logo",
          "maxclass": "fpic",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            14.0,
            4.0,
            100.0,
            28.0
          ],
          "presentation": 1,
          "presentation_rect": [
            14.0,
            2.0,
            100.0,
            30.0
          ],
          "pic": "paradis_latin_logo.jpg",
          "autofit": 1,
          "forceaspect": 1,
          "ignoreclick": 1,
          "outlettype": [
            "jit_matrix"
          ]
        }
      },
      {
        "box": {
          "id": "title",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            122.0,
            8.0,
            215.0,
            20.0
          ],
          "presentation": 1,
          "presentation_rect": [
            122.0,
            7.0,
            215.0,
            20.0
          ],
          "text": "cl midi console monitor",
          "fontsize": 10.0,
          "fontface": 0,
          "textcolor": [
            0.56,
            0.59,
            0.65,
            1.0
          ]
        }
      },
      {
        "box": {
          "id": "midi-led",
          "maxclass": "button",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            326.0,
            9.0,
            16.0,
            16.0
          ],
          "presentation": 1,
          "presentation_rect": [
            326.0,
            9.0,
            16.0,
            16.0
          ],
          "bgcolor": [
            0.08,
            0.11,
            0.1,
            1.0
          ],
          "blinkcolor": [
            0.2,
            0.95,
            0.42,
            1.0
          ],
          "outlinecolor": [
            0.2,
            0.4,
            0.28,
            1.0
          ]
        }
      },
      {
        "box": {
          "id": "subtitle",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            16.0,
            35.0,
            430.0,
            18.0
          ],
          "presentation": 0,
          "presentation_rect": [
            14.0,
            33.0,
            360.0,
            18.0
          ],
          "text": "Transit MIDI transparent · Program Change uniquement",
          "fontsize": 10.0,
          "textcolor": [
            0.55,
            0.6,
            0.68,
            1.0
          ]
        }
      },
      {
        "box": {
          "id": "panel-cl5",
          "maxclass": "panel",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            12.0,
            39.0,
            516.0,
            29.0
          ],
          "presentation": 1,
          "presentation_rect": [
            12.0,
            38.0,
            516.0,
            29.0
          ],
          "bgcolor": [
            0.08,
            0.16,
            0.22,
            1.0
          ],
          "border": 1,
          "rounded": 8,
          "background": 1
        }
      },
      {
        "box": {
          "id": "panel-ql1",
          "maxclass": "panel",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            12.0,
            72.0,
            516.0,
            29.0
          ],
          "presentation": 1,
          "presentation_rect": [
            12.0,
            71.0,
            516.0,
            29.0
          ],
          "bgcolor": [
            0.12,
            0.16,
            0.2,
            1.0
          ],
          "border": 1,
          "rounded": 8,
          "background": 1
        }
      },
      {
        "box": {
          "id": "label-cl5",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            25.0,
            44.0,
            92.0,
            20.0
          ],
          "presentation": 1,
          "presentation_rect": [
            24.0,
            43.0,
            95.0,
            20.0
          ],
          "text": "CL5",
          "fontsize": 11.0,
          "textcolor": [
            0.35,
            0.72,
            1.0,
            1.0
          ]
        }
      },
      {
        "box": {
          "id": "label-ql1",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            25.0,
            77.0,
            92.0,
            20.0
          ],
          "presentation": 1,
          "presentation_rect": [
            24.0,
            76.0,
            95.0,
            20.0
          ],
          "text": "QL1",
          "fontsize": 11.0,
          "textcolor": [
            0.6,
            0.82,
            1.0,
            1.0
          ]
        }
      },
      {
        "box": {
          "id": "display-cl5",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            95.0,
            43.0,
            245.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            95.0,
            42.0,
            245.0,
            22.0
          ],
          "text": "—",
          "fontsize": 11.0,
          "fontface": 1,
          "textcolor": [
            0.35,
            0.72,
            1.0,
            1.0
          ],
          "bgcolor": [
            0.03,
            0.06,
            0.09,
            1.0
          ],
          "border": 0,
          "rounded": 5
        }
      },
      {
        "box": {
          "id": "display-ql1",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            95.0,
            76.0,
            245.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            95.0,
            75.0,
            245.0,
            22.0
          ],
          "text": "—",
          "fontsize": 11.0,
          "fontface": 1,
          "textcolor": [
            0.6,
            0.82,
            1.0,
            1.0
          ],
          "bgcolor": [
            0.04,
            0.07,
            0.1,
            1.0
          ],
          "border": 0,
          "rounded": 5
        }
      },
      {
        "box": {
          "id": "program-cl5",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            345.0,
            43.0,
            38.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            345.0,
            42.0,
            38.0,
            22.0
          ],
          "text": "—",
          "fontsize": 10.0,
          "fontface": 1,
          "textcolor": [
            0.95,
            0.78,
            0.38,
            1.0
          ],
          "bgcolor": [
            0.06,
            0.07,
            0.09,
            1.0
          ],
          "border": 0,
          "rounded": 5
        }
      },
      {
        "box": {
          "id": "program-ql1",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            345.0,
            76.0,
            38.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            345.0,
            75.0,
            38.0,
            22.0
          ],
          "text": "—",
          "fontsize": 10.0,
          "fontface": 1,
          "textcolor": [
            0.95,
            0.78,
            0.38,
            1.0
          ],
          "bgcolor": [
            0.06,
            0.07,
            0.09,
            1.0
          ],
          "border": 0,
          "rounded": 5
        }
      },
      {
        "box": {
          "id": "confirmation-cl5",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            390.0,
            43.0,
            122.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            390.0,
            42.0,
            123.0,
            22.0
          ],
          "text": "EN ATTENTE",
          "fontsize": 9.0,
          "fontface": 1,
          "textcolor": [
            0.95,
            0.72,
            0.32,
            1.0
          ],
          "bgcolor": [
            0.03,
            0.06,
            0.09,
            1.0
          ],
          "border": 0,
          "rounded": 5
        }
      },
      {
        "box": {
          "id": "confirmation-ql1",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            390.0,
            76.0,
            122.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            390.0,
            75.0,
            123.0,
            22.0
          ],
          "text": "EN ATTENTE",
          "fontsize": 9.0,
          "fontface": 1,
          "textcolor": [
            0.35,
            0.92,
            0.55,
            1.0
          ],
          "bgcolor": [
            0.04,
            0.07,
            0.1,
            1.0
          ],
          "border": 0,
          "rounded": 5
        }
      },
      {
        "box": {
          "id": "midi-status",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            14.0,
            106.0,
            286.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            14.0,
            104.0,
            286.0,
            20.0
          ],
          "text": "MIDI · en attente",
          "fontsize": 9.0,
          "textcolor": [
            0.95,
            0.72,
            0.32,
            1.0
          ],
          "bgcolor": [
            0.04,
            0.05,
            0.07,
            1.0
          ],
          "border": 0
        }
      },
      {
        "box": {
          "id": "floating-button",
          "maxclass": "textbutton",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            310.0,
            106.0,
            75.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            310.0,
            104.0,
            75.0,
            20.0
          ],
          "text": "DÉTACHER",
          "fontsize": 8.0,
          "bgcolor": [
            0.16,
            0.26,
            0.38,
            1.0
          ]
        }
      },
      {
        "box": {
          "id": "auto-window",
          "maxclass": "live.toggle",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            395.0,
            106.0,
            20.0,
            20.0
          ],
          "presentation": 1,
          "presentation_rect": [
            395.0,
            104.0,
            20.0,
            20.0
          ],
          "parameter_enable": 1,
          "varname": "auto_open_monitor",
          "saved_attribute_attributes": {
            "valueof": {
              "parameter_longname": "Ouvrir automatiquement le moniteur",
              "parameter_shortname": "Auto fenêtre",
              "parameter_type": 0,
              "parameter_mmin": 0.0,
              "parameter_mmax": 1.0,
              "parameter_initial": [
                0.0
              ],
              "parameter_initial_enable": 1,
              "parameter_invisible": 1
            }
          }
        }
      },
      {
        "box": {
          "id": "auto-window-label",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            417.0,
            106.0,
            43.0,
            18.0
          ],
          "presentation": 1,
          "presentation_rect": [
            417.0,
            105.0,
            43.0,
            18.0
          ],
          "text": "AUTO",
          "fontsize": 8.0,
          "textcolor": [
            0.58,
            0.64,
            0.72,
            1.0
          ]
        }
      },
      {
        "box": {
          "id": "clear-button",
          "maxclass": "textbutton",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            465.0,
            106.0,
            62.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            465.0,
            104.0,
            62.0,
            20.0
          ],
          "text": "EFFACER",
          "fontsize": 8.0
        }
      },
      {
        "box": {
          "id": "clear-message",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            455.0,
            675.0,
            48.0,
            22.0
          ],
          "text": "set —"
        }
      }
    ],
    "lines": [
      {
        "patchline": {
          "source": [
            "midi-in",
            0
          ],
          "destination": [
            "midi-out",
            0
          ],
          "order": 0
        }
      },
      {
        "patchline": {
          "source": [
            "midi-in",
            0
          ],
          "destination": [
            "midi-parse",
            0
          ],
          "order": 1
        }
      },
      {
        "patchline": {
          "source": [
            "midi-parse",
            3
          ],
          "destination": [
            "event-gate",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "role-menu",
            0
          ],
          "destination": [
            "role-index",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "role-index",
            0
          ],
          "destination": [
            "event-gate",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "role-default",
            0
          ],
          "destination": [
            "event-gate",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "role-loadbang",
            0
          ],
          "destination": [
            "role-defer",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "role-defer",
            0
          ],
          "destination": [
            "role-menu",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "role-defer",
            0
          ],
          "destination": [
            "lookup-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "role-defer",
            0
          ],
          "destination": [
            "lookup-ql1-cc",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "role-defer",
            0
          ],
          "destination": [
            "lookup-ql1-pgm",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            0
          ],
          "destination": [
            "lookup-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            0
          ],
          "destination": [
            "midi-led",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            0
          ],
          "destination": [
            "status-plus-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "status-plus-cl5",
            0
          ],
          "destination": [
            "status-label-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "status-label-cl5",
            0
          ],
          "destination": [
            "status-send",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "lookup-cl5",
            0
          ],
          "destination": [
            "send-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "lookup-cl5",
            1
          ],
          "destination": [
            "send-cl5-program",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            0
          ],
          "destination": [
            "request-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            1
          ],
          "destination": [
            "lookup-ql1-cc",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            1
          ],
          "destination": [
            "midi-led",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            1
          ],
          "destination": [
            "status-plus-ql1-cc",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "status-plus-ql1-cc",
            0
          ],
          "destination": [
            "status-label-ql1-cc",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "status-label-ql1-cc",
            0
          ],
          "destination": [
            "status-send",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "lookup-ql1-cc",
            0
          ],
          "destination": [
            "send-ql1-cc",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "lookup-ql1-cc",
            1
          ],
          "destination": [
            "send-ql1-cc-program",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            1
          ],
          "destination": [
            "request-ql1-cc",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            2
          ],
          "destination": [
            "lookup-ql1-pgm",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            2
          ],
          "destination": [
            "midi-led",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            2
          ],
          "destination": [
            "status-plus-ql1-pgm",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "status-plus-ql1-pgm",
            0
          ],
          "destination": [
            "status-label-ql1-pgm",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "status-label-ql1-pgm",
            0
          ],
          "destination": [
            "status-send",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "lookup-ql1-pgm",
            0
          ],
          "destination": [
            "send-ql1-pgm",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "lookup-ql1-pgm",
            1
          ],
          "destination": [
            "send-ql1-pgm-program",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            2
          ],
          "destination": [
            "request-ql1-pgm",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            3
          ],
          "destination": [
            "confirm-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            3
          ],
          "destination": [
            "midi-led",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            3
          ],
          "destination": [
            "confirm-plus-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirm-plus-cl5",
            0
          ],
          "destination": [
            "confirm-label-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirm-label-cl5",
            0
          ],
          "destination": [
            "status-send",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            4
          ],
          "destination": [
            "confirm-ql1",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            4
          ],
          "destination": [
            "midi-led",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "event-gate",
            4
          ],
          "destination": [
            "confirm-plus-ql1",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirm-plus-ql1",
            0
          ],
          "destination": [
            "confirm-label-ql1",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirm-label-ql1",
            0
          ],
          "destination": [
            "status-send",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "request-recv-cl5",
            0
          ],
          "destination": [
            "confirmation-js-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirm-recv-cl5",
            0
          ],
          "destination": [
            "confirmation-js-cl5",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirmation-js-cl5",
            0
          ],
          "destination": [
            "confirm-set-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirm-set-cl5",
            0
          ],
          "destination": [
            "confirmation-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirmation-js-cl5",
            1
          ],
          "destination": [
            "confirm-match-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirm-match-cl5",
            0
          ],
          "destination": [
            "midi-led",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "request-recv-ql1",
            0
          ],
          "destination": [
            "confirmation-js-ql1",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirm-recv-ql1",
            0
          ],
          "destination": [
            "confirmation-js-ql1",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirmation-js-ql1",
            0
          ],
          "destination": [
            "confirm-set-ql1",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirm-set-ql1",
            0
          ],
          "destination": [
            "confirmation-ql1",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirmation-js-ql1",
            1
          ],
          "destination": [
            "confirm-match-ql1",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "confirm-match-ql1",
            0
          ],
          "destination": [
            "midi-led",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "status-recv",
            0
          ],
          "destination": [
            "status-set",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "status-set",
            0
          ],
          "destination": [
            "midi-status",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "recv-cl5",
            0
          ],
          "destination": [
            "route-empty-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route-empty-cl5",
            0
          ],
          "destination": [
            "empty-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "empty-cl5",
            0
          ],
          "destination": [
            "display-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route-empty-cl5",
            1
          ],
          "destination": [
            "set-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "set-cl5",
            0
          ],
          "destination": [
            "display-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "recv-ql1",
            0
          ],
          "destination": [
            "route-empty-ql1",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route-empty-ql1",
            0
          ],
          "destination": [
            "empty-ql1",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "empty-ql1",
            0
          ],
          "destination": [
            "display-ql1",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route-empty-ql1",
            1
          ],
          "destination": [
            "set-ql1",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "set-ql1",
            0
          ],
          "destination": [
            "display-ql1",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "recv-cl5-program",
            0
          ],
          "destination": [
            "set-cl5-program",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "set-cl5-program",
            0
          ],
          "destination": [
            "program-cl5",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "recv-ql1-program",
            0
          ],
          "destination": [
            "set-ql1-program",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "set-ql1-program",
            0
          ],
          "destination": [
            "program-ql1",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "clear-button",
            0
          ],
          "destination": [
            "clear-message",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "clear-message",
            0
          ],
          "destination": [
            "display-cl5",
            0
          ],
          "order": 0
        }
      },
      {
        "patchline": {
          "source": [
            "clear-message",
            0
          ],
          "destination": [
            "display-ql1",
            0
          ],
          "order": 1
        }
      },
      {
        "patchline": {
          "source": [
            "clear-message",
            0
          ],
          "destination": [
            "program-cl5",
            0
          ],
          "order": 2
        }
      },
      {
        "patchline": {
          "source": [
            "clear-message",
            0
          ],
          "destination": [
            "program-ql1",
            0
          ],
          "order": 3
        }
      },
      {
        "patchline": {
          "source": [
            "floating-button",
            0
          ],
          "destination": [
            "floating-message",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "auto-window",
            0
          ],
          "destination": [
            "auto-window-select",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "auto-window-select",
            0
          ],
          "destination": [
            "auto-window-delay",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "auto-window-delay",
            0
          ],
          "destination": [
            "floating-message",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "floating-message",
            0
          ],
          "destination": [
            "thispatcher",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "scene-udp",
            0
          ],
          "destination": [
            "scene-route",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "scene-route",
            0
          ],
          "destination": [
            "scene-prepend",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "scene-route",
            1
          ],
          "destination": [
            "scene-reset",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "scene-prepend",
            0
          ],
          "destination": [
            "scene-send",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "scene-reset",
            0
          ],
          "destination": [
            "scene-send",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "scene-recv",
            0
          ],
          "destination": [
            "lookup-cl5",
            0
          ],
          "order": 0
        }
      },
      {
        "patchline": {
          "source": [
            "scene-recv",
            0
          ],
          "destination": [
            "lookup-ql1-cc",
            0
          ],
          "order": 1
        }
      },
      {
        "patchline": {
          "source": [
            "scene-recv",
            0
          ],
          "destination": [
            "lookup-ql1-pgm",
            0
          ],
          "order": 2
        }
      }
    ],
    "dependency_cache": [
      {
        "name": "CLMidiConsoleDisplay.js",
        "bootpath": ".",
        "patcherrelativepath": ".",
        "type": "TEXT",
        "implicit": 1
      },
      {
        "name": "CLMidiConsoleConfirmation.js",
        "bootpath": ".",
        "patcherrelativepath": ".",
        "type": "TEXT",
        "implicit": 1
      },
      {
        "name": "paradis_latin_logo.jpg",
        "bootpath": ".",
        "patcherrelativepath": ".",
        "type": "JPEG",
        "implicit": 1
      }
    ]
  }
}
