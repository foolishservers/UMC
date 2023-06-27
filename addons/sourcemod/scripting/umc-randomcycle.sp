/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *                               Ultimate Mapchooser - Random Cycle                              *
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

#define NEXT_MAPGROUP_KEY "next_mapgroup"

// Plugin Information
public Plugin myinfo =
{
	name		= "[UMC] Random Cycle",
	author		= "Sandy",
	description = "Extends Ultimate Mapchooser to provide random selecting of the next map.",
	version		= PL_VERSION,
	url			= "http://forums.alliedmods.net/showthread.php?t=134190"
};

////----CONVARS-----/////
ConVar cvar_filename;
ConVar cvar_randnext;
ConVar cvar_randnext_mem;
ConVar cvar_randnext_catmem;
ConVar cvar_start;
////----/CONVARS-----/////

// Mapcycle KV
KeyValues map_kv;
KeyValues umc_mapcycle;

// Memory queues
ArrayList randnext_mem_arr;
ArrayList randnext_catmem_arr;

// Stores the next category to randomly select a map from.
char next_rand_cat[MAP_LENGTH];

// Used to trigger the selection if the mode doesn't support the "game_end" event
UserMsg VGuiMenu;
bool intermission_called;

// Flag
bool setting_map;	  // Are we setting the nextmap at the end of this map?

//************************************************************************************************//
//                                        SOURCEMOD EVENTS                                        //
//************************************************************************************************//
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("GetUserMessageType");
	return APLRes_Success;
}

// Called when the plugin is finished loading.
public void OnPluginStart()
{
	cvar_start = CreateConVar(
		"sm_umc_randcycle_start",
		"1",
		"Specifies when to select the next map.\n 0 - Map Start,\n 1 - Map End",
		0, true, 0.0, true, 1.0);

	cvar_randnext_catmem = CreateConVar(
		"sm_umc_randcycle_groupexclude",
		"0",
		"Specifies how many past map groups to exclude when picking a random map.",
		0, true, 0.0);

	cvar_randnext = CreateConVar(
		"sm_umc_randcycle_enabled",
		"1",
		"Enables random selection of the next map at the end of each map if a vote hasn't taken place.",
		0, true, 0.0, true, 1.0);

	cvar_randnext_mem = CreateConVar(
		"sm_umc_randcycle_mapexclude",
		"4",
		"Specifies how many past maps to exclude when picking a random map. 1 = Current Map Only",
		0, true, 0.0);

	cvar_filename = CreateConVar(
		"sm_umc_randcycle_cyclefile",
		"umc_mapcycle.txt",
		"File to use for Ultimate Mapchooser's map rotation.");

	// Create the config if it doesn't exist, and then execute it.
	AutoExecConfig(true, "umc-randomcycle");

	// Admin commmand to pick a random nextmap.
	RegAdminCmd(
		"sm_umc_randcycle_picknextmapnow",
		Command_Random,
		ADMFLAG_CHANGEMAP,
		"Makes Ultimate Mapchooser pick a random nextmap.");

	// Hook end of game.
	HookEventEx("dod_game_over", Event_GameEnd);		 // DoD
	HookEventEx("teamplay_game_over", Event_GameEnd);	 // TF2
	HookEventEx("tf_game_over", Event_GameEnd);			 // TF2 (mp_winlimit)
	HookEventEx("game_newmap", Event_GameEnd);			 // Insurgency
	HookEventEx("cs_intermission", Event_GameEnd);		 // CS:GO

	// Hook intermission
	char game[20];
	GetGameFolderName(game, sizeof(game));
	if (!StrEqual(game, "tf", false) && !StrEqual(game, "dod", false) && !StrEqual(game, "insurgency", false))
	{
		LogUMCMessage("SETUP: Hooking intermission...");
		VGuiMenu = GetUserMessageId("VGUIMenu");
		HookUserMessage(VGuiMenu, _VGuiMenu);
	}

	// Hook cvar change
	HookConVarChange(cvar_randnext_mem, Handle_RandNextMemoryChange);

	// Initialize our memory arrays
	int numCells		= ByteCountToCells(MAP_LENGTH);
	randnext_mem_arr	= new ArrayList(numCells);
	randnext_catmem_arr = new ArrayList(numCells);
}

//************************************************************************************************//
//                                           GAME EVENTS                                          //
//************************************************************************************************//
// Called after all config files were executed.
public void OnConfigsExecuted()
{
	intermission_called = false;
	setting_map			= ReloadMapcycle();

	// Grab the name of the current map.
	char mapName[MAP_LENGTH];
	GetCurrentMap(mapName, sizeof(mapName));
	char groupName[MAP_LENGTH];
	UMC_GetCurrentMapGroup(groupName, sizeof(groupName));

	if (setting_map && StrEqual(groupName, INVALID_GROUP, false))
	{
		KvFindGroupOfMap(umc_mapcycle, mapName, groupName, sizeof(groupName));
	}

	SetupNextRandGroup(mapName, groupName);

	// Add the map to all the memory queues.
	int mapmem = cvar_randnext_mem.IntValue;
	int catmem = cvar_randnext_catmem.IntValue;
	AddToMemoryArray(mapName, randnext_mem_arr, mapmem);
	AddToMemoryArray(groupName, randnext_catmem_arr, (mapmem > catmem) ? mapmem : catmem);

	if (setting_map)
	{
		RemovePreviousMapsFromCycle();
	}

	if (!cvar_start.BoolValue)
	{
		LogUMCMessage("Selecting random next map due to map starting.");
		DoRandomNextMap();
	}
}

// Called when intermission window is active. Necessary for mods without "game_end" event.
public Action _VGuiMenu(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	// Do nothing if we have already seen the intermission.
	if (intermission_called)
	{
		return Plugin_Continue;
	}

	char type[10];
	BfReadString(msg, type, sizeof(type));

	if (strcmp(type, "scores", false) == 0)
	{
		// Wtf? BfReadByte(msg) == 1 && BfReadByte(msg) == 0
		if (BfReadByte(msg) == 1 || BfReadByte(msg) == 0)
		{
			intermission_called = true;
			Event_GameEnd(null, "", false);
		}
	}

	return Plugin_Continue;
}

// Called when the game ends. Used to trigger random selection of the next map.
public void Event_GameEnd(Event event, const char[] name, bool dontBroadcast)
{
	// Select and change to a random map if the cvar to do so is enabled AND
	// we haven't completed an end-of-map vote AND we haven't completed an RTV.
	if (cvar_start.BoolValue && cvar_randnext.BoolValue && setting_map)
	{
		LogUMCMessage("Selecting random next map due to map ending.");
		DoRandomNextMap();
	}
}

//************************************************************************************************//
//                                              SETUP                                             //
//************************************************************************************************//
// Fetches the set next group for the given map and group in the mapcycle.
void SetupNextRandGroup(const char[] map, const char[] group)
{
	char gNextGroup[MAP_LENGTH];

	if (umc_mapcycle == null || StrEqual(group, INVALID_GROUP, false))
	{
		strcopy(next_rand_cat, sizeof(next_rand_cat), INVALID_GROUP);
		return;
	}

	umc_mapcycle.Rewind();
	if (umc_mapcycle.JumpToKey(group))
	{
		umc_mapcycle.GetString(NEXT_MAPGROUP_KEY, gNextGroup, sizeof(gNextGroup), INVALID_GROUP);
		if (umc_mapcycle.JumpToKey(map))
		{
			umc_mapcycle.GetString(NEXT_MAPGROUP_KEY, next_rand_cat, sizeof(next_rand_cat), gNextGroup);
			umc_mapcycle.GoBack();
		}
		umc_mapcycle.GoBack();
	}
}

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
	FilterMapcycleFromArrays(map_kv, randnext_mem_arr, randnext_catmem_arr, cvar_randnext_catmem.IntValue);
}

//************************************************************************************************//
//                                          CVAR CHANGES                                          //
//************************************************************************************************//
// Called when the number of excluded previous maps from random selection of the next map has changed.
public void Handle_RandNextMemoryChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	// Trim the memory array for random selection of the next map.
	// We pass 1 extra to the argument in order to account for the current map, which should always be excluded.
	TrimArray(randnext_mem_arr, StringToInt(newValue));
}

//************************************************************************************************//
//                                            COMMANDS                                            //
//************************************************************************************************//
// Called when the command to pick a random nextmap is called
public Action Command_Random(int client, int args)
{
	if (setting_map || map_kv != null)
	{
		LogUMCMessage("User %L requested a random map be selected now.", client);
		DoRandomNextMap();
	}
	else
	{
		ReplyToCommand(client, "[UMC] Mapcycle is invalid, cannot pick a map.");
	}

	return Plugin_Handled;
}

//************************************************************************************************//
//                                         RANDOM NEXTMAP                                         //
//************************************************************************************************//
// Sets a random next map. Returns true on success.
void DoRandomNextMap()
{
	char nextMap[MAP_LENGTH], nextGroup[MAP_LENGTH];
	if (UMC_GetRandomMap(map_kv, umc_mapcycle, next_rand_cat, nextMap, sizeof(nextMap), nextGroup, sizeof(nextGroup), false, true))
	{
		UMC_SetNextMap(map_kv, nextMap, nextGroup, ChangeMapTime_MapEnd);
	}
	else
	{
		LogUMCMessage("Failed to find a suitable random map.");
	}
}

//************************************************************************************************//
//                                   ULTIMATE MAPCHOOSER EVENTS                                   //
//************************************************************************************************//
// Called when UMC has set a next map.
public void UMC_OnNextmapSet(KeyValues kv, const char[] map, const char[] group, const char[] display)
{
	LogUMCMessage("Disabling random nextmap selection.");
	setting_map = false;
}

// Called when UMC requests that the mapcycle should be reloaded.
public void UMC_RequestReloadMapcycle()
{
	bool reloaded = ReloadMapcycle();
	if (reloaded)
	{
		RemovePreviousMapsFromCycle();
	}

	setting_map = reloaded && setting_map;
}

// Called when UMC requests that the mapcycle is printed to the console.
public void UMC_DisplayMapCycle(int client, bool filtered)
{
	PrintToConsole(client, "Module: Random Mapcycle");
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
