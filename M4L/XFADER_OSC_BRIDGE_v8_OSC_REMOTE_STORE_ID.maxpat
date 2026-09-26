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
      569.0,
      220.0,
      837.0,
      542.0
    ],
    "openrect": [
      0.0,
      0.0,
      0.0,
      169.0
    ],
    "openrectmode": 0,
    "openinpresentation": 1,
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
          "id": "title",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            40.0,
            25.0,
            1200.0,
            18.0
          ],
          "text": "XFADER OSC BRIDGE v8 — TRUE OSC. Put this Max Audio Effect on MASTER. UDP 9001: /xfader/a /xfader/center /xfader/b"
        }
      },
      {
        "box": {
          "id": "note",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            40.0,
            55.0,
            1200.0,
            18.0
          ],
          "text": "Manual test: lock patcher, click -1 / 0 / 1. The crossfader is attached once when the device loads."
        }
      },
      {
        "box": {
          "id": "plug",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 2,
          "outlettype": [
            "signal",
            "signal"
          ],
          "patching_rect": [
            40.0,
            110.0,
            70.0,
            20.0
          ],
          "text": "plugin~"
        }
      },
      {
        "box": {
          "id": "plugout",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 2,
          "outlettype": [
            "signal",
            "signal"
          ],
          "patching_rect": [
            40.0,
            175.0,
            75.0,
            20.0
          ],
          "text": "plugout~"
        }
      },
      {
        "box": {
          "id": "lb",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "outlettype": [
            "bang"
          ],
          "patching_rect": [
            520.0,
            100.0,
            80.0,
            20.0
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
          "outlettype": [
            ""
          ],
          "patching_rect": [
            520.0,
            135.0,
            80.0,
            20.0
          ],
          "text": "deferlow"
        }
      },
      {
        "box": {
          "id": "delay",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            "bang"
          ],
          "patching_rect": [
            520.0,
            170.0,
            85.0,
            20.0
          ],
          "text": "delay 1500"
        }
      },
      {
        "box": {
          "id": "bang",
          "maxclass": "button",
          "numinlets": 1,
          "numoutlets": 1,
          "outlettype": [
            "bang"
          ],
          "parameter_enable": 0,
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
          "numinlets": 1,
          "numoutlets": 3,
          "outlettype": [
            "",
            "",
            ""
          ],
          "patching_rect": [
            520.0,
            210.0,
            360.0,
            20.0
          ],
          "text": "live.path live_set master_track mixer_device crossfader"
        }
      },
      {
        "box": {
          "id": "printid",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            900.0,
            210.0,
            130.0,
            20.0
          ],
          "text": "print XFADER_ID"
        }
      },
      {
        "box": {
          "id": "udp",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            40.0,
            300.0,
            120.0,
            20.0
          ],
          "text": "udpreceive 9001"
        }
      },
      {
        "box": {
          "id": "printudp",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            180.0,
            265.0,
            130.0,
            20.0
          ],
          "text": "print UDP_IN"
        }
      },
      {
        "box": {
          "id": "route",
          "maxclass": "newobj",
          "numinlets": 5,
          "numoutlets": 5,
          "outlettype": [
            "",
            "",
            "",
            "",
            ""
          ],
          "patching_rect": [
            180.0,
            300.0,
            380.0,
            20.0
          ],
          "text": "route /xfader/a /xfader/center /xfader/b /xfader/value"
        }
      },
      {
        "box": {
          "id": "ua",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            180.0,
            345.0,
            45.0,
            20.0
          ],
          "text": "-1."
        }
      },
      {
        "box": {
          "id": "uc",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            250.0,
            345.0,
            45.0,
            20.0
          ],
          "text": "0."
        }
      },
      {
        "box": {
          "id": "ub",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            320.0,
            345.0,
            45.0,
            20.0
          ],
          "text": "1."
        }
      },
      {
        "box": {
          "id": "manual",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            40.0,
            410.0,
            180.0,
            18.0
          ],
          "text": "Manual test buttons"
        }
      },
      {
        "box": {
          "id": "ma",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            40.0,
            440.0,
            55.0,
            20.0
          ],
          "text": "-1."
        }
      },
      {
        "box": {
          "id": "mc",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            110.0,
            440.0,
            55.0,
            20.0
          ],
          "text": "0."
        }
      },
      {
        "box": {
          "id": "mb",
          "maxclass": "message",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            180.0,
            440.0,
            55.0,
            20.0
          ],
          "text": "1."
        }
      },
      {
        "box": {
          "id": "clip",
          "maxclass": "newobj",
          "numinlets": 3,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            520.0,
            340.0,
            80.0,
            20.0
          ],
          "text": "clip -1. 1."
        }
      },
      {
        "box": {
          "id": "sig",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "outlettype": [
            "signal"
          ],
          "patching_rect": [
            660.0,
            500.0,
            70.0,
            20.0
          ],
          "text": "sig~ 0."
        }
      },
      {
        "box": {
          "id": "remote",
          "maxclass": "newobj",
          "numinlets": 2,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            660.0,
            545.0,
            100.0,
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
          "id": "pval",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            780.0,
            500.0,
            135.0,
            20.0
          ],
          "text": "print XFADER_SENT"
        }
      },
      {
        "box": {
          "id": "pulse",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            780.0,
            545.0,
            620.0,
            18.0
          ],
          "text": "TEST LIVEOBJECT: ecriture directe de la propriete value du crossfader."
        }
      },
      {
        "box": {
          "id": "value_note",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            580.0,
            300.0,
            620.0,
            18.0
          ],
          "text": "Slider continu: /xfader/value -> clip -1..1 -> set value -> live.object."
        }
      },
      {
        "box": {
          "id": "set_value",
          "maxclass": "newobj",
          "numinlets": 1,
          "numoutlets": 1,
          "outlettype": [
            ""
          ],
          "patching_rect": [
            640.0,
            500.0,
            120.0,
            20.0
          ],
          "text": "prepend set value"
        }
      },
      {
        "box": {
          "data": [
            28288,
            "png",
            "IBkSG0fBZn....PCIgDQRA..Ab.....THX.....EWAKW....DLmPIQEBHf.B7g.YHB..f.PRDEDU3wI68dGmjUTt++uq5D5tmdx4cmMGgU.IiWvEDPDTPEECHHnffdAIbuvEPQTQLyEATTL.F.w.nffAPxYEPhKKrKaNOoclomd5zITU86OpS2Suq68589E7082eLOudMae59jp5odpOOwpVAfgononononchj+ecCXJZJZJ5++IME3vTzTzTztjlBbXJZJZJZWRSANLEMEMEsKoo.Glhlhlh1kzTfCSQSQSQ6RZJvgonononcIME3vTzTzTztjlBbXJZJZJZWRSANLEMEMEsKoo.Glhlhlh1kzTfCSQSQSQ6RZJvgonononcIME3vTzTzTztjlBbXJZJZJZWRtuteBRvQC9IeshDLN.N.HfXCn.mjcMBkH41LBj.wdBvnAM1cVBIIGmxdfLBRtGzt08bhAAHz1uWaSoPjf2U8D0eRiL4Q4fAIfjFHfPfXujqI11VcR9ZzN0cqeyuP.Xbq6GU1eywd3Nc85Z7KL1+rWWV.vM4NhQAXvs5Q9IuIkDox9bzUuYQcMbGkkOV8kJreJL055SdNiDAxDVsH4mUI8IMFQR6Tjzf0fq1d8Q0NuN48a4oxj9mh5u2I610SU4uRfJUuNgGHT1avXG9bp6dhqccxZ8A.RgfX.kLg4qRdgNIMDE3lnCz.nHocazIrnpse6s3lzjqj75bS5Hw0Dqj3lbcVInHh.pTa7vEIowK4oGREL0XBVFiCFbH11+qJOHru3pskpySpwKqJHU835+6eRzqavAg.jBPXjnwfwXlbhtv.F64scJYMoUiwX6W5DtflcfIXEd0npuyW6X8e+OQcmyTmAQhc7blZyNseuZSs1.z+ETULq+Nxj79LZHoMW8Sc82U0mccMX6YBS9YCFD1IcIC5BAXTX4YZQB1owxlRdNNBCFAnM0gHTGnPsW4Nz+z00ab2glmDPa1IPMyj8CIfxn+6DLqNzUeaaGZ.0wa00+0c0MYHomZAqp+2l7XMBjXpuQj.NJpcncrXG.pEUu2pSB0XR5yBrfap5XH0j+L.BIFTDSs4x1qo54qI6pPgDCwXHdmF6sRF6P+O4ypsIn1TmIet0CJjz0pGy3eFzqavAiRhFIwIeWZTXPfwjfvqiqw3qwNMVQ7ZieFI9IZLBSXfdXuGgwJ2nq692gIo0OWu1jBM0OWoFkHXTmYF0gpuiW1NLYYmOYx6xPhxNqtbD0FzqdG5IaB6L3fr5fu01DsAqF4jqUUEfPmHxXDIsKGbPi1XvXfTlXTFrZOStWAR7SDyB1g2cbsmurlv3j8NA5ZV8DWmPX09J.NI8o35v7jIcnpGqM63b8c0b+3jmiC0AFkLlILjXWyjSAs.ARDI8gIO6NY5X09Vxyr5j+c.XLwpDG.UhoBFskmqfIsbhDPlpxRRscnPCgIOCkvO4BhRZ2Zlz9O0jV3UUXOA.KtFiQtC7QQMtottlqtlrgv.N0EMf3csJq2Pn+eFbPHRZsFmZMOABDBK2ynqpowoVGUHDnDxZCTFiI4JT6XvOjFTZcMyJmToiLQXXm8kXmNt58Tu.Y8VETmKG0zvtSBuU01TU1Pye2q.AfWx4pW6T8ZU96njIklZVSM4Cq1uShQVZvwXQILIvXpjoTRiFGDnQsisKi0XWAU+TkvmodFI5jIQp5zhVkj6D+PTmUPUcGvoFOQihpt.H2g+sJOXGZe00mseT8IqqAPX42VaGM0bIXGCOVUfsp78ZtOIrsqpiKSdwhDMuNHDZDFqpg50DTCDo5e67fnYGOuxT84ZlzZujaT.fyj8oIoj9jnp5TMSx8qSoYxu4fFGj0.Apx+0IVV8eij1qa50skCxpcLIfPfPJPJj3XL3nALFbzNVwaiUkhBPKjfzFfBsQ.DZ6rNXAGLJTlI86zHbADX8W1N3h.7LSN4bRKvjIL0IoXSheb0qAwLofdMyGEritxTukr0AjTUgPMkxIeQqq660eO0ceT+6Ko+TyM8pBdxDMfgVQFMFDHQgSh0CI9rmpXR2Q.FWjJARi0YEIZbPUaBb02WUgPa7AhrfgIZB2QflI+Aiv5hW0tktZeL4lTF.sUPtdqtTU+lXGdxUY0SBFJRLcJQapwXcGPrCihSd8U4eUmZU8phqZw.UgcRr5JVjfKk3VFZaaSa.s.AFpcEFAFsAgQj.NmXYQ0N0NzIlzzJ66UUCVF0jJVrrSIVXKWrAlCr11Yc2sd2Ypw+IAls1wI8S14K9Md5+m.GpZ0fPHvHTHLZDZKZoNoGJEFqoaFYh3hU6iKZhQRrzfQJINg4qzIpTpNiSNYPJq4IYMKNRLKzLoF8Zn9lIQg2knp06tgotq3uy8ic56+8x163kVSHemNQ89JtyOCCfvEiQiFMtnwQkDQ.oUt0BBXmJqwfVHPXpFNUnl+bXrHSlpZlLnEZjZ8+McG4jtkImDXqd9gn50k3jaUiPpY4S0KJ4XsVicDu5z15PTpSHup9QcsmQcny3X0piETxdvN9rLlIUHT0Rg56fZyjn5hDHFaLFLXDVvVqanxjluU9RV2.o0DdQM1gTLoEN0d7xD83BGDF8jwRqJCxnqMgdRqOmzsycf2rS7RK3hdGjh2AGqqFb1+IQ+CAGDBwjlktqHmXbMPFkUSWLVz4pZkcSLwxJPpnZLsMJPohAeWLBEQR6LUoALpDWNLh5l7VE5LwmQiswWp9nvuClmYaKUYs05Alp9zZaSQLogs0B7Vs.vsSel3xDBosmXrVnTyQz5i+wNY4P02oBl74YjfqolqnRDjNoeVQAw0zkW0xBMFQXMqXD.YU0GXLUhvup16nF1QUE3nmzMOp22Wq7b8VMYMc2FSop8Cc8Bwvju75LMupSH0nZOyIcgolkG0yyvfTKRhfUUWHM0beSgwFKjj6qZbkLFKPZs.6alTGfK1bSY0NavHznqKaJ9wVM3ppF.mHCNY+2dg5DgXOiFkzl8Bk.bINwEEoEzQZPKvZMbhILh55+Uy+UUIaS8JOpC7r96v1vnlEZUkEvn+mI1v+c5DStfcA3fPHpY8PJGMsHgoabnQoGZgu0DXYHNRvQ6hvHwHrnpQZEgpXJq0DqLLFVAzxXSWkRTU.qNe4p1PqZFqVhq1NvWwMggpkLYpJqqSI1wXTTu+01IG+89xtC2e8+H+8mrZlLq4xR0zIVUnO4upo5MBI0IeiJY9uvXnYigt.x.DhKlDMvNISw0LolVuZfuV.mHrFnVgpfh1eqLSlN1pVWILS56ZnibGENqSXUTi2Hq0kEUiMfvdsUY+pcAOp9ept4i6H+pZzKDFDFHUx3Z0lQU2g7RNtnntSZj17nqqKU4riuHWj3lzgj.oXGS0bS0wqDXGm14IE02Nj0c8Q0c80ateU9drbmxrJ0Y8P88ip71cZlnYm4o00f1kxouAS+CsbvXLSF7wcA0XDLCeeN1YsPxFBkTRBTwLsdxx34FgTxTniU33KHJJ.izfWJeFKWdDBG193UXfxSvlQwfFXPiAsmGNZMZiFGeIwQJ7bgnHvHDfzFBSkQB5xHDRDFAtIZaTHP36hQUcZgDg1fqPfwj3emvNx3JbvnUIQ.ViT5RrVARIwZENNNnTI0.fvBX4Vm5tn5TYJLhIGPUfTJs.jpIAnRIcIRGWKlEpD0dN.c5BGbKsxrRkEC9fVSSRWjBMAlhnjVykS6jAYfFo1.FWzNFxqJQnSDEiJSgnHFqTLCpfAAxKETBIgZANNdnhirAQTJQnzHvFXSWuTDqBpIzJRfBD.9BWTFEFrwORJjn0ZxfMwbgFK3toFXiAgvAgRkzWsuGElI8c2EREHQifHQLRGql6L.YsrPDBHxLYJFq3.FGG7CD3ffhIVrUyhmpCMI8AkRacGv.sCLGf2TqcQXPoD4WM3HQ4IINLhrxTHQP9nJ344gajMSAEhCwyyiTRAJkhxlXTBPpiIkWJTAXyijqg7NFVuJhALFFEMQLoRDCdHbjnIv9iAtHS7OrlQXUMRVlnjT6XsfynAYLoapApTnD9dBBCLHkRbccILLrlxbOOOhh14pz4+czq+5b.nUWGZMViJeYN3i5nYjRSvs+m9k7V2m2Luk8+P3dtm6kwGZDNx29QP+acK7BuvKvBW3hoXwRL2daj4lZlz6niypFeL7CCXbklRZERWAUBU3HqyU.sgXcDFbQ33hiPhJRmL4NFG7.IDGE.9tINRKvnzIg8wMw4FA35QbbED.YbbIVoPqs0cfqThRa0J465PXbDFCj10CixZEjCBhbRhohRiTBwFAtdRLQJDZEUyxPFOeJGEhRGR5ToINLxF6.iAWg06hFkR5yMMyqwVXy4KhqeZJOdAjxXLohPqLHHMUpTAUnhVZoEpjuBZogzMmAUrlljoo216.2zMvfSTjULznj20mWahwwCeP5Pfvf1nIVaHENDmvYz5jfz56fnZtJSBhrTJPo.gzAzJLZSs7PY4pBTl5RgLfVqvCYs3Gnq2zsD+9rFCJQ43fHVQWNRlQ5LLsLowSHHePEDtdDFFx1i0TQGPwPERbstKX.WWOhqNQn5LLWKhPMMrJqv9A19LXgM2JgDREUHYjR7yjlBAkQqfT5D.wFRgP5PboJDFFR1NaCg.JO9DVYCmDGCDw3ncwMzAOi.eGMUx3gyHCwvae3DKlDIPpVWizF.GqYEdROzZchLYRbcDT69PK.gCFM363SnVSkRUvyShwnowFarFn.LY7.ihhv00k33ZNV9+ZxA3x+GcQ6JKGp5ZQVigVvvL7SQS81Ceju+0PuG79vO7O7K3s8w9v7Nuhqfma8qis2XC7u+yuYp3mh6+UVAW10+CQNy4vO8O9KXhvJzsWCrGcOS7KEfHpDkwfRC9HwwXsIvXrZRbEfmu.UT.Fsgzo7.iM2+HTXL1RPAkBowfIoPKLRvw2sp7t0iCOExL9nCCsBpBqnrRqISJeTww1fJ4JsZwTIAFDSsfaYiOhFGrS5DXPnM3IRjUEPETDKAuTNDRLwFMw9FREW0uXncEbPcMKFKWQ57PWJevO2kwecSalkka67o+FWA4aoQdfW403C9YtXb2+2DW8C7GYONr2AG0YcF7GW4xYcUpvRdqKkMLzHDTpBhhg7l6YljpbEbhhPPLkTgHE1fF5J8nZ.LrZy0f1fTXEj0ZisfSM1.MpoZ.3.WgCNHnhPPDVyoEBGLBIUwdcjVvYa0jXscHtl8zVAeIRhwfVaHKFlgwvRm1rYOatKZqhh41ZuLqFZgY0XKTtTQ1R4JDHcw2.ovkRnQqL3KbQZDIYXPZmNFic7OQSba.KNxit7ZfAhySKysOV9XivqLv1n8EsPF2Uvx21VngYOSFqwT7DqdU3LstooENOd5stAVwXCQ1YOS1XgIXc4FkVlyrYHG3YV0ZPzTG3lpAxu8AowlalgiBYSElfRBAJo.WiEnRgDiAbcwB1qmLaLRoDoTXKZPs.iQfizCzZ7vAsIFe+znhUzUmcxw+ddOrzC8swDSLACLv.344gTJQHD1wqcHBy+um9eD3.72CPTEbHkwPOMz.yOaSL3Xiw1ZHE+4W3o39uuGGzEwKRvsem+dFcrbL2t6hm3wdbJUrLejy3SQtQywi77OFm7obJDWIf0thUxhlQe3DGRXbYBLjLQThvnIEPJC3a.ekglw5ymmRimwZNpOPCX8krwjumFP5XMOUqT333hGNV.EGMlPEYLVSYcRtdO.OkhTXm75qs9DmFHURbB7.T9t1JYTqvSZHsAxZr2S55dVBi0uX+XCoRJmboZRSn8vJ7tOYagfRkY+N92Ku4226kUr7WgsL7.bNesu.Jihm9UVImyk+kn4EOOt468OwYe5mIG4o7Q4w+K+E1qC5f4yd0WC4yWha+t9871Nrifv7EoilagFyjhnxkITYsSP33REc3N39tDKeHcRP4bvZQiU70ZT7jYOv9cssltIsTfmQiiQiqzXiafJFeL3QhUFhpwLII8hHvwy25FGFRigY.ru8zGiOP+bZerOFuy2y6km7IdL7CqfR5vqVbBJKpVLTJjHIsvCiIFejjxBQivXvGG7cbAiB2D97AltCZ1yk8+Xda7QutqDkVy1xkiq8N+cLuYOGdpW5k359I+Ddquyige4u+Ov68iepbdemqkW5UeEhb73Fti6jVaocV9pWMe+a5lYgu4cie4s8a4jOsyjy8Kd4jeEqf96eKLJZ1Tg7jCq0BSVZ11bOIPkDDZq6rVOwzIJtlLwptFM9TsDvLHUQHQygcnGJuqi63nwlZlFZnAV25VGEKVDiwTyMXGGm+6Slv+.50+Zq.PokjwOCaXyaka5G+SHWXY1aen80L.22UbUrPuTHEZt8OykgLNlNDB9NmzIxJdsWi2969v3C+4+b7Gtoaje5i7vLQ+grjYNWFY0i..aNIe.shOYQfj.xPUyQgT3PITjFGLnPgEbPyjA5bbfbJaxFhDfJ1VE.9X0.kVamX1.SFinpArqZ.npfs1AD.wJav+D.aKHBWePkFDUr901XxynZ92qZoc8A7JH47kw5KsDnSfrpBXBmfeyUek7zOxCxy8zu.AAE3qbBe.V6PCvKuhMvYcleJxKhY30sMtiu20vJejGhkc22Giuncm65WdGbaO3iyQbFmEm2UckbSWwWhew09cYO5c5b.yXAzx1GhWZ7gX.UPhut9fPiQDgWLzKV.qRIsqpYzoDPnGTRoAgFW7rtaHz3pgFL1f8YkGreVsJDs8SEFCDkTK8tIAKrhtB34.w1eSAjKpH4ZTPK+K6IhCYoDdK+PBW+FnRgww.j1OC5JSfVXHiQgSRU4FSLFfFPZWuLDgQAMJDnMFRAHjFJGThgGbaj+IeRdsWdELvl2Ju78e+r7WYEz+fCwy82dd78RQ4IJxSs7WhNu66hWY0qBJFv5ewkwPaa.xOx3r1UrJFenMgJRSwR4gvhTIn.5vPRmxEGfLYZfxwFbhJWyiJQRZGRAnbiHAaDgSshiGjRbzJxnLHQSwjwhrIxS5JUHe97Tpb.JkpFPP8VKTEj3+Wo+gYqn1E9egkCMpT7lxzHGWm8ha5Lb1+leEqeyahu+o8wXws1NaarRTHJFmTRzp.RYz365SKczIiLZNb5qK1iC9.3OshmiEtvEhXcCQ+KakzWqMwS7ZuFuBP.BdS9sxdNqYRZhQEVAiQgmi.Tow22mXcjsdKLFhqDfuzAMJHiOCGVl0M1HrkhkYbAnbcIPYPoEzEwrvtaicq0dgRAfTR5zoIkmGExOAQAgjJaFJqiwMkOJkhAFdHxUXBlPqXyBHTBE8grAvQjsS5yOKlFboTXYxjNEFighkKPyYZhzZCgUhvowTTILhBRCMkICiMT+zTwBbXczAdNtr4FZgAhM3XbwQZHtxHTIkKqtLz5hVDSnTrrUrRNzfBzPisREijX+Lr7stEFGEGy648xYbVeJ9k2xMwZetmmcOcqDORdb7b4E1zZX0lhLrBBb8vfhHildANrF6h1ERF2IFiTfmzgwCi3UxMJiHfhNfP5guRRbbHshglEPWNdzZpFvIscM1DKLjR5iHPizwisVbBVePQFAHVJPncvCIgYRptnPnGzr6n4.mybYCEGEcSMRqSaFr4k8x71m1zYsaoetqREImaCPbIZsQeVbYIZGAANRv0AGifXkAsi.kVimqK53HxjRRaQZ1KSJVXmcyly2OAl.1hHCAFCw9NH88IJHFeiC9ZG1RgwIX9cwzVvb3Y+yOL8ltIlSacimRStb4n4lalLgCPwJZDY6ftS2DcLx1YZ80K+07ixCNv.LrqKZELGbnIGWBbbIRYsL1AXBlTIVDPreZhEFvDQ6JAyCG70gTLiM7Y8HxxHkKw18SwteP6OdszJKaYKiMu4MiTJQoT34Yq5i+OOfj.TQUFiTSkvxrgsrYxOQQLwFhcbYcEmfUUIGEvhZ1LVMzYKDPO8zK62nE4Au9eJK7Heq7ktxqmgV9qwG+XOdlUrO6d6yjUO5lwECcDWj4J0TpTIpn0HasYFb7bjVVAGOGpDFPnJhTMjBgufJkJhSrlLkBY1oxv7mwBXiiki+1PalsEESjuKETZliBVb5lXVtoX6kxgrwLLdtsSQeWazo8bQHhoAWIQkJPiJAuk9lMQAgL3fCR5fxrg3xTpLzpCr+sMM5HDxmQPNeAggU.GIszVy153HVS1VafHWCRGGZzwinhk4.l9bHcwwQTXLBMJFZrgYD7v0yGJTjcqoz33jgdVxb3y7i+oL311Jm5o+I3Hh5jBwALJgHbUrmyYVTHLjUcO2MWz8d2LVaMve79tWlteS7wOlimNCBYel8bXj09JHAVmJBWIjRBS2OMGTqSitzvPlRn8Dj0MM4kBFu3DTLLYcffFoRQVuz7VhKyr5tW5zOCBsAx5hw2ghAgXBhnkTooglaiUM5vTo+hTBnnvfVDSHR7C0Do.W2LDEWFMPJ2TjMUCb.K8Hn09lE+gMzOlnXaE2h.IBZ1ykdyjk2SmsiISZVy3CiW1LzfLEEyWjFatU.a.rKTt.9M4ieXH8IbnYSDGP1lPVwm01TKTPERdOAQBABWeZRjhVTdL+Faji7hOGN3i6n4ydxmA4d00yzjdHiCIn4lIaSMQGSLANczFqMWQX7wo4v.7CpfIrr0B23X5DGNhtmNyqgFILNFgqlRk1NgUlfMVHhRFG1lIlsBLZXDQnHq.lsWJNll5kt8bHW5.jRWZnnjASGyiVbTdlG+IXLrJpSmNMkKWF30OnPU5+wfC+WkRyXfFZnAznXqaseNsOwoSkfH1uxkIJVyDFE4.xA3JgIRRUko7XroMTf4il8n2YQ+CLB+9q6Gxit7kyVykiQh8X581EoysUJp0zdJGZHnLCOvfbxm4YxddzGIm8EdgHwv23a8M49dv6ievM9i3Z+xWCRCbVmwYwIbzGI64LV.+wa82Q9sNBKYQKlPoKEFXCLt1V0VtJnwXCgCOJ64bmOGyIdB7CukeFKesqhK5RtXZJaiboWxmgC4e4f4vOjkxc+q9s7xq3knaZfEMqYSrCDuo0PTCQ3VDjiOAoTtb3G4gyddnGHWxkcIjMaV9JW9kyCbe2O+7e1OmK+Ke4jporb9+GWDslsI12EuDdsm4YXtMzHdYDLdkJze9JrErly2BPKEfYzYOLd+CxKbu2Oqdaah3B4wOPx3irMVGJ7v5VPKYZgCcdykmarsSkTRdhm+4voP.u1V2LSDEydMmEvdO6oyyswsgwZAqMHuwJRWN.8HSvXpAsUWgeyzTe8QSBI9XWvQZshTtdLio0KK02ivBkPM31wXLj2MjsU1VnVyp0VXzbaklm9hnwXM9IBbhp1W6JvKQNVo00bESEESkxgbhe3Sh1N32JK+geBBV2JQqT3iOwwQDPLc2Vqz1DAjqTANpCZu44e0UvVW8p3nNzCm33Xdp+xSwL5aFbP60dwc8P2MgAZhEvDFXubSQuYZh0GmiQxMLahIq0gYfKc07zISZAq8kWF8LmowDaYqzovg3gFjbkFkx.o52g42VFFY7sxgbPKko0Yu7B+weGgEySlT9DiMlSYPQGFn0BkovD4n4VxfTHnhD5omYPYOeVaPH9kJgQGgtRIRQLs63y7R2.MjOOUxMLQwZ5twoSmczCOawQswCy0NEVoTHDBbbbHNN9+6RkYUPBiwPFfn.MgNZZYVsvW9K74XvsL.Oy27ZPnCHhPpfsnWJqAODVSobLnEQbywv+hiK6dAI+rK6ywBNw2Oe1q8Kwe86eCTzjicqAAau.3UtLjwkM1rfB6y7g2x9xnyXZP5rTZ+OH1xV1FqnmEg4s7AnR4RrsYuarjy++f86ssT9ACsMdve+cydMxV3MmMKGfWJxGUgXgj.zjOcZFyIjc+HNH557OSRElmW36cCLmS7zIJHfs+S9Uz0I8wXu+jeLtpAdM9KOVN9PG9wyi+pqk225WOc2Pqb2SLL.3jJCa1Dv999VJhi9vYC25sPyM0A4Np2E48agG59dJtji+TojqlW8m7K4q94OeN5i88vgezua9YO4yydaZlCXlyjlaZPJu0MypwFmhlPR6s1BaZ3swIcVmAUjPic2Di0Xq7piBOfAxQZ7jUnqxiyAsEW1moOSlSkhbKe7+UVkiOehK7em1S6x87SuI1qFZAeFfWnAMFsCNUTj1wm.2XBmUybJe6afAGc67muzOGHCIJkOAAAH.lMvQIxxAnalea4sx5GcLVenjq3puN9vG66fS+LNM5o614+3J9Z7W99+TdjeychrgFqUjVJos9GDwJhvgHT35XMatBfSCdnFSwke4eE5ZQKfWXMqjCo0FIH2HTgXxBzAPKEhXvxE4fO4OHK8p9pr5evOfm5mbqbQ+veDs1Zy70NxCkK4xNeN5OzGlq6ne+jejw4D+7WBuzy7bbpeyqgY2TS7I0YHpIAKehgXCIsuERLKHsBxOAW0UeCT4FuMZMeNNr8dOY0SLJqujfADNnyzH6lJfbc2Iu8K6yxBNjCk6XoqmnAGfBkKiOXSAr1.ThMij9N6OIG3G4CvW8J9r72d5mfCqmYRwsrUVP5FYgo8PnCX3hUXb.Q4Inje.uP5JbfWzkhmQvqd8+PZJLGAROz3gVaAETJUM2Jf2Xrd3Mj5bnQ+LDWIhN5sKN5i68xZe4WkmK0O.iiGwUKTTisPXSR3GwFSs.8sg92Lyq69Xel+tyG4ie5rfkdHz+88nrwkub5rstoXg9skksiOMpc4W7stNtye1sx.O2KxfNZ9Xmv6ivzoHrbdNiS9CQ5XMAqc87at5uCO5ccW3C7899WOO1u8NvY0qgNZoYRs8JIk8JjwwgPsK2wsem7zCO.22i8nHFaXtzOwoRZmLLzxeYt2e7Ois7BOKK+9dT9ze7ONW3W3qyu4G8yXE+6mKYl4LnghCiVCkCKiwn4JuvKkt+IKjge5mk9MtbNe3ShWYyakQGZPN2y9SR6Y8YjWaEL7S877xhzzlxv65HdaT7UVE4Kji17bnCee7CiHFCQnQaf95YF7IujOKqN2v7it4a1VNwRANJAFgAkAxCrlhiPzZqvdN6Yv7m07nXoBbdm4YhAbGu91...H.jDQAQEEOxcbmLx.CQecOcZt3.DTwFoeiwjTfNF5omdvOaFjtNHkRpToBMf0RldaoA5tsowF151XNG89vG7fVJeiq45oGcLKvym2jqGc5Ho8LdL2FSw8maHRO8dpYY.QppYP0tPkDRhhhvCnIA3Hj344QtbiRwMrAag8DqHJxl0gJTsLIDjVEypdpmgY8G+yL3e4YQ8Zqkk+muelvAFp+AXku7qxesqGmw1vVXedS6EG6w99vIeI5r6NoLAr0sOAcMmdIckgnIADFZC7bgxkHUiMvI9tOV1sC6P4O7suJJNQAq46LNwFas0lNcZFe7w4Gb8eeZ72963Eewmm8cNyEuvHz.gZCgLok264RdSr6KZwj10i26w8t4Ke1WLW0U7U3w9C2I60LmGtBOZuy4ia+iPaYyRTjhd5tWN4O5ofNHju8u3WSP9h3IMHIxlYijm8qmLSrqnW2fCYwGYICs0dqrpkuJNr86foP4JLusmio08rHV3QDUR.ErU1uBgsBEkPEkhwzU.SYTEJyU94tLZa1ygm6gdRVzzmAYkBjzOUvgRQFVRGyFUgPhFZCbBcLcd9lhY6adM709Y+LJGo3zN9Sj1KEyGpu4Q3y9p7f2+8wG9BNOdmerOJxxE4Q9xOGMhCYwEeDjFM5REw0KEd3vXCMJsKkzWyYnk0rRbTo3CNiE.CNJC+Ge.l8vkXs22SxCtfaka41tMhhqvA1rK80aarssMF9YRSOYaA2RiPwm7U43R0JllZgG6u97bLumiia9luEt1q5qy8e62F6WGsvpt9eNO+M9q3c+9OdN6q5axyba+V9Rm6ml4N24RaROLDVs1MoX4H5Z5ylC6Ccpr30sF9s29ehJSLFQF65FPKhwHghwvZ.xoKh611Lu4Es6zTtw3hOqyhsC7WV9x4HxzDyo8FnOsOSPLgnw3JPILrl0uNdOuuim7Elf2RbLcM24iHISBsBzpeFlfPFWMAm34cgbvK8swK7POA+1K6RYS23MRqaZsjs0z7COpCkng1NGzbmE+sIFivDANWiM0xRIDG4XqMAWGTwADarEfVZOetpu82lV2+8mK7Dd+X1v5rlJGDRD11RAshEjoI1vKuRtwS8SSnVv6hF3W7ueQr41ZhS33dO7LO7eka4a88ooPAqYq43zdyGHiqB3ae8WMydOVL25A+9ohNldaqMFXnwRR8sDurYHLLhi7HORNvS4TXk+96fAVyZINYRuM0iFTQJ7b734W1KxbWxaFcTDRsAsdxhOJMVy+MwFt3K9hQdcWCuxxdV97Wz4hSWYPO8l4c7uc1btmy4vYdZmJO1e4Y3eosoSlToPoB4UW4qww+dNAZLcJ5t+swr6oKDiVvV0kUW0nuACL.+u.bn93MTe7GTDWyblTYxxgeDucFdrbLwC7HTnRo5pObYspETinVUzUV.ELP4vInkrMy5Vy54v2q8i8be1OFccafVZsIL.8igvAFflBflBBoWOCcmNsceMvXHkij7iNFcJTrWSqWZQ.R+T7Vl2B3gt86fMUpL+0689XOBqPmszAYvA2j0rPjNhn.Cm14btbXWv4xO5xtTV8u9WPWHY3JkoREE5RSP6s1JG171M9qu7qwY8oNajc2MSCXfB4QJrZbd4g6msWpLocUjIJl97SgWCMvyJEzWOcydtf4yB5pSFISF12t5gYMlhw8kLw5WOO5McS7Gt2+DJGacU3EEiKSt7byzTyrt0uQt7OwYxFFeTJluHtd1gPMfxnP33f1UfVC4BiYSAknwsrIVxzlFO1C7.Lmi5cvW7J9J7R23OgJQwLCmLrMJwX.FoA2Lono1aky3SdlL13iyF+4+bJUpDNNdHhhncfYzQ2Lw3iyZ0U3a7s+t71uuGAU+Cv91cuP9wo6lZFDJhBCIcmsx.pRzuJnV5akIM3njc1spVF3fsdOhBp.BC26ceOz6F2H8u0sReYZr5x4.G2TLQb.kEBFKSJZI6LIcr.kVPKYaDugGj4bv6CW6O9FXkO4SxI8td2rfN5f40dOHJWBhpPiNRpToHAdBLZEc2bajZnwvAagLGXTfifq65+draO6ywxd1miYzZa.jT6KInaIkj427a9M4Me3GEW6I7AX6qZMStHvRj9KWtLMjpA9.G+Iv+x668xU94uH90+3ahk8.2KqdCalO149uge1Fvui1X+emGIuoF6hm8deP5sqNwssNXFya9PPEJGERfNDgiceP4elzqaKGhPSYm.J4FSOyqO97W8Wmk+BuD2vy+7j12CWiJoHZhrVNTCWvlEcoK3DAUBCHSFC68aco749d+.V6cbabkW3EhSEaA0rVzrh74viX5F3s54SShIXvfTz+n443e+ePZzHYt3Ses0Fu7FVCYR6yLapSXfwoAgOG267XYS2xsf1DCDhjDS9xlBgVxe399yjqi13wermh45zDCO937PiOBBft.l8vSv7y3Ses0NyaoKkK3p9O49+pWH20ccWjIcVhYLdl3wwY773ggEJf1ZuAFajsxPNA7su4af68QeHh13l3P5tORMv37p4FhVm9rYsqXk7LaXsHZuAp3X.kll87wQY2iKUnrQ4VUhQJliQGeDJUp.Y5rEbj0Vs1XLJPKPYborPxVLZ5LNfE63vr8xv4+udVb.G8QwOeUuFuv8bOLqrsxvEFAOfvnJTHnHc1a2bJm0YQtA5mez89.P4R152G6Dir3RAWAehS5Cw5W3dys+c+t7NZtYJjaLdohiyPpPjHIkmCEihHzGJlsA5GHxIY8cDFhmTRnVhqzkXUDt.YbrkJcPP.W+0e8DzXV7KUhCYwKFcrsj0ic7vDGvFyMB2PnBgJh9vmY2dWzrHhMTXHV2K8W4W+yuAF8kVNyIcZ1sd5gnsMLSS5ROs2BW3I+wHeaYo2AGi8eAKhTw15SYDRpqEsMndqd0qlUt4sQiiMJytk1ngzoSV3UJbEIqxTCbO+o6lMtsgXEu7xYgczA8Ov315vQBQZa0O565wgdHGL60AcfrayYtDOz.r+CGx7bZmUeS2Nmyu3NXfBCysd2+dZXlyfa6stTdgMtV5r2YvO4G8SHd6CwU9gNVTpHlHJNYsm7Fu6DUo+Gsjs2UT8MHWeOBiCXnsNNW8W8qyHaOG4FcLZ2ugZqIB6Rr0VZt.3lTgbpXawfjMaCDDGwxd4Wge908cXaO4CQbbQjIPKiCT.akOlIcZZb58RgvJbwe0qBeOG9zm8mD2BkYOl2tw11xVX0kxSedMSa4Gm8XgymK5y9YwTpBW8C7vDjeBDBCMXr4WtbPIbjoXYO+ywVBhYKu1pYgs1JlPqekg.YcfoM6YStf.Vd+al2RCGNd9NjAGRY7AgOEA1NRbQRaDSltZgAzgz4hmGeiy4r3Nt+Gl+3M9S4.ZuOjt9rwbCaKS7vhjosN3KeseKZZdSi+sO5oP7.SfaxpRn5ttzDEyybWz73x+U+ZV+xVFmxo8wQpUPbxVtlz0tZG0JvXHRHnfAFXhInRtwn6zo3m9C+g7H+0mjG4O96YNMlklD9z.1rIkJUJzFCilaLNuO4Yx1291ok0udlWuSivPaFH7wALF7kN79O8y.Nv2Fq89e.711VoXbDaTERdYJJniIJJt5ZvhIFqDxztnBiQosabMwZGzXWotUWmFwpHxjJMpbiy246bszyR1cthK3+fBiLJRojPkgPkhLttLT4JjCnG.CgLMohQb0z1hlKxvw3BN6ykEqEbPyY2X6CNDikaSzlW6faD69hVL64wcLLzcb2jOedPKrEIUxeoaJKQAg70+FeCV79r+b8m2mF8DSPXkfpqBhIK3Hgl632dabOOvCSSCuElc1Fw22OAjAZSZiMQoJk4JthqfocG+FV8S7Hrno2Krw9oQeOPJvyOEJuF4N9Q2DkZMCGvg813cbDGMemq+F3absWKcnBY6CML8zQq33kkhwE1gjC7FM8FR.IchgV7ZjA21vba23s.RelWoHbcRAhjELax1okgjceXkc4U2NtznTRC9oPKcY22sEwS8DONO2e3Ovd0a6X77nHV.lVbDLMELmFZhf.GJVxgdVvRnyL9rfV5BmHaUU1e9QYLfdERRmwm0ttUy4cdmKobSCCMNslNEJiM3Z9.o87wIRvW7BtXNjS+L3G8k9hLv8bW3UYB1CDzZm8QqsjlRlH1XbI5cuWB+g6+2ye5u7Hr+qaiLuEra7paebhIssJ1DBllIl41deLTwwnsYMMNji8XX7JU3Ut4akY1UGrxbamUilL.czdaTVaXKCLHnmf7EKfuuOpXaY2Ff07T2TdjqXdV4S9Xrx0sNhiiPEapUAlNZe7MI6vQNBjZCAZEkvPJOeZHcEdfG59Y0CtEL9tzeP.ysQQcqwTMBogQGOGY88n81aGiPfqzAeeebhCs69zZPWJhe8W8+jmZ12NO4S+TzRWsRCs1DsWp.4zQTlTnbRiVUBhiIaZWJVI.GOWTw1BJ1l70PTFMRD0V94oSmFGGGxzXV5pmtsQiOViQa2iuTBHTHw02C2jZuXOauUZq0lX6YSyW+6+cY.UI9WOwOB6gJMtkiXSEKvD.caJQZgCu82yGkS7xtTdBkG+pa9VvCAdXAhKBnisqpT.l9zmNNRIpXEpnXaI6icgQIbLjISF9pW9mi86PVJe2S4iiSoxDEEVyMoXMDohw2yi8de1KNfi5cvsupU.kpvFaHjULznTbrAokVak8elKj0c+OIuz5VOm+W6Kya83+.7S+S+Y9JWy+I8EFww3GSy8zC5X6J7zXh++NKG9GQRfvxUPoTrn4uH9o+o+LqcEqjq9T9XfRiqYxcE.6tjrBowt6.5.jECSqgNvu4VXjxk3q7M95jo413LW1eC+nPxGqS1xy.oJhY45whmder1gxwf4KxG5jNI50QRGCLD66LlAqb0qhhDSiXWaDdNtTIHfQGdPJkOfokOjt6napeqbwQCob7Xsq50XVKeYr1Mrdx35xzmQezlSJB873EV2pYcpXN6K9b3L9OtX9deyqh+yu02gd6nWbQvH4KxDDhOtjxDwatm4fuwkUL7P72t26im6C9AYzUsFVTasRlfH1vf8y1AVBfuzkbiNBm+4e9TnAMsTJ.+9VDvjkrsF6Jhbsqa87A+fmHU.ZssVv2wGuj9hQowPLtBPIDIfKdnHl74yABMG265cwW+GeC7BOv8wW6x9b1kYd0mu1fqmGKZQKhK7acULQtI35W8Ggx4KXMFAHGFFb7QYQs0E2yCe+z+AtTtfK8RXk24sR4IJvRlQeTdqCPYCLtNFimOwQZjUrwOIJJFDVwNCFDdtHzFDZ6V7l.q+4ROImy4ctD2XiPt7r39lsMVWH.ULFOAgwwzAP29BZu81YSCzOqv.acjbL7fagdvmt7RSTXDiTwBN3zTCHS6ys+6tSV0DkYa+teWxNntrFHbC.pvHzwJ9bW5kh7q+MH8.agCX1y2VSOSLNJfTRIRogv3XjdNn01UqabbHFixtOZjrjyS0PFBJTgS5C+gYwG9gypt6eOa7EeQF0Uv1.F0.LVNpL9xY9s2MGvB2c9S+reA2wi+fr5A6meyu4Vowg2NOvm47IrPQbjlZ6RU+yh9ez94PUZW4hgAfztTTGgqvgUthkyFV6Fr4aMNFOswtHlDFBcrBrJoFWgDmXMyAAKp2to+JE4YV+V3Fu0altaoSL4JR6czCqL+3LDV+AyBrvt6f7iOBGym7zYed6GCWzkeYrxG4AYocOCxN1n3GGfDnOf1CUnpDyLm6B3x+0+Z5eaamu+IdlLQncyEWfIYgQ4RrJjezu5my272ca3YfiYVygRttrpg2JzdGzzAsejaYuHu3.Cx5d0WkfWaMbrc1EYZoQVU+alAByiDAdDxzPPeszDETw74uluCqK+H7s9heA5KBVvr2cFYKCRiXnEr0LPqECnqlZhy+KdYH6HKe2K6KPbXjsd4iAPhqTR4xQrv4tX9xW04vVFdXtxu0UiJYqR2tFFrvvZQx1GuzpoMVGgFC9ddrpMtQdlm9oY8u1ZHLRgRN4N0U0w6srksvO359tDEoXfstMlVasiRYHFq6GqZ3AX1M0N831Ju2S+z48epmL2JE3W9suF12NmAKIij7kJSYCT13BN1s1NWscOdxT07QcDlXKnmxDgGBJgA+zoHXjP9zm24RKyZ17itxqhRAk.oAgVC3Z2SMD1h9ZlM1NUDRROiYx7ZsaNsS9Lo0JkYIs2J9FEu1falJXsRzUKvKRhrnhM+pqlsus9Ydyb1DTpbxtBl8uTNdDqLrnEsHV39serra6VoRjUIX0TxpihIJDJnJvk7Y9Ljss1o00sdda61dfrzD10gSBfWPP.Roju7W8qPW+peIa8QdX18t5lAJZWQrEPRQDTPWlsme6r3nxLmoOcV9C+nz9LmA66tsXb5sCdHOIQpJ35ECAg+8+2.vafzqaKGrxtFbZvkWc0qhOwm5LnX9hrOJvyUR5jHb6EAtQFjB6FyQVzzrzg8py9PnTz3rlMm2obJ7qt26gU+Tu.GVychuzg9KV.6RUwvt0Q6zQasyy+Zql8NaV5cOWB8zVqLXpzzyz6E8vCizwg8n8NvToDM2RKD34vVKNA+969dHXhJDmT7MfGNU2TawEDZ9Tm4oyRO0SkOym4R40V0FQUp.8WbbNuO8mlS4R+BbdmyYysdy2Dq3O+PreoxvRZsMd7A2FqehBDHbIxnXt.6ducxHkFmbRWdqG0wvLGYXt24+Koy7kwGWx33wBZrWltuG8keb7cSgz2vh2ikPyc2Fs1XSnGOFiqKDjrHxzw3JcHSiMxdezGMY+a+MZpolHNbrZKxrvDwaGoDi.L5XhHhzHHa1rDDGwpVyZ3ycYeAF7EeAVxLmAJkZRenSPHhCpvi8HOJEyWjYFEY22LbbnRrEDZLilMOdNldO8vC7K+0jeCqg64weXFRanPTE5tklYgFHtbY1hIlxNRLQVs9RR1HU0IalCxT1MvGkfPzVs1JEYanINzC8Pos2zah67mcyDr9M.XKc6L9oPFTDWigESVlc2yjsDliK+puZl4drubBuiiEm0rZVXKsRgsuYbAlozCsVhuQfvH4z9DmFGyEbAb2m+4aCnblL6fd33JA3Ic3e8rNKdKenOHW211JCu10vV151psfxbkNHk18jiK4RtDl8BWD25EdwDohHLNpVlYh.691fwfqeZxlMqU4nvfmeyno.g3SYofhTFcbQ7yWlzobYu5aV7zqac7tNhCmF0Qb.4FmYsf4Q4sN7Ns069FO8FxZqPKBPQDKXQylO+27ZXsqYCbqWzkfTnXul4LogMuEFmJDflPCzDoIMRl+LmCDMNKe8qhS9j9v7gunOKZgjq9oddldWsy3EyStfhDfgkHfY0TirogGkAh07U95eCtw67tXauxKy9r66NO+DamLhH5aO2SJUHOlFcHcucy5FuLO8qtNd5K+xQjqHGTfGyelyDkPRPxdEYPrAuTNLyYOClyR1cZn2owHCWhOzm7eke4s+K3YV85Yue1WgM7hqm1BLr3F5l9Zzi0r7kwy3ZW7LAlX5DXgM1.Sqwl34FcXd0Qmfy9S+uw34lfMs5MSGSqOFMxfHaSzaioP64fJiCaHnHqchRbpm4mDeeOh2zV3M02bobrMiNwnIsziTdN7Bu7KxG3HVJ4JUhIJVBu1ZCCCZ0lkRfR5Rbx+IL36IIcjBGLDoLnj9bkWy2g4uu6MeyS+zgwFg51ELIVY2Ug5omd359U+JFanQ36bRmLhpa02X+enpAMvJFYH7l07wecqkevicu7u7ANAtvK5yvseUeKTCNB6taSTYyqmgUJBkIa3NHQhexZmMAbPayhkzwlNbAPXbDEKVjK3Bt.Ds2NaYkqf2Qmcf+HNP.3DEfmQS6NtrGszKCM537TCuAd30sB5qRIxmeP1mN6flEJ7y5vdJyfrkdIHD7iTLHQ7.O8CQgaqEd1G8Qw2yi3j8agHRVsuNtDTtB268durtQGgW9keYZUJHUlTTtP0Txpw0wkFyjgEtaKl89sbv7fc2AkGXHjtt1sJNfFEPXXHdt97EthKm48VOD9wkmfU9XOFNxrIaBLwfz2tpTigMfllKNNynqtnqToX1KY2HN2njN2nje3wn4TowToB+yjd8+epM.NBWBKEPG8NM16C3.HP5Q9LNLpmBoWFlyhWH7+W68dGtcVUl2+eVOsc+zqImzqDHfTBAPBMEjhJRGQAjAXTFvAEKzDPEADonHEEFDTo4fRKTB8RBIPZP58xI4bxoW28m1Z86OV68gv757NyOQtbdmqbecsIbN6ydued1OOq60c4682uA9365hiYDBBzj4VTaKpYelItM2D+km4YYnzYX0u1qvwL4ohxvfV6saxKCwAXh0UMwLsXBe1Cgy9nNZtsG9gX9KdgbMW32jK6acwbiW8UhcXHW808i4I9C+Nd224k45+QWMO+6tL9vASyO9tuG76nGdya7miePN7T5JYjCIQiGCW+z7KtyeI24KLOdu0rVtwq8GyEeYeaR3.W2MbC7RO8qvXapE1+IuuDlOC9tJbAF.8rBDS.UqfpchQXnhO+YdFLqXw39t6Ghi8vORtm6493Au86fA7Ebw+K+y77u1KvpV6p4688ub1b28va96dHtvK7BYBszLO1sdGj22mPCcd4wvBWoOHCwNhEM1RSD1WeLPtgwKXDdsBgZ2UOCEV9JRALtJRRrJqft6c.DQhPS0VO053PX.rqfBkzbK.CAdddDff29MdCxmOOAAd3golkr.b00Ulco7HZlA3vimfolrZNlC9v3f+BeQl+K9R7JK4w3Xm3LXhUUKaendPEB9BExRrlstyDkZAmPARHTpoz8b.1115YDvWRfm6HrYTPfOw.jgADCXZ01.BgEVwrXpGzAx0e62NIsrXFszDgCVjU0SOTc8QHdsUxF1XaTS0MRCM0D6X6agUN+4yq05VXzabaL8ILYx44MBctYflN+JpT7HO0SRvbeVlnuGGz3F+Gwd9TBDTd93FFx2467cnpFaBqkubl0TlF3lUyMHkq4fkdf1+8Oxej8aKah2dAymojJEcmSVhb5Cz2HIzNTxBjQonPAWl73l.+366dwav94W+kOYhEMAtEyPTMpP9jtD9+Ty3+5+j+uaw.LCroRyTr7krRNpi7KvW6RuTF6wdDbyu5bY+ufyf2tmVIr45XHKCRGwhwdnG.AiuA1nHOW9C8Pbq+weO8sqcxic2+Jpti9ol7grt1ZicD3RDfIE0g5pHIaXaaiwc.eFNxK5h3fl0AhCv9LkoSxZZhHIqAmZaDFynvXT0irpJvYZSilpuAFaiMy9tOyj8ZumNlwD3pJPLrFopyAAdHML4TOyylq6G+SXpSaR7jOw8wbuyqms8T+6b31wXuqpR9cO38wC+BOEwlvnYnroYbUVAQElXqfJjvDqtFpptln2BA7MtjuMeuq9pYxSbLb7egigC4qdFLsCd+YxGygxz9W9Fr2m5mmLsjj86B9ZbTm1ISMsLZ9xm5owW7j+JL1IMIJTrHFVVkfIb.UfAdtE4.m8Av89TON21ccaDsxn3EDNRk9E9gPwPrQQTCAwPWSiIjpRxaXP93w3W7KuC9rGzrXmqY8zrSb5wKOYPW3Skg.CCC5omd359wWOWyO5GQec2C111HKAxKEZdxrefsjIMoyNLiuol4UermfK8DNQl2a81jXLils2amLlQ0H6aUQXTJPIAeqPD3iERrT1HjFHLEfPgPnqMUYbEZaayi7nOJOw7lGSc5Sgb4yfQoMJbPxDDNLkJpjcZ6y49C+NL24uPlv3lDipkwye90eSNka3FXQFV7sdh+Be06+2QasLNN5q9Z3Jd9mG2INYNiu4kwq9VuGm+Y80IW9BXYpifReOgFt3IqHE+ha5lYdyadbv689poC.0GoJXFHvTJvFKNrC6v3HNhifJppxQ3UAazNFrABc8v2Oj23MdC9iO5iPe82OdA9TvQgOkb1HJkJhP+yECEPzXz8fCxi7GdTd9m+EYvB4wyTSgN9erDg96u8INxAIfHPO69iswwvQbxmJKu8swfcuMFZ3AYKstC9BG+Ix0ey2Ly8d9M7RuzKy+xM9io8suQN2K7B3Auy6lfzooYSCFaKigQmpNV6N1AapPV5GnYfoTUCXYGigTvu9e62yatx0wFV9hXlUkjm3t9U7guxqxZV8pHZ7XbkequEcrysQvP8yO8qeAzUOCwF1113r9JeErbKvDGnGFSiMgoktZ2l.FlBby6yrm8gxLOrCmINpwvG9BuD+tMbabXiZbb.SbRrzt5kN1v5omBCxx11FX5tEIYxDLphdDPHiwxhIVWir8t5kOLcO7ytkaA6DQwbfdYg+4m.0N1AabQuGJkfwdW2Eu46+FLXm6hG+ZuA5sPA5bqaku2keYjHVD5XkqjSrowQW8MH.DCKTDRLqHr90sQd1G5Ov525VoXQOh4TAk0KRGCSDxPLJpotul.lRhjTazjzVt77Ke3GF+Jqjy6TNEpnX.AYyS6tYIKkIuFSLLrnlZpgG3AteFn294k+gWC1lNknDcMuZVlcq6zu.evPE3.puAD82OqbkKiq4t+0749bGC+5u+UxtV4pXuqaTTL+1oWOcK8DkTnqxyfoxKPS8eFVnB0sIzyyCOWW9C+9eOpZqgN5nCFmiCVlBLBzC62jpsNR5ExazW67lqb4X71ikJy6SlAGfk8puNcricgxvl0toVwvD5cvLrss0Jss1MfLPga1hLP28SeCzOBg.KKqRrPJXKrzZDDvXG6XYulwLzpCl7ioLmXaaiiEjLdBNyK5hYbG7AyMO+4Stc00H0ARCbLSpHYkjqXAti6714.Nx4v8bQ+SL35WOAlez6oQIcD1T8QyNRXXH81auba2wsSP97bBwifafOVQr.W2OoKe++p82kVYFMpM8md.lzTlFW1MbCrlE+d7cO8uL+qe9Sgd6telym8HfVai9aamrqcrE11hlOqZsqAqASybu0eIiphTbnisI5bv94M5nU1X9Lzs.RpfoGoBFkcRh23XTeGNc....B.IQTPT4W7cuVdvm4E449K+INhVplI1RcjHLEdssCNzpqA2v.7251Y+RjDqphg+tFhIXBEppZ9LmvwQ9gFh9et4Btt3E3govTifSAjHdbt9q95H0i7mYoye974FcKzbTG5ImO13xd0bKbqWw2msjRR8sz.ctqbTecUxmMTwt5pKlYU0gkuhlN5ilidpSh6+A+sXleXNxwMVpNSFZatuHyJUkDFpXcOxSRUgE4rG6mggeg2jfDI3fZnQ7xlAyDVDJKhoLfnFFDCCxWRGGhXEi910N3JuhqEogfZarI8j+U5ZgMQvgBj.ESBASJRJldyihdxlg022.zwPCyv6nUZv1lTwhRt7EX6EySrRDQpkkklbahDgXUlh5cbHQr3DTzU6HU3fTUDAFfot0caRERwsuUNkosWjHbbju8NwOD1Xtrrlc0Fm0jlIyL4no2b8v5c8wEIABiOpaJJczzRobjYu.Lvxzl68dtabSlj3dEwZBigf.MUA1PrTzT7DTukMGzI+E4sVx6wCe++VlTEUy3qnBdgq8mPg79b.gBdka5VIWtbLainz8y+J7PO0bo9rCxy7.2GuvK9TzXqcx9Moopa6NknDOkDGGGxjOGW00b0Do15H552.66jl.EyN3H0nQi2rPxmMG27McSjpolXWqd0LyQOVjERORgKAIYGZXhjLE6XG6.q0TEaeGsRM1FPf+HqirCoTcYztKLMMQ46QKM0HWwcbKjs+93ct1qmHlFDJySvmhoT.+cv4fI5ufhmLEabiaj65JuR1QmcQkgBlVMMxncpfd23V4l+9+.Zsi1olJpfex0ccDKVLlTyiloQ8H8yReaYyzYQeVOPm.EbLnVyHL5T0h6.oYTGxnY+NsuJGUZe9f4+1zbTaRu8VYfb5rtLPu6mIvfnCkqoD0Qz31L8VZgK+ZtFJtqN3W8NuCAtdnPMB29466CBCl4L1al5QerD1WZZX3dIXfgYkCzMwvlYOtoQJCAieBiie8u+9oqEsDtsq4Z4fsqhTwRQiQhx16uO9ZmyYwD+hmHqbEKmgV+pIUAW76tOJ34iG1TV30.Ec1YmLdrHUzjL1Jphq+A9s3L5Z3BNoSF+zEP46gGxRx4tAtE7XJSbJbu+rajUs4Mws+qtKDgRRQDRgE9l1XaqXRwhx9GsRFqSTBJ3xW+bOeN73w3e9a+swxq.SNYETckUw15aM3aqGBJY.XaZRjHQXasuSNmy+bAeIGXGCv3ZXz333fqWVc+FLswKzGggI8qBIVfG6Z6amQWS87LOwSvu7QdTJXH43OtuDE+f0SKopmwDwfszotkhBaAkUDJyfRDDtgbDw8UoTXnf671tCpculF2xU9CvM2vibCaiUUCxhEYx60j3xe7Gm29w+SbqW7kvdWeiTgTQlt5lpLhSMN1jqqdHoRgQfMIFLGwMBw2vhy5Kehr2G2mm28l+05wctz12Qw.OBzXxQJotFZfJadTLzZ1.R+.hDIBEHCNHnXwh3jLFJojAGbPxIU366SrXwvzzbDGHgnHpsC4ymme4u7WRhQ0HVaZiLqwNlQD7WM88ahrDSSpHDkvjHllDu9F3.O3YQO6Xm7AwSnA2Vf2m7ZB7eg82zfWs6hZiaXHELUTvVRuE5kdVxaRustS16zCRKEpis6Gx.9tzdOcShHQoN7IzO.2hEHumO+IybLrmOCGIE8UbPbDJpQAS1UxmsljjHYLVb2cxqtf2f0eImGCtf4ybpMFclWw5yAqmDT.WTFgHMUHCfJT5YgXVFlrOohwV1wV4mckWEESmmf9yRpHIJwejZdQVJAeG3qbVmAGv4bQrqObUj9c2JCjOCqEvFISuPuLw3RbC8owhR1PzZYQdw3DUNXNpwxVJ1Oue59Hyu+FY1u6yRsqXSLNiZ3cyMHenm1gmmk.uRZBVBgIF9AbrDvLRIn67t7Nu0RP1XsjNiAVRMwc3EBtkFY67phDq5Zn4I0BgIRPzTUSzLcwrquRF+.CSxZafbREFUUM8K83UFrKJN5T70+WOSlhvfG99uKlR+9Lipahms60wp.DlIwuXVpCHdQOBMhRz5FMW34+Mns1akte1mhLQbITVDKjT.C7B00MvPp0jg9LfWrXZNDQELSyDTXmajy7m8K3ru7Km63J9drz49BbjwcHIv6Arq.eBEl3qLw2Lfn1VXTPWjQS.OgB+jQYxGv9SsMMVpOQCXLTFpF3n.Zopn7pc1CaMSuD4wdL1xaMelUz3DOWVd095g0G3QniMYyCRSGLEVXGzOMG3yoUUMjz1lS739Jrum64h6a71L+2ZgD0NFNnG5pJMAYXdRlJB2zO85XRG4QvMbrGGE2UWDw0kZA5.EwhZRfiOIijhe6u59opFZja7jOIJlMClVhRJetMQIJEEYwvVvcdS+JlwrmE2ykedjqsMQxBUiMkfweDIfKnfndfLvi3QrXsqdEb1m7oikLfQ2aGT2jmjljd9js1++R6u4HGJOYl1TBYddAbfG3r3G7u+WXCKYI7fesymrdtrgN5j1vG0fZFz0Ac9ptkdzk.Jpf7XPLqnfr.FJcsFZngFv0vlK96dE7bqbY7z+4+DGQk0RcMMZV2V1LCA3YpHLTqB0gALhmXcNeJrcLIe977tK3swOaAlYgbTekUi.C7QW.nXNQHa9g3g+c+a7pKcE7hu7yyINpZn6gGB.JhhUzS2bDSaxrqt6kS63+hzgQTpqlZYW8mC6PIUOwIy4cBGCOxb+yrz48gb5sLc5MeQ5L2PjqD0mpJS6RpRfTxT2E.CCCJjOKW809CoSjLipqCRUCR4GAPIGSGRFKNu6JWIm5oeJLXwP1VacxRTtDKUE3zXCzZgh3aZQGacqbYW6OjyepSfq3me8bMeyKk5LhPJoIsL4wyVFrW1ZlAI.v0ykJshhJnHECBwsPQFayilK7Rub15JWF+l48hDw1FKgktXhBC7T59iHLEPnDWolCIZu69XRMmjwW2XXmqeMrt2egrvk89zc2swzG2DXRitE1bOsSO9Zp52HRLHzkhEBHNlDft3pwbrQkMKm6YdV3YEkDYxxwVUBrEBrqtR5cvg3zOmuN0uO6K21O7ZgA5miY7SjczV6zUfGAXPZOeTBK7B7vFOT3iGPlbYIZs0wO+1uMZ5seK14bedZo4wR9L5chCAFNDLrcnneHO+K9BLwc0Nc2YWTqsAQhFGIY..CKaxWLGtVwYdyadDuppYvAGjlqHNtAgk5BjEoIOHhQ7jIvKviL4ynkFALQYHFg3YKqvaBkdgosoEYxjAgoAoRVIYGteLssnfe.N1lD3+o6TY92jym+iX4NoYThZ3vPCLDKe4KiE8gqfrxPJFMF8Jrncfshh0Cr1RO1HZNGXPEfsM1Dgv.eLTPbALsw1BCO7vzxAevbR+3qmq9J9NLdmDL1pZfsu8cRmEyx..4M8IvtD.dF4vxTKWYFgTvMO62LmFO0S9G4dt6amlquVbKjEggNbOEfewBDyv.ubCCV9DqRax6U.eUHAXRd6HzJv5yLLMjrNj8MLmvQbz7b+4+Li8Kcx7t8OLG14c9bw248x+zocQLylaA+DIXsYGfsqxwfBE9XfTVZlRBkTLPQAgdJGccKR80UK24seq7.2+8P7JbvNpIVF5tAEAvHThYnfJRlhYru6M0NglPVgIQNxCmAmxT3E6sGlzYb5bvm+EP+0TMU+Y9LrOmzIQSQpjO7kVHYl+pX+paLzZtg306eSLHPNSSLrsoPfWoc4TD0JBac8alK4LOat1evURvPtHbkkDtVsCNKDDfBWoDkvh.LvCC5vyk1FXHZtwFXky6k3qc7GCQGUEbQ+jqgdBjHLhSKNInIJEgPXIrcJfPSQIzOnvHLDm.ImzQcjbBetilZSDiZUFzbz3jHZL1Qu8x99YOR9xWzEwosOG.SstlY6COHKtPN5CCxHhfqQDj1QvwzVO4hkd+iVQRx46SOCMDqayaF2hgXYXRb6Xin+FJCAglwHaw.dxm9Y3Fuwaj02Z6jJVBRWH2HjA6v48wIQkLP5L7LO+yvS7u+DzdOcfiSL7P+4IsrwGHZxTzS+8w0cCWOm64ed75uyhwwIN9J4HHb0pztZVA5tlDQnIZmIMkowi9nOF20ceu3jLol6MDeLoC9SE6SbMGr.78JRTQR9f0tQtrK6xnut6gi1xlb9tTzwlrt9TzROd2lRMiCorsITBFTjb9gDyHBVxPRoLXTUljXwiyl2Qarfm6oIWUUh2V2JStlZwJdbZqsVoaY.4.P5OB1eMLL.gIAgZHoZXXfiuDiASini9veGcfHSFhjHEdpfQ3LPKCHlzfq6GdUD+3OVhzQGzyBW.QhDASu7jy2m9sfU2SuLgJZjoU2nYrUTISq4FYdipFVRlN3ddxmj9FZP1vB+.ZzLIcNT+rcuAPWOYEN5jo05vgRPfgVjWBIj3FPDkji5vmC3.y0wgbYGh7g5Es57VkXpfCaulIW987aXsKaw7Su8aia89+cLXu8yoeNeUN9S6Kwj2+ChWeAuFeu+k+YlTyMy.aYSLmwLdZNVEr4ctS1X9LzI59n6GZfxHPS5JRvHhVMuLBUD2IJ9NQwPpvTZfkoA1in5tBBEgnLzJGgPYhTB4vkkkoKh1mfoVaU3Elmq3e8ayAcLGK20x1Hs9dKlwWcCzUtsSGXiqTo0oNA3FpmfSO.+POhEwguy0dsvXGCW4I7EI852DioxZnKYQNhi+X40e8Wme2y8BTyhWIM1bc7dctY5GHMF3YYgikfBExisvDs51HvOTQwhdTQz3biW8UwgdwWDO7ocJrgMTlL9zsmzUpvRXQ0QSwsdMWAy4Kchbam1Yxvc1AFkpkfBHQzDfTwjGy33F+M+FhWYUbqmxYfcfhX1N3B3GTDKDTHaNpIUkb8+qeWF+L2adjezUhrmNIPEaDVYnrdeNhrHHCwRXP1r44Ul2qRgLCSw7EPlLIR4GA48Osr++EAyV1185OHALMUTH6vL68aFbdO3+Fye9ym4eS2HP.tJecAdJqW5kJHmLPQnRUpEYB7MgJkVLJ74yzvXn+vBrem3wRihHbG+paiYgM6+jlNKYGaiUIKfuoAxPIhRXGwPgd2AgAtkzufHRAsDoBFXG6f63rtHbK5yDrLvuBSjBIglfW.HcKPiBKVxu+wYe2Rq3u7UvXRjhtFrC.IwiFibpP5xUQac1FSpgQyBdtmgW+UdI1XUNbbmwWhkuf4ypesWiStgwSyIRxN6oK7njFVn.PgDeJp.Crw1vbDb5GWEhbvL7.Wv2jzp.prmAox5pjvnfWtx5Do.yvP72xNoqe2iyp+vkPx0rUV+y7Bzc+8Qzd5l+zcdSTW0UgbKqhwOTNpLeNZtwFYv.ed+dZkVyll9.Jh.CQDrDFXDlGGCCDRHLzGrfwOgwv269taFXyal63bNKTBIVkz8AMpKz2Hq0wx.Dl1njRLMhv.RWVYucxIXzHyHdk7320ukm7wmKu4qLOFioCGZMMQTfJvfLRKLs03LQIT3pzoZl1OOEjJtsewsv.Qiwh27VIgxgDlQo5oOdtvG3do8ksF95Wv2jSHV0zyPoYKYxSVC8.moj93VnHIiEm.I345izWRLLPHMo1nIouUsZ54klG45pCHedjnwkfteAPrPAtoKPjN5G0F2FQxmi3lFfxGWzQyEEfb9XFoHa+8VHgARnu9wLYB76ueZ.nG7nBrIpP.4yyzppJF63m.ixLBY7DnrsFI0QUYALY2VyEMZTV45VEuwO3ZPD3xrIjjNQIgkCNAk4DqOcr+aq3U6tUtfjkkCuVRTAsXaShJpjO2kdIzWGcxFe9Wf5qpVVWlbLPflomEk9HCKkkkdJ6z6RQfKQvkCNdczbEUPOFAby228xweBm.KcduFSMQULb5zr97ooGY.YKwAkkyWy.z6fUZ24XHnAmHzniI0VY03EBUkpRRUYb1dtLrph4X.fFTPUUTAMFKICzY27AqbEXXZhKR5LPRqddjWZhWX.wEPzhtL53IHZjnro1aki8x+Vb2+56lPuh7gu4BXeppdhpD35nHgi.6PORVRzbRgfDnYS55kPkDvLApNZbprppYfgRiaP.wRlfXUlh00eurIeIE.ZNVLFynFE4KTj0rxUytZqMRFIFKe4qjMswMPzXVLz.8R2c2NUmHJsTYcXXZw15uO1P+8wFy6VR8kfJrLoZojJTdTmvfpBkTGPKFJ1qXUPwAF.B7XKKeYz0xVBUXYQ17tnj9DG84RE.ojPLgh5jJpCIQTZwtKgBlpPQDiHL+szJ0L1wQj3wnuc0FSLUbBx4xFCKfuQL7B0YlaXYfoTqhY0WQRhXDg2YguGS9PODN9u3IwNW05.SnfkjFDRVy7WHo25VnlPCZsucPunHPAwURpDsz5YG3ORWULTFTABlPrDTU73r1MrAd223MISa6jpqsAxKLXGYFjdAFUhjLCm3jvvjEupUy67ZuFFoGlHIiSaExRWEzQcZZXywFOECkKOy+8eeV9BVDwKTjFZpQ1YgrrKWWMKUij8u1ZIlvf2YIKkEM2Wj917VYz0z.qSA8O7PTDMhaK6evBnImnzbzH33jjK+l+Ebf6+9QmKd9jv1gMLXV5W4Wp5Ge5XehRqPHzHyqP9.hVaCL+OXE7bG9Qyvc2Ce9PaLxIwpntX.RE3oJSpVFfRCWVGrIRnDKBXBQbXBMUK6p8cvZ7KxC9vOJiJVDpWnHzTPmtEXmAEQjHI94xVVtEQH2MkDRoQ4WQojs3lA+9Ff5iDEYPDnPZrM7oOUHCGpPHfcAPt7zatbjRnEbDynNjKLjNCBIjDnjRDDAKjHwG+PA05jfQgfUtvUw6O+kwJV6lI1nahdhZfmqGUEOIMlpBLqRoITUkBkgVV1EpPhD.NBHgqEcNbZVW1NnPrHjMsONQiP3v8SqEB.SaBBkrIY.jtWhhB+AGhphGmvhdXYIHT5qCaVnv0K.+PIEyNHoKDPegAjE826Isf3gvLSYyLriRMdRFHzBGSChnBnNSCZoXdRmKCq5AdPbCbYZFPsBHUhDredwzshLhMAhP7B7IHpAESmm3VNXaZPdYFrUgTosE856wIexmLe2G7AXQu3b4Gcw+STTDPN+BDknDHGIaaLvAC7YHJPOCUjYlpBNnQOQtjK37o4IOdl+S+mY6qXkbPFMyKdq+ZHeNN5FZfgJFx3i5PTq.JXXRXfAJeIUXEgdcKvZjJ52HDWLHsLjAhYSyoRPCUVAtE7H9nrw21lgxmdDU9JuxiVyOL6aCsPcAPw.ehDKE4jADJLKUeFHzRQO9gjptFYzDfPXRRohd8cofiM4QyYHoLLns7YYupqQhWTR9tGf5qqYxFHYP2hT.0HLjlRHHPnEjGeKE9BEidhikO6wdjLPGswxuGaTHQXBFe7Bs82c6uImC6NGRF.HrrofujwM5wyYbQWLqZIKA4K8JXJDXg9QHJLLfPkF5YlVVnB0LVjQnGo.lZ8UgupH6ygMKZnpp42b22CiIvmCdZ6E6HS+rwbCP.BFHWVM88IzbknkPORvkmo.SSaJJCncOOFxCLyW.KzTEd4.wxglzOGxWR1gGlNK8kQ.fSVMuVJQPAbHgYBJFVDvmnXSkUWECmNGGvLlEO052DmyIbh36Wj49mdBNzIOUt7y67X0qY0LtFajfgyQrxhOqiIlQMwHH.kWH1VQv1LAcmOOe.EnqLfCB7SqHp.xozp8koUT1kaN5aG6DGCHhDrG3ijSunvHP50GMDBBTBBvfhXgxvBTtjOPQ0.6U8MwzLMo3t5fBQRQbGKrDgjKSZ5yxGUpXDfAAl1jyxjrdEHmOjnxZv1PPN2hDwvfpqtZFr3PTYsUQDyXXX.NdlnLTzumf1JDv.q3CYLO7CyJem2j3FBJRHYTRxQQrHBABePYPPfVPdSiAcl2kCr5HjvMO+1e5Oi7IrXqC2CS7yLCZq01IYtBTskEcMbZxmvAy5qj5rrfnwwyKDG+PFkkMCF3wfCzE8kU6DsnD9fd5jNFZPr8JIRy3husICJLXP.oAzSdOVkw.rygG.WrvDaLM8Iixm1JgRRe.uB4XgAYHd1gzQnnQyECfOCVhjhBsLXf.IKtu9YGCzOVlIvxzgsM3.34UjNSEkzTpqTB.glc1CAjlBRTUErjktTtzuykRgA6mpJjiQ2X8j2u.e5N1UeBSq..GkhFRljZMfoOyYv4c6+bFWMUwpewWBamHrtrYXPU.dkbN3WRewUh.TVRDx.pFXV1VL85qkND44ptqaiS3B+lr92Z9zjmGwLLYk81M6PJofPfOBbhECeeeLTlZF4oLWFIzDspjRZkgA3pzE5JG5BwkEslYJkTZJAET.I4K8bYPmie.VnDZDBEkPpf.NfFaBDdT2mY5b0+4+.6ayihk9puJIJVjS6Kb7nLD7nu7Kv9bhed9129sxhZc6rYuB70t1qhb0WC+92dAbBW3Evb9JmFuzx9PpSXSqEyv5jdziI3oDDZ3PdCA4TRjXoibQDpY.InDmRpYAy9inHigtcvE.xaPoJkafNdLAJgARgj3JMjpmbplXfhtrWG1gSim1oxe7cdax2XcbR+qWJuaucxqrqcxbt3KldqNEO1JVAMdTeVl9I8k4O+geHqMvkC9bNaZUI4o+fkxj9BGCwl5z34W5Ghac0wgeNmEKumdXSE73W7D+6T6mYe3Z9g+PZe4Km8q1lHmPwFFJMoALMLnncHHjXJCPhDWSAgx.pvymI2TSrs0rZ9fOXE78+oWCWw87K4cW2pY9auUNfuxoyh5peVYO6fC7KchzkgMu1ZVKwl3DoxQOZ15JVG0TW8zdwbzcQOMMwqLHsPQmgAzEgzNArKjztLj9jg5PzsrwGI8KUrSTzFgzJ9rCUHcIf9UPfkEAXpYNcjrMoOamP1gJjcfjN.FVpSGzUZiqofdTR1oB8eaPQZKrH6j.51qXInRqqMqToGLs3FRZNYblP7TjsPdxTYBRmdPpMWZTnXaAtziu5SUGD+cY1JP3SLq3r52cg7.W52lsrwMfHaVBiFujpL+Q8q2FE9JktBhBINJs3ydfMLJLyTfc1Uu7Gen+HyXhKCUu8SxXIosA6mc4qyuJzTyZPdE8AkFC7Rkdwr.EpRbTopDuQHEPfI3J0yamRnywUnLvPYfqQo+3RSanlSCDXKMQfBovi3JEwQxd4TESopJo8N1AaaSqkVW7BYnksXldTGpaTSmG61tCFxykV21V3TO0SmIMtIhSz3LtoNc9R+yWLi+8VD26i8G33O8SioNlIwyOuWEu0rUJF5qCoU.4QSnIJgBDlXnjZ1UrzwlzPOLOJoolbWDRjkbBVFiGBz6JJPgooEtg9DItCFEbwQIQ5FRpTI4K90NW3j9h7PO4ehYbHyh4bw+yLjMrggFhy5J+gz4l2DO07eCNwy+avr+7eQdkEuTLiFiK7VtEVxbeZd+0tJ9dW+MPUiZr7Vu6R3.O5igS4GbkDq4Qwcbm2EIquNFe1LLZgASs5FnRmXrzd1EooDNWj9595KXjcN8MMX3vP1VgbDuycwTGy3IZ+wX3M0Jq3EeUV252Hm74dtbY23si8sbartk+xbo268wxegWmEs5MxU8StAl43mL+jS5qPPfGQLMIk.5UJwW.G6IdbL6C4vXv9Syi+X+I5cftXTM0L1lVLTasgEBZbzily9rOChGOAV1IX0qai7Wl6egPOWR5DE2hAnPxTl3znst5fB4GlH1BN4S9KQyiZLzPcMSX9Pd4W4UYQqZEzxjGKG9QevXZHn1j0PlARyV1vFoXdWNsC4fv20Cu74vwIJ1wSwRV37o00rB7x4R9Ayx9O0Yvk+P+d5r8syscxeYbbbvKH7iSu0eJX+ME4.vGqfjiKkE6sQLhLPV19pWOA6pGlbpJgnQYUCO.CnGHUDFZpHS.5wzSASRA6Sp5XebRfUF8Luu8ObCr42dgjTHHqkIKs2NY6.4M0Srlox.oToAQRYNRS7QNFPOneXpDXoDfxjPgMJg.UIX6pTkzQCKM0pIJA9DJAgWoPyXURKEQDJlBlLqZqmIqDH6uO5r2AYQu1qSvp1.iuppwRFfUQOZJvlIKhS90sc9vm8kYmK9CHr6dI8V1Lu1e4IYnsrCxt4sPqKZgrtEs.lTzpnqLCSaJexWpIPZGpZGnJkbD.WKETFmsPouGCCUHJceR4aTJ6jPgPC1JPG9dnjp.lZpjDKaF71dqrxUrB1v69tLbqshYmcx69bOO8u4sPj9GfU9FuMaZoqfJc8HypVGKbtuHze+TegBrzWYdrqUrRh6kiAVy5Xku0BHemcSUtE4YerGkss9Mxle64yFetWfZRmiVZpAZe3gYCCkitHjh1l3G0B7jXHKwGiXhA1Dpfr3S5hdXof5bRvfqea7AO+KSuaZKzfSLh6Fv7dlmi9141IYZW9f2Zgr8kuJl0jmDwGneVw7dILHjNcyvNJFhcLK9429swE9MNeFWKsvz26oxe3QdXZrgwv8bO2GwhGiE8dKhPUHidLsv89atON74bjr7UrFN8S6Loo5ajkujkQnuDUP.e8u54v26J9t7ruvKhPXhmqKWv4ddbC23snKdqkCW12+JXcstIRWHG+a2+8yoexmNC18.bZmxYfsSTZpwl3h9VWDScpSk+kK8xnoQ0By9PmM0WYU7pu7KyjSTE6Uhpws+zjr15YyK+CnmktbprhpXMCOH8FxGMt8eJX+M66QHzE9qhvP9LUGgiJdiLpHonGuhXX4PRjzZ1L7p82EsgDWk14.RCjXRnHDoPxdIgCarSl81vgfrYwshJonRQEFvv9EYw80EqNeV52D7LAKO8L.TLrzT8YU9LPpc3.ifxLSLvpT2Q7MLJsnRig+xyBmxR+5LjpxTKfd2Wg.kgBhBIJBe1TUvQzzXngb4QFFP5JhSmYyvXkQIqxmk0YaX.LoTMSbiHDuhJwUF.QcHmrHCKKpEjRUH9tEQDFPkISQixT7AcrcVPwrzSoBrJ+ObEQetnOtBKEqmHPOZwZtQZjS6QrxE90DSLsMwMrHUZASvCN1oL6ZvOjC..NLQRDEDUYlfsCC0V6rinInlJqhrExhoPKFKISljb4JfuuOwimD2BEgPMwuZXaQ1rYIP5Ss0VMCmcHjRAllwv00GgoB63QIT.19ALgnIQoTr195l0Nz.zNNzGRBiaQfeQL8sQ2l2.s6AyH5P9HjJAZjPllSML9JpjZRFCi3Frq96CWm3jyOjHxBHBTXKswTIQIJRRaCbxmmFmzDYdacyrohdbte2qfa3luEtwq65Xl629xquv4y88.O.+zq+V3G8itJdjG+w3xtrKiLYGlwO9wxK87u.oRUIG4Q743ZtlqioO8oyIbBGO4xjkQ2XCrf4+1L5lajS7zNadiW60vP4wO5ptJtga5V36cEWIO5S9m3MWv6PlBo469cubdn+sGjZSTEG5rOLNxi3Hnt5pAKKKRmcPrrb3W8q9Ubq25swZW6ZYZiaLb6+reF6epZ3KM5ISaaZqLXxXjO2vLq5qAWGCdpNZk1TJ56SQPR9IJsBkRgxA13Pt3ktChpLPlLBgggjLvhgccYHLvGcwlTJSLvTC0YglW.xiGqnuNYKdAjHRTRmY.jJEUDyf9xjgtKoehFnY4ZPeuiRH.jDInzhlREwYjisO1CEHzOaYpxOTnGZXQfMZn7TdB2zCGkFJqAPQEggP2t9r3d5FS2rDDDfJSbBLLnUSnsA5kgrMIieHqISOX.jvaPrEFDSXPDSCLrg3wiR5zCQU0VE4KFR2t4Xq4bos.ecwqTkWfauaNvB3iYkNIMJcoKf3knNE+R3BsjCNC8RNIR84ho.OkfNQx62WOzloMIiXSAAjK8PkRGQ6Ro+AGFkBbrrI8fYvwIJBKCR66SXQsFVXFMBsmNCfIBSCBjgX4XgkvfgGHCUWW0LfWNxVr.ckYX1omGcCZp3GAxRrFsFT8Z.UoDJD3ivPS+v4vfNjB52aHVSeoowzQnFyPFUc0gsPxnpJEUTLBFREVgFjLdTx4OLBKEgUjf1xkizhnP7jbNeiKg110v79KZ0XaVAye9KlnIqhYr2Slbt43PNhYSCioAxrtgzvVWpnp3I4RujKliXNGBy8EddBTdHM7YZ6+dQhZRfQLal0Ase7Zu5Khv.bhGAB7n9Zqh7YGlN20NY+NvYvXarNDEcQEwGaaal6y+7LpQUKgg9zUWcwY+UOWBkPQWed0W+UXCMzH.jILfdkADuwFwIpC1Mz.RBHqzEezZ8wml1m3ZNjSu9gfPcOtcSqCzoL3N8wTW4a.MwZowHpBEnjzGP1B4zxfVfVnV0ntDLMzEHTJffvRDMBVZgIUnoYLS0GQJnhReF6tENxNq5+qX2d9x0Ao7uo7L7CFHTgHTFXZXBFAzVgBzQgBXhFKcgtoQ.TjgHnz2CgFvfxPRFMFasvv3fF9yoJA2XU+5eN6vYFA4iNXnQE3tePqBKM5tkOeJ63yfxYNUNZAIZbcTNxBJ8uJotTJJzLmjkoE9AAjAXKYxPqkzKjHTBxvk9duHejNYjrTcbJ2+cmR+sg6102xyiP4imxeu5MbuDozyU.HigfLnv.AFVlDFT.KKCTXfBIFkuXHCQJAoPRQgIdBAVJKFlPR6UfJHjs1VaXCjTXRJUHVHvAaJfWIxtuD7lAZG3.NpSjlG6jn81am0twMvBV36PdgOSdelF4ROLO+y7zbZm8WkC9fOX15l2LBgol0t8kjJUJ7CJvgeXGJM0bCrictSN1i633wd7+Dm4oeFbnG5rIQhXjKeAM9cDBFn+dIZznzPc0RggFBSBHlsElXRKsLF13l2DCLT2DIhf.Ocg58BTTUM0ROc1E82YWjzwltcyyqs40PJk9paDCKxIyhRDgzPIxd4+g0JS3iPLYfBDBaFREhoofhggXapItBarwu7Tmapa1lRJwPIQnTnT5KhtJsxKag.SYvGSrTEVZn8FBfxrzgbIpzPPIJ1pzD.qLPGaBTdAUfgjQVQAnDgHUhcaQVHJBYDgMyPGJhRDfgDrTNHkRxiTSFHktdTlNwJhdVpjnqGhDHcwBXYIPpT3ofdkpQzvfbTtaCBLsixf9EvTHPHLvTJKEUjNUGYIFdTG8iFpWlkVFFJBzBXiH.jeTpHpRtTDTp1CV5tsnBBFgB6GNPUBciezhbagFGJB.CKMxQMQyNSVXRw+CHwq7UgxVYLyZXKv0WGyiV13DTDE4klfkMggdPfG1BPEHIrThb1gkO9E5yXQowV1TqXTJrvSFpKfrT+d6oBIp9tJLJQutZ4rq7wjfBXCwhhT3QnnH9l4ImLOVNvgb.6CctkVYoe3GxW8r+ZbzGxQxS7fONQDwQXDEogM2y8duL249r7TO0yvs7StQtpq9ZooZZhe2C8PrWSe+XVy9PXLia7roMsIjJSvzlVFyD3rNquJierikG6QdP13Z1.AdgDq1jbK27swwdhGGgAoIHr.ARklzXbDjOcNr.bLEjMzmzRMecVgsA19Z8BQ.jS4hGFHshBAE3SK6uCDLqMRCSBjBPFfHp.OOEVVVno9OUoQ2ub09z2LTN79x3NPYZQfTO0lZ.l3nIJUQoK01VPfEHMPHLPIzQYDNBE7pKkuV4rEk+M7QUXjx+DpRE36ihgPWw+QppmHbjB9ED5ST6nTvOqNxhRbYltgKBBJAHdgR6PzxDBCKUPy.84mSoEhZMnv.eLHzvDUPoIyTIQH0zOFBvrjSlQpgBnKXip7YVo6RJWbxxmeJAHJwL.kdoAgAfvnTyMAKgEETA5Y9vR6b2zTPNeEFV6V8Nr0WpbkVkHb.saJSC8HtqB096CCsw1PhsQHEC0KT02UYPw.MGeafIJSKHzGDgZmogkHBEgXjKQBzudAF58AnDWOXBnTDZ4vPdZGK4Jcblsz0Terv1wA+f7PoWBRM9Z11NZkL4xPhTQoglqgt6saDFvg+YmMe3arT5u6doictKl0AbHLtwLdjAPtBEoJohHQhwl1zlHyPCyTmvTXl60LHpSLZem6hN5nSNlO2Qvw94+Brg0uQ7CzEY+K+k+xDqxJXtO2KvM7itNps5ZHlSLxmo.2xs9KX1y9P4.Nnowu31tELM05zAnmEnXV1TLvGbDHMU3YC84JIgEDFTJxsRY8R3+CbpLKaZBBMfPoqNWQTfKHTZ5sRu6l9NWQX.hP8hNcqGKehpCESD3gP5iuPfqPPXnOBYHiHl.dAfrHPNTpb55OpG5fROz0HHf.boDiCgbjfLFI2iQ1gsb569ZGFpROeHPn9hbHPnHjbA4PpQnBBeABkf.D3I.gTfPJ.k.oPfmTqf39A5eVJDTDwHmWEEJBEgfxCAdk7j7QUWPoJ8wWp9CkCiWKfE9DTpyOHoDRbz+QJYoqGReP5Q.5GBTHTRBEBJHDLLg3Iz8FPDJPIED3qcnpB0mKhPAh.c0QCUADRfdNPBkDn44V8wVHfH.ekj7g5AISDT50Gp4ERe7wkhPXVPo4YeYXYbZ.nJBDfG5n.CPG4jHnz6kr76oDguOTBmK9B8iOJkr.B7KfPIJITOFnLzWe6niswBdyWiIL5wvQMmiCY.zxnlHSaJG.S+PlMm3Yd5z6fCvduOSi5ZnZBT4IUEN34migGdXptlFHYUUSqczNSee1aFUKMxE7OctjJYDLEFLmC+vPfBGa8fz8xuw7nmtam3whvvY8A6DjMzCOiBrzk9VbbetCioOooAdFDF.0UWCXnTfvkzA9XDMJg9fkzBQd82m4CKstn78gkpOyml1eWnl9+2r8ekTi8elVh9e2W+m11mzi++eUq74sggACMzPbm24cxTlxT3htnKhkrjkv9rO6Cs2d6bS2zMgRovzzj8a+1ON0S8T4oe5mlHQhPxjI4rNqyh4Lm4Pas0FO4S9jbtm64x8bO2CKbgKjINwIxblyb3POzCkC9fO3QjwuctycxJW4J4m+y+4bbG2wwl1zln1ZqEkRwkbIWByblyDkRoYUpBEHYxjDFFhkUI8AoXwQTt9+QZ+Miyg+6Z+u0a91i8+bsc+dNSSSTJEc0UWrzktTZrwFYNyYNjMaVd1m8YYcqacjOedFZng3cdm2g0st0wvCOLKZQKhst0sxTm5TYwKdwb8W+0yN24NIHHf24cdGZu81Ie97zQGcv6+9uOoSml96ueV25VGqe8qmW9keYZpol3q+0+5jKWNV+5WOKXAKfZpoF5ryNYwKdwrwMtQTJE0We8ze+8yxV1xXqacq34oKp++n2X4SYLVsGaO1+XMiRy0hggwH++iabiizoSS2c2M115Rx566SznQ07BoiyHKP2cy11VqPXRIFF5oJd22g2vv3i8bUWc0bJmxofTJYgKbgr0stUjRIVVkZCcPvH+skUr6xGiJkZONG1isG6Say11VShvnijvzzDOOORjHA4ym+isHrbjFkWjaaqYRphEKNBv+LLL9XuekSIHLLDGGc2sBCCGY.EiFMJddZV81yyajOefQbVT9yyxxBOOuQ94xNM9GgsGmC6w9e8V4ciKGQfTJIVrXTnPAbbbHHH.aaabccGYwdYGJkWfZZpaeR4E1111kTT6fRclKPip1RNZhEKFgggi77.+eDMRjHQv22GGGGBCC++vgy+ns83bXO1+q118nFJuf1zzDWW2Q1w9+rcmKuSejHQ9XKds1Mc9nriixNX788GIcix09nrCEKKqQRCorSjxe16tikxysz+nSsXONG1i8+5sxKTCCCGYW4cOj8xKD28cr+OFAQ4eW4TNJ+7keske+9O6m2cyrjf.U118Nqr60d3ejoT.6w4vdr8X6w9Ow9zVWL1isGaO1+OpsGmC6w1isG6upsGmC6w1isG6upsGmC6w1isG6upsGmC6w1isG6upsGmC6w1isG6upsGmC6w1isG6up8+GfDRAO9jT2bvA....PRE4DQtJDXBB"
          ],
          "embed": 1,
          "id": "paradis-logo",
          "maxclass": "fpic",
          "numinlets": 1,
          "numoutlets": 1,
          "outlettype": [
            "jit_matrix"
          ],
          "patching_rect": [
            1075.0,
            115.0,
            263.0,
            80.0
          ],
          "pic": "paradis-latin-logo.jpg",
          "presentation": 1,
          "presentation_rect": [
            29.0,
            29.0,
            263.0,
            80.0
          ]
        }
      },
      {
        "box": {
          "fontface": 1,
          "fontsize": 16.0,
          "id": "presentation-title",
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            1075.0,
            215.0,
            300.0,
            24.0
          ],
          "presentation": 1,
          "presentation_rect": [
            313.0,
            41.0,
            280.0,
            24.0
          ],
          "text": "XFADER OSC BRIDGE"
        }
      },
      {
        "box": {
          "fontsize": 12.0,
          "id": "presentation-status",
          "linecount": 2,
          "maxclass": "comment",
          "numinlets": 1,
          "numoutlets": 0,
          "patching_rect": [
            1075.0,
            250.0,
            188.0,
            33.0
          ],
          "presentation": 1,
          "presentation_linecount": 2,
          "presentation_rect": [
            313.0,
            73.0,
            188.0,
            33.0
          ],
          "text": "MASTER · UDP 9001\nA / CENTRE / B + slider continu"
        }
      }
    ],
    "lines": [
      {
        "patchline": {
          "destination": [
            "lp",
            0
          ],
          "source": [
            "bang",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "pval",
            0
          ],
          "order": 0,
          "source": [
            "clip",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "set_value",
            0
          ],
          "order": 2,
          "source": [
            "clip",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "sig",
            0
          ],
          "order": 1,
          "source": [
            "clip",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "delay",
            0
          ],
          "source": [
            "defer",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "lp",
            0
          ],
          "source": [
            "delay",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "defer",
            0
          ],
          "source": [
            "lb",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "printid",
            0
          ],
          "order": 0,
          "source": [
            "lp",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "remote",
            1
          ],
          "order": 1,
          "source": [
            "lp",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "clip",
            0
          ],
          "source": [
            "ma",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "clip",
            0
          ],
          "source": [
            "mb",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "clip",
            0
          ],
          "source": [
            "mc",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "plugout",
            1
          ],
          "source": [
            "plug",
            1
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "plugout",
            0
          ],
          "source": [
            "plug",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "clip",
            0
          ],
          "source": [
            "route",
            3
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "ua",
            0
          ],
          "source": [
            "route",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "ub",
            0
          ],
          "source": [
            "route",
            2
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "uc",
            0
          ],
          "source": [
            "route",
            1
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "remote",
            0
          ],
          "source": [
            "set_value",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "clip",
            0
          ],
          "source": [
            "ua",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "clip",
            0
          ],
          "source": [
            "ub",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "clip",
            0
          ],
          "source": [
            "uc",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "printudp",
            0
          ],
          "order": 1,
          "source": [
            "udp",
            0
          ]
        }
      },
      {
        "patchline": {
          "destination": [
            "route",
            0
          ],
          "order": 0,
          "source": [
            "udp",
            0
          ]
        }
      }
    ],
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
      "amxdtype": 1633771873,
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
    "oscreceiveudpport": 0
  }
}
