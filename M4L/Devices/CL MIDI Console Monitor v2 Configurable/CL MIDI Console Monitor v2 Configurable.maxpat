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
      70,
      70,
      900,
      600
    ],
    "openinpresentation": 1,
    "devicewidth": 540.0,
    "description": "Configurable per-console MIDI Program Change monitor",
    "digest": "Dynamic Live track selection with persistent console configuration",
    "title": "CL MIDI Console Monitor v2 Configurable",
    "project": {
      "version": 1,
      "creationdate": 0,
      "modificationdate": 0,
      "viewrect": [
        0,
        0,
        300,
        500
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
      1
    ],
    "boxes": [
      {
        "box": {
          "id": "midi-in",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            30,
            260,
            45,
            22
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
            30,
            330,
            50,
            22
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
            100,
            330,
            65,
            22
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
          "id": "resolver",
          "maxclass": "newobj",
          "numinlets": 4,
          "numoutlets": 4,
          "patching_rect": [
            210,
            330,
            260,
            22
          ],
          "text": "js CLMidiConsoleConfigurable.js"
        }
      },
      {
        "box": {
          "id": "loadbang",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            490,
            330,
            60,
            22
          ],
          "text": "loadbang"
        }
      },
      {
        "box": {
          "id": "defer",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            560,
            330,
            58,
            22
          ],
          "text": "delay 350"
        }
      },
      {
        "box": {
          "id": "refresh",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            630,
            330,
            54,
            22
          ],
          "text": "refresh"
        }
      },
      {
        "box": {
          "id": "source-menu",
          "maxclass": "umenu",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            190,
            8,
            330,
            24
          ],
          "presentation": 1,
          "presentation_rect": [
            190,
            8,
            330,
            24
          ],
          "varname": "v2_source_track",
          "items": [
            "Automatique"
          ]
        }
      },
      {
        "box": {
          "id": "console-name",
          "maxclass": "textedit",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            65,
            43,
            190,
            24
          ],
          "presentation": 1,
          "presentation_rect": [
            65,
            43,
            190,
            24
          ],
          "varname": "v2_console_name",
          "text": "Console",
          "rounded": 5
        }
      },
      {
        "box": {
          "id": "console-label",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            14,
            46,
            48,
            18
          ],
          "presentation": 1,
          "presentation_rect": [
            14,
            46,
            48,
            18
          ],
          "text": "Nom",
          "fontsize": 9.0
        }
      },
      {
        "box": {
          "id": "route-text",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            210,
            375,
            65,
            22
          ],
          "text": "route text"
        }
      },
      {
        "box": {
          "id": "mode-menu",
          "maxclass": "live.menu",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            270,
            43,
            120,
            24
          ],
          "presentation": 1,
          "presentation_rect": [
            270,
            43,
            120,
            24
          ],
          "varname": "v2_console_mode",
          "items": [
            "Commande",
            "Retour"
          ],
          "parameter_enable": 1,
          "saved_attribute_attributes": {
            "valueof": {
              "parameter_enum": [
                "Commande",
                "Retour"
              ],
              "parameter_longname": "Mode console",
              "parameter_shortname": "Mode",
              "parameter_type": 2
            }
          }
        }
      },
      {
        "box": {
          "id": "slot-menu",
          "maxclass": "live.menu",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            400,
            43,
            120,
            24
          ],
          "presentation": 1,
          "presentation_rect": [
            400,
            43,
            120,
            24
          ],
          "varname": "v2_console_slot",
          "items": [
            "Console 1",
            "Console 2",
            "Console 3",
            "Console 4",
            "Console 5",
            "Console 6"
          ],
          "parameter_enable": 1,
          "saved_attribute_attributes": {
            "valueof": {
              "parameter_enum": [
                "Console 1",
                "Console 2",
                "Console 3",
                "Console 4",
                "Console 5",
                "Console 6"
              ],
              "parameter_longname": "Emplacement console",
              "parameter_shortname": "Console",
              "parameter_type": 2
            }
          }
        }
      },
      {
        "box": {
          "id": "logo",
          "maxclass": "fpic",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            14,
            5,
            160,
            30
          ],
          "presentation": 1,
          "presentation_rect": [
            14,
            5,
            160,
            30
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
          "id": "panel",
          "maxclass": "panel",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            12,
            76,
            516,
            60
          ],
          "presentation": 1,
          "presentation_rect": [
            12,
            76,
            516,
            60
          ],
          "bgcolor": [
            0.04,
            0.08,
            0.12,
            1
          ],
          "border": 1,
          "rounded": 8,
          "background": 1
        }
      },
      {
        "box": {
          "id": "title",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            24,
            87,
            350,
            24
          ],
          "presentation": 1,
          "presentation_rect": [
            24,
            87,
            350,
            24
          ],
          "text": "—",
          "fontsize": 12.0,
          "fontface": 1,
          "textcolor": [
            0.35,
            0.72,
            1,
            1
          ],
          "bgcolor": [
            0.03,
            0.05,
            0.08,
            1
          ],
          "border": 0
        }
      },
      {
        "box": {
          "id": "program",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            385,
            87,
            125,
            24
          ],
          "presentation": 1,
          "presentation_rect": [
            385,
            87,
            125,
            24
          ],
          "text": "—",
          "fontsize": 11.0,
          "fontface": 1,
          "textcolor": [
            0.95,
            0.75,
            0.3,
            1
          ],
          "bgcolor": [
            0.03,
            0.05,
            0.08,
            1
          ],
          "border": 0
        }
      },
      {
        "box": {
          "id": "status",
          "maxclass": "message",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            24,
            112,
            486,
            20
          ],
          "presentation": 1,
          "presentation_rect": [
            24,
            112,
            486,
            20
          ],
          "text": "Sélectionnez une piste MIDI",
          "fontsize": 9.0,
          "textcolor": [
            0.6,
            0.7,
            0.82,
            1
          ],
          "bgcolor": [
            0.03,
            0.05,
            0.08,
            1
          ],
          "border": 0
        }
      },
      {
        "box": {
          "id": "autopattr",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "patching_rect": [
            700,
            330,
            60,
            22
          ],
          "text": "autopattr"
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
            "resolver",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "source-menu",
            0
          ],
          "destination": [
            "resolver",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "resolver",
            0
          ],
          "destination": [
            "source-menu",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "console-name",
            0
          ],
          "destination": [
            "route-text",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route-text",
            0
          ],
          "destination": [
            "resolver",
            2
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "loadbang",
            0
          ],
          "destination": [
            "defer",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "defer",
            0
          ],
          "destination": [
            "refresh",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "refresh",
            0
          ],
          "destination": [
            "resolver",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "resolver",
            1
          ],
          "destination": [
            "title",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "resolver",
            2
          ],
          "destination": [
            "program",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "resolver",
            3
          ],
          "destination": [
            "status",
            0
          ]
        }
      }
    ],
    "dependency_cache": [
      {
        "name": "CLMidiConsoleConfigurable.js",
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
