import unittest

from showcue_pdf_import import parse_pdf_text


class ShowCuePdfImportTests(unittest.TestCase):

    def test_mpc_style_document(self):
        document = parse_pdf_text(
            """
            N° TABLEAUX TITRES MICROS NOTES

            PRÉPARER LES MICROS / LES P° EARS / LES MIX POUR LE CAST

            1 SCÈNE DE COMÉDIE : Intro

            2 WELCOME IN CABARET
            La Petite Sirène - Pauvres âmes infortunées
            Lady Gaga - Bad Romance
            SCÈNE DE COMÉDIE dans le tableau
            Lady Gaga - Bad Romance Reprise

            10 L’ENVOL
            AIDER ROXY AU CHANGEMENT DE COSTUME À COUR

            16 SCÈNE DE COMÉDIE : Roxy / Léo
            TOPER l’entrée de ROXY à COUR après qu’elle a mis sa cape
            """
        )

        cues = document["cues"]

        self.assertTrue(cues)
        self.assertTrue(
            all(cue["timecode"] == "" for cue in cues)
        )

        texts = [
            cue["text"]
            for cue in cues
        ]

        self.assertIn(
            "Lady Gaga - Bad Romance",
            texts,
        )

        self.assertIn(
            "TOPER l’entrée de ROXY à COUR après qu’elle a mis sa cape",
            texts,
        )

        top = next(
            cue
            for cue in cues
            if cue["text"].startswith("TOPER ")
        )

        self.assertEqual(
            top["type"],
            "ENTRÉE ARTISTE",
        )


if __name__ == "__main__":
    unittest.main()
