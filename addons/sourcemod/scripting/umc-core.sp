/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *                                  Ultimate Mapchooser - Core                                   *
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

// Dependencies
#include <umc-core>
#include <umc_utils>
#include <sourcemod>
#include <sdktools_sound>
#include <emitsoundany>

// Some definitions
#define NOTHING_OPTION "?nothing?"
#define WEIGHT_KEY	   "___calculated-weight"

// Plugin Information
public Plugin myinfo =
{
	name		= "[UMC] Ultimate Mapchooser Core",
	author		= PL_AUTHOR,
	description = "Core component for [UMC]",
	version		= PL_VERSION,
	url			= "http://forums.alliedmods.net/showthread.php?t=134190"
};

//************************************************************************************************//
//                                        GLOBAL VARIABLES                                        //
//************************************************************************************************//
////----CONVARS-----/////
ConVar g_Cvar_Runoff_Display;
ConVar g_Cvar_Runoff_Selective;
ConVar g_Cvar_Vote_TierAmount;
ConVar g_Cvar_Vote_TierDisplay;
ConVar g_Cvar_Logging;
ConVar g_Cvar_Extend_Display;
ConVar g_Cvar_DontChange_Display;
ConVar g_Cvar_ValveMenu;
ConVar g_Cvar_Version;
ConVar g_Cvar_Count_Sound;
ConVar g_Cvar_Extend_Command;
ConVar g_Cvar_Default_Vm;
ConVar g_Cvar_Block_Slots;
ConVar g_Cvar_NoVote;
ConVar g_Cvar_NomMsg_Disp;
ConVar g_Cvar_MapNom_Display;

//Stores the current category.
char g_Current_Cat[MAP_LENGTH];

//Stores the category of the next map.
char g_Next_Cat[MAP_LENGTH];

//Array of nomination tries.
ArrayList g_Nominations_Arr;

//Forward for when a nomination is removed.
GlobalForward g_Nomination_Reset_Forward;

//Sound used during countdown to map vote
char g_Countdown_Sound[PLATFORM_MAX_PATH];

/* Reweight System */
GlobalForward g_Reweight_Forward;
GlobalForward g_Reweight_Group_Forward;
bool g_Reweight_Active = false;
float g_Current_Weight;

/* Exclusion System */
GlobalForward g_Exclude_Forward;

/* Reload System */
GlobalForward g_Reload_Forward;

/* Extend System */
GlobalForward g_Extend_Forward;

/* Nextmap System */
GlobalForward g_Nextmap_Forward;

/* Failure System */
GlobalForward g_Failure_Forward;

/* Vote Notification System */
GlobalForward g_Vote_Start_Forward;
GlobalForward g_Vote_End_Forward;
GlobalForward g_Client_Voted_Forward;

/* Vote Management System */
StringMap g_Vote_Managers;
ArrayList g_Vote_Manager_IDs;

/* Maplist Display */
GlobalForward g_MapListDisplay_Forward;

/* Template System */
GlobalForward g_Template_Forward;

//Flags
bool g_Change_Map_Round; //Change map when the round ends?

//Misc ConVars
ConVar g_Cvar_MaxRounds;
ConVar g_Cvar_FragLimit;
ConVar g_Cvar_WinLimit;
ConVar g_Cvar_NextLevel;  //GE:S
ConVar g_Cvar_ZpsMaxRnds; // ZPS Survival
ConVar g_Cvar_ZpoMaxRnds; // ZPS Objective
//************************************************************************************************//
//                                        SOURCEMOD EVENTS                                        //
//************************************************************************************************//
// Called before the plugin loads, sets up our natives.
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("UMC_AddWeightModifier", Native_UMCAddWeightModifier);
	CreateNative("UMC_StartVote", Native_UMCStartVote);
	CreateNative("UMC_GetCurrentMapGroup", Native_UMCGetCurrentGroup);
	CreateNative("UMC_GetRandomMap", Native_UMCGetRandomMap);
	CreateNative("UMC_SetNextMap", Native_UMCSetNextMap);
	CreateNative("UMC_IsMapNominated", Native_UMCIsMapNominated);
	CreateNative("UMC_NominateMap", Native_UMCNominateMap);
	CreateNative("UMC_CreateValidMapArray", Native_UMCCreateMapArray);
	CreateNative("UMC_CreateValidMapGroupArray", Native_UMCCreateGroupArray);
	CreateNative("UMC_IsMapValid", Native_UMCIsMapValid);
	CreateNative("UMC_FilterMapcycle", Native_UMCFilterMapcycle);
	CreateNative("UMC_IsVoteInProgress", Native_UMCIsVoteInProgress);
	CreateNative("UMC_StopVote", Native_UMCStopVote);
	CreateNative("UMC_RegisterVoteManager", Native_UMCRegVoteManager);
	CreateNative("UMC_UnregisterVoteManager", Native_UMCUnregVoteManager);
	CreateNative("UMC_VoteManagerVoteCompleted", Native_UMCVoteManagerComplete);
	CreateNative("UMC_VoteManagerVoteCancelled", Native_UMCVoteManagerCancel);
	CreateNative("UMC_VoteManagerClientVoted", Native_UMCVoteManagerVoted);
	CreateNative("UMC_FormatDisplayString", Native_UMCFormatDisplay);
	CreateNative("UMC_IsNewVoteAllowed", Native_UMCIsNewVoteAllowed);

	RegPluginLibrary("umccore");

	return APLRes_Success;
}

// Called when the plugin is finished loading.
public void OnPluginStart()
{
	g_Cvar_NomMsg_Disp = CreateConVar(
		"sm_umc_nommsg_display",
		"^",
		"String to replace the {NOMINATED} map display-template string with.");

	g_Cvar_NoVote = CreateConVar(
		"sm_umc_votemanager_core_novote",
		"0",
		"Enable No Vote option at the top of vote menus. Requires SourceMod >= 1.4",
		0, true, 0.0, true, 1.0);

	g_Cvar_Block_Slots = CreateConVar(
		"sm_umc_votemanager_core_blockslots",
		"0",
		"Specifies how many slots in a vote are disabled to prevent accidental voting.",
		0, true, 0.0, true, 5.0);

	g_Cvar_Default_Vm = CreateConVar(
		"sm_umc_votemanager_default",
		"core",
		"Specifies the default UMC Vote Manager to be used for voting. The default value of \"core\" means that Sourcemod's built-in voting will be used.");

	g_Cvar_Extend_Command = CreateConVar(
		"sm_umc_extend_command",
		"",
		"Specifies a server command to be executed when the map is extended by UMC.");

	g_Cvar_Count_Sound = CreateConVar(
		"sm_umc_countdown_sound",
		"",
		"Specifies a sound to be played each second during the countdown time between runoff and tiered votes. (Sound will be precached and added to the download table.)");

	g_Cvar_ValveMenu = CreateConVar(
		"sm_umc_votemanager_core_menu_esc",
		"0",
		"If enabled, votes will use Valve-Stlye menus (players will be required to press ESC in order to vote). NOTE: this may not work in TF2!",
		0, true, 0.0, true, 1.0);

	g_Cvar_Extend_Display = CreateConVar(
		"sm_umc_extend_display",
		"0",
		"Determines where in votes the \"Extend Map\" option will be displayed.\n 0 - Bottom,\n 1 - Top",
		0, true, 0.0, true, 1.0);

	g_Cvar_DontChange_Display = CreateConVar(
		"sm_umc_dontchange_display",
		"0",
		"Determines where in votes the \"Don't Change\" option will be displayed.\n 0 - Bottom,\n 1 - Top",
		0, true, 0.0, true, 1.0);

	g_Cvar_MapNom_Display = CreateConVar(
		"sm_umc_mapnom_display",
		"0",
		"Determines where in votes the nominated maps will be displayed.\n 0 - Bottom,\n 1 - Top",
		0, true, 0.0, true, 1.0);

	g_Cvar_Logging = CreateConVar(
		"sm_umc_logging_verbose",
		"1",
		"Enables in-depth logging. Use this to have the plugin log how votes are being populated.",
		0, true, 0.0, true, 1.0);

	g_Cvar_Runoff_Selective = CreateConVar(
		"sm_umc_runoff_selective",
		"0",
		"Specifies whether runoff votes are only displayed to players whose votes were eliminated in the runoff and players who did not vote.",
		0, true, 0.0, true, 1.0);

	g_Cvar_Vote_TierAmount = CreateConVar(
		"sm_umc_vote_tieramount",
		"6",
		"Specifies the maximum number of maps to appear in the second part of a tiered vote.",
		0, true, 2.0);

	g_Cvar_Runoff_Display = CreateConVar(
		"sm_umc_runoff_display",
		"C",
		"Determines where the Runoff Vote Message is displayed on the screen.\n C - Center Message\n S - Chat Message\n T - Top Message\n H - Hint Message");

	g_Cvar_Vote_TierDisplay = CreateConVar(
		"sm_umc_vote_tierdisplay",
		"C",
		"Determines where the Tiered Vote Message is displayed on the screen.\n C - Center Message\n S - Chat Message\n T - Top Message\n H - Hint Message");

	// Version
	g_Cvar_Version = CreateConVar(
		"improved_map_randomizer_version", PL_VERSION, "Ultimate Mapchooser's version",
		FCVAR_NOTIFY | FCVAR_DONTRECORD | FCVAR_SPONLY | FCVAR_REPLICATED);

	// Create the config if it doesn't exist, and then execute it.
	AutoExecConfig(true, "ultimate-mapchooser");

	// Admin commands
	RegAdminCmd("sm_umc_displaymaplists", Command_DisplayMapLists, ADMFLAG_CHANGEMAP, "Displays the current maplist for all UMC modules.");
	RegAdminCmd("sm_umc_maphistory", Command_MapHistory, ADMFLAG_CHANGEMAP, "Shows the most recent maps played");
	RegAdminCmd("sm_setnextmap", Command_SetNextmap, ADMFLAG_CHANGEMAP, "sm_setnextmap <map>");
	RegAdminCmd("sm_umc_reload_mapcycles", Command_Reload, ADMFLAG_RCON, "Reloads the mapcycle file.");
	RegAdminCmd("sm_umc_stopvote", Command_StopVote, ADMFLAG_CHANGEMAP, "Stops all UMC votes that are in progress.");

	// Hook round end events
	HookEvent("round_end", Event_RoundEnd);				  // Generic
	HookEventEx("game_round_end", Event_RoundEnd);		  // Hidden: Source, Neotokyo
	HookEventEx("teamplay_win_panel", Event_RoundEnd);	  // TF2
	HookEventEx("arena_win_panel", Event_RoundEnd);		  // TF2
	HookEventEx("round_win", Event_RoundEnd);			  // Nuclear Dawn
	HookEventEx("game_end", Event_RoundEnd);			  // EmpiresMod
	HookEventEx("game_round_restart", Event_RoundEnd);	  // ZPS

	// Initialize our vote arrays
	g_Nominations_Arr = CreateArray();

	// Make listeners for player chat. Needed to recognize chat commands ("rtv", etc.)
	AddCommandListener(OnPlayerChat, "say");
	AddCommandListener(OnPlayerChat, "say2");	 // Insurgency Only
	AddCommandListener(OnPlayerChat, "say_team");

	// Fetch Cvars
	g_Cvar_MaxRounds  = FindConVar("mp_maxrounds");
	g_Cvar_FragLimit  = FindConVar("mp_fraglimit");
	g_Cvar_WinLimit	  = FindConVar("mp_winlimit");
	g_Cvar_ZpsMaxRnds = FindConVar("zps_survival_rounds");	   // ZPS only!
	g_Cvar_ZpoMaxRnds = FindConVar("zps_objective_rounds");	   // ZPS only!

	// GE:S Fix
	char game[20];
	GetGameFolderName(game, sizeof(game));
	if (StrEqual(game, "gesource", false))
	{
		g_Cvar_NextLevel = FindConVar("nextlevel");
	}

	// Load the translations file
	LoadTranslations("ultimate-mapchooser.phrases");

	// Setup our forward for when a nomination is removed
	g_Nomination_Reset_Forward = new GlobalForward("UMC_OnNominationRemoved", ET_Ignore, Param_String, Param_Cell);
	g_Reweight_Forward		   = new GlobalForward("UMC_OnReweightMap", ET_Ignore, Param_Cell, Param_String, Param_String);
	g_Reweight_Group_Forward   = new GlobalForward("UMC_OnReweightGroup", ET_Ignore, Param_Cell, Param_String);
	g_Exclude_Forward		   = new GlobalForward("UMC_OnDetermineMapExclude", ET_Hook, Param_Cell, Param_String, Param_String, Param_Cell, Param_Cell);
	g_Reload_Forward		   = new GlobalForward("UMC_RequestReloadMapcycle", ET_Ignore);
	g_Extend_Forward		   = new GlobalForward("UMC_OnMapExtended", ET_Ignore);
	g_Nextmap_Forward		   = new GlobalForward("UMC_OnNextmapSet", ET_Ignore, Param_Cell, Param_String, Param_String, Param_String);
	g_Failure_Forward		   = new GlobalForward("UMC_OnVoteFailed", ET_Ignore);
	g_MapListDisplay_Forward   = new GlobalForward("UMC_DisplayMapCycle", ET_Ignore, Param_Cell, Param_Cell);
	g_Vote_Start_Forward	   = new GlobalForward("UMC_VoteStarted", ET_Ignore, Param_String, Param_Array, Param_Cell, Param_Cell);
	g_Vote_End_Forward		   = new GlobalForward("UMC_VoteEnded", ET_Ignore, Param_String, Param_Cell);
	g_Client_Voted_Forward	   = new GlobalForward("UMC_ClientVoted", ET_Ignore, Param_String, Param_Cell, Param_Cell);
	g_Template_Forward		   = new GlobalForward("UMC_OnFormatTemplateString", ET_Ignore, Param_String, Param_Cell, Param_Cell, Param_String, Param_String);

	g_Vote_Managers			   = new StringMap();
	g_Vote_Manager_IDs		   = new ArrayList(ByteCountToCells(64));

	UMC_RegisterVoteManager("core", VM_MapVote, VM_GroupVote, VM_CancelVote, VM_IsVoteInProgress);
}

//************************************************************************************************//
//                                           GAME EVENTS                                          //
//************************************************************************************************//
// Called before any configs are executed.
public void OnMapStart()
{
	char map[MAP_LENGTH];
	GetCurrentMap(map, sizeof(map));

	LogUMCMessage("---------------------MAP CHANGE: %s---------------------", map);

	// Update the current category.
	strcopy(g_Current_Cat, sizeof(g_Current_Cat), g_Next_Cat);
	strcopy(g_Next_Cat, sizeof(g_Next_Cat), INVALID_GROUP);

	CreateTimer(5.0, UpdateTrackingCvar);

	CacheSound(g_Countdown_Sound);
}

public Action UpdateTrackingCvar(Handle timer)
{
	g_Cvar_Version.SetString(PL_VERSION, false, false);
	return Plugin_Continue;
}

// Called after all config files were executed.
public void OnConfigsExecuted()
{
	g_Reweight_Active  = false;
	g_Change_Map_Round = false;
	g_Cvar_Count_Sound.GetString(g_Countdown_Sound, sizeof(g_Countdown_Sound));
}

// Called when a player types in chat required to handle user commands.
public Action OnPlayerChat(int client, const char[] command, int argc)
{
	// Return immediately if nothing was typed.
	if (argc == 0)
	{
		return Plugin_Continue;
	}

	// Get what was typed.
	char text[13];
	GetCmdArg(1, text, sizeof(text));

	if (StrEqual(text, "umc", false) || StrEqual(text, "!umc", false) || StrEqual(text, "/umc", false))
	{
		PrintToChat(client, "[SM] Ultimate Mapchooser (UMC) Plugin v%s ", PL_VERSION);
	}
	return Plugin_Continue;
}

// Called when a client has left the server. Needed to update nominations.
public void OnClientDisconnect(int client)
{
	// Find this client in the array of clients who have entered RTV.
	int index = FindClientNomination(client);

	// Remove the client from the nomination pool if the client is in the pool to begin with.
	if (index != -1)
	{
		StringMap nomination = GetArrayCell(g_Nominations_Arr, index);
		char oldMap[MAP_LENGTH];
		GetTrieString(nomination, MAP_TRIE_MAP_KEY, oldMap, sizeof(oldMap));
		int owner;
		GetTrieValue(nomination, "client", owner);
		Call_StartForward(g_Nomination_Reset_Forward);
		Call_PushString(oldMap);
		Call_PushCell(owner);
		Call_Finish();

		// Nomination KV, local scope
		KeyValues nomKV;
		GetTrieValue(nomination, "mapcycle", nomKV);
		CloseHandle(nomKV);
		CloseHandle(nomination);
		g_Nominations_Arr.Erase(index);
	}
}

// Called when a round ends.
public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (g_Change_Map_Round)
	{
		g_Change_Map_Round = false;
		char map[MAP_LENGTH];
		GetNextMap(map, sizeof(map));
		ForceChangeInFive(map, "CORE");
	}
}

// Called at the end of a map.
public void OnMapEnd()
{
	// Empty array of nominations (and close all handles).
	ClearNominations();

	// End all votes currently in progress.
	int		  size = GetArraySize(g_Vote_Manager_IDs);
	StringMap vM;
	bool	  inProgress;
	char	  id[64];
	for (int i = 0; i < size; i++)
	{
		g_Vote_Manager_IDs.GetString(i, id, sizeof(id));
		GetTrieValue(g_Vote_Managers, id, vM);
		GetTrieValue(vM, "in_progress", inProgress);
		if (inProgress)
		{
			VoteCancelled(vM);
		}
	}
}

//************************************************************************************************//
//                                             NATIVES                                            //
//************************************************************************************************//
public any Native_UMCIsNewVoteAllowed(Handle plugin, int numParams)
{
	// Retrieve the vote manager.
	int len;
	GetNativeStringLength(1, len);
	char[] voteManagerID = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(1, voteManagerID, len + 1);
	}

	if (strlen(voteManagerID) == 0)
	{
		g_Cvar_Default_Vm.GetString(voteManagerID, len + 1);
	}

	StringMap voteManager;
	if (!GetTrieValue(g_Vote_Managers, voteManagerID, voteManager))
	{
		if (StrEqual(voteManagerID, "core"))
		{
			LogError("FATAL: Could not find core vote manager. Aborting vote.");
			return false;
		}
		LogError("Could not find a vote manager matching ID \"%s\". Using \"core\" instead.");
		if (!GetTrieValue(g_Vote_Managers, "core", voteManager))
		{
			LogError("FATAL: Could not find core vote manager. Aborting vote.");
			return false;
		}
		strcopy(voteManagerID, len + 1, "core");
	}

	bool vote_InProgress;
	GetTrieValue(voteManager, "in_progress", vote_InProgress);

	if (vote_InProgress)
	{
		return false;
	}

	return !IsVMVoteInProgress(voteManager);
}

// return int: UMC_FormatDisplayString
public any Native_UMCFormatDisplay(Handle plugin, int numParams)
{
	int		  maxlen = GetNativeCell(2);
	KeyValues kv	 = new KeyValues("umc_mapcycle");
	KvCopySubkeys(GetNativeCell(3), kv);

	int len;
	GetNativeStringLength(4, len);
	char[] map = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(4, map, len + 1);
	}

	GetNativeStringLength(5, len);
	char[] group = new char[len + 1];

	if (len > 0)
	{
		GetNativeString(5, group, len + 1);
	}

	char display[MAP_LENGTH], gDisp[MAP_LENGTH];
	kv.JumpToKey(group);
	kv.GetString("display-template", gDisp, sizeof(gDisp), "{MAP}");
	kv.GoBack();

	GetMapDisplayString(kv, group, map, gDisp, display, sizeof(display));
	CloseHandle(kv);

	return SetNativeString(1, display, maxlen);
}

// return void: UMC_VoteManagerClientVoted
public any Native_UMCVoteManagerVoted(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] id = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(1, id, len + 1);
	}
	int		  client = GetNativeCell(2);

	ArrayList option = GetNativeCell(3);

	Call_StartForward(g_Client_Voted_Forward);
	Call_PushString(id);
	Call_PushCell(client);
	Call_PushCell(option);
	Call_Finish();

	return 0;
}

// return KeyValues: UMC_FilterMapcycle
public any Native_UMCFilterMapcycle(Handle plugin, int numParams)
{
	KeyValues kv  = new KeyValues("umc_rotation");
	KeyValues arg = GetNativeCell(1);
	KvCopySubkeys(arg, kv);

	KeyValues mapcycle	   = GetNativeCell(2);

	bool	  isNom		   = GetNativeCell(3);
	bool	  forMapChange = GetNativeCell(4);

	FilterMapcycle(kv, mapcycle, isNom, forMapChange);

	return CloseAndClone(kv, plugin);
}

// return void: UMC_VoteManagerVoteCancelled
public any Native_UMCVoteManagerCancel(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] id = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(1, id, len + 1);
	}
	StringMap voteManager;
	if (!GetTrieValue(g_Vote_Managers, id, voteManager))
	{
		ThrowNativeError(SP_ERROR_PARAM, "A Vote Manager with the ID \"%s\" does not exist!", id);
		return false;
	}

	return VoteCancelled(voteManager);
}

// return void: UMC_RegisterVoteManager
public any Native_UMCRegVoteManager(Handle plugin, int numParams)
{
	StringMap voteManager;

	int len;
	GetNativeStringLength(1, len);
	char[] id = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(1, id, len + 1);
	}

	if (GetTrieValue(g_Vote_Managers, id, voteManager))
	{
		UMC_UnregisterVoteManager(id);
	}

	voteManager = new StringMap();
	SetTrieValue(g_Vote_Managers, id, voteManager);

	// NOTE: In SM 1.7.3 and on, we cannot coerce functions to values.
	// Instead, we need to create callbacks to alleviate any potential issues.
	PrivateForward mapCallback = new PrivateForward(ET_Single, Param_Cell, Param_Cell, Param_Array, Param_Cell, Param_String);
	mapCallback.AddFunction(plugin, GetNativeFunction(2));

	PrivateForward groupCallback = new PrivateForward(ET_Single, Param_Cell, Param_Cell, Param_Array, Param_Cell, Param_String);
	groupCallback.AddFunction(plugin, GetNativeFunction(3));

	PrivateForward cancelCallback = new PrivateForward(ET_Ignore);
	cancelCallback.AddFunction(plugin, GetNativeFunction(4));

	PrivateForward progressCallback = new PrivateForward(ET_Single);
	Function	   progressFunction = GetNativeFunction(5);

	if (progressFunction != INVALID_FUNCTION)
	{
		progressCallback.AddFunction(plugin, progressFunction);
	}

	SetTrieValue(voteManager, "plugin", plugin);
	SetTrieValue(voteManager, "map", mapCallback);
	SetTrieValue(voteManager, "group", groupCallback);
	SetTrieValue(voteManager, "cancel", cancelCallback);
	SetTrieValue(voteManager, "checkprogress", progressCallback);
	SetTrieValue(voteManager, "vote_storage", CreateArray());
	SetTrieValue(voteManager, "in_progress", false);
	SetTrieValue(voteManager, "active", false);
	SetTrieValue(voteManager, "total_votes", 0);
	SetTrieValue(voteManager, "prev_vote_count", 0);
	SetTrieValue(voteManager, "map_vote", CreateArray());

	g_Vote_Manager_IDs.PushString(id);

	return 0;
}

// return void: UMC_UnregisterVoteManager
public any Native_UMCUnregVoteManager(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] id = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(1, id, len + 1);
	}
	StringMap vM;

	if (!GetTrieValue(g_Vote_Managers, id, vM))
	{
		ThrowNativeError(SP_ERROR_PARAM, "A Vote Manager with the ID \"%s\" does not exist!", id);
	}

	if (UMC_IsVoteInProgress(id))
	{
		UMC_StopVote(id);
	}

	Handle hndl;
	GetTrieValue(vM, "vote_storage", hndl);
	CloseHandle(hndl);
	GetTrieValue(vM, "map_vote", hndl);
	CloseHandle(hndl);
	GetTrieValue(vM, "map", hndl);
	CloseHandle(hndl);
	GetTrieValue(vM, "group", hndl);
	CloseHandle(hndl);
	GetTrieValue(vM, "cancel", hndl);
	CloseHandle(hndl);
	GetTrieValue(vM, "checkprogress", hndl);
	CloseHandle(hndl);

	CloseHandle(vM);

	RemoveFromTrie(g_Vote_Managers, id);

	int index = FindStringInArray(g_Vote_Manager_IDs, id);
	if (index != -1)
	{
		RemoveFromArray(g_Vote_Manager_IDs, index);
	}

	if (StrEqual(id, "core", false))
	{
		UMC_RegisterVoteManager("core", VM_MapVote, VM_GroupVote, VM_CancelVote, VM_IsVoteInProgress);
	}

	return 0;
}

// return void: UMC_VoteManagerVoteCompleted
public any Native_UMCVoteManagerComplete(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] id = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(1, id, len + 1);
	}
	ArrayList voteOptions = GetNativeCell(2);

	StringMap vM;
	GetTrieValue(g_Vote_Managers, id, vM);

	StringMap		 response = ProcessVoteResults(vM, voteOptions);

	// UMC_VoteResponseHandler handler = view_as<UMC_VoteResponseHandler>(GetNativeFunction(3));
	Function		 handler  = GetNativeFunction(3);

	UMC_VoteResponse result;
	char			 param[MAP_LENGTH];
	GetTrieValue(response, "response", result);
	GetTrieString(response, "param", param, sizeof(param));

	Call_StartFunction(plugin, handler);
	Call_PushCell(result);
	Call_PushString(param);
	Call_Finish();

	Call_StartForward(g_Vote_End_Forward);
	Call_PushString(id);
	Call_PushCell(result);
	Call_Finish();

	CloseHandle(response);

	return 0;
}

// native ArrayList UMC_CreateValidMapArray(KeyValues mapcycle, KeyValues originalMapcycle, const char[] group, bool isNom, bool forMapChange);
public any Native_UMCCreateMapArray(Handle plugin, int numParams)
{
	KeyValues kv  = CreateKeyValues("umc_rotation");
	KeyValues arg = GetNativeCell(1);
	KvCopySubkeys(arg, kv);

	KeyValues mapcycle = GetNativeCell(2);

	int		  len;
	GetNativeStringLength(3, len);
	char[] group = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(3, group, len + 1);
	}
	bool	  isNom		   = GetNativeCell(4);
	bool	  forMapChange = GetNativeCell(5);

	ArrayList result	   = CreateMapArray(kv, mapcycle, group, isNom, forMapChange);

	CloseHandle(kv);

	if (result == null)
	{
		ThrowNativeError(SP_ERROR_PARAM, "Could not generate valid map array from provided mapcycle.");
	}

	// Clone all of the handles in the array to prevent memory leaks.
	ArrayList cloned = new ArrayList();

	int		  size	 = GetArraySize(result);
	Handle	  map;	  // Right?
	for (int i = 0; i < size; i++)
	{
		map = result.Get(i);
		cloned.Push(CloseAndClone(map, plugin));
	}

	CloseHandle(result);

	return CloseAndClone(cloned, plugin);
}

// Create an array of valid maps from the given mapcycle and group.
ArrayList CreateMapArray(KeyValues kv, KeyValues mapcycle, const char[] group, bool isNom, bool forMapChange)
{
	if (kv == null)
	{
		LogError("NATIVE: Cannot build map array, mapcycle is invalid.");
		return null;
	}

	bool oneSection = false;
	if (StrEqual(group, INVALID_GROUP))
	{
		if (!kv.GotoFirstSubKey())
		{
			LogError("NATIVE: Cannot build map array, mapcycle has no groups.");
			return null;
		}
	}
	else
	{
		if (!kv.JumpToKey(group))
		{
			LogError("NATIVE: Cannot build map array, mapcycle has no group '%s'", group);
			return null;
		}

		oneSection = true;
	}

	ArrayList result = new ArrayList();
	char	  mapName[MAP_LENGTH], groupName[MAP_LENGTH];
	do
	{
		kv.GetSectionName(groupName, sizeof(groupName));

		if (!kv.GotoFirstSubKey())
		{
			if (!oneSection)
			{
				continue;
			}
			else
			{
				break;
			}
		}

		do
		{
			if (IsValidMap(kv, mapcycle, groupName, isNom, forMapChange))
			{
				kv.GetSectionName(mapName, sizeof(mapName));
				PushArrayCell(result, CreateMapTrie(mapName, groupName));
			}
		}
		while (kv.GotoNextKey());

		kv.GoBack();

		if (oneSection)
		{
			break;
		}
	}
	while (kv.GotoNextKey());

	kv.GoBack();

	return result;
}

// native ArrayList UMC_CreateValidMapGroupArray(KeyValues kv, KeyValues originalMapcycle, bool isNom, bool forMapChange);
public any Native_UMCCreateGroupArray(Handle plugin, int numParams)
{
	KeyValues arg = GetNativeCell(1);
	KeyValues kv  = CreateKeyValues("umc_rotation");
	KvCopySubkeys(arg, kv);
	KeyValues mapcycle	   = GetNativeCell(2);
	bool	  isNom		   = GetNativeCell(3);
	bool	  forMapChange = GetNativeCell(4);

	ArrayList result	   = CreateMapGroupArray(kv, mapcycle, isNom, forMapChange);

	CloseHandle(kv);

	return CloseAndClone(result, plugin);
}

// Create an array of valid maps from the given mapcycle and group.
ArrayList CreateMapGroupArray(KeyValues kv, KeyValues mapcycle, bool isNom, bool forMapChange)
{
	if (!kv.GotoFirstSubKey())
	{
		LogError("NATIVE: Cannot build map array, mapcycle has no groups.");
		return null;
	}

	ArrayList result = new ArrayList(ByteCountToCells(MAP_LENGTH));
	char	  groupName[MAP_LENGTH];
	do
	{
		if (IsValidCat(kv, mapcycle, isNom, forMapChange))
		{
			kv.GetSectionName(groupName, sizeof(groupName));
			PushArrayString(result, groupName);
		}
	}
	while (kv.GotoNextKey());

	kv.GoBack();

	return result;
}

// native bool UMC_IsMapNominated(const char[] map, const char[] group);
public any Native_UMCIsMapNominated(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] map = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(1, map, len + 1);
	}
	GetNativeStringLength(2, len);
	char[] group = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(2, group, len + 1);
	}
	return FindNominationIndex(map, group) != -1;
}

// native bool UMC_NominateMap(KeyValues mapcycle, const char[] map, const char[] group, int client, const char[] nominationGroup = INVALID_GROUP);
public any Native_UMCNominateMap(Handle plugin, int numParams)
{
	KeyValues kv = CreateKeyValues("umc_rotation");
	KvCopySubkeys(GetNativeCell(1), kv);

	int len;
	GetNativeStringLength(2, len);
	char[] map = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(2, map, len + 1);
	}

	GetNativeStringLength(3, len);
	char[] group = new char[len + 1];

	if (len > 0)
	{
		GetNativeString(3, group, len + 1);
	}

	char nomGroup[MAP_LENGTH];
	if (numParams > 4)
	{
		GetNativeStringLength(5, len);
		if (len > 0)
		{
			GetNativeString(5, nomGroup, sizeof(nomGroup));
		}
	}
	else
	{
		strcopy(nomGroup, sizeof(nomGroup), INVALID_GROUP);
	}

	return InternalNominateMap(kv, map, group, GetNativeCell(4), nomGroup);
}

// native AddWeightModifier(MapWeightModifier:func);
public any Native_UMCAddWeightModifier(Handle plugin, int numParams)
{
	if (g_Reweight_Active)
	{
		g_Current_Weight *= GetNativeCell(1);
	}
	else
	{
		LogError("REWEIGHT: Attempted to add weight modifier outside of UMC_OnReweightMap forward.");
	}

	return 0;
}

// native bool UMC_StartVote( ...20+ params... );
public any Native_UMCStartVote(Handle plugin, int numParams)
{
	// Retrieve the many, many parameters.
	int len;
	GetNativeStringLength(1, len);
	char[] voteManagerID = new char[len + 1];

	if (len > 0)
	{
		GetNativeString(1, voteManagerID, len + 1);
	}

	if (strlen(voteManagerID) == 0)
	{
		g_Cvar_Default_Vm.GetString(voteManagerID, len + 1);
	}
	StringMap voteManager;

	if (!GetTrieValue(g_Vote_Managers, voteManagerID, voteManager))
	{
		if (StrEqual(voteManagerID, "core"))
		{
			LogError("FATAL: Could not find core vote manager. Aborting vote.");
			return false;
		}

		LogError("Could not find a vote manager matching ID \"%s\". Using \"core\" instead.");
		if (!GetTrieValue(g_Vote_Managers, "core", voteManager))
		{
			LogError("FATAL: Could not find core vote manager. Aborting vote.");
			return false;
		}
		strcopy(voteManagerID, len + 1, "core");
	}

	bool vote_inprogress;
	GetTrieValue(voteManager, "in_progress", vote_inprogress);

	if (vote_inprogress)
	{
		LogError("Cannot start a vote, vote manager \"%s\" already has a vote in progress.", voteManagerID);
		return false;
	}

	// Get the name of the calling plugin.
	char stored_reason[PLATFORM_MAX_PATH];
	GetPluginFilename(plugin, stored_reason, sizeof(stored_reason));
	SetTrieString(voteManager, "stored_reason", stored_reason);
	KeyValues	 kv		  = GetNativeCell(2);
	KeyValues	 mapcycle = GetNativeCell(3);
	UMC_VoteType type	  = GetNativeCell(4);
	int			 time	  = GetNativeCell(5);
	bool		 scramble = GetNativeCell(6);

	GetNativeStringLength(7, len);
	char[] startSound = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(7, startSound, len + 1);
	}

	GetNativeStringLength(8, len);
	char[] endSound = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(8, endSound, len + 1);
	}

	bool				 extend			  = GetNativeCell(9);
	float				 timestep		  = GetNativeCell(10);
	int					 roundstep		  = GetNativeCell(11);
	int					 fragstep		  = GetNativeCell(12);
	bool				 dontChange		  = GetNativeCell(13);
	float				 threshold		  = GetNativeCell(14);
	UMC_ChangeMapTime	 successAction	  = GetNativeCell(15);
	UMC_VoteFailAction	 failAction		  = GetNativeCell(16);
	int					 maxRunoffs		  = GetNativeCell(17);
	int					 maxRunoffMaps	  = GetNativeCell(18);
	UMC_RunoffFailAction runoffFailAction = GetNativeCell(19);

	GetNativeStringLength(20, len);
	char[] runoffSound = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(20, runoffSound, len + 1);
	}

	bool nominationStrictness = GetNativeCell(21);
	bool allowDuplicates	  = GetNativeCell(22);

	int	 voteClients[MAXPLAYERS + 1];
	GetNativeArray(23, voteClients, sizeof(voteClients));
	int	 numClients		   = GetNativeCell(24);

	bool runExclusionCheck = (numParams >= 25) ? (GetNativeCell(25)) : true;

	// OK now that that's done, let's save 'em.
	SetTrieValue(voteManager, "stored_type", type);
	SetTrieValue(voteManager, "stored_scramble", scramble);
	SetTrieValue(voteManager, "stored_ignoredupes", allowDuplicates);
	SetTrieValue(voteManager, "stored_strictnoms", nominationStrictness);

	switch (failAction)
	{
		case VoteFailAction_Nothing:
		{
			SetTrieValue(voteManager, "stored_fail_action", RunoffFailAction_Nothing);
			SetTrieValue(voteManager, "remaining_runoffs", 0);
		}
		case VoteFailAction_Runoff:
		{
			SetTrieValue(voteManager, "stored_fail_action", runoffFailAction);
			SetTrieValue(voteManager, "remaining_runoffs", (maxRunoffs == 0) ? -1 : maxRunoffs);
		}
	}

	SetTrieValue(voteManager, "extend_timestep", timestep);
	SetTrieValue(voteManager, "extend_roundstep", roundstep);
	SetTrieValue(voteManager, "extend_fragstep", fragstep);
	SetTrieValue(voteManager, "stored_threshold", threshold);
	SetTrieValue(voteManager, "stored_runoffmaps_max", maxRunoffMaps);
	SetTrieValue(voteManager, "stored_votetime", time);

	SetTrieValue(voteManager, "change_map_when", successAction);

	KeyValues stored_kv = new KeyValues("umc_rotation");
	KvCopySubkeys(kv, stored_kv);
	SetTrieValue(voteManager, "stored_kv", stored_kv);

	KeyValues stored_mapcycle = new KeyValues("umc_rotation");
	KvCopySubkeys(mapcycle, stored_mapcycle);
	SetTrieValue(voteManager, "stored_mapcycle", stored_mapcycle);

	SetTrieString(voteManager, "stored_start_sound", startSound);
	SetTrieString(voteManager, "stored_end_sound", endSound);
	SetTrieString(voteManager, "stored_runoff_sound", (strlen(runoffSound) > 0) ? runoffSound : startSound);

	int users[MAXPLAYERS + 1];
	ConvertClientsToUserIDs(voteClients, users, numClients);
	SetTrieArray(voteManager, "stored_users", users, numClients);
	SetTrieValue(voteManager, "stored_exclude", runExclusionCheck);

	// Make the vote menu.
	ArrayList options = BuildVoteItems(voteManager, stored_kv, stored_mapcycle, type, scramble, allowDuplicates, nominationStrictness, runExclusionCheck, extend, dontChange);

	// Run the vote if the menu was created successfully.
	if (options != null)
	{
		bool vote_active = PerformVote(voteManager, type, options, time, voteClients, numClients, startSound);
		if (vote_active)
		{
			Call_StartForward(g_Vote_Start_Forward);
			Call_PushString(voteManagerID);
			Call_PushArray(voteClients, numClients);
			Call_PushCell(numClients);
			Call_PushCell(options);
			Call_Finish();
		}
		else
		{
			DeleteVoteParams(voteManager);
			ClearVoteArrays(voteManager);
		}

		FreeOptions(options);
		return vote_active;
	}
	else
	{
		DeleteVoteParams(voteManager);
		return false;
	}
}

// native bool UMC_GetRandomMap(KeyValues mapcycle, KeyValues originalMapcycle, const char[] group, char[] buffer, int size, char[] groupBuffer, gBufferSize, bool isNomination, bool forMapChange);
public any Native_UMCGetRandomMap(Handle plugin, int numParams)
{
	KeyValues kv	   = GetNativeCell(1);
	KeyValues filtered = new KeyValues("umc_rotation");
	KvCopySubkeys(kv, filtered);

	KeyValues mapcycle = GetNativeCell(2);
	int		  len;
	GetNativeStringLength(3, len);
	char[] group = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(3, group, len + 1);
	}

	bool isNom		  = GetNativeCell(8);
	bool forMapChange = GetNativeCell(9);

	FilterMapcycle(filtered, mapcycle, isNom, forMapChange);
	WeightMapcycle(filtered, mapcycle);

	char map[MAP_LENGTH], groupResult[MAP_LENGTH];
	bool result = GetRandomMapFromCycle(filtered, group, map, sizeof(map), groupResult, sizeof(groupResult));

	CloseHandle(filtered);

	if (result)
	{
		SetNativeString(4, map, GetNativeCell(5), false);
		SetNativeString(6, groupResult, GetNativeCell(7), false);
		return true;
	}
	return false;
}

// native void UMC_SetNextMap(KeyValues mapcycle, const char[] map, const char[] group, UMC_ChangeMapTime when);
public any Native_UMCSetNextMap(Handle plugin, int numParams)
{
	KeyValues kv = GetNativeCell(1);

	int		  len;
	GetNativeStringLength(2, len);
	char[] map = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(2, map, len + 1);
	}
	GetNativeStringLength(3, len);
	char[] group = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(3, group, len + 1);
	}
	if (!IsMapValid(map))
	{
		LogError("SETMAP: Map %s is invalid!", map);
		return 0;
	}

	UMC_ChangeMapTime when = GetNativeCell(4);

	char			  reason[PLATFORM_MAX_PATH];
	GetPluginFilename(plugin, reason, sizeof(reason));

	DoMapChange(when, kv, map, group, reason, map);

	return 0;
}

public any Native_UMCIsVoteInProgress(Handle plugin, int numParams)
{
	if (numParams > 0)
	{
		int len;
		GetNativeStringLength(1, len);
		char[] voteManagerID = new char[len + 1];
		if (len > 0)
		{
			GetNativeString(1, voteManagerID, len + 1);
		}

		if (strlen(voteManagerID) > 0)
		{
			bool	  inProgress;
			StringMap vM;
			if (!GetTrieValue(g_Vote_Managers, voteManagerID, vM))
			{
				ThrowNativeError(SP_ERROR_PARAM, "A Vote Manager with the ID \"%s\" does not exist!", voteManagerID);
			}
			GetTrieValue(vM, "in_progress", inProgress);
			return inProgress;
		}
	}
	char	  buffer[64];
	int		  size = GetArraySize(g_Vote_Manager_IDs);
	StringMap vM;
	bool	  inProgress;
	for (int i = 0; i < size; i++)
	{
		g_Vote_Manager_IDs.GetString(i, buffer, sizeof(buffer));
		GetTrieValue(g_Vote_Managers, buffer, vM);
		GetTrieValue(vM, "in_progress", inProgress);
		if (inProgress)
		{
			return true;
		}
	}
	return false;
}

//"sm_umc_stopvote"
public any Native_UMCStopVote(Handle plugin, int numParams)
{
	return Native_UMCVoteManagerCancel(plugin, numParams);
}

// native bool UMC_IsMapValid(KeyValues mapcycle, const char[] map, const char[] group, bool isNom, bool forMapChange);
public any Native_UMCIsMapValid(Handle plugin, int numParams)
{
	KeyValues arg = GetNativeCell(1);
	KeyValues kv  = new KeyValues("umc_rotation");
	KvCopySubkeys(arg, kv);

	int len;
	GetNativeStringLength(2, len);
	char[] map = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(2, map, len + 1);
	}
	GetNativeStringLength(3, len);
	char[] group = new char[len + 1];
	if (len > 0)
	{
		GetNativeString(3, group, len + 1);
	}
	bool isNom		  = GetNativeCell(4);
	bool forMapChange = GetNativeCell(5);

	if (!kv.JumpToKey(group))
	{
		LogError("NATIVE: No group '%s' in mapcycle.", group);
		return false;
	}
	if (!kv.JumpToKey(map))
	{
		LogError("NATIVE: No map %s found in group '%s'", map, group);
		return false;
	}

	return IsValidMap(kv, arg, group, isNom, forMapChange);
}

public any Native_UMCGetCurrentGroup(Handle plugin, int numParams)
{
	SetNativeString(1, g_Current_Cat, GetNativeCell(2), false);
	return 0;
}

//************************************************************************************************//
//                                            COMMANDS                                            //
//************************************************************************************************//
public Action Command_DisplayMapLists(int client, int args)
{
	bool filtered;
	if (args < 1)
	{
		filtered = false;
	}
	else
	{
		char arg[5];
		GetCmdArg(1, arg, sizeof(arg));
		filtered = StringToInt(arg) > 0;
	}

	PrintToConsole(client, "UMC Maplists:");

	Call_StartForward(g_MapListDisplay_Forward);
	Call_PushCell(client);
	Call_PushCell(filtered);
	Call_Finish();

	return Plugin_Handled;
}

public Action Command_MapHistory(int client, int args)
{
	PrintToConsole(client, "Map History:");

	int	 size = GetMapHistorySize();
	char map[MAP_LENGTH], reason[100], timeString[100];
	int	 time;
	for (int i = 0; i < size; i++)
	{
		GetMapHistory(i, map, sizeof(map), reason, sizeof(reason), time);
		FormatTime(timeString, sizeof(timeString), NULL_STRING, time);
		ReplyToCommand(client, "%02i. %s : %s : %s", i + 1, map, reason, timeString);
	}
	return Plugin_Handled;
}

// Called when the command to set the nextmap is called.
public Action Command_SetNextmap(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[UMC] Usage: sm_setnextmap <map> <0|1|2>\n 0 - Change Now\n 1 - Change at end of round\n 2 - Change at end of map.");
		return Plugin_Handled;
	}

	char map[MAP_LENGTH];
	GetCmdArg(1, map, sizeof(map));

	if (!IsMapValid(map))
	{
		ReplyToCommand(client, "[UMC] Map '%s' was not found.", map);
		return Plugin_Handled;
	}

	UMC_ChangeMapTime when = ChangeMapTime_MapEnd;
	if (args > 1)
	{
		char whenArg[2];
		GetCmdArg(2, whenArg, sizeof(whenArg));
		when = view_as<UMC_ChangeMapTime>(StringToInt(whenArg));
	}

	// DisableVoteInProgress(id);
	DoMapChange(when, null, map, INVALID_GROUP, "sm_setnextmap", map);

	// TODO: Make this a translation
	ShowActivity(client, "Changed nextmap to \"%s\".", map);
	LogUMCMessage("%L changed nextmap to \"%s\"", client, map);

	// vote_completed = true;

	return Plugin_Handled;
}

// Called when the command to reload the mapcycle has been triggered.
public Action Command_Reload(int client, int args)
{
	// Call the reload forward.
	Call_StartForward(g_Reload_Forward);
	Call_Finish();

	ReplyToCommand(client, "[UMC] UMC Mapcycles Reloaded.");

	// Return success
	return Plugin_Handled;
}

//"sm_umc_stopvote"
public Action Command_StopVote(int client, int args)
{
	// End all votes currently in progress.
	int		  size = GetArraySize(g_Vote_Manager_IDs);
	StringMap vM;
	bool	  inProgress;
	char	  id[64];
	bool	  stopped = false;
	for (int i = 0; i < size; i++)
	{
		GetArrayString(g_Vote_Manager_IDs, i, id, sizeof(id));
		GetTrieValue(g_Vote_Managers, id, vM);
		GetTrieValue(vM, "in_progress", inProgress);
		if (inProgress)
		{
			// DEBUG_MESSAGE("Ending vote in progress: %s", id)
			stopped = true;
			VoteCancelled(vM);
		}
	}
	if (!stopped)
	{
		ReplyToCommand(client, "[UMC] No map vote running!");	 // TODO Translation?
	}
	return Plugin_Handled;
}

//************************************************************************************************//
//                                        CORE VOTE MANAGER                                       //
//************************************************************************************************//
bool core_vote_active;

public bool VM_IsVoteInProgress()
{
	return IsVoteInProgress();
}

public Action VM_MapVote(int duration, ArrayList vote_items, const int[] clients, int numClients, const char[] startSound)
{
	if (VM_IsVoteInProgress())
	{
		LogUMCMessage("Could not start core vote, another SM vote is already in progress.");
		return Plugin_Stop;
	}

	bool verboseLogs = g_Cvar_Logging.BoolValue;

	if (verboseLogs)
	{
		LogUMCMessage("Adding Clients to Vote:");
	}
	int clientArr[MAXPLAYERS + 1];
	int count = 0;
	int client;
	for (int i = 0; i < numClients; i++)
	{
		client = clients[i];
		if (client != 0 && IsClientInGame(client))
		{
			if (verboseLogs)
			{
				LogUMCMessage("%i: %N (%i)", i, client, client);
			}
			clientArr[count++] = client;
		}
	}

	if (count == 0)
	{
		LogUMCMessage("Could not start core vote, no players to display vote to!");
		return Plugin_Stop;
	}

	Menu menu = BuildVoteMenu(vote_items, "Map Vote Menu Title", Handle_MapVoteResults);

	core_vote_active = (menu != null && VoteMenu(menu, clientArr, count, duration));

	if (core_vote_active)
	{
		if (strlen(startSound) > 0)
		{
			EmitSoundToAllAny(startSound);
		}
		return Plugin_Continue;
	}
	else
	{
		LogError("Could not start core vote.");
		return Plugin_Stop;
	}
}

public Action VM_GroupVote(int duration, ArrayList vote_items, const int[] clients, int numClients, const char[] startSound)
{
	if (VM_IsVoteInProgress())
	{
		LogUMCMessage("Could not start core vote, another SM vote is already in progress.");
		return Plugin_Stop;
	}

	bool verboseLogs = g_Cvar_Logging.BoolValue;

	if (verboseLogs)
	{
		LogUMCMessage("Adding Clients to Vote:");
	}
	int clientArr[MAXPLAYERS + 1];
	int count = 0;
	int client;
	for (int i = 0; i < numClients; i++)
	{
		client = clients[i];
		if (client != 0 && IsClientInGame(client))
		{
			if (verboseLogs)
			{
				LogUMCMessage("%i: %N (%i)", i, client, client);
			}
			clientArr[count++] = client;
		}
	}

	if (count == 0)
	{
		LogUMCMessage("Could not start core vote, no players to display vote to!");
		return Plugin_Stop;
	}

	Menu menu = BuildVoteMenu(vote_items, "Group Vote Menu Title", Handle_MapVoteResults);
	core_vote_active = true;

	if (menu != null && VoteMenu(menu, clientArr, count, duration))
	{
		if (strlen(startSound) > 0)
		{
			EmitSoundToAllAny(startSound);
		}
		return Plugin_Continue;
	}

	core_vote_active = false;
	LogError("Could not start core vote.");
	return Plugin_Stop;
}

Menu BuildVoteMenu(ArrayList vote_items, const char[] title, VoteHandler callback)
{
	bool verboseLogs = g_Cvar_Logging.BoolValue;

	if (verboseLogs)
	{
		LogUMCMessage("VOTE MENU:");
	}

	// Begin creating menu
	Menu menu = g_Cvar_ValveMenu.BoolValue ? CreateMenuEx(GetMenuStyleHandle(MenuStyle_Valve), Handle_VoteMenu, MenuAction_DisplayItem | MenuAction_Display) : CreateMenu(Handle_VoteMenu, MenuAction_DisplayItem | MenuAction_Display);

	SetVoteResultCallback(menu, callback);	  // Set callback
	SetMenuExitButton(menu, false);			  // Don't want an exit button.

	// Set the title
	SetMenuTitle(menu, title);

	// Keep track of slots taken up in the vote.
	int blockSlots = GetConVarInt(g_Cvar_Block_Slots);
	int voteSlots  = blockSlots;

	if (g_Cvar_NoVote.BoolValue)
	{
		SetMenuOptionFlags(menu, MENUFLAG_BUTTON_NOVOTE);
		voteSlots++;

		if (verboseLogs)
		{
			LogUMCMessage("1: No Vote");
		}
	}

	// Add blocked slots if the cvar for blocked slots is enabled.
	AddSlotBlockingToMenu(menu, blockSlots);
	int size = GetArraySize(vote_items);

	// Throw an error and return nothing if the number of items in the vote is less than 2 (hence no point in voting).
	if (size <= 1)
	{
		LogError("VOTING: Not enough options to run a vote. %i options available.", size);
		CloseHandle(menu);
		return null;
	}

	StringMap voteItem;
	char	  info[MAP_LENGTH], display[MAP_LENGTH];
	for (int i = 0; i < size; i++)
	{
		voteSlots++;
		voteItem = vote_items.Get(i);
		GetTrieString(voteItem, "info", info, sizeof(info));
		GetTrieString(voteItem, "display", display, sizeof(display));
		AddMenuItem(menu, info, display);

		if (verboseLogs)
		{
			LogUMCMessage("%i: %s (%s)", voteSlots, display, info);
		}
	}

	SetCorrectMenuPagination(menu, voteSlots);

	return menu;	// Return the finished menu.
}

public void VM_CancelVote()
{
	if (core_vote_active)
	{
		core_vote_active = false;
		CancelVote();
	}
}

// Adds slot blocking to a menu
void AddSlotBlockingToMenu(Menu menu, int blockSlots)
{
	// Add blocked slots if the cvar for blocked slots is enabled.
	if (blockSlots > 3)
	{
		AddMenuItem(menu, NOTHING_OPTION, "", ITEMDRAW_SPACER);
	}
	if (blockSlots > 0)
	{
		AddMenuItem(menu, NOTHING_OPTION, "Slot Block Message 1", ITEMDRAW_DISABLED);
	}
	if (blockSlots > 1)
	{
		AddMenuItem(menu, NOTHING_OPTION, "Slot Block Message 2", ITEMDRAW_DISABLED);
	}
	if (blockSlots > 2)
	{
		AddMenuItem(menu, NOTHING_OPTION, "", ITEMDRAW_SPACER);
	}
	if (blockSlots > 4)
	{
		AddMenuItem(menu, NOTHING_OPTION, "", ITEMDRAW_SPACER);
	}
}

// Called when a vote has finished.
public int Handle_VoteMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			Panel panel = view_as<Panel>(param2);

			char  phrase[255];
			GetMenuTitle(menu, phrase, sizeof(phrase));

			char buffer[255];
			FormatEx(buffer, sizeof(buffer), "%T", phrase, param1);

			SetPanelTitle(panel, buffer);
		}
		case MenuAction_Select:
		{
			if (g_Cvar_Logging.BoolValue)
			{
				LogUMCMessage("%L selected menu item %i", param1, param2);
			}
			UMC_VoteManagerClientVoted("core", param1, null);
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
			if (g_Cvar_Logging.BoolValue)
			{
				LogUMCMessage("Vote has concluded.");
			}
		}
		case MenuAction_VoteCancel:
		{
			if (core_vote_active)
			{
				// Vote was cancelled generically, notify UMC.
				core_vote_active = false;
				UMC_VoteManagerVoteCancelled("core");
			}
		}
		case MenuAction_DisplayItem:
		{
			char map[MAP_LENGTH], display[MAP_LENGTH];
			GetMenuItem(menu, param2, map, sizeof(map), _, display, sizeof(display));

			if (StrEqual(map, EXTEND_MAP_OPTION) || StrEqual(map, DONT_CHANGE_OPTION) || (StrEqual(map, NOTHING_OPTION) && strlen(display) > 0))
			{
				char buffer[255];
				FormatEx(buffer, sizeof(buffer), "%T", display, param1);

				return RedrawMenuItem(buffer);
			}
		}
	}
	return 0;
}

// Handles the results of a vote.
public void Handle_MapVoteResults(Menu menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	core_vote_active  = false;
	ArrayList results = ConvertVoteResults(menu, num_clients, client_info, num_items, item_info);
	UMC_VoteManagerVoteCompleted("core", results, Handle_Response);

	// Free Memory
	int		  size = GetArraySize(results);
	StringMap item;
	ArrayList clients;
	for (int i = 0; i < size; i++)
	{
		item = results.Get(i);
		GetTrieValue(item, "clients", clients);
		CloseHandle(clients);
		CloseHandle(item);
	}
	CloseHandle(results);
}

public void Handle_Response(UMC_VoteResponse response, const char[] param)
{
	// Do Nothing
}

// Converts results of a vote to the format required for UMC to process votes.
ArrayList ConvertVoteResults(Menu menu, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	ArrayList result = new ArrayList();
	int		  itemIndex;
	StringMap voteItem;
	ArrayList voteClientArray;
	char	  info[MAP_LENGTH], disp[MAP_LENGTH];
	for (int i = 0; i < num_items; i++)
	{
		itemIndex = item_info[i][VOTEINFO_ITEM_INDEX];
		GetMenuItem(menu, itemIndex, info, sizeof(info), _, disp, sizeof(disp));

		voteItem		= new StringMap();
		voteClientArray = new ArrayList();

		SetTrieString(voteItem, "info", info);
		SetTrieString(voteItem, "display", disp);
		SetTrieValue(voteItem, "clients", voteClientArray);

		PushArrayCell(result, voteItem);

		for (int j = 0; j < num_clients; j++)
		{
			if (client_info[j][VOTEINFO_CLIENT_ITEM] == itemIndex)
			{
				PushArrayCell(voteClientArray, client_info[j][VOTEINFO_CLIENT_INDEX]);
			}
		}
	}
	return result;
}

//************************************************************************************************//
//                                        VOTING UTILITIES                                        //
//************************************************************************************************//
void DisableVoteInProgress(StringMap vM)
{
	SetTrieValue(vM, "in_progress", false);
}

void FreeOptions(ArrayList options)
{
	int	   size = GetArraySize(options);
	Handle item;
	for (int i = 0; i < size; i++)
	{
		item = options.Get(i);
		CloseHandle(item);
	}
	CloseHandle(options);
}

bool IsVMVoteInProgress(StringMap voteManager)
{
	PrivateForward progressCheck;
	GetTrieValue(voteManager, "checkprogress", progressCheck);
	bool result;

	if (GetForwardFunctionCount(progressCheck) == 0)
	{
		result = IsVoteInProgress();
	}
	else
	{
		Call_StartForward(progressCheck);
		Call_Finish(result);
	}

	return result;
}

bool PerformVote(StringMap voteManager, UMC_VoteType type, ArrayList options, int time, const int[] clients, int numClients, const char[] startSound)
{
	PrivateForward handler;
	switch (type)
	{
		case VoteType_Map:
		{
			LogUMCMessage("Initiating Vote Type: Map");
			GetTrieValue(voteManager, "map", handler);
		}
		case VoteType_Group:
		{
			LogUMCMessage("Initiating Vote Type: Group");
			GetTrieValue(voteManager, "group", handler);
		}
		case VoteType_Tier:
		{
			LogUMCMessage("Initiating Vote Type: Stage 1 Tiered");
			GetTrieValue(voteManager, "group", handler);
		}
	}

	Action result;
	Call_StartForward(handler);
	Call_PushCell(time);
	Call_PushCell(options);
	Call_PushArray(clients, numClients);
	Call_PushCell(numClients);
	Call_PushString(startSound);
	Call_Finish(result);

	bool started = (result == Plugin_Continue);

	if (started)
	{
		SetTrieValue(voteManager, "in_progress", true);
		SetTrieValue(voteManager, "active", true);
	}

	return started;
}

enum UMC_BuildOptionsError
{
	BuildOptionsError_InvalidMapcycle,
	BuildOptionsError_NoMapGroups,
	BuildOptionsError_NotEnoughOptions,
	BuildOptionsError_Success
};

// Build and returns a new vote menu.
ArrayList BuildVoteItems(StringMap vM, KeyValues kv, KeyValues mapcycle, UMC_VoteType &type, bool scramble, bool allowDupes, bool strictNoms, bool exclude, bool extend, bool dontChange)
{
	ArrayList			  result = new ArrayList();
	UMC_BuildOptionsError error;

	switch (type)
	{
		case VoteType_Map:
		{
			error = BuildMapVoteItems(vM, result, kv, mapcycle, scramble, extend, dontChange, allowDupes, strictNoms, .exclude = exclude);
		}
		case VoteType_Group:
		{
			error = BuildCatVoteItems(vM, result, kv, mapcycle, scramble, extend, dontChange, strictNoms, exclude);
		}
		case VoteType_Tier:
		{
			error = BuildCatVoteItems(vM, result, kv, mapcycle, scramble, extend, dontChange, strictNoms, exclude);
		}
	}

	if ((type == VoteType_Group || type == VoteType_Tier) && error == BuildOptionsError_NotEnoughOptions)
	{
		type  = VoteType_Map;
		error = BuildMapVoteItems(vM, result, kv, mapcycle, scramble, extend, dontChange, allowDupes, strictNoms, .exclude = exclude);
	}

	if (error == BuildOptionsError_InvalidMapcycle || error == BuildOptionsError_NoMapGroups)
	{
		CloseHandle(result);
		result = null;
	}

	return result;
}

// Builds and returns a menu for a map vote.
UMC_BuildOptionsError BuildMapVoteItems(StringMap voteManager, ArrayList result, KeyValues okv, KeyValues mapcycle, bool scramble, bool extend, bool dontChange, bool ignoreDupes = false, bool strictNoms = false, bool ignoreInvoteSetting = false, bool exclude = true)
{
	// Throw an error and return nothing if the mapcycle is invalid.
	if (okv == null)
	{
		LogError("VOTING: Cannot build map vote menu, rotation file is invalid.");
		return BuildOptionsError_InvalidMapcycle;
	}

	// Duplicate the kv handle, because we will be deleting some keys.
	okv.Rewind();									 // rewind original
	KeyValues kv = new KeyValues("umc_rotation");	 // new handle
	KvCopySubkeys(okv, kv);							 // copy everything to the new handle

	// Filter mapcycle
	if (exclude)
	{
		FilterMapcycle(kv, mapcycle, .deleteEmpty = true);
	}

	// Log an error and return nothing if it cannot find a category.
	if (!kv.GotoFirstSubKey())
	{
		LogError("VOTING: No map groups found in rotation. Vote menu was not built.");
		CloseHandle(kv);
		return BuildOptionsError_NoMapGroups;
	}

	ClearVoteArrays(voteManager);

	// Determine how we're logging
	bool	  verboseLogs = g_Cvar_Logging.BoolValue;

	// Buffers
	char	  mapName[MAP_LENGTH];	  // Name of the map
	char	  display[MAP_LENGTH];	  // String to be displayed in the vote
	char	  gDisp[MAP_LENGTH];
	char	  catName[MAP_LENGTH];	  // Name of the category.

	// Other variables
	int		  voteCounter = 0;		 // Number of maps in the vote currently
	int		  numNoms	  = 0;		 // Number of nominated maps in the vote.
	ArrayList nominationsFromCat;	 // adt_array containing all nominations from the current category.
	ArrayList tempCatNoms;
	StringMap trie;			// a nomination
	ArrayList nameArr;		// adt_array of map names from nominations
	ArrayList weightArr;	// adt_array of map weights from nominations.

	ArrayList map_vote;
	GetTrieValue(voteManager, "map_vote", map_vote);

	ArrayList map_vote_display = new ArrayList(ByteCountToCells(MAP_LENGTH));

	int		  nomIndex, position, numMapsFromCat, nomCounter, inVote, index;	//, cIndex;

	int		  tierAmount = g_Cvar_Vote_TierAmount.IntValue;

	KeyValues nomKV;
	char	  nomGroup[MAP_LENGTH];

	// Add maps to vote array from current category.
	do
	{
		WeightMapGroup(kv, mapcycle);

		// Store the name of the current category.
		KvGetSectionName(kv, catName, sizeof(catName));

		// Get the map-display template from the categeory definition.
		KvGetString(kv, "display-template", gDisp, sizeof(gDisp), "{MAP}");

		// Get all nominations for the current category.
		if (exclude)
		{
			tempCatNoms = GetCatNominations(catName);
			nominationsFromCat = FilterNominationsArray(tempCatNoms);
			CloseHandle(tempCatNoms);
		}
		else
		{
			nominationsFromCat = GetCatNominations(catName);
		}
		// Get the amount of nominations for the current category.
		numNoms = GetArraySize(nominationsFromCat);

		// Get the total amount of maps to appear in the vote from this category.
		inVote	= ignoreInvoteSetting ? tierAmount : KvGetNum(kv, "maps_invote", 1);

		if (verboseLogs)
		{
			if (ignoreInvoteSetting)
			{
				LogUMCMessage("VOTE MENU: (Verbose) Second stage tiered vote. See cvar \"sm_umc_vote_tieramount.\"");
			}
			LogUMCMessage("VOTE MENU: (Verbose) Fetching %i maps from group '%s'", inVote, catName);
		}

		// Calculate the number of maps we still need to fetch from the mapcycle.
		numMapsFromCat = inVote - numNoms;

		// Populate vote with nomination maps from this category if we do not need to fetch any maps from the mapcycle AND
		// the number of nominated maps in the vote is limited to the maps_invote setting for the category.
		if (numMapsFromCat < 0 && strictNoms)
		{
			//////
			// The piece of code inside this block is for the case where the current category's
			// nominations exceeds it's number of maps allowed in the vote.
			//
			// In order to solve this problem, we first fetch all nominations where the map has
			// appropriate min and max players for the amount of players on the server, and then
			// randomly pick from this pool based on the weights if the maps, until the number
			// of maps in the vote from this category is reached.
			//////
			if (verboseLogs)
			{
				LogUMCMessage(
					"VOTE MENU: (Verbose) Number of nominations (%i) exceeds allowable maps in vote for the map group '%s'. Limiting nominated maps to %i. (See cvar \"sm_umc_nominate_strict\")",
					numNoms, catName, inVote);
			}

			// No nominations have been fetched from pool of possible nomination.
			nomCounter = 0;

			// Populate vote array with nominations from this category if we have nominations from this category.
			if (numNoms > 0)
			{
				// Initialize name and weight adt_arrays.
				nameArr			   = new ArrayList(ByteCountToCells(MAP_LENGTH));
				weightArr		   = new ArrayList();
				ArrayList cycleArr = new ArrayList();

				// Store data from a nomination for each index of the adt_array of nominations from this category.
				for (int i = 0; i < numNoms; i++)
				{
					// Store nomination.
					trie = GetArrayCell(nominationsFromCat, i);

					// Get the map name from the nomination.
					GetTrieString(trie, MAP_TRIE_MAP_KEY, mapName, sizeof(mapName));

					// Add map to list of possible maps to be added to vote from the nominations
					// if the map is valid (correct number of players, correct time)
					if (!ignoreDupes && FindStringInVoteArray(mapName, MAP_TRIE_MAP_KEY, map_vote) != -1)
					{
						if (verboseLogs)
						{
							LogUMCMessage("VOTE MENU: (Verbose) Skipping nominated map '%s' from map group '%s' because it already is in the vote.", mapName, catName);
						}
					}
					else
					{
						// Increment number of noms fetched.
						nomCounter++;

						// Fetch mapcycle for weighting
						GetTrieValue(trie, "mapcycle", nomKV);

						// Add map name to the pool.
						PushArrayString(nameArr, mapName);

						// Add map weight to the pool.
						PushArrayCell(weightArr, GetMapWeight(nomKV, mapName, catName));
						PushArrayCell(cycleArr, trie);
					}
				}

				// Populate vote array with maps from the pool if the number of nominations fetched is greater than zero.
				if (nomCounter > 0)
				{
					// Add a nominated map from the pool into the vote arrays for the number of available spots there are from the category.
					int min = (inVote < nomCounter) ? inVote : nomCounter;

					for (int i = 0; i < min; i++)
					{
						// Get a random map from the pool.
						GetWeightedRandomSubKey(mapName, sizeof(mapName), weightArr, nameArr, index);
						StringMap nom = cycleArr.Get(index);
						GetTrieValue(nom, "mapcycle", nomKV);
						GetTrieString(nom, "nom_group", nomGroup, sizeof(nomGroup));

						// Get the position in the vote array to add the map to
						position = GetNextMenuIndex(voteCounter, scramble);

						// Template
						KeyValues dispKV = new KeyValues("umc_mapcycle");
						KvCopySubkeys(nomKV, dispKV);
						GetMapDisplayString(dispKV, nomGroup, mapName, gDisp, display, sizeof(display));
						CloseHandle(dispKV);

						StringMap map		  = CreateMapTrie(mapName, catName);
						KeyValues nomMapcycle = new KeyValues("umc_mapcycle");
						KvCopySubkeys(nomKV, nomMapcycle);
						SetTrieValue(map, "mapcycle", nomMapcycle);

						InsertArrayCell(map_vote, position, map);
						InsertArrayString(map_vote_display, position, display);

						// Increment number of maps added to the vote.
						voteCounter++;

						// Delete the map so it can't be picked again.
						KvDeleteSubKey(kv, mapName);

						// Remove map from pool.
						nameArr.Erase(index);
						weightArr.Erase(index);
						cycleArr.Erase(index);

						if (verboseLogs)
						{
							LogUMCMessage("VOTE MENU: (Verbose) Nominated map '%s' from group '%s' was added to the vote.", mapName, catName);
						}
					}
				}

				// Close handles for the pool.
				CloseHandle(nameArr);
				CloseHandle(weightArr);
				CloseHandle(cycleArr);

				// Update numMapsFromCat to reflect the actual amount still required.
				numMapsFromCat = inVote - nomCounter;
			}
		}
		// Otherwise, we fill the vote with nominations then fill the rest with random maps from the mapcycle.
		else
		{
			// Add nomination to the vote array for each index in the nomination array.
			for (int i = 0; i < numNoms; i++)
			{
				// Get map name.
				StringMap nom = GetArrayCell(nominationsFromCat, i);
				GetTrieString(nom, MAP_TRIE_MAP_KEY, mapName, sizeof(mapName));

				// Add nominated map to the vote array if the map isn't already in the vote AND
				// the server has a valid number of players for the map.
				if (!ignoreDupes && FindStringInVoteArray(mapName, MAP_TRIE_MAP_KEY, map_vote) != -1)
				{
					if (verboseLogs)
					{
						LogUMCMessage("VOTE MENU: (Verbose) Skipping nominated map '%s' from map group '%s' because it is already in the vote.", mapName, catName);
					}
				}
				else
				{
					GetTrieValue(nom, "mapcycle", nomKV);
					GetTrieString(nom, "nom_group", nomGroup, sizeof(nomGroup));

					// Get extra fields from the map
					KeyValues dispKV = new KeyValues("umc_mapcycle");
					KvCopySubkeys(nomKV, dispKV);
					GetMapDisplayString(dispKV, nomGroup, mapName, gDisp, display, sizeof(display));
					CloseHandle(dispKV);

					// Get the position in the vote array to add the map to.
					position			  = GetNextMenuIndex(voteCounter, scramble);
					StringMap map		  = CreateMapTrie(mapName, catName);
					KeyValues nomMapcycle = new KeyValues("umc_mapcycle");
					KvCopySubkeys(nomKV, nomMapcycle);

					SetTrieValue(map, "mapcycle", nomMapcycle);
					InsertArrayCell(map_vote, position, map);
					InsertArrayString(map_vote_display, position, display);

					// Increment number of maps added to the vote.
					voteCounter++;

					// Delete the map so it cannot be picked again.
					KvDeleteSubKey(kv, mapName);

					if (verboseLogs)
					{
						LogUMCMessage("VOTE MENU: (Verbose) Nominated map '%s' from group '%s' was added to the vote.", mapName, catName);
					}
				}
			}
		}

		//////
		// At this point in the algorithm, we have already handled nominations for this category.
		// If there are maps which still need to be added to the vote, we will be fetching them
		// from the mapcycle directly.
		//////
		if (verboseLogs)
		{
			LogUMCMessage("VOTE MENU: (Verbose) Finished parsing nominations for map group '%s'", catName);

			if (numMapsFromCat > 0)
			{
				LogUMCMessage("VOTE MENU: (Verbose) Still need to fetch %i maps from the group.", numMapsFromCat);
			}
		}

		// We no longer need the nominations array, so we close the handle.
		CloseHandle(nominationsFromCat);

		// Add a map to the vote array from the current category while
		// maps still need to be added from the current category.
		while (numMapsFromCat > 0)
		{
			// Skip the category if there are no more maps that can be added to the vote.
			// This is Problem. Why?
			if (!GetRandomMap(kv, mapName, sizeof(mapName)))
			{
				if (verboseLogs)
				{
					LogUMCMessage("VOTE MENU: (Verbose) No more maps in map group '%s'", catName);
				}
				break;
			}

			// Remove the map from the category (so it cannot be selected again) and repick a map
			// if the map has already been added to the vote (through nomination or another category
			if (!ignoreDupes && FindStringInVoteArray(mapName, MAP_TRIE_MAP_KEY, map_vote) != -1)
			{
				KvDeleteSubKey(kv, mapName);
				if (verboseLogs)
				{
					LogUMCMessage("VOTE MENU: (Verbose) Skipping selected map '%s' from map group '%s' because it is already in the vote.", mapName, catName);
				}
				continue;
			}

			// At this point we have a map which we are going to add to the vote array.
			if (verboseLogs)
			{
				LogUMCMessage("VOTE MENU: (Verbose) Selected map '%s' from group '%s' was added to the vote.", mapName, catName);
			}

			// Find this map in the list of nominations.
			nomIndex = FindNominationIndex(mapName, catName);

			// Remove the nomination if it was found.
			if (nomIndex != -1)
			{
				StringMap nom = GetArrayCell(g_Nominations_Arr, nomIndex);

				int owner;
				GetTrieValue(nom, "client", owner);

				Call_StartForward(g_Nomination_Reset_Forward);
				Call_PushString(mapName);
				Call_PushCell(owner);
				Call_Finish();

				KeyValues oldnomKV;
				GetTrieValue(nom, "mapcycle", oldnomKV);
				CloseHandle(oldnomKV);
				CloseHandle(nom);
				RemoveFromArray(g_Nominations_Arr, nomIndex);
				if (verboseLogs)
				{
					LogUMCMessage("VOTE MENU: (Verbose) Removing selected map '%s' from nominations.", mapName);
				}
			}

			// Get extra fields from the map
			KeyValues dispKV = new KeyValues("umc_mapcycle");
			KvCopySubkeys(okv, dispKV);
			GetMapDisplayString(dispKV, catName, mapName, gDisp, display, sizeof(display));
			CloseHandle(dispKV);
			StringMap map		  = CreateMapTrie(mapName, catName);
			KeyValues mapMapcycle = new KeyValues("umc_mapcycle");
			KvCopySubkeys(mapcycle, mapMapcycle);
			SetTrieValue(map, "mapcycle", mapMapcycle);

			// Depending on the cvar, we will display all nominations in the vote either at the top or at the bottom
			// Bottom of the map vote
			if (!g_Cvar_MapNom_Display.BoolValue)
			{
				InsertArrayCell(map_vote, 0, map);
				InsertArrayString(map_vote_display, 0, display);
			}
			// Top of the map vote
			if (g_Cvar_MapNom_Display.BoolValue)
			{
				// Get the position in the vote array to add the map to.
				position = GetNextMenuIndex(voteCounter, scramble);
				InsertArrayCell(map_vote, position, map);
				InsertArrayString(map_vote_display, position, display);
			}

			// Increment number of maps added to the vote.
			voteCounter++;

			// Delete the map from the KV so we can't pick it again.
			KvDeleteSubKey(kv, mapName);

			// One less map to be added to the vote from this category.
			numMapsFromCat--;
		}
	}
	while (KvGotoNextKey(kv));	  // Do this for each category.

	// We no longer need the copy of the mapcycle
	CloseHandle(kv);

	ArrayList infoArr = BuildNumArray(voteCounter);

	StringMap voteItem;
	char buffer[MAP_LENGTH];
	for (int i = 0; i < voteCounter; i++)
	{
		voteItem = new StringMap();
		infoArr.GetString(i, buffer, sizeof(buffer));
		SetTrieString(voteItem, "info", buffer);
		map_vote_display.GetString(i, buffer, sizeof(buffer));
		SetTrieString(voteItem, "display", buffer);
		result.Push(voteItem);
	}

	CloseHandle(map_vote_display);
	CloseHandle(infoArr);

	if (extend)
	{
		voteItem = new StringMap();
		SetTrieString(voteItem, "info", EXTEND_MAP_OPTION);
		SetTrieString(voteItem, "display", "Extend Map");
		if (GetConVarBool(g_Cvar_Extend_Display))
		{
			InsertArrayCell(result, 0, voteItem);
		}
		else
		{
			result.Push(voteItem);
		}
	}

	if (dontChange)
	{
		voteItem = CreateTrie();
		SetTrieString(voteItem, "info", DONT_CHANGE_OPTION);
		SetTrieString(voteItem, "display", "Don't Change");
		if (g_Cvar_DontChange_Display.BoolValue)
		{
			InsertArrayCell(result, 0, voteItem);
		}
		else
		{
			PushArrayCell(result, voteItem);
		}
	}

	return BuildOptionsError_Success;
}

// Builds and returns a menu for a group vote.
UMC_BuildOptionsError BuildCatVoteItems(StringMap vM, ArrayList result, KeyValues okv, KeyValues mapcycle, bool scramble, bool extend, bool dontChange, bool strictNoms = false, bool exclude = true)
{
	// Throw an error and return nothing if the mapcycle is invalid.
	if (okv == null)
	{
		LogError("VOTING: Cannot build map group vote menu, rotation file is invalid.");
		return BuildOptionsError_InvalidMapcycle;
	}

	// Rewind our mapcycle.
	okv.Rewind();									   // rewind original
	KeyValues kv = CreateKeyValues("umc_rotation");	   // new handle
	KvCopySubkeys(okv, kv);

	// Log an error and return nothing if it cannot find a category.
	if (!KvGotoFirstSubKey(kv))
	{
		LogError("VOTING: No map groups found in rotation. Vote menu was not built.");
		CloseHandle(kv);
		return BuildOptionsError_NoMapGroups;
	}

	ClearVoteArrays(vM);

	bool	  verboseLogs = g_Cvar_Logging.BoolValue;

	char	  catName[MAP_LENGTH];	  // Buffer to store category name in.
	char	  mapName[MAP_LENGTH];
	char	  nomGroup[MAP_LENGTH];
	int		  voteCounter = 0;												   // Number of categories in the vote.
	ArrayList catArray	  = new ArrayList(ByteCountToCells(MAP_LENGTH), 0);	   // Array of categories in the vote.
	ArrayList catNoms;
	StringMap nom;
	int		  size;
	bool	  haveNoms = false;

	KeyValues nomKV;
	KeyValues nomMapcycle;

	// Add the current category to the vote.
	do
	{
		kv.GetSectionName(catName, sizeof(catName));
		haveNoms = false;
		if (exclude)
		{
			catNoms = GetCatNominations(catName);
			size	= GetArraySize(catNoms);
			for (int i = 0; i < size; i++)
			{
				nom = catNoms.Get(i);
				GetTrieValue(nom, "mapcycle", nomMapcycle);

				nomKV = new KeyValues("umc_rotation");
				KvCopySubkeys(nomMapcycle, nomKV);

				GetTrieString(nom, "nom_group", nomGroup, sizeof(nomGroup));

				GetTrieString(nom, MAP_TRIE_MAP_KEY, mapName, sizeof(mapName));

				nomKV.JumpToKey(nomGroup);

				if (IsValidMapFromCat(nomKV, nomMapcycle, mapName, .isNom = true))
				{
					haveNoms = true;
					CloseHandle(nomKV);
					break;
				}

				CloseHandle(nomKV);
			}
			CloseHandle(catNoms);
		}
		else if (!kv.GotoFirstSubKey())
		{
			if (verboseLogs)
			{
				LogUMCMessage("VOTE MENU: (Verbose) Skipping empty map group '%s'.", catName);
			}
			continue;
		}
		else
		{
			kv.GoBack();
			haveNoms = true;
		}

		// Skip this category if the server doesn't have the required amount of players or all maps are excluded OR
		// the number of maps in the vote from the category is less than 1.
		if (!haveNoms)
		{
			if (!IsValidCat(kv, mapcycle))
			{
				if (verboseLogs)
				{
					LogUMCMessage("VOTE MENU: (Verbose) Skipping excluded map group '%s'.", catName);
				}
				continue;
			}
			else if (kv.GetNum("maps_invote", 1) < 1 && strictNoms)
			{
				if (verboseLogs)
				{
					LogUMCMessage("VOTE MENU: (Verbose) Skipping map group '%s' due to \"maps_invote\" setting of 0.", catName);
				}
				continue;
			}
		}

		if (verboseLogs)
		{
			LogUMCMessage("VOTE MENU: (Verbose) Group '%s' was added to the vote.", catName);
		}

		// Add category to the vote array...
		InsertArrayString(catArray, GetNextMenuIndex(voteCounter, scramble), catName);

		// Increment number of categories in the vote.
		voteCounter++;
	}
	while (kv.GotoNextKey());	 // Do this for each category.

	// No longer need the copied mapcycle
	CloseHandle(kv);

	// Fall back to a map vote if only one group is available.
	if (GetArraySize(catArray) == 1)
	{
		CloseHandle(catArray);
		LogUMCMessage("Not enough groups available for group vote, performing map vote with only group available.");
		return BuildOptionsError_NotEnoughOptions;
	}

	StringMap voteItem;
	char	  buffer[MAP_LENGTH];
	for (int i = 0; i < voteCounter; i++)
	{
		voteItem = new StringMap();
		catArray.GetString(i, buffer, sizeof(buffer));
		SetTrieString(voteItem, "info", buffer);
		SetTrieString(voteItem, "display", buffer);
		result.Push(voteItem);
	}

	CloseHandle(catArray);

	if (extend)
	{
		voteItem = new StringMap();
		SetTrieString(voteItem, "info", EXTEND_MAP_OPTION);
		SetTrieString(voteItem, "display", "Extend Map");
		if (g_Cvar_Extend_Display.BoolValue)
		{
			InsertArrayCell(result, 0, voteItem);
		}
		else
		{
			result.Push(voteItem);
		}
	}

	if (dontChange)
	{
		voteItem = new StringMap();
		SetTrieString(voteItem, "info", DONT_CHANGE_OPTION);
		SetTrieString(voteItem, "display", "Don't Change");
		if (g_Cvar_DontChange_Display.BoolValue)
		{
			InsertArrayCell(result, 0, voteItem);
		}
		else
		{
			result.Push(voteItem);
		}
	}

	return BuildOptionsError_Success;
}

// Calls the templating system to format a map's display string.
//   kv: Mapcycle containing the template info to use
//   group:  Group of the map we're getting display info for.
//   map:    Name of the map we're getting display info for.
//   buffer: Buffer to store the display string.
//   maxlen: Maximum length of the buffer.
void GetMapDisplayString(KeyValues kv, const char[] group, const char[] map, const char[] template, char[] buffer, int maxlen)
{
	strcopy(buffer, maxlen, "");
	if (kv.JumpToKey(group))
	{
		if (kv.JumpToKey(map))
		{
			kv.GetString("display", buffer, maxlen, template);
			kv.GoBack();
		}
		kv.GoBack();
	}

	Call_StartForward(g_Template_Forward);
	Call_PushStringEx(buffer, maxlen, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(maxlen);
	Call_PushCell(kv);
	Call_PushString(map);
	Call_PushString(group);
	Call_Finish();
}

// Replaces {MAP} and {NOMINATED} in template strings.
public void UMC_OnFormatTemplateString(char[] template, int maxlen, KeyValues kv, const char[] map, const char[] group)
{
	char resolvedMap[MAP_LENGTH];
	GetMapDisplayName(map, resolvedMap, sizeof(resolvedMap));

	if (strlen(template) == 0)
	{
		strcopy(template, maxlen, resolvedMap);
		return;
	}

	ReplaceString(template, maxlen, "{MAP}", resolvedMap, false);

	char nomString[16];
	g_Cvar_NomMsg_Disp.GetString(nomString, sizeof(nomString));
	ReplaceString(template, maxlen, "{NOMINATED}", nomString, false);
}

// Selects a random map from a category based off of the supplied weights for the maps.
//     kv:     a mapcycle whose traversal stack is currently at the level of the category to choose
//             from.
//     buffer:    a string to store the selected map in
//     key:  the key containing the weight information (for maps, 'weight', for cats, 'group_weight')
//     excluded: an adt_array of maps to exclude from the selection.
// bool:GetRandomMap(Handle:kv, String:buffer[], size, Handle:excluded, Handle:excludedCats,
//                   bool:isNom=false, bool:forMapChange=true, bool:memory=true)
bool GetRandomMap(KeyValues kv, char[] buffer, int size)
{
	char catName[MAP_LENGTH];
	kv.GetSectionName(catName, sizeof(catName));

	// Return failure if there are no maps in the category.
	if (!kv.GotoFirstSubKey())
	{
		return false;
	}

	int	index = 0;	 // counter of maps in the random pool
	ArrayList nameArr = new ArrayList(ByteCountToCells(MAP_LENGTH));	  // Array to store possible map names
	ArrayList weightArr = new ArrayList();								  // Array to store possible map weights.
	char temp[MAP_LENGTH];	// Buffer to store map names in.

	// Add a map to the random pool.
	do
	{
		// Get the name of the map.
		kv.GetSectionName(temp, sizeof(temp));

		// custom
		// filter out maps by recent GetMapHistory
		// after 5 maps
		int	 size2 = (GetMapHistorySize() >= 5) ? 5 : GetMapHistorySize();
		char mapname[64], lol[2];
		bool skip = false;
		int	 lol2;

		for (int i = 0; i < size2; i++)
		{
			GetMapHistory(i, mapname, sizeof(mapname), lol, 2, lol2);
			if (StrEqual(mapname, temp)) skip = true;
		}

		if (skip) continue;

		// Add the map to the random pool.
		weightArr.Push(GetWeight(kv));
		nameArr.PushString(temp);

		// One more map in the pool.
		index++;
	}
	while (kv.GotoNextKey());	 // Do this for each map.

	// Go back to the category level.
	kv.GoBack();

	// Close pool and fail if no maps are selectable.
	if (index == 0)
	{
		CloseHandle(nameArr);
		CloseHandle(weightArr);
		return false;
	}

	// Use weights to randomly select a map from the pool.
	bool result = GetWeightedRandomSubKey(buffer, size, weightArr, nameArr);

	// Close the pool.
	CloseHandle(nameArr);
	CloseHandle(weightArr);

	// Done!
	return result;
}

// Searches array for given string. Returns -1 on failure.
int FindStringInVoteArray(const char[] target, const char[] val, ArrayList arr)
{
	int	 size = GetArraySize(arr);
	char buffer[MAP_LENGTH];
	for (int i = 0; i < size; i++)
	{
		GetTrieString(arr.Get(i), val, buffer, sizeof(buffer));
		if (StrEqual(buffer, target))
		{
			return i;
		}
	}
	return -1;
}

// Catches the case where a vote occurred but nobody voted.
bool VoteCancelled(StringMap vM)
{
	PrivateForward handler;
	bool		   vote_inprogress;	   //, bool:vote_active;
	GetTrieValue(vM, "in_progress", vote_inprogress);

	if (vote_inprogress)
	{
		GetTrieValue(vM, "cancel", handler);

		ClearVoteArrays(vM);
		EmptyStorage(vM);
		DeleteVoteParams(vM);
		VoteFailed(vM);

		Call_StartForward(handler);
		Call_Finish();
		return true;
	}

	return false;
}

// Utility function to clear all the voting storage arrays.
void ClearVoteArrays(StringMap voteManager)
{
	ArrayList map_vote;
	GetTrieValue(voteManager, "map_vote", map_vote);

	int size = GetArraySize(map_vote);
	StringMap mapTrie;
	KeyValues kv;
	for (int i = 0; i < size; i++)
	{
		mapTrie = GetArrayCell(map_vote, i);
		GetTrieValue(mapTrie, "mapcycle", kv);
		CloseHandle(kv);
		CloseHandle(mapTrie);
	}
	ClearArray(map_vote);
}

// Get the winner from a vote.
any GetWinner(StringMap vM)
{
	ArrayList vote_storage;
	GetTrieValue(vM, "vote_storage", vote_storage);

	int		  counter  = 1;
	StringMap voteItem = GetArrayCell(vote_storage, 0);
	ArrayList voteClients;
	GetTrieValue(voteItem, "clients", voteClients);
	int most_votes = GetArraySize(voteClients);
	int num_items  = GetArraySize(vote_storage);
	while (counter < num_items)
	{
		GetTrieValue(GetArrayCell(vote_storage, counter), "clients", voteClients);
		if (GetArraySize(voteClients) < most_votes)
		{
			break;
		}
		counter++;
	}
	if (counter > 1)
	{
		return GetArrayCell(vote_storage, GetRandomInt(0, counter - 1));
	}
	else
	{
		return GetArrayCell(vote_storage, 0);
	}
}

// Generates a list of categories to be excluded from the second stage of a tiered vote.
stock KeyValues MakeSecondTieredCatExclusion(KeyValues kv, const char[] cat)
{
	// Log an error and return nothing if there are no categories in the cycle (for some reason).
	if (!kv.JumpToKey(cat))
	{
		LogError("TIERED VOTE: Cannot create second stage of vote, rotation file is invalid (no groups were found.)");
		return null;
	}

	// Array to return at the end.
	KeyValues result = new KeyValues("umc_rotation");
	result.JumpToKey(cat, true);

	KvCopySubkeys(kv, result);

	// Return to the root.
	kv.GoBack();
	result.GoBack();

	// Success!
	return result;
}

// Updates the display for the interval between tiered votes.
void DisplayTierMessage(int timeleft)
{
	char msg[255], notification[10];
	FormatEx(msg, sizeof(msg), "%t", "Another Vote", timeleft);
	GetConVarString(g_Cvar_Vote_TierDisplay, notification, sizeof(notification));
	DisplayServerMessage(msg, notification);
}

// Empties the vote storage
void EmptyStorage(StringMap vM)
{
	ArrayList vote_storage;
	GetTrieValue(vM, "vote_storage", vote_storage);

	int size = GetArraySize(vote_storage);
	for (int i = 0; i < size; i++)
	{
		RemoveFromStorage(vM, 0);
	}
	SetTrieValue(vM, "total_votes", 0);
}

// Removes a vote item from the storage
void RemoveFromStorage(StringMap vM, int index)
{
	ArrayList vote_storage;
	int		  total_votes;
	GetTrieValue(vM, "vote_storage", vote_storage);
	GetTrieValue(vM, "total_votes", total_votes);

	StringMap stored = GetArrayCell(vote_storage, index);
	ArrayList clients;
	GetTrieValue(stored, "clients", clients);
	SetTrieValue(vM, "total_votes", total_votes - GetArraySize(clients));
	CloseHandle(clients);
	CloseHandle(stored);
	RemoveFromArray(vote_storage, index);
}

// Gets the winning info for the vote
void GetVoteWinner(StringMap vM, char[] info, int maxinfo, float &percentage, char[] disp = "", int maxdisp = 0)
{
	int total_votes;
	GetTrieValue(vM, "total_votes", total_votes);

	StringMap winner = GetWinner(vM);
	ArrayList clients;
	GetTrieString(winner, "info", info, maxinfo);
	GetTrieString(winner, "display", disp, maxdisp);
	GetTrieValue(winner, "clients", clients);
	percentage = float(GetArraySize(clients)) / total_votes * 100;
}

// Finds the index of the given vote item in the storage array. Returns -1 on failure.
int FindVoteInStorage(ArrayList vote_storage, const char[] info)
{
	int		  arraySize = GetArraySize(vote_storage);
	StringMap vote;
	char	  infoBuf[255];
	for (int i = 0; i < arraySize; i++)
	{
		vote = GetArrayCell(vote_storage, i);
		GetTrieString(vote, "info", infoBuf, sizeof(infoBuf));
		if (StrEqual(info, infoBuf))
		{
			return i;
		}
	}
	return -1;
}

// Comparison function for stored vote items. Used for sorting.
public int CompareStoredVoteItems(int index1, int index2, Handle array, Handle hndl)
{
	int		  size1, size2;
	StringMap vote;
	ArrayList clientArray;
	vote = GetArrayCell(array, index1);
	GetTrieValue(vote, "clients", clientArray);
	size1 = GetArraySize(clientArray);
	vote  = GetArrayCell(array, index2);
	GetTrieValue(vote, "clients", clientArray);
	size2 = GetArraySize(clientArray);
	return size2 - size1;
}

// Adds vote results to the vote storage
void AddToStorage(StringMap vM, ArrayList vote_results)
{
	ArrayList vote_storage;
	GetTrieValue(vM, "vote_storage", vote_storage);
	SetTrieValue(vM, "prev_vote_count", GetArraySize(vote_storage));

	int		  num_items = GetArraySize(vote_results);
	int		  storageIndex;
	int		  num_votes = 0;
	StringMap voteItem;
	ArrayList voteClientArray;
	char	  infoBuffer[255], dispBuffer[255];
	for (int i = 0; i < num_items; i++)
	{
		voteItem = GetArrayCell(vote_results, i);
		GetTrieString(voteItem, "info", infoBuffer, sizeof(infoBuffer));
		storageIndex = FindVoteInStorage(vote_storage, infoBuffer);
		GetTrieValue(voteItem, "clients", voteClientArray);
		num_votes += GetArraySize(voteClientArray);
		if (storageIndex == -1)
		{
			StringMap newItem = new StringMap();
			SetTrieString(newItem, "info", infoBuffer);
			GetTrieString(voteItem, "display", dispBuffer, sizeof(dispBuffer));
			SetTrieString(newItem, "display", dispBuffer);
			SetTrieValue(newItem, "clients", CloneArray(voteClientArray));
			PushArrayCell(vote_storage, newItem);
		}
		else
		{
			ArrayList storageClientArray;
			GetTrieValue(GetArrayCell(vote_storage, storageIndex), "client", storageClientArray);
			ArrayAppend(storageClientArray, voteClientArray);
		}
	}
	SortADTArrayCustom(vote_storage, CompareStoredVoteItems);

	int total_votes;
	GetTrieValue(vM, "total_votes", total_votes);
	SetTrieValue(vM, "total_votes", total_votes + num_votes);
}

// Handles the results of a vote
StringMap ProcessVoteResults(StringMap vM, ArrayList vote_results)
{
	StringMap result = new StringMap();

	// Vote is no longer running.
	SetTrieValue(vM, "active", false);

	// Adds these results to the storage.
	AddToStorage(vM, vote_results);

	// Perform a runoff vote if it is necessary.
	if (NeedRunoff(vM))
	{
		int remaining_runoffs, prev_vote_count;
		GetTrieValue(vM, "remaining_runoffs", remaining_runoffs);
		GetTrieValue(vM, "prev_vote_count", prev_vote_count);

		// If we can't runoff anymore
		if (remaining_runoffs == 0 || prev_vote_count == 2)
		{
			// Retrieve
			UMC_RunoffFailAction stored_fail_action;
			GetTrieValue(vM, "stored_fail_action", stored_fail_action);

			if (stored_fail_action == RunoffFailAction_Accept)
			{
				ProcessVoteWinner(vM, result);
			}
			else if (stored_fail_action == RunoffFailAction_Nothing)
			{
				int total_votes;
				GetTrieValue(vM, "total_votes", total_votes);
				float percentage;
				GetVoteWinner(vM, "", 0, percentage);
				PrintToChatAll(
					"[UMC] %t (%t)",
					"Vote Failed",
					"Vote Win Percentage",
					percentage,
					total_votes);
				LogUMCMessage("MAPVOTE: Vote failed, winning map did not reach threshold.");
				VoteFailed(vM);
				DeleteVoteParams(vM);
				ClearVoteArrays(vM);
				SetTrieValue(result, "response", VoteResponse_Fail);
			}
			EmptyStorage(vM);
		}
		else
		{
			DoRunoffVote(vM, result);
		}
	}
	else	// Otherwise set the results.
	{
		ProcessVoteWinner(vM, result);
		EmptyStorage(vM);
	}
	return result;
}

// Processes the winner from the vote.
void ProcessVoteWinner(StringMap vM, StringMap response)
{
	// Detemine winner information.
	char  winner[255], disp[255];
	float percentage;
	GetVoteWinner(vM, winner, sizeof(winner), percentage, disp, sizeof(disp));

	UMC_VoteType stored_type;
	GetTrieValue(vM, "stored_type", stored_type);

	SetTrieValue(response, "response", VoteResponse_Success);
	SetTrieString(response, "param", disp);

	switch (stored_type)
	{
		case VoteType_Map:
		{
			Handle_MapVoteWinner(vM, winner, disp, percentage);
		}
		case VoteType_Group:
		{
			Handle_CatVoteWinner(vM, winner, disp, percentage);
		}
		case VoteType_Tier:
		{
			SetTrieValue(response, "response", VoteResponse_Tiered);
			Handle_TierVoteWinner(vM, winner, disp, percentage);
		}
	}
}

// Determines if a runoff vote is needed.
bool NeedRunoff(StringMap vM)
{
	// Retrive
	float	  stored_threshold;
	int		  total_votes;
	ArrayList vote_storage;
	GetTrieValue(vM, "stored_threshold", stored_threshold);
	GetTrieValue(vM, "total_votes", total_votes);
	GetTrieValue(vM, "vote_storage", vote_storage);

	// Get the winning vote item.
	StringMap voteItem = vote_storage.Get(0);
	ArrayList clients;
	GetTrieValue(voteItem, "clients", clients);

	int numClients = GetArraySize(clients);
	return (float(numClients) / total_votes) < stored_threshold;
}

// Sets up a runoff vote.
void DoRunoffVote(StringMap vM, StringMap response)
{
	int remaining_runoffs;
	GetTrieValue(vM, "remaining_runoffs", remaining_runoffs);
	SetTrieValue(vM, "remaining_runoffs", remaining_runoffs - 1);

	// Array to store clients the menu will be displayed to.
	ArrayList runoffClients = new ArrayList();

	// Build the runoff vote based off of the results of the failed vote.
	ArrayList runoffOptions = BuildRunoffOptions(vM, runoffClients);

	// Setup the timer if the menu was built successfully
	if (runoffOptions != null)
	{
		int clients[MAXPLAYERS + 1];
		int numClients;

		// Empty storage and add all clients if we're revoting completely.
		if (!g_Cvar_Runoff_Selective.BoolValue)
		{
			runoffClients.Clear();
			EmptyStorage(vM);

			int users[MAXPLAYERS + 1];
			GetTrieArray2(vM, "stored_users", users, sizeof(users), numClients);
			ConvertUserIDsToClients(users, clients, numClients);

			// runoffClients = GetClientsWithFlags(adminFlags);
			ConvertArray(clients, numClients, runoffClients);
		}

		// Setup timer to delay the start of the runoff vote.
		SetTrieValue(vM, "runoff_delay", 7);

		// Display the first message
		DisplayRunoffMessage(8);

		// Setup data pack to go along with the timer.
		DataPack pack;
		CreateDataTimer(1.0, Handle_RunoffVoteTimer, pack, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
		// Add info to the pack.
		WritePackCell(pack, vM);
		WritePackCell(pack, runoffOptions);
		WritePackCell(pack, runoffClients);
		SetTrieValue(response, "response", VoteResponse_Runoff);
	}
	else	// Otherwise, cleanup
	{
		LogError("RUNOFF: Unable to create runoff vote menu, runoff aborted.");
		CloseHandle(runoffClients);
		VoteFailed(vM);
		EmptyStorage(vM);
		DeleteVoteParams(vM);
		ClearVoteArrays(vM);
		SetTrieValue(response, "response", VoteResponse_Fail);
	}
}

// Builds a runoff vote menu.
//   clientArray:    adt_array to be populated with clients whose votes were eliminated
ArrayList BuildRunoffOptions(StringMap vM, ArrayList clientArray)
{
	ArrayList vote_storage;
	float	  stored_threshold;
	GetTrieValue(vM, "vote_storage", vote_storage);
	GetTrieValue(vM, "stored_threshold", stored_threshold);

	bool verboseLogs = g_Cvar_Logging.BoolValue;
	if (verboseLogs)
	{
		LogUMCMessage("RUNOFF MENU: (Verbose) Building runoff vote menu.");
	}

	float runoffThreshold = stored_threshold;

	// Copy the current total number of votes. Needed because the number will change as we remove items.
	int	  totalVotes;
	GetTrieValue(vM, "total_votes", totalVotes);

	StringMap voteItem;
	ArrayList voteClients;
	int		  voteNumVotes;
	int		  num_items = GetArraySize(vote_storage);

	// Array determining which clients have voted
	bool	  clientVotes[MAXPLAYERS + 1];
	for (int i = 0; i < num_items; i++)
	{
		voteItem = vote_storage.Get(i);
		GetTrieValue(voteItem, "clients", voteClients);
		voteNumVotes = GetArraySize(voteClients);
		for (int j = 0; j < voteNumVotes; j++)
		{
			clientVotes[voteClients.Get(j)] = true;
		}
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!clientVotes[i])
		{
			PushArrayCell(clientArray, i);
		}
	}

	StringMap winning = vote_storage.Get(0);
	int		  winningNumVotes;
	ArrayList winningClients;
	GetTrieValue(winning, "clients", winningClients);
	winningNumVotes = GetArraySize(winningClients);

	// Starting max possible percentage of the winning item in this vote.
	float percent	= float(winningNumVotes) / float(totalVotes) * 100;
	float newPercent;

	// Max number of maps in the runoff vote
	int	  maxMaps;
	GetTrieValue(vM, "stored_runoffmaps_max", maxMaps);
	bool checkMax = maxMaps > 1;

	// Starting at the item with the least votes, calculate the new possible max percentage
	// of the winning item. Stop when this percentage is greater than the threshold.
	for (int i = num_items - 1; i > 1; i--)
	{
		voteItem = vote_storage.Get(i);
		GetTrieValue(voteItem, "clients", voteClients);
		voteNumVotes = GetArraySize(voteClients);
		ArrayAppend(clientArray, voteClients);

		newPercent = float(voteNumVotes) / float(totalVotes) * 100;
		percent += newPercent;

		if (verboseLogs)
		{
			char dispBuf[255];
			GetTrieString(voteItem, "display", dispBuf, sizeof(dispBuf));
			LogUMCMessage("RUNOFF MENU: (Verbose) '%s' was removed from the vote. It had %i votes (%.f%% of total)", dispBuf, voteNumVotes, newPercent);
		}

		// No longer store the map
		RemoveFromStorage(vM, i);
		num_items--;

		// Stop if the new percentage is over the threshold AND the number of maps in the vote is under the max.
		if (percent >= runoffThreshold && (!checkMax || num_items <= maxMaps))
		{
			break;
		}
	}

	if (verboseLogs)
	{
		LogUMCMessage("RUNOFF MENU: (Verbose) Stopped removing options from the vote. Maximum possible winning vote percentage is %.f%%.", percent);
	}

	// Start building the new vote menu.
	ArrayList newMenu = new ArrayList();

	// Populate the new menu with what remains of the storage.
	int		  count	  = 0;
	char	  info[255], disp[255];
	StringMap item;
	for (int i = 0; i < num_items; i++)
	{
		voteItem = vote_storage.Get(i);
		GetTrieString(voteItem, "info", info, sizeof(info));
		GetTrieString(voteItem, "display", disp, sizeof(disp));

		item = new StringMap();
		SetTrieString(item, "info", info);
		SetTrieString(item, "display", disp);
		newMenu.Push(item);

		count++;
	}

	// Log an error and do nothing if there weren't enough items added to the runoff vote.
	//   *This shouldn't happen if the algorithm is working correctly*
	if (count < 2)
	{
		for (int i = 0; i < count; i++)
		{
			CloseHandle(GetArrayCell(newMenu, i));
		}
		CloseHandle(newMenu);
		LogError("RUNOFF: Not enough remaining maps to perform runoff vote. %i maps remaining. Please notify plugin author.", count);
		return null;
	}

	return newMenu;
}

// Called when the runoff timer for an end-of-map vote completes.
public Action Handle_RunoffVoteTimer(Handle timer, DataPack datapack)
{
	datapack.Reset();
	StringMap vM = datapack.ReadCell();

	bool	  vote_inprogress;
	GetTrieValue(vM, "in_progress", vote_inprogress);

	if (!vote_inprogress)
	{
		VoteFailed(vM);
		EmptyStorage(vM);
		DeleteVoteParams(vM);
		ClearVoteArrays(vM);

		ArrayList options = datapack.ReadCell();
		ArrayList clients = datapack.ReadCell();
		FreeOptions(options);
		CloseHandle(clients);

		return Plugin_Stop;
	}

	int runoff_delay;
	GetTrieValue(vM, "runoff_delay", runoff_delay);
	DisplayRunoffMessage(runoff_delay);

	// Display a message and continue timer if the timer hasn't finished yet.
	if (runoff_delay > 0)
	{
		if (strlen(g_Countdown_Sound) > 0)
		{
			EmitSoundToAllAny(g_Countdown_Sound);
		}

		SetTrieValue(vM, "runoff_delay", runoff_delay - 1);
		return Plugin_Continue;
	}

	LogUMCMessage("RUNOFF: Starting runoff vote.");

	// Log an error and do nothing if another vote is currently running for some reason.
	if (IsVMVoteInProgress(vM))
	{
		LogUMCMessage("RUNOFF: There is a vote already in progress, cannot start a new vote.");
		return Plugin_Continue;
	}

	ArrayList options	  = datapack.ReadCell();
	ArrayList voteClients = datapack.ReadCell();
	int		  clients[MAXPLAYERS + 1];
	int		  numClients = GetArraySize(voteClients);
	ConvertAdtArray(voteClients, clients, sizeof(clients));

	CloseHandle(voteClients);

	UMC_VoteType type;
	GetTrieValue(vM, "stored_type", type);
	int time;
	GetTrieValue(vM, "stored_votetime", time);
	char sound[PLATFORM_MAX_PATH];
	GetTrieString(vM, "stored_runoff_sound", sound, sizeof(sound));

	bool vote_active = PerformVote(vM, type, options, time, clients, numClients, sound);
	if (!vote_active)
	{
		DeleteVoteParams(vM);
		ClearVoteArrays(vM);
		EmptyStorage(vM);
		VoteFailed(vM);
	}

	FreeOptions(options);

	return Plugin_Stop;
}

// Displays a notification for the impending runoff vote.
void DisplayRunoffMessage(int timeRemaining)
{
	char msg[255], notification[10];
	if (timeRemaining > 5)
	{
		FormatEx(msg, sizeof(msg), "%t", "Runoff Msg");
	}
	else
	{
		FormatEx(msg, sizeof(msg), "%t", "Another Vote", timeRemaining);
	}
	g_Cvar_Runoff_Display.GetString(notification, sizeof(notification));
	DisplayServerMessage(msg, notification);
}

// Handles the winner of an end-of-map map vote.
public void Handle_MapVoteWinner(StringMap vM, const char[] info, const char[] disp, float percentage)
{
	int total_votes;
	GetTrieValue(vM, "total_votes", total_votes);

	// Print a message and extend the current map if the server voted to extend the map.
	if (StrEqual(info, EXTEND_MAP_OPTION))
	{
		PrintToChatAll(
			"[UMC] %t %t (%t)",
			"End of Map Vote Over",
			"Map Extended",
			"Vote Win Percentage",
			percentage,
			total_votes);
		LogUMCMessage("MAPVOTE: Players voted to extend the map.");
		ExtendMap(vM);
	}
	else if (StrEqual(info, DONT_CHANGE_OPTION))
	{
		PrintToChatAll(
			"[UMC] %t %t (%t)",
			"End of Map Vote Over",
			"Map Unchanged",
			"Vote Win Percentage",
			percentage,
			total_votes);

		LogUMCMessage("MAPVOTE: Players voted to stay on the map (Don't Change).");
		VoteFailed(vM);
	}
	else	// Otherwise, we print a message and then set the new map.
	{
		PrintToChatAll(
			"[UMC] %t %t (%t)",
			"End of Map Vote Over",
			"End of Map Vote Map Won",
			disp,
			"Vote Win Percentage",
			percentage,
			total_votes);

		ArrayList		  map_vote;
		UMC_ChangeMapTime change_map_when;
		GetTrieValue(vM, "map_vote", map_vote);
		GetTrieValue(vM, "change_map_when", change_map_when);
		char stored_reason[PLATFORM_MAX_PATH];
		GetTrieString(vM, "stored_reason", stored_reason, sizeof(stored_reason));

		// Find the index of the winning map in the stored vote array.
		int		  index = StringToInt(info);
		char	  map[MAP_LENGTH], group[MAP_LENGTH];

		StringMap mapData = map_vote.Get(index);
		GetTrieString(mapData, MAP_TRIE_MAP_KEY, map, sizeof(map));
		GetTrieString(mapData, MAP_TRIE_GROUP_KEY, group, sizeof(group));

		KeyValues mapcycle;
		GetTrieValue(mapData, "mapcycle", mapcycle);

		// Set it.
		DisableVoteInProgress(vM);
		DoMapChange(change_map_when, mapcycle, map, group, stored_reason, disp);

		LogUMCMessage("MAPVOTE: Players voted for map '%s' from group '%s'", map, group);
	}

	char stored_end_sound[PLATFORM_MAX_PATH];
	GetTrieString(vM, "stored_end_sound", stored_end_sound, sizeof(stored_end_sound));

	// Play the vote completed sound if the vote completed sound is defined.
	if (strlen(stored_end_sound) > 0)
	{
		EmitSoundToAllAny(stored_end_sound);
	}

	// No longer need the vote array.
	ClearVoteArrays(vM);
	DeleteVoteParams(vM);
}

// Handles the winner of an end-of-map category vote.
public void Handle_CatVoteWinner(StringMap vM, const char[] cat, const char[] disp, float percentage)
{
	int total_votes;
	GetTrieValue(vM, "total_votes", total_votes);

	// Print a message and extend the map if the server voted to extend the map.
	if (StrEqual(cat, EXTEND_MAP_OPTION))
	{
		PrintToChatAll(
			"[UMC] %t %t (%t)",
			"End of Map Vote Over",
			"Map Extended",
			"Vote Win Percentage",
			percentage,
			total_votes);
		LogUMCMessage("Players voted to extend the map.");
		ExtendMap(vM);
	}
	else if (StrEqual(cat, DONT_CHANGE_OPTION))
	{
		PrintToChatAll(
			"[UMC] %t %t (%t)",
			"End of Map Vote Over",
			"Map Unchanged",
			"Vote Win Percentage",
			percentage,
			total_votes);

		LogUMCMessage("Players voted to stay on the map (Don't Change).");
		VoteFailed(vM);
	}
	else	// Otherwise, we pick a random map from the category and set that as the next map.
	{
		char			  map[MAP_LENGTH];
		KeyValues		  stored_kv, stored_mapcycle;
		UMC_ChangeMapTime change_map_when;
		char			  stored_reason[PLATFORM_MAX_PATH];
		bool			  stored_exclude;
		GetTrieValue(vM, "stored_kv", stored_kv);
		GetTrieValue(vM, "stored_mapcycle", stored_mapcycle);
		GetTrieValue(vM, "change_map_when", change_map_when);
		GetTrieString(vM, "stored_reason", stored_reason, sizeof(stored_reason));
		GetTrieValue(vM, "stored_exclude", stored_exclude);

		// Rewind the mapcycle.
		stored_kv.Rewind();	   // rewind original
		KeyValues kv = CreateKeyValues("umc_rotation");
		KvCopySubkeys(stored_kv, kv);

		// Jump to the category in the mapcycle.
		KvJumpToKey(kv, cat);

		if (stored_exclude)
		{
			FilterMapGroup(kv, stored_mapcycle);
		}

		WeightMapGroup(kv, stored_mapcycle);

		ArrayList nominationsFromCat;

		// An adt_array of nominations from the given category.
		if (stored_exclude)
		{
			ArrayList tempCatNoms = GetCatNominations(cat);
			nominationsFromCat	  = FilterNominationsArray(tempCatNoms);
			CloseHandle(tempCatNoms);
		}
		else
		{
			nominationsFromCat = GetCatNominations(cat);
		}

		// If there are nominations for this category.
		if (GetArraySize(nominationsFromCat) > 0)
		{
			// Array of nominated map names.
			ArrayList nameArr	= new ArrayList(ByteCountToCells(MAP_LENGTH));

			// Array of nominated map weights (linked to the previous by index).
			ArrayList weightArr = new ArrayList();
			ArrayList cycleArr	= new ArrayList();

			// Buffer to store the map name
			char	  nameBuffer[MAP_LENGTH];
			char	  nomGroup[MAP_LENGTH];

			// A nomination.
			StringMap trie;
			KeyValues nomKV;
			int		  index;

			// Add nomination to name and weight array for each nomination in the nomination array for this category.
			int		  arraySize = GetArraySize(nominationsFromCat);
			for (int i = 0; i < arraySize; i++)
			{
				// Get the nomination at the current index.
				trie = nominationsFromCat.Get(i);

				// Get the map name from the nomination.
				GetTrieString(trie, MAP_TRIE_MAP_KEY, nameBuffer, sizeof(nameBuffer));
				GetTrieValue(trie, "mapcycle", nomKV);

				// Add the map to the map name array.
				nameArr.PushString(nameBuffer);
				weightArr.Push(GetMapWeight(nomKV, nameBuffer, cat));
				cycleArr.Push(trie);
			}

			// Pick a random map from the nominations if there are nominations to choose from.
			if (GetWeightedRandomSubKey(map, sizeof(map), weightArr, nameArr, index))
			{
				trie = cycleArr.Get(index);
				GetTrieValue(trie, "mapcycle", nomKV);
				GetTrieString(trie, "nom_group", nomGroup, sizeof(nomGroup));
				DisableVoteInProgress(vM);
				DoMapChange(change_map_when, nomKV, map, nomGroup, stored_reason, map);
			}
			else	// Otherwise, we select a map randomly from the category.
			{
				GetRandomMap(kv, map, sizeof(map));
				DisableVoteInProgress(vM);
				DoMapChange(change_map_when, stored_mapcycle, map, cat, stored_reason, map);
			}

			// Close the handles for the storage arrays.
			CloseHandle(nameArr);
			CloseHandle(weightArr);
			CloseHandle(cycleArr);
		}

		// Otherwise, there are no nominations to worry about so we just pick a map randomly from the winning category.
		else
		{
			GetRandomMap(kv, map, sizeof(map));	   //, stored_exmaps, stored_exgroups);
			DisableVoteInProgress(vM);
			DoMapChange(change_map_when, stored_mapcycle, map, cat, stored_reason, map);
		}

		// We no longer need the adt_array to store nominations.
		CloseHandle(nominationsFromCat);

		// We no longer need the copy of the mapcycle.
		CloseHandle(kv);

		PrintToChatAll(
			"[UMC] %t %t (%t)",
			"End of Map Vote Over",
			"End of Map Vote Group Won",
			map, cat,
			"Vote Win Percentage",
			percentage,
			total_votes);
		LogUMCMessage("MAPVOTE: Players voted for map group '%s' and the map '%s' was randomly selected.", cat, map);
	}

	char stored_end_sound[PLATFORM_MAX_PATH];
	GetTrieString(vM, "stored_end_sound", stored_end_sound, sizeof(stored_end_sound));

	// Play the vote completed sound if the vote completed sound is defined.
	if (strlen(stored_end_sound) > 0)
	{
		EmitSoundToAllAny(stored_end_sound);
	}

	DeleteVoteParams(vM);
}

// Handles the winner of an end-of-map tiered vote.
public void Handle_TierVoteWinner(StringMap vM, const char[] cat, const char[] disp, float percentage)
{
	int total_votes;
	GetTrieValue(vM, "total_votes", total_votes);

	// Print a message and extend the map if the server voted to extend the map.
	if (StrEqual(cat, EXTEND_MAP_OPTION))
	{
		PrintToChatAll(
			"[UMC] %t %t (%t)",
			"End of Map Vote Over",
			"Map Extended",
			"Vote Win Percentage",
			percentage,
			total_votes);
		LogUMCMessage("MAPVOTE: Players voted to extend the map.");
		DeleteVoteParams(vM);
		ExtendMap(vM);
	}
	else if (StrEqual(cat, DONT_CHANGE_OPTION))
	{
		PrintToChatAll(
			"[UMC] %t %t (%t)",
			"End of Map Vote Over",
			"Map Unchanged",
			"Vote Win Percentage",
			percentage,
			total_votes);

		LogUMCMessage("MAPVOTE: Players voted to stay on the map (Don't Change).");
		DeleteVoteParams(vM);
		VoteFailed(vM);
	}
	else	// Otherwise, we set up the second stage of the tiered vote
	{
		LogUMCMessage("MAPVOTE (Tiered): Players voted for map group '%s'", cat);
		int		  vMapCount;

		// Get the number of valid nominations from the group
		ArrayList tempNoms = GetCatNominations(cat);
		bool	  stored_exclude;
		GetTrieValue(vM, "stored_exclude", stored_exclude);

		if (stored_exclude)
		{
			ArrayList catNoms = FilterNominationsArray(tempNoms);
			vMapCount		  = GetArraySize(catNoms);
			CloseHandle(catNoms);
		}
		else
		{
			vMapCount = GetArraySize(tempNoms);
		}
		CloseHandle(tempNoms);

		KeyValues stored_kv;
		GetTrieValue(vM, "stored_kv", stored_kv);

		// Jump to the map group
		stored_kv.Rewind();
		KeyValues kv = new KeyValues("umc_rotation");
		KvCopySubkeys(stored_kv, kv);

		if (!kv.JumpToKey(cat))
		{
			LogError("KV Error: Unable to find map group \"%s\". Try removing any punctuation from the group's name.", cat);
			CloseHandle(kv);
			return;
		}

		if (stored_exclude)
		{
			KeyValues stored_mapcycle;
			GetTrieValue(vM, "stored_mapcycle", stored_mapcycle);
			FilterMapGroup(kv, stored_mapcycle);
		}

		// Get the number of valid maps from the group
		vMapCount += CountMapsFromGroup(kv);

		// Return to the root.
		kv.GoBack();

		// Just parse the results as a normal map group vote if the total number of valid maps is 1.
		if (vMapCount <= 1)
		{
			LogUMCMessage("MAPVOTE (Tiered): Only one valid map found in group. Handling results as a Map Group Vote.");
			CloseHandle(kv);
			Handle_CatVoteWinner(vM, cat, disp, percentage);
			return;
		}

		// Setup timer to delay the next vote for a few seconds.
		SetTrieValue(vM, "tiered_delay", 4);

		// Display the first message
		DisplayTierMessage(5);
		KeyValues tieredKV = MakeSecondTieredCatExclusion(kv, cat);
		CloseHandle(kv);

		// Setup timer to delay the next vote for a few seconds.
		DataPack pack = new DataPack();
		CreateDataTimer(1.0, Handle_TieredVoteTimer, pack, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
		WritePackCell(pack, vM);
		WritePackCell(pack, tieredKV);
	}

	char stored_end_sound[PLATFORM_MAX_PATH];
	GetTrieString(vM, "stored_end_sound", stored_end_sound, sizeof(stored_end_sound));

	// Play the vote completed sound if the vote completed sound is defined.
	if (strlen(stored_end_sound) > 0)
	{
		EmitSoundToAllAny(stored_end_sound);
	}
}

// Called when the timer for the tiered end-of-map vote triggers.
public Action Handle_TieredVoteTimer(Handle timer, DataPack pack)
{
	pack.Reset();
	StringMap vM = pack.ReadCell();

	bool	  vote_inprogress;
	GetTrieValue(vM, "in_progress", vote_inprogress);

	if (!vote_inprogress)
	{
		VoteFailed(vM);
		DeleteVoteParams(vM);
		return Plugin_Stop;
	}

	int tiered_delay;
	GetTrieValue(vM, "tiered_delay", tiered_delay);

	DisplayTierMessage(tiered_delay);

	if (tiered_delay > 0)
	{
		if (strlen(g_Countdown_Sound) > 0)
		{
			EmitSoundToAllAny(g_Countdown_Sound);
		}
		SetTrieValue(vM, "tiered_delay", tiered_delay - 1);
		return Plugin_Continue;
	}

	if (IsVMVoteInProgress(vM))
	{
		return Plugin_Continue;
	}

	KeyValues tieredKV = pack.ReadCell();

	// Log a message
	LogUMCMessage("MAPVOTE (Tiered): Starting second stage of tiered vote.");

	KeyValues stored_mapcycle;
	bool	  stored_scramble, stored_ignoredupes, stored_strictnoms, stored_exclude;
	GetTrieValue(vM, "stored_mapcycle", stored_mapcycle);
	GetTrieValue(vM, "stored_scramble", stored_scramble);
	GetTrieValue(vM, "stored_ignoredupes", stored_ignoredupes);
	GetTrieValue(vM, "stored_strictnoms", stored_strictnoms);
	GetTrieValue(vM, "stored_exclude", stored_exclude);

	// Initialize the menu.
	ArrayList options = new ArrayList();

	UMC_BuildOptionsError error = BuildMapVoteItems(
		  vM, options, stored_mapcycle, tieredKV,
		  stored_scramble, false,
		  false, stored_ignoredupes,
		  stored_strictnoms, true, stored_exclude);

	if (error == BuildOptionsError_Success)
	{
		char stored_start_sound[PLATFORM_MAX_PATH];	   //, String:adminFlags[64];
		GetTrieString(vM, "stored_start_sound", stored_start_sound, sizeof(stored_start_sound));
		// GetTrieString(vM, "stored_adminflags", adminFlags, sizeof(adminFlags));

		int users[MAXPLAYERS + 1];
		int numClients;
		int clients[MAXPLAYERS + 1];
		GetTrieArray2(vM, "stored_users", users, sizeof(users), numClients);
		ConvertUserIDsToClients(users, clients, numClients);

		SetTrieValue(vM, "stored_type", VoteType_Map);

		int stored_votetime;
		GetTrieValue(vM, "stored_votetime", stored_votetime);

		// vote_active = true;
		bool vote_active = PerformVote(vM, VoteType_Map, options, stored_votetime, clients, numClients, stored_start_sound);

		FreeOptions(options);

		if (!vote_active)
		{
			DeleteVoteParams(vM);
			ClearVoteArrays(vM);
			VoteFailed(vM);
		}
	}
	else
	{
		LogError("MAPVOTE (Tiered): Unable to create second stage vote menu. Vote aborted.");
		VoteFailed(vM);
		DeleteVoteParams(vM);
	}

	return Plugin_Stop;
}

// Extend the current map.
void ExtendMap(StringMap vM)
{
	DisableVoteInProgress(vM);
	float extend_timestep;
	int	  extend_roundstep;
	int	  extend_fragstep;
	GetTrieValue(vM, "extend_timestep", extend_timestep);
	GetTrieValue(vM, "extend_roundstep", extend_roundstep);
	GetTrieValue(vM, "extend_fragstep", extend_fragstep);

	// Generic/Used in most games
	if (g_Cvar_MaxRounds != INVALID_HANDLE && GetConVarInt(g_Cvar_MaxRounds) > 0)
	{
		SetConVarInt(g_Cvar_MaxRounds, GetConVarInt(g_Cvar_MaxRounds) + extend_roundstep);
	}
	if (g_Cvar_WinLimit != INVALID_HANDLE && GetConVarInt(g_Cvar_WinLimit) > 0)
	{
		SetConVarInt(g_Cvar_WinLimit, GetConVarInt(g_Cvar_WinLimit) + extend_roundstep);
	}
	if (g_Cvar_FragLimit != INVALID_HANDLE && GetConVarInt(g_Cvar_FragLimit) > 0)
	{
		SetConVarInt(g_Cvar_FragLimit, GetConVarInt(g_Cvar_FragLimit) + extend_fragstep);
	}
	// ZPS specific
	if (g_Cvar_ZpsMaxRnds != INVALID_HANDLE && GetConVarInt(g_Cvar_ZpsMaxRnds) > 0)
	{
		SetConVarInt(g_Cvar_ZpsMaxRnds, GetConVarInt(g_Cvar_ZpsMaxRnds) + extend_roundstep);
	}
	if (g_Cvar_ZpoMaxRnds != INVALID_HANDLE && GetConVarInt(g_Cvar_ZpoMaxRnds) > 0)
	{
		SetConVarInt(g_Cvar_ZpoMaxRnds, GetConVarInt(g_Cvar_ZpoMaxRnds) + extend_roundstep);
	}

	// Extend the time limit.
	ExtendMapTimeLimit(RoundToNearest(extend_timestep * 60));

	// Execute the extend command
	char command[64];
	GetConVarString(g_Cvar_Extend_Command, command, sizeof(command));
	if (strlen(command) > 0)
	{
		ServerCommand(command);
	}
	// Call the extend forward.
	Call_StartForward(g_Extend_Forward);
	Call_Finish();

	// Log some stuff.
	LogUMCMessage("MAPVOTE: Map extended.");
}

// Called when the vote has failed.
void VoteFailed(StringMap vM)
{
	DisableVoteInProgress(vM);
	Call_StartForward(g_Failure_Forward);
	Call_Finish();
}

// Sets the next map and when to change to it.
void DoMapChange(UMC_ChangeMapTime when, KeyValues kv, const char[] map, const char[] group, const char[] reason, const char[] display = "")
{
	// Set the next map group
	strcopy(g_Next_Cat, sizeof(g_Next_Cat), group);

	// Set the next map in SM
	LogUMCMessage("Setting nextmap to: %s", map);
	SetNextMap(map);

	// GE:S Fix
	if (g_Cvar_NextLevel != null)
	{
		g_Cvar_NextLevel.SetString(map);
	}

	// Call UMC forward for next map being set
	KeyValues new_kv;

	if (kv != null)
	{
		new_kv = CreateKeyValues("umc_rotation");
		KvCopySubkeys(kv, new_kv);
	}
	else
	{
		LogUMCMessage("Mapcycle handle is invalid. Map change reason: %s", reason);
	}

	Call_StartForward(g_Nextmap_Forward);
	Call_PushCell(new_kv);
	Call_PushString(map);
	Call_PushString(group);
	Call_PushString(display);
	Call_Finish();

	if (new_kv != null)
	{
		CloseHandle(new_kv);
	}

	// Perform the map change setup
	switch (when)
	{
		case ChangeMapTime_Now:	   // We change the map in 5 seconds.
		{
			char game[20];
			GetGameFolderName(game, sizeof(game));
			if (!StrEqual(game, "gesource", false) && !StrEqual(game, "zps", false))
			{
				// Routine by Tsunami to end the map
				int iGameEnd = FindEntityByClassname(-1, "game_end");
				if (iGameEnd == -1 && (iGameEnd = CreateEntityByName("game_end")) == -1)
				{
					ForceChangeInFive(map, reason);
				}
				else
				{
					AcceptEntityInput(iGameEnd, "EndGame");
				}
			}
			else
			{
				ForceChangeInFive(map, reason);
			}
		}
		case ChangeMapTime_RoundEnd:	// We change the map at the end of the round.
		{
			LogUMCMessage("%s: Map will change to '%s' at the end of the round.", reason, map);

			g_Change_Map_Round = true;

			// Print a message.
			PrintToChatAll("[UMC] %t", "Map Change at Round End");
		}
	}
}

// Deletes the stored parameters for the vote.
void DeleteVoteParams(StringMap vM)
{
	KeyValues stored_kv;
	KeyValues stored_mapcycle;
	GetTrieValue(vM, "stored_kv", stored_kv);
	GetTrieValue(vM, "stored_mapcycle", stored_mapcycle);

	CloseHandle(stored_kv);
	CloseHandle(stored_mapcycle);

	SetTrieValue(vM, "stored_kv", INVALID_HANDLE);
	SetTrieValue(vM, "stored_mapcycle", INVALID_HANDLE);
}

//************************************************************************************************//
//                                        VALIDITY TESTING                                        //
//************************************************************************************************//
// Checks to see if the server has the required number of players for the given map, and is in the
// required time range.
//    kv:       a mapcycle whose traversal stack is currently at the level of the map's category.
//    map:      the map to check
bool IsValidMapFromCat(KeyValues kv, KeyValues mapcycle, const char[] map, bool isNom = false, bool forMapChange = true)
{
	char catName[MAP_LENGTH];
	kv.GetSectionName(catName, sizeof(catName));

	// Return that the map is not valid if the map doesn't exist in the category.
	if (!kv.JumpToKey(map))
	{
		return false;
	}

	// Determine if the map is valid, store the answer.
	bool result = IsValidMap(kv, mapcycle, catName, isNom, forMapChange);

	// Rewind back to the category.
	kv.GoBack();

	// Return the result.
	return result;
}

// Determines if the server has the required number of players for the given map.
//     kv:       a mapcycle whose traversal stack is currently at the level of the map.
bool IsValidMap(KeyValues kv, KeyValues mapcycle, const char[] groupName, bool isNom = false, bool forMapChange = true)
{
	char mapName[MAP_LENGTH];
	kv.GetSectionName(mapName, sizeof(mapName));

	if (!IsMapValid(mapName))
	{
		LogUMCMessage("WARNING: Map \"%s\" does not exist on the server. (Group: \"%s\")", mapName, groupName);
		return false;
	}

	Action	  result;

	KeyValues new_kv = new KeyValues("umc_rotation");
	KvCopySubkeys(mapcycle, new_kv);

	Call_StartForward(g_Exclude_Forward);
	Call_PushCell(new_kv);
	Call_PushString(mapName);
	Call_PushString(groupName);
	Call_PushCell(isNom);
	Call_PushCell(forMapChange);
	Call_Finish(result);

	CloseHandle(new_kv);

	return result == Plugin_Continue;
}

// Determines if the server has the required number of players for the given category and the required time.
//     kv: a mapcycle whose traversal stack is currently at the level of the category.
bool IsValidCat(KeyValues kv, KeyValues mapcycle, bool isNom = false, bool forMapChange = true)
{
	// Get the name of the cat.
	char catName[MAP_LENGTH];
	kv.GetSectionName(catName, sizeof(catName));

	// Return that the map is invalid if there are no maps to check.
	if (!kv.GotoFirstSubKey())
	{
		return false;
	}

	// Check to see if the server's player count satisfies the min/max conditions for a map in the category.
	do
	{
		// Return to the category level of the mapcycle and return true if a map was found to be satisfied by the server's player count.
		if (IsValidMap(kv, mapcycle, catName, isNom, forMapChange))
		{
			KvGoBack(kv);
			return true;
		}
	}
	while (kv.GotoNextKey());	 // Goto the next map in the category.

	// Return to the category level.
	kv.GoBack();

	// No maps in the category can be played with the current amount of players on the server.
	return false;
}

// Counts the number of maps in the given group.
int CountMapsFromGroup(KeyValues kv)
{
	int result = 0;
	if (!kv.GotoFirstSubKey())
	{
		return result;
	}

	do
	{
		result++;
	}
	while (kv.GotoNextKey());

	kv.GoBack();

	return result;
}

// Calculates the weight of a map by running it through all of the weight modifiers.
float GetMapWeight(KeyValues mapcycle, const char[] map, const char[] group)
{
	// Get the starting weight
	g_Current_Weight = 1.0;

	KeyValues kv	 = new KeyValues("umc_rotation");
	KvCopySubkeys(mapcycle, kv);

	g_Reweight_Active = true;

	Call_StartForward(g_Reweight_Forward);
	Call_PushCell(kv);
	Call_PushString(map);
	Call_PushString(group);
	Call_Finish();

	g_Reweight_Active = false;

	CloseHandle(kv);

	// And return our calculated weight.
	return (g_Current_Weight >= 0.0) ? g_Current_Weight : 0.0;
}

// Calculates the weight of a map group
float GetMapGroupWeight(KeyValues originalMapcycle, const char[] group)
{
	g_Current_Weight = 1.0;

	KeyValues kv	 = new KeyValues("umc_rotation");
	KvCopySubkeys(originalMapcycle, kv);

	g_Reweight_Active = true;

	Call_StartForward(g_Reweight_Group_Forward);
	Call_PushCell(kv);
	Call_PushString(group);
	Call_Finish();

	g_Reweight_Active = false;

	CloseHandle(kv);

	return (g_Current_Weight >= 0.0) ? g_Current_Weight : 0.0;
}

// Calculates weights for a mapcycle
void WeightMapcycle(KeyValues kv, KeyValues originalMapcycle)
{
	if (!kv.GotoFirstSubKey())
	{
		return;
	}

	char group[MAP_LENGTH];
	do
	{
		kv.GetSectionName(group, sizeof(group));

		kv.SetFloat(WEIGHT_KEY, GetMapGroupWeight(originalMapcycle, group));

		WeightMapGroup(kv, originalMapcycle);
	}
	while (kv.GotoNextKey());

	kv.GoBack();
}

// Calculates weights for a map group.
void WeightMapGroup(KeyValues kv, KeyValues originalMapcycle)
{
	char map[MAP_LENGTH], group[MAP_LENGTH];
	kv.GetSectionName(group, sizeof(group));
	if (!kv.GotoFirstSubKey())
	{
		return;
	}

	do
	{
		kv.GetSectionName(map, sizeof(map));

		kv.SetFloat(WEIGHT_KEY, GetMapWeight(originalMapcycle, map, group));
	}
	while (kv.GotoNextKey());

	kv.GoBack();
}

// Returns the weight of a given map or map group
float GetWeight(KeyValues kv)
{
	return kv.GetFloat(WEIGHT_KEY, 1.0);
}

// Filters a mapcycle with all invalid entries filtered out.
void FilterMapcycle(KeyValues kv, KeyValues originalMapcycle, bool isNom = false, bool forMapChange = true, bool deleteEmpty = true)
{
	// Do nothing if there are no map groups.
	if (!kv.GotoFirstSubKey())
	{
		return;
	}

	char group[MAP_LENGTH];
	for (;;)
	{
		// Filter all the maps.
		FilterMapGroup(kv, originalMapcycle, isNom, forMapChange);

		// Delete the group if there are no valid maps in it.
		if (deleteEmpty)
		{
			if (!kv.GotoFirstSubKey())
			{
				kv.GetSectionName(group, sizeof(group));

				if (kv.DeleteThis() == -1)
				{
					return;
				}
				else
				{
					continue;
				}
			}

			kv.GoBack();
		}

		if (!kv.GotoNextKey())
		{
			break;
		}
	}

	// Return to the root.
	kv.GoBack();
}

// Filters the kv at the level of the map group.
void FilterMapGroup(KeyValues kv, KeyValues mapcycle, bool isNom = false, bool forMapChange = true)
{
	char group[MAP_LENGTH];
	kv.GetSectionName(group, sizeof(group));

	if (!kv.GotoFirstSubKey())
	{
		return;
	}

	char mapName[MAP_LENGTH];
	for (;;)
	{
		if (!IsValidMap(kv, mapcycle, group, isNom, forMapChange))
		{
			kv.GetSectionName(mapName, sizeof(mapName));
			if (kv.DeleteThis() == -1)
			{
				return;
			}
		}
		else
		{
			if (!kv.GotoNextKey())
			{
				break;
			}
		}
	}

	kv.GoBack();
}

//************************************************************************************************//
//                                           NOMINATIONS                                          //
//************************************************************************************************//
// Filters an array of nominations so that only valid maps remain.
ArrayList FilterNominationsArray(ArrayList nominations, bool forMapChange = true)
{
	ArrayList result = new ArrayList();

	int		  size	 = GetArraySize(nominations);
	StringMap nom;
	char	  gBuffer[MAP_LENGTH], mBuffer[MAP_LENGTH];
	KeyValues mapcycle;
	KeyValues kv;
	for (int i = 0; i < size; i++)
	{
		nom = GetArrayCell(nominations, i);
		GetTrieString(nom, MAP_TRIE_MAP_KEY, mBuffer, sizeof(mBuffer));
		GetTrieString(nom, MAP_TRIE_GROUP_KEY, gBuffer, sizeof(gBuffer));
		GetTrieValue(nom, "mapcycle", mapcycle);

		kv = new KeyValues("umc_rotation");
		KvCopySubkeys(mapcycle, kv);

		if (!kv.JumpToKey(gBuffer))
		{
			continue;
		}

		if (IsValidMapFromCat(kv, mapcycle, mBuffer, .isNom = true, .forMapChange = forMapChange))
		{
			PushArrayCell(result, nom);
		}

		CloseHandle(kv);
	}

	return result;
}

// Nominated a map and group
bool InternalNominateMap(KeyValues kv, const char[] map, const char[] group, int client, const char[] nomGroup)
{
	if (FindNominationIndex(map, group) != -1)
	{
		return false;
	}

	// Create the nomination trie.
	StringMap nomination = CreateMapTrie(map, StrEqual(nomGroup, INVALID_GROUP) ? group : nomGroup);
	SetTrieValue(nomination, "client", client);	   // Add the client
	SetTrieValue(nomination, "mapcycle", kv);	   // Add the mapcycle
	SetTrieString(nomination, "nom_group", group);

	// Remove the client's old nomination, if it exists.
	int index = FindClientNomination(client);
	if (index != -1)
	{
		StringMap oldNom = g_Nominations_Arr.Get(index);
		char	  oldName[MAP_LENGTH];
		GetTrieString(oldNom, MAP_TRIE_MAP_KEY, oldName, sizeof(oldName));
		Call_StartForward(g_Nomination_Reset_Forward);
		Call_PushString(oldName);
		Call_PushCell(client);
		Call_Finish();

		KeyValues nomKV;
		GetTrieValue(oldNom, "mapcycle", nomKV);
		CloseHandle(nomKV);
		CloseHandle(oldNom);
		g_Nominations_Arr.Erase(index);
	}

	// Display Bottom
	if (!g_Cvar_MapNom_Display.BoolValue)
	{
		InsertArrayCell(g_Nominations_Arr, 0, nomination);
	}
	// Display Top
	if (g_Cvar_MapNom_Display.BoolValue)
	{
		g_Nominations_Arr.Push(nomination);
	}

	return true;
}

// Returns the index of the given client in the nomination pool. -1 is returned if the client isn't in the pool.
int FindClientNomination(int client)
{
	int buffer;
	int arraySize = GetArraySize(g_Nominations_Arr);
	for (int i = 0; i < arraySize; i++)
	{
		GetTrieValue(g_Nominations_Arr.Get(i), "client", buffer);
		if (buffer == client)
		{
			return i;
		}
	}
	return -1;
}

// Utility function to find the index of a map in the nomination pool.
int FindNominationIndex(const char[] map, const char[] group)
{
	char	  mName[MAP_LENGTH];
	char	  gName[MAP_LENGTH];
	StringMap nom;
	int		  arraySize = GetArraySize(g_Nominations_Arr);
	for (int i = 0; i < arraySize; i++)
	{
		nom = g_Nominations_Arr.Get(i);
		GetTrieString(nom, MAP_TRIE_MAP_KEY, mName, sizeof(mName));
		GetTrieString(nom, MAP_TRIE_GROUP_KEY, gName, sizeof(gName));
		if (StrEqual(mName, map, false) && StrEqual(gName, group, false))
		{
			return i;
		}
	}
	return -1;
}

// Utility function to get all nominations from a group.
ArrayList GetCatNominations(const char[] cat)
{
	ArrayList arr1 = FilterNominations(MAP_TRIE_GROUP_KEY, cat);
	ArrayList arr2 = FilterNominations(MAP_TRIE_GROUP_KEY, INVALID_GROUP);
	ArrayAppend(arr1, arr2);
	CloseHandle(arr2);
	return arr1;
}

// Utility function to filter out nominations whose value for the given key matches the given value.
ArrayList FilterNominations(const char[] key, const char[] value)
{
	ArrayList result = new ArrayList();
	StringMap buffer;
	char	  temp[255];
	int		  arraySize = GetArraySize(g_Nominations_Arr);
	for (int i = 0; i < arraySize; i++)
	{
		buffer = GetArrayCell(g_Nominations_Arr, i);
		GetTrieString(GetArrayCell(g_Nominations_Arr, i), key, temp, sizeof(temp));
		if (StrEqual(temp, value, false))
		{
			PushArrayCell(result, buffer);
		}
	}
	return result;
}

// Clears all stored nominations.
void ClearNominations()
{
	int		  size = GetArraySize(g_Nominations_Arr);
	StringMap nomination;
	int		  owner;
	char	  map[MAP_LENGTH];
	for (int i = 0; i < size; i++)
	{
		nomination = g_Nominations_Arr.Get(i);
		GetTrieString(nomination, MAP_TRIE_MAP_KEY, map, sizeof(map));
		GetTrieValue(nomination, "client", owner);

		Call_StartForward(g_Nomination_Reset_Forward);
		Call_PushString(map);
		Call_PushCell(owner);
		Call_Finish();

		KeyValues nomKV;
		GetTrieValue(nomination, "mapcycle", nomKV);
		CloseHandle(nomKV);
		CloseHandle(nomination);
	}
	g_Nominations_Arr.Clear();
}

//************************************************************************************************//
//                                         RANDOM NEXTMAP                                         //
//************************************************************************************************//

// bool:GetRandomMapFromCycle(Handle:kv, const String:group[], String:buffer[], size, String:gBuffer[],
//                            gSize, Handle:exMaps, Handle:exGroups, numEGroups, bool:isNom=false,
//                            bool:forMapChange=true)
bool GetRandomMapFromCycle(KeyValues kv, const char[] group, char[] buffer, int size, char[] gBuffer, int gSize)
{
	// Buffer to store the name of the category we will be looking for a map in.
	char gName[MAP_LENGTH];

	strcopy(gName, sizeof(gName), group);

	if (StrEqual(gName, INVALID_GROUP, false) || !kv.JumpToKey(gName))
	{
		if (!GetRandomCat(kv, gName, sizeof(gName)))
		{
			LogError("RANDOM MAP: Cannot pick a random map, no available map groups found in rotation.");
			return false;
		}
		kv.JumpToKey(gName);
	}

	// Buffer to store the name of the new map.
	char mapName[MAP_LENGTH];

	// Log an error and fail if there were no maps found in the category.
	if (!GetRandomMap(kv, mapName, sizeof(mapName)))
	{
		LogError("RANDOM MAP: Cannot pick a random map, no available maps found. Parent Group: %s", gName);
		return false;
	}

	kv.GoBack();

	// Copy results into the buffers.
	strcopy(buffer, size, mapName);
	strcopy(gBuffer, gSize, gName);

	// Return success!
	return true;
}

// Selects a random category based off of the supplied weights for the categories.
//     kv:       a mapcycle whose traversal stack is currently at the root level.
//     buffer:      a string to store the selected category in.
//     key:      the key containing the weight information (most likely 'group_weight')
//     excluded: adt_array of excluded maps
// bool:GetRandomCat(Handle:kv, String:buffer[], size, Handle:excludedCats, numExcludedCats,
//                   Handle:excluded, bool:isNom=false, bool:forMapChange=true)
bool GetRandomCat(KeyValues kv, char[] buffer, int size)
{
	// Fail if there are no categories in the mapcycle.
	if (!kv.GotoFirstSubKey())
	{
		return false;
	}

	int		  index		= 0;											  // counter of categories in the random pool
	ArrayList nameArr	= new ArrayList(ByteCountToCells(MAP_LENGTH));	  // Array to store possible category names.
	ArrayList weightArr = new ArrayList();								  // Array to store possible category weights.

	// Add a category to the random pool.
	do
	{
		char temp[MAP_LENGTH];	  // Buffer to store the name of the category.

		// Get the name of the category.
		kv.GetSectionName(temp, sizeof(temp));

		// Add the category to the random pool.
		weightArr.Push(GetWeight(kv));
		nameArr.PushString(temp);

		// One more category in the pool.
		index++;
	}
	while (kv.GotoNextKey());	 // Do this for each category.

	// Return to the root level.
	kv.GoBack();

	// Fail if no categories are selectable.
	if (index == 0)
	{
		CloseHandle(nameArr);
		CloseHandle(weightArr);
		return false;
	}

	// Use weights to randomly select a category from the pool.
	bool result = GetWeightedRandomSubKey(buffer, size, weightArr, nameArr);

	// Close the pool.
	CloseHandle(nameArr);
	CloseHandle(weightArr);

	// Booyah!
	return result;
}
