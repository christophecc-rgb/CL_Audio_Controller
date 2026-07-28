tell application "Audio MIDI Setup" to activate
delay 0.3

tell application "System Events"
	tell process "Audio MIDI Setup"
		set frontmost to true
		repeat with candidateWindow in windows
			set windowName to name of candidateWindow as text
			set isNetworkWindow to false
			if windowName contains "réseau MIDI" or windowName contains "MIDI Network" then set isNetworkWindow to true
			try
				if exists static text "Sessions et répertoires" of candidateWindow then set isNetworkWindow to true
			end try
			if isNetworkWindow then
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

		set networkButton to missing value
		set toolbarElements to entire contents of toolbar 1 of studioWindow
		repeat with candidateElement in toolbarElements
			try
				set elementText to ""
				try
					set elementText to elementText & " " & (name of candidateElement as text)
				end try
				try
					set elementText to elementText & " " & (description of candidateElement as text)
				end try
				try
					set elementText to elementText & " " & (help of candidateElement as text)
				end try
				if elementText contains "réseau MIDI" or elementText contains "Réseau MIDI" or elementText contains "MIDI Network" then
					set networkButton to candidateElement
					exit repeat
				end if
			end try
		end repeat
		if networkButton is missing value then
			try
				set networkButton to checkbox 2 of group 1 of group 4 of toolbar 1 of studioWindow
			end try
		end if
		if networkButton is missing value then error "Bouton globe Réseau MIDI introuvable"
		try
			click networkButton
		on error
			perform action "AXPress" of networkButton
		end try

		repeat 20 times
			delay 0.25
			repeat with candidateWindow in windows
				set windowName to name of candidateWindow as text
				set isNetworkWindow to false
				if windowName contains "réseau MIDI" or windowName contains "MIDI Network" then set isNetworkWindow to true
				try
					if exists static text "Sessions et répertoires" of candidateWindow then set isNetworkWindow to true
				end try
				if isNetworkWindow then
					perform action "AXRaise" of candidateWindow
					return "opened"
				end if
			end repeat
		end repeat
		error "Fenêtre Réglages de réseau MIDI introuvable"
	end tell
end tell
