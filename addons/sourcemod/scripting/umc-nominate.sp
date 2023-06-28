/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *                               Ultimate Mapchooser - Nominations                               *
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

#define NOMINATE_ADMINFLAG_KEY "nominate_flags"

// Plugin Information
public Plugin myinfo =
{
	name		= "[UMC] Nominations",
	author		= PL_AUTHOR,
	description = "Extends Ultimate Mapchooser to allow players to nominate maps.",
	version		= PL_VERSION,
	url			= "http://forums.alliedmods.net/showthread.php?t=134190"
};

////----CONVARS-----/////
ConVar cvar_filename;
ConVar cvar_nominate;
ConVar cvar_nominate_tiered;
ConVar cvar_mem_map;
ConVar cvar_mem_group;
ConVar cvar_sort;
ConVar cvar_flags;
ConVar cvar_nominate_time;
ConVar cvar_nominate_weight;
////----/CONVARS-----/////

// Mapcycle
KeyValues map_kv;
KeyValues umc_mapcycle;

// Memory queues. Used to store the previously played maps.
ArrayList vote_mem_arr;
ArrayList vote_catmem_arr;

ArrayList nom_menu_groups[MAXPLAYERS + 1]	 = { null, ... };
ArrayList nom_menu_nomgroups[MAXPLAYERS + 1] = { null, ... };
// EACH INDEX OF THE ABOVE TWO ARRAYS CORRESPONDS TO A NOMINATION MENU FOR A PARTICULAR CLIENT.

// Has a vote neem completed?
bool vote_completed;

// Can we nominate?
bool can_nominate;

bool db_createTableSuccess = false;

char db_createTable[] = "CREATE TABLE IF NOT EXISTS `umc_weight` (`map` VARCHAR(256) PRIMARY KEY, `weight` INT NOT NULL);";
char db_insertRow[]	= "INSERT IGNORE INTO `umc_weight` (`map`, `weight`) VALUES ('%s', 0);";
char db_selectRow[]	= "SELECT `weight` FROM `umc_weight` WHERE `map` = '%s' LIMIT 1;";

// TODO: Add cvar for enable/disable exclusion from prev. maps.
//       Possible bug: nomination menu doesn't want to display twice for a client in a map.
//       Alphabetize based off of display, not actual map name.
//
//       New map option called "nomination_group" that sets the "real" map group to be used when
//       the map is nominated for a vote. Useful for tiered nomination menu.
//************************************************************************************************//
//                                         SOURCEMOD EVENTS                                        //
//************************************************************************************************//
// Called when the plugin is finished loading.
public void OnPluginStart()
{
	cvar_flags = CreateConVar(
		"sm_umc_nominate_defaultflags",
		"",
		"Flags necessary for a player to nominate a map, if flags are not specified by a map in the mapcycle. If empty, all players can nominate.");

	cvar_sort = CreateConVar(
		"sm_umc_nominate_sorted",
		"0",
		"Determines the order of maps in the nomination menu.\n 0 - Same as mapcycle,\n 1 - Alphabetical",
		0, true, 0.0, true, 1.0);

	cvar_nominate_tiered = CreateConVar(
		"sm_umc_nominate_tiermenu",
		"0",
		"Organizes the nomination menu so that users select a group first, then a map.",
		0, true, 0.0, true, 1.0);

	cvar_nominate = CreateConVar(
		"sm_umc_nominate_enabled",
		"1",
		"Specifies whether players have the ability to nominate maps for votes.",
		0, true, 0.0, true, 1.0);

	cvar_filename = CreateConVar(
		"sm_umc_nominate_cyclefile",
		"umc_mapcycle.txt",
		"File to use for Ultimate Mapchooser's map rotation.");

	cvar_mem_group = CreateConVar(
		"sm_umc_nominate_groupexclude",
		"0",
		"Specifies how many past map groups to exclude from nominations.",
		0, true, 0.0);

	cvar_mem_map = CreateConVar(
		"sm_umc_nominate_mapexclude",
		"4",
		"Specifies how many past maps to exclude from nominations. 1 = Current Map Only",
		0, true, 0.0);

	cvar_nominate_time = CreateConVar(
		"sm_umc_nominate_duration",
		"20",
		"Specifies how long the nomination menu should remain open for. Minimum is 10 seconds!",
		0, true, 10.0);

	cvar_nominate_weight = CreateConVar(
		"sm_umc_nominate_minweight",
		"-1",
		"How much weight needed to appear in nominated list?",
		0, true, -1.0);

	// Create the config if it doesn't exist, and then execute it.
	AutoExecConfig(true, "umc-nominate");

	// Reg the nominate console cmd
	RegConsoleCmd("sm_nominate", Command_Nominate);

	// Make listeners for player chat. Needed to recognize chat commands ("rtv", etc.)
	AddCommandListener(OnPlayerChat, "say");
	AddCommandListener(OnPlayerChat, "say2");	 // Insurgency Only
	AddCommandListener(OnPlayerChat, "say_team");

	// Initialize our memory arrays
	int numCells	= ByteCountToCells(MAP_LENGTH);
	vote_mem_arr	= new ArrayList(numCells);
	vote_catmem_arr = new ArrayList(numCells);

	// Load the translations file
	LoadTranslations("ultimate-mapchooser.phrases");
}

//************************************************************************************************//
//                                           GAME EVENTS                                          //
//************************************************************************************************//
// Called after all config files were executed.
public void OnConfigsExecuted()
{
	// DEBUG_MESSAGE("Executing Nominate OnConfigsExecuted")

	can_nominate   = ReloadMapcycle();
	vote_completed = false;

	ArrayList groupArray;
	for (int i = 0; i < sizeof(nom_menu_groups); i++)
	{
		groupArray = nom_menu_groups[i];
		if (groupArray != null)
		{
			CloseHandle(groupArray);
			nom_menu_groups[i] = null;
		}
	}
	for (int i = 0; i < sizeof(nom_menu_nomgroups); i++)
	{
		groupArray = nom_menu_groups[i];
		if (groupArray != null)
		{
			CloseHandle(groupArray);
			nom_menu_groups[i] = null;
		}
	}

	// Grab the name of the current map.
	char mapName[MAP_LENGTH];
	GetCurrentMap(mapName, sizeof(mapName));

	char groupName[MAP_LENGTH];
	UMC_GetCurrentMapGroup(groupName, sizeof(groupName));

	if (can_nominate && StrEqual(groupName, INVALID_GROUP, false))
	{
		KvFindGroupOfMap(umc_mapcycle, mapName, groupName, sizeof(groupName));
	}

	// Add the map to all the memory queues.
	int mapmem = cvar_mem_map.IntValue;
	int catmem = cvar_mem_group.IntValue;
	AddToMemoryArray(mapName, vote_mem_arr, mapmem);
	AddToMemoryArray(groupName, vote_catmem_arr, (mapmem > catmem) ? mapmem : catmem);

	if (can_nominate)
	{
		RemovePreviousMapsFromCycle();
	}
}

// Called when a player types in chat.
// Required to handle user commands.
public Action OnPlayerChat(int client, const char[] command, int argc)
{
	// Return immediately if nothing was typed.
	if (argc == 0)
	{
		return Plugin_Continue;
	}

	if (!cvar_nominate.BoolValue)
	{
		return Plugin_Continue;
	}

	// Get what was typed.
	char text[80];
	GetCmdArg(1, text, sizeof(text));
	TrimString(text);
	char arg[MAP_LENGTH];
	int	 next = BreakString(text, arg, sizeof(arg));

	if (StrEqual(arg, "nominate", false))
	{
		if (vote_completed || !can_nominate)
		{
			PrintToChat(client, "[UMC] %t", "No Nominate Nextmap");
		}
		else	// Otherwise, let them nominate.
		{
			if (next != -1)
			{
				BreakString(text[next], arg, sizeof(arg));

				// Get the selected map.
				char groupName[MAP_LENGTH], nomGroup[MAP_LENGTH];

				if (!KvFindGroupOfMap(map_kv, arg, groupName, sizeof(groupName)))
				{
					// TODO: Change to translation phrase
					PrintToChat(client, "[UMC] Could not find map \"%s\"", arg);
				}
				else
				{
					map_kv.Rewind();

					map_kv.JumpToKey(groupName);

					char adminFlags[64];
					cvar_flags.GetString(adminFlags, sizeof(adminFlags));

					map_kv.GetString(NOMINATE_ADMINFLAG_KEY, adminFlags, sizeof(adminFlags), adminFlags);

					map_kv.JumpToKey(arg);

					map_kv.GetSectionName(arg, sizeof(arg));

					map_kv.GetString(NOMINATE_ADMINFLAG_KEY, adminFlags, sizeof(adminFlags), adminFlags);

					map_kv.GetString("nominate_group", nomGroup, sizeof(nomGroup), groupName);

					map_kv.GoBack();
					map_kv.GoBack();

					int clientFlags = GetUserFlagBits(client);
					int weight		= cvar_nominate_weight.IntValue;

					// Check if admin flag set
					if (adminFlags[0] != '\0' && !(clientFlags & ReadFlagString(adminFlags)))
					{
						// TODO: Change to translation phrase
						PrintToChat(client, "[UMC] Could not find map \"%s\"", arg);
					}
					else if (weight >= 0 && GetMapWeight_Custom(arg) < weight)
					{
						PrintToChat(client, "[UMC] Weight for map \"%s\" is not enough.", arg);
					}
					else
					{
						// Nominate it.
						UMC_NominateMap(map_kv, arg, groupName, client, nomGroup);

						// Display a message.
						char clientName[MAX_NAME_LENGTH];
						GetClientName(client, clientName, sizeof(clientName));
						PrintToChatAll("[UMC] %t", "Player Nomination", clientName, arg);
						LogUMCMessage("%s has nominated '%s' from group '%s'", clientName, arg, groupName);
					}
				}
			}
			else
			{
				if (!DisplayNominationMenu(client))
				{
					PrintToChat(client, "[UMC] %t", "No Nominate Nextmap");
				}
			}
		}
	}
	return Plugin_Continue;
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
	FilterMapcycleFromArrays(map_kv, vote_mem_arr, vote_catmem_arr, cvar_mem_group.IntValue);
}

//************************************************************************************************//
//                                            COMMANDS                                            //
//************************************************************************************************//
// sm_nominate
public Action Command_Nominate(int client, int args)
{
	if (!cvar_nominate.BoolValue)
	{
		return Plugin_Handled;
	}

	if (vote_completed || !can_nominate)
	{
		ReplyToCommand(client, "[UMC] %t", "No Nominate Nextmap");
	}
	else	// Otherwise, let them nominate.
	{
		if (args > 0)
		{
			// Get what was typed.
			char arg[MAP_LENGTH];
			GetCmdArg(1, arg, sizeof(arg));
			TrimString(arg);

			// Get the selected map.
			char groupName[MAP_LENGTH], nomGroup[MAP_LENGTH];

			if (!KvFindGroupOfMap(map_kv, arg, groupName, sizeof(groupName)))
			{
				// TODO: Change to translation phrase
				ReplyToCommand(client, "[UMC] Could not find map \"%s\"", arg);
			}
			else
			{
				map_kv.Rewind();

				map_kv.JumpToKey(groupName);

				char adminFlags[64];
				cvar_flags.GetString(adminFlags, sizeof(adminFlags));

				map_kv.GetString(NOMINATE_ADMINFLAG_KEY, adminFlags, sizeof(adminFlags), adminFlags);

				map_kv.JumpToKey(arg);

				map_kv.GetSectionName(arg, sizeof(arg));

				map_kv.GetString(NOMINATE_ADMINFLAG_KEY, adminFlags, sizeof(adminFlags), adminFlags);

				map_kv.GetString("nominate_group", nomGroup, sizeof(nomGroup), groupName);

				map_kv.GoBack();
				map_kv.GoBack();

				int clientFlags = GetUserFlagBits(client);

				// Check if admin flag set
				if (adminFlags[0] != '\0' && !(clientFlags & ReadFlagString(adminFlags)))
				{
					// TODO: Change to translation phrase
					ReplyToCommand(client, "[UMC] Could not find map \"%s\"", arg);
				}
				else
				{
					// Nominate it.
					UMC_NominateMap(map_kv, arg, groupName, client, nomGroup);

					// Display a message.
					char clientName[MAX_NAME_LENGTH];
					GetClientName(client, clientName, sizeof(clientName));
					PrintToChatAll("[UMC] %t", "Player Nomination", clientName, arg);
					LogUMCMessage("%s has nominated '%s' from group '%s'", clientName, arg, groupName);
				}
			}
		}
		else
		{
			if (!DisplayNominationMenu(client))
			{
				ReplyToCommand(client, "[UMC] %t", "No Nominate Nextmap");
			}
		}
	}
	return Plugin_Handled;
}

//************************************************************************************************//
//                                           NOMINATIONS                                          //
//************************************************************************************************//
// Displays a nomination menu to the given client.
bool DisplayNominationMenu(int client)
{
	if (!can_nominate)
	{
		return false;
	}

	LogUMCMessage("%N wants to nominate a map.", client);

	// Build the menu
	Menu menu = cvar_nominate_tiered.BoolValue ? BuildTieredNominationMenu(client) : BuildNominationMenu(client);

	// Display the menu if the menu was built successfully.
	if (menu != null)
	{
		return DisplayMenu(menu, client, GetConVarInt(cvar_nominate_time));
	}
	return false;
}

// Creates and returns the Nomination menu for the given client.
Menu BuildNominationMenu(int client, const char[] cat = INVALID_GROUP)
{
	// Initialize the menu
	Menu menu = new Menu(Handle_NominationMenu, MenuAction_Display);

	// Set the title.
	SetMenuTitle(menu, "%T", "Nomination Menu Title", LANG_SERVER);

	if (!StrEqual(cat, INVALID_GROUP))
	{
		// Make it so we can return to the previous menu.
		SetMenuExitBackButton(menu, true);
	}

	map_kv.Rewind();

	// Copy over for template processing
	KeyValues dispKV = new KeyValues("umc_mapcycle");
	KvCopySubkeys(map_kv, dispKV);

	// Get map array.
	ArrayList mapArray = UMC_CreateValidMapArray(map_kv, umc_mapcycle, cat, true, false);

	if (GetConVarBool(cvar_sort))
	{
		SortMapTrieArray(mapArray);
	}

	int size = GetArraySize(mapArray);
	if (size == 0)
	{
		LogError("No maps available to be nominated.");
		CloseHandle(menu);
		CloseHandle(mapArray);
		CloseHandle(dispKV);
		return null;
	}

	// Variables
	int numCells			   = ByteCountToCells(MAP_LENGTH);
	nom_menu_groups[client]	   = new ArrayList(numCells);
	nom_menu_nomgroups[client] = new ArrayList(numCells);
	ArrayList menuItems		   = new ArrayList(numCells);
	ArrayList menuItemDisplay  = new ArrayList(numCells);
	char	  display[MAP_LENGTH];	  //, String:gDisp[MAP_LENGTH];
	StringMap mapTrie;
	char	  mapBuff[MAP_LENGTH], groupBuff[MAP_LENGTH];
	char	  group[MAP_LENGTH];

	char	  dAdminFlags[64], gAdminFlags[64], mAdminFlags[64];
	cvar_flags.GetString(dAdminFlags, sizeof(dAdminFlags));
	int clientFlags = GetUserFlagBits(client);

	for (int i = 0; i < size; i++)
	{
		mapTrie = GetArrayCell(mapArray, i);
		GetTrieString(mapTrie, MAP_TRIE_MAP_KEY, mapBuff, sizeof(mapBuff));
		GetTrieString(mapTrie, MAP_TRIE_GROUP_KEY, groupBuff, sizeof(groupBuff));

		map_kv.JumpToKey(groupBuff);

		map_kv.GetString("nominate_group", group, sizeof(group), INVALID_GROUP);

		if (StrEqual(group, INVALID_GROUP))
		{
			strcopy(group, sizeof(group), groupBuff);
		}

		if (UMC_IsMapNominated(mapBuff, group))
		{
			map_kv.GoBack();
			continue;
		}

		map_kv.GetString(NOMINATE_ADMINFLAG_KEY, gAdminFlags, sizeof(gAdminFlags), dAdminFlags);

		map_kv.JumpToKey(mapBuff);

		map_kv.GetString(NOMINATE_ADMINFLAG_KEY, mAdminFlags, sizeof(mAdminFlags), gAdminFlags);

		// Check if admin flag set
		if (mAdminFlags[0] != '\0')
		{
			// Check if player has admin flag
			if (!(clientFlags & ReadFlagString(mAdminFlags)))
			{
				continue;
			}
		}

		int weight = cvar_nominate_weight.IntValue;
		if (weight >= 0 && GetMapWeight_Custom(mapBuff) < weight) continue;

		// Get the name of the current map.
		map_kv.GetSectionName(mapBuff, sizeof(mapBuff));

		// Get the display string.
		UMC_FormatDisplayString(display, sizeof(display), dispKV, mapBuff, groupBuff);

		// Add map data to the arrays.
		menuItems.PushString(mapBuff);
		menuItemDisplay.PushString(display);
		nom_menu_groups[client].PushString(groupBuff);
		nom_menu_nomgroups[client].PushString(group);

		map_kv.Rewind();
	}

	// Add all maps from the nominations array to the menu.
	AddArrayToMenu(menu, menuItems, menuItemDisplay);

	// No longer need the arrays.
	CloseHandle(menuItems);
	CloseHandle(menuItemDisplay);
	ClearHandleArray(mapArray);
	CloseHandle(mapArray);

	// Or the display KV
	CloseHandle(dispKV);

	// Success!
	return menu;
}

// Creates the first part of a tiered Nomination menu.
Menu BuildTieredNominationMenu(int client)
{
	// Initialize the menu
	Menu menu = new Menu(Handle_TieredNominationMenu, MenuAction_Display);

	map_kv.Rewind();

	// Get group array.
	ArrayList groupArray = UMC_CreateValidMapGroupArray(map_kv, umc_mapcycle, true, false);

	int		  size		 = GetArraySize(groupArray);

	// Log an error and return nothing if the number of maps available to be nominated
	if (size == 0)
	{
		LogError("No maps available to be nominated.");
		CloseHandle(menu);
		CloseHandle(groupArray);
		return null;
	}

	// Variables
	char dAdminFlags[64], gAdminFlags[64], mAdminFlags[64];
	cvar_flags.GetString(dAdminFlags, sizeof(dAdminFlags));
	int		  clientFlags = GetUserFlagBits(client);

	ArrayList menuItems	  = new ArrayList(ByteCountToCells(MAP_LENGTH));
	char	  groupName[MAP_LENGTH], mapName[MAP_LENGTH];
	bool	  excluded = true;
	for (int i = 0; i < size; i++)
	{
		groupArray.GetString(i, groupName, sizeof(groupName));

		map_kv.JumpToKey(groupName);

		map_kv.GetString(NOMINATE_ADMINFLAG_KEY, gAdminFlags, sizeof(gAdminFlags), dAdminFlags);

		map_kv.GotoFirstSubKey();
		do
		{
			map_kv.GetSectionName(mapName, sizeof(mapName));

			if (UMC_IsMapNominated(mapName, groupName))
			{
				continue;
			}

			map_kv.GetString(NOMINATE_ADMINFLAG_KEY, mAdminFlags, sizeof(mAdminFlags), gAdminFlags);

			// Check if admin flag set
			if (mAdminFlags[0] != '\0')
			{
				// Check if player has admin flag
				if (!(clientFlags & ReadFlagString(mAdminFlags)))
				{
					continue;
				}
			}

			excluded = false;
			break;
		}
		while (map_kv.GotoNextKey());

		if (!excluded)
		{
			menuItems.PushString(groupName);
		}

		map_kv.GoBack();
		map_kv.GoBack();
	}

	// Add all maps from the nominations array to the menu.
	AddArrayToMenu(menu, menuItems);

	// No longer need the arrays.
	CloseHandle(menuItems);
	CloseHandle(groupArray);

	// Success!
	return menu;
}

// Called when the client has picked an item in the nomination menu.
public int Handle_NominationMenu(Menu menu, MenuAction action, int client, int param2)
{
	switch (action)
	{
		case MenuAction_Select:	   // The client has picked something.
		{
			// Get the selected map.
			char map[MAP_LENGTH], group[MAP_LENGTH], nomGroup[MAP_LENGTH];
			menu.GetItem(param2, map, sizeof(map));
			nom_menu_groups[client].GetString(param2, group, sizeof(group));
			nom_menu_nomgroups[client].GetString(param2, nomGroup, sizeof(nomGroup));
			map_kv.Rewind();

			// Nominate it.
			UMC_NominateMap(map_kv, map, group, client, nomGroup);

			// Display a message.
			char clientName[MAX_NAME_LENGTH];
			GetClientName(client, clientName, sizeof(clientName));
			PrintToChatAll("[UMC] %t", "Player Nomination", clientName, map);
			LogUMCMessage("%s has nominated '%s' from group '%s'", clientName, map, group);

			// Close handles for stored data for the client's menu.
			CloseHandle(nom_menu_groups[client]);
			CloseHandle(nom_menu_nomgroups[client]);
			nom_menu_groups[client]	   = null;
			nom_menu_nomgroups[client] = null;
		}
		case MenuAction_End:	// The client has closed the menu.
		{
			// We're done here.
			CloseHandle(menu);
		}
		case MenuAction_Display:	// the menu is being displayed
		{
			Panel panel = view_as<Panel>(param2);
			char  buffer[255];
			FormatEx(buffer, sizeof(buffer), "%T", "Nomination Menu Title", client);
			panel.SetTitle(buffer);
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				// Build the menu
				Menu newmenu = BuildTieredNominationMenu(client);

				// Display the menu if the menu was built successfully.
				if (newmenu != null)
				{
					DisplayMenu(newmenu, client, cvar_nominate_time.IntValue);
				}
			}
		}
	}
	return 0;
}

// Handles the first-stage tiered nomination menu.
public int Handle_TieredNominationMenu(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		char cat[MAP_LENGTH];
		menu.GetItem(param2, cat, sizeof(cat));

		// Build the menu
		Menu newmenu = BuildNominationMenu(client, cat);

		// Display the menu if the menu was built successfully.
		if (newmenu != null)
		{
			DisplayMenu(newmenu, client, GetConVarInt(cvar_nominate_time));
		}
	}
	else
	{
		Handle_NominationMenu(menu, action, client, param2);
	}
	return 0;
}

//************************************************************************************************//
//                                   ULTIMATE MAPCHOOSER EVENTS                                   //
//************************************************************************************************//
// Called when UMC requests that the mapcycle should be reloaded.
public void UMC_RequestReloadMapcycle()
{
	can_nominate = ReloadMapcycle();
	if (can_nominate)
	{
		RemovePreviousMapsFromCycle();
	}
}

// Called when UMC has set a next map.
public void UMC_OnNextmapSet(KeyValues kv, const char[] map, const char[] group, const char[] display)
{
	vote_completed = true;
}

// Called when UMC has extended a map.
public void UMC_OnMapExtended()
{
	vote_completed = false;
}

// Called when UMC requests that the mapcycle is printed to the console.
public void UMC_DisplayMapCycle(int client, bool filtered)
{
	PrintToConsole(client, "Module: Nominations");
	if (filtered)
	{
		PrintToConsole(client, "Maps available to nominate:");
		KeyValues filteredMapcycle = UMC_FilterMapcycle(map_kv, umc_mapcycle, true, false);

		PrintKvToConsole(filteredMapcycle, client);
		CloseHandle(filteredMapcycle);
		PrintToConsole(client, "Maps available for map change (if nominated):");

		filteredMapcycle = UMC_FilterMapcycle(map_kv, umc_mapcycle, true, true);
		PrintKvToConsole(filteredMapcycle, client);
		CloseHandle(filteredMapcycle);
	}
	else
	{
		PrintKvToConsole(umc_mapcycle, client);
	}
}

stock int GetMapWeight_Custom(const char[] map)
{
	Database db = connect2DB();
	if (db == null)
	{
		return 0;
	}

	int	 point = 0;

	char error[255];

	int	 escapedMapNameLength = strlen(map) * 2 + 1;
	char[] escapedMapName	  = new char[escapedMapNameLength];
	db.Escape(map, escapedMapName, escapedMapNameLength);

	{
		int queryStatementLength = sizeof(db_insertRow) + strlen(escapedMapName);
		char[] queryStatement	 = new char[queryStatementLength];
		Format(queryStatement, queryStatementLength, db_insertRow, escapedMapName);

		if (!SQL_FastQuery(db, queryStatement))
		{
			SQL_GetError(db, error, sizeof(error));
			LogError("Could not query to database: %s", error);

			return 0;
		}
	}

	{
		DBResultSet hQuery;

		int			queryStatementLength = sizeof(db_selectRow) + strlen(escapedMapName);
		char[] queryStatement			 = new char[queryStatementLength];
		Format(queryStatement, queryStatementLength, db_selectRow, escapedMapName);

		if ((hQuery = SQL_Query(db, queryStatement)) == null)
		{
			SQL_GetError(db, error, sizeof(error));
			LogError("Could not query to database: %s", error);

			return 0;
		}

		if (SQL_FetchRow(hQuery))
		{
			point = SQL_FetchInt(hQuery, 0);
		}

		delete hQuery;
	}

	return point;
}

Database connect2DB()
{
	char error[255];
	Database db;

	if (SQL_CheckConfig("umc_weight"))
	{
		db = SQL_Connect("umc_weight", true, error, sizeof(error));
	}
	else
	{
		db = SQL_Connect("default", true, error, sizeof(error));
	}

	if (db == null)
	{
		LogError("Could not connect to database: %s", error);
	}

	if (!db_createTableSuccess && !SQL_FastQuery(db, db_createTable))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);
	}

	db_createTableSuccess = true;

	return db;
}
