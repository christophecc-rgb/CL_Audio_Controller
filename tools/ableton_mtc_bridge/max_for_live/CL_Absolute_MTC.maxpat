{
  "patcher": {
    "fileversion": 1,
    "appversion": {
      "major": 9,
      "minor": 0,
      "revision": 0,
      "architecture": "arm64",
      "modernui": 1
    },
    "classnamespace": "box",
    "rect": [100.0, 100.0, 760.0, 430.0],
    "openinpresentation": 1,
    "boxes": [
      {
        "box": {
          "id": "obj-title",
          "maxclass": "comment",
          "text": "CL Absolute MTC → Logic",
          "patching_rect": [30.0, 20.0, 210.0, 22.0],
          "presentation": 1,
          "presentation_rect": [20.0, 18.0, 210.0, 22.0]
        }
      },
      {
        "box": {
          "id": "obj-info",
          "maxclass": "comment",
          "text": "Live API SMPTE 25 fps → UDP 127.0.0.1:20809",
          "patching_rect": [30.0, 48.0, 320.0, 22.0],
          "presentation": 1,
          "presentation_rect": [20.0, 44.0, 320.0, 22.0]
        }
      },
      {
        "box": {
          "id": "obj-toggle",
          "maxclass": "toggle",
          "patching_rect": [30.0, 95.0, 24.0, 24.0],
          "presentation": 1,
          "presentation_rect": [20.0, 78.0, 24.0, 24.0]
        }
      },
      {
        "box": {
          "id": "obj-onlabel",
          "maxclass": "comment",
          "text": "ENVOI",
          "patching_rect": [62.0, 97.0, 60.0, 22.0],
          "presentation": 1,
          "presentation_rect": [52.0, 80.0, 60.0, 22.0]
        }
      },
      {
        "box": {
          "id": "obj-loadbang",
          "maxclass": "loadbang",
          "patching_rect": [30.0, 145.0, 60.0, 22.0]
        }
      },
      {
        "box": {
          "id": "obj-one",
          "maxclass": "message",
          "text": "1",
          "patching_rect": [105.0, 145.0, 35.0, 22.0]
        }
      },
      {
        "box": {
          "id": "obj-metro",
          "maxclass": "newobj",
          "text": "metro 40",
          "patching_rect": [30.0, 190.0, 65.0, 22.0]
        }
      },
      {
        "box": {
          "id": "obj-get",
          "maxclass": "message",
          "text": "call get_current_smpte_song_time 2",
          "patching_rect": [30.0, 230.0, 220.0, 22.0]
        }
      },
      {
        "box": {
          "id": "obj-path",
          "maxclass": "newobj",
          "text": "live.path live_set",
          "patching_rect": [330.0, 145.0, 120.0, 22.0]
        }
      },
      {
        "box": {
          "id": "obj-object",
          "maxclass": "newobj",
          "text": "live.object",
          "patching_rect": [330.0, 230.0, 80.0, 22.0]
        }
      },
      {
        "box": {
          "id": "obj-route",
          "maxclass": "newobj",
          "text": "route get_current_smpte_song_time",
          "patching_rect": [330.0, 275.0, 70.0, 22.0]
        }
      },
      {
        "box": {
          "id": "obj-tosymbol",
          "maxclass": "newobj",
          "text": "tosymbol",
          "patching_rect": [330.0, 315.0, 65.0, 22.0]
        }
      },
      {
        "box": {
          "id": "obj-display",
          "maxclass": "message",
          "text": "00:00:00:00",
          "patching_rect": [420.0, 315.0, 115.0, 22.0],
          "presentation": 1,
          "presentation_rect": [120.0, 78.0, 120.0, 24.0]
        }
      },
      {
        "box": {
          "id": "obj-udp",
          "maxclass": "newobj",
          "text": "udpsend 127.0.0.1 20809",
          "patching_rect": [330.0, 360.0, 165.0, 22.0]
        }
      }
    ],
    "lines": [
      {
        "patchline": {
          "source": ["obj-loadbang", 0],
          "destination": ["obj-one", 0]
        }
      },
      {
        "patchline": {
          "source": ["obj-one", 0],
          "destination": ["obj-toggle", 0]
        }
      },
      {
        "patchline": {
          "source": ["obj-toggle", 0],
          "destination": ["obj-metro", 0]
        }
      },
      {
        "patchline": {
          "source": ["obj-metro", 0],
          "destination": ["obj-get", 0]
        }
      },
      {
        "patchline": {
          "source": ["obj-get", 0],
          "destination": ["obj-object", 0]
        }
      },
      {
        "patchline": {
          "source": ["obj-loadbang", 0],
          "destination": ["obj-path", 0]
        }
      },
      {
        "patchline": {
          "source": ["obj-path", 0],
          "destination": ["obj-object", 1]
        }
      },
      {
        "patchline": {
          "source": ["obj-object", 0],
          "destination": ["obj-route", 0]
        }
      },
      {
        "patchline": {
          "source": ["obj-route", 0],
          "destination": ["obj-tosymbol", 0]
        }
      },
      {
        "patchline": {
          "source": ["obj-tosymbol", 0],
          "destination": ["obj-display", 1]
        }
      },
      {
        "patchline": {
          "source": ["obj-tosymbol", 0],
          "destination": ["obj-udp", 0]
        }
      }
    ]
  }
}
