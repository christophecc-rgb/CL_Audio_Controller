{
  "patcher": {
    "fileversion": 1,
    "appversion": {
      "major": 8,
      "minor": 6,
      "revision": 0,
      "architecture": "x64",
      "modernui": 1
    },
    "classnamespace": "box",
    "rect": [
      100.0,
      100.0,
      1400.0,
      780.0
    ],
    "bglocked": 0,
    "openinpresentation": 0,
    "default_fontsize": 12.0,
    "default_fontface": 0,
    "default_fontname": "Arial",
    "gridonopen": 1,
    "gridsize": [
      15.0,
      15.0
    ],
    "toolbarvisible": 1,
    "boxes": [
      {
        "box": {
          "id": "title",
          "maxclass": "comment",
          "patching_rect": [
            40.0,
            25.0,
            1200.0,
            22.0
          ],
          "text": "XFADER OSC BRIDGE v8 \u2014 TRUE OSC. Put this Max Audio Effect on MASTER. UDP 9001: /xfader/a /xfader/center /xfader/b"
        }
      },
      {
        "box": {
          "id": "note",
          "maxclass": "comment",
          "patching_rect": [
            40.0,
            55.0,
            1200.0,
            22.0
          ],
          "text": "Manual test: lock patcher, click -1 / 0 / 1. If needed click the black button connected to live.path."
        }
      },
      {
        "box": {
          "id": "plug",
          "maxclass": "newobj",
          "patching_rect": [
            40.0,
            110.0,
            70.0,
            22.0
          ],
          "text": "plugin~"
        }
      },
      {
        "box": {
          "id": "plugout",
          "maxclass": "newobj",
          "patching_rect": [
            40.0,
            175.0,
            75.0,
            22.0
          ],
          "text": "plugout~"
        }
      },
      {
        "box": {
          "id": "lb",
          "maxclass": "newobj",
          "patching_rect": [
            520.0,
            100.0,
            80.0,
            22.0
          ],
          "text": "loadbang"
        }
      },
      {
        "box": {
          "id": "defer",
          "maxclass": "newobj",
          "patching_rect": [
            520.0,
            135.0,
            80.0,
            22.0
          ],
          "text": "deferlow"
        }
      },
      {
        "box": {
          "id": "delay",
          "maxclass": "newobj",
          "patching_rect": [
            520.0,
            170.0,
            85.0,
            22.0
          ],
          "text": "delay 1500"
        }
      },
      {
        "box": {
          "id": "bang",
          "maxclass": "button",
          "patching_rect": [
            705.0,
            170.0,
            24.0,
            24.0
          ]
        }
      },
      {
        "box": {
          "id": "lp",
          "maxclass": "newobj",
          "patching_rect": [
            520.0,
            210.0,
            360.0,
            22.0
          ],
          "text": "live.path live_set master_track mixer_device crossfader"
        }
      },
      {
        "box": {
          "id": "printid",
          "maxclass": "newobj",
          "patching_rect": [
            900.0,
            210.0,
            130.0,
            22.0
          ],
          "text": "print XFADER_ID"
        }
      },
      {
        "box": {
          "id": "idreg",
          "maxclass": "newobj",
          "patching_rect": [
            520.0,
            250.0,
            60.0,
            22.0
          ],
          "text": "zl reg"
        }
      },
      {
        "box": {
          "id": "udp",
          "maxclass": "newobj",
          "patching_rect": [
            40.0,
            300.0,
            120.0,
            22.0
          ],
          "text": "udpreceive 9001"
        }
      },
      {
        "box": {
          "id": "printudp",
          "maxclass": "newobj",
          "patching_rect": [
            180.0,
            265.0,
            130.0,
            22.0
          ],
          "text": "print UDP_IN"
        }
      },
      {
        "box": {
          "id": "route",
          "maxclass": "newobj",
          "patching_rect": [
            180.0,
            300.0,
            380.0,
            22.0
          ],
          "text": "route /xfader/a /xfader/center /xfader/b /xfader/value"
        }
      },
      {
        "box": {
          "id": "ua",
          "maxclass": "message",
          "patching_rect": [
            180.0,
            345.0,
            45.0,
            22.0
          ],
          "text": "-1."
        }
      },
      {
        "box": {
          "id": "uc",
          "maxclass": "message",
          "patching_rect": [
            250.0,
            345.0,
            45.0,
            22.0
          ],
          "text": "0."
        }
      },
      {
        "box": {
          "id": "ub",
          "maxclass": "message",
          "patching_rect": [
            320.0,
            345.0,
            45.0,
            22.0
          ],
          "text": "1."
        }
      },
      {
        "box": {
          "id": "manual",
          "maxclass": "comment",
          "patching_rect": [
            40.0,
            410.0,
            180.0,
            22.0
          ],
          "text": "Manual test buttons"
        }
      },
      {
        "box": {
          "id": "ma",
          "maxclass": "message",
          "patching_rect": [
            40.0,
            440.0,
            55.0,
            24.0
          ],
          "text": "-1."
        }
      },
      {
        "box": {
          "id": "mc",
          "maxclass": "message",
          "patching_rect": [
            110.0,
            440.0,
            55.0,
            24.0
          ],
          "text": "0."
        }
      },
      {
        "box": {
          "id": "mb",
          "maxclass": "message",
          "patching_rect": [
            180.0,
            440.0,
            55.0,
            24.0
          ],
          "text": "1."
        }
      },
      {
        "box": {
          "id": "clip",
          "maxclass": "newobj",
          "patching_rect": [
            520.0,
            340.0,
            80.0,
            22.0
          ],
          "text": "clip -1. 1."
        }
      },
      {
        "box": {
          "id": "trig",
          "maxclass": "newobj",
          "patching_rect": [
            520.0,
            380.0,
            70.0,
            22.0
          ],
          "text": "t b b f"
        }
      },
      {
        "box": {
          "id": "f",
          "maxclass": "newobj",
          "patching_rect": [
            660.0,
            420.0,
            45.0,
            22.0
          ],
          "text": "f"
        }
      },
      {
        "box": {
          "id": "dval",
          "maxclass": "newobj",
          "patching_rect": [
            660.0,
            460.0,
            75.0,
            22.0
          ],
          "text": "delay 80"
        }
      },
      {
        "box": {
          "id": "sig",
          "maxclass": "newobj",
          "patching_rect": [
            660.0,
            500.0,
            70.0,
            22.0
          ],
          "text": "sig~ 0."
        }
      },
      {
        "box": {
          "id": "remote",
          "maxclass": "newobj",
          "patching_rect": [
            660.0,
            545.0,
            100.0,
            22.0
          ],
          "text": "live.remote~"
        }
      },
      {
        "box": {
          "id": "pval",
          "maxclass": "newobj",
          "patching_rect": [
            780.0,
            500.0,
            135.0,
            22.0
          ],
          "text": "print XFADER_SENT"
        }
      },
      {
        "box": {
          "id": "rel",
          "maxclass": "newobj",
          "patching_rect": [
            790.0,
            420.0,
            80.0,
            22.0
          ],
          "text": "delay 450"
        }
      },
      {
        "box": {
          "id": "id0",
          "maxclass": "message",
          "patching_rect": [
            790.0,
            460.0,
            55.0,
            22.0
          ],
          "text": "id 0"
        }
      },
      {
        "box": {
          "id": "pulse",
          "maxclass": "comment",
          "patching_rect": [
            780.0,
            545.0,
            620.0,
            22.0
          ],
          "text": "Pulse: recall stored ID \u2192 attach live.remote~ \u2192 after 80 ms send value \u2192 after 450 ms release id 0."
        }
      },
      {
        "box": {
          "id": "value_note",
          "maxclass": "comment",
          "text": "Slider continu: /xfader/value <float -1..1> va directement vers clip puis live.remote~.",
          "patching_rect": [
            580.0,
            300.0,
            620.0,
            22.0
          ]
        }
      }
    ],
    "lines": [
      {
        "patchline": {
          "source": [
            "plug",
            0
          ],
          "destination": [
            "plugout",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "plug",
            1
          ],
          "destination": [
            "plugout",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "lb",
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
            "delay",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "delay",
            0
          ],
          "destination": [
            "lp",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "bang",
            0
          ],
          "destination": [
            "lp",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "lp",
            0
          ],
          "destination": [
            "printid",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "lp",
            0
          ],
          "destination": [
            "idreg",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "udp",
            0
          ],
          "destination": [
            "printudp",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "udp",
            0
          ],
          "destination": [
            "route",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route",
            0
          ],
          "destination": [
            "ua",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route",
            1
          ],
          "destination": [
            "uc",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route",
            2
          ],
          "destination": [
            "ub",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "ua",
            0
          ],
          "destination": [
            "clip",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "uc",
            0
          ],
          "destination": [
            "clip",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "ub",
            0
          ],
          "destination": [
            "clip",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "ma",
            0
          ],
          "destination": [
            "clip",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "mc",
            0
          ],
          "destination": [
            "clip",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "mb",
            0
          ],
          "destination": [
            "clip",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "clip",
            0
          ],
          "destination": [
            "trig",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "trig",
            2
          ],
          "destination": [
            "f",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "trig",
            1
          ],
          "destination": [
            "idreg",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "idreg",
            0
          ],
          "destination": [
            "remote",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "trig",
            0
          ],
          "destination": [
            "dval",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "dval",
            0
          ],
          "destination": [
            "f",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "f",
            0
          ],
          "destination": [
            "sig",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "f",
            0
          ],
          "destination": [
            "pval",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "sig",
            0
          ],
          "destination": [
            "remote",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "trig",
            0
          ],
          "destination": [
            "rel",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "rel",
            0
          ],
          "destination": [
            "id0",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "id0",
            0
          ],
          "destination": [
            "remote",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "route",
            3
          ],
          "destination": [
            "clip",
            0
          ]
        }
      }
    ]
  }
}