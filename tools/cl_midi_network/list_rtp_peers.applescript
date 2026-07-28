tell application "System Events"
	tell process "Audio MIDI Setup"
		set networkWindow to missing value
		repeat with candidateWindow in windows
			set windowName to name of candidateWindow as text
			if windowName contains "réseau MIDI" or windowName contains "MIDI Network" then
				set networkWindow to candidateWindow
				exit repeat
			end if
		end repeat
		if networkWindow is missing value then error "Fenêtre Réglages de réseau MIDI fermée"

		tell networkWindow
			set sessionScroll to scroll area 1 of group 1 of group 2 of splitter group 1 of group 1
			set localNetworkName to value of text field "Nom de réseau :" of group 3 of group 2 of sessionScroll as text
			set output to "SELF\t" & localNetworkName
			set directoryOutline to outline 1 of scroll area 1 of group 2 of group 1 of splitter group 1 of group 1
			repeat with candidateRow in rows of directoryOutline
				set rowContainer to group 1 of UI element 1 of candidateRow
				set peerName to value of static text 1 of rowContainer as text
				if peerName is not localNetworkName then set output to output & linefeed & "PEER\t" & peerName
			end repeat
			return output
		end tell
	end tell
end tell
