{
  "patcher": {
    "fileversion": 1,
    "appversion": {
      "major": 9,
      "minor": 1,
      "revision": 5,
      "architecture": "x64",
      "modernui": 1
    },
    "classnamespace": "box",
    "rect": [
      2494.0,
      -484.0,
      631.0,
      430.0
    ],
    "openrect": [
      0.0,
      0.0,
      430.0,
      145.0
    ],
    "openrectmode": 0,
    "default_fontsize": 10.0,
    "default_fontname": "Arial Bold",
    "gridsize": [
      8.0,
      8.0
    ],
    "boxanimatetime": 500,
    "boxes": [
      {
        "box": {
          "id": "obj-pl-logo",
          "maxclass": "fpic",
          "numinlets": 1,
          "numoutlets": 1,
          "outlettype": [
            "jit_matrix"
          ],
          "patching_rect": [
            10.0,
            8.0,
            128.0,
            39.0
          ],
          "presentation": 1,
          "presentation_rect": [
            8.0,
            6.0,
            128.0,
            39.0
          ],
          "pic": "paradis latin.jpg",
          "autofit": 1
        }
      },
      {
        "box": {
          "fontsize": 10.0,
          "id": "obj-info",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            30.0,
            48.0,
            320.0,
            18.0
          ],
          "presentation": 1,
          "presentation_rect": [
            145.0,
            8.0,
            205.0,
            18.0
          ],
          "text": "CL AUDIO  •  MTC 25 fps  •  48 kHz"
        }
      },
      {
        "box": {
          "id": "obj-toggle",
          "maxclass": "toggle",
          "numinlets": 1,
          "numoutlets": 1,
          "outlettype": [
            "int"
          ],
          "parameter_enable": 0,
          "patching_rect": [
            30.0,
            95.0,
            24.0,
            24.0
          ],
          "presentation": 1,
          "presentation_rect": [
            353.0,
            7.0,
            20.0,
            20.0
          ]
        }
      },
      {
        "box": {
          "id": "obj-onlabel",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            62.0,
            97.0,
            60.0,
            18.0
          ],
          "presentation": 1,
          "presentation_rect": [
            378.0,
            8.0,
            45.0,
            18.0
          ],
          "text": "ENVOI"
        }
      },
      {
        "box": {
          "id": "obj-one",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            105.0,
            176.0,
            35.0,
            20.0
          ],
          "text": "1"
        }
      },
      {
        "box": {
          "id": "obj-metro",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            "bang"
          ],
          "patching_rect": [
            30.0,
            190.0,
            65.0,
            20.0
          ],
          "text": "metro 40"
        }
      },
      {
        "box": {
          "id": "obj-get",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            30.0,
            230.0,
            220.0,
            20.0
          ],
          "text": "call get_current_smpte_song_time 2"
        }
      },
      {
        "box": {
          "id": "obj-path",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 3,
          "outlettype": [
            "",
            "",
            ""
          ],
          "patching_rect": [
            342.0,
            190.0,
            120.0,
            20.0
          ],
          "text": "live.path live_set"
        }
      },
      {
        "box": {
          "id": "obj-object",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            330.0,
            230.0,
            80.0,
            20.0
          ],
          "saved_object_attributes": {
            "_persistence": 0
          },
          "text": "live.object"
        }
      },
      {
        "box": {
          "id": "obj-route",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 2,
          "outlettype": [
            "",
            ""
          ],
          "patching_rect": [
            330.0,
            275.0,
            182.0,
            20.0
          ],
          "text": "route get_current_smpte_song_time"
        }
      },
      {
        "box": {
          "id": "obj-tosymbol",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            330.0,
            315.0,
            65.0,
            20.0
          ],
          "text": "tosymbol"
        }
      },
      {
        "box": {
          "id": "obj-display",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            420.0,
            315.0,
            115.0,
            20.0
          ],
          "presentation": 1,
          "presentation_rect": [
            290.0,
            108.0,
            130.0,
            20.0
          ],
          "text": "00:00:00:00"
        }
      },
      {
        "box": {
          "id": "obj-udp",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            330.0,
            360.0,
            165.0,
            20.0
          ],
          "text": "udpsend 127.0.0.1 20809"
        }
      },
      {
        "box": {
          "fontface": 1,
          "fontsize": 10.0,
          "id": "offset-label",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            30.0,
            390.0,
            110.0,
            18.0
          ],
          "presentation": 1,
          "presentation_rect": [
            8.0,
            56.0,
            95.0,
            18.0
          ],
          "text": "SYNC ADVANCE"
        }
      },
      {
        "box": {
          "id": "offset-dial",
          "maxclass": "live.dial",
          "numinlets": 1,
          "numoutlets": 2,
          "outlettype": [
            "",
            "float"
          ],
          "parameter_enable": 1,
          "patching_rect": [
            163.0,
            82.0,
            54.0,
            48.0
          ],
          "presentation": 1,
          "presentation_rect": [
            102.0,
            46.0,
            58.0,
            50.0
          ],
          "saved_attribute_attributes": {
            "valueof": {
              "parameter_initial": [
                0.0
              ],
              "parameter_longname": "MTC Offset",
              "parameter_mmax": 100.0,
              "parameter_mmin": -100.0,
              "parameter_modmode": 0,
              "parameter_shortname": "Offset",
              "parameter_type": 0,
              "parameter_unitstyle": 2,
              "parameter_steps": 2001
            }
          },
          "varname": "mtc_offset_ms"
        }
      },
      {
        "box": {
          "format": 6,
          "id": "offset-value",
          "maxclass": "flonum",
          "maximum": 100.0,
          "minimum": -100.0,
          "numinlets": 1,
          "numoutlets": 2,
          "outlettype": [
            "",
            "bang"
          ],
          "parameter_enable": 0,
          "patching_rect": [
            105.0,
            295.0,
            70.0,
            20.0
          ],
          "presentation": 1,
          "presentation_rect": [
            166.0,
            56.0,
            74.0,
            24.0
          ]
        }
      },
      {
        "box": {
          "id": "offset-unit",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            180.0,
            295.0,
            30.0,
            18.0
          ],
          "presentation": 1,
          "presentation_rect": [
            241.0,
            60.0,
            28.0,
            18.0
          ],
          "text": "ms"
        }
      },
      {
        "box": {
          "id": "offset-reset",
          "maxclass": "live.text",
          "mode": 0,
          "numinlets": 1,
          "numoutlets": 2,
          "outlettype": [
            "",
            ""
          ],
          "parameter_enable": 1,
          "patching_rect": [
            105.0,
            329.0,
            76.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            8.0,
            106.0,
            72.0,
            22.0
          ],
          "saved_attribute_attributes": {
            "valueof": {
              "parameter_enum": [
                "val1",
                "val2"
              ],
              "parameter_longname": "live.text",
              "parameter_mmax": 1,
              "parameter_modmode": 0,
              "parameter_shortname": "live.text",
              "parameter_type": 2
            }
          },
          "text": "RESET 0",
          "texton": "RESET 0",
          "varname": "live.text"
        }
      },
      {
        "box": {
          "id": "offset-zero",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            193.0,
            329.0,
            36.0,
            20.0
          ],
          "text": "0."
        }
      },
      {
        "box": {
          "id": "offset-format",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            237.0,
            295.0,
            180.0,
            20.0
          ],
          "text": "sprintf CLMTC_OFFSET %.3f"
        }
      },
      {
        "box": {
          "id": "offset-ready",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 3,
          "outlettype": [
            "bang",
            "int",
            "int"
          ],
          "patching_rect": [
            237.0,
            329.0,
            102.0,
            20.0
          ],
          "text": "live.thisdevice"
        }
      },
      {
        "box": {
          "id": "offset-defer",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            350.0,
            329.0,
            61.0,
            20.0
          ],
          "text": "deferlow"
        }
      },
      {
        "box": {
          "id": "offset-query",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            425.0,
            329.0,
            76.0,
            20.0
          ],
          "text": "getvalueof"
        }
      },
      {
        "box": {
          "id": "offset-set-display",
          "maxclass": "newobj",
          "text": "prepend set",
          "patching_rect": [
            315.0,
            220.0,
            78.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "offset-entry-clip",
          "maxclass": "newobj",
          "text": "clip -100. 100.",
          "patching_rect": [
            315.0,
            250.0,
            92.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "offset-minus10",
          "maxclass": "message",
          "text": "-10",
          "patching_rect": [
            10.0,
            300.0,
            42.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            272.0,
            48.0,
            42.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "offset-minus1",
          "maxclass": "message",
          "text": "-1",
          "patching_rect": [
            10.0,
            300.0,
            34.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            317.0,
            48.0,
            34.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "offset-minus01",
          "maxclass": "message",
          "text": "-0.1",
          "patching_rect": [
            10.0,
            300.0,
            42.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            354.0,
            48.0,
            42.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "offset-plus01",
          "maxclass": "message",
          "text": "+0.1",
          "patching_rect": [
            10.0,
            300.0,
            42.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            354.0,
            74.0,
            42.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "offset-plus1",
          "maxclass": "message",
          "text": "+1",
          "patching_rect": [
            10.0,
            300.0,
            34.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            317.0,
            74.0,
            34.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "offset-plus10",
          "maxclass": "message",
          "text": "+10",
          "patching_rect": [
            10.0,
            300.0,
            42.0,
            22.0
          ],
          "presentation": 1,
          "presentation_rect": [
            272.0,
            74.0,
            42.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "offset-current",
          "maxclass": "newobj",
          "text": "f 0.",
          "patching_rect": [
            100.0,
            330.0,
            42.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "offset-trigger",
          "maxclass": "newobj",
          "text": "t b f",
          "patching_rect": [
            150.0,
            330.0,
            42.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "offset-add",
          "maxclass": "newobj",
          "text": "+ 0.",
          "patching_rect": [
            200.0,
            330.0,
            42.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "offset-step-clip",
          "maxclass": "newobj",
          "text": "clip -100. 100.",
          "patching_rect": [
            250.0,
            330.0,
            92.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "offset-precision-label",
          "maxclass": "comment",
          "text": "réglage fin 0,1 ms",
          "fontsize": 9.0,
          "patching_rect": [
            270.0,
            100.0,
            110.0,
            18.0
          ],
          "presentation": 1,
          "presentation_rect": [
            87.0,
            109.0,
            105.0,
            18.0
          ]
        }
      }
    ],
    "lines": [
      {
        "patchline": {
          "destination": [
            "obj-object",
            0
          ],
          "source": [
            "obj-get",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "obj-get",
            0
          ],
          "source": [
            "obj-metro",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "obj-route",
            0
          ],
          "source": [
            "obj-object",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "obj-toggle",
            0
          ],
          "source": [
            "obj-one",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "obj-object",
            1
          ],
          "source": [
            "obj-path",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "obj-tosymbol",
            0
          ],
          "source": [
            "obj-route",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "obj-metro",
            0
          ],
          "source": [
            "obj-toggle",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "obj-display",
            1
          ],
          "order": 0,
          "source": [
            "obj-tosymbol",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "obj-udp",
            0
          ],
          "order": 1,
          "source": [
            "obj-tosymbol",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "offset-query",
            0
          ],
          "source": [
            "offset-defer",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "offset-format",
            0
          ],
          "order": 0,
          "source": [
            "offset-dial",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "obj-udp",
            0
          ],
          "source": [
            "offset-format",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "offset-dial",
            0
          ],
          "source": [
            "offset-query",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "offset-defer",
            0
          ],
          "source": [
            "offset-ready",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "offset-zero",
            0
          ],
          "source": [
            "offset-reset",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "offset-dial",
            0
          ],
          "source": [
            "offset-zero",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-dial",
            0
          ],
          "destination": [
            "offset-set-display",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-set-display",
            0
          ],
          "destination": [
            "offset-value",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-value",
            0
          ],
          "destination": [
            "offset-entry-clip",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-entry-clip",
            0
          ],
          "destination": [
            "offset-dial",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-dial",
            0
          ],
          "destination": [
            "offset-current",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-minus10",
            0
          ],
          "destination": [
            "offset-trigger",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-minus1",
            0
          ],
          "destination": [
            "offset-trigger",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-minus01",
            0
          ],
          "destination": [
            "offset-trigger",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-plus01",
            0
          ],
          "destination": [
            "offset-trigger",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-plus1",
            0
          ],
          "destination": [
            "offset-trigger",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-plus10",
            0
          ],
          "destination": [
            "offset-trigger",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-trigger",
            1
          ],
          "destination": [
            "offset-add",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-trigger",
            0
          ],
          "destination": [
            "offset-current",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-current",
            0
          ],
          "destination": [
            "offset-add",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-add",
            0
          ],
          "destination": [
            "offset-step-clip",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "offset-step-clip",
            0
          ],
          "destination": [
            "offset-dial",
            0
          ]
        }
      }
    ],
    "parameters": {
      "offset-dial": [
        "MTC Offset",
        "Offset",
        0
      ],
      "offset-reset": [
        "live.text",
        "live.text",
        0
      ],
      "parameterbanks": {
        "0": {
          "index": 0,
          "name": "",
          "parameters": [
            "-",
            "-",
            "-",
            "-",
            "-",
            "-",
            "-",
            "-"
          ],
          "buttons": [
            "-",
            "-",
            "-",
            "-",
            "-",
            "-",
            "-",
            "-"
          ]
        }
      },
      "inherited_shortname": 1
    },
    "latency": 0,
    "is_mpe": 0,
    "external_mpe_tuning_enabled": 0,
    "minimum_live_version": "",
    "minimum_max_version": "",
    "platform_compatibility": 0,
    "project": {
      "version": 1,
      "creationdate": 3590052786,
      "modificationdate": 3590052786,
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
      "viewmode": 0,
      "includepackages": 0
    },
    "autosave": 0,
    "saved_attribute_attributes": {
      "default_plcolor": {
        "expression": ""
      }
    },
    "oscreceiveudpport": 0,
    "openinpresentation": 1,
    "devicewidth": 430.0,
    "dependency_cache": [
      {
        "name": "paradis latin.jpg",
        "patcherrelativepath": ".",
        "type": "JPEG",
        "implicit": 1
      }
    ]
  }
}
