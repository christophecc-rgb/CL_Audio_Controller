tell application "Audio MIDI Setup" to activate
delay 0.3

tell application "System Events"
	tell process "Audio MIDI Setup"
		set frontmost to true
		repeat with candidateWindow in windows
			set windowName to name of candidateWindow as text
			if windowName contains "réseau MIDI" or windowName contains "MIDI Network" then
				perform action "AXRaise" of candidateWindow
				return "raised"
			end if
		end repeat

		set studioWindow to missing value
		repeat 20 times
			repeat with candidateWindow in windows
				set windowName to name of candidateWindow as text
				if windowName contains "Studio MIDI" or windowName contains "MIDI Studio" then
					set studioWindow to candidateWindow
					exit repeat
				end if
			end repeat
			if studioWindow is not missing value then exit repeat
			delay 0.25
		end repeat
		if studioWindow is missing value then
			if exists menu item "Afficher le studio MIDI" of menu 1 of menu bar item "Fenêtre" of menu bar 1 then
				click menu item "Afficher le studio MIDI" of menu 1 of menu bar item "Fenêtre" of menu bar 1
			else if exists menu item "Show MIDI Studio" of menu 1 of menu bar item "Window" of menu bar 1 then
				click menu item "Show MIDI Studio" of menu 1 of menu bar item "Window" of menu bar 1
			end if
			delay 0.75
			repeat with candidateWindow in windows
				set windowName to name of candidateWindow as text
				if windowName contains "Studio MIDI" or windowName contains "MIDI Studio" then
					set studioWindow to candidateWindow
					exit repeat
				end if
			end repeat
		end if
		if studioWindow is missing value then error "Studio MIDI introuvable"

		set networkButton to checkbox 2 of group 1 of group 4 of toolbar 1 of studioWindow
		set networkButtonHelp to help of networkButton as text
		if networkButtonHelp does not contain "réseau" and networkButtonHelp does not contain "Network" then error "Bouton Réseau MIDI introuvable"
		click networkButton

		repeat 20 times
			delay 0.25
			repeat with candidateWindow in windows
				set windowName to name of candidateWindow as text
				if windowName contains "réseau MIDI" or windowName contains "MIDI Network" then
					perform action "AXRaise" of candidateWindow
					return "opened"
				end if
			end repeat
		end repeat
		error "Fenêtre Réglages de réseau MIDI introuvable"
	end tell
end tell
