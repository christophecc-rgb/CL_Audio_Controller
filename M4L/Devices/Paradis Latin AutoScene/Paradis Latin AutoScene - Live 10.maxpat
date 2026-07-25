{
  "patcher": {
    "fileversion": 1,
    "appversion": {
      "major": 8,
      "minor": 1,
      "revision": 11,
      "architecture": "x64",
      "modernui": 1
    },
    "classnamespace": "box",
    "rect": [
      80.0,
      80.0,
      920.0,
      620.0
    ],
    "openrect": [
      0.0,
      0.0,
      720.0,
      169.0
    ],
    "devicewidth": 720.0,
    "bglocked": 1,
    "openinpresentation": 1,
    "default_fontname": "Avenir Next",
    "default_fontsize": 12.0,
    "gridsize": [
      10.0,
      10.0
    ],
    "boxes": [
      {
        "box": {
          "id": "bg",
          "maxclass": "panel",
          "patching_rect": [
            20.0,
            20.0,
            720.0,
            360.0
          ],
          "presentation": 1,
          "presentation_rect": [
            0.0,
            0.0,
            720.0,
            169.0
          ],
          "background": 1,
          "bgcolor": [
            0.063,
            0.071,
            0.082,
            1.0
          ],
          "border": 0,
          "mode": 0,
          "angle": 270.0,
          "proportion": 0.39,
          "bgfillcolor_type": "color",
          "bgfillcolor_color": [
            0.063,
            0.071,
            0.082,
            1.0
          ],
          "bgfillcolor_color1": [
            0.063,
            0.071,
            0.082,
            1.0
          ],
          "bgfillcolor_color2": [
            0.063,
            0.071,
            0.082,
            1.0
          ],
          "gradient": 0
        }
      },
      {
        "box": {
          "id": "header",
          "maxclass": "panel",
          "patching_rect": [
            20.0,
            20.0,
            720.0,
            72.0
          ],
          "presentation": 1,
          "presentation_rect": [
            0.0,
            0.0,
            720.0,
            50.0
          ],
          "background": 1,
          "bgcolor": [
            0.09,
            0.09,
            0.09,
            1.0
          ],
          "border": 0,
          "mode": 0,
          "angle": 270.0,
          "proportion": 0.39,
          "bgfillcolor_type": "color",
          "bgfillcolor_color": [
            0.09,
            0.09,
            0.09,
            1.0
          ],
          "bgfillcolor_color1": [
            0.09,
            0.09,
            0.09,
            1.0
          ],
          "bgfillcolor_color2": [
            0.09,
            0.09,
            0.09,
            1.0
          ],
          "gradient": 0
        }
      },
      {
        "box": {
          "id": "logo",
          "maxclass": "fpic",
          "pic": "paradis_latin_logo.jpg",
          "autofit": 1,
          "forceaspect": 1,
          "ignoreclick": 1,
          "patching_rect": [
            44.0,
            28.0,
            330.0,
            60.0
          ],
          "presentation": 1,
          "presentation_rect": [
            18.0,
            -3.9,
            190.0,
            57.8
          ]
        }
      },
      {
        "box": {
          "id": "subtitle",
          "maxclass": "comment",
          "text": "DÉPART AUTOMATIQUE DE SCÈNE",
          "fontsize": 10.0,
          "fontface": 1,
          "textjustification": 1,
          "textcolor": [
            0.8901960784313725,
            0.3764705882352941,
            0.3764705882352941,
            1.0
          ],
          "patching_rect": [
            420.0,
            48.0,
            290.0,
            24.0
          ],
          "presentation": 1,
          "presentation_rect": [
            238.93807232379913,
            7.079646587371826,
            185.0,
            20.0
          ]
        }
      },
      {
        "box": {
          "id": "time-label",
          "maxclass": "comment",
          "text": "HEURE DE DÉPART",
          "fontsize": 10.0,
          "fontface": 1,
          "textcolor": [
            0.8156862745098039,
            0.6901960784313725,
            0.08235294117647059,
            1.0
          ],
          "patching_rect": [
            48.0,
            112.0,
            150.0,
            20.0
          ],
          "presentation": 1,
          "presentation_rect": [
            543.5,
            7.079646587371826,
            166.0,
            20.0
          ]
        }
      },
      {
        "box": {
          "id": "hour",
          "maxclass": "umenu",
          "varname": "heure_depart",
          "fontsize": 18.0,
          "fontname": "Arial Rounded MT Bold",
          "fontface": 1,
          "items": [
            "00",
            ",",
            "01",
            ",",
            "02",
            ",",
            "03",
            ",",
            "04",
            ",",
            "05",
            ",",
            "06",
            ",",
            "07",
            ",",
            "08",
            ",",
            "09",
            ",",
            "10",
            ",",
            "11",
            ",",
            "12",
            ",",
            "13",
            ",",
            "14",
            ",",
            "15",
            ",",
            "16",
            ",",
            "17",
            ",",
            "18",
            ",",
            "19",
            ",",
            "20",
            ",",
            "21",
            ",",
            "22",
            ",",
            "23"
          ],
          "patching_rect": [
            48.0,
            136.0,
            52.0,
            28.0
          ],
          "presentation": 1,
          "presentation_rect": [
            539.0,
            29.400000000000006,
            54.0,
            29.0
          ],
          "bgcolor": [
            0.11,
            0.12,
            0.14,
            1.0
          ],
          "textcolor": [
            0.7019607843137254,
            0.25882352941176473,
            0.07058823529411765,
            1.0
          ],
          "bgfillcolor_angle": 270.0,
          "bgfillcolor_color": [
            0.11,
            0.12,
            0.14,
            1.0
          ],
          "bgfillcolor_color1": [
            0.13825893909668954,
            0.14395080499165816,
            0.16744603916432302,
            1
          ],
          "bgfillcolor_color2": [
            0.13825893909668954,
            0.14395080499165816,
            0.16744603916432302,
            1
          ],
          "bgfillcolor_proportion": 0.39,
          "bgfillcolor_type": "color"
        }
      },
      {
        "box": {
          "id": "colon1",
          "maxclass": "comment",
          "text": ":",
          "fontsize": 18.0,
          "fontname": "Arial Rounded MT Bold",
          "fontface": 1,
          "textcolor": [
            0.6,
            0.6,
            0.6,
            1.0
          ],
          "patching_rect": [
            104.0,
            136.0,
            16.0,
            28.0
          ],
          "presentation": 1,
          "presentation_rect": [
            587.0,
            29.400000000000006,
            23.0,
            27.0
          ]
        }
      },
      {
        "box": {
          "id": "minute",
          "maxclass": "number",
          "varname": "minute_depart",
          "minimum": 0,
          "maximum": 59,
          "fontsize": 18.0,
          "fontname": "Arial Rounded MT Bold",
          "fontface": 1,
          "patching_rect": [
            120.0,
            136.0,
            52.0,
            28.0
          ],
          "presentation": 1,
          "presentation_rect": [
            595.0,
            29.400000000000006,
            55.0,
            29.0
          ],
          "bgcolor": [
            0.11,
            0.12,
            0.14,
            1.0
          ],
          "textcolor": [
            0.7019607843137254,
            0.25882352941176473,
            0.07058823529411765,
            1.0
          ]
        }
      },
      {
        "box": {
          "id": "colon2",
          "maxclass": "comment",
          "text": ":",
          "fontsize": 18.0,
          "fontname": "Arial Rounded MT Bold",
          "fontface": 1,
          "textcolor": [
            0.6,
            0.6,
            0.6,
            1.0
          ],
          "patching_rect": [
            176.0,
            136.0,
            16.0,
            28.0
          ],
          "presentation": 1,
          "presentation_rect": [
            649.0,
            29.400000000000006,
            23.0,
            27.0
          ]
        }
      },
      {
        "box": {
          "id": "second",
          "maxclass": "umenu",
          "varname": "seconde_depart",
          "fontsize": 18.0,
          "fontname": "Arial Rounded MT Bold",
          "fontface": 1,
          "items": [
            "00",
            ",",
            "15",
            ",",
            "30",
            ",",
            "45"
          ],
          "patching_rect": [
            192.0,
            136.0,
            52.0,
            28.0
          ],
          "presentation": 1,
          "presentation_rect": [
            654.0,
            29.400000000000006,
            62.0,
            29.0
          ],
          "bgcolor": [
            0.11,
            0.12,
            0.14,
            1.0
          ],
          "textcolor": [
            0.7019607843137254,
            0.25882352941176473,
            0.07058823529411765,
            1.0
          ],
          "bgfillcolor_angle": 270.0,
          "bgfillcolor_color": [
            0.11,
            0.12,
            0.14,
            1.0
          ],
          "bgfillcolor_color1": [
            0.13825893909668954,
            0.14395080499165816,
            0.16744603916432302,
            1
          ],
          "bgfillcolor_color2": [
            0.13825893909668954,
            0.14395080499165816,
            0.16744603916432302,
            1
          ],
          "bgfillcolor_proportion": 0.39,
          "bgfillcolor_type": "color"
        }
      },
      {
        "box": {
          "id": "scene-label",
          "maxclass": "comment",
          "text": "ENTREE PUBLIC · LA SÉLECTION ARME LE DÉPART",
          "fontsize": 10.0,
          "fontface": 1,
          "textcolor": [
            0.10980392156862745,
            0.611764705882353,
            0.2784313725490196,
            1.0
          ],
          "patching_rect": [
            288.0,
            112.0,
            220.0,
            20.0
          ],
          "presentation": 1,
          "presentation_rect": [
            215.9292209148407,
            33.900000000000006,
            255.0,
            20.0
          ]
        }
      },
      {
        "box": {
          "id": "scene-menu",
          "maxclass": "umenu",
          "varname": "scene_selectionnee",
          "parameter_enable": 1,
          "fontsize": 12.0,
          "fontface": 1,
          "patching_rect": [
            288.0,
            136.0,
            306.0,
            28.0
          ],
          "presentation": 1,
          "presentation_rect": [
            17.699116468429565,
            69.0265542268753,
            470.0,
            25.0
          ],
          "bgcolor": [
            0.055,
            0.067,
            0.086,
            1.0
          ],
          "textcolor": [
            0.96,
            0.96,
            0.96,
            1.0
          ],
          "bgfillcolor_angle": 270.0,
          "bgfillcolor_autogradient": 0.0,
          "bgfillcolor_color": [
            0.055,
            0.067,
            0.086,
            1.0
          ],
          "bgfillcolor_color1": [
            0.055,
            0.067,
            0.086,
            1.0
          ],
          "bgfillcolor_color2": [
            0.055,
            0.067,
            0.086,
            1.0
          ],
          "bgfillcolor_proportion": 0.39,
          "bgfillcolor_type": "color",
          "elementcolor": [
            0.25,
            0.55,
            0.9,
            1.0
          ],
          "hilitecolor": [
            0.0392156862745098,
            0.40784313725490196,
            0.8156862745098039,
            1.0
          ],
          "textcolor_inverse": [
            1.0,
            1.0,
            1.0,
            1.0
          ],
          "applycolors": 1
        }
      },
      {
        "box": {
          "id": "refresh",
          "maxclass": "textbutton",
          "text": "↻  ACTUALISER",
          "fontface": 1,
          "patching_rect": [
            604.0,
            136.0,
            112.0,
            28.0
          ],
          "presentation": 1,
          "presentation_rect": [
            500.0,
            68.0265542268753,
            98.0,
            27.0
          ],
          "bgcolor": [
            0.0392156862745098,
            0.40784313725490196,
            0.8156862745098039,
            1.0
          ],
          "textcolor": [
            0.96,
            0.96,
            0.96,
            1.0
          ]
        }
      },
      {
        "box": {
          "id": "floating-button",
          "maxclass": "textbutton",
          "text": "FENÊTRE",
          "fontface": 1,
          "patching_rect": [
            620.0,
            410.0,
            96.0,
            24.0
          ],
          "presentation": 1,
          "presentation_rect": [
            606.0,
            68.0265542268753,
            100.0,
            27.0
          ],
          "bgcolor": [
            0.45098039215686275,
            0.21176470588235294,
            0.4823529411764706,
            1.0
          ],
          "textcolor": [
            0.96,
            0.96,
            0.96,
            1.0
          ]
        }
      },
      {
        "box": {
          "id": "clock-label",
          "maxclass": "comment",
          "text": "HEURE ACTUELLE",
          "fontsize": 9.0,
          "fontface": 1,
          "textcolor": [
            0.6,
            0.6,
            0.6,
            1.0
          ],
          "patching_rect": [
            48.0,
            196.0,
            150.0,
            20.0
          ],
          "presentation": 1,
          "presentation_rect": [
            18.0,
            104.0,
            112.0,
            19.0
          ]
        }
      },
      {
        "box": {
          "id": "clock-display",
          "maxclass": "message",
          "text": "00:00:00",
          "fontsize": 16.0,
          "fontface": 1,
          "patching_rect": [
            48.0,
            218.0,
            150.0,
            38.0
          ],
          "presentation": 1,
          "presentation_rect": [
            18.0,
            121.0,
            112.0,
            30.0
          ],
          "bgcolor": [
            0.11,
            0.12,
            0.14,
            1.0
          ],
          "textcolor": [
            0.9254901960784314,
            0.396078431372549,
            0.396078431372549,
            1.0
          ],
          "bgcolor2": [
            0.13825893909668954,
            0.14395080499165816,
            0.16744603916432302,
            1
          ],
          "gradient": 1,
          "bgfillcolor_angle": 270.0,
          "bgfillcolor_autogradient": 0.0,
          "bgfillcolor_color": [
            0.13825893909668954,
            0.14395080499165816,
            0.16744603916432302,
            1
          ],
          "bgfillcolor_color1": [
            0.11,
            0.12,
            0.14,
            1.0
          ],
          "bgfillcolor_color2": [
            0.13825893909668954,
            0.14395080499165816,
            0.16744603916432302,
            1
          ],
          "bgfillcolor_proportion": 0.39,
          "bgfillcolor_type": "gradient"
        }
      },
      {
        "box": {
          "id": "count-label",
          "maxclass": "comment",
          "text": "TEMPS RESTANT",
          "fontsize": 9.0,
          "fontface": 1,
          "textcolor": [
            0.6,
            0.6,
            0.6,
            1.0
          ],
          "patching_rect": [
            218.0,
            196.0,
            150.0,
            20.0
          ],
          "presentation": 1,
          "presentation_rect": [
            142.0,
            104.0,
            112.0,
            19.0
          ]
        }
      },
      {
        "box": {
          "id": "count-display",
          "maxclass": "message",
          "text": "00:00:00",
          "fontsize": 16.0,
          "fontface": 1,
          "patching_rect": [
            218.0,
            218.0,
            150.0,
            38.0
          ],
          "presentation": 1,
          "presentation_rect": [
            142.0,
            121.0,
            112.0,
            30.0
          ],
          "bgcolor": [
            0.11,
            0.12,
            0.14,
            1.0
          ],
          "textcolor": [
            1.0,
            0.72,
            0.3,
            1.0
          ],
          "bgcolor2": [
            0.13825893909668954,
            0.14395080499165816,
            0.16744603916432302,
            1
          ],
          "gradient": 1,
          "bgfillcolor_angle": 270.0,
          "bgfillcolor_autogradient": 0.0,
          "bgfillcolor_color": [
            0.13825893909668954,
            0.14395080499165816,
            0.16744603916432302,
            1
          ],
          "bgfillcolor_color1": [
            0.11,
            0.12,
            0.14,
            1.0
          ],
          "bgfillcolor_color2": [
            0.13825893909668954,
            0.14395080499165816,
            0.16744603916432302,
            1
          ],
          "bgfillcolor_proportion": 0.39,
          "bgfillcolor_type": "gradient"
        }
      },
      {
        "box": {
          "id": "arm",
          "maxclass": "textbutton",
          "mode": 1,
          "text": "DÉSARMÉ",
          "texton": "DÉSARMER",
          "fontsize": 11.0,
          "fontface": 1,
          "patching_rect": [
            408.0,
            198.0,
            134.0,
            58.0
          ],
          "presentation": 1,
          "presentation_rect": [
            501.0,
            104.0,
            97.0,
            40.0
          ],
          "bgcolor": [
            0.17,
            0.17,
            0.17,
            1.0
          ],
          "bgoncolor": [
            0.23,
            0.23,
            0.23,
            1.0
          ],
          "textcolor": [
            0.6,
            0.6,
            0.6,
            1.0
          ],
          "textoncolor": [
            0.96,
            0.96,
            0.96,
            1.0
          ]
        }
      },
      {
        "box": {
          "id": "test",
          "maxclass": "textbutton",
          "text": "TESTER",
          "fontsize": 11.0,
          "fontface": 1,
          "patching_rect": [
            558.0,
            198.0,
            158.0,
            58.0
          ],
          "presentation": 1,
          "presentation_rect": [
            610.0,
            104.0,
            92.0,
            40.0
          ],
          "bgcolor": [
            0.61,
            0.17,
            0.17,
            1.0
          ],
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
          "id": "status-label",
          "maxclass": "comment",
          "text": "ÉTAT",
          "fontsize": 9.0,
          "fontface": 1,
          "textcolor": [
            0.6,
            0.6,
            0.6,
            1.0
          ],
          "patching_rect": [
            48.0,
            286.0,
            80.0,
            20.0
          ],
          "presentation": 1,
          "presentation_rect": [
            270.0,
            104.0,
            60.0,
            19.0
          ]
        }
      },
      {
        "box": {
          "id": "status-display",
          "maxclass": "message",
          "text": "NON ARMÉ",
          "fontsize": 11.0,
          "fontface": 1,
          "patching_rect": [
            48.0,
            308.0,
            668.0,
            38.0
          ],
          "presentation": 1,
          "presentation_rect": [
            270.0,
            121.0,
            230.0,
            24.0
          ],
          "bgcolor": [
            0.11,
            0.12,
            0.14,
            1.0
          ],
          "textcolor": [
            0.33725490196078434,
            0.6666666666666666,
            0.10196078431372549,
            1.0
          ],
          "bgcolor2": [
            0.13825893909668954,
            0.14395080499165816,
            0.16744603916432302,
            1
          ],
          "gradient": 1,
          "bgfillcolor_angle": 270.0,
          "bgfillcolor_autogradient": 0.0,
          "bgfillcolor_color": [
            0.13825893909668954,
            0.14395080499165816,
            0.16744603916432302,
            1
          ],
          "bgfillcolor_color1": [
            0.11,
            0.12,
            0.14,
            1.0
          ],
          "bgfillcolor_color2": [
            0.13825893909668954,
            0.14395080499165816,
            0.16744603916432302,
            1
          ],
          "bgfillcolor_proportion": 0.39,
          "bgfillcolor_type": "gradient"
        }
      },
      {
        "box": {
          "id": "baseline",
          "maxclass": "comment",
          "text": "SYNCHRO ABLETON ACTIVE · SÉLECTIONNER UNE SCÈNE ARME LE DÉPART",
          "fontsize": 8.0,
          "textjustification": 1,
          "textcolor": [
            0.42,
            0.44,
            0.48,
            1.0
          ],
          "patching_rect": [
            48.0,
            350.0,
            668.0,
            14.0
          ],
          "presentation": 1,
          "presentation_rect": [
            14.0,
            153.0,
            494.0,
            17.0
          ]
        }
      },
      {
        "box": {
          "id": "js",
          "maxclass": "newobj",
          "text": "js ParadisLatin_AutoScene.js",
          "patching_rect": [
            300.0,
            450.0,
            560.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "qmetro",
          "maxclass": "newobj",
          "text": "qmetro 500",
          "patching_rect": [
            48.0,
            410.0,
            74.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "loadbang",
          "maxclass": "newobj",
          "text": "loadbang",
          "patching_rect": [
            48.0,
            382.0,
            62.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "one",
          "maxclass": "message",
          "text": "1",
          "patching_rect": [
            126.0,
            382.0,
            30.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "tick",
          "maxclass": "message",
          "text": "tick",
          "patching_rect": [
            48.0,
            450.0,
            35.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "refresh-msg",
          "maxclass": "message",
          "text": "refresh",
          "patching_rect": [
            510.0,
            410.0,
            52.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "hour-prepend",
          "maxclass": "newobj",
          "text": "prepend hour",
          "patching_rect": [
            48.0,
            500.0,
            88.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "minute-prepend",
          "maxclass": "newobj",
          "text": "prepend minute",
          "patching_rect": [
            144.0,
            500.0,
            98.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "second-prepend",
          "maxclass": "newobj",
          "text": "prepend second",
          "patching_rect": [
            250.0,
            500.0,
            98.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "arm-prepend",
          "maxclass": "newobj",
          "text": "prepend arm",
          "patching_rect": [
            356.0,
            500.0,
            82.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "test-msg",
          "maxclass": "message",
          "text": "test",
          "patching_rect": [
            446.0,
            500.0,
            34.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "route",
          "maxclass": "newobj",
          "text": "route clock countdown status selection target scenecount",
          "patching_rect": [
            300.0,
            540.0,
            330.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "disarm-route",
          "maxclass": "newobj",
          "text": "route disarm arm fired",
          "patching_rect": [
            650.0,
            450.0,
            132.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "zero",
          "maxclass": "message",
          "text": "set 0",
          "patching_rect": [
            650.0,
            500.0,
            38.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "set-one",
          "maxclass": "message",
          "text": "set 1",
          "patching_rect": [
            700.0,
            500.0,
            38.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "plugin",
          "maxclass": "newobj",
          "text": "plugin~",
          "patching_rect": [
            48.0,
            574.0,
            52.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "plugout",
          "maxclass": "newobj",
          "text": "plugout~",
          "patching_rect": [
            130.0,
            574.0,
            58.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "default-hour",
          "maxclass": "newobj",
          "text": "loadmess 19",
          "patching_rect": [
            202.0,
            574.0,
            78.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "default-minute",
          "maxclass": "newobj",
          "text": "loadmess 30",
          "patching_rect": [
            290.0,
            574.0,
            78.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "default-second",
          "maxclass": "newobj",
          "text": "loadmess 0",
          "patching_rect": [
            378.0,
            574.0,
            72.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "floating-message",
          "maxclass": "message",
          "text": "window flags nogrow close nozoom, window size 180 120 900 318, window exec, presentation 1, locked 1, front",
          "patching_rect": [
            470.0,
            574.0,
            520.0,
            22.0
          ]
        }
      },
      {
        "box": {
          "id": "thispatcher",
          "maxclass": "newobj",
          "text": "thispatcher",
          "patching_rect": [
            470.0,
            606.0,
            76.0,
            22.0
          ]
        }
      }
    ],
    "lines": [
      {
        "patchline": {
          "source": [
            "loadbang",
            0
          ],
          "destination": [
            "one",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "one",
            0
          ],
          "destination": [
            "qmetro",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "qmetro",
            0
          ],
          "destination": [
            "tick",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "tick",
            0
          ],
          "destination": [
            "js",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "scene-menu",
            0
          ],
          "destination": [
            "js",
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
            "refresh-msg",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "refresh-msg",
            0
          ],
          "destination": [
            "js",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "hour",
            0
          ],
          "destination": [
            "hour-prepend",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "hour-prepend",
            0
          ],
          "destination": [
            "js",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "minute",
            0
          ],
          "destination": [
            "minute-prepend",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "minute-prepend",
            0
          ],
          "destination": [
            "js",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "second",
            1
          ],
          "destination": [
            "second-prepend",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "second-prepend",
            0
          ],
          "destination": [
            "js",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "arm",
            0
          ],
          "destination": [
            "arm-prepend",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "arm-prepend",
            0
          ],
          "destination": [
            "js",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "test",
            0
          ],
          "destination": [
            "test-msg",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "test-msg",
            0
          ],
          "destination": [
            "js",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "js",
            0
          ],
          "destination": [
            "scene-menu",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "js",
            1
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
            "clock-display",
            1
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
            "count-display",
            1
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
            "status-display",
            1
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "js",
            2
          ],
          "destination": [
            "disarm-route",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "disarm-route",
            0
          ],
          "destination": [
            "zero",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "zero",
            0
          ],
          "destination": [
            "arm",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "disarm-route",
            1
          ],
          "destination": [
            "set-one",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "set-one",
            0
          ],
          "destination": [
            "arm",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "plugin",
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
            "plugin",
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
            "default-hour",
            0
          ],
          "destination": [
            "hour",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "default-minute",
            0
          ],
          "destination": [
            "minute",
            0
          ]
        }
      },
      {
        "patchline": {
          "source": [
            "default-second",
            0
          ],
          "destination": [
            "second",
            0
          ]
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
            "floating-message",
            0
          ],
          "destination": [
            "thispatcher",
            0
          ]
        }
      }
    ],
    "dependency_cache": [
      {
        "name": "ParadisLatin_AutoScene.js",
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
    ],
    "autosave": 0,
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
        "patchers": {
        }
      },
      "layout": {
      },
      "searchpath": {
      },
      "detailsvisible": 0,
      "amxdtype": 1633771873,
      "readonly": 0,
      "devpathtype": 0,
      "devpath": ".",
      "sortmode": 0,
      "viewmode": 0,
      "includepackages": 0
    },
    "platform_compatibility": 0,
    "latency": 0,
    "is_mpe": 0,
    "external_mpe_tuning_enabled": 0,
    "minimum_live_version": "10.0.0",
    "minimum_max_version": "8.0.0",
    "bgcolor": [
      0.063,
      0.071,
      0.082,
      1.0
    ]
  }
}
