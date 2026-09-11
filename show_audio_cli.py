"""CLI de diagnostic local pour CL Show Audio Builder."""

from __future__ import annotations

import argparse
from pathlib import Path

from show_audio_builder import (
    audio_filename_for_variant,
    load_show_audio_document,
    validate_show_audio_document,
    variant_display_name,
)


def main():
    parser = argparse.ArgumentParser(
        description="Inspecte un document CL Show Audio Builder."
    )
    parser.add_argument(
        "document",
        nargs="?",
        default="show_audio.json",
    )

    args = parser.parse_args()

    path = Path(args.document)
    document = load_show_audio_document(path)
    validation = validate_show_audio_document(document)

    print(f"Document : {path}")
    print(f"Révision : {document['revision']}")
    print(f"Variantes : {len(document['variants'])}")
    print(f"Prêt : {'OUI' if validation['ready'] else 'NON'}")
    print()

    for index, variant in enumerate(
        document["variants"],
        1,
    ):
        print(
            f"{index:03d} | "
            f"{variant_display_name(variant)}"
        )
        print(
            f"      scène={variant['scene_index']} "
            f"name={variant['scene_name'] or '-'}"
        )
        print(
            f"      playback={variant['playback'] or '-'}"
        )
        print(
            f"      export={variant['export']} "
            f"→ {audio_filename_for_variant(variant)}"
        )

    if not validation["ready"]:
        print()
        print("ERREURS / INCOMPLETS")

        for item in validation["incomplete_variants"]:
            print(
                f"- {item['id']} : "
                + ", ".join(item["missing"])
            )

        for item in validation["duplicate_ids"]:
            print(f"- ID dupliqué : {item}")

        for item in validation["duplicate_assignments"]:
            print(
                f"- affectation dupliquée : {item}"
            )


if __name__ == "__main__":
    main()
