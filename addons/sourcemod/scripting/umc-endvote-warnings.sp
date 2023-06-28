/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *                              Ultimate Mapchooser - Vote Warnings                              *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */
/*************************************************************************
*************************************************************************
This plugin is free software: you can redistribute
it and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation, either version 3 of the License, or
later version.

This plugin is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this plugin.  If not, see <http://www.gnu.org/licenses/>.
*************************************************************************
*************************************************************************/
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <regex>
#include <sdktools_sound>
#include <umc-core>
#include <umc-endvote>
#include <umc_utils>
#include <emitsoundany>

public Plugin myinfo =
{
	name		= "[UMC] End of Map Vote Warnings",
	author		= PL_AUTHOR,
	description = "Adds vote warnings to UMC End of Map Votes.",
	version		= PL_VERSION,
	url			= "http://forums.alliedmods.net/showthread.php?t=134190"
}

// Cvars
ConVar cvar_time;
ConVar cvar_frag;
ConVar cvar_round;
ConVar cvar_win;

// Flags
bool time_enabled;
bool frag_enabled;
bool round_enabled;
bool win_enabled;

bool time_init;
bool frag_init;
bool round_init;
bool win_init;

// Warning adt_arrays
ArrayList time_array;
ArrayList frag_array;
ArrayList round_array;
ArrayList win_array;

// Current warning indices
int current_time;
int current_frag;
int current_round;
int current_win;

// TODO:
// Possible bug where warnings are never updated (vote timer activates before OnConfigsExecuted
// finishes) Possible solution is to update the warnings when the timer ticks (use flags so its
// only done when necessary).
public void OnPluginStart()
{
	cvar_time = CreateConVar(
		"sm_umc_endvote_timewarnings",
		"addons/sourcemod/configs/vote_warnings.txt",
		"Specifies which file time-based vote warnings are defined in. (uses mp_timelimit)");

	cvar_frag = CreateConVar(
		"sm_umc_endvote_fragwarnings",
		"",
		"Specifies which file frag-based vote warnings are defined in. (uses mp_fraglimit)");

	cvar_round = CreateConVar(
		"sm_umc_endvote_roundwarnings",
		"",
		"Specifies which file round-based vote warnings are defined in. (uses mp_maxrounds)");

	cvar_win = CreateConVar(
		"sm_umc_endvote_winwarnings",
		"",
		"Specifies which file win-based vote warnings are defined in. (uses mp_winlimit)");

	AutoExecConfig(true, "umc-endvote-warnings");

	// Initialize warning arrays
	time_array	= new ArrayList();
	frag_array	= new ArrayList();
	round_array = new ArrayList();
	win_array	= new ArrayList();

	LoadTranslations("ultimate-mapchooser.phrases");
}

public void OnConfigsExecuted()
{
	// Clear warning arrays
	ClearHandleArray(time_array);
	ClearHandleArray(frag_array);
	ClearHandleArray(round_array);
	ClearHandleArray(win_array);
}

public void OnMapStart()
{
	// Store cvar values
	char timefile[256], fragfile[256], roundfile[256], winfile[256];
	cvar_time.GetString(timefile, sizeof(timefile));
	cvar_frag.GetString(fragfile, sizeof(fragfile));
	cvar_round.GetString(roundfile, sizeof(roundfile));
	cvar_win.GetString(winfile, sizeof(winfile));

	// Set vote warning flags
	time_enabled  = strlen(timefile) > 0 && FileExists(timefile);
	frag_enabled  = strlen(fragfile) > 0 && FileExists(fragfile);
	round_enabled = strlen(roundfile) > 0 && FileExists(roundfile);
	win_enabled	  = strlen(winfile) > 0 && FileExists(winfile);

	// Initialize warning variables if vote warnings are enabled.
	if (time_enabled)
	{
		GetVoteWarnings(timefile, time_array, current_time);
	}
	if (frag_enabled)
	{
		GetVoteWarnings(fragfile, frag_array, current_frag);
	}
	if (round_enabled)
	{
		GetVoteWarnings(roundfile, round_array, current_round);
	}
	if (win_enabled)
	{
		GetVoteWarnings(winfile, win_array, current_win);
	}

	time_init  = false;
	frag_init  = false;
	round_init = false;
	win_init   = false;
}

// Comparison function for vote warnings. Used for sorting.
public int CompareWarnings(int index1, int index2, Handle array, Handle hndl)
{
	int	time1, time2;
	StringMap warning;
	warning = GetArrayCell(array, index1);
	GetTrieValue(warning, "time", time1);
	warning = GetArrayCell(array, index2);
	GetTrieValue(warning, "time", time2);
	return time2 - time1;
}

// Parses the vote warning definitions file and returns an adt_array of vote warnings.
void GetVoteWarnings(const char[] fileName, ArrayList warningArray, int &next)
{
	// Get our warnings file as a Kv file.
	KeyValues kv = GetKvFromFile(fileName, "vote_warnings", false);

	// Do nothing if we can't find the warning definitions.
	if (kv == null)
	{
		LogUMCMessage("Unable to parse warning file '%s', no vote warnings created.", fileName);
		return;
	}

	// Variables to hold default values. Initially set to defaults in the event that the user doesn't
	// specify his own.
	char dMessage[255];
	FormatEx(dMessage, sizeof(dMessage), "%T", "Default Warning", LANG_SERVER);	   // Message
	char dNotification[10]		   = "C";										   // Notification
	char dSound[PLATFORM_MAX_PATH] = "";										   // Sound
	char dFlags[64]				   = "";

	// Grab defaults from the KV if...
	//     ...they are actually defined.
	if (kv.JumpToKey("default"))
	{
		// Grab 'em.
		kv.GetString("message", dMessage, sizeof(dMessage), dMessage);
		kv.GetString("notification", dNotification, sizeof(dNotification), dNotification);
		kv.GetString("sound", dSound, sizeof(dSound), dSound);
		kv.GetString("adminflags", dFlags, sizeof(dFlags), dFlags);

		// Rewind back to root, so we can begin parsing the warnings.
		kv.Rewind();
	}

	// Log an error and return nothing if it cannot find any defined warnings.
	//  If the default definition is found, this code block will not execute. We will catch this case after we attempt to parse the file.
	if (!kv.GotoFirstSubKey())
	{
		LogUMCMessage("No vote warnings defined, vote warnings were not created.");
		CloseHandle(kv);
		return;
	}

	// Counter to keep track of the number of warnings we're storing.
	int warningCount = 0;

	// Storage handle for each warning.
	StringMap warning;

	// Storage buffers for warning values.
	int	warningTime;		 // Time (in seconds) before vote when the warning is displayed.
	char nameBuffer[10];	 // Buffer to hold the section name;
	char message[255];
	char notification[2];
	char sound[PLATFORM_MAX_PATH];
	char flags[64];

	// Storage buffer for formatted sound strings
	char fsound[PLATFORM_MAX_PATH];
	char timeString[10];

	// Regex to store sequence pattern in.
	Regex re;
	if (re == null)
	{
		re = CompileRegex("^([0-9]+)\\s*(?:(?:\\.\\.\\.)|-)\\s*([0-9]+)$");
	}

	// Variables to store sequence definition
	char sequence_start[10], sequence_end[10];

	// Variable storing interval of the sequence
	int	interval;

	// For a warning, add it to the result adt_array.
	do
	{
		// Grab the name (time) of the warning.
		kv.GetSectionName(nameBuffer, sizeof(nameBuffer));

		// Skip this warning if it is the default definition.
		if (StrEqual(nameBuffer, "default", false))
		{
			continue;
		}

		// Store warning info into variables.
		kv.GetString("message", message, sizeof(message), dMessage);
		kv.GetString("notification", notification, sizeof(notification), dNotification);
		kv.GetString("sound", sound, sizeof(sound), dSound);
		kv.GetString("adminflags", flags, sizeof(flags), dFlags);

		// Prepare to handle sequence of warnings if a sequence is what was defined.
		if (re.Match(nameBuffer) > 0)
		{
			// Get components of sequence
			re.GetSubString(1, sequence_start, sizeof(sequence_start));
			re.GetSubString(2, sequence_end, sizeof(sequence_end));

			// Calculate sequence interval
			warningTime = StringToInt(sequence_start);
			interval = (warningTime - StringToInt(sequence_end)) + 1;

			// Invert sequence if it was specified in the wrong order.
			if (interval < 0)
			{
				interval *= -1;
				warningTime += interval;
			}
		}
		else	// Otherwise, just handle the single warning.
		{
			warningTime = StringToInt(nameBuffer);
			interval = 1;
		}

		// Store a warning for each element in the interval.
		for (int i = 0; i < interval; i++)
		{
			// Store everything in a trie which represents a warning object
			warning = new StringMap();
			SetTrieValue(warning, "time", warningTime - i);
			SetTrieString(warning, "message", message);
			SetTrieString(warning, "notification", notification);
			SetTrieString(warning, "flags", flags);

			// Insert correct time remaining if the message has a place to insert it.
			if (StrContains(sound, "{TIME}") != -1)
			{
				IntToString(warningTime - i, timeString, sizeof(timeString));
				strcopy(fsound, sizeof(fsound), sound);
				ReplaceString(fsound, sizeof(fsound), "{TIME}", timeString, false);

				// Setup the sound for the warning.
				CacheSound(fsound);
				SetTrieString(warning, "sound", fsound);
			}
			else	// Otherwise just cache the defined sound.
			{
				// Setup the sound for the warning.
				CacheSound(sound);
				SetTrieString(warning, "sound", sound);
			}

			// Add the new warning to the result adt_array.
			PushArrayCell(warningArray, warning);

			// Increment the counter.
			warningCount++;
		}
	}
	while (kv.GotoNextKey());	 // Do this for every warning.

	// We no longer need the kv.
	CloseHandle(kv);

	// Log an error and return nothing if no vote warnings were found.
	//  This accounts for the case where the default definition was provided, but not actual warnings.
	if (warningCount < 1)
	{
		LogUMCMessage("No vote warnings defined, vote warnings were not created.");
	}
	else	// Otherwise, log a success!
	{
		LogUMCMessage("Successfully parsed and set up %i vote warnings.", warningCount);

		// Sort the array in descending order of time.
		SortADTArrayCustom(warningArray, CompareWarnings);
		next = GetArraySize(warningArray);
	}
}

int UpdateWarnings(Handle array, int threshold, int &warningTime)
{
	// Storage variables.
	int i, arraySize;

	// Test if a warning is the next warning to be displayed for each warning in the warning array.
	arraySize = GetArraySize(array);
	for (i = 0; i < arraySize; i++)
	{
		GetTrieValue(GetArrayCell(array, i), "time", warningTime);

		// We found out answer if the trigger for the next warning hasn't passed.
		if (warningTime < threshold)
		{
			break;
		}
	}

	return i;
}

void UpdateWinWarnings(int winsleft)
{
	int warningTime;
	current_win = UpdateWarnings(win_array, winsleft, warningTime);

	if (current_win < GetArraySize(win_array))
	{
		win_init = true;
		LogUMCMessage("First win-warning will appear at %i wins before the end of the map.", warningTime);
	}
}

void UpdateFragWarnings(int fragsleft)
{
	int warningTime;
	current_frag = UpdateWarnings(frag_array, fragsleft, warningTime);

	if (current_round < GetArraySize(round_array))
	{
		frag_init = true;
		LogUMCMessage("First frag-warning will appear at %i frags before the end of map vote.", warningTime);
	}
}

void UpdateTimeWarnings(int timeleft)
{
	int warningTime;
	current_time = UpdateWarnings(time_array, timeleft, warningTime);

	if (current_time < GetArraySize(time_array))
	{
		time_init = true;
		LogUMCMessage("First time-warning will appear %i seconds before the end of map vote.", warningTime);
	}
}

void UpdateRoundWarnings(int roundsleft)
{
	int warningTime;
	current_round = UpdateWarnings(round_array, roundsleft, warningTime);

	if (current_round < GetArraySize(round_array))
	{
		round_init = true;
		LogUMCMessage("First round-warning will appear at %i rounds before the end of map vote.", warningTime);
	}
}

// Perform a vote warning, does nothing if there is no warning defined for this time.
stock void DoVoteWarning(ArrayList warningArray, int &next, int triggertime, int param = 0)
{
	// Do nothing if there are no more warnings to perform.
	if (GetArraySize(warningArray) <= next)
	{
		return;
	}

	// Get the current warning.
	StringMap warning = GetArrayCell(warningArray, next);

	// Get the trigger time of the current warning.
	int warningTime;
	GetTrieValue(warning, "time", warningTime);

	// Display warning if the time to trigger it has come.
	if (triggertime <= warningTime)
	{
		DisplayVoteWarning(warning, param);

		// Move to the next warning.
		next++;

		// Repeat in the event that there are multiple warnings for this time.
		DoVoteWarning(warningArray, next, triggertime, param);
	}
}

void TryDoTimeWarning(int timeleft)
{
	if (time_enabled)
	{
		DoVoteWarning(time_array, current_time, timeleft);
	}
}

void TryDoRoundWarning(int rounds)
{
	if (round_enabled)
	{
		DoVoteWarning(round_array, current_round, rounds);
	}
}

void TryDoFragWarning(int frags, int client)
{
	if (frag_enabled)
	{
		DoVoteWarning(frag_array, current_frag, frags, client);
	}
}

void TryDoWinWarning(int wins, int team)
{
	if (win_enabled)
	{
		DoVoteWarning(win_array, current_win, wins, team);
	}
}

// Displays the given vote warning to the server
void DisplayVoteWarning(StringMap warning, int param = 0)
{
	// Get warning information.
	int time;
	char message[255];
	char notification[2];
	char sound[PLATFORM_MAX_PATH];
	GetTrieValue(warning, "time", time);
	GetTrieString(warning, "message", message, sizeof(message));
	GetTrieString(warning, "notification", notification, sizeof(notification));
	GetTrieString(warning, "sound", sound, sizeof(sound));

	// Emit the warning sound if the sound is defined.
	if (strlen(sound) > 0)
	{
		EmitSoundToAllAny(sound);
	}

	// Stop here if there is nothing to display.
	if (strlen(message) == 0 || strlen(notification) == 0)
	{
		return;
	}

	// Buffer to store string replacements in the message.
	char sBuffer[5];

	// Insert correct time remaining if the message has a place to insert it.
	if (StrContains(message, "{TIME}") != -1)
	{
		IntToString(time, sBuffer, sizeof(sBuffer));
		ReplaceString(message, sizeof(message), "{TIME}", sBuffer, false);
	}

	// Insert correct time remaining if the message has a place to insert it.
	if (StrContains(message, "{PLAYER}") != -1)
	{
		FormatEx(sBuffer, sizeof(sBuffer), "%N", param);
		ReplaceString(message, sizeof(message), "{PLAYER}", sBuffer, false);
	}

	// Insert a newline character if the message has a place to insert it.
	if (StrContains(message, "\\n") != -1)
	{
		FormatEx(sBuffer, sizeof(sBuffer), "%c", 13);
		ReplaceString(message, sizeof(message), "\\n", sBuffer);
	}

	// Display the message
	DisplayServerMessage(message, notification);
}

//************************************************************************************************//
//                                   UMC END OF MAP VOTE EVENTS                                   //
//************************************************************************************************//
public void UMC_OnNextmapSet(KeyValues kv, const char[] map, const char[] group, const char[] display)
{
	// Stop displaying any warnings.
	DisplayServerMessage("", "");
}

public void UMC_EndVote_OnTimeTimerUpdated(int timeleft)
{
	UpdateTimeWarnings(timeleft);
}

public void UMC_EndVote_OnRoundTimerUpdated(int roundsleft)
{
	UpdateRoundWarnings(roundsleft);
}

public void UMC_EndVote_OnFragTimerUpdated(int fragsleft, int client)
{
	UpdateFragWarnings(fragsleft);
}

public void UMC_EndVote_OnWinTimerUpdated(int winsleft, int team)
{
	UpdateWinWarnings(winsleft);
}

public void UMC_EndVote_OnTimeTimerTicked(int timeleft)
{
	if (!time_init)
	{
		UpdateTimeWarnings(timeleft);
	}
	TryDoTimeWarning(timeleft);
}

public void UMC_EndVote_OnRoundTimerTicked(int roundsleft)
{
	if (!round_init)
	{
		UpdateRoundWarnings(roundsleft);
	}
	TryDoRoundWarning(roundsleft);
}

public void UMC_EndVote_OnFragTimerTicked(int fragsleft, int client)
{
	if (!frag_init)
	{
		UpdateFragWarnings(fragsleft);
	}
	TryDoFragWarning(fragsleft, client);
}

public void UMC_EndVote_OnWinTimerTicked(int winsleft, int team)
{
	if (!win_init)
	{
		UpdateWinWarnings(winsleft);
	}
	TryDoWinWarning(winsleft, team);
}
