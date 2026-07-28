property peerName : "__CL_PEER__"
	if peerName is "" then error "Correspondant RTP vide"

	tell application "Audio MIDI Setup" to activate
	delay 0.4

	tell application "System Events"
		tell process "Audio MIDI Setup"
			set frontmost to true
			set networkWindow to missing value
			repeat with candidateWindow in windows
				set windowName to name of candidateWindow as text
				if windowName contains "réseau MIDI" or windowName contains "MIDI Network" then
					set networkWindow to candidateWindow
					exit repeat
				end if
			end repeat

			if networkWindow is missing value then
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
				delay 0.6
				repeat with candidateWindow in windows
					set windowName to name of candidateWindow as text
					if windowName contains "réseau MIDI" or windowName contains "MIDI Network" then
						set networkWindow to candidateWindow
						exit repeat
					end if
				end repeat
			end if
			if networkWindow is missing value then error "Fenêtre Réglages de réseau MIDI introuvable"

			tell networkWindow
				set directoryGroup to group 2 of group 1 of splitter group 1 of group 1
				set directoryOutline to outline 1 of scroll area 1 of directoryGroup
				set participantOutline to outline 1 of scroll area 1 of group 2 of group 1 of group 2 of splitter group 1 of group 1
				repeat with participantRow in rows of participantOutline
					set participantContainer to group 1 of UI element 1 of participantRow
					if exists static text peerName of participantContainer then return "already-connected:" & peerName
				end repeat
				set matchingRows to {}
				repeat with candidateRow in rows of directoryOutline
					set rowContainer to group 1 of UI element 1 of candidateRow
					if exists static text peerName of rowContainer then set end of matchingRows to candidateRow
				end repeat
				if (count of matchingRows) is 0 then error "Correspondant RTP introuvable: " & peerName
				if (count of matchingRows) is greater than 1 then error "Correspondant RTP ambigu: " & peerName

				select item 1 of matchingRows
				delay 0.25
				set connectButton to button 1 of directoryGroup
				if enabled of connectButton is false then error "Connexion RTP indisponible pour: " & peerName
				click connectButton
				repeat 20 times
					delay 0.25
					repeat with participantRow in rows of participantOutline
						set participantContainer to group 1 of UI element 1 of participantRow
						if exists static text peerName of participantContainer then return "connected:" & peerName
					end repeat
				end repeat
				error "Timeout de connexion RTP vers " & peerName
			end tell
		end tell
	end tell
