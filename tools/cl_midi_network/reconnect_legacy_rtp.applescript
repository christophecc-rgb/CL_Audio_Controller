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
				set windowName to name of candidateWindow as text
				if windowName contains "réseau MIDI" or windowName contains "MIDI Network" then
					set networkWindow to candidateWindow
					exit repeat
				end if
			end repeat
			if networkWindow is missing value then error "Fenêtre Réglages de réseau MIDI introuvable"

			set rootGroup to UI element 1 of networkWindow
			set splitGroup to UI element 1 of rootGroup
			set leftPanel to UI element 1 of splitGroup

			set sessionsGroup to UI element 1 of leftPanel
			set sessionsScroll to UI element 2 of sessionsGroup
			set sessionsTable to UI element 1 of sessionsScroll
			if (count of rows of sessionsTable) is 0 then error "Aucune session RTP configurée"
			set sessionRow to row 1 of sessionsTable
			select sessionRow
			set sessionCell to UI element 1 of sessionRow
			set sessionContents to UI element 1 of sessionCell
			set sessionCheckbox to UI element 1 of sessionContents
			if (value of sessionCheckbox as integer) is 0 then click sessionCheckbox

			set activeName to ""
			repeat with sessionElement in UI elements of sessionContents
				try
					set candidateValue to value of sessionElement as text
					if candidateValue is connectedName then set activeName to candidateValue
				end try
			end repeat
			if activeName is connectedName then return "already-connected:" & activeName

			set directoryGroup to UI element 2 of leftPanel
			set directoryScroll to UI element 2 of directoryGroup
			set directoryTable to UI element 1 of directoryScroll
			set matchingRow to missing value
			repeat with candidateRow in rows of directoryTable
				set directoryCell to UI element 1 of candidateRow
				set rowContents to UI element 1 of directoryCell
				try
					if exists static text peerName of rowContents then
						set matchingRow to candidateRow
						exit repeat
					end if
				end try
			end repeat
			if matchingRow is missing value then error "Correspondant RTP introuvable: " & peerName

			select matchingRow
			set connectButton to UI element 3 of directoryGroup
			click connectButton
			repeat 20 times
				delay 0.5
				set activeName to ""
				repeat with sessionElement in UI elements of sessionContents
					try
						set candidateValue to value of sessionElement as text
						if candidateValue is connectedName then set activeName to candidateValue
					end try
				end repeat
				if activeName is connectedName then return "connected:" & activeName
			end repeat
			error "Timeout de reconnexion RTP vers " & peerName
		end tell
	end tell
end run
