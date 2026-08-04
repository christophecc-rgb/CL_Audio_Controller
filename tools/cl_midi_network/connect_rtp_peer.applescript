property peerName : "__CL_PEER__"
	if peerName is "" then error "Correspondant RTP vide"

	tell application "Audio MIDI Setup" to activate
	delay 0.4

	tell application "System Events"
		tell process "Audio MIDI Setup"
			-- `activate` ne réaffiche pas toujours une application précédemment
			-- cachée par le connecteur. Les clics AX ne réveillent alors pas le
			-- bouton de connexion, même si la ligne paraît sélectionnée.
			set visible to true
			set frontmost to true
			delay 0.8
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
				-- Après une ouverture de session, Audio MIDI Setup peut mettre plus de
				-- cinq secondes à restaurer le Studio MIDI sur les Mac les plus anciens.
				repeat 60 times
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
			try
				perform action "AXRaise" of networkWindow
			end try
			set frontmost to true
			try
				set windowPosition to position of networkWindow
				click at {(item 1 of windowPosition) + 220, (item 2 of windowPosition) + 22}
			end try
			delay 0.5
			-- Le clic qui rend la fenêtre principale peut amener macOS 26 à remplacer
			-- son objet d’accessibilité. Toujours récupérer une référence fraîche.
			set networkWindow to missing value
			repeat with candidateWindow in windows
				set windowName to name of candidateWindow as text
				if windowName contains "réseau MIDI" or windowName contains "MIDI Network" then
					set networkWindow to candidateWindow
					exit repeat
				end if
			end repeat
			if networkWindow is missing value then error "Fenêtre Réglages de réseau MIDI perdue"

			tell networkWindow
				set directoryGroup to group 2 of group 1 of splitter group 1 of group 1
				set directoryOutline to outline 1 of scroll area 1 of directoryGroup
				set participantOutline to outline 1 of scroll area 1 of group 2 of group 1 of group 2 of splitter group 1 of group 1
				repeat with participantRow in rows of participantOutline
					set participantContainer to group 1 of UI element 1 of participantRow
					if exists static text peerName of participantContainer then
						try
							set visible of process "Audio MIDI Setup" to false
						end try
						return "already-connected:" & peerName
					end if
				end repeat
				set matchingRows to {}
				repeat with candidateRow in rows of directoryOutline
					set rowContainer to group 1 of UI element 1 of candidateRow
					if exists static text peerName of rowContainer then set end of matchingRows to candidateRow
				end repeat
				if (count of matchingRows) is 0 then error "Correspondant RTP introuvable: " & peerName
				if (count of matchingRows) is greater than 1 then error "Correspondant RTP ambigu: " & peerName

				-- Depuis macOS 26, un simple AXSelect ou un clic unique laisse parfois
				-- le bouton « Se connecter » désactivé. Deux clics réveillent la ligne
				-- comme le double-clic effectué par l'utilisateur.
				set matchingRow to item 1 of matchingRows
				set rowPosition to position of matchingRow
				set rowSize to size of matchingRow
				set clickPoint to {(item 1 of rowPosition) + ((item 1 of rowSize) div 2), (item 2 of rowPosition) + ((item 2 of rowSize) div 2)}
				try
					set focused of directoryOutline to true
					-- Home force AppKit à produire une vraie sélection clavier dans la liste.
					key code 115
					delay 0.25
				end try
				repeat 10 times
					try
						set selected of matchingRow to true
					end try
					try
						perform action "AXPress" of matchingRow
					end try
					-- Un clic aux coordonnées de la ligne reproduit le clic physique que
					-- macOS 26 exige ici; AXPress/AXSelect seuls ne suffisent pas toujours.
					click at clickPoint
					delay 0.12
					click at clickPoint
					delay 0.5
					if enabled of button 1 of directoryGroup then exit repeat
				end repeat
				set connectButton to button 1 of directoryGroup
				if enabled of connectButton is false then error "Connexion RTP indisponible pour: " & peerName & " CL_CLICK:" & (item 1 of clickPoint) & "," & (item 2 of clickPoint)
				click connectButton
				repeat 20 times
					delay 0.25
					repeat with participantRow in rows of participantOutline
						set participantContainer to group 1 of UI element 1 of participantRow
						if exists static text peerName of participantContainer then
							try
								set visible of process "Audio MIDI Setup" to false
							end try
							return "connected:" & peerName
						end if
					end repeat
				end repeat
				error "Timeout de connexion RTP vers " & peerName
			end tell
		end tell
	end tell
