/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *                               Ultimate Mapchooser - Vote Command                              *
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
#include <umc-core>
#include <umc_utils>

// Plugin Information
public Plugin myinfo =
{
	name		= "[UMC] Vote Command",
	author		= PL_AUTHOR,
	description = "Extends Ultimate Mapchooser to allow admins to spawn votes.",
	version		= PL_VERSION,
	url			= "http://forums.alliedmods.net/showthread.php?t=134190"
};

////----CONVARS-----/////
ConVar cvar_filename;
ConVar cvar_scramble;
ConVar cvar_vote_time;
ConVar cvar_strict_noms;
ConVar cvar_runoff;
ConVar cvar_runoff_sound;
ConVar cvar_runoff_max;
ConVar cvar_vote_allowduplicates;
ConVar cvar_vote_threshold;
ConVar cvar_fail_action;
ConVar cvar_runoff_fail_action;
ConVar cvar_extend_rounds;
ConVar cvar_extend_frags;
ConVar cvar_extend_time;
ConVar cvar_extensions;
ConVar cvar_vote_mem;
ConVar cvar_vote_type;
ConVar cvar_vote_startsound;
ConVar cvar_vote_endsound;
ConVar cvar_vote_catmem;
ConVar cvar_dontchange;
ConVar cvar_flags;
////----/CONVARS-----/////

// Mapcycle KV
KeyValues map_kv;
KeyValues umc_mapcycle;

// Memory queues. Used to store the previously played maps.
ArrayList vote_mem_arr;
ArrayList vote_catmem_arr;

// Sounds to be played at the start and end of votes.
char vote_start_sound[PLATFORM_MAX_PATH];
char vote_end_sound[PLATFORM_MAX_PATH];
char runoff_sound[PLATFORM_MAX_PATH];

// Can we start a vote (is the mapcycle valid?)
bool can_vote;

//************************************************************************************************//
//                                        SOURCEMOD EVENTS                                        //
//************************************************************************************************//
// Called when the plugin is finished loading.
public void OnPluginStart()
{
	cvar_flags = CreateConVar(
		"sm_umc_vc_adminflags",
		"",
		"Specifies which admin flags are necessary for a player to participate in a vote. If empty, all players can participate.");

	cvar_fail_action = CreateConVar(
		"sm_umc_vc_failaction",
		"0",
		"Specifies what action to take if the vote doesn't reach the set theshold.\n 0 - Do Nothing,\n 1 - Perform Runoff Vote",
		0, true, 0.0, true, 1.0);

	cvar_runoff_fail_action = CreateConVar(
		"sm_umc_vc_runoff_failaction",
		"0",
		"Specifies what action to take if the runoff vote reaches the maximum amount of runoffs and the set threshold has not been reached.\n 0 - Do Nothing,\n 1 - Change Map to Winner",
		0, true, 0.0, true, 1.0);

	cvar_runoff_max = CreateConVar(
		"sm_umc_vc_runoff_max",
		"0",
		"Specifies the maximum number of maps to appear in a runoff vote.\n 1 or 0 sets no maximum.",
		0, true, 0.0);

	cvar_vote_allowduplicates = CreateConVar(
		"sm_umc_vc_allowduplicates",
		"1",
		"Allows a map to appear in the vote more than once. This should be enabled if you want the same map in different categories to be distinct.",
		0, true, 0.0, true, 1.0);

	cvar_vote_threshold = CreateConVar(
		"sm_umc_vc_threshold",
		"0",
		"If the winning option has less than this percentage of total votes, a vote will fail and the action specified in \"sm_umc_vc_failaction\" cvar will be performed.",
		0, true, 0.0, true, 1.0);

	cvar_runoff = CreateConVar(
		"sm_umc_vc_runoffs",
		"0",
		"Specifies a maximum number of runoff votes to run for a vote.\n 0 = unlimited.",
		0, true, 0.0);

	cvar_runoff_sound = CreateConVar(
		"sm_umc_vc_runoff_sound",
		"",
		"If specified, this sound file (relative to sound folder) will be played at the beginning of a runoff vote. If not specified, it will use the normal vote start sound.");

	cvar_vote_catmem = CreateConVar(
		"sm_umc_vc_groupexclude",
		"0",
		"Specifies how many past map groups to exclude from votes.",
		0, true, 0.0);

	cvar_vote_startsound = CreateConVar(
		"sm_umc_vc_startsound",
		"",
		"Sound file (relative to sound folder) to play at the start of a vote.");

	cvar_vote_endsound = CreateConVar(
		"sm_umc_vc_endsound",
		"",
		"Sound file (relative to sound folder) to play at the completion of a vote.");

	cvar_strict_noms = CreateConVar(
		"sm_umc_vc_nominate_strict",
		"0",
		"Specifies whether the number of nominated maps appearing in the vote for a map group should be limited by the group's \"maps_invote\" setting.",
		0, true, 0.0, true, 1.0);

	cvar_extend_rounds = CreateConVar(
		"sm_umc_vc_extend_roundstep",
		"5",
		"Specifies how many more rounds each extension adds to the round limit.",
		0, true, 1.0);

	cvar_extend_time = CreateConVar(
		"sm_umc_vc_extend_timestep",
		"15",
		"Specifies how many more minutes each extension adds to the time limit.",
		0, true, 1.0);

	cvar_extend_frags = CreateConVar(
		"sm_umc_vc_extend_fragstep",
		"10",
		"Specifies how many more frags each extension adds to the frag limit.",
		0, true, 1.0);

	cvar_extensions = CreateConVar(
		"sm_umc_vc_extend",
		"0",
		"Adds an \"Extend\" option to votes.",
		0, true, 0.0, true, 1.0);

	cvar_vote_type = CreateConVar(
		"sm_umc_vc_type",
		"0",
		"Controls vote type:\n 0 - Maps,\n 1 - Groups,\n 2 - Tiered Vote (vote for a group, then vote for a map from the group).",
		0, true, 0.0, true, 2.0);

	cvar_vote_time = CreateConVar(
		"sm_umc_vc_duration",
		"20",
		"Specifies how long a vote should be available for.",
		0, true, 10.0);

	cvar_filename = CreateConVar(
		"sm_umc_vc_cyclefile",
		"umc_mapcycle.txt",
		"File to use for Ultimate Mapchooser's map rotation.");

	cvar_vote_mem = CreateConVar(
		"sm_umc_vc_mapexclude",
		"4",
		"Specifies how many past maps to exclude from votes. 1 = Current Map Only",
		0, true, 0.0);

	cvar_scramble = CreateConVar(
		"sm_umc_vc_menuscrambled",
		"0",
		"Specifies whether vote menu items are displayed in a random order.",
		0, true, 0.0, true, 1.0);

	cvar_dontchange = CreateConVar(
		"sm_umc_vc_dontchange",
		"1",
		"Adds a \"Don't Change\" option to votes.",
		0, true, 0.0, true, 1.0);

	// Create the config if it doesn't exist, and then execute it.
	AutoExecConfig(true, "umc-votecommand");

	// Admin command to immediately start a mapvote.
	RegAdminCmd("sm_umc_mapvote", Command_Vote, ADMFLAG_CHANGEMAP, "Starts an Ultimate Mapchooser map vote.");

	// Initialize our memory arrays
	int numCells	= ByteCountToCells(MAP_LENGTH);
	vote_mem_arr	= new ArrayList(numCells);
	vote_catmem_arr = new ArrayList(numCells);
}

//************************************************************************************************//
//                                           GAME EVENTS                                          //
//************************************************************************************************//
// Called after all config files were executed.
public void OnConfigsExecuted()
{
	can_vote = ReloadMapcycle();

	// Grab the name of the current map.
	char mapName[MAP_LENGTH];
	GetCurrentMap(mapName, sizeof(mapName));
	char groupName[MAP_LENGTH];
	UMC_GetCurrentMapGroup(groupName, sizeof(groupName));

	if (can_vote && StrEqual(groupName, INVALID_GROUP, false))
	{
		KvFindGroupOfMap(umc_mapcycle, mapName, groupName, sizeof(groupName));
	}

	// Add the map to all the memory queues.
	int mapmem = cvar_vote_mem.IntValue;
	int catmem = cvar_vote_catmem.IntValue;
	AddToMemoryArray(mapName, vote_mem_arr, mapmem);
	AddToMemoryArray(groupName, vote_catmem_arr, (mapmem > catmem) ? mapmem : catmem);

	if (can_vote)
	{
		RemovePreviousMapsFromCycle();
	}
}

public void OnMapStart()
{
	SetupVoteSounds();
}

//************************************************************************************************//
//                                              SETUP                                             //
//************************************************************************************************//
// Parses the mapcycle file and returns a KV handle representing the mapcycle.
KeyValues GetMapcycle()
{
	// Grab the file name from the cvar.
	char filename[PLATFORM_MAX_PATH];
	cvar_filename.GetString(filename, sizeof(filename));

	// Get the kv handle from the file.
	KeyValues result = GetKvFromFile(filename, "umc_rotation");

	// Log an error and return empty handle if the mapcycle file failed to parse.
	if (result == null)
	{
		LogError("SETUP: Mapcycle failed to load!");
		return null;
	}

	// Success!
	return result;
}

// Reloads the mapcycle. Returns true on success, false on failure.
bool ReloadMapcycle()
{
	if (umc_mapcycle != null)
	{
		CloseHandle(umc_mapcycle);
		umc_mapcycle = null;
	}
	if (map_kv != null)
	{
		CloseHandle(map_kv);
		map_kv = null;
	}
	umc_mapcycle = GetMapcycle();

	return umc_mapcycle != null;
}

void RemovePreviousMapsFromCycle()
{
	map_kv = new KeyValues("umc_rotation");
	KvCopySubkeys(umc_mapcycle, map_kv);
	FilterMapcycleFromArrays(map_kv, vote_mem_arr, vote_catmem_arr, cvar_vote_catmem.IntValue);
}

// Sets up the vote sounds.
void SetupVoteSounds()
{
	// Grab sound files from cvars.
	cvar_vote_startsound.GetString(vote_start_sound, sizeof(vote_start_sound));
	cvar_vote_endsound.GetString(vote_end_sound, sizeof(vote_end_sound));
	cvar_runoff_sound.GetString(runoff_sound, sizeof(runoff_sound));

	// Gotta cache 'em all!
	CacheSound(vote_start_sound);
	CacheSound(vote_end_sound);
	CacheSound(runoff_sound);
}

//************************************************************************************************//
//                                            COMMANDS                                            //
//************************************************************************************************//
// Called when the command to start a map vote is called
public Action Command_Vote(int client, int args)
{
	if (!can_vote)
	{
		ReplyToCommand(client, "[UMC] Mapcycle is invalid, cannot start a vote.");
		return Plugin_Handled;
	}

	if (args < 1)
	{
		ReplyToCommand(client, "[UMC] Usage: sm_umc_mapvote <0|1|2>\n 0: Change now, 1: Change at end of round, 2: Change at end of map.");
		return Plugin_Handled;
	}

	char arg[128];
	GetCmdArg(1, arg, sizeof(arg));
	int changeTime = StringToInt(arg);

	if (changeTime < 0 || changeTime > 2)
	{
		ReplyToCommand(client, "[UMC] Usage: sm_umc_mapvote <0|1|2>\n 0: Change now, 1: Change at end of round, 2: Change at end of map.");
		return Plugin_Handled;
	}

	char flags[64];
	cvar_flags.GetString(flags, sizeof(flags));

	int clients[MAXPLAYERS + 1];
	int numClients;
	GetClientsWithFlags(flags, clients, sizeof(clients), numClients);

	// Start the UMC vote.
	bool result = UMC_StartVote(
		"core",
		map_kv,																// Mapcycle
		umc_mapcycle,														// Complete Mapcycle
		view_as<UMC_VoteType>(cvar_vote_type.IntValue),						// Vote Type (map, group, tiered)
		cvar_vote_time.IntValue,											// Vote duration
		cvar_scramble.BoolValue,											// Scramble
		vote_start_sound,													// Start Sound
		vote_end_sound,														// End Sound
		cvar_extensions.BoolValue,											// Extend option
		cvar_extend_time.FloatValue,										// How long to extend the timelimit by,
		cvar_extend_rounds.IntValue,										// How much to extend the roundlimit by,
		cvar_extend_frags.IntValue,											// How much to extend the fraglimit by,
		cvar_dontchange.BoolValue,											// Don't Change option
		cvar_vote_threshold.FloatValue,										// Threshold
		view_as<UMC_ChangeMapTime>(changeTime),								// Success Action (when to change the map)
		view_as<UMC_VoteFailAction>(cvar_fail_action.IntValue),				// Fail Action (runoff / nothing)
		cvar_runoff.IntValue,												// Max Runoffs
		cvar_runoff_max.IntValue,											// Max maps in the runoff
		view_as<UMC_RunoffFailAction>(cvar_runoff_fail_action.IntValue),	// Runoff Fail Action
		runoff_sound,														// Runoff Sound
		cvar_strict_noms.BoolValue,											// Nomination Strictness
		cvar_vote_allowduplicates.BoolValue,								// Ignore Duplicates
		clients,
		numClients);

	if (result)
	{
		ReplyToCommand(client, "[UMC] Started Vote.");
	}
	else
	{
		ReplyToCommand(client, "[UMC] Could not start vote. See log for details.");
	}
	return Plugin_Handled;
}

//************************************************************************************************//
//                                   ULTIMATE MAPCHOOSER EVENTS                                   //
//************************************************************************************************//
// Called when UMC requests that the mapcycle should be reloaded.
public void UMC_RequestReloadMapcycle()
{
	can_vote = ReloadMapcycle();
	if (can_vote)
	{
		RemovePreviousMapsFromCycle();
	}
}

// Called when UMC requests that the mapcycle is printed to the console.
public void UMC_DisplayMapCycle(int client, bool filtered)
{
	PrintToConsole(client, "Module: Vote Command");
	if (filtered)
	{
		KeyValues filteredMapcycle = UMC_FilterMapcycle(map_kv, umc_mapcycle, false, true);
		PrintKvToConsole(filteredMapcycle, client);
		CloseHandle(filteredMapcycle);
	}
	else
	{
		PrintKvToConsole(umc_mapcycle, client);
	}
}