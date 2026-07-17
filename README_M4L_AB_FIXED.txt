VERSION PRO V12 — Interface originale conservée, A/B corrigé via Max for Live OSC

Cette version reprend ton interface Pro V12 et remplace seulement le moteur A/B.
Le crossfader n'utilise plus MIDI/IAC/RTP. Il envoie:
- /xfader/a
- /xfader/center
- /xfader/b
vers Max for Live sur 127.0.0.1:9001.

Installation:
1. Dans Ableton, place un Max Audio Effect sur MASTER.
2. Ouvre/copier M4L/XFADER_OSC_BRIDGE_v8_OSC_REMOTE_STORE_ID.maxpat.
3. Vérifie que les boutons manuels -1 / 0 / 1 bougent le crossfader.
4. Lance l'app comme avant.
5. Page A/B: le look original est conservé, mais A/B passe par Max for Live OSC.

Si macOS bloque un .command:
chmod +x *.command
xattr -dr com.apple.quarantine .


MISE À JOUR v3 SLIDER:
- Les boutons A/B/Centre envoient toujours /xfader/a, /xfader/b, /xfader/center.
- Le slider envoie maintenant /xfader/value <float>.
- Le patch Max route maintenant:
  route /xfader/a /xfader/center /xfader/b /xfader/value
