{
 "patcher": {
  "fileversion": 1,
  "appversion": {
   "major": 8,
   "minor": 6,
   "revision": 2,
   "architecture": "x64",
   "modernui": 1
  },
  "classnamespace": "box",
  "rect": [
   737.0,
   106.0,
   592.0,
   169.0
  ],
  "openrect": [
   0.0,
   0.0,
   592.0,
   169.0
  ],
  "bglocked": 0,
  "openinpresentation": 1,
  "default_fontsize": 10.0,
  "default_fontface": 0,
  "default_fontname": "Arial Bold",
  "gridonopen": 1,
  "gridsize": [
   8.0,
   8.0
  ],
  "gridsnaponopen": 1,
  "objectsnaponopen": 1,
  "statusbarvisible": 2,
  "toolbarvisible": 1,
  "lefttoolbarpinned": 0,
  "toptoolbarpinned": 0,
  "righttoolbarpinned": 0,
  "bottomtoolbarpinned": 0,
  "toolbars_unpinned_last_save": 0,
  "tallnewobj": 0,
  "boxanimatetime": 500,
  "enablehscroll": 1,
  "enablevscroll": 1,
  "devicewidth": 592.0,
  "description": "LTC v2 UDP configurable",
  "digest": "",
  "tags": "",
  "style": "",
  "subpatcher_template": "",
  "assistshowspatchername": 0,
  "boxes": [
   {
    "box": {
     "id": "obj-81",
     "maxclass": "newobj",
     "numinlets": 0,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patcher": {
      "fileversion": 1,
      "appversion": {
       "major": 8,
       "minor": 6,
       "revision": 2,
       "architecture": "x64",
       "modernui": 1
      },
      "classnamespace": "box",
      "rect": [
       59.0,
       125.0,
       1025.0,
       695.0
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
      "gridsnaponopen": 1,
      "objectsnaponopen": 1,
      "statusbarvisible": 2,
      "toolbarvisible": 1,
      "lefttoolbarpinned": 0,
      "toptoolbarpinned": 0,
      "righttoolbarpinned": 0,
      "bottomtoolbarpinned": 0,
      "toolbars_unpinned_last_save": 0,
      "tallnewobj": 0,
      "boxanimatetime": 200,
      "enablehscroll": 1,
      "enablevscroll": 1,
      "devicewidth": 0.0,
      "description": "",
      "digest": "",
      "tags": "",
      "style": "",
      "subpatcher_template": "",
      "assistshowspatchername": 0,
      "boxes": [
       {
        "box": {
         "id": "obj-3",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          47.5,
          238.0,
          71.0,
          22.0
         ],
         "text": "fromsymbol"
        }
       },
       {
        "box": {
         "id": "obj-4",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          47.5,
          166.0,
          86.0,
          22.0
         ],
         "text": "property name"
        }
       },
       {
        "box": {
         "id": "obj-2",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 2,
         "outlettype": [
          "bang",
          ""
         ],
         "patching_rect": [
          74.5,
          103.0,
          29.5,
          22.0
         ],
         "text": "t b l"
        }
       },
       {
        "box": {
         "id": "obj-1",
         "maxclass": "newobj",
         "numinlets": 2,
         "numoutlets": 2,
         "outlettype": [
          "",
          ""
         ],
         "patching_rect": [
          47.5,
          203.0,
          77.0,
          22.0
         ],
         "saved_object_attributes": {
          "_persistence": 1
         },
         "text": "live.observer"
        }
       },
       {
        "box": {
         "id": "obj-79",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          47.5,
          278.0,
          79.0,
          22.0
         ],
         "text": "prepend set"
        }
       },
       {
        "box": {
         "id": "obj-58",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          17.0,
          16.0,
          273.0,
          22.0
         ],
         "text": "loadmess path this_device canonical_parent"
        }
       },
       {
        "box": {
         "id": "obj-16",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 3,
         "outlettype": [
          "",
          "",
          ""
         ],
         "patching_rect": [
          17.0,
          51.0,
          62.0,
          22.0
         ],
         "text": "live.path"
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-80",
         "index": 1,
         "maxclass": "outlet",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          47.5,
          325.0,
          30.0,
          30.0
         ]
        }
       }
      ],
      "lines": [
       {
        "patchline": {
         "destination": [
          "obj-3",
          0
         ],
         "source": [
          "obj-1",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-2",
          0
         ],
         "source": [
          "obj-16",
          1
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-1",
          1
         ],
         "source": [
          "obj-2",
          1
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-4",
          0
         ],
         "source": [
          "obj-2",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-79",
          0
         ],
         "source": [
          "obj-3",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-1",
          0
         ],
         "source": [
          "obj-4",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-16",
          0
         ],
         "source": [
          "obj-58",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-80",
          0
         ],
         "source": [
          "obj-79",
          0
         ]
        }
       }
      ],
      "saved_attribute_attributes": {
       "default_plcolor": {
        "expression": ""
       }
      }
     },
     "patching_rect": [
      134.0,
      1098.0,
      71.0,
      20.0
     ],
     "saved_attribute_attributes": {
      "default_plcolor": {
       "expression": ""
      }
     },
     "saved_object_attributes": {
      "description": "",
      "digest": "",
      "globalpatchername": "",
      "tags": ""
     },
     "text": "p TrackName"
    }
   },
   {
    "box": {
     "id": "obj-70",
     "maxclass": "newobj",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      527.5,
      316.0,
      77.0,
      20.0
     ],
     "text": "pack sym sym"
    }
   },
   {
    "box": {
     "id": "obj-61",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      385.0,
      251.0,
      76.0,
      20.0
     ],
     "saved_object_attributes": {
      "filename": "framerate.js",
      "parameter_enable": 0
     },
     "text": "js framerate.js"
    }
   },
   {
    "box": {
     "id": "obj-60",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 3,
     "outlettype": [
      "",
      "int",
      "int"
     ],
     "patching_rect": [
      385.0,
      217.0,
      44.0,
      20.0
     ],
     "text": "change"
    }
   },
   {
    "box": {
     "id": "obj-56",
     "maxclass": "newobj",
     "numinlets": 7,
     "numoutlets": 2,
     "outlettype": [
      "",
      ""
     ],
     "patching_rect": [
      477.5,
      251.0,
      213.0,
      20.0
     ],
     "text": "combine h : m : s : f @padding 2 0 2 0 2 0 2"
    }
   },
   {
    "box": {
     "id": "obj-4",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 5,
     "outlettype": [
      "int",
      "int",
      "int",
      "int",
      "int"
     ],
     "patching_rect": [
      440.5,
      174.0,
      71.0,
      20.0
     ],
     "text": "unpack i i i i i"
    }
   },
   {
    "box": {
     "id": "obj-86",
     "maxclass": "newobj",
     "numinlets": 0,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      689.4999999999999,
      1108.25,
      59.0,
      20.0
     ],
     "text": "r jumpText"
    }
   },
   {
    "box": {
     "id": "obj-85",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      848.888887,
      429.0,
      61.0,
      20.0
     ],
     "text": "s jumpText"
    }
   },
   {
    "box": {
     "id": "obj-84",
     "maxclass": "newobj",
     "numinlets": 0,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      848.888887,
      363.0,
      50.0,
      20.0
     ],
     "text": "r jumpTc"
    }
   },
   {
    "box": {
     "id": "obj-83",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      632.0,
      1183.0,
      52.0,
      20.0
     ],
     "text": "s jumpTc"
    }
   },
   {
    "box": {
     "id": "obj-82",
     "maxclass": "newobj",
     "numinlets": 2,
     "numoutlets": 2,
     "outlettype": [
      "",
      ""
     ],
     "patcher": {
      "fileversion": 1,
      "appversion": {
       "major": 8,
       "minor": 6,
       "revision": 2,
       "architecture": "x64",
       "modernui": 1
      },
      "classnamespace": "box",
      "rect": [
       364.0,
       270.0,
       501.0,
       779.0
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
      "gridsnaponopen": 1,
      "objectsnaponopen": 1,
      "statusbarvisible": 2,
      "toolbarvisible": 1,
      "lefttoolbarpinned": 0,
      "toptoolbarpinned": 0,
      "righttoolbarpinned": 0,
      "bottomtoolbarpinned": 0,
      "toolbars_unpinned_last_save": 0,
      "tallnewobj": 0,
      "boxanimatetime": 200,
      "enablehscroll": 1,
      "enablevscroll": 1,
      "devicewidth": 0.0,
      "description": "",
      "digest": "",
      "tags": "",
      "style": "",
      "subpatcher_template": "",
      "assistshowspatchername": 0,
      "boxes": [
       {
        "box": {
         "id": "obj-9",
         "maxclass": "newobj",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "patching_rect": [
          178.61111307144165,
          552.0,
          67.0,
          22.0
         ],
         "text": "delay 2500"
        }
       },
       {
        "box": {
         "id": "obj-7",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          322.61111307144165,
          445.0,
          97.0,
          22.0
         ],
         "text": "set start_time $1"
        }
       },
       {
        "box": {
         "id": "obj-47",
         "linecount": 2,
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          240.11111307144165,
          679.0,
          179.5,
          35.0
         ],
         "text": "set \"Press enter to jump to any previously played timecode.\""
        }
       },
       {
        "box": {
         "id": "obj-46",
         "linecount": 2,
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          22.11111307144165,
          679.0,
          169.0,
          35.0
         ],
         "text": "set \"Timecode not found. Has this part been played yet?\""
        }
       },
       {
        "box": {
         "id": "obj-44",
         "maxclass": "button",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "parameter_enable": 0,
         "patching_rect": [
          172.11111307144165,
          394.0,
          24.0,
          24.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-43",
         "maxclass": "newobj",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "patching_rect": [
          172.11111307144165,
          430.0,
          54.0,
          22.0
         ],
         "text": "delay 10"
        }
       },
       {
        "box": {
         "id": "obj-42",
         "maxclass": "button",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "parameter_enable": 0,
         "patching_rect": [
          97.0,
          394.0,
          24.0,
          24.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-40",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          172.11111307144165,
          470.0,
          31.0,
          22.0
         ],
         "text": "stop"
        }
       },
       {
        "box": {
         "id": "obj-37",
         "maxclass": "newobj",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "patching_rect": [
          123.0,
          505.0,
          61.0,
          22.0
         ],
         "text": "delay 100"
        }
       },
       {
        "box": {
         "id": "obj-32",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          96.0,
          147.0,
          72.0,
          22.0
         ],
         "text": "01:10:01:26"
        }
       },
       {
        "box": {
         "id": "obj-23",
         "maxclass": "button",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "parameter_enable": 0,
         "patching_rect": [
          123.0,
          536.0,
          24.0,
          24.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-16",
         "maxclass": "newobj",
         "numinlets": 2,
         "numoutlets": 2,
         "outlettype": [
          "bang",
          ""
         ],
         "patching_rect": [
          427.0,
          314.0,
          40.0,
          22.0
         ],
         "text": "select"
        }
       },
       {
        "box": {
         "id": "obj-20",
         "maxclass": "button",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "parameter_enable": 0,
         "patching_rect": [
          274.61111307144165,
          583.5,
          24.0,
          24.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-17",
         "maxclass": "button",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "parameter_enable": 0,
         "patching_rect": [
          352.5,
          474.5,
          24.0,
          24.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-15",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          85.61111307144165,
          626.0,
          167.0,
          22.0
         ],
         "text": "textcolor 0.863 0.149 0.149 1."
        }
       },
       {
        "box": {
         "id": "obj-13",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          284.0,
          626.0,
          161.0,
          22.0
         ],
         "text": "textcolor 0.278 0.73 0.469 1."
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-11",
         "index": 2,
         "maxclass": "outlet",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          221.36111307144165,
          755.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-8",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          309.61111307144165,
          394.0,
          163.0,
          22.0
         ],
         "text": "set current_song_time $1"
        }
       },
       {
        "box": {
         "id": "obj-6",
         "maxclass": "newobj",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          309.61111307144165,
          591.0,
          62.0,
          22.0
         ],
         "saved_object_attributes": {
          "_persistence": 1
         },
         "text": "live.object"
        }
       },
       {
        "box": {
         "id": "obj-5",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 3,
         "outlettype": [
          "",
          "",
          ""
         ],
         "patching_rect": [
          352.61111307144165,
          552.0,
          116.0,
          22.0
         ],
         "text": "live.path live_set"
        }
       },
       {
        "box": {
         "id": "obj-3",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 3,
         "outlettype": [
          "bang",
          "int",
          "int"
         ],
         "patching_rect": [
          352.61111307144165,
          520.0,
          102.0,
          22.0
         ],
         "text": "live.thisdevice"
        }
       },
       {
        "box": {
         "id": "obj-1",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          97.0,
          260.9444441795349,
          63.0,
          22.0
         ],
         "text": "getPos $1"
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-2",
         "index": 2,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          97.0,
          208.86752939224243,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-60",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          221.36111307144165,
          181.44444489479065,
          39.0,
          22.0
         ],
         "text": "$2 $1"
        }
       },
       {
        "box": {
         "id": "obj-84",
         "maxclass": "newobj",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          "float"
         ],
         "patching_rect": [
          221.36111307144165,
          109.92308521270752,
          39.0,
          22.0
         ],
         "text": "/ 100."
        }
       },
       {
        "box": {
         "id": "obj-80",
         "maxclass": "newobj",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          "float"
         ],
         "patching_rect": [
          221.36111307144165,
          60.0,
          40.0,
          22.0
         ],
         "text": "* 100."
        }
       },
       {
        "box": {
         "id": "obj-76",
         "maxclass": "newobj",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          221.36111307144165,
          148.8717987537384,
          57.0,
          22.0
         ],
         "text": "pack 0. 0"
        }
       },
       {
        "box": {
         "id": "obj-73",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          33.0,
          260.9444441795349,
          51.0,
          22.0
         ],
         "text": "tc $1 $2"
        }
       },
       {
        "box": {
         "id": "obj-70",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          212.86111307144165,
          260.9444441795349,
          73.0,
          22.0
         ],
         "text": "prepend get"
        }
       },
       {
        "box": {
         "fontface": 1,
         "fontname": "Arial",
         "fontsize": 10.0,
         "id": "obj-69",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 3,
         "outlettype": [
          "",
          "int",
          "int"
         ],
         "patching_rect": [
          221.36111307144165,
          86.46153926849365,
          44.0,
          20.0
         ],
         "text": "change"
        }
       },
       {
        "box": {
         "id": "obj-68",
         "maxclass": "newobj",
         "numinlets": 3,
         "numoutlets": 3,
         "outlettype": [
          "",
          "",
          ""
         ],
         "patching_rect": [
          221.36111307144165,
          215.5,
          56.0,
          22.0
         ],
         "text": "route 0 1"
        }
       },
       {
        "box": {
         "id": "obj-66",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          172.11111307144165,
          260.9444441795349,
          30.0,
          22.0
         ],
         "text": "size"
        }
       },
       {
        "box": {
         "fontface": 1,
         "fontname": "Arial",
         "fontsize": 10.0,
         "id": "obj-64",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 3,
         "outlettype": [
          "",
          "int",
          "int"
         ],
         "patching_rect": [
          147.11111307144165,
          60.0,
          44.0,
          20.0
         ],
         "text": "change"
        }
       },
       {
        "box": {
         "id": "obj-61",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          298.11111307144165,
          260.9444441795349,
          75.0,
          22.0
         ],
         "text": "prepend pos"
        }
       },
       {
        "box": {
         "fontface": 1,
         "fontname": "Arial",
         "fontsize": 10.0,
         "id": "obj-56",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 9,
         "outlettype": [
          "int",
          "int",
          "int",
          "float",
          "list",
          "float",
          "float",
          "int",
          "int"
         ],
         "patching_rect": [
          147.11111307144165,
          32.0,
          118.0,
          20.0
         ],
         "text": "plugsync~"
        }
       },
       {
        "box": {
         "id": "obj-4",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 2,
         "outlettype": [
          "",
          ""
         ],
         "patching_rect": [
          159.61111307144165,
          342.0,
          65.0,
          22.0
         ],
         "saved_object_attributes": {
          "filename": "cache.js",
          "parameter_enable": 0
         },
         "text": "js cache.js"
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-79",
         "index": 1,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          33.0,
          208.86752939224243,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-81",
         "index": 1,
         "maxclass": "outlet",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          130.0,
          394.0,
          30.0,
          30.0
         ]
        }
       }
      ],
      "lines": [
       {
        "patchline": {
         "destination": [
          "obj-4",
          0
         ],
         "order": 0,
         "source": [
          "obj-1",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-42",
          0
         ],
         "order": 1,
         "source": [
          "obj-1",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-11",
          0
         ],
         "midpoints": [
          293.5,
          666.0,
          230.86111307144165,
          666.0
         ],
         "source": [
          "obj-13",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-11",
          0
         ],
         "midpoints": [
          95.11111307144165,
          666.0,
          230.86111307144165,
          666.0
         ],
         "source": [
          "obj-15",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-3",
          0
         ],
         "source": [
          "obj-17",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-1",
          0
         ],
         "source": [
          "obj-2",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-13",
          0
         ],
         "order": 0,
         "source": [
          "obj-20",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-47",
          0
         ],
         "order": 1,
         "source": [
          "obj-20",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-15",
          0
         ],
         "midpoints": [
          132.5,
          606.0,
          95.11111307144165,
          606.0
         ],
         "order": 1,
         "source": [
          "obj-23",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-46",
          0
         ],
         "midpoints": [
          132.5,
          590.0,
          31.61111307144165,
          590.0
         ],
         "order": 2,
         "source": [
          "obj-23",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-9",
          0
         ],
         "order": 0,
         "source": [
          "obj-23",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-5",
          0
         ],
         "source": [
          "obj-3",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-1",
          0
         ],
         "source": [
          "obj-32",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-23",
          0
         ],
         "source": [
          "obj-37",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-20",
          0
         ],
         "midpoints": [
          215.11111307144165,
          421.0,
          284.11111307144165,
          421.0
         ],
         "order": 2,
         "source": [
          "obj-4",
          1
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-44",
          0
         ],
         "order": 3,
         "source": [
          "obj-4",
          1
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-7",
          0
         ],
         "midpoints": [
          215.11111307144165,
          412.0,
          294.0,
          412.0,
          294.0,
          422.0,
          332.11111307144165,
          422.0
         ],
         "order": 0,
         "source": [
          "obj-4",
          1
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-8",
          0
         ],
         "order": 1,
         "source": [
          "obj-4",
          1
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-81",
          0
         ],
         "source": [
          "obj-4",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-37",
          0
         ],
         "source": [
          "obj-40",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-37",
          0
         ],
         "source": [
          "obj-42",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-40",
          0
         ],
         "source": [
          "obj-43",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-43",
          0
         ],
         "source": [
          "obj-44",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-11",
          0
         ],
         "source": [
          "obj-46",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-11",
          0
         ],
         "source": [
          "obj-47",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-6",
          1
         ],
         "source": [
          "obj-5",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-64",
          0
         ],
         "source": [
          "obj-56",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-80",
          0
         ],
         "source": [
          "obj-56",
          6
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-68",
          0
         ],
         "source": [
          "obj-60",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-4",
          0
         ],
         "source": [
          "obj-61",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-66",
          0
         ],
         "source": [
          "obj-64",
          2
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-76",
          1
         ],
         "midpoints": [
          156.61111307144165,
          139.0,
          268.86111307144165,
          139.0
         ],
         "source": [
          "obj-64",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-4",
          0
         ],
         "source": [
          "obj-66",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-61",
          0
         ],
         "source": [
          "obj-68",
          1
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-70",
          0
         ],
         "source": [
          "obj-68",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-84",
          0
         ],
         "source": [
          "obj-69",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-6",
          0
         ],
         "source": [
          "obj-7",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-4",
          0
         ],
         "source": [
          "obj-70",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-4",
          0
         ],
         "source": [
          "obj-73",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-60",
          0
         ],
         "source": [
          "obj-76",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-73",
          0
         ],
         "source": [
          "obj-79",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-6",
          0
         ],
         "source": [
          "obj-8",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-69",
          0
         ],
         "source": [
          "obj-80",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-76",
          0
         ],
         "source": [
          "obj-84",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-20",
          0
         ],
         "source": [
          "obj-9",
          0
         ]
        }
       }
      ],
      "saved_attribute_attributes": {
       "default_plcolor": {
        "expression": ""
       }
      }
     },
     "patching_rect": [
      821.888887,
      393.0,
      46.0,
      20.0
     ],
     "saved_attribute_attributes": {
      "default_plcolor": {
       "expression": ""
      }
     },
     "saved_object_attributes": {
      "description": "",
      "digest": "",
      "globalpatchername": "",
      "tags": ""
     },
     "text": "p cache"
    }
   },
   {
    "box": {
     "id": "obj-78",
     "maxclass": "newobj",
     "numinlets": 0,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      598.5,
      1108.25,
      24.0,
      20.0
     ],
     "text": "r tc"
    }
   },
   {
    "box": {
     "id": "obj-77",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      212.0,
      765.0,
      26.0,
      20.0
     ],
     "text": "s tc"
    }
   },
   {
    "box": {
     "id": "obj-74",
     "maxclass": "newobj",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patcher": {
      "fileversion": 1,
      "appversion": {
       "major": 8,
       "minor": 6,
       "revision": 2,
       "architecture": "x64",
       "modernui": 1
      },
      "classnamespace": "box",
      "rect": [
       800.0,
       629.0,
       592.0,
       168.0
      ],
      "openrect": [
       0.0,
       0.0,
       592.0,
       168.0
      ],
      "bglocked": 0,
      "openinpresentation": 1,
      "default_fontsize": 12.0,
      "default_fontface": 0,
      "default_fontname": "Arial",
      "gridonopen": 1,
      "gridsize": [
       16.0,
       16.0
      ],
      "gridsnaponopen": 1,
      "objectsnaponopen": 1,
      "statusbarvisible": 2,
      "toolbarvisible": 1,
      "lefttoolbarpinned": 0,
      "toptoolbarpinned": 0,
      "righttoolbarpinned": 0,
      "bottomtoolbarpinned": 0,
      "toolbars_unpinned_last_save": 0,
      "tallnewobj": 0,
      "boxanimatetime": 200,
      "enablehscroll": 1,
      "enablevscroll": 1,
      "devicewidth": 0.0,
      "description": "",
      "digest": "",
      "tags": "",
      "style": "",
      "subpatcher_template": "",
      "assistshowspatchername": 0,
      "title": "Jump to Timecode",
      "boxes": [
       {
        "box": {
         "comment": "",
         "id": "obj-7",
         "index": 2,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          8.5,
          83.25,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-22",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          168.14160645008087,
          195.5752369761467,
          95.0,
          22.0
         ],
         "text": "text 01:00:01:26"
        }
       },
       {
        "box": {
         "id": "obj-20",
         "maxclass": "newobj",
         "numinlets": 2,
         "numoutlets": 2,
         "outlettype": [
          "",
          ""
         ],
         "patching_rect": [
          25.5,
          183.185855448246,
          59.0,
          22.0
         ],
         "text": "route text"
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "id": "obj-19",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          0.5,
          138.0,
          592.0,
          21.0
         ],
         "presentation": 1,
         "presentation_rect": [
          0.5,
          139.0,
          592.0,
          21.0
         ],
         "text": "Press enter to jump to any previously played timecode.",
         "textcolor": [
          0.278,
          0.73,
          0.469,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "autoscroll": 0,
         "bangmode": 1,
         "bgcolor": [
          0.2,
          0.2,
          0.2,
          0.0
         ],
         "bordercolor": [
          0.349019607843137,
          0.349019607843137,
          0.349019607843137,
          0.0
         ],
         "fontname": "Ableton Sans Medium",
         "fontsize": 90.0,
         "id": "obj-16",
         "keymode": 1,
         "lines": 1,
         "maxclass": "textedit",
         "numinlets": 1,
         "numoutlets": 4,
         "outlettype": [
          "",
          "int",
          "",
          ""
         ],
         "parameter_enable": 0,
         "parameter_mappable": 0,
         "patching_rect": [
          25.5,
          24.0,
          542.0,
          115.0
         ],
         "presentation": 1,
         "presentation_rect": [
          25.5,
          8.0,
          542.0,
          115.0
         ],
         "text": "00:00:00:00",
         "textcolor": [
          0.27843137254902,
          0.729411764705882,
          0.470588235294118,
          1.0
         ],
         "textjustification": 1,
         "wordwrap": 0
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-2",
         "index": 1,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          0.5,
          4.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "id": "obj-27",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          424.5,
          115.25,
          143.0,
          21.0
         ],
         "presentation": 1,
         "presentation_rect": [
          453.0,
          104.0,
          85.0,
          21.0
         ],
         "text": "frames",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "id": "obj-26",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          294.5,
          115.25,
          143.0,
          21.0
         ],
         "presentation": 1,
         "presentation_rect": [
          320.0,
          104.0,
          85.0,
          21.0
         ],
         "text": "seconds",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "id": "obj-25",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          161.5,
          115.25,
          143.0,
          21.0
         ],
         "presentation": 1,
         "presentation_rect": [
          185.77464827895164,
          104.0,
          85.0,
          21.0
         ],
         "text": "minutes",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "id": "obj-24",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          25.5,
          115.25,
          143.0,
          21.0
         ],
         "presentation": 1,
         "presentation_rect": [
          53.0,
          104.0,
          85.0,
          21.0
         ],
         "text": "hours",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-11",
         "index": 1,
         "maxclass": "outlet",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          25.5,
          222.9292048215866,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-3",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          726.8500845774361,
          856.0,
          84.0,
          22.0
         ],
         "text": "savewindow 0"
        }
       },
       {
        "box": {
         "id": "obj-10",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          340.85008457743606,
          856.0,
          137.0,
          22.0
         ],
         "text": "title \"Jump to Timecode\""
        }
       },
       {
        "box": {
         "id": "obj-4",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          322.85008457743606,
          4.0,
          221.0,
          22.0
         ],
         "text": "window flags grow nofloat, window exec"
        }
       },
       {
        "box": {
         "id": "obj-9",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 2,
         "outlettype": [
          "",
          ""
         ],
         "patching_rect": [
          521.3500845774361,
          931.0,
          67.0,
          22.0
         ],
         "save": [
          "#N",
          "thispatcher",
          ";",
          "#Q",
          "end",
          ";"
         ],
         "text": "thispatcher"
        }
       },
       {
        "box": {
         "id": "obj-8",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          479.60225849047947,
          856.0,
          221.0,
          22.0
         ],
         "text": "window flags float nogrow, window exec"
        }
       },
       {
        "box": {
         "id": "obj-6",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "patching_rect": [
          521.3500845774361,
          787.0,
          58.0,
          22.0
         ],
         "text": "loadbang"
        }
       },
       {
        "box": {
         "angle": 270.0,
         "bgcolor": [
          0.070588235294118,
          0.07843137254902,
          0.086274509803922,
          1.0
         ],
         "hidden": 1,
         "id": "obj-5",
         "maxclass": "panel",
         "mode": 0,
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          0.5,
          0.0,
          592.0,
          168.0
         ],
         "presentation": 1,
         "presentation_rect": [
          0.0,
          0.0,
          592.0,
          168.0
         ],
         "proportion": 0.5,
         "saved_attribute_attributes": {
          "bgfillcolor": {
           "expression": ""
          }
         }
        }
       }
      ],
      "lines": [
       {
        "patchline": {
         "destination": [
          "obj-9",
          0
         ],
         "midpoints": [
          350.35008457743606,
          895.0,
          530.8500845774361,
          895.0
         ],
         "source": [
          "obj-10",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-20",
          0
         ],
         "order": 1,
         "source": [
          "obj-16",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-22",
          1
         ],
         "order": 0,
         "source": [
          "obj-16",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-16",
          0
         ],
         "source": [
          "obj-2",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-11",
          0
         ],
         "source": [
          "obj-20",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-20",
          0
         ],
         "source": [
          "obj-22",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-9",
          0
         ],
         "midpoints": [
          736.3500845774361,
          913.0,
          530.8500845774361,
          913.0
         ],
         "source": [
          "obj-3",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-9",
          0
         ],
         "midpoints": [
          332.35008457743606,
          625.0,
          530.8500845774361,
          625.0
         ],
         "source": [
          "obj-4",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-10",
          0
         ],
         "order": 2,
         "source": [
          "obj-6",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-3",
          0
         ],
         "order": 0,
         "source": [
          "obj-6",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-8",
          0
         ],
         "order": 1,
         "source": [
          "obj-6",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-19",
          0
         ],
         "source": [
          "obj-7",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-9",
          0
         ],
         "midpoints": [
          489.10225849047947,
          895.0,
          530.8500845774361,
          895.0
         ],
         "source": [
          "obj-8",
          0
         ]
        }
       }
      ],
      "styles": [
       {
        "name": "rnbodefault",
        "default": {
         "accentcolor": [
          0.343034118413925,
          0.506230533123016,
          0.86220508813858,
          1.0
         ],
         "bgcolor": [
          0.031372549019608,
          0.125490196078431,
          0.211764705882353,
          1.0
         ],
         "bgfillcolor": {
          "angle": 270.0,
          "autogradient": 0.0,
          "color": [
           0.031372549019608,
           0.125490196078431,
           0.211764705882353,
           1.0
          ],
          "color1": [
           0.031372549019608,
           0.125490196078431,
           0.211764705882353,
           1.0
          ],
          "color2": [
           0.263682,
           0.004541,
           0.038797,
           1.0
          ],
          "proportion": 0.39,
          "type": "color"
         },
         "color": [
          0.929412,
          0.929412,
          0.352941,
          1.0
         ],
         "elementcolor": [
          0.357540726661682,
          0.515565991401672,
          0.861786782741547,
          1.0
         ],
         "fontname": [
          "Lato"
         ],
         "fontsize": [
          12.0
         ],
         "stripecolor": [
          0.258338063955307,
          0.352425158023834,
          0.511919498443604,
          1.0
         ]
        },
        "parentstyle": "",
        "multi": 0
       },
       {
        "name": "rnbohighcontrast",
        "default": {
         "accentcolor": [
          0.666666666666667,
          0.666666666666667,
          0.666666666666667,
          1.0
         ],
         "bgcolor": [
          0.0,
          0.0,
          0.0,
          1.0
         ],
         "bgfillcolor": {
          "angle": 270.0,
          "autogradient": 0.0,
          "color": [
           0.0,
           0.0,
           0.0,
           1.0
          ],
          "color1": [
           0.090196078431373,
           0.090196078431373,
           0.090196078431373,
           1.0
          ],
          "color2": [
           0.156862745098039,
           0.168627450980392,
           0.164705882352941,
           1.0
          ],
          "proportion": 0.5,
          "type": "color"
         },
         "clearcolor": [
          1.0,
          1.0,
          1.0,
          0.0
         ],
         "color": [
          1.0,
          0.874509803921569,
          0.141176470588235,
          1.0
         ],
         "editing_bgcolor": [
          0.258823529411765,
          0.258823529411765,
          0.258823529411765,
          1.0
         ],
         "elementcolor": [
          0.223386004567146,
          0.254748553037643,
          0.998085916042328,
          1.0
         ],
         "fontsize": [
          13.0
         ],
         "locked_bgcolor": [
          0.258823529411765,
          0.258823529411765,
          0.258823529411765,
          1.0
         ],
         "selectioncolor": [
          0.301960784313725,
          0.694117647058824,
          0.949019607843137,
          1.0
         ],
         "stripecolor": [
          0.258823529411765,
          0.258823529411765,
          0.258823529411765,
          1.0
         ],
         "textcolor": [
          1.0,
          1.0,
          1.0,
          1.0
         ],
         "textcolor_inverse": [
          1.0,
          1.0,
          1.0,
          1.0
         ]
        },
        "parentstyle": "",
        "multi": 0
       },
       {
        "name": "rnbolight",
        "default": {
         "accentcolor": [
          0.443137254901961,
          0.505882352941176,
          0.556862745098039,
          1.0
         ],
         "bgcolor": [
          0.796078431372549,
          0.862745098039216,
          0.925490196078431,
          1.0
         ],
         "bgfillcolor": {
          "angle": 270.0,
          "autogradient": 0.0,
          "color": [
           0.835294117647059,
           0.901960784313726,
           0.964705882352941,
           1.0
          ],
          "color1": [
           0.031372549019608,
           0.125490196078431,
           0.211764705882353,
           1.0
          ],
          "color2": [
           0.263682,
           0.004541,
           0.038797,
           1.0
          ],
          "proportion": 0.39,
          "type": "color"
         },
         "clearcolor": [
          0.898039,
          0.898039,
          0.898039,
          1.0
         ],
         "color": [
          0.815686274509804,
          0.509803921568627,
          0.262745098039216,
          1.0
         ],
         "editing_bgcolor": [
          0.898039,
          0.898039,
          0.898039,
          1.0
         ],
         "elementcolor": [
          0.337254901960784,
          0.384313725490196,
          0.462745098039216,
          1.0
         ],
         "fontname": [
          "Lato"
         ],
         "locked_bgcolor": [
          0.898039,
          0.898039,
          0.898039,
          1.0
         ],
         "stripecolor": [
          0.309803921568627,
          0.698039215686274,
          0.764705882352941,
          1.0
         ],
         "textcolor_inverse": [
          0.0,
          0.0,
          0.0,
          1.0
         ]
        },
        "parentstyle": "",
        "multi": 0
       },
       {
        "name": "rnbomonokai",
        "default": {
         "accentcolor": [
          0.501960784313725,
          0.501960784313725,
          0.501960784313725,
          1.0
         ],
         "bgcolor": [
          0.0,
          0.0,
          0.0,
          1.0
         ],
         "bgfillcolor": {
          "angle": 270.0,
          "autogradient": 0.0,
          "color": [
           0.0,
           0.0,
           0.0,
           1.0
          ],
          "color1": [
           0.031372549019608,
           0.125490196078431,
           0.211764705882353,
           1.0
          ],
          "color2": [
           0.263682,
           0.004541,
           0.038797,
           1.0
          ],
          "proportion": 0.39,
          "type": "color"
         },
         "clearcolor": [
          0.976470588235294,
          0.96078431372549,
          0.917647058823529,
          1.0
         ],
         "color": [
          0.611764705882353,
          0.125490196078431,
          0.776470588235294,
          1.0
         ],
         "editing_bgcolor": [
          0.976470588235294,
          0.96078431372549,
          0.917647058823529,
          1.0
         ],
         "elementcolor": [
          0.749019607843137,
          0.83921568627451,
          1.0,
          1.0
         ],
         "fontname": [
          "Lato"
         ],
         "locked_bgcolor": [
          0.976470588235294,
          0.96078431372549,
          0.917647058823529,
          1.0
         ],
         "stripecolor": [
          0.796078431372549,
          0.207843137254902,
          1.0,
          1.0
         ],
         "textcolor": [
          0.129412,
          0.129412,
          0.129412,
          1.0
         ]
        },
        "parentstyle": "",
        "multi": 0
       }
      ],
      "bgcolor": [
       0.070588235294118,
       0.07843137254902,
       0.086274509803922,
       1.0
      ],
      "saved_attribute_attributes": {
       "default_plcolor": {
        "expression": ""
       },
       "locked_bgcolor": {
        "expression": ""
       }
      }
     },
     "patching_rect": [
      632.0,
      1143.685885667801,
      44.0,
      20.0
     ],
     "saved_attribute_attributes": {
      "default_plcolor": {
       "expression": ""
      },
      "locked_bgcolor": {
       "expression": ""
      }
     },
     "saved_object_attributes": {
      "description": "",
      "digest": "",
      "globalpatchername": "",
      "locked_bgcolor": [
       0.070588235294118,
       0.07843137254902,
       0.086274509803922,
       1.0
      ],
      "tags": ""
     },
     "text": "p Jump"
    }
   },
   {
    "box": {
     "appearance": 2,
     "id": "obj-72",
     "lcdbgcolor": [
      0.07843137254902,
      0.07843137254902,
      0.07843137254902,
      0.0
     ],
     "lcdcolor": [
      0.152941176470588,
      0.403921568627451,
      0.286274509803922,
      1.0
     ],
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
      548.9814813733101,
      1000.0,
      96.0,
      16.0
     ],
     "presentation": 1,
     "presentation_rect": [
      232.0,
      146.0,
      96.0,
      16.0
     ],
     "saved_attribute_attributes": {
      "lcdbgcolor": {
       "expression": ""
      },
      "lcdcolor": {
       "expression": ""
      },
      "valueof": {
       "parameter_enum": [
        "val1",
        "val2"
       ],
       "parameter_invisible": 2,
       "parameter_longname": "live.text[6]",
       "parameter_mmax": 1,
       "parameter_modmode": 0,
       "parameter_shortname": "Jump to Timecode",
       "parameter_type": 2
      }
     },
     "text": "Jump to Timecode",
     "varname": "live.text[3]"
    }
   },
   {
    "box": {
     "id": "obj-65",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      632.0,
      1075.25,
      32.0,
      20.0
     ],
     "text": "open"
    }
   },
   {
    "box": {
     "id": "obj-67",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      632.0,
      1108.25,
      48.0,
      20.0
     ],
     "text": "pcontrol"
    }
   },
   {
    "box": {
     "id": "obj-95",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 2,
     "outlettype": [
      "",
      ""
     ],
     "patching_rect": [
      854.75,
      582.5,
      89.0,
      20.0
     ],
     "text": "unpack sym sym"
    }
   },
   {
    "box": {
     "id": "obj-75",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      741.75,
      582.5,
      94.0,
      20.0
     ],
     "text": "00:00:00:00 --"
    }
   },
   {
    "box": {
     "id": "obj-59",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "outlettype": [
      "list"
     ],
     "patching_rect": [
      440.5,
      134.0,
      90.0,
      20.0
     ],
     "text": "smpte_decode6~"
    }
   },
   {
    "box": {
     "activebgcolor": [
      0.647059,
      0.647059,
      0.647059,
      1.0
     ],
     "activebgoncolor": [
      1.0,
      0.709804,
      0.196078,
      1.0
     ],
     "appearance": 2,
     "bgcolor": [
      0.647059,
      0.647059,
      0.647059,
      1.0
     ],
     "bordercolor": [
      0.313725,
      0.313725,
      0.313725,
      1.0
     ],
     "focusbordercolor": [
      0.313725490196078,
      0.313725490196078,
      0.313725490196078,
      0.0
     ],
     "id": "obj-57",
     "inactivelcdcolor": [
      0.54902,
      0.54902,
      0.54902,
      1.0
     ],
     "lcdbgcolor": [
      0.156862745098039,
      0.156862745098039,
      0.156862745098039,
      0.0
     ],
     "lcdcolor": [
      0.152941176470588,
      0.403921568627451,
      0.286274509803922,
      1.0
     ],
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
      373.0,
      1000.0,
      71.0,
      16.0
     ],
     "presentation": 1,
     "presentation_rect": [
      64.0,
      146.0,
      68.0,
      16.0
     ],
     "saved_attribute_attributes": {
      "activebgcolor": {
       "expression": ""
      },
      "activebgoncolor": {
       "expression": ""
      },
      "bgcolor": {
       "expression": ""
      },
      "bordercolor": {
       "expression": ""
      },
      "focusbordercolor": {
       "expression": ""
      },
      "inactivelcdcolor": {
       "expression": ""
      },
      "lcdbgcolor": {
       "expression": ""
      },
      "lcdcolor": {
       "expression": ""
      },
      "textcolor": {
       "expression": ""
      },
      "textoffcolor": {
       "expression": ""
      },
      "valueof": {
       "parameter_enum": [
        "val1",
        "val2"
       ],
       "parameter_invisible": 2,
       "parameter_longname": "live.text[3]",
       "parameter_mmax": 1,
       "parameter_modmode": 0,
       "parameter_shortname": "live.text",
       "parameter_type": 2
      }
     },
     "text": "Pop Out Big",
     "textcolor": [
      0.352941,
      0.352941,
      0.352941,
      1.0
     ],
     "textoffcolor": [
      0.352941,
      0.352941,
      0.352941,
      1.0
     ],
     "varname": "live.text[2]"
    }
   },
   {
    "box": {
     "id": "obj-48",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      101.0,
      881.25,
      32.0,
      20.0
     ],
     "text": "open"
    }
   },
   {
    "box": {
     "id": "obj-55",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      101.0,
      912.25,
      48.0,
      20.0
     ],
     "text": "pcontrol"
    }
   },
   {
    "box": {
     "id": "obj-10",
     "maxclass": "newobj",
     "numinlets": 3,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patcher": {
      "fileversion": 1,
      "appversion": {
       "major": 8,
       "minor": 6,
       "revision": 2,
       "architecture": "x64",
       "modernui": 1
      },
      "classnamespace": "box",
      "rect": [
       603.0,
       436.0,
       592.0,
       168.0
      ],
      "openrect": [
       0.0,
       0.0,
       592.0,
       168.0
      ],
      "bglocked": 0,
      "openinpresentation": 1,
      "default_fontsize": 12.0,
      "default_fontface": 0,
      "default_fontname": "Arial",
      "gridonopen": 1,
      "gridsize": [
       16.0,
       16.0
      ],
      "gridsnaponopen": 1,
      "objectsnaponopen": 1,
      "statusbarvisible": 2,
      "toolbarvisible": 1,
      "lefttoolbarpinned": 0,
      "toptoolbarpinned": 0,
      "righttoolbarpinned": 0,
      "bottomtoolbarpinned": 0,
      "toolbars_unpinned_last_save": 0,
      "tallnewobj": 0,
      "boxanimatetime": 200,
      "enablehscroll": 1,
      "enablevscroll": 1,
      "devicewidth": 0.0,
      "description": "",
      "digest": "",
      "tags": "",
      "style": "",
      "subpatcher_template": "",
      "assistshowspatchername": 0,
      "title": "LTC Timecode",
      "boxes": [
       {
        "box": {
         "comment": "",
         "id": "obj-12",
         "index": 2,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          196.0,
          9.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "id": "obj-7",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          8.0,
          9.0,
          143.0,
          21.0
         ],
         "presentation": 1,
         "presentation_rect": [
          8.0,
          8.0,
          85.0,
          21.0
         ],
         "text": "LTC Track",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ]
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-2",
         "index": 1,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          161.5,
          9.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-1",
         "index": 3,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          554.5000000000001,
          91.25,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Light",
         "fontsize": 10.0,
         "id": "obj-38",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          523.0,
          145.5,
          61.0,
          18.0
         ],
         "presentation": 1,
         "presentation_rect": [
          523.0,
          145.0,
          61.0,
          18.0
         ],
         "text": "-- FPS",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 2
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "id": "obj-27",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          424.5,
          115.25,
          143.0,
          21.0
         ],
         "presentation": 1,
         "presentation_rect": [
          453.0,
          120.0,
          85.0,
          21.0
         ],
         "text": "frames",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "id": "obj-26",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          294.5,
          115.25,
          143.0,
          21.0
         ],
         "presentation": 1,
         "presentation_rect": [
          320.0,
          120.0,
          85.0,
          21.0
         ],
         "text": "seconds",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "id": "obj-25",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          161.5,
          115.25,
          143.0,
          21.0
         ],
         "presentation": 1,
         "presentation_rect": [
          185.77464827895164,
          120.0,
          85.0,
          21.0
         ],
         "text": "minutes",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "id": "obj-24",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          25.5,
          115.25,
          143.0,
          21.0
         ],
         "presentation": 1,
         "presentation_rect": [
          53.0,
          120.0,
          85.0,
          21.0
         ],
         "text": "hours",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "fontsize": 90.0,
         "id": "obj-28",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          25.5,
          24.0,
          542.0,
          115.0
         ],
         "presentation": 1,
         "presentation_rect": [
          30.5,
          23.5,
          531.0,
          115.0
         ],
         "style": "redness",
         "text": "00:00:00:00",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-11",
         "index": 1,
         "maxclass": "outlet",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          0.5,
          207.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-3",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          726.8500845774361,
          856.0,
          84.0,
          22.0
         ],
         "text": "savewindow 0"
        }
       },
       {
        "box": {
         "id": "obj-10",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          340.85008457743606,
          856.0,
          116.0,
          22.0
         ],
         "text": "title \"LTC Timecode\""
        }
       },
       {
        "box": {
         "id": "obj-4",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          322.85008457743606,
          4.0,
          221.0,
          22.0
         ],
         "text": "window flags grow nofloat, window exec"
        }
       },
       {
        "box": {
         "id": "obj-9",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 2,
         "outlettype": [
          "",
          ""
         ],
         "patching_rect": [
          521.3500845774361,
          931.0,
          67.0,
          22.0
         ],
         "save": [
          "#N",
          "thispatcher",
          ";",
          "#Q",
          "end",
          ";"
         ],
         "text": "thispatcher"
        }
       },
       {
        "box": {
         "id": "obj-8",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          479.60225849047947,
          856.0,
          221.0,
          22.0
         ],
         "text": "window flags float nogrow, window exec"
        }
       },
       {
        "box": {
         "id": "obj-6",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "patching_rect": [
          521.3500845774361,
          787.0,
          58.0,
          22.0
         ],
         "text": "loadbang"
        }
       },
       {
        "box": {
         "appearance": 2,
         "id": "obj-42",
         "lcdcolor": [
          0.152941176470588,
          0.403921568627451,
          0.286274509803922,
          1.0
         ],
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
          8.0,
          146.0,
          96.0,
          16.0
         ],
         "presentation": 1,
         "presentation_rect": [
          8.0,
          146.0,
          96.0,
          16.0
         ],
         "saved_attribute_attributes": {
          "lcdcolor": {
           "expression": ""
          },
          "valueof": {
           "parameter_enum": [
            "val1",
            "val2"
           ],
           "parameter_longname": "live.text[4]",
           "parameter_mmax": 1,
           "parameter_modmode": 0,
           "parameter_shortname": "live.text",
           "parameter_type": 2
          }
         },
         "text": "Copy to Clipboard",
         "varname": "live.text[1]"
        }
       },
       {
        "box": {
         "angle": 270.0,
         "bgcolor": [
          0.070588235294118,
          0.07843137254902,
          0.086274509803922,
          1.0
         ],
         "hidden": 1,
         "id": "obj-5",
         "maxclass": "panel",
         "mode": 0,
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          0.5,
          0.0,
          592.0,
          168.0
         ],
         "presentation": 1,
         "presentation_rect": [
          0.0,
          0.0,
          592.0,
          168.0
         ],
         "proportion": 0.5,
         "saved_attribute_attributes": {
          "bgfillcolor": {
           "expression": ""
          }
         }
        }
       }
      ],
      "lines": [
       {
        "patchline": {
         "destination": [
          "obj-38",
          0
         ],
         "source": [
          "obj-1",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-9",
          0
         ],
         "midpoints": [
          350.35008457743606,
          895.0,
          530.8500845774361,
          895.0
         ],
         "source": [
          "obj-10",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-7",
          0
         ],
         "source": [
          "obj-12",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-28",
          0
         ],
         "source": [
          "obj-2",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-9",
          0
         ],
         "midpoints": [
          736.3500845774361,
          913.0,
          530.8500845774361,
          913.0
         ],
         "source": [
          "obj-3",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-9",
          0
         ],
         "midpoints": [
          332.35008457743606,
          625.0,
          530.8500845774361,
          625.0
         ],
         "source": [
          "obj-4",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-11",
          0
         ],
         "source": [
          "obj-42",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-10",
          0
         ],
         "order": 2,
         "source": [
          "obj-6",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-3",
          0
         ],
         "order": 0,
         "source": [
          "obj-6",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-8",
          0
         ],
         "order": 1,
         "source": [
          "obj-6",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-9",
          0
         ],
         "midpoints": [
          489.10225849047947,
          895.0,
          530.8500845774361,
          895.0
         ],
         "source": [
          "obj-8",
          0
         ]
        }
       }
      ],
      "bgcolor": [
       0.070588235294118,
       0.07843137254902,
       0.086274509803922,
       1.0
      ],
      "saved_attribute_attributes": {
       "default_plcolor": {
        "expression": ""
       },
       "locked_bgcolor": {
        "expression": ""
       }
      }
     },
     "patching_rect": [
      101.0,
      946.25,
      78.0,
      20.0
     ],
     "saved_attribute_attributes": {
      "default_plcolor": {
       "expression": ""
      },
      "locked_bgcolor": {
       "expression": ""
      }
     },
     "saved_object_attributes": {
      "description": "",
      "digest": "",
      "globalpatchername": "",
      "locked_bgcolor": [
       0.070588235294118,
       0.07843137254902,
       0.086274509803922,
       1.0
      ],
      "tags": ""
     },
     "text": "p Popup-Small"
    }
   },
   {
    "box": {
     "id": "obj-11",
     "linecount": 3,
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      697.0,
      477.5,
      150.0,
      40.0
     ],
     "text": "Mira sometimes doesn't\nget the first color update,\nso we send it a few times"
    }
   },
   {
    "box": {
     "id": "obj-8",
     "maxclass": "newobj",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patcher": {
      "fileversion": 1,
      "appversion": {
       "major": 8,
       "minor": 6,
       "revision": 2,
       "architecture": "x64",
       "modernui": 1
      },
      "classnamespace": "box",
      "rect": [
       1059.0,
       848.0,
       640.0,
       480.0
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
      "gridsnaponopen": 1,
      "objectsnaponopen": 1,
      "statusbarvisible": 2,
      "toolbarvisible": 1,
      "lefttoolbarpinned": 0,
      "toptoolbarpinned": 0,
      "righttoolbarpinned": 0,
      "bottomtoolbarpinned": 0,
      "toolbars_unpinned_last_save": 0,
      "tallnewobj": 0,
      "boxanimatetime": 200,
      "enablehscroll": 1,
      "enablevscroll": 1,
      "devicewidth": 0.0,
      "description": "",
      "digest": "",
      "tags": "",
      "style": "",
      "subpatcher_template": "",
      "assistshowspatchername": 0,
      "boxes": [
       {
        "box": {
         "comment": "",
         "id": "obj-5",
         "index": 2,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          "int"
         ],
         "patching_rect": [
          261.0,
          15.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-31",
         "maxclass": "button",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "parameter_enable": 0,
         "patching_rect": [
          195.0,
          18.0,
          24.0,
          24.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-23",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "patching_rect": [
          135.0,
          90.0,
          22.0,
          22.0
         ],
         "text": "t b"
        }
       },
       {
        "box": {
         "id": "obj-20",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          180.0,
          497.0,
          225.0,
          22.0
         ],
         "text": "textcolor 0.278 0.73 0.469 1.",
         "textcolor": [
          1.0,
          1.0,
          1.0,
          1.0
         ]
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-18",
         "index": 1,
         "maxclass": "outlet",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          117.5,
          497.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-17",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          117.5,
          422.0,
          117.0,
          22.0
         ],
         "text": "textcolor $1 $2 $3 1."
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-15",
         "index": 1,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          "int"
         ],
         "patching_rect": [
          135.0,
          15.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-13",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          247.0,
          180.0,
          99.0,
          22.0
         ],
         "text": "0.469, 0.469 100"
        }
       },
       {
        "box": {
         "id": "obj-14",
         "maxclass": "newobj",
         "numinlets": 3,
         "numoutlets": 2,
         "outlettype": [
          "",
          "bang"
         ],
         "patching_rect": [
          247.0,
          302.0,
          40.0,
          22.0
         ],
         "text": "line"
        }
       },
       {
        "box": {
         "id": "obj-11",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          135.0,
          180.0,
          85.0,
          22.0
         ],
         "text": "0.73, 0.73 100"
        }
       },
       {
        "box": {
         "id": "obj-12",
         "maxclass": "newobj",
         "numinlets": 3,
         "numoutlets": 2,
         "outlettype": [
          "",
          "bang"
         ],
         "patching_rect": [
          135.0,
          302.0,
          40.0,
          22.0
         ],
         "text": "line"
        }
       },
       {
        "box": {
         "id": "obj-4",
         "maxclass": "newobj",
         "numinlets": 3,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          117.5,
          377.0,
          54.0,
          22.0
         ],
         "text": "pack f f f"
        }
       },
       {
        "box": {
         "id": "obj-3",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          15.0,
          180.0,
          99.0,
          22.0
         ],
         "text": "0.278, 0.278 100"
        }
       },
       {
        "box": {
         "id": "obj-1",
         "maxclass": "newobj",
         "numinlets": 3,
         "numoutlets": 2,
         "outlettype": [
          "",
          "bang"
         ],
         "patching_rect": [
          15.0,
          302.0,
          40.0,
          22.0
         ],
         "text": "line"
        }
       },
       {
        "box": {
         "id": "obj-2",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          216.0,
          244.0,
          31.0,
          22.0
         ],
         "text": "stop"
        }
       }
      ],
      "lines": [
       {
        "patchline": {
         "destination": [
          "obj-4",
          0
         ],
         "source": [
          "obj-1",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-12",
          0
         ],
         "source": [
          "obj-11",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-4",
          1
         ],
         "source": [
          "obj-12",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-14",
          0
         ],
         "source": [
          "obj-13",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-4",
          2
         ],
         "source": [
          "obj-14",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-23",
          0
         ],
         "source": [
          "obj-15",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-18",
          0
         ],
         "order": 1,
         "source": [
          "obj-17",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-20",
          1
         ],
         "order": 0,
         "source": [
          "obj-17",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-1",
          0
         ],
         "order": 2,
         "source": [
          "obj-2",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-12",
          0
         ],
         "order": 1,
         "source": [
          "obj-2",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-14",
          0
         ],
         "order": 0,
         "source": [
          "obj-2",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-11",
          0
         ],
         "order": 1,
         "source": [
          "obj-23",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-13",
          0
         ],
         "order": 0,
         "source": [
          "obj-23",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-3",
          0
         ],
         "order": 2,
         "source": [
          "obj-23",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-1",
          0
         ],
         "source": [
          "obj-3",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-23",
          0
         ],
         "midpoints": [
          204.5,
          75.0,
          144.5,
          75.0
         ],
         "source": [
          "obj-31",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-17",
          0
         ],
         "source": [
          "obj-4",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-2",
          0
         ],
         "source": [
          "obj-5",
          0
         ]
        }
       }
      ],
      "saved_attribute_attributes": {
       "default_plcolor": {
        "expression": ""
       }
      }
     },
     "patching_rect": [
      700.5,
      535.0,
      83.0,
      20.0
     ],
     "saved_attribute_attributes": {
      "default_plcolor": {
       "expression": ""
      }
     },
     "saved_object_attributes": {
      "description": "",
      "digest": "",
      "globalpatchername": "",
      "tags": ""
     },
     "text": "p \"Force Color\""
    }
   },
   {
    "box": {
     "id": "obj-54",
     "maxclass": "newobj",
     "numinlets": 0,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      280.0,
      456.5,
      61.0,
      20.0
     ],
     "text": "receive init"
    }
   },
   {
    "box": {
     "id": "obj-53",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      697.0,
      436.0,
      50.0,
      20.0
     ],
     "text": "send init"
    }
   },
   {
    "box": {
     "id": "obj-51",
     "maxclass": "newobj",
     "numinlets": 4,
     "numoutlets": 0,
     "patcher": {
      "fileversion": 1,
      "appversion": {
       "major": 8,
       "minor": 6,
       "revision": 2,
       "architecture": "x64",
       "modernui": 1
      },
      "classnamespace": "box",
      "rect": [
       1615.0,
       258.0,
       640.0,
       480.0
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
      "gridsnaponopen": 1,
      "objectsnaponopen": 1,
      "statusbarvisible": 2,
      "toolbarvisible": 1,
      "lefttoolbarpinned": 0,
      "toptoolbarpinned": 0,
      "righttoolbarpinned": 0,
      "bottomtoolbarpinned": 0,
      "toolbars_unpinned_last_save": 0,
      "tallnewobj": 0,
      "boxanimatetime": 200,
      "enablehscroll": 1,
      "enablevscroll": 1,
      "devicewidth": 0.0,
      "description": "",
      "digest": "",
      "tags": "",
      "style": "",
      "subpatcher_template": "",
      "assistshowspatchername": 0,
      "boxes": [
       {
        "box": {
         "id": "obj-1",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          50.0,
          266.0,
          19.0,
          22.0
         ],
         "text": "t l"
        }
       },
       {
        "box": {
         "id": "obj-66",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          140.0,
          174.0,
          50.0,
          22.0
         ],
         "text": "fps --"
        }
       },
       {
        "box": {
         "id": "obj-64",
         "linecount": 2,
         "maxclass": "newobj",
         "numinlets": 2,
         "numoutlets": 2,
         "outlettype": [
          "",
          ""
         ],
         "patching_rect": [
          77.0,
          174.0,
          54.0,
          35.0
         ],
         "text": "zl.change"
        }
       },
       {
        "box": {
         "id": "obj-56",
         "linecount": 2,
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          94.0,
          100.0,
          37.0,
          35.0
         ],
         "text": "fps $1"
        }
       },
       {
        "box": {
         "id": "obj-55",
         "linecount": 2,
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          50.0,
          100.0,
          31.0,
          35.0
         ],
         "text": "tc $1"
        }
       },
       {
        "box": {
         "id": "obj-10",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          50.0,
          323.5,
          173.0,
          22.0
         ],
         "text": "udpsend 127.0.0.1 63123"
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-8",
         "index": 1,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          50.0,
          40.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-11",
         "index": 2,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          94.0,
          40.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-48",
         "index": 3,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          "int"
         ],
         "patching_rect": [
          140.0,
          40.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-ltc-config-in",
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "patching_rect": [
          220.0,
          40.0,
          30.0,
          30.0
         ],
         "index": 4,
         "outlettype": [
          ""
         ],
         "comment": "Destination UDP LTC"
        }
       }
      ],
      "lines": [
       {
        "patchline": {
         "destination": [
          "obj-10",
          0
         ],
         "source": [
          "obj-1",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-56",
          0
         ],
         "source": [
          "obj-11",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-66",
          0
         ],
         "source": [
          "obj-48",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-1",
          0
         ],
         "source": [
          "obj-55",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-64",
          0
         ],
         "order": 1,
         "source": [
          "obj-56",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-66",
          1
         ],
         "order": 0,
         "source": [
          "obj-56",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-1",
          0
         ],
         "midpoints": [
          86.5,
          228.0,
          59.5,
          228.0
         ],
         "source": [
          "obj-64",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-1",
          0
         ],
         "midpoints": [
          149.5,
          241.0,
          59.5,
          241.0
         ],
         "source": [
          "obj-66",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-55",
          0
         ],
         "source": [
          "obj-8",
          0
         ]
        }
       },
       {
        "patchline": {
         "source": [
          "obj-ltc-config-in",
          0
         ],
         "destination": [
          "obj-10",
          0
         ]
        }
       }
      ],
      "saved_attribute_attributes": {
       "default_plcolor": {
        "expression": ""
       }
      }
     },
     "patching_rect": [
      71.0,
      688.0,
      62.0,
      20.0
     ],
     "saved_attribute_attributes": {
      "default_plcolor": {
       "expression": ""
      }
     },
     "saved_object_attributes": {
      "description": "",
      "digest": "",
      "globalpatchername": "",
      "tags": ""
     },
     "text": "p udp-send"
    }
   },
   {
    "box": {
     "id": "obj-12",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 2,
     "outlettype": [
      "bang",
      "bang"
     ],
     "patcher": {
      "fileversion": 1,
      "appversion": {
       "major": 8,
       "minor": 6,
       "revision": 2,
       "architecture": "x64",
       "modernui": 1
      },
      "classnamespace": "box",
      "rect": [
       59.0,
       125.0,
       640.0,
       480.0
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
      "gridsnaponopen": 1,
      "objectsnaponopen": 1,
      "statusbarvisible": 2,
      "toolbarvisible": 1,
      "lefttoolbarpinned": 0,
      "toptoolbarpinned": 0,
      "righttoolbarpinned": 0,
      "bottomtoolbarpinned": 0,
      "toolbars_unpinned_last_save": 0,
      "tallnewobj": 0,
      "boxanimatetime": 200,
      "enablehscroll": 1,
      "enablevscroll": 1,
      "devicewidth": 0.0,
      "description": "",
      "digest": "",
      "tags": "",
      "style": "",
      "subpatcher_template": "",
      "assistshowspatchername": 0,
      "boxes": [
       {
        "box": {
         "comment": "",
         "id": "obj-3",
         "index": 2,
         "maxclass": "outlet",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          129.0,
          205.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-2",
         "index": 1,
         "maxclass": "outlet",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          64.0,
          205.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "fontname": "Arial Bold",
         "fontsize": 10.0,
         "id": "obj-11",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 3,
         "outlettype": [
          "bang",
          "stop",
          "bang"
         ],
         "patching_rect": [
          64.0,
          91.89617455005646,
          84.0,
          20.0
         ],
         "text": "t b stop b"
        }
       },
       {
        "box": {
         "id": "obj-8",
         "maxclass": "newobj",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "patching_rect": [
          64.0,
          131.0,
          61.0,
          22.0
         ],
         "text": "delay 250"
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-1",
         "index": 1,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          64.0,
          26.0,
          30.0,
          30.0
         ]
        }
       }
      ],
      "lines": [
       {
        "patchline": {
         "destination": [
          "obj-11",
          0
         ],
         "source": [
          "obj-1",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-3",
          0
         ],
         "source": [
          "obj-11",
          2
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-8",
          0
         ],
         "source": [
          "obj-11",
          1
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-8",
          0
         ],
         "source": [
          "obj-11",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-2",
          0
         ],
         "source": [
          "obj-8",
          0
         ]
        }
       }
      ],
      "saved_attribute_attributes": {
       "default_plcolor": {
        "expression": ""
       }
      }
     },
     "patching_rect": [
      436.0,
      393.0,
      65.0,
      20.0
     ],
     "saved_attribute_attributes": {
      "default_plcolor": {
       "expression": ""
      }
     },
     "saved_object_attributes": {
      "description": "",
      "digest": "",
      "globalpatchername": "",
      "tags": ""
     },
     "text": "p debounce"
    }
   },
   {
    "box": {
     "id": "obj-33",
     "maxclass": "newobj",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patcher": {
      "fileversion": 1,
      "appversion": {
       "major": 8,
       "minor": 6,
       "revision": 2,
       "architecture": "x64",
       "modernui": 1
      },
      "classnamespace": "box",
      "rect": [
       1126.0,
       484.0,
       640.0,
       480.0
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
      "gridsnaponopen": 1,
      "objectsnaponopen": 1,
      "statusbarvisible": 2,
      "toolbarvisible": 1,
      "lefttoolbarpinned": 0,
      "toptoolbarpinned": 0,
      "righttoolbarpinned": 0,
      "bottomtoolbarpinned": 0,
      "toolbars_unpinned_last_save": 0,
      "tallnewobj": 0,
      "boxanimatetime": 200,
      "enablehscroll": 1,
      "enablevscroll": 1,
      "devicewidth": 0.0,
      "description": "",
      "digest": "",
      "tags": "",
      "style": "",
      "subpatcher_template": "",
      "assistshowspatchername": 0,
      "boxes": [
       {
        "box": {
         "comment": "",
         "id": "obj-5",
         "index": 2,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          "int"
         ],
         "patching_rect": [
          261.0,
          15.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-31",
         "maxclass": "button",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "parameter_enable": 0,
         "patching_rect": [
          195.0,
          18.0,
          24.0,
          24.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-23",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "patching_rect": [
          135.0,
          90.0,
          22.0,
          22.0
         ],
         "text": "t b"
        }
       },
       {
        "box": {
         "id": "obj-20",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          180.0,
          497.0,
          225.0,
          22.0
         ],
         "text": "textcolor 0.152 0.402 0.285 1.",
         "textcolor": [
          1.0,
          1.0,
          1.0,
          1.0
         ]
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-18",
         "index": 1,
         "maxclass": "outlet",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          117.5,
          497.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-17",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          117.5,
          422.0,
          117.0,
          22.0
         ],
         "text": "textcolor $1 $2 $3 1."
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-15",
         "index": 1,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          "int"
         ],
         "patching_rect": [
          135.0,
          15.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-13",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          247.0,
          180.0,
          99.0,
          22.0
         ],
         "text": "0.469, 0.285 500"
        }
       },
       {
        "box": {
         "id": "obj-14",
         "maxclass": "newobj",
         "numinlets": 3,
         "numoutlets": 2,
         "outlettype": [
          "",
          "bang"
         ],
         "patching_rect": [
          247.0,
          302.0,
          40.0,
          22.0
         ],
         "text": "line"
        }
       },
       {
        "box": {
         "id": "obj-11",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          135.0,
          180.0,
          92.0,
          22.0
         ],
         "text": "0.73, 0.402 500"
        }
       },
       {
        "box": {
         "id": "obj-12",
         "maxclass": "newobj",
         "numinlets": 3,
         "numoutlets": 2,
         "outlettype": [
          "",
          "bang"
         ],
         "patching_rect": [
          135.0,
          302.0,
          40.0,
          22.0
         ],
         "text": "line"
        }
       },
       {
        "box": {
         "id": "obj-4",
         "maxclass": "newobj",
         "numinlets": 3,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          117.5,
          377.0,
          54.0,
          22.0
         ],
         "text": "pack f f f"
        }
       },
       {
        "box": {
         "id": "obj-3",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          15.0,
          180.0,
          99.0,
          22.0
         ],
         "text": "0.278, 0.152 500"
        }
       },
       {
        "box": {
         "id": "obj-1",
         "maxclass": "newobj",
         "numinlets": 3,
         "numoutlets": 2,
         "outlettype": [
          "",
          "bang"
         ],
         "patching_rect": [
          15.0,
          302.0,
          40.0,
          22.0
         ],
         "text": "line"
        }
       },
       {
        "box": {
         "id": "obj-2",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          216.0,
          244.0,
          31.0,
          22.0
         ],
         "text": "stop"
        }
       }
      ],
      "lines": [
       {
        "patchline": {
         "destination": [
          "obj-4",
          0
         ],
         "source": [
          "obj-1",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-12",
          0
         ],
         "source": [
          "obj-11",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-4",
          1
         ],
         "source": [
          "obj-12",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-14",
          0
         ],
         "source": [
          "obj-13",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-4",
          2
         ],
         "source": [
          "obj-14",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-23",
          0
         ],
         "source": [
          "obj-15",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-18",
          0
         ],
         "order": 1,
         "source": [
          "obj-17",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-20",
          1
         ],
         "order": 0,
         "source": [
          "obj-17",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-1",
          0
         ],
         "order": 2,
         "source": [
          "obj-2",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-12",
          0
         ],
         "order": 1,
         "source": [
          "obj-2",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-14",
          0
         ],
         "order": 0,
         "source": [
          "obj-2",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-11",
          0
         ],
         "order": 1,
         "source": [
          "obj-23",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-13",
          0
         ],
         "order": 0,
         "source": [
          "obj-23",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-3",
          0
         ],
         "order": 2,
         "source": [
          "obj-23",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-1",
          0
         ],
         "source": [
          "obj-3",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-23",
          0
         ],
         "midpoints": [
          204.5,
          75.0,
          144.5,
          75.0
         ],
         "source": [
          "obj-31",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-17",
          0
         ],
         "source": [
          "obj-4",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-2",
          0
         ],
         "source": [
          "obj-5",
          0
         ]
        }
       }
      ],
      "saved_attribute_attributes": {
       "default_plcolor": {
        "expression": ""
       }
      }
     },
     "patching_rect": [
      515.5,
      535.0,
      61.0,
      20.0
     ],
     "saved_attribute_attributes": {
      "default_plcolor": {
       "expression": ""
      }
     },
     "saved_object_attributes": {
      "description": "",
      "digest": "",
      "globalpatchername": "",
      "tags": ""
     },
     "text": "p Fade-Out"
    }
   },
   {
    "box": {
     "id": "obj-52",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      436.0,
      436.5,
      29.5,
      20.0
     ],
     "text": "0"
    }
   },
   {
    "box": {
     "id": "obj-49",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      482.0,
      436.5,
      29.5,
      20.0
     ],
     "text": "1"
    }
   },
   {
    "box": {
     "id": "obj-47",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 3,
     "outlettype": [
      "",
      "int",
      "int"
     ],
     "patching_rect": [
      471.5,
      468.5,
      44.0,
      20.0
     ],
     "text": "change"
    }
   },
   {
    "box": {
     "id": "obj-50",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      240.0,
      527.5,
      29.5,
      20.0
     ],
     "text": "1"
    }
   },
   {
    "box": {
     "id": "obj-46",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 3,
     "outlettype": [
      "",
      "int",
      "int"
     ],
     "patching_rect": [
      221.0,
      564.5,
      44.0,
      20.0
     ],
     "text": "change"
    }
   },
   {
    "box": {
     "id": "obj-44",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      339.5,
      648.5,
      145.0,
      20.0
     ],
     "text": "textcolor 0.152 0.402 0.285 1."
    }
   },
   {
    "box": {
     "id": "obj-36",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      524.5,
      648.25,
      140.0,
      20.0
     ],
     "text": "textcolor 0.278 0.73 0.469 1."
    }
   },
   {
    "box": {
     "id": "obj-45",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      280.0,
      556.5,
      29.5,
      20.0
     ],
     "text": "--"
    }
   },
   {
    "box": {
     "id": "obj-43",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "outlettype": [
      "list"
     ],
     "patching_rect": [
      96.0,
      828.0,
      54.0,
      20.0
     ],
     "text": "clipboard"
    }
   },
   {
    "box": {
     "appearance": 2,
     "id": "obj-42",
     "lcdbgcolor": [
      0.07843137254902,
      0.07843137254902,
      0.07843137254902,
      0.0
     ],
     "lcdcolor": [
      0.152941176470588,
      0.403921568627451,
      0.286274509803922,
      1.0
     ],
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
      447.9814813733101,
      1000.0,
      96.0,
      16.0
     ],
     "presentation": 1,
     "presentation_rect": [
      134.0,
      146.0,
      96.0,
      16.0
     ],
     "saved_attribute_attributes": {
      "lcdbgcolor": {
       "expression": ""
      },
      "lcdcolor": {
       "expression": ""
      },
      "valueof": {
       "parameter_enum": [
        "val1",
        "val2"
       ],
       "parameter_invisible": 2,
       "parameter_longname": "live.text[1]",
       "parameter_mmax": 1,
       "parameter_modmode": 0,
       "parameter_shortname": "Copy to Clipboard",
       "parameter_type": 2
      }
     },
     "text": "Copy to Clipboard",
     "varname": "live.text[1]"
    }
   },
   {
    "box": {
     "id": "obj-41",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      96.0,
      778.0,
      80.0,
      20.0
     ],
     "text": "set 00:00:00:00"
    }
   },
   {
    "box": {
     "fontname": "Ableton Sans Medium",
     "fontsize": 24.0,
     "id": "obj-39",
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      1827.0,
      850.25,
      143.0,
      35.0
     ],
     "presentation": 1,
     "presentation_rect": [
      1815.0,
      606.25,
      143.0,
      35.0
     ],
     "text": "-- FPS",
     "textcolor": [
      0.152,
      0.402,
      0.285,
      1.0
     ],
     "textjustification": 2
    }
   },
   {
    "box": {
     "fontname": "Ableton Sans Light",
     "id": "obj-38",
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      837.5,
      999.25,
      61.0,
      18.0
     ],
     "presentation": 1,
     "presentation_rect": [
      523.0,
      145.5,
      61.0,
      18.0
     ],
     "text": "-- FPS",
     "textcolor": [
      0.152,
      0.402,
      0.285,
      1.0
     ],
     "textjustification": 2
    }
   },
   {
    "box": {
     "id": "obj-35",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      256.5,
      765.0,
      19.0,
      20.0
     ],
     "text": "t l"
    }
   },
   {
    "box": {
     "id": "obj-40",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      256.5,
      688.0,
      59.0,
      20.0
     ],
     "text": "set $1 FPS"
    }
   },
   {
    "box": {
     "id": "obj-37",
     "linecount": 4,
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      10.0,
      10.0,
      150.0,
      51.0
     ],
     "text": "(c) Leo Bernard, leolabs.org\n\nPlease don't distribute this device or parts of it.",
     "textcolor": [
      0.427450980392157,
      0.843137254901961,
      1.0,
      1.0
     ]
    }
   },
   {
    "box": {
     "id": "obj-32",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      314.5,
      765.0,
      19.0,
      20.0
     ],
     "text": "t l"
    }
   },
   {
    "box": {
     "fontname": "Ableton Sans Medium",
     "fontsize": 24.0,
     "id": "obj-14",
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      1797.0,
      1028.7065217391305,
      91.0,
      35.0
     ],
     "presentation": 1,
     "presentation_rect": [
      1785.0,
      784.7065217391305,
      91.0,
      35.0
     ],
     "text": "frames",
     "textcolor": [
      0.152,
      0.402,
      0.285,
      1.0
     ],
     "textjustification": 1
    }
   },
   {
    "box": {
     "fontname": "Ableton Sans Medium",
     "fontsize": 24.0,
     "id": "obj-15",
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      1560.6740821983503,
      1028.7065217391305,
      103.0,
      35.0
     ],
     "presentation": 1,
     "presentation_rect": [
      1550.6740821983503,
      784.7065217391305,
      103.0,
      35.0
     ],
     "text": "seconds",
     "textcolor": [
      0.152,
      0.402,
      0.285,
      1.0
     ],
     "textjustification": 1
    }
   },
   {
    "box": {
     "fontname": "Ableton Sans Medium",
     "fontsize": 24.0,
     "id": "obj-19",
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      1333.4306039374806,
      1028.7065217391305,
      95.0,
      35.0
     ],
     "presentation": 1,
     "presentation_rect": [
      1323.4306039374806,
      784.7065217391305,
      95.0,
      35.0
     ],
     "text": "minutes",
     "textcolor": [
      0.152,
      0.402,
      0.285,
      1.0
     ],
     "textjustification": 1
    }
   },
   {
    "box": {
     "fontname": "Ableton Sans Medium",
     "fontsize": 24.0,
     "id": "obj-22",
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      1112.813212633133,
      1028.7065217391305,
      71.0,
      35.0
     ],
     "presentation": 1,
     "presentation_rect": [
      1105.813212633133,
      784.7065217391305,
      71.0,
      35.0
     ],
     "text": "hours",
     "textcolor": [
      0.152,
      0.402,
      0.285,
      1.0
     ]
    }
   },
   {
    "box": {
     "fontname": "Avenir",
     "fontsize": 166.0,
     "id": "obj-23",
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      1023.0,
      850.25,
      947.0,
      233.0
     ],
     "presentation": 1,
     "presentation_rect": [
      1011.0,
      606.25,
      947.0,
      233.0
     ],
     "style": "redness",
     "text": "00:00:00:00",
     "textcolor": [
      0.152,
      0.402,
      0.285,
      1.0
     ],
     "textjustification": 1
    }
   },
   {
    "box": {
     "id": "obj-29",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      217.0,
      874.25,
      32.0,
      20.0
     ],
     "text": "open"
    }
   },
   {
    "box": {
     "appearance": 2,
     "id": "obj-20",
     "lcdbgcolor": [
      0.07843137254902,
      0.07843137254902,
      0.07843137254902,
      0.0
     ],
     "lcdcolor": [
      0.152941176470588,
      0.403921568627451,
      0.286274509803922,
      1.0
     ],
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
      314.0,
      1000.0,
      54.0,
      16.0
     ],
     "presentation": 1,
     "presentation_rect": [
      8.0,
      146.0,
      54.0,
      16.0
     ],
     "saved_attribute_attributes": {
      "lcdbgcolor": {
       "expression": ""
      },
      "lcdcolor": {
       "expression": ""
      },
      "valueof": {
       "parameter_enum": [
        "val1",
        "val2"
       ],
       "parameter_invisible": 2,
       "parameter_longname": "live.text",
       "parameter_mmax": 1,
       "parameter_modmode": 0,
       "parameter_shortname": "live.text",
       "parameter_type": 2
      }
     },
     "text": "Pop Out",
     "varname": "live.text"
    }
   },
   {
    "box": {
     "id": "obj-17",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      217.0,
      907.25,
      48.0,
      20.0
     ],
     "text": "pcontrol"
    }
   },
   {
    "box": {
     "id": "obj-9",
     "maxclass": "newobj",
     "numinlets": 3,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patcher": {
      "fileversion": 1,
      "appversion": {
       "major": 8,
       "minor": 6,
       "revision": 2,
       "architecture": "x64",
       "modernui": 1
      },
      "classnamespace": "box",
      "rect": [
       742.0,
       274.0,
       1024.0,
       290.0
      ],
      "openrect": [
       0.0,
       0.0,
       1024.0,
       290.0
      ],
      "bglocked": 0,
      "openinpresentation": 1,
      "default_fontsize": 12.0,
      "default_fontface": 0,
      "default_fontname": "Arial",
      "gridonopen": 1,
      "gridsize": [
       16.0,
       16.0
      ],
      "gridsnaponopen": 1,
      "objectsnaponopen": 1,
      "statusbarvisible": 2,
      "toolbarvisible": 1,
      "lefttoolbarpinned": 0,
      "toptoolbarpinned": 0,
      "righttoolbarpinned": 0,
      "bottomtoolbarpinned": 0,
      "toolbars_unpinned_last_save": 0,
      "tallnewobj": 0,
      "boxanimatetime": 200,
      "enablehscroll": 1,
      "enablevscroll": 1,
      "devicewidth": 0.0,
      "description": "",
      "digest": "",
      "tags": "",
      "style": "",
      "subpatcher_template": "",
      "assistshowspatchername": 0,
      "title": "LTC Timecode",
      "boxes": [
       {
        "box": {
         "comment": "",
         "id": "obj-13",
         "index": 2,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          68.0,
          0.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "fontsize": 25.868981695307802,
         "id": "obj-12",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          27.0,
          20.0,
          318.0,
          38.0
         ],
         "presentation": 1,
         "presentation_rect": [
          10.0,
          7.0,
          919.0,
          38.0
         ],
         "text": "LTC Track",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ]
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-11",
         "index": 1,
         "maxclass": "outlet",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          52.0,
          335.0,
          30.0,
          30.0
         ],
         "presentation": 1,
         "presentation_rect": [
          52.0,
          335.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "appearance": 2,
         "fontsize": 12.0,
         "id": "obj-42",
         "lcdcolor": [
          0.152941176470588,
          0.403921568627451,
          0.286274509803922,
          1.0
         ],
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
          10.0,
          256.5,
          118.0,
          25.0
         ],
         "presentation": 1,
         "presentation_rect": [
          10.0,
          256.5,
          118.0,
          25.0
         ],
         "saved_attribute_attributes": {
          "lcdcolor": {
           "expression": ""
          },
          "valueof": {
           "parameter_enum": [
            "val1",
            "val2"
           ],
           "parameter_longname": "live.text[2]",
           "parameter_mmax": 1,
           "parameter_modmode": 0,
           "parameter_shortname": "live.text",
           "parameter_type": 2
          }
         },
         "text": "Copy to Clipboard",
         "varname": "live.text[1]"
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "fontsize": 20.0,
         "id": "obj-7",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          844.0000000000001,
          251.5,
          148.0,
          30.0
         ],
         "presentation": 1,
         "presentation_rect": [
          866.0,
          254.0,
          148.0,
          30.0
         ],
         "text": "-- FPS",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 2
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-1",
         "index": 3,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          746.0000000000001,
          204.45652173913044,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "id": "obj-3",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          726.8500845774361,
          856.0,
          84.0,
          22.0
         ],
         "text": "savewindow 0"
        }
       },
       {
        "box": {
         "id": "obj-10",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          340.85008457743606,
          856.0,
          116.0,
          22.0
         ],
         "text": "title \"LTC Timecode\""
        }
       },
       {
        "box": {
         "id": "obj-4",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          392.85008457743606,
          8.0,
          221.0,
          22.0
         ],
         "text": "window flags grow nofloat, window exec"
        }
       },
       {
        "box": {
         "id": "obj-9",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 2,
         "outlettype": [
          "",
          ""
         ],
         "patching_rect": [
          521.3500845774361,
          931.0,
          67.0,
          22.0
         ],
         "save": [
          "#N",
          "thispatcher",
          ";",
          "#Q",
          "end",
          ";"
         ],
         "text": "thispatcher"
        }
       },
       {
        "box": {
         "id": "obj-8",
         "maxclass": "message",
         "numinlets": 2,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          479.60225849047947,
          856.0,
          221.0,
          22.0
         ],
         "text": "window flags float nogrow, window exec"
        }
       },
       {
        "box": {
         "id": "obj-6",
         "maxclass": "newobj",
         "numinlets": 1,
         "numoutlets": 1,
         "outlettype": [
          "bang"
         ],
         "patching_rect": [
          521.3500845774361,
          787.0,
          58.0,
          22.0
         ],
         "text": "loadbang"
        }
       },
       {
        "box": {
         "comment": "",
         "id": "obj-2",
         "index": 1,
         "maxclass": "inlet",
         "numinlets": 0,
         "numoutlets": 1,
         "outlettype": [
          ""
         ],
         "patching_rect": [
          27.0,
          0.0,
          30.0,
          30.0
         ]
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "fontsize": 25.8689816953079,
         "id": "obj-27",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          792.1370410991751,
          200.45652173913044,
          185.15652173913043,
          38.0
         ],
         "presentation": 1,
         "presentation_rect": [
          792.1370410991751,
          200.45652173913044,
          185.15652173913043,
          38.0
         ],
         "text": "frames",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "fontsize": 25.86898169530805,
         "id": "obj-26",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          548.2674758817839,
          200.45652173913044,
          180.1565217391303,
          38.0
         ],
         "presentation": 1,
         "presentation_rect": [
          548.2674758817839,
          200.45652173913044,
          180.1565217391303,
          38.0
         ],
         "text": "seconds",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "fontsize": 25.86898169530772,
         "id": "obj-25",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          302.0239976209142,
          200.45652173913044,
          179.15652173913043,
          38.0
         ],
         "presentation": 1,
         "presentation_rect": [
          302.0239976209142,
          200.45652173913044,
          179.15652173913043,
          38.0
         ],
         "text": "minutes",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "fontsize": 25.868981695307802,
         "id": "obj-24",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          54.40660631656641,
          200.45652173913044,
          180.15652173913043,
          38.0
         ],
         "presentation": 1,
         "presentation_rect": [
          54.40660631656641,
          200.45652173913044,
          182.15652173913043,
          38.0
         ],
         "text": "hours",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "fontname": "Ableton Sans Medium",
         "fontsize": 166.0,
         "id": "obj-28",
         "maxclass": "comment",
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          27.0,
          37.0,
          970.0,
          206.0
         ],
         "presentation": 1,
         "presentation_rect": [
          27.0,
          34.0,
          970.0,
          206.0
         ],
         "style": "redness",
         "text": "00:00:00:00",
         "textcolor": [
          0.152,
          0.402,
          0.285,
          1.0
         ],
         "textjustification": 1
        }
       },
       {
        "box": {
         "angle": 270.0,
         "bgcolor": [
          0.070588235294118,
          0.07843137254902,
          0.086274509803922,
          1.0
         ],
         "hidden": 1,
         "id": "obj-5",
         "maxclass": "panel",
         "mode": 0,
         "numinlets": 1,
         "numoutlets": 0,
         "patching_rect": [
          0.0,
          0.0,
          1024.0,
          290.0
         ],
         "presentation": 1,
         "presentation_rect": [
          0.0,
          0.0,
          1024.0,
          290.0
         ],
         "proportion": 0.5,
         "saved_attribute_attributes": {
          "bgfillcolor": {
           "expression": ""
          }
         }
        }
       }
      ],
      "lines": [
       {
        "patchline": {
         "destination": [
          "obj-7",
          0
         ],
         "source": [
          "obj-1",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-9",
          0
         ],
         "midpoints": [
          350.35008457743606,
          895.0,
          530.8500845774361,
          895.0
         ],
         "source": [
          "obj-10",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-12",
          0
         ],
         "source": [
          "obj-13",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-28",
          0
         ],
         "source": [
          "obj-2",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-9",
          0
         ],
         "midpoints": [
          736.3500845774361,
          913.0,
          530.8500845774361,
          913.0
         ],
         "source": [
          "obj-3",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-9",
          0
         ],
         "midpoints": [
          402.35008457743606,
          625.0,
          530.8500845774361,
          625.0
         ],
         "source": [
          "obj-4",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-11",
          0
         ],
         "source": [
          "obj-42",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-10",
          0
         ],
         "order": 2,
         "source": [
          "obj-6",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-3",
          0
         ],
         "order": 0,
         "source": [
          "obj-6",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-8",
          0
         ],
         "order": 1,
         "source": [
          "obj-6",
          0
         ]
        }
       },
       {
        "patchline": {
         "destination": [
          "obj-9",
          0
         ],
         "midpoints": [
          489.10225849047947,
          895.0,
          530.8500845774361,
          895.0
         ],
         "source": [
          "obj-8",
          0
         ]
        }
       }
      ],
      "bgcolor": [
       0.070588235294118,
       0.07843137254902,
       0.086274509803922,
       1.0
      ],
      "saved_attribute_attributes": {
       "default_plcolor": {
        "expression": ""
       },
       "locked_bgcolor": {
        "expression": ""
       }
      }
     },
     "patching_rect": [
      152.5,
      985.25,
      68.0,
      20.0
     ],
     "saved_attribute_attributes": {
      "default_plcolor": {
       "expression": ""
      },
      "locked_bgcolor": {
       "expression": ""
      }
     },
     "saved_object_attributes": {
      "description": "",
      "digest": "",
      "globalpatchername": "",
      "locked_bgcolor": [
       0.070588235294118,
       0.07843137254902,
       0.086274509803922,
       1.0
      ],
      "tags": ""
     },
     "text": "p Popup-Big"
    }
   },
   {
    "box": {
     "id": "obj-18",
     "linecount": 2,
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      207.0,
      226.0,
      150.0,
      29.0
     ],
     "text": "When playback stops, \nfade timecode display"
    }
   },
   {
    "box": {
     "fontface": 1,
     "fontname": "Arial",
     "fontsize": 10.0,
     "id": "obj-34",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 3,
     "outlettype": [
      "",
      "int",
      "int"
     ],
     "patching_rect": [
      207.0,
      295.0,
      44.0,
      20.0
     ],
     "text": "change"
    }
   },
   {
    "box": {
     "fontface": 1,
     "fontname": "Arial",
     "fontsize": 10.0,
     "id": "obj-3",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 9,
     "outlettype": [
      "int",
      "int",
      "int",
      "float",
      "list",
      "float",
      "float",
      "int",
      "int"
     ],
     "patching_rect": [
      207.0,
      261.0,
      118.0,
      20.0
     ],
     "text": "plugsync~"
    }
   },
   {
    "box": {
     "id": "obj-7",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      318.0,
      571.5,
      145.0,
      20.0
     ],
     "text": "textcolor 0.152 0.402 0.285 1."
    }
   },
   {
    "box": {
     "id": "obj-6",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      495.5,
      571.5,
      140.0,
      20.0
     ],
     "text": "textcolor 0.278 0.73 0.469 1."
    }
   },
   {
    "box": {
     "fontname": "Ableton Sans Medium",
     "id": "obj-27",
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      738.5,
      965.5,
      143.0,
      18.0
     ],
     "presentation": 1,
     "presentation_rect": [
      453.0,
      120.0,
      85.0,
      18.0
     ],
     "text": "frames",
     "textcolor": [
      0.152,
      0.402,
      0.285,
      1.0
     ],
     "textjustification": 1
    }
   },
   {
    "box": {
     "fontname": "Ableton Sans Medium",
     "id": "obj-26",
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      608.5,
      965.5,
      143.0,
      18.0
     ],
     "presentation": 1,
     "presentation_rect": [
      320.0,
      120.0,
      85.0,
      18.0
     ],
     "text": "seconds",
     "textcolor": [
      0.152,
      0.402,
      0.285,
      1.0
     ],
     "textjustification": 1
    }
   },
   {
    "box": {
     "fontname": "Ableton Sans Medium",
     "id": "obj-25",
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      475.5,
      965.5,
      143.0,
      18.0
     ],
     "presentation": 1,
     "presentation_rect": [
      185.77464827895164,
      120.0,
      85.0,
      18.0
     ],
     "text": "minutes",
     "textcolor": [
      0.152,
      0.402,
      0.285,
      1.0
     ],
     "textjustification": 1
    }
   },
   {
    "box": {
     "fontname": "Ableton Sans Medium",
     "id": "obj-24",
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      339.5,
      965.5,
      143.0,
      18.0
     ],
     "presentation": 1,
     "presentation_rect": [
      53.0,
      120.0,
      85.0,
      18.0
     ],
     "text": "hours",
     "textcolor": [
      0.152,
      0.402,
      0.285,
      1.0
     ],
     "textjustification": 1
    }
   },
   {
    "box": {
     "id": "obj-21",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      364.0,
      692.0,
      80.0,
      20.0
     ],
     "text": "set 00:00:00:00"
    }
   },
   {
    "box": {
     "id": "obj-13",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 3,
     "outlettype": [
      "bang",
      "int",
      "int"
     ],
     "patching_rect": [
      664.5,
      393.0,
      77.0,
      20.0
     ],
     "text": "live.thisdevice"
    }
   },
   {
    "box": {
     "id": "obj-31",
     "maxclass": "message",
     "numinlets": 2,
     "numoutlets": 1,
     "outlettype": [
      ""
     ],
     "patching_rect": [
      212.0,
      688.0,
      37.0,
      20.0
     ],
     "text": "set $1"
    }
   },
   {
    "box": {
     "fontname": "Ableton Sans Medium",
     "fontsize": 90.0,
     "id": "obj-28",
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      339.5,
      874.25,
      542.0,
      115.0
     ],
     "presentation": 1,
     "presentation_rect": [
      30.5,
      23.5,
      531.0,
      115.0
     ],
     "style": "redness",
     "text": "00:00:00:00",
     "textcolor": [
      0.152,
      0.402,
      0.285,
      1.0
     ],
     "textjustification": 1
    }
   },
   {
    "box": {
     "fontname": "Arial Bold",
     "fontsize": 10.0,
     "id": "obj-2",
     "maxclass": "newobj",
     "numinlets": 2,
     "numoutlets": 2,
     "outlettype": [
      "signal",
      "signal"
     ],
     "patching_rect": [
      490.0,
      83.0,
      53.0,
      20.0
     ],
     "text": "plugout~"
    }
   },
   {
    "box": {
     "fontname": "Arial Bold",
     "fontsize": 10.0,
     "id": "obj-1",
     "maxclass": "newobj",
     "numinlets": 2,
     "numoutlets": 2,
     "outlettype": [
      "signal",
      "signal"
     ],
     "patching_rect": [
      490.0,
      41.0,
      53.0,
      20.0
     ],
     "text": "plugin~"
    }
   },
   {
    "box": {
     "angle": 270.0,
     "bgcolor": [
      0.070588235294118,
      0.07843137254902,
      0.086274509803922,
      1.0
     ],
     "hidden": 1,
     "id": "obj-5",
     "maxclass": "panel",
     "mode": 0,
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      314.5,
      850.25,
      592.0,
      168.0
     ],
     "presentation": 1,
     "presentation_rect": [
      0.0,
      0.0,
      592.0,
      168.0
     ],
     "proportion": 0.5,
     "saved_attribute_attributes": {
      "bgfillcolor": {
       "expression": ""
      }
     }
    }
   },
   {
    "box": {
     "background": 1,
     "color": [
      0.070588235294118,
      0.07843137254902,
      0.086274509803922,
      1.0
     ],
     "id": "obj-30",
     "ignoreclick": 1,
     "maxclass": "mira.frame",
     "numinlets": 0,
     "numoutlets": 0,
     "patching_rect": [
      983.0,
      623.25,
      1026.813212633133,
      730.0
     ],
     "presentation": 1,
     "presentation_rect": [
      971.0,
      390.25,
      1026.813212633133,
      730.0
     ],
     "tabname": "LTC Timecode"
    }
   },
   {
    "box": {
     "id": "obj-ltc-destination-label",
     "maxclass": "comment",
     "numinlets": 1,
     "numoutlets": 0,
     "patching_rect": [
      314.0,
      1040.0,
      36.0,
      18.0
     ],
     "presentation": 1,
     "presentation_rect": [
      330.0,
      145.0,
      28.0,
      18.0
     ],
     "text": "LTC→"
    }
   },
   {
    "box": {
     "id": "obj-ltc-host",
     "maxclass": "textedit",
     "numinlets": 1,
     "numoutlets": 4,
     "patching_rect": [
      360.0,
      1040.0,
      105.0,
      20.0
     ],
     "outlettype": [
      "",
      "int",
      "",
      ""
     ],
     "parameter_enable": 0,
     "presentation": 1,
     "presentation_rect": [
      360.0,
      143.0,
      105.0,
      20.0
     ],
     "text": "127.0.0.1",
     "varname": "ltc_destination"
    }
   },
   {
    "box": {
     "id": "obj-ltc-port",
     "maxclass": "textedit",
     "numinlets": 1,
     "numoutlets": 4,
     "patching_rect": [
      468.0,
      1040.0,
      50.0,
      20.0
     ],
     "outlettype": [
      "",
      "int",
      "",
      ""
     ],
     "parameter_enable": 0,
     "presentation": 1,
     "presentation_rect": [
      468.0,
      143.0,
      50.0,
      20.0
     ],
     "text": "63123",
     "varname": "ltc_port_input"
    }
   },
   {
    "box": {
     "id": "obj-ltc-route-text",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      314.0,
      1080.0,
      62.0,
      22.0
     ],
     "text": "route text"
    }
   },
   {
    "box": {
     "id": "obj-ltc-tosymbol",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      385.0,
      1080.0,
      55.0,
      22.0
     ],
     "text": "tosymbol"
    }
   },
   {
    "box": {
     "id": "obj-ltc-host-restore-trigger",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      500.0,
      1080.0,
      40.0,
      22.0
     ],
     "text": "t s s"
    }
   },
   {
    "box": {
     "id": "obj-ltc-host-message",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      550.0,
      1080.0,
      85.0,
      22.0
     ],
     "text": "prepend host"
    }
   },
   {
    "box": {
     "id": "obj-ltc-host-set",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      645.0,
      1080.0,
      75.0,
      22.0
     ],
     "text": "prepend set"
    }
   },
   {
    "box": {
     "id": "obj-ltc-host-pattr",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      314.0,
      1110.0,
      420.0,
      22.0
     ],
     "text": "pattr ltc_destination_state @bindto ltc_destination @initial 127.0.0.1 @type symbol @parameter_enable 1",
     "saved_object_attributes": {
      "parameter_enable": 1
     },
     "saved_attribute_attributes": {
      "valueof": {
       "parameter_invisible": 1,
       "parameter_longname": "LTC Destination",
       "parameter_shortname": "LTC Destination",
       "parameter_type": 3
      }
     }
    }
   },
   {
    "box": {
     "id": "obj-ltc-port-route-text",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      314.0,
      1150.0,
      62.0,
      22.0
     ],
     "text": "route text"
    }
   },
   {
    "box": {
     "id": "obj-ltc-port-fromsymbol",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      385.0,
      1150.0,
      72.0,
      22.0
     ],
     "text": "fromsymbol"
    }
   },
   {
    "box": {
     "id": "obj-ltc-port-int",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      465.0,
      1150.0,
      58.0,
      22.0
     ],
     "text": "route int"
    }
   },
   {
    "box": {
     "id": "obj-ltc-port-split",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      535.0,
      1150.0,
      80.0,
      22.0
     ],
     "text": "split 1 65535"
    }
   },
   {
    "box": {
     "id": "obj-ltc-port-invalid",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      545.0,
      1180.0,
      28.0,
      22.0
     ],
     "text": "t b"
    }
   },
   {
    "box": {
     "id": "obj-ltc-port-restore-int",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      575.0,
      1150.0,
      20.0,
      22.0
     ],
     "text": "i"
    }
   },
   {
    "box": {
     "id": "obj-ltc-port-restore-split",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      605.0,
      1150.0,
      80.0,
      22.0
     ],
     "text": "split 1 65535"
    }
   },
   {
    "box": {
     "id": "obj-ltc-port-restore-trigger",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      695.0,
      1150.0,
      40.0,
      22.0
     ],
     "text": "t i i"
    }
   },
   {
    "box": {
     "id": "obj-ltc-port-message",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      745.0,
      1150.0,
      82.0,
      22.0
     ],
     "text": "prepend port"
    }
   },
   {
    "box": {
     "id": "obj-ltc-port-set",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      835.0,
      1150.0,
      75.0,
      22.0
     ],
     "text": "prepend set"
    }
   },
   {
    "box": {
     "id": "obj-ltc-port-pattr",
     "maxclass": "newobj",
     "numinlets": 1,
     "numoutlets": 1,
     "patching_rect": [
      314.0,
      1180.0,
      320.0,
      22.0
     ],
     "text": "pattr ltc_port_state @initial 63123. @type float @min 1. @max 65535. @parameter_enable 1",
     "saved_object_attributes": {
      "parameter_enable": 1
     },
     "saved_attribute_attributes": {
      "valueof": {
       "parameter_invisible": 1,
       "parameter_longname": "LTC Port",
       "parameter_mmin": 1.0,
       "parameter_mmax": 65535.0,
       "parameter_shortname": "LTC Port",
       "parameter_type": 0,
       "parameter_unitstyle": 0
      }
     }
    }
   }
  ],
  "lines": [
   {
    "patchline": {
     "destination": [
      "obj-2",
      1
     ],
     "source": [
      "obj-1",
      1
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-2",
      0
     ],
     "order": 0,
     "source": [
      "obj-1",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-59",
      0
     ],
     "order": 1,
     "source": [
      "obj-1",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-41",
      0
     ],
     "midpoints": [
      110.5,
      976.0,
      81.0,
      976.0,
      81.0,
      772.0,
      105.5,
      772.0
     ],
     "source": [
      "obj-10",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-49",
      0
     ],
     "source": [
      "obj-12",
      1
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-52",
      0
     ],
     "source": [
      "obj-12",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-21",
      0
     ],
     "midpoints": [
      674.0,
      677.0,
      373.5,
      677.0
     ],
     "order": 2,
     "source": [
      "obj-13",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-52",
      0
     ],
     "midpoints": [
      674.0,
      426.5,
      445.5,
      426.5
     ],
     "order": 1,
     "source": [
      "obj-13",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-53",
      0
     ],
     "order": 0,
     "source": [
      "obj-13",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-9",
      0
     ],
     "midpoints": [
      226.5,
      970.0,
      162.0,
      970.0
     ],
     "source": [
      "obj-17",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-48",
      0
     ],
     "midpoints": [
      323.5,
      1035.0,
      289.39694714546204,
      1035.0,
      289.39694714546204,
      852.0,
      110.5,
      852.0
     ],
     "source": [
      "obj-20",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-32",
      0
     ],
     "midpoints": [
      373.5,
      754.0,
      324.0,
      754.0
     ],
     "order": 0,
     "source": [
      "obj-21",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-41",
      1
     ],
     "midpoints": [
      373.5,
      722.0,
      166.5,
      722.0
     ],
     "order": 1,
     "source": [
      "obj-21",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-17",
      0
     ],
     "source": [
      "obj-29",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-34",
      0
     ],
     "source": [
      "obj-3",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-32",
      0
     ],
     "midpoints": [
      221.5,
      754.0,
      324.0,
      754.0
     ],
     "order": 0,
     "source": [
      "obj-31",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-41",
      1
     ],
     "midpoints": [
      221.5,
      721.0,
      166.5,
      721.0
     ],
     "order": 2,
     "source": [
      "obj-31",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-77",
      0
     ],
     "order": 1,
     "source": [
      "obj-31",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-10",
      0
     ],
     "midpoints": [
      324.0,
      844.0,
      186.0,
      844.0,
      186.0,
      868.0,
      185.0,
      868.0,
      185.0,
      940.0,
      110.5,
      940.0
     ],
     "order": 3,
     "source": [
      "obj-32",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-23",
      0
     ],
     "midpoints": [
      324.0,
      833.0860217213631,
      1032.5,
      833.0860217213631
     ],
     "order": 0,
     "source": [
      "obj-32",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-28",
      0
     ],
     "midpoints": [
      324.0,
      859.0,
      349.0,
      859.0
     ],
     "order": 1,
     "source": [
      "obj-32",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-9",
      0
     ],
     "midpoints": [
      324.0,
      833.0,
      162.0,
      833.0
     ],
     "order": 2,
     "source": [
      "obj-32",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-32",
      0
     ],
     "midpoints": [
      525.0,
      565.0,
      480.0,
      565.0,
      480.0,
      610.0,
      495.0,
      610.0,
      495.0,
      751.0,
      324.0,
      751.0
     ],
     "order": 0,
     "source": [
      "obj-33",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-35",
      0
     ],
     "midpoints": [
      525.0,
      565.0,
      480.0,
      565.0,
      480.0,
      610.0,
      495.0,
      610.0,
      495.0,
      751.0,
      266.0,
      751.0
     ],
     "order": 1,
     "source": [
      "obj-33",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-51",
      2
     ],
     "midpoints": [
      229.0,
      508.0,
      123.5,
      508.0
     ],
     "source": [
      "obj-34",
      1
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-52",
      0
     ],
     "midpoints": [
      241.5,
      426.5,
      445.5,
      426.5
     ],
     "source": [
      "obj-34",
      2
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-10",
      2
     ],
     "midpoints": [
      266.0,
      823.0,
      169.5,
      823.0
     ],
     "order": 3,
     "source": [
      "obj-35",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-38",
      0
     ],
     "midpoints": [
      266.0,
      810.0,
      847.0,
      810.0
     ],
     "order": 1,
     "source": [
      "obj-35",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-39",
      0
     ],
     "midpoints": [
      266.0,
      810.0,
      1836.5,
      810.0
     ],
     "order": 0,
     "source": [
      "obj-35",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-9",
      2
     ],
     "midpoints": [
      266.0,
      811.0,
      211.0,
      811.0
     ],
     "order": 2,
     "source": [
      "obj-35",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-35",
      0
     ],
     "midpoints": [
      534.0,
      734.0,
      266.0,
      734.0
     ],
     "source": [
      "obj-36",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-56",
      6
     ],
     "source": [
      "obj-4",
      4
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-56",
      4
     ],
     "source": [
      "obj-4",
      3
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-56",
      2
     ],
     "source": [
      "obj-4",
      2
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-56",
      0
     ],
     "source": [
      "obj-4",
      1
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-60",
      0
     ],
     "source": [
      "obj-4",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-35",
      0
     ],
     "source": [
      "obj-40",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-43",
      0
     ],
     "source": [
      "obj-41",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-41",
      0
     ],
     "midpoints": [
      457.4814813733101,
      1053.0,
      276.0,
      1053.0,
      276.0,
      1053.0,
      57.0,
      1053.0,
      57.0,
      757.0,
      105.5,
      757.0
     ],
     "source": [
      "obj-42",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-35",
      0
     ],
     "midpoints": [
      349.0,
      722.0,
      266.0,
      722.0
     ],
     "source": [
      "obj-44",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-40",
      0
     ],
     "midpoints": [
      289.5,
      668.0,
      266.0,
      668.0
     ],
     "source": [
      "obj-45",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-36",
      0
     ],
     "midpoints": [
      255.5,
      605.0,
      534.0,
      605.0
     ],
     "source": [
      "obj-46",
      2
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-44",
      0
     ],
     "midpoints": [
      243.0,
      610.0,
      349.0,
      610.0
     ],
     "source": [
      "obj-46",
      1
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-33",
      0
     ],
     "order": 1,
     "source": [
      "obj-47",
      2
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-33",
      1
     ],
     "order": 1,
     "source": [
      "obj-47",
      1
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-50",
      0
     ],
     "midpoints": [
      506.0,
      514.0,
      249.5,
      514.0
     ],
     "order": 2,
     "source": [
      "obj-47",
      2
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-6",
      0
     ],
     "order": 2,
     "source": [
      "obj-47",
      1
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-8",
      1
     ],
     "order": 0,
     "source": [
      "obj-47",
      2
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-8",
      0
     ],
     "order": 0,
     "source": [
      "obj-47",
      1
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-55",
      0
     ],
     "source": [
      "obj-48",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-47",
      0
     ],
     "source": [
      "obj-49",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-46",
      0
     ],
     "source": [
      "obj-50",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-47",
      0
     ],
     "source": [
      "obj-52",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-44",
      0
     ],
     "midpoints": [
      289.5,
      541.0,
      315.0,
      541.0,
      315.0,
      610.0,
      349.0,
      610.0
     ],
     "order": 0,
     "source": [
      "obj-54",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-45",
      0
     ],
     "order": 2,
     "source": [
      "obj-54",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-50",
      0
     ],
     "midpoints": [
      289.5,
      514.0,
      249.5,
      514.0
     ],
     "order": 3,
     "source": [
      "obj-54",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-7",
      0
     ],
     "midpoints": [
      289.5,
      541.0,
      327.5,
      541.0
     ],
     "order": 1,
     "source": [
      "obj-54",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-10",
      0
     ],
     "source": [
      "obj-55",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-31",
      0
     ],
     "midpoints": [
      487.0,
      340.0,
      90.0,
      340.0,
      90.0,
      543.0,
      89.0,
      543.0,
      89.0,
      675.0,
      221.5,
      675.0
     ],
     "order": 1,
     "source": [
      "obj-56",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-51",
      0
     ],
     "midpoints": [
      487.0,
      327.0,
      80.5,
      327.0
     ],
     "order": 2,
     "source": [
      "obj-56",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-70",
      0
     ],
     "order": 0,
     "source": [
      "obj-56",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-29",
      0
     ],
     "midpoints": [
      382.5,
      1044.5572531223297,
      276.0,
      1044.5572531223297,
      276.0,
      859.0,
      226.5,
      859.0
     ],
     "source": [
      "obj-57",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-4",
      0
     ],
     "source": [
      "obj-59",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-32",
      0
     ],
     "midpoints": [
      505.0,
      754.0,
      324.0,
      754.0
     ],
     "source": [
      "obj-6",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-61",
      0
     ],
     "source": [
      "obj-60",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-40",
      0
     ],
     "midpoints": [
      394.5,
      366.0,
      117.0,
      366.0,
      117.0,
      656.0,
      266.0,
      656.0
     ],
     "order": 1,
     "source": [
      "obj-61",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-51",
      1
     ],
     "midpoints": [
      394.5,
      355.0,
      102.0,
      355.0
     ],
     "order": 2,
     "source": [
      "obj-61",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-70",
      1
     ],
     "order": 0,
     "source": [
      "obj-61",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-67",
      0
     ],
     "source": [
      "obj-65",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-74",
      0
     ],
     "source": [
      "obj-67",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-32",
      0
     ],
     "source": [
      "obj-7",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-12",
      0
     ],
     "order": 1,
     "source": [
      "obj-70",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-82",
      0
     ],
     "order": 0,
     "source": [
      "obj-70",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-65",
      0
     ],
     "source": [
      "obj-72",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-83",
      0
     ],
     "source": [
      "obj-74",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-74",
      0
     ],
     "source": [
      "obj-78",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-23",
      0
     ],
     "midpoints": [
      710.0,
      684.0,
      1032.5,
      684.0
     ],
     "source": [
      "obj-8",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-10",
      1
     ],
     "order": 1,
     "source": [
      "obj-81",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-9",
      1
     ],
     "order": 0,
     "source": [
      "obj-81",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-75",
      1
     ],
     "order": 1,
     "source": [
      "obj-82",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-85",
      0
     ],
     "source": [
      "obj-82",
      1
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-95",
      0
     ],
     "order": 0,
     "source": [
      "obj-82",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-82",
      1
     ],
     "source": [
      "obj-84",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-74",
      1
     ],
     "source": [
      "obj-86",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-41",
      0
     ],
     "midpoints": [
      162.0,
      1023.0,
      70.0,
      1023.0,
      70.0,
      763.0,
      105.5,
      763.0
     ],
     "source": [
      "obj-9",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-31",
      0
     ],
     "midpoints": [
      864.25,
      634.0,
      221.5,
      634.0
     ],
     "order": 0,
     "source": [
      "obj-95",
      0
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-40",
      0
     ],
     "midpoints": [
      934.25,
      634.0,
      266.0,
      634.0
     ],
     "order": 0,
     "source": [
      "obj-95",
      1
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-51",
      1
     ],
     "midpoints": [
      934.25,
      619.0,
      102.0,
      619.0
     ],
     "order": 1,
     "source": [
      "obj-95",
      1
     ]
    }
   },
   {
    "patchline": {
     "destination": [
      "obj-51",
      0
     ],
     "midpoints": [
      864.25,
      619.0,
      80.5,
      619.0
     ],
     "order": 1,
     "source": [
      "obj-95",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-host",
      0
     ],
     "destination": [
      "obj-ltc-route-text",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-route-text",
      0
     ],
     "destination": [
      "obj-ltc-tosymbol",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-tosymbol",
      0
     ],
     "destination": [
      "obj-ltc-host-pattr",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-host-pattr",
      0
     ],
     "destination": [
      "obj-ltc-host-restore-trigger",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-host-restore-trigger",
      0
     ],
     "destination": [
      "obj-ltc-host-message",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-host-restore-trigger",
      1
     ],
     "destination": [
      "obj-ltc-host-set",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-host-set",
      0
     ],
     "destination": [
      "obj-ltc-host",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-host-message",
      0
     ],
     "destination": [
      "obj-51",
      3
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port",
      0
     ],
     "destination": [
      "obj-ltc-port-route-text",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-route-text",
      0
     ],
     "destination": [
      "obj-ltc-port-fromsymbol",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-fromsymbol",
      0
     ],
     "destination": [
      "obj-ltc-port-int",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-int",
      0
     ],
     "destination": [
      "obj-ltc-port-split",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-int",
      1
     ],
     "destination": [
      "obj-ltc-port-invalid",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-split",
      0
     ],
     "destination": [
      "obj-ltc-port-pattr",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-split",
      1
     ],
     "destination": [
      "obj-ltc-port-invalid",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-invalid",
      0
     ],
     "destination": [
      "obj-ltc-port-pattr",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-pattr",
      0
     ],
     "destination": [
      "obj-ltc-port-restore-int",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-restore-int",
      0
     ],
     "destination": [
      "obj-ltc-port-restore-split",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-restore-split",
      0
     ],
     "destination": [
      "obj-ltc-port-restore-trigger",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-restore-trigger",
      0
     ],
     "destination": [
      "obj-ltc-port-message",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-restore-trigger",
      1
     ],
     "destination": [
      "obj-ltc-port-set",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-set",
      0
     ],
     "destination": [
      "obj-ltc-port",
      0
     ]
    }
   },
   {
    "patchline": {
     "source": [
      "obj-ltc-port-message",
      0
     ],
     "destination": [
      "obj-51",
      3
     ]
    }
   }
  ],
  "parameters": {
   "obj-10::obj-42": [
    "live.text[4]",
    "live.text",
    0
   ],
   "obj-20": [
    "live.text",
    "live.text",
    0
   ],
   "obj-42": [
    "live.text[1]",
    "Copy to Clipboard",
    0
   ],
   "obj-57": [
    "live.text[3]",
    "live.text",
    0
   ],
   "obj-72": [
    "live.text[6]",
    "Jump to Timecode",
    0
   ],
   "obj-9::obj-42": [
    "live.text[2]",
    "live.text",
    0
   ],
   "parameterbanks": {},
   "inherited_shortname": 1
  },
  "dependency_cache": [
   {
    "name": "cache.js",
    "bootpath": "~/Music/Ableton/User Library/Presets/Audio Effects/Max Audio Effect",
    "type": "TEXT",
    "implicit": 1
   },
   {
    "name": "clipboard.mxo",
    "type": "iLaX"
   },
   {
    "name": "smpte_decode6~.mxo",
    "type": "iLaX"
   }
  ],
  "latency": 0,
  "is_mpe": 0,
  "minimum_live_version": "",
  "minimum_max_version": "",
  "platform_compatibility": 0,
  "project": {
   "version": 1,
   "creationdate": 3590052493,
   "modificationdate": 3590052493,
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
    "patchers": {},
    "code": {},
    "externals": {}
   },
   "layout": {},
   "searchpath": {},
   "detailsvisible": 0,
   "amxdtype": 1633771873,
   "readonly": 0,
   "devpathtype": 0,
   "devpath": ".",
   "sortmode": 0,
   "viewmode": 0,
   "includepackages": 0
  },
  "autosave": 0,
  "bgcolor": [
   0.070588235294118,
   0.07843137254902,
   0.086274509803922,
   1.0
  ],
  "saved_attribute_attributes": {
   "default_plcolor": {
    "expression": ""
   },
   "locked_bgcolor": {
    "expression": ""
   }
  }
 }
}
