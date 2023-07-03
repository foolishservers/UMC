/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *                                Ultimate Mapchooser - Admin Menu                               *
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
#include <adminmenu>
#include <regex>

#undef REQUIRE_PLUGIN

#define AMMENU_ITEM_INDEX_AUTO 0
#define AMMENU_ITEM_INDEX_MANUAL 1
#define AMMENU_ITEM_INFO_AUTO "auto"
#define AMMENU_ITEM_INFO_MANUAL "manual"

#define VTMENU_ITEM_INDEX_MAP 0
#define VTMENU_ITEM_INDEX_GROUP 1
#define VTMENU_ITEM_INDEX_TIER 2
#define VTMENU_ITEM_INFO_MAP "map"
#define VTMENU_ITEM_INFO_GROUP "group"
#define VTMENU_ITEM_INFO_TIER "tier"

#define VOTE_POP_STOP_INFO "stop"

#define DMENU_ITEM_INDEX_DEFAULTS 0
#define DMENU_ITEM_INDEX_MANUAL 1
#define DMENU_ITEM_INFO_DEFAULTS "0"
#define DMENU_ITEM_INFO_MANUAL "1"

#define SMENU_ITEM_INFO_NO "no"
#define SMENU_ITEM_INFO_YES "yes"

#define TMENU_ITEM_INFO_DEFAULT "def"
#define TMENU_ITEM_INFO_PREV "prev"

#define FAMENU_ITEM_INFO_NOTHING "nothing"
#define FAMENU_ITEM_INFO_RUNOFF "runoff"

#define MRMENU_ITEM_INFO_DEFAULT "def"
#define MRMENU_ITEM_INFO_PREV "prev"

#define RFAMENU_ITEM_INFO_NOTHING "nothing"
#define RFAMENU_ITEM_INFO_ACCEPT "accept"

#define EMENU_ITEM_INFO_NO "no"
#define EMENU_ITEM_INFO_YES "yes"

#define DCMENU_ITEM_INFO_NO "no"
#define DCMENU_ITEM_INFO_YES "yes"

#define ADMINMENU_ADMINFLAG_KEY "adminmenu_flags"

//Plugin Information
public Plugin myinfo =
{
    name        = "[UMC] Admin Menu",
    author      = PL_AUTHOR,
    description = "Adds an Ultimate Mapchooser entry in the SourceMod Admin Menu.",
    version     = PL_VERSION,
    url         = "http://forums.alliedmods.net/showthread.php?t=134190"
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
ConVar cvar_vote_startsound;
ConVar cvar_vote_endsound;
ConVar cvar_vote_catmem;
ConVar cvar_dontchange;
ConVar cvar_defaultsflags;
ConVar cvar_flags;
ConVar cvar_ignoreexcludeflags;
////----/CONVARS-----/////

//Mapcycle KV
KeyValues map_kv;
KeyValues umc_mapcycle;

//Memory queues. Used to store the previously played maps.
ArrayList vote_mem_arr;
ArrayList vote_catmem_arr;

//Sounds to be played at the start and end of votes.
char vote_start_sound[PLATFORM_MAX_PATH], vote_end_sound[PLATFORM_MAX_PATH], runoff_sound[PLATFORM_MAX_PATH];
    
//Can we start a vote (is the mapcycle valid?)
bool can_vote;

//Admin Menu
TopMenu admin_menu;
//new TopMenuObject:umc_menu;

//Tries to store menu selections / build options.
StringMap menu_tries[MAXPLAYERS];

//Flags for Chat Triggers
bool runoff_trigger[MAXPLAYERS];
bool runoff_menu_trigger[MAXPLAYERS];
bool threshold_trigger[MAXPLAYERS];
bool threshold_menu_trigger[MAXPLAYERS];

//Regex objects for chat triggers
Regex runoff_regex;
Regex threshold_regex;

//************************************************************************************************//
//                                        SOURCEMOD EVENTS                                        //
//************************************************************************************************//
//Called when the plugin is finished loading.
public void OnPluginStart()
{
    cvar_ignoreexcludeflags = CreateConVar(
        "sm_umc_am_adminflags_exclude",
        "",
        "Flags required for admins to be able to select maps which would normally be excluded by UMC. If empty, all admins can select excluded maps."
    );
    
    cvar_defaultsflags = CreateConVar(
        "sm_umc_am_adminflags_default",
        "",
        "Flags required for admins to be able to manually select settings for the vote. If the admin does not have the proper priveleges, the vote will automatically use the cvars in this file. If empty, all admins have access."
    );
    
    cvar_flags = CreateConVar(
        "sm_umc_am_vote_adminflags",
        "",
        "Specifies which admin flags are necessary for a player to participate in a vote. If empty, all players can participate."
    );
    
    cvar_fail_action = CreateConVar(
        "sm_umc_am_failaction",
        "0",
        "Specifies what action to take if the vote doesn't reach the set theshold.\n 0 - Do Nothing,\n 1 - Perform Runoff Vote",
        0, true, 0.0, true, 1.0
    );
    
    cvar_runoff_fail_action = CreateConVar(
        "sm_umc_am_runoff_failaction",
        "0",
        "Specifies what action to take if the runoff vote reaches the maximum amount of runoffs and the set threshold has not been reached.\n 0 - Do Nothing,\n 1 - Change Map to Winner",
        0, true, 0.0, true, 1.0
    );
    
    cvar_runoff_max = CreateConVar(
        "sm_umc_am_runoff_max",
        "0",
        "Specifies the maximum number of maps to appear in a runoff vote.\n 1 or 0 sets no maximum.",
        0, true, 0.0
    );

    cvar_vote_allowduplicates = CreateConVar(
        "sm_umc_am_allowduplicates",
        "1",
        "Allows a map to appear in the vote more than once. This should be enabled if you want the same map in different categories to be distinct.",
        0, true, 0.0, true, 1.0
    );
    
    cvar_vote_threshold = CreateConVar(
        "sm_umc_am_threshold",
        "0",
        "If the winning option has less than this percentage of total votes, a vote will fail and the action specified in \"sm_umc_vc_failaction\" cvar will be performed.",
        0, true, 0.0, true, 1.0
    );
    
    cvar_runoff = CreateConVar(
        "sm_umc_am_runoffs",
        "0",
        "Specifies a maximum number of runoff votes to run for a vote.\n 0 = unlimited.",
        0, true, 0.0
    );
    
    cvar_runoff_sound = CreateConVar(
        "sm_umc_am_runoff_sound",
        "",
        "If specified, this sound file (relative to sound folder) will be played at the beginning of a runoff vote. If not specified, it will use the normal vote start sound."
    );
    
    cvar_vote_catmem = CreateConVar(
        "sm_umc_am_groupexclude",
        "0",
        "Specifies how many past map groups to exclude from votes.",
        0, true, 0.0, true, 10.0
    );
    
    cvar_vote_startsound = CreateConVar(
        "sm_umc_am_startsound",
        "",
        "Sound file (relative to sound folder) to play at the start of a vote."
    );
    
    cvar_vote_endsound = CreateConVar(
        "sm_umc_am_endsound",
        "",
        "Sound file (relative to sound folder) to play at the completion of a vote."
    );
    
    cvar_strict_noms = CreateConVar(
        "sm_umc_am_nominate_strict",
        "0",
        "Specifies whether the number of nominated maps appearing in the vote for a map group should be limited by the group's \"maps_invote\" setting.",
        0, true, 0.0, true, 1.0
    );

    cvar_extend_rounds = CreateConVar(
        "sm_umc_am_extend_roundstep",
        "5",
        "Specifies how many more rounds each extension adds to the round limit.",
        0, true, 1.0
    );

    cvar_extend_time = CreateConVar(
        "sm_umc_am_extend_timestep",
        "15",
        "Specifies how many more minutes each extension adds to the time limit.",
        0, true, 1.0
    );

    cvar_extend_frags = CreateConVar(
        "sm_umc_am_extend_fragstep",
        "10",
        "Specifies how many more frags each extension adds to the frag limit.",
        0, true, 1.0
    );

    cvar_extensions = CreateConVar(
        "sm_umc_am_extend",
        "0",
        "Adds an \"Extend\" option to votes.",
        0, true, 0.0, true, 1.0
    );

    cvar_vote_time = CreateConVar(
        "sm_umc_am_duration",
        "20",
        "Specifies how long a vote should be available for.",
        0, true, 10.0
    );

    cvar_filename = CreateConVar(
        "sm_umc_am_cyclefile",
        "umc_mapcycle.txt",
        "File to use for Ultimate Mapchooser's map rotation."
    );

    cvar_vote_mem = CreateConVar(
        "sm_umc_am_mapexclude",
        "4",
        "Specifies how many past maps to exclude from votes. 1 = Current Map Only",
        0, true, 0.0, true, 10.0
    );

    cvar_scramble = CreateConVar(
        "sm_umc_am_menuscrambled",
        "0",
        "Specifies whether vote menu items are displayed in a random order.",
        0, true, 0.0, true, 1.0
    );
    
    cvar_dontchange = CreateConVar(
        "sm_umc_am_dontchange",
        "1",
        "Adds a \"Don't Change\" option to votes.",
        0, true, 0.0, true, 1.0
    );

    //Create the config if it doesn't exist, and then execute it.
    AutoExecConfig(true, "umc-adminmenu");
    
    //Make listeners for player chat. Needed to recognize chat input.
    AddCommandListener(OnPlayerChat, "say");
    AddCommandListener(OnPlayerChat, "say2"); //Insurgency Only
    AddCommandListener(OnPlayerChat, "say_team");
    
    //Initialize our memory arrays
    int numCells = ByteCountToCells(MAP_LENGTH);
    vote_mem_arr    = new ArrayList(numCells);
    vote_catmem_arr = new ArrayList(numCells);
    
    //Manually fire AdminMenu callback.
    TopMenu topmenu;
    if ((topmenu = GetAdminTopMenu()) != null)
    {
        OnAdminMenuReady(topmenu);
    }
    
    runoff_regex = CompileRegex("^([0-9]+)\\s*$");
    threshold_regex = CompileRegex("^([0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)%?\\s*$");
    
    //Load the translations file
    LoadTranslations("ultimate-mapchooser.phrases");
    LoadTranslations("ultimate-mapchooser-adminmenu.phrases");
}

//************************************************************************************************//
//                                           GAME EVENTS                                          //
//************************************************************************************************//
//Called after all config files were executed.
public void OnConfigsExecuted()
{
    can_vote = ReloadMapcycle();
    
    //Grab the name of the current map.
    char mapName[MAP_LENGTH];
    GetCurrentMap(mapName, sizeof(mapName));
    
    char groupName[MAP_LENGTH];
    UMC_GetCurrentMapGroup(groupName, sizeof(groupName));
    
    if (can_vote && StrEqual(groupName, INVALID_GROUP, false))
    {
        KvFindGroupOfMap(umc_mapcycle, mapName, groupName, sizeof(groupName));
    }
    
    //TODO -- Set to 11, add options in menus to specify a smaller amount
    //Add the map to all the memory queues.
    int mapmem = cvar_vote_mem.IntValue;
    int catmem = cvar_vote_catmem.IntValue;
    AddToMemoryArray(mapName, vote_mem_arr, mapmem); //11); 
    AddToMemoryArray(groupName, vote_catmem_arr, (mapmem > catmem) ? mapmem : catmem); //11);
    
    if (can_vote)
    {
        RemovePreviousMapsFromCycle();
    }
}

public void OnMapStart()
{
    SetupVoteSounds();
}

//Called when a player types in chat
public Action OnPlayerChat(int client, const char[] command, int argc)
{
    //Return immediately if nothing was typed.
    if (argc == 0) 
    {
        return Plugin_Continue;
    }
    
    //Get what was typed.
    char text[13];
    GetCmdArg(1, text, sizeof(text));
    
    if (threshold_trigger[client] && ProcessThresholdText(client, text))
    {
        return Plugin_Handled;
    }
    
    if (runoff_trigger[client] && ProcessRunoffText(client, text))
    {
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}

//************************************************************************************************//
//                                              SETUP                                             //
//************************************************************************************************//
//Parses the mapcycle file and returns a KV handle representing the mapcycle.
KeyValues GetMapcycle()
{
    //Grab the file name from the cvar.
    char filename[PLATFORM_MAX_PATH];
    GetConVarString(cvar_filename, filename, sizeof(filename));
    
    //Get the kv handle from the file.
    KeyValues result = GetKvFromFile(filename, "umc_rotation");
    
    //Log an error and return empty handle if the mapcycle file failed to parse.
    if (result == null)
    {
        LogError("SETUP: Mapcycle failed to load!");
        return null;
    }
    
    //Success!
    return result;
}

//Reloads the mapcycle. Returns true on success, false on failure.
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

//Sets up the vote sounds.
void SetupVoteSounds()
{
    //Grab sound files from cvars.
    cvar_vote_startsound.GetString(vote_start_sound, sizeof(vote_start_sound));
    cvar_vote_endsound.GetString(vote_end_sound, sizeof(vote_end_sound));
    cvar_runoff_sound.GetString(runoff_sound, sizeof(runoff_sound));
    
    //Gotta cache 'em all!
    CacheSound(vote_start_sound);
    CacheSound(vote_end_sound);
    CacheSound(runoff_sound);
}

//************************************************************************************************//
//                                           ADMIN MENU                                           //
//************************************************************************************************//
//Sets up the admin menu when it is ready to be set up.
public void OnAdminMenuReady(Handle topmenu)
{
    TopMenu topMenu = view_as<TopMenu>(topmenu);
    //Block this from being called twice
    if (topMenu == admin_menu)
    {
        return;
    }
    
    //Setup menu...
    admin_menu = topMenu;
    
    TopMenuObject umc_menu = AddToTopMenu(
        admin_menu, "Ultimate Mapchooser", TopMenuObject_Category,
        Adm_CategoryHandler, INVALID_TOPMENUOBJECT
    );
    
    AddToTopMenu(
        admin_menu, "umc_changemap", TopMenuObject_Item, UMCMenu_ChangeMap,
        umc_menu, "umc_changemap", ADMFLAG_CHANGEMAP
    );
    
    AddToTopMenu(
        admin_menu, "umc_setnextmap", TopMenuObject_Item, UMCMenu_NextMap,
        umc_menu, "sm_umc_setnextmap", ADMFLAG_CHANGEMAP
    );
    
    AddToTopMenu(
        admin_menu, "umc_mapvote", TopMenuObject_Item, UMCMenu_MapVote,
        umc_menu, "sm_umc_startmapvote", ADMFLAG_CHANGEMAP
    );
}

//Handles the UMC category in the admin menu.
public void Adm_CategoryHandler(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength)
{
    if (action == TopMenuAction_DisplayTitle || action == TopMenuAction_DisplayOption)
    {
        strcopy(buffer, maxlength, "Ultimate Mapchooser");
    }
}

//Handles the Change Map option in the menu.
public void UMCMenu_ChangeMap(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int client, char[] buffer, int maxlength)
{
    if (action == TopMenuAction_DisplayOption)
    {
        FormatEx(buffer, maxlength, "%T", "AM Change Map", client);
    }
    else if (action == TopMenuAction_SelectOption)
    {
        CreateAMChangeMap(client);
    }
}

//Handles the Change Map option in the menu.
public void UMCMenu_NextMap(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int client, char[] buffer, int maxlength)
{
    if (action == TopMenuAction_DisplayOption)
    {
        FormatEx(buffer, maxlength, "%T", "AM Set Next Map", client);
    }
    else if (action == TopMenuAction_SelectOption)
    {
        CreateAMNextMap(client);
    }
}

//Handles the Change Map option in the menu.
public void UMCMenu_MapVote(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int client, char[] buffer, int maxlength)
{
    if (action == TopMenuAction_DisplayOption)
    {
        if (UMC_IsVoteInProgress("core")) //TODO FIXME
        {
            FormatEx(buffer, maxlength, "%T", "AM Stop Vote", client);
        }
        else
        {
            FormatEx(buffer, maxlength, "%T", "AM Start Vote", client);
        }
    }
    else if (action == TopMenuAction_SelectOption)
    {
        /*
        Order:
            1. Vote Type
            2. Auto/Manual
            --IF MANUAL--
                A. Pick Group/END
                --IF END--
                    I. Goto 3
                B. Pick Map
                C. Goto A
            3. Defaults/Override
            --IF OVERRIDE--
                A. Scramble
                B. Threshold
                C. Fail Action
                --IF RUNOFF--
                    I. Max Runoffs
                    II. Runoff Fail Action
                D. Extend Option
                E. Don't Change Option
            4. When
            
        Trie Structure: *incomplete*
        {
            int type
            bool auto
            adt_array maps
            bool defaults
            bool scramble
            Float threshold
            int fail_action
            int max_runoffs
            int runoff_fail_action
            bool extend
            bool dont_change
            int when
        }
        
        Trie "Methods":
            bool VoteAutoPopulated(client)
            bool RunoffIsEnabled(client)
            bool UsingDefaults(client)
        */
        
        if (UMC_IsVoteInProgress("core")) //TODO FIXME
        {
            UMC_StopVote("core"); //TODO FIXME
            RedisplayAdminMenu(topmenu, client);
        }
        else
        {
            menu_tries[client] = CreateVoteMenuTrie(client);
            DisplayVoteTypeMenu(client);
        }
    }
}

StringMap CreateVoteMenuTrie(int client)
{
    StringMap trie = new StringMap();
    ArrayList mapList = new ArrayList();
    SetTrieValue(trie, "maps", mapList);
    
    bool ignoreExclude = false;
    char flags[64];
    cvar_ignoreexcludeflags.GetString(flags, sizeof(flags));
    
    if (flags[0] != '\0')
    {
        if (ReadFlagString(flags) & GetUserFlagBits(client))
        {
            ignoreExclude = true;
        }
    }
    else
    {
        ignoreExclude = true;
    }
    
    SetTrieValue(trie, "ignore_exclusion", ignoreExclude);
    return trie;
}

void DisplayVoteTypeMenu(int client)
{
	Menu menu = new Menu(HandleMV_VoteType, MenuAction_DisplayItem|MenuAction_Display);
	menu.SetTitle("AM Vote Type");
    
	menu.AddItem(VTMENU_ITEM_INFO_MAP, "Maps");
	menu.AddItem(VTMENU_ITEM_INFO_GROUP, "Groups");
	menu.AddItem(VTMENU_ITEM_INFO_TIER, "Tiered");

	menu.Display(client, 0);
}

public int Handle_MenuTranslation(Menu menu, MenuAction action, int client, int param2)
{
    switch(action)
    {
        case MenuAction_Display:
        {
            Panel panel = view_as<Panel>(param2);
            
            char translation[256];
            menu.GetTitle(translation, sizeof(translation));
            
            if (strlen(translation) > 0)
            {
                char buffer[256];
                FormatEx(buffer, sizeof(buffer), "%T", translation, client);
                
                panel.SetTitle(buffer);
            }
        }
        case MenuAction_DisplayItem:
        {
            char info[256], display[256];
            menu.GetItem(param2, info, sizeof(info), _, display, sizeof(display));
            
            if (strlen(display) > 0)
            {
                char buffer[255];
                FormatEx(buffer, sizeof(buffer), "%T", display, client);
                    
                return RedrawMenuItem(buffer);
            }
        }
    }
    return 0;
}

public int HandleMV_VoteType(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            SetTrieValue(menu_tries[param1], "type", param2);
            DisplayAutoManualMenu(param1);
        }
        case MenuAction_Cancel:
        {
            CloseClientVoteTrie(param1);
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

void DisplayAutoManualMenu(int client)
{
    Menu menu = CreateAutoManualMenu(HandleMV_AutoManual, "AM Populate Vote");
    menu.ExitBackButton = true;
    menu.Display(client, 0);
}

public int HandleMV_AutoManual(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            switch (param2)
            {
                case AMMENU_ITEM_INDEX_AUTO:
                {
                    AutoBuildVote(param1, true);
                    DisplayDefaultsMenu(param1);
                }
                case AMMENU_ITEM_INDEX_MANUAL:
                {
                    AutoBuildVote(param1, false);
                    DisplayGroupSelectMenu(param1);
                }
            }
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                DisplayVoteTypeMenu(param1);
            }
            else
            {
                CloseClientVoteTrie(param1);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

void AutoBuildVote(int client, bool value)
{
    SetTrieValue(menu_tries[client], "auto", value);
}

void CloseClientVoteTrie(int client)
{
    StringMap trie = menu_tries[client];
    menu_tries[client] = null;
    
    ArrayList mapList;
    GetTrieValue(trie, "maps", mapList);
    ClearHandleArray(mapList);
    CloseHandle(mapList);
    
    CloseHandle(trie);
}

void DisplayGroupSelectMenu(int client)
{
    bool ignoreLimits;
    GetTrieValue(menu_tries[client], "ignore_exclusion", ignoreLimits);
    
    Menu menu = CreateGroupMenu(HandleMV_Groups, !ignoreLimits, client);
    
    ArrayList voteArray;
    GetTrieValue(menu_tries[client], "maps", voteArray);
    if (GetArraySize(voteArray) > 1)
    {
        InsertMenuItem(menu, 0, VOTE_POP_STOP_INFO, "Stop Adding Maps"); //TODO: Make Translation
    }
    
    menu.Display(client, 0);
}

public int HandleMV_Groups(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Display:
        {
            Handle_MenuTranslation(menu, action, param1, param2);
        }
        case MenuAction_Select:
        {
            char group[MAP_LENGTH];
            menu.GetItem(param2, group, sizeof(group));
            
            if (StrEqual(group, VOTE_POP_STOP_INFO))
            {
                char flags[64];
                cvar_defaultsflags.GetString(flags, sizeof(flags));
                
                if (!ClientHasAdminFlags(param1, flags))
                {
                    UseVoteDefaults(param1);
                    DisplayChangeWhenMenu(param1);
                }
                else
                {
                    DisplayDefaultsMenu(param1);
                }
            }
            else
            {
                SetTrieString(menu_tries[param1], "group", group);   
                DisplayMapSelectMenu(param1, group);
            }
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                DisplayAutoManualMenu(param1);
            }
            else
            {
                CloseClientVoteTrie(param1);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }    
    return 0;
}

void DisplayMapSelectMenu(int client, const char[] group)
{
    bool ignoreLimits;
    GetTrieValue(menu_tries[client], "ignore_exclusion", ignoreLimits);
    
    Menu newMenu = CreateMapMenu(HandleMV_Maps, group, !ignoreLimits, client);
    newMenu.Display(client, 0);
}

public int HandleMV_Maps(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Display:
        {
            Handle_MenuTranslation(menu, action, param1, param2);
        }
        case MenuAction_Select:
        {
            char map[MAP_LENGTH], group[MAP_LENGTH];
            menu.GetItem(param2, map, sizeof(map));
            GetTrieString(menu_tries[param1], "group", group, sizeof(group));
            
            AddToVoteList(param1, map, group);
            
            DisplayGroupSelectMenu(param1);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                DisplayGroupSelectMenu(param1);
            }
            else
            {
                CloseClientVoteTrie(param1);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return 0;
}

void AddToVoteList(int client, const char[] map, const char[] group)
{
    StringMap mapTrie = CreateMapTrie(map, group);
    ArrayList mapList;
    GetTrieValue(menu_tries[client], "maps", mapList);
    mapList.Push(mapTrie);
}

void DisplayDefaultsMenu(int client)
{
    Menu menu = new Menu(HandleMV_Defaults, MenuAction_DisplayItem|MenuAction_Display);
    menu.SetTitle("AM Vote Settings");
    
    menu.AddItem(DMENU_ITEM_INFO_DEFAULTS, "AM-VS Defaults");
    menu.AddItem(DMENU_ITEM_INFO_MANUAL, "Manually Choose");
    
    menu.ExitBackButton = true;
    
    menu.Display(client, 0);
}

public int HandleMV_Defaults(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            switch (param2)
            {
                case DMENU_ITEM_INDEX_DEFAULTS:
                {
                    UseVoteDefaults(param1);
                    DisplayChangeWhenMenu(param1);
                }
                case DMENU_ITEM_INDEX_MANUAL:
                {
                    SetTrieValue(menu_tries[param1], "defaults", false);
                    DisplayScrambleMenu(param1);
                }
            }
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                if (VoteAutoPopulated(param1))
                    DisplayAutoManualMenu(param1);
                else
                    DisplayGroupSelectMenu(param1);
            }
            else
            {
                CloseClientVoteTrie(param1);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

void UseVoteDefaults(int client)
{
    StringMap trie = menu_tries[client];
    
    SetTrieValue(trie, "defaults", true);
    
    SetTrieValue(trie, "scramble", cvar_scramble.BoolValue);
    SetTrieValue(trie, "extend", cvar_extensions.BoolValue);
    SetTrieValue(trie, "dont_change", cvar_dontchange.BoolValue);
    SetTrieValue(trie, "threshold", cvar_vote_threshold.FloatValue);
    SetTrieValue(trie, "fail_action", cvar_fail_action.IntValue);
    SetTrieValue(trie, "runoff_fail_action", cvar_runoff_fail_action.IntValue);
    SetTrieValue(trie, "max_runoffs", cvar_runoff.IntValue);
    
    char flags[64];
    cvar_flags.GetString(flags, sizeof(flags));
    SetTrieString(trie, "flags", flags);
}

bool VoteAutoPopulated(int client)
{
    bool autoPop;
    GetTrieValue(menu_tries[client], "auto", autoPop);
    
    return autoPop;
}

void DisplayScrambleMenu(int client)
{
    Menu menu = new Menu(HandleMV_Scramble, MenuAction_DisplayItem|MenuAction_Display);
    menu.SetTitle("AM Scramble Menu");
    
    if (cvar_scramble.BoolValue)
    {
        menu.AddItem(SMENU_ITEM_INFO_NO, "No");
        menu.AddItem(SMENU_ITEM_INFO_YES, "Default Yes");
    }
    else
    {
        menu.AddItem(SMENU_ITEM_INFO_NO, "Default No");
        menu.AddItem(SMENU_ITEM_INFO_YES, "Yes");
    }
    
    menu.ExitBackButton = true;
    
    menu.Display(client, 0);
}

public int HandleMV_Scramble(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            SetTrieValue(menu_tries[param1], "scramble", param2);
        
            DisplayThresholdMenu(param1);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                char flags[64];
                cvar_defaultsflags.GetString(flags, sizeof(flags));
                
                if (!ClientHasAdminFlags(param1, flags))
                {
                    if (VoteAutoPopulated(param1))
                    {
                        DisplayAutoManualMenu(param1);
                    }
                    else
                    {
                        DisplayGroupSelectMenu(param1);
                    }
                }
                else
                {
                    DisplayDefaultsMenu(param1);
                }
            }
            else
            {
                CloseClientVoteTrie(param1);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

void DisplayThresholdMenu(int client)
{
    threshold_trigger[client] = true;
    
    Menu menu = new Menu(HandleMV_Threshold, MenuAction_DisplayItem|MenuAction_Display);
    menu.SetTitle("AM Threshold Menu");
    
    menu.AddItem("", "AM Threshold Menu Message 1", ITEMDRAW_DISABLED);
    menu.AddItem("", "AM Threshold Menu Message 2", ITEMDRAW_DISABLED);
    menu.AddItem("", "", ITEMDRAW_SPACER);
    
    float threshold;
    if (GetTrieValue(menu_tries[client], "threshold", threshold))
    {
        char fmt2[20];
        FormatEx(fmt2, sizeof(fmt2), "%.f%% (previously entered)", threshold * 100);
        menu.AddItem(TMENU_ITEM_INFO_PREV, fmt2);
    }
    
    char fmt[20];
    FormatEx(fmt, sizeof(fmt), "%.f%% (default)", cvar_vote_threshold.FloatValue * 100);
    menu.AddItem(TMENU_ITEM_INFO_DEFAULT, fmt);
    
    menu.ExitBackButton = true;
    
    menu.Display(client, 0);
}

public int HandleMV_Threshold(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Display:
        {
            Handle_MenuTranslation(menu, action, param1, param2);
        }
        case MenuAction_Select:
        {
            threshold_trigger[param1] = false;
            
            char info[255];
            menu.GetItem(param2, info, sizeof(info));
            
            if (StrEqual(info, TMENU_ITEM_INFO_DEFAULT))
            {
                SetTrieValue(menu_tries[param1], "threshold", GetConVarFloat(cvar_vote_threshold));
            }
            DisplayFailActionMenu(param1);
        }
        case MenuAction_Cancel:
        {
            threshold_trigger[param1] = false;
            
            if (!threshold_menu_trigger[param1])
            {
                if (param2 == MenuCancel_ExitBack)
                {
                    DisplayScrambleMenu(param1);
                }
                else
                {
                    CloseClientVoteTrie(param1);
                }
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
        case MenuAction_DisplayItem:
        {
            char info[256], disp[256];
            menu.GetItem(param2, info, sizeof(info), _, disp, sizeof(disp));
        
            if (StrEqual(info, TMENU_ITEM_INFO_PREV))
            {
                float threshold;
                GetTrieValue(menu_tries[param1], "threshold", threshold);
            
                char buffer[255];
                FormatEx(buffer, sizeof(buffer), "%.f%% (%T)", threshold * 100, "Previously Entered", param1);

                return RedrawMenuItem(buffer);
            }
            else if (StrEqual(info, TMENU_ITEM_INFO_DEFAULT))
            {
                char buffer[255];
                FormatEx(buffer, sizeof(buffer), "%.f%% (%T)", GetConVarFloat(cvar_vote_threshold) * 100, "Default", param1);
                    
                return RedrawMenuItem(buffer);
            }
            else if (strlen(disp) > 0)
            {
                return Handle_MenuTranslation(menu, action, param1, param2);
            }
        }
    }
    return 0;
}

bool ProcessThresholdText(int client, const char[] text)
{
    char num[20];
    float percent;
    if (MatchRegex(threshold_regex, text))
    {
        GetRegexSubString(threshold_regex, 1, num, sizeof(num));
        percent = StringToFloat(num);
        
        if (percent <= 100.0 && percent >= 0.0)
        {
            SetTrieValue(menu_tries[client], "threshold", percent / 100.0);
            CancelThresholdMenu(client);
            DisplayFailActionMenu(client);
            return true;
        }
    }
    return false;
}

void CancelThresholdMenu(int client)
{
    threshold_menu_trigger[client] = true;
    CancelClientMenu(client);
    threshold_menu_trigger[client] = false;
}

void DisplayFailActionMenu(int client)
{
    Menu menu = new Menu(HandleMV_FailAction, MenuAction_DisplayItem|MenuAction_Display);
    menu.SetTitle("AM Fail Action Menu");
    
    if (cvar_fail_action.BoolValue)
    {
        menu.AddItem(FAMENU_ITEM_INFO_NOTHING, "Do Nothing");
        menu.AddItem(FAMENU_ITEM_INFO_RUNOFF, "Default Perform Runoff Vote");
    }
    else
    {
        menu.AddItem(FAMENU_ITEM_INFO_NOTHING, "Default Do Nothing");
        menu.AddItem(FAMENU_ITEM_INFO_RUNOFF, "Perform Runoff Vote");
    }
    
    menu.ExitBackButton = true;
    
    menu.Display(client, 0);
}

public int HandleMV_FailAction(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            SetTrieValue(menu_tries[param1], "fail_action", param2);
            
            switch (view_as<UMC_VoteFailAction>(param2))
            {
                case VoteFailAction_Nothing:
                {
                    DisplayExtendMenu(param1);
                }
                case VoteFailAction_Runoff:
                {
                    DisplayMaxRunoffMenu(param1);
                }
            }
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                DisplayThresholdMenu(param1);
            }
            else
            {
                CloseClientVoteTrie(param1);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

void DisplayMaxRunoffMenu(int client)
{
    runoff_trigger[client] = true;
    
    Menu menu = new Menu(HandleMV_MaxRunoff, MenuAction_DisplayItem|MenuAction_Display);
    menu.SetTitle("AM Max Runoff Menu");
    
    menu.AddItem("", "AM Max Runoff Menu Message 1", ITEMDRAW_DISABLED);
    menu.AddItem("", "AM Max Runoff Menu Message 2", ITEMDRAW_DISABLED);
    menu.AddItem("", "AM Max Runoff Menu Message 3", ITEMDRAW_DISABLED);
    menu.AddItem("", "", ITEMDRAW_SPACER);
    
    int runoffs;
    if (GetTrieValue(menu_tries[client], "max_runoffs", runoffs))
    {
        char fmt2[20];
        FormatEx(fmt2, sizeof(fmt2), "%i (previously entered)", runoffs);
        menu.AddItem(MRMENU_ITEM_INFO_PREV, fmt2);
    }
    
    char fmt[20];
    FormatEx(fmt, sizeof(fmt), "%i (default)", GetConVarInt(cvar_runoff_max));
    menu.AddItem(MRMENU_ITEM_INFO_DEFAULT, fmt);
    
    menu.ExitBackButton = true;
    
    menu.Display(client, 0);
}

public int HandleMV_MaxRunoff(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Display:
        {
            Handle_MenuTranslation(menu, action, param1, param2);
        }
        case MenuAction_Select:
        {
            runoff_trigger[param1] = false;
            
            char info[255];
            menu.GetItem(param2, info, sizeof(info));
            
            if (StrEqual(info, MRMENU_ITEM_INFO_DEFAULT))
            {
                SetTrieValue(menu_tries[param1], "max_runoffs", cvar_runoff_max.IntValue);
            }
            //TODO:
            //I don't think I need to handle the case where we reselect the previously entered amount,
            //since it should already be stored in the trie.
        
            DisplayRunoffFailActionMenu(param1);
        }
        case MenuAction_Cancel:
        {
            runoff_trigger[param1] = false;
            
            if (!runoff_menu_trigger[param1])
            {
                if (param2 == MenuCancel_ExitBack)
                {
                    DisplayFailActionMenu(param1);
                }
                else
                {
                    CloseClientVoteTrie(param1);
                }
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
        case MenuAction_DisplayItem:
        {
            char info[256];
            menu.GetItem(param2, info, sizeof(info));
        
            if (StrEqual(info, MRMENU_ITEM_INFO_PREV))
            {
                int maxrunoffs;
                GetTrieValue(menu_tries[param1], "max_runoffs", maxrunoffs);
            
                char buffer[255];
                FormatEx(buffer, sizeof(buffer), "%i (%T)", maxrunoffs, "Previously Entered", param1);
                    
                return RedrawMenuItem(buffer);
            }
            else if (StrEqual(info, MRMENU_ITEM_INFO_DEFAULT))
            {
                char buffer[255];
                FormatEx(buffer, sizeof(buffer), "%i (%T)", cvar_runoff_max.IntValue, "Default", param1);
                    
                return RedrawMenuItem(buffer);
            }
            else
            {
                return Handle_MenuTranslation(menu, action, param1, param2);
            }
        }
    }
    return 0;
}

bool ProcessRunoffText(int client, const char[] text)
{
    char num[20];
    int amt;
    if (MatchRegex(runoff_regex, text))
    {
        GetRegexSubString(runoff_regex, 1, num, sizeof(num));
        amt = StringToInt(num);
        
        if (amt >= 0)
        {
            SetTrieValue(menu_tries[client], "max_runoffs", amt);
            CancelRunoffMenu(client);
            DisplayRunoffFailActionMenu(client);
            return true;
        }
    }
    return false;
}

void CancelRunoffMenu(int client)
{
    runoff_menu_trigger[client] = true;
    CancelClientMenu(client);
    runoff_menu_trigger[client] = false;        
}

void DisplayRunoffFailActionMenu(int client)
{
    Menu menu = new Menu(HandleMV_RunoffFailAction, MenuAction_DisplayItem|MenuAction_Display);
    menu.SetTitle("AM Runoff Fail Action Menu");
    
    if (cvar_runoff_fail_action.BoolValue)
    {
        menu.AddItem(RFAMENU_ITEM_INFO_NOTHING, "Do Nothing");
        menu.AddItem(RFAMENU_ITEM_INFO_ACCEPT, "Default Accept Winner");
    }
    else
    {
        menu.AddItem(RFAMENU_ITEM_INFO_NOTHING, "Default Do Nothing");
        menu.AddItem(RFAMENU_ITEM_INFO_ACCEPT, "Accept Winner");
    }
    
    menu.ExitBackButton = true;
    
    menu.Display(client, 0);
}

public int HandleMV_RunoffFailAction(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            SetTrieValue(menu_tries[param1], "runoff_fail_action", param2);
            
            DisplayExtendMenu(param1);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                DisplayMaxRunoffMenu(param1);
            }
            else
            {
                CloseClientVoteTrie(param1);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

void DisplayExtendMenu(int client)
{
    Menu menu = new Menu(HandleMV_Extend, MenuAction_DisplayItem|MenuAction_Display);
    menu.SetTitle("AM Extend Menu");
    
    if (cvar_extensions.BoolValue)
    {
        menu.AddItem(EMENU_ITEM_INFO_NO, "No");
        menu.AddItem(EMENU_ITEM_INFO_YES, "Default Yes");
    }
    else
    {
        menu.AddItem(EMENU_ITEM_INFO_NO, "Default No");
        menu.AddItem(EMENU_ITEM_INFO_YES, "Yes");
    }
    
    menu.ExitBackButton = true;
    menu.Display(client, 0);
}

public int HandleMV_Extend(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            SetTrieValue(menu_tries[param1], "extend", param2);
            
            DisplayDontChangeMenu(param1);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                if (RunoffIsEnabled(param1))
                {
                    DisplayMaxRunoffMenu(param1);
                }
                else
                {
                    DisplayFailActionMenu(param1);
                }
            }
            else
            {
                CloseClientVoteTrie(param1);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

bool RunoffIsEnabled(int client)
{
    UMC_VoteFailAction failAction;
    GetTrieValue(menu_tries[client], "fail_action", failAction);

    return failAction == VoteFailAction_Runoff;
}

void DisplayDontChangeMenu(int client)
{
    Menu menu = new Menu(HandleMV_DontChange, MenuAction_DisplayItem|MenuAction_Display);
    menu.SetTitle("AM Don't Change Menu");
    
    if (cvar_dontchange.BoolValue)
    {
        menu.AddItem(DCMENU_ITEM_INFO_NO, "No");
        menu.AddItem(DCMENU_ITEM_INFO_YES, "Default Yes");
    }
    else
    {
        menu.AddItem(DCMENU_ITEM_INFO_NO, "Default No");
        menu.AddItem(DCMENU_ITEM_INFO_YES, "Yes");
    }
    
    menu.ExitBackButton = true;

    menu.Display(client, 0);
}

public int HandleMV_DontChange(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            StringMap trie = menu_tries[param1];
            SetTrieValue(trie, "dont_change", param2);
            
            char flags[64];
            cvar_flags.GetString(flags, sizeof(flags));
            
            if (flags[0] != '\0')
            {
                SetTrieValue(trie, "skip_admin", false);
                DisplayAdminFlagsMenu(param1);
            }
            else
            {
                SkipAdminFlags(param1);
                DisplayChangeWhenMenu(param1);
            }
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                DisplayExtendMenu(param1);
            }
            else
            {
                CloseClientVoteTrie(param1);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

void SkipAdminFlags(int client)
{
    StringMap trie = menu_tries[client];
    SetTrieString(trie, "flags", "");
    SetTrieValue(trie, "skip_admin", true);
}

bool SkippingAdminFlags(int client)
{
    bool result;
    return GetTrieValue(menu_tries[client], "skip_admin", result) && result;
}

void DisplayAdminFlagsMenu(int client)
{
    Menu menu = new Menu(HandleMV_AdminFlags, MenuAction_DisplayItem|MenuAction_Display);
    menu.SetTitle("AM Admin Flag Menu");
    
    char flags[64];
    cvar_flags.GetString(flags, sizeof(flags));
    
    menu.AddItem("", "Everyone");
    menu.AddItem(flags, "Admins Only");
    
    menu.ExitBackButton = true;

    menu.Display(client, 0);
}

public int HandleMV_AdminFlags(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[64];
            menu.GetItem(param2, info, sizeof(info));
            
            SetTrieString(menu_tries[param1], "flags", info);
            
            DisplayChangeWhenMenu(param1);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                DisplayDontChangeMenu(param1);
            }
            else
            {
                CloseClientVoteTrie(param1);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

void DisplayChangeWhenMenu(int client)
{
    Menu menu = new Menu(HandleMV_When, MenuAction_DisplayItem|MenuAction_Display);
    menu.SetTitle("AM Change When Menu");
    
    SetMenuExitBackButton(menu, true);

    char info1[2];
    FormatEx(info1, sizeof(info1), "%i", ChangeMapTime_Now);
    menu.AddItem(info1, "Now");
    
    char info2[2];
    FormatEx(info2, sizeof(info2), "%i", ChangeMapTime_RoundEnd);
    menu.AddItem(info2, "End of Round");
    
    char info3[2];
    FormatEx(info3, sizeof(info3), "%i", ChangeMapTime_MapEnd);
    menu.AddItem(info3, "End of Map");
    
    menu.Display(client, 0);
}

public int HandleMV_When(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[2];
            menu.GetItem(param2, info, sizeof(info));
            
            SetTrieValue(menu_tries[param1], "when", StringToInt(info));
            
            DoMapVote(param1);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                if (UsingDefaults(param1))
                {
                    char flags[64];
                    cvar_defaultsflags.GetString(flags, sizeof(flags));
                    
                    if (!ClientHasAdminFlags(param1, flags))
                    {
                        if (VoteAutoPopulated(param1))
                        {
                            DisplayAutoManualMenu(param1);
                        }
                        else
                        {
                            DisplayGroupSelectMenu(param1);
                        }
                    }
                    else
                    {
                        DisplayDefaultsMenu(param1);
                    }
                }
                else
                {
                    if (SkippingAdminFlags(param1))
                    {
                        DisplayDontChangeMenu(param1);
                    }
                    else
                    {
                        DisplayAdminFlagsMenu(param1);
                    }
                }
            }
            else
            {
                CloseClientVoteTrie(param1);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

bool UsingDefaults(int client)
{
    bool defaults;
    GetTrieValue(menu_tries[client], "defaults", defaults);
    
    return defaults;
}

void DoMapVote(int client)
{
    StringMap trie = menu_tries[client];
    ArrayList selectedMaps;
    
    UMC_VoteType type;
    bool scramble, extend, dontChange;
    float threshold;
    UMC_ChangeMapTime when;
    UMC_VoteFailAction failAction;
    int runoffs;
    UMC_RunoffFailAction runoffFailAction;
        
    char flags[64];
    
    bool ignoreExclusion;
        
    GetTrieValue(trie, "maps", selectedMaps);

    bool autoPop = VoteAutoPopulated(client);
    KeyValues mapcycle = autoPop ? map_kv : CreateVoteKV(selectedMaps);

    GetTrieValue(trie, "type",               type);
    GetTrieValue(trie, "scramble",           scramble);
    GetTrieValue(trie, "extend",             extend);
    GetTrieValue(trie, "dont_change",        dontChange);
    GetTrieValue(trie, "threshold",          threshold);
    GetTrieValue(trie, "when",               when);
    GetTrieValue(trie, "fail_action",        failAction);
    GetTrieValue(trie, "runoff_fail_action", runoffFailAction);
    GetTrieValue(trie, "max_runoffs",        runoffs);
    
    GetTrieString(trie, "flags", flags, sizeof(flags));
    
    int clients[MAXPLAYERS+1];
    int numClients;
    GetClientsWithFlags(flags, clients, sizeof(clients), numClients);
    
    GetTrieValue(trie, "ignore_exclusion", ignoreExclusion);
    
    CloseClientVoteTrie(client);

    UMC_StartVote(
        "core",
        mapcycle, umc_mapcycle, type, cvar_vote_time.IntValue, scramble, vote_start_sound,
        vote_end_sound, extend, cvar_extend_time.FloatValue, cvar_extend_rounds.IntValue,
        cvar_extend_frags.IntValue, dontChange, threshold, when, failAction, runoffs,
        cvar_runoff_max.IntValue, runoffFailAction, runoff_sound,
        cvar_strict_noms.BoolValue, cvar_vote_allowduplicates.BoolValue, clients, 
        numClients, !ignoreExclusion
    );
    
    if (!autoPop)
    {
        CloseHandle(mapcycle);
    }
}

KeyValues CreateVoteKV(ArrayList maps)
{
    KeyValues result = new KeyValues("umc_rotation");
    map_kv.Rewind();
    KvCopySubkeys(map_kv, result);
    
    if (!result.GotoFirstSubKey())
    {
        return result;
    }
    
    char group[MAP_LENGTH], map[MAP_LENGTH];
    bool goBackMap;
    bool goBackGroup = true;
    int groupMapCount;
    for ( ; ; )
    {
        groupMapCount = 0;
        goBackMap = true;
    
        result.GetSectionName(group, sizeof(group));
        
        if (!result.GotoFirstSubKey())
        {
            if (!result.GotoNextKey())
            {
                break;
            }
            continue;
        }
 
        for ( ; ; )
        {
            result.GetSectionName(map, sizeof(map));
            
            if (!FindMapInList(maps, map, group))
            {
                if (result.DeleteThis() == -1)
                {
                    goBackMap = false;
                    break;
                }
                else
                {
                    continue;
                }
            }
            else
            {
                groupMapCount++;
            }
            
            if (!result.GotoNextKey())
            {
                break;
            }
        }
        
        if (goBackMap)
        {
            result.GoBack();
        }
        
        if (!result.GotoFirstSubKey())
        {
            if (result.DeleteThis() == -1)
            {
                goBackGroup = false;
                break;
            }
            else
            {
                continue;
            }
        }
        else
        {
            result.GoBack();
            result.SetNum("maps_invote", groupMapCount);
        }
            
        if (!result.GotoNextKey())
        {
            break;
        }
    }
    
    if (goBackGroup)
    {
        result.GoBack();
    }
    
    return result;
}

bool FindMapInList(ArrayList maps, const char[] map, const char[] group)
{
    char gBuffer[MAP_LENGTH], mBuffer[MAP_LENGTH];
    StringMap trie;
    int size = GetArraySize(maps);
    for (int i = 0; i < size; i++)
    {
        trie = maps.Get(i);
        GetTrieString(trie, MAP_TRIE_MAP_KEY, mBuffer, sizeof(mBuffer));
        if (StrEqual(mBuffer, map, false))
        {
            GetTrieString(trie, MAP_TRIE_GROUP_KEY, gBuffer, sizeof(gBuffer));
            if (StrEqual(gBuffer, group, false))
            {
                return true;
            }
        }
    }
    return false;
}

void CreateAMNextMap(int client)
{
    Menu menu = CreateAutoManualMenu(HandleAM_NextMap, "Select A Map");
    menu.Display(client, 0);
}

void CreateAMChangeMap(int client)
{
    Menu menu = CreateAutoManualMenu(HandleAM_ChangeMap, "Select A Map");
    menu.Display(client, 0);
}

public int HandleAM_ChangeMap(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            if (param2 == AMMENU_ITEM_INDEX_AUTO)
            {
                AutoChangeMap(param1);
            }
            else
            {
                ManualChangeMap(param1);
            }
        }
        case MenuAction_Cancel:
        {
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

void ManualChangeMap(int client)
{
    menu_tries[client] = new StringMap();
    
    bool ignoreExclude = false;
    char flags[64];
    cvar_ignoreexcludeflags.GetString(flags, sizeof(flags));
    
    if (flags[0] != '\0')
    {
        if (ReadFlagString(flags) & GetUserFlagBits(client))
        {
            ignoreExclude = true;
        }
    }
    else
    {
        ignoreExclude = true;
    }
    
    Menu menu = CreateGroupMenu(HandleGM_ChangeMap, !ignoreExclude, client);
    menu.Display(client, 0);
}

public int HandleGM_ChangeMap(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Display:
        {
            Handle_MenuTranslation(menu, action, param1, param2);
        }
        case MenuAction_Select:
        {
            char group[MAP_LENGTH];
            menu.GetItem(param2, group, sizeof(group));
            
            SetTrieString(menu_tries[param1], "group", group);
            
            bool ignoreExclude = false;
            char flags[64];
            cvar_ignoreexcludeflags.GetString(flags, sizeof(flags));
            
            if (flags[0] != '\0')
            {
                if (ReadFlagString(flags) & GetUserFlagBits(param1))
                {
                    ignoreExclude = true;
                }
            }
            else
            {
                ignoreExclude = true;
            }
            
            Menu newMenu = CreateMapMenu(HandleMM_ChangeMap, group, !ignoreExclude, param1);
            newMenu.Display(param1, 0);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                CreateAMChangeMap(param1);
            }
            else
            {
                CloseHandle(menu_tries[param1]);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return 0;
}

public int HandleMM_ChangeMap(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Display:
        {
            Handle_MenuTranslation(menu, action, param1, param2);
        }
        case MenuAction_Select:
        {
            char map[MAP_LENGTH];
            menu.GetItem(param2, map, sizeof(map));
            
            SetTrieString(menu_tries[param1], "map", map);
            
            ManualChangeMapWhen(param1);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                bool ignoreExclude = false;
                char flags[64];
                cvar_ignoreexcludeflags.GetString(flags, sizeof(flags));
                
                if (flags[0] != '\0')
                {
                    if (ReadFlagString(flags) & GetUserFlagBits(param1))
                    {
                        ignoreExclude = true;
                    }
                }
                else
                {
                    ignoreExclude = true;
                }
            
                Menu newMenu = CreateGroupMenu(HandleGM_ChangeMap, !ignoreExclude, param1);
                newMenu.Display(param1, 0);
            }
            else
            {
                CloseHandle(menu_tries[param1]);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return 0;
}

void ManualChangeMapWhen(int client)
{
    Menu menu = new Menu(Handle_ManualChangeWhenMenu, MenuAction_DisplayItem|MenuAction_Display);
    menu.SetTitle("AM Change When Menu");
    
    menu.ExitBackButton = true;

    char info1[2];
    FormatEx(info1, sizeof(info1), "%i", ChangeMapTime_Now);
    menu.AddItem(info1, "Now");
    
    char info2[2];
    FormatEx(info2, sizeof(info2), "%i", ChangeMapTime_RoundEnd);
    menu.AddItem(info2, "End of Round");
    
    menu.Display(client, 0);
}

public int Handle_ManualChangeWhenMenu(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[2];
            menu.GetItem(param2, info, sizeof(info));
            
            SetTrieValue(menu_tries[param1], "when", StringToInt(info));
            DoManualMapChange(param1);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                bool ignoreExclude = false;
                char flags[64];
                cvar_ignoreexcludeflags.GetString(flags, sizeof(flags));
                
                if (flags[0] != '\0')
                {
                    if (ReadFlagString(flags) & GetUserFlagBits(param1))
                    {
                        ignoreExclude = true;
                    }
                }
                else
                {
                    ignoreExclude = true;
                }
            
                Menu newMenu = CreateGroupMenu(HandleGM_ChangeMap, !ignoreExclude, param1);
                newMenu.Display(param1, 0);
            }
            else
            {
                CloseHandle(menu_tries[param1]);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

void DoManualMapChange(int client)
{
    StringMap trie = menu_tries[client];
    
    char nextMap[MAP_LENGTH], nextGroup[MAP_LENGTH];
    int when;
    
    GetTrieString(trie, "map", nextMap, sizeof(nextMap));
    GetTrieString(trie, "group", nextGroup, sizeof(nextGroup));
    GetTrieValue(trie, "when", when);
    
    CloseHandle(trie);
    
    DoMapChange(client, view_as<UMC_ChangeMapTime>(when), nextMap, nextGroup);
}

void AutoChangeMap(int client)
{
    Menu menu = new Menu(Handle_AutoChangeWhenMenu, MenuAction_DisplayItem|MenuAction_Display);
    SetMenuTitle(menu, "AM Change When Menu");
    
    menu.ExitBackButton = true;

    char info1[2];
    FormatEx(info1, sizeof(info1), "%i", ChangeMapTime_Now);
    menu.AddItem(info1, "Now");
    
    char info2[2];
    FormatEx(info2, sizeof(info2), "%i", ChangeMapTime_RoundEnd);
    menu.AddItem(info2, "End of Round");
    
    menu.Display(client, 0);
}

public int Handle_AutoChangeWhenMenu(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[2];
            menu.GetItem(param2, info, sizeof(info));
            
            DoAutoMapChange(param1, view_as<UMC_ChangeMapTime>(StringToInt(info)));
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                CreateAMChangeMap(param1);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

void DoAutoMapChange(int client, UMC_ChangeMapTime when)
{
    char nextMap[MAP_LENGTH], nextGroup[MAP_LENGTH];
    if (UMC_GetRandomMap(map_kv, umc_mapcycle, INVALID_GROUP, nextMap, sizeof(nextMap), nextGroup, sizeof(nextGroup), false, true))
    {
        DoMapChange(client, when, nextMap, nextGroup);
    }
    else
    {
        LogError("Could not automatically change the map, no valid maps available.");
    }
}

void DoMapChange(int client, UMC_ChangeMapTime when, const char[] map, const char[] group)
{
    UMC_SetNextMap(map_kv, map, group, when);
    LogUMCMessage("%L set the next map to %s from group %s.", client, map, group);
}

public int HandleAM_NextMap(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            if (param2 == AMMENU_ITEM_INDEX_AUTO)
            {
                AutoNextMap(param1);
            }
            else
            {
                ManualNextMap(param1);
            }
        }
        case MenuAction_Cancel:
        {   
            // Do Nothing
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return Handle_MenuTranslation(menu, action, param1, param2);
}

void ManualNextMap(int client)
{
    menu_tries[client] = new StringMap();
    
    bool ignoreExclude = false;
    char flags[64];
    cvar_ignoreexcludeflags.GetString(flags, sizeof(flags));
    
    if (flags[0] != '\0')
    {
        if (ReadFlagString(flags) & GetUserFlagBits(client))
        {
            ignoreExclude = true;
        }
    }
    else
    {
        ignoreExclude = true;
    }
    
    Menu menu = CreateGroupMenu(HandleGM_NextMap, !ignoreExclude, client);
    DisplayMenu(menu, client, 0);
}

public int HandleGM_NextMap(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Display:
        {
            Handle_MenuTranslation(menu, action, param1, param2);
        }
        case MenuAction_Select:
        {
            char group[MAP_LENGTH];
            menu.GetItem(param2, group, sizeof(group));
            
            SetTrieString(menu_tries[param1], "group", group);
            
            bool ignoreExclude = false;
            char flags[64];
            cvar_ignoreexcludeflags.GetString(flags, sizeof(flags));
            
            if (flags[0] != '\0')
            {
                if (ReadFlagString(flags) & GetUserFlagBits(param1))
                {
                    ignoreExclude = true;
                }
            }
            else
            {
                ignoreExclude = true;
            }
            
            Menu newMenu = CreateMapMenu(HandleMM_NextMap, group, !ignoreExclude, param1);
            newMenu.Display(param1, 0);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                CreateAMNextMap(param1);
            }
            else
            {
                CloseHandle(menu_tries[param1]);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return 0;
}

public int HandleMM_NextMap(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Display:
        {
            Handle_MenuTranslation(menu, action, param1, param2);
        }
        case MenuAction_Select:
        {
            char map[MAP_LENGTH];
            menu.GetItem(param2, map, sizeof(map));
            
            SetTrieString(menu_tries[param1], "map", map);
            
            DoManualNextMap(param1);
        }
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
            {
                bool ignoreExclude = false;
                char flags[64];
                cvar_ignoreexcludeflags.GetString(flags, sizeof(flags));
                
                if (flags[0] != '\0')
                {
                    if (ReadFlagString(flags) & GetUserFlagBits(param1))
                    {
                        ignoreExclude = true;
                    }
                }
                else
                {
                    ignoreExclude = true;
                }
            
                Menu newMenu = CreateGroupMenu(HandleGM_ChangeMap, !ignoreExclude, param1);
                newMenu.Display(param1, 0);
            }
            else
            {
                CloseHandle(menu_tries[param1]);
            }
        }
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    return 0;
}

void DoManualNextMap(int client)
{
    StringMap trie = menu_tries[client];
    
    char nextMap[MAP_LENGTH], nextGroup[MAP_LENGTH];
    GetTrieString(trie, "map", nextMap, sizeof(nextMap));
    GetTrieString(trie, "group", nextGroup, sizeof(nextGroup));
    
    CloseHandle(trie);
    
    DoMapChange(client, ChangeMapTime_MapEnd, nextMap, nextGroup);
}

void AutoNextMap(int client)
{
    char nextMap[MAP_LENGTH], nextGroup[MAP_LENGTH];
    if (UMC_GetRandomMap(map_kv, umc_mapcycle, INVALID_GROUP, nextMap, sizeof(nextMap), nextGroup, sizeof(nextGroup), false, true))
    {
        DoMapChange(client, ChangeMapTime_MapEnd, nextMap, nextGroup);
    }
    else
    {
        LogError("Could not automatically set the next map, no valid maps available.");
    }
}

stock ArrayList FetchGroupNames(KeyValues kv)
{
    ArrayList result = new ArrayList(ByteCountToCells(MAP_LENGTH));
    if (!kv.GotoFirstSubKey())
    {
        return result;
    }
    
    char group[MAP_LENGTH];
    
    do
    {
        kv.GetSectionName(group, sizeof(group));
        result.PushString(group);
    }
    while (kv.GotoNextKey());
    
    kv.GoBack();
    
    return result;
}

stock ArrayList FetchMapsFromGroup(KeyValues kv, const char[] group)
{
    KeyValues mapcycle = new KeyValues("umc_rotation");
    KvCopySubkeys(kv, mapcycle);

    if (!kv.JumpToKey(group))
    {
        LogError("Cannot jump to map group '%s'", group);
        CloseHandle(mapcycle);
        return null;
    }
    
    ArrayList result = new ArrayList();
    
    if (!kv.GotoFirstSubKey())
    {
        CloseHandle(mapcycle);
        return result;
    }
        
    char map[MAP_LENGTH];
    StringMap trie;
    
    do
    {
        kv.GetSectionName(map, sizeof(map));
        trie = new StringMap();
        SetTrieString(trie, MAP_TRIE_MAP_KEY, map);
        SetTrieString(trie, MAP_TRIE_GROUP_KEY, group);
        SetTrieValue(trie, "excluded", !UMC_IsMapValid(mapcycle, map, group, false, true));
        result.Push(trie);
    }
    while (kv.GotoNextKey());
    
    kv.GoBack();
    kv.GoBack();
    
    return result;
}

void FilterGroupArrayForAdmin(ArrayList groups, int admin)
{
    int userflags = GetUserFlagBits(admin);
    
    char group[MAP_LENGTH];
    char gFlags[64], mFlags[64];
    int size = GetArraySize(groups);
    for (int i = 0; i < size; i++)
    {
        bool excluded = true;
        
        groups.GetString(i, group, sizeof(group));
        map_kv.JumpToKey(group);
        map_kv.GetString(ADMINMENU_ADMINFLAG_KEY, gFlags, sizeof(gFlags), "");
        
        if (map_kv.GotoFirstSubKey())
        {
            do
            {
                map_kv.GetString(ADMINMENU_ADMINFLAG_KEY, mFlags, sizeof(mFlags), gFlags);
                if (mFlags[0] == '\0' || (userflags & ReadFlagString(mFlags)))
                {
                    excluded = false;
                    break;
                }
            }
            while (map_kv.GotoNextKey());
            
            map_kv.GoBack();
        }
        
        if (excluded)
        {
            groups.Erase(i);
            size--;
            i--;
        }
        
        map_kv.GoBack();
    }
}

//Builds and returns a map group selection menu.
Menu CreateGroupMenu(MenuHandler handler, bool limits, int client)
{
    //Initialize the menu
    Menu menu = new Menu(handler, MenuAction_DisplayItem|MenuAction_Display);
    menu.SetTitle("Select A Group");
    
    menu.ExitBackButton = true;
    
    map_kv.Rewind();
    
    //Get group array.
    ArrayList groupArray;
    if (limits)
    {
        groupArray = UMC_CreateValidMapGroupArray(map_kv, umc_mapcycle, false, true);
    }
    else
    {
        groupArray = FetchGroupNames(umc_mapcycle);
    }
    
    FilterGroupArrayForAdmin(groupArray, client);
    
    int size = GetArraySize(groupArray);
    
    //Log an error and return nothing if the number of maps available to be nominated
    if (size == 0)
    {
        LogError("No map groups available to build menu.");
        CloseHandle(menu);
        CloseHandle(groupArray);
        return null;
    }
    
    char group[MAP_LENGTH], buffer[MAP_LENGTH];
    for (int i = 0; i < size; i++)
    {
        GetArrayString(groupArray, i, group, sizeof(group));
        if (!limits)
        {
            umc_mapcycle.JumpToKey(group);
            if (!umc_mapcycle.GotoFirstSubKey())
            {
                umc_mapcycle.GoBack();
                continue;
            }
            umc_mapcycle.GoBack();
            umc_mapcycle.GoBack();
            
            if (GroupExcludedPreviouslyPlayed(group, vote_catmem_arr, cvar_vote_catmem.IntValue))
            {
                FormatEx(buffer, sizeof(buffer), "%s (!)", group);
                menu.AddItem(group, buffer);
            }
            else
            {
                menu.AddItem(group, group);
            }
        }
        else
        {
            menu.AddItem(group, group);
        }
    }
    
    //No longer need the array.
    CloseHandle(groupArray);

    //Success!
    return menu;
}

//Builds and returns a map selection menu.
Menu CreateMapMenu(MenuHandler handler, const char[] group, bool limits, int client)
{
    //Initialize the menu
    Menu menu = new Menu(handler, MenuAction_DisplayItem|MenuAction_Display);
    
    //Set the title.
    menu.SetTitle("Select A Map");
    
    menu.ExitBackButton = true;
    
    map_kv.Rewind();
    
    KeyValues dispKV = new KeyValues("umc_mapcycle");
    KvCopySubkeys(umc_mapcycle, dispKV);

    //Get map array.
    ArrayList mapArray;
    if (limits)
    {
        mapArray = UMC_CreateValidMapArray(map_kv, umc_mapcycle, group, false, true);
    }
    else
    {
        mapArray = FetchMapsFromGroup(umc_mapcycle, group);
    }
    
    int size = GetArraySize(mapArray);
    if (size == 0)
    {
        LogError("No maps available to build menu.");
        CloseHandle(menu);
        CloseHandle(mapArray);
        CloseHandle(dispKV);
        return null;
    }
    
    //Variables
    int numCells = ByteCountToCells(MAP_LENGTH);
    ArrayList menuItems = new ArrayList(numCells);
    ArrayList menuItemDisplay = new ArrayList(numCells);
    char display[MAP_LENGTH + 4]; //, String:gDisp[MAP_LENGTH];
    StringMap mapTrie;
    char mapBuff[MAP_LENGTH], groupBuff[MAP_LENGTH];
    bool excluded;
    char gAdminFlags[64], mAdminFlags[64];
    for (int i = 0; i < size; i++)
    {
        mapTrie = mapArray.Get(i);
        GetTrieString(mapTrie, MAP_TRIE_MAP_KEY, mapBuff, sizeof(mapBuff));
        GetTrieString(mapTrie, MAP_TRIE_GROUP_KEY, groupBuff, sizeof(groupBuff));
        GetTrieValue(mapTrie, "excluded", excluded);
        
        umc_mapcycle.JumpToKey(groupBuff);
        umc_mapcycle.GetString(ADMINMENU_ADMINFLAG_KEY, gAdminFlags, sizeof(gAdminFlags), "");
        umc_mapcycle.JumpToKey(mapBuff);

        //Get the name of the current map.
        umc_mapcycle.GetSectionName(mapBuff, sizeof(mapBuff));
        umc_mapcycle.GetString(ADMINMENU_ADMINFLAG_KEY, mAdminFlags, sizeof(mAdminFlags), gAdminFlags);
        
        if (!ClientHasAdminFlags(client, mAdminFlags))
        {
            continue;
        }
        
        UMC_FormatDisplayString(display, sizeof(display), dispKV, mapBuff, groupBuff);
            
        if (UMC_IsMapNominated(mapBuff, groupBuff))
        {
            char buff[MAP_LENGTH];
            strcopy(buff, sizeof(buff), display);
            FormatEx(display, sizeof(display), "%s (*)", buff);
        }
            
        if (excluded || MapExcludedPreviouslyPlayed(mapBuff, groupBuff, vote_mem_arr, vote_catmem_arr, cvar_vote_catmem.IntValue))
        {
            char buff[MAP_LENGTH];
            strcopy(buff, sizeof(buff), display);
            FormatEx(display, sizeof(display), "%s (!)", buff);
        }
            
        //Add map data to the arrays.
        PushArrayString(menuItems, mapBuff);
        PushArrayString(menuItemDisplay, display);
        
        umc_mapcycle.Rewind();
    }
    
    //Add all maps from the nominations array to the menu.
    AddArrayToMenu(menu, menuItems, menuItemDisplay);
    
    //No longer need the arrays.
    CloseHandle(menuItems);
    CloseHandle(menuItemDisplay);
    ClearHandleArray(mapArray);
    CloseHandle(mapArray);
    
    //Or the display KV
    CloseHandle(dispKV);
    
    //Success!
    return menu;
}

//Builds a menu with Auto and Manual options.
Menu CreateAutoManualMenu(MenuHandler handler, const char[] title)
{
    Menu menu = new Menu(handler, MenuAction_DisplayItem|MenuAction_Display);
    menu.SetTitle(title);
    
    menu.AddItem(AMMENU_ITEM_INFO_AUTO, "Auto Select");
    menu.AddItem(AMMENU_ITEM_INFO_MANUAL, "Manual Select");
    
    return menu;
}

//************************************************************************************************//
//                                   ULTIMATE MAPCHOOSER EVENTS                                   //
//************************************************************************************************//
//Called when UMC requests that the mapcycle should be reloaded.
public void UMC_RequestReloadMapcycle()
{
    can_vote = ReloadMapcycle();
    if (can_vote)
    {
        RemovePreviousMapsFromCycle();
    }
}

//Called when UMC requests that the mapcycle is printed to the console.
public void UMC_DisplayMapCycle(int client, bool filtered)
{
    PrintToConsole(client, "Module: UMC Admin Menu");
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
