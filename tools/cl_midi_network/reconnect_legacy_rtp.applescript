on run argv
	if (count of argv) < 2 then error "Usage: osascript reconnect_legacy_rtp.applescript PEER_NAME CONNECTED_NAME"
	set peerName to item 1 of argv
	set connectedName to item 2 of argv

	tell application "Audio MIDI Setup" to activate
	delay 1

	tell application "System Events"
		tell process "Audio MIDI Setup"
			set networkWindow to missing value
			repeat with candidateWindow in windows
				if exists static text "Sessions et répertoires" of candidateWindow then
					set networkWindow to candidateWindow
					exit repeat
				end if
			end repeat
			if networkWindow is missing value then error "Fenêtre Réglages de réseau MIDI introuvable"

			tell networkWindow
				if exists button "Se déconnecter" of group 2 then
					set activeName to value of text field 2 of group 2 as text
					if activeName is connectedName then return "already-connected:" & activeName
					error "Une autre session RTP est déjà active: " & activeName
				end if

				set directoryTable to table 1 of scroll area 1 of group 3
				set matchingRow to missing value
				repeat with candidateRow in rows of directoryTable
					if exists static text peerName of UI element 1 of candidateRow then
						set matchingRow to candidateRow
						exit repeat
					end if
				end repeat
				if matchingRow is missing value then error "Correspondant RTP introuvable: " & peerName

				select matchingRow
				click button "Se connecter" of group 3
				repeat 20 times
					delay 0.5
					if exists button "Se déconnecter" of group 2 then
						set activeName to value of text field 2 of group 2 as text
						if activeName is connectedName then return "connected:" & activeName
					end if
				end repeat
				error "Timeout de reconnexion RTP vers " & peerName
			end tell
		end tell
	end tell
end run
