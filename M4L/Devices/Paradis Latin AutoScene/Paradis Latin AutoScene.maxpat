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
        "rect": [ 134.0, 167.0, 920.0, 620.0 ],
        "openrect": [ 0.0, 0.0, 720.0, 169.0 ],
        "devicewidth": 720.0,
        "bglocked": 1,
        "openinpresentation": 1,
        "default_fontname": "Avenir Next",
        "gridsize": [ 10.0, 10.0 ],
        "boxes": [
            {
                "box": {
                    "angle": 270.0,
                    "background": 1,
                    "bgcolor": [ 0.063, 0.071, 0.082, 1.0 ],
                    "id": "bg",
                    "maxclass": "panel",
                    "mode": 0,
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 20.0, 20.0, 720.0, 360.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 0.0, 0.0, 720.0, 169.0 ],
                    "proportion": 0.39,
                    "saved_attribute_attributes": {
                        "bgfillcolor": {
                            "expression": ""
                        }
                    }
                }
            },
            {
                "box": {
                    "angle": 270.0,
                    "background": 1,
                    "bgcolor": [ 0.09, 0.09, 0.09, 1.0 ],
                    "id": "header",
                    "maxclass": "panel",
                    "mode": 0,
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 20.0, 20.0, 720.0, 72.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 0.0, 0.0, 720.0, 50.0 ],
                    "proportion": 0.39,
                    "saved_attribute_attributes": {
                        "bgfillcolor": {
                            "expression": ""
                        }
                    }
                }
            },
            {
                "box": {
                    "autofit": 1,
                    "forceaspect": 1,
                    "id": "logo",
                    "ignoreclick": 1,
                    "maxclass": "fpic",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "jit_matrix" ],
                    "patching_rect": [ 44.0, 28.0, 330.0, 60.0 ],
                    "pic": "paradis_latin_logo.jpg",
                    "presentation": 1,
                    "presentation_rect": [ 18.0, -3.9, 190.0, 57.8 ]
                }
            },
            {
                "box": {
                    "fontface": 1,
                    "fontsize": 10.0,
                    "id": "subtitle",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 420.0, 48.0, 226.0, 20.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 238.93807232379913, 7.079646587371826, 185.0, 20.0 ],
                    "text": "DÉPART AUTOMATIQUE DE SCÈNE",
                    "textcolor": [ 0.8901960784313725, 0.3764705882352941, 0.3764705882352941, 1.0 ],
                    "textjustification": 1
                }
            },
            {
                "box": {
                    "fontface": 1,
                    "fontsize": 10.0,
                    "id": "time-label",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 48.0, 112.0, 150.0, 20.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 543.5, 7.079646587371826, 166.0, 20.0 ],
                    "text": "HEURE DE DÉPART",
                    "textcolor": [ 0.8156862745098039, 0.6901960784313725, 0.08235294117647059, 1.0 ]
                }
            },
            {
                "box": {
                    "bgcolor": [ 0.11, 0.12, 0.14, 1.0 ],
                    "bgfillcolor_angle": 270.0,
                    "bgfillcolor_color": [ 0.11, 0.12, 0.14, 1.0 ],
                    "bgfillcolor_color1": [ 0.13825893909668954, 0.14395080499165816, 0.16744603916432302, 1 ],
                    "bgfillcolor_color2": [ 0.13825893909668954, 0.14395080499165816, 0.16744603916432302, 1 ],
                    "bgfillcolor_proportion": 0.39,
                    "bgfillcolor_type": "color",
                    "fontface": 1,
                    "fontname": "Arial Rounded MT Bold",
                    "fontsize": 18.0,
                    "id": "hour",
                    "items": [ "00", ",", "01", ",", "02", ",", "03", ",", "04", ",", "05", ",", "06", ",", "07", ",", "08", ",", "09", ",", "10", ",", "11", ",", "12", ",", "13", ",", "14", ",", "15", ",", "16", ",", "17", ",", "18", ",", "19", ",", "20", ",", "21", ",", "22", ",", "23" ],
                    "maxclass": "umenu",
                    "numinlets": 1,
                    "numoutlets": 3,
                    "outlettype": [ "int", "", "" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 48.0, 136.0, 52.0, 29.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 539.0, 29.400000000000006, 54.0, 29.0 ],
                    "textcolor": [ 0.7019607843137254, 0.25882352941176473, 0.07058823529411765, 1.0 ],
                    "varname": "heure_depart"
                }
            },
            {
                "box": {
                    "fontface": 1,
                    "fontname": "Arial Rounded MT Bold",
                    "fontsize": 18.0,
                    "id": "colon1",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 104.0, 136.0, 23.0, 27.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 587.0, 29.400000000000006, 23.0, 27.0 ],
                    "text": ":",
                    "textcolor": [ 0.6, 0.6, 0.6, 1.0 ]
                }
            },
            {
                "box": {
                    "bgcolor": [ 0.11, 0.12, 0.14, 1.0 ],
                    "fontface": 1,
                    "fontname": "Arial Rounded MT Bold",
                    "fontsize": 18.0,
                    "id": "minute",
                    "maxclass": "number",
                    "maximum": 59,
                    "minimum": 0,
                    "numinlets": 1,
                    "numoutlets": 2,
                    "outlettype": [ "", "bang" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 120.0, 136.0, 52.0, 29.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 595.0, 29.400000000000006, 55.0, 29.0 ],
                    "textcolor": [ 0.7019607843137254, 0.25882352941176473, 0.07058823529411765, 1.0 ],
                    "varname": "minute_depart"
                }
            },
            {
                "box": {
                    "fontface": 1,
                    "fontname": "Arial Rounded MT Bold",
                    "fontsize": 18.0,
                    "id": "colon2",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 176.0, 136.0, 23.0, 27.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 649.0, 29.400000000000006, 23.0, 27.0 ],
                    "text": ":",
                    "textcolor": [ 0.6, 0.6, 0.6, 1.0 ]
                }
            },
            {
                "box": {
                    "bgcolor": [ 0.11, 0.12, 0.14, 1.0 ],
                    "bgfillcolor_angle": 270.0,
                    "bgfillcolor_color": [ 0.11, 0.12, 0.14, 1.0 ],
                    "bgfillcolor_color1": [ 0.13825893909668954, 0.14395080499165816, 0.16744603916432302, 1 ],
                    "bgfillcolor_color2": [ 0.13825893909668954, 0.14395080499165816, 0.16744603916432302, 1 ],
                    "bgfillcolor_proportion": 0.39,
                    "bgfillcolor_type": "color",
                    "fontface": 1,
                    "fontname": "Arial Rounded MT Bold",
                    "fontsize": 18.0,
                    "id": "second",
                    "items": [ "00", ",", "15", ",", "30", ",", "45" ],
                    "maxclass": "umenu",
                    "numinlets": 1,
                    "numoutlets": 3,
                    "outlettype": [ "int", "", "" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 192.0, 136.0, 52.0, 29.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 654.0, 29.400000000000006, 62.0, 29.0 ],
                    "textcolor": [ 0.7019607843137254, 0.25882352941176473, 0.07058823529411765, 1.0 ],
                    "varname": "seconde_depart"
                }
            },
            {
                "box": {
                    "fontface": 1,
                    "fontsize": 10.0,
                    "id": "scene-label",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 288.0, 112.0, 251.0, 20.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 215.9292209148407, 33.900000000000006, 255.0, 20.0 ],
                    "text": "ENTREE PUBLIC · LA SÉLECTION ARME LE DÉPART",
                    "textcolor": [ 0.10980392156862745, 0.611764705882353, 0.2784313725490196, 1.0 ]
                }
            },
            {
                "box": {
                    "applycolors": 1,
                    "bgcolor": [ 0.055, 0.067, 0.086, 1.0 ],
                    "bgfillcolor_angle": 270.0,
                    "bgfillcolor_autogradient": 0.0,
                    "bgfillcolor_color": [ 0.055, 0.067, 0.086, 1.0 ],
                    "bgfillcolor_color1": [ 0.055, 0.067, 0.086, 1.0 ],
                    "bgfillcolor_color2": [ 0.055, 0.067, 0.086, 1.0 ],
                    "bgfillcolor_proportion": 0.39,
                    "bgfillcolor_type": "color",
                    "fontface": 1,
                    "fontsize": 12.0,
                    "id": "scene-menu",
                    "items": "<empty>",
                    "maxclass": "umenu",
                    "numinlets": 1,
                    "numoutlets": 3,
                    "outlettype": [ "int", "", "" ],
                    "parameter_enable": 1,
                    "patching_rect": [ 288.0, 136.0, 306.0, 25.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 17.699116468429565, 69.0265542268753, 470.0, 25.0 ],
                    "saved_attribute_attributes": {
                        "valueof": {
                            "parameter_enum": [ "0", "1" ],
                            "parameter_longname": "scene_selectionnee",
                            "parameter_mmax": 1,
                            "parameter_modmode": 0,
                            "parameter_shortname": "scene_selectionnee",
                            "parameter_type": 2
                        }
                    },
                    "elementcolor": [ 0.25, 0.55, 0.9, 1.0 ],
                    "hilitecolor": [ 0.0392156862745098, 0.40784313725490196, 0.8156862745098039, 1.0 ],
                    "textcolor": [ 0.96, 0.96, 0.96, 1.0 ],
                    "textcolor_inverse": [ 1.0, 1.0, 1.0, 1.0 ],
                    "varname": "scene_selectionnee"
                }
            },
            {
                "box": {
                    "bgcolor": [ 0.0392156862745098, 0.40784313725490196, 0.8156862745098039, 1.0 ],
                    "fontface": 1,
                    "id": "refresh",
                    "maxclass": "textbutton",
                    "numinlets": 1,
                    "numoutlets": 3,
                    "outlettype": [ "", "", "int" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 604.0, 136.0, 112.0, 28.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 500.0, 68.0265542268753, 98.0, 27.0 ],
                    "saved_attribute_attributes": {
                        "bgcolor": {
                            "expression": ""
                        },
                        "textcolor": {
                            "expression": ""
                        }
                    },
                    "text": "↻  ACTUALISER",
                    "textcolor": [ 0.96, 0.96, 0.96, 1.0 ]
                }
            },
            {
                "box": {
                    "bgcolor": [ 0.45098039215686275, 0.21176470588235294, 0.4823529411764706, 1.0 ],
                    "fontface": 1,
                    "id": "floating-button",
                    "maxclass": "textbutton",
                    "numinlets": 1,
                    "numoutlets": 3,
                    "outlettype": [ "", "", "int" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 620.0, 410.0, 96.0, 24.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 606.0, 68.0265542268753, 100.0, 27.0 ],
                    "saved_attribute_attributes": {
                        "bgcolor": {
                            "expression": ""
                        },
                        "textcolor": {
                            "expression": ""
                        }
                    },
                    "text": "FENÊTRE",
                    "textcolor": [ 0.96, 0.96, 0.96, 1.0 ]
                }
            },
            {
                "box": {
                    "fontface": 1,
                    "fontsize": 9.0,
                    "id": "clock-label",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 48.0, 196.0, 150.0, 19.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 18.0, 104.0, 112.0, 19.0 ],
                    "text": "HEURE ACTUELLE",
                    "textcolor": [ 0.6, 0.6, 0.6, 1.0 ]
                }
            },
            {
                "box": {
                    "bgcolor": [ 0.11, 0.12, 0.14, 1.0 ],
                    "bgcolor2": [ 0.13825893909668954, 0.14395080499165816, 0.16744603916432302, 1 ],
                    "bgfillcolor_angle": 270.0,
                    "bgfillcolor_autogradient": 0.0,
                    "bgfillcolor_color": [ 0.13825893909668954, 0.14395080499165816, 0.16744603916432302, 1 ],
                    "bgfillcolor_color1": [ 0.11, 0.12, 0.14, 1.0 ],
                    "bgfillcolor_color2": [ 0.13825893909668954, 0.14395080499165816, 0.16744603916432302, 1 ],
                    "bgfillcolor_proportion": 0.39,
                    "bgfillcolor_type": "gradient",
                    "fontface": 1,
                    "fontsize": 16.0,
                    "gradient": 1,
                    "id": "clock-display",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 48.0, 218.0, 150.0, 30.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 18.0, 121.0, 112.0, 30.0 ],
                    "text": "15:55:59",
                    "textcolor": [ 0.9254901960784314, 0.396078431372549, 0.396078431372549, 1.0 ]
                }
            },
            {
                "box": {
                    "fontface": 1,
                    "fontsize": 9.0,
                    "id": "count-label",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 218.0, 196.0, 150.0, 19.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 142.0, 104.0, 112.0, 19.0 ],
                    "text": "TEMPS RESTANT",
                    "textcolor": [ 0.6, 0.6, 0.6, 1.0 ]
                }
            },
            {
                "box": {
                    "bgcolor": [ 0.11, 0.12, 0.14, 1.0 ],
                    "bgcolor2": [ 0.13825893909668954, 0.14395080499165816, 0.16744603916432302, 1 ],
                    "bgfillcolor_angle": 270.0,
                    "bgfillcolor_autogradient": 0.0,
                    "bgfillcolor_color": [ 0.13825893909668954, 0.14395080499165816, 0.16744603916432302, 1 ],
                    "bgfillcolor_color1": [ 0.11, 0.12, 0.14, 1.0 ],
                    "bgfillcolor_color2": [ 0.13825893909668954, 0.14395080499165816, 0.16744603916432302, 1 ],
                    "bgfillcolor_proportion": 0.39,
                    "bgfillcolor_type": "gradient",
                    "fontface": 1,
                    "fontsize": 16.0,
                    "gradient": 1,
                    "id": "count-display",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 218.0, 218.0, 150.0, 30.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 142.0, 121.0, 112.0, 30.0 ],
                    "text": "03:34:01",
                    "textcolor": [ 1.0, 0.72, 0.3, 1.0 ]
                }
            },
            {
                "box": {
                    "bgcolor": [ 0.17, 0.17, 0.17, 1.0 ],
                    "bgoncolor": [ 0.23, 0.23, 0.23, 1.0 ],
                    "fontface": 1,
                    "fontsize": 11.0,
                    "id": "arm",
                    "maxclass": "textbutton",
                    "mode": 1,
                    "numinlets": 1,
                    "numoutlets": 3,
                    "outlettype": [ "", "", "int" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 408.0, 198.0, 134.0, 58.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 501.0, 104.0, 97.0, 40.0 ],
                    "saved_attribute_attributes": {
                        "bgcolor": {
                            "expression": ""
                        },
                        "bgoncolor": {
                            "expression": ""
                        },
                        "textcolor": {
                            "expression": ""
                        },
                        "textoncolor": {
                            "expression": ""
                        }
                    },
                    "text": "DÉSARMÉ",
                    "textcolor": [ 0.6, 0.6, 0.6, 1.0 ],
                    "texton": "DÉSARMER",
                    "textoncolor": [ 0.96, 0.96, 0.96, 1.0 ]
                }
            },
            {
                "box": {
                    "bgcolor": [ 0.61, 0.17, 0.17, 1.0 ],
                    "fontface": 1,
                    "fontsize": 11.0,
                    "id": "test",
                    "maxclass": "textbutton",
                    "numinlets": 1,
                    "numoutlets": 3,
                    "outlettype": [ "", "", "int" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 558.0, 198.0, 158.0, 58.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 610.0, 104.0, 92.0, 40.0 ],
                    "saved_attribute_attributes": {
                        "bgcolor": {
                            "expression": ""
                        },
                        "textcolor": {
                            "expression": ""
                        }
                    },
                    "text": "TESTER",
                    "textcolor": [ 1.0, 1.0, 1.0, 1.0 ]
                }
            },
            {
                "box": {
                    "fontface": 1,
                    "fontsize": 9.0,
                    "id": "status-label",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 48.0, 286.0, 80.0, 19.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 270.0, 104.0, 60.0, 19.0 ],
                    "text": "ÉTAT",
                    "textcolor": [ 0.6, 0.6, 0.6, 1.0 ]
                }
            },
            {
                "box": {
                    "bgcolor": [ 0.11, 0.12, 0.14, 1.0 ],
                    "bgcolor2": [ 0.13825893909668954, 0.14395080499165816, 0.16744603916432302, 1 ],
                    "bgfillcolor_angle": 270.0,
                    "bgfillcolor_autogradient": 0.0,
                    "bgfillcolor_color": [ 0.13825893909668954, 0.14395080499165816, 0.16744603916432302, 1 ],
                    "bgfillcolor_color1": [ 0.11, 0.12, 0.14, 1.0 ],
                    "bgfillcolor_color2": [ 0.13825893909668954, 0.14395080499165816, 0.16744603916432302, 1 ],
                    "bgfillcolor_proportion": 0.39,
                    "bgfillcolor_type": "gradient",
                    "fontface": 1,
                    "fontsize": 11.0,
                    "gradient": 1,
                    "id": "status-display",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 48.0, 308.0, 668.0, 24.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 270.0, 121.0, 230.0, 24.0 ],
                    "text": "\"NON ARME\"",
                    "textcolor": [ 0.33725490196078434, 0.6666666666666666, 0.10196078431372549, 1.0 ]
                }
            },
            {
                "box": {
                    "fontsize": 8.0,
                    "id": "baseline",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 48.0, 350.0, 668.0, 17.0 ],
                    "presentation": 1,
                    "presentation_rect": [ 14.0, 153.0, 494.0, 17.0 ],
                    "text": "SYNCHRO ABLETON ACTIVE · SÉLECTIONNER UNE SCÈNE ARME LE DÉPART",
                    "textcolor": [ 0.42, 0.44, 0.48, 1.0 ],
                    "textjustification": 1
                }
            },
            {
                "box": {
                    "id": "js",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 3,
                    "outlettype": [ "", "", "" ],
                    "patching_rect": [ 300.0, 450.0, 560.0, 25.0 ],
                    "saved_object_attributes": {
                        "filename": "ParadisLatin_AutoScene.js",
                        "parameter_enable": 0
                    },
                    "text": "js ParadisLatin_AutoScene.js"
                }
            },
            {
                "box": {
                    "id": "qmetro",
                    "maxclass": "newobj",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "bang" ],
                    "patching_rect": [ 48.0, 410.0, 74.0, 25.0 ],
                    "text": "qmetro 500"
                }
            },
            {
                "box": {
                    "id": "loadbang",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "bang" ],
                    "patching_rect": [ 48.0, 382.0, 62.0, 25.0 ],
                    "text": "loadbang"
                }
            },
            {
                "box": {
                    "id": "one",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 126.0, 382.0, 30.0, 25.0 ],
                    "text": "1"
                }
            },
            {
                "box": {
                    "id": "tick",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 48.0, 450.0, 35.0, 25.0 ],
                    "text": "tick"
                }
            },
            {
                "box": {
                    "id": "refresh-msg",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 510.0, 410.0, 52.0, 25.0 ],
                    "text": "refresh"
                }
            },
            {
                "box": {
                    "id": "hour-prepend",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 48.0, 500.0, 88.0, 25.0 ],
                    "text": "prepend hour"
                }
            },
            {
                "box": {
                    "id": "minute-prepend",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 144.0, 500.0, 98.0, 25.0 ],
                    "text": "prepend minute"
                }
            },
            {
                "box": {
                    "id": "second-prepend",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 250.0, 500.0, 99.0, 25.0 ],
                    "text": "prepend second"
                }
            },
            {
                "box": {
                    "id": "arm-prepend",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 356.0, 500.0, 82.0, 25.0 ],
                    "text": "prepend arm"
                }
            },
            {
                "box": {
                    "id": "test-msg",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 446.0, 500.0, 34.0, 25.0 ],
                    "text": "test"
                }
            },
            {
                "box": {
                    "id": "route",
                    "maxclass": "newobj",
                    "numinlets": 7,
                    "numoutlets": 7,
                    "outlettype": [ "", "", "", "", "", "", "" ],
                    "patching_rect": [ 300.0, 540.0, 330.0, 25.0 ],
                    "text": "route clock countdown status selection target scenecount"
                }
            },
            {
                "box": {
                    "id": "disarm-route",
                    "maxclass": "newobj",
                    "numinlets": 4,
                    "numoutlets": 4,
                    "outlettype": [ "", "", "", "" ],
                    "patching_rect": [ 650.0, 450.0, 132.0, 25.0 ],
                    "text": "route disarm arm fired"
                }
            },
            {
                "box": {
                    "id": "zero",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 650.0, 500.0, 38.0, 25.0 ],
                    "text": "set 0"
                }
            },
            {
                "box": {
                    "id": "set-one",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 700.0, 500.0, 38.0, 25.0 ],
                    "text": "set 1"
                }
            },
            {
                "box": {
                    "id": "plugin",
                    "maxclass": "newobj",
                    "numinlets": 2,
                    "numoutlets": 2,
                    "outlettype": [ "signal", "signal" ],
                    "patching_rect": [ 48.0, 574.0, 52.0, 25.0 ],
                    "text": "plugin~"
                }
            },
            {
                "box": {
                    "id": "plugout",
                    "maxclass": "newobj",
                    "numinlets": 2,
                    "numoutlets": 2,
                    "outlettype": [ "signal", "signal" ],
                    "patching_rect": [ 130.0, 574.0, 60.0, 25.0 ],
                    "text": "plugout~"
                }
            },
            {
                "box": {
                    "id": "default-hour",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 202.0, 574.0, 78.0, 25.0 ],
                    "text": "loadmess 19"
                }
            },
            {
                "box": {
                    "id": "default-minute",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 290.0, 574.0, 78.0, 25.0 ],
                    "text": "loadmess 30"
                }
            },
            {
                "box": {
                    "id": "default-second",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 378.0, 574.0, 72.0, 25.0 ],
                    "text": "loadmess 0"
                }
            },
            {
                "box": {
                    "id": "floating-message",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 470.0, 574.0, 618.0, 25.0 ],
                    "text": "window flags nogrow close nozoom, window size 180 120 900 318, window exec, presentation 1, locked 1, front"
                }
            },
            {
                "box": {
                    "id": "thispatcher",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 2,
                    "outlettype": [ "", "" ],
                    "patching_rect": [ 470.0, 606.0, 76.0, 25.0 ],
                    "save": [ "#N", "thispatcher", ";", "#Q", "end", ";" ],
                    "text": "thispatcher"
                }
            }
        ],
        "lines": [
            {
                "patchline": {
                    "destination": [ "arm-prepend", 0 ],
                    "source": [ "arm", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "js", 0 ],
                    "source": [ "arm-prepend", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "hour", 0 ],
                    "source": [ "default-hour", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "minute", 0 ],
                    "source": [ "default-minute", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "second", 0 ],
                    "source": [ "default-second", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "set-one", 0 ],
                    "source": [ "disarm-route", 1 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "zero", 0 ],
                    "source": [ "disarm-route", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "floating-message", 0 ],
                    "source": [ "floating-button", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "thispatcher", 0 ],
                    "source": [ "floating-message", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "hour-prepend", 0 ],
                    "source": [ "hour", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "js", 0 ],
                    "source": [ "hour-prepend", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "disarm-route", 0 ],
                    "source": [ "js", 2 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "route", 0 ],
                    "source": [ "js", 1 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "scene-menu", 0 ],
                    "source": [ "js", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "one", 0 ],
                    "source": [ "loadbang", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "minute-prepend", 0 ],
                    "source": [ "minute", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "js", 0 ],
                    "source": [ "minute-prepend", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "qmetro", 0 ],
                    "source": [ "one", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "plugout", 1 ],
                    "source": [ "plugin", 1 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "plugout", 0 ],
                    "source": [ "plugin", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "tick", 0 ],
                    "source": [ "qmetro", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "refresh-msg", 0 ],
                    "source": [ "refresh", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "js", 0 ],
                    "source": [ "refresh-msg", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "clock-display", 1 ],
                    "source": [ "route", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "count-display", 1 ],
                    "source": [ "route", 1 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "status-display", 1 ],
                    "source": [ "route", 2 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "js", 0 ],
                    "source": [ "scene-menu", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "second-prepend", 0 ],
                    "source": [ "second", 1 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "js", 0 ],
                    "source": [ "second-prepend", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "arm", 0 ],
                    "source": [ "set-one", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "test-msg", 0 ],
                    "source": [ "test", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "js", 0 ],
                    "source": [ "test-msg", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "js", 0 ],
                    "source": [ "tick", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "arm", 0 ],
                    "source": [ "zero", 0 ]
                }
            }
        ],
        "parameters": {
            "scene-menu": [ "scene_selectionnee", "scene_selectionnee", 0 ],
            "parameterbanks": {
                "0": {
                    "index": 0,
                    "name": "",
                    "parameters": [ "-", "-", "-", "-", "-", "-", "-", "-" ],
                    "buttons": [ "-", "-", "-", "-", "-", "-", "-", "-" ]
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
            "creationdate": 3590052493,
            "modificationdate": 3590052493,
            "viewrect": [ 0.0, 0.0, 300.0, 500.0 ],
            "autoorganize": 1,
            "hideprojectwindow": 1,
            "showdependencies": 1,
            "autolocalize": 0,
            "contents": {
                "patchers": {                }
            },
            "layout": {            },
            "searchpath": {            },
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
        "oscreceiveudpport": 0
    }
}
