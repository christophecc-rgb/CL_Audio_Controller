on run argv
	if (count of argv) < 2 then error "Usage: osascript reconnect_legacy_rtp.applescript PEER_NAME CONNECTED_NAME"
	set peerName to item 1 of argv
	set connectedName to item 2 of argv
	if peerName is "" then error "Correspondant RTP vide"

	tell application "Audio MIDI Setup" to activate
	delay 0.4

	tell application "System Events"
		set midiProcesses to every process whose bundle identifier is "com.apple.audio.AudioMIDISetup"
		if (count of midiProcesses) is 0 then error "Processus Configuration audio et MIDI introuvable"
		tell item 1 of midiProcesses
			set frontmost to true
			set networkWindow to missing value
			repeat with candidateWindow in windows
				set windowName to name of candidateWindow as text
				if windowName contains "réseau MIDI" or windowName contains "MIDI Network" then
					set networkWindow to candidateWindow
					exit repeat
				end if
			end repeat
			if networkWindow is missing value then error "Fenêtre Réglages de réseau MIDI introuvable"

			tell networkWindow
				set directoryGroup to group 2 of group 1 of splitter group 1 of group 1
				set directoryOutline to outline 1 of scroll area 1 of directoryGroup
				set participantOutline to outline 1 of scroll area 1 of group 2 of group 1 of group 2 of splitter group 1 of group 1
				repeat with participantRow in rows of participantOutline
					set participantContainer to group 1 of UI element 1 of participantRow
					if exists static text connectedName of participantContainer then
						set visible to false
						return "already-connected:" & connectedName
					end if
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
						if exists static text connectedName of participantContainer then
							set visible to false
							return "connected:" & connectedName
						end if
					end repeat
				end repeat
				error "Timeout de reconnexion RTP vers " & peerName
			end tell
		end tell
	end tell
end run
