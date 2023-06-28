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
#if defined _umc_utils_included
    #endinput
#endif
#define _umc_utils_included

#pragma semicolon 1

#include <sourcemod>
#include <umc-core>
#include <sdktools_functions>
#include <sdktools_entinput>
#include <sdktools_stringtables>
#include <regex>
#include <emitsoundany>

#pragma newdecls required

//************************************************************************************************//
//                                        GENERAL UTILITIES                                       //
//************************************************************************************************//

#if UMC_DEBUG
//Prints a debug message.
stock void DebugMessage(const char[] message, any ...)
{
    int size = strlen(message) + 255;
    char[] fMessage = new char[size];
    VFormat(fMessage, size, message, 2);
    
    LogUMCMessage("DEBUG: %s", fMessage);
}
#define DEBUG_MESSAGE(%0) DebugMessage(%0);

#else

#define DEBUG_MESSAGE(%0)

#endif


#define MIN(%0, %1) ((%0) < (%1)) ? (%0) : (%1)


stock void LogUMCMessage(const char[] message, any ...)
{
    int size = strlen(message) + 255;
    char[] fMessage = new char[size];
    VFormat(fMessage, size, message, 2);
    
    char fileName[PLATFORM_MAX_PATH];
    char timeStamp[64];
    FormatTime(timeStamp, sizeof(timeStamp), "%Y%m%d", GetTime());
    BuildPath(Path_SM, fileName, sizeof(fileName), "logs/UMC_%s.log", timeStamp);
    
    LogToFile(fileName, fMessage);
}


stock void StringToUpper(char[] str)
{
    for (int i = 0; str[i] != '\0'; i++)
    {
        str[i] = CharToUpper(str[i]);
    }
}


//Utility function to build a map trie.
stock StringMap CreateMapTrie(const char[] map, const char[] group)
{
    StringMap trie = new StringMap();
    trie.SetString(MAP_TRIE_MAP_KEY, map);
    trie.SetString(MAP_TRIE_GROUP_KEY, group);
    return trie;
}


//Utility function to get a KeyValues Handle from a filename, with the specified root key.
stock KeyValues GetKvFromFile(const char[] filename, const char[] rootKey, bool checkNorm = true)
{
    KeyValues kv = new KeyValues(rootKey);

    kv.SetEscapeSequences(true);
    
    //Log an error and return empty handle if the kv file fails to parse.
    if (!(checkNorm && ConvertNormalMapcycle(kv, filename)) && !kv.ImportFromFile(filename))
    {
        LogError("KV ERROR: Unable to load KV file: %s", filename);
        delete kv;
        return null;
    }
    
#if UMC_DEBUG
    LogKv(kv);
#endif
    
    return kv;
}


stock bool ConvertNormalMapcycle(KeyValues kv, const char[] filename)
{
    //DEBUG_MESSAGE("Opening Mapcycle File %s", filename)
    File file = OpenFile(filename, "r");
    
    if (file == null)
    {    
        return false;
    }
    
    //DEBUG_MESSAGE("Fetching first line.")
    char firstLine[256];
    bool foundDef = false;
    while (file.ReadLine(firstLine, sizeof(firstLine)))
    {
        TrimString(firstLine);
        if (strlen(firstLine) > 0)
        {
            foundDef = true;
            break;
        }
    }
    
    if (!foundDef)
    {
        //DEBUG_MESSAGE("Couldn't find first line")
        file.Close();
        return false;
    }
    
    //DEBUG_MESSAGE("Checking first line for UMC header: \"%s\"", firstLine)
    static Regex re = null;
    if (re == null)
    {
        re = new Regex("^//!UMC\\s+([0-9]+)\\s*$");
    }
    
    char buffer[5];
    
    if (re.Match(firstLine) > 1)
    {
        re.GetSubString(1, buffer, sizeof(buffer));
    }
    else
    {
        //DEBUG_MESSAGE("Header was not found. Aborting.")
        file.Close();
        return false;
    }
    
    //DEBUG_MESSAGE("Making a map group.")
    static Regex re2 = null;
    if (re2 == null)
    {
        re2 = new Regex("^\\s*([^/\\\\:*?'\"<>|\\s]+)\\s*(?://.*)?$");
    }

    kv.JumpToKey("Mapcycle", true);
    kv.SetNum("maps_invote", StringToInt(buffer));
    
    //DEBUG_MESSAGE("Parsing maps.")
    
    char map[MAP_LENGTH];
    char line[256];
    while (file.ReadLine(line, sizeof(line)))
    {
        TrimString(line);
        if (re2.Match(line) > 1)
        {
            re2.GetSubString(1, map, sizeof(map));
            //DEBUG_MESSAGE("Adding map: %s", map)
            kv.JumpToKey(map, true);
            kv.GoBack();
        }
    }
    
    kv.GoBack();
    file.Close();

    return true;
}


//Utility function to jump to a specific map in a mapcycle.
//  kv: Mapcycle Keyvalues that must be at the root value.
stock bool KvJumpToMap(KeyValues kv, const char[] map)
{
    if (!kv.GotoFirstSubKey())
    {
        return false;
    }    
    char mapName[MAP_LENGTH];
    
    do
    {
        if (!kv.GotoFirstSubKey())
        {
            continue;
        }
        
        do
        {
            kv.GetSectionName(mapName, sizeof(mapName));
            if (StrEqual(mapName, map))
            {
                return true;
            }
        }
        while (kv.GotoNextKey());
        
        kv.GoBack();
    }
    while (kv.GotoNextKey());
    
    kv.GoBack();

    return false;
}


//Utility function to search for a group that contains the given map.
//  kv: Mapcycle
//  map: Map whose group we're looking for.
//  buffer: Buffer to store the found group name.
//  maxlen: Maximum length of the buffer.
stock bool KvFindGroupOfMap(KeyValues kv, const char[] map, char[] buffer, int maxlen)
{
    if (!kv.GotoFirstSubKey())
    {
        return false;
    }
    
    char mapName[MAP_LENGTH], groupName[MAP_LENGTH];
    do
    {
        kv.GetSectionName(groupName, sizeof(groupName));
        
        if (!kv.GotoFirstSubKey())
        {
            continue;
        }
        
        do
        {
            kv.GetSectionName(mapName, sizeof(mapName));
            if (StrEqual(mapName, map, false))
            {
                kv.GoBack();
                kv.GoBack();

                strcopy(buffer, maxlen, groupName);
                return true;
            }
        }
        while (kv.GotoNextKey());
        
        kv.GoBack();
    }
    while (kv.GotoNextKey());
    kv.GoBack();
    return false;
}


enum CustomHudFallbackType 
{
    HudFallback_Chat,
    HudFallback_Hint,
    HudFallback_Center,
	HudFallback_None
};

//Color Arrays for colors in warning messages.
static int g_iSColors[7] = {
    1,
    3,
    3,
    4,
    4,
    5,
    6
};
static char g_sSColors[7][] = {
    "{DEFAULT}",
    "{LIGHTGREEN}",
    "{TEAM}",
    "{GREEN}",
    "{RED}",
    "{DARKGREEN}",
    "{YELLOW}"
};
static int g_iTColors[13][4] = {
    {255, 255, 255, 255},
    {255,   0,   0, 255},
    {  0, 255,   0, 255}, 
    {  0,   0, 255, 255},
    {255, 255,   0, 255},
    {255,   0, 255, 255},
    {  0, 255, 255, 255},
    {255, 128,   0, 255},
    {255,   0, 128, 255},
    {128, 255,   0, 255},
    {  0, 255, 128, 255},
    {128,   0, 255, 255}, 
    {  0, 128, 255, 255}
};
static char g_sTColors[13][] = {
    "{WHITE}",
    "{RED}",
    "{GREEN}",
    "{BLUE}",
    "{YELLOW}",
    "{PURPLE}",
    "{CYAN}",
    "{ORANGE}",
    "{PINK}",
    "{OLIVE}",
    "{LIME}",
    "{VIOLET}",    
    "{LIGHTBLUE}"
};

//Handle to the Center Message timer. For Vote Warnings.
static Handle center_message_timer = null;
static bool center_warning_active = false;

//Displays a message to the server
stock void DisplayServerMessage(const char[] msg, const char[] type)
{
    if (center_warning_active)
    {   
        center_warning_active = false;
        TriggerTimer(center_message_timer);
    }
    
    if (strlen(msg) == 0)
    {    
        return;
    }
    char message[255];
    strcopy(message, sizeof(message), msg);
    
    //Display a chat message ("S") if the user specifies.
    if (StrContains(type, "S") != -1)
    {
        char sColor[4];
        Format(message, sizeof(message), "%c%s", 1, message);
        for (int c = 0; c < sizeof(g_iSColors); c++)
        {
            if (StrContains(message, g_sSColors[c]))
            {
                FormatEx(sColor, sizeof(sColor), "%c", g_iSColors[c]);
                ReplaceString(message, sizeof(message), g_sSColors[c], sColor);
            }
        }
        PrintToChatAll(message);
    }
    
    //Buffer to hold message in order to manipulate it.
    char sTextTmp[255];
    
    //Display a top message ("T") if the user specifies.
    if (StrContains(type, "T") != -1)
    {
        strcopy(sTextTmp, sizeof(sTextTmp), message);
        char sColor[16];
        int iColor = -1;
        int iPos = BreakString(sTextTmp, sColor, sizeof(sColor));
        
        for (int i = 0; i < sizeof(g_sTColors); i++)
        {
            if (StrEqual(sColor, g_sTColors[i]))
            {    
                iColor = i;
            }
        }
        
        if (iColor == -1)
        {
            iPos   = 0;
            iColor = 0;
        }
        
        KeyValues hKv = new KeyValues("Stuff");
        hKv.SetString("title", sTextTmp[iPos]);
        hKv.SetColor4("color", g_iTColors[iColor]);
        hKv.SetNum("level", 1);
        hKv.SetNum("time", 10);

        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i))
            {    
                CreateDialog(i, hKv, DialogType_Msg);
            }
        }

        delete hKv;
    }
    
    // Remove colors, because C,H,M methods do not support colors.
    //Remove a color from the message string for each color in the Say color array.
    for (int c = 0; c < sizeof(g_iSColors); c++)
    {
        if (StrContains(message, g_sSColors[c]) != -1)
        {    
            ReplaceString(message, sizeof(message), g_sSColors[c], "");
        }
    }
    
    //Remove a color from the message string for each color in the Top color array.
    for (int c = 0; c < sizeof(g_iTColors); c++)
    {
        if (StrContains(message, g_sTColors[c]) != -1)
        {    
            ReplaceString(message, sizeof(message), g_sTColors[c], "");
        }
    }
    
    //Display a center message ("C") if the user specifies.
    if (StrContains(type, "C") != -1)
    {
        PrintCenterTextAll(message);
        
        //Setup timer to keep the center message visible.
        DataPack hCenterAd;
        center_message_timer = CreateDataTimer(1.0, Timer_CenterAd, hCenterAd, TIMER_REPEAT);
        hCenterAd.WriteString(message);
        
        center_warning_active = center_message_timer != null;
        if (!center_warning_active)
        {    
            delete hCenterAd;
        }
    }
    
    //Display a hint message ("H") if the user specifies.
    if (StrContains(type, "H") != -1)
    {    
        PrintHintTextToAll(message);
    }    
}


//Called with each tick of the timer for center messages. Used to keep the message visible for an
//extended period.
public Action Timer_CenterAd(Handle timer, DataPack pack)
{
    char sText[256];
    static int iCount = 0;
    
    pack.Reset();
    pack.ReadString(sText, sizeof(sText));
    
    if (center_warning_active && ++iCount < 5)
    {
        PrintCenterTextAll(sText);
        return Plugin_Continue;
    }
    else
    {
        iCount = 0;
        center_warning_active = false;
        center_message_timer = null;
        return Plugin_Stop;
    }
}


//Sets all elements of an array of booleans to false.
stock void ResetArray(bool[] arr, int size)
{
    for (int i = 0; i < size; i++)
    {    
        arr[i] = false;
    }
}


//Utility function to cache a sound.
stock void CacheSound(const char[] sound)
{
    //Handle the sound if it is defined.
    if (strlen(sound) > 0)
    {
        //Filepath buffer
        char filePath[PLATFORM_MAX_PATH];
    
        //Format sound to the correct directory.
        FormatEx(filePath, sizeof(filePath), "sound/%s", sound);
        
        //Log an error and don't cache the sound if the sound file does not exist
        if (!FileExists(filePath, true))
        {
            LogError("SOUND ERROR: Sound file '%s' does not exist.", filePath);
        }
        //Otherwise, cache the sound.
        else
        {
            //Make sure clients download the sound if they don't have it.
            AddFileToDownloadsTable(filePath);
            
            //Cache it.
            PrecacheSoundAny(sound, true);
            
            /*
            //Log an error if the sound failed to be cached.
            if (!IsSoundPrecached(filePath))
            {    
                LogError("SOUND ERROR: Failed to precache sound file '%s'", sound);
            }
            */
        }
    }
}


//Fetch the next index of the menu.
//    size: the size of the menu
//    scramble: whether or not a random index should be picked.
stock int GetNextMenuIndex(int size, bool scramble)
{
    return scramble ? GetRandomInt(0, size) : size;
}


//Inserts given string into given array at given index.
stock void InsertArrayString(ArrayList arr, int index, const char[] value)
{
    if (arr.Length > index)
    {
        arr.ShiftUp(index);
        arr.SetString(index, value);
    }
    else
    {
        arr.PushString(value);
    }
}


//Inserts given cell into given adt_array at given index,
stock void InsertArrayCell(ArrayList arr, int index, any cell)
{
    if (arr.Length > index)
    {
        arr.ShiftUp(index);
        arr.Set(index, cell);
    }
    else
    {
        arr.Push(cell);
    }
}


//Deletes values off the end of an array until it is down to the given size.
stock void TrimArray(ArrayList arr, int size)
{
    //Remove elements from the start of an array while the size of the array is greater than the required size.
    if (arr.Length > size)
    {
        arr.Resize(size);
    }
}


//Adds the given map to the given memory array.
//    mapName: the name of the map
//    arr:     the memory array we're adding to
//    size:    the maximum size of the memory array
stock void AddToMemoryArray(const char[] mapName, ArrayList arr, int size)
{
    //Add the new map to the beginning of the array.
    InsertArrayString(arr, 0, mapName);
    
    //Trim the array down to size.
    TrimArray(arr, size);
}


//Adds entire array to the given menu.
stock void AddArrayToMenu(Menu menu, ArrayList arr, ArrayList dispArr = null)
{
    char map[MAP_LENGTH], disp[MAP_LENGTH];
    int arrSize = arr.Length;
    int dispSize = (dispArr != null) ? dispArr.Length : 0;
    for (int i = 0; i < arrSize; i++)
    {
        arr.GetString(i, map, sizeof(map));
        if (i >= dispSize)
        {
            disp = map;
        }
        else
        {
            dispArr.GetString(i, disp, sizeof(disp));
        }
        
        menu.AddItem(map, disp);
    }
}


//Changes the map in 5 seconds.
stock void ForceChangeInFive(const char[] map, const char[] reason = "")
{
    //Notify the server.
    PrintToChatAll("\x03[UMC]\x01 %t", "Map Change in 5");
    
    //Setup the change.
    ForceChangeMap(map, 5.0, reason);
}


//Changes the map after the specified time period.
stock void ForceChangeMap(const char[] map, float time, const char[] reason = "")
{
    LogUMCMessage("%s: Changing map to '%s' in %.f seconds.", reason, map, time);

    //Setup the timer.
    DataPack pack;
    CreateDataTimer(
        time,
        Handle_MapChangeTimer,
        pack,
        TIMER_FLAG_NO_MAPCHANGE
    );
    pack.WriteString(map);
    pack.WriteString(reason);
}


//Called after the mapchange timer is completed.
public Action Handle_MapChangeTimer(Handle timer, DataPack pack)
{
    //Get map from the timer's pack.
    char map[MAP_LENGTH], reason[255];
    pack.Reset();
    pack.ReadString(map, sizeof(map));
    pack.ReadString(reason, sizeof(reason));
    
    //DEBUG_MESSAGE("Changing map to %s: %s", map, reason)
    
    //Change the map.
    ForceChangeLevel(map, reason);

    return Plugin_Continue;
}


//Determines if the current server time is between the given min and max.
stock bool IsTimeBetween(int min, int max)
{
    //Get the current server time.
    char time[5];
    FormatTime(time, sizeof(time), "%H%M");
    int theTime = StringToInt(time);
    
    //Handle wrap-around case if...
    //  ...max time is less than min time.
    if (max <= min)
    {
        max += 2400;
        if (theTime <= min)
        {
            theTime += 2400;
        }
    }
    return min <= theTime && theTime <= max;
}


//Determines if the current server player count is between the given min and max.
stock bool IsPlayerCountBetween(int min, int max)
{
    //Get the current number of players.
    int numplayers = GetRealClientCount();
    return min <= numplayers && numplayers <= max;
}


//Converts an adt_array to a standard array.
stock void ConvertAdtArray(ArrayList arr, any[] newArr, int size)
{
    int arraySize = arr.Length;
    int min = (size < arraySize) ? size : arraySize;
    for (int i = 0; i < min; i++)
    {    
        newArr[i] = arr.Get(i);
    }
}


stock void ConvertArray(const any[] arr, int amt, ArrayList newArr)
{
    for (int i = 0; i < amt; i++)
    {
        newArr.Push(arr[i]);
    }
}


//Selects one random name from the given name array, using the weights in the supplies weight array.
//Stores the result in buffer.
stock bool GetWeightedRandomSubKey(char[] buffer, int size, ArrayList weightArr, ArrayList nameArr, int &index = 0)
{
    //Calc total number of maps we're choosing.
    int total = weightArr.Length;
    
    //DEBUG_MESSAGE("Getting number of items in the pool - %i", total)
    
    //Return an answer immediately if there's only one map to choose from.
    if (total == 1)
    {   
        //DEBUG_MESSAGE("Only 1 item in pool, setting it as the winner.")
        //WE HAVE A WINNER!
        nameArr.GetString(0, buffer, size);
        return true;
    }
    //Otherwise, we immediately do nothing and return, if there are no maps to choose from.
    else if (total == 0)
    {
        //DEBUG_MESSAGE("No items in the pool. Returning false.")
        return false;
    }
    
    //custom: shuffle array once more
    //bogo sort?
    int ord1, ord2;
    for (int i = 0; i < total; i++)
    {
    	ord1 = GetRandomInt(0, total - 1);
    	do { ord2 = GetRandomInt(0, total - 1); } while(ord1 == ord2);
    	
        weightArr.SwapAt(ord1, ord2);
        nameArr.SwapAt(ord1, ord2);
    }
    
    weightArr.SortCustom(Sort_MapWeight, nameArr);

    //DEBUG_MESSAGE("Setting up array of weights.")
    //Convert the adt_array of weights to a normal array.
    float[] weights = new float[total];
    ConvertAdtArray(weightArr, weights, total);

    //DEBUG_MESSAGE("Picking a random number.")
    //We select a random number here by getting a random Float in the
    //range [0, 1), and then multiply it by the sum of the weights, to
    //make the effective range [0, totalweight).
    float rand = GetURandomFloat() * ArraySum(weights, total);
    float runningTotal = 0.0; //keeps track of total so far
    
    LogUMCMessage("--- MAP LIST ---");
    for (int i = 0; i < total; i++)
    {
        nameArr.GetString(i, buffer, size);
    	LogUMCMessage("\'%s\', Weight: %.2f", buffer, weights[i]);
    }
    
    //DEBUG_MESSAGE("Find the winner in the pool.")
    //Determine if a map is the winner for each map in the arrays.
    for (int i = 0; i < total; i++)
    {
        //DEBUG_MESSAGE("Update running total of weights.")
        //add weight onto the total
        runningTotal += weights[i];
        
        //DEBUG_MESSAGE("Check if we're at the right item.")
        //We have found an answer if the running total has reached the random number.
        if (runningTotal >= rand)
        {
            //DEBUG_MESSAGE("Item found.")
            nameArr.GetString(i, buffer, size);
            index = i;
            return true;
        }
    }
    
    //DEBUG_MESSAGE("ERROR WITH THE RANDOMIZATION ALGORITHM!")
    //This shouldn't ever happen, but alas the compiler complains.
    index = -1;
    return false;
}

int Sort_MapWeight(int index1, int index2, ArrayList weightArr, ArrayList nameArr)
{
	if (view_as<float>(weightArr.Get(index1)) < view_as<float>(weightArr.Get(index2)))
	{
		SwapArrayItems(nameArr, index1, index2);
		return 1;
	}
	
	return 0;
}

//Utility function to sum up an array of floats.
stock float ArraySum(const float[] floats, int size)
{
    float result = 0.0;
    for (int i = 0; i < size; i++)
    {
        result += floats[i];
    }
    return result;
}


//Utility function to clear an array of Handles and close each Handle.
stock void ClearHandleArray(ArrayList arr)
{
    int arraySize = arr.Length;
    for (int i = 0; i < arraySize; i++)
    {
        CloseHandle(arr.Get(i));
    }
    arr.Clear();
}


//Utility function to get the true count of active clients on the server.
stock int GetRealClientCount(bool inGameOnly = true)
{
    int clients = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if ((inGameOnly ? IsClientInGame(i) : IsClientConnected(i)) && !IsFakeClient(i))
        {
            clients++;
        }
    }
    return clients;
}


//Utiliy function to append arrays
stock void ArrayAppend(ArrayList arr1, ArrayList arr2)
{
    int arraySize = arr2.Length;
    for (int i = 0; i < arraySize; i++)
    {
        arr1.Push(arr2.Get(i));
    }
}


//Builds an adt_array of numbers from 0 to max-1.
stock ArrayList BuildNumArray(int max)
{
    int size = 2 + max / 10;
    ArrayList result = new ArrayList(ByteCountToCells(size));
    char[] buffer = new char[size];
    for (int i = 0; i < max; i++)
    {
        //IntToString(i, buffer, size);
        FormatEx(buffer, size, "%i", i);
        result.PushString(buffer);
    }
    return result;
}


//Determines the correct time to paginate a menu. Menu passed to this argument should have
//pagination enabled.
stock void SetCorrectMenuPagination(Menu menu, int numSlots)
{
    if (GetMenuStyleHandle(MenuStyle_Valve) != GetMenuStyleHandle(MenuStyle_Radio) && numSlots < 10)
    {
        SetMenuPagination(menu, MENU_NO_PAGINATION);
    }
}


//Finds a string in an array starting at a specific index.
stock int FindStringInArrayEx(ArrayList arr, const char[] value, int start = 0)
{
    int size = arr.Length;
    char buffer[255];
    for (int i = start; i < size; i++)
    {
        arr.GetString(i, buffer, sizeof(buffer));
        if (StrEqual(value, buffer))
        {
            return i;
        }
    }
    return -1;
}


//Creates a copy of an adt_array.
stock ArrayList CopyStringArray(ArrayList arr, int blocksize = 1)
{
    int size = arr.Length;
    ArrayList result = new ArrayList(blocksize);
    int len = 4 * blocksize;
    char[] buffer = new char[len];
    for (int i = 0; i < size; i++)
    {
        arr.GetString(i, buffer, len);
        result.PushString(buffer);
    }
    return result;
}


//Makes the timer to retry running a vote every second.
stock void MakeRetryVoteTimer(Function callback)
{
    PrivateForward callbackForward = new PrivateForward(ET_Single);
    callbackForward.AddFunction(null, callback);
    CreateTimer(1.0, Handle_RetryVoteTimer, callbackForward, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}


//Handles the retry timer for votes that were attempted to be started.
Action Handle_RetryVoteTimer(Handle timer, PrivateForward callback)
{
    if (!UMC_IsNewVoteAllowed())
    {
        return Plugin_Continue;
    }
    
    Call_StartForward(callback);
    Call_Finish();
    
    return Plugin_Stop;
}


//Comparison function for map tries <Map, MapGroup>. Used for sorting.
int CompareMapTries(int index1, int index2, ArrayList array, Handle hndl)
{
    char map1[MAP_LENGTH], map2[MAP_LENGTH],
         group1[MAP_LENGTH], group2[MAP_LENGTH];
    
    StringMap map = null;
    map = view_as<StringMap>(array.Get(index1));
    map.GetString(MAP_TRIE_MAP_KEY, map1, sizeof(map1));
    map.GetString(MAP_TRIE_GROUP_KEY, group1, sizeof(group1));
    map = view_as<StringMap>(array.Get(index2));
    map.GetString(MAP_TRIE_MAP_KEY, map2, sizeof(map2));
    map.GetString(MAP_TRIE_GROUP_KEY, group2, sizeof(group2));
    
    int result = strcmp(map1, map2);
    if (result == 0)
    {
        result = strcmp(group1, group2);
    }
    return result;
}


//Sorts an array of map tries
stock void SortMapTrieArray(ArrayList array)
{
    array.SortCustom(CompareMapTries);
}


//Prints the sections of a kv to the log.
stock void PrintKvToConsole(KeyValues kv, int client, int depth = 0)
{
    char section[64];
    kv.GetSectionName(section, sizeof(section));
    
    int whitespace = depth * 2 + 1;
    char[] space = new char[whitespace];
    FillWhiteSpace(space, whitespace);
    
    PrintToConsole(client, "%s\"%s\"", space, section);
    
    if (!kv.GotoFirstSubKey())
    {
        return;
    }
    
    do
    {
        PrintKvToConsole(kv, client, depth + 1);
    }
    while (kv.GotoNextKey());
    
    kv.GoBack();
}


//Prints the sections of a kv to the log.
stock void LogKv(KeyValues kv, int depth = 0)
{
    char section[64];
    kv.GetSectionName(section, sizeof(section));
    
    int whitespace = depth * 2 + 1;
    char[] space = new char[whitespace];
    FillWhiteSpace(space, whitespace);
    
    LogUMCMessage("%i: %s\"%s\"", depth+1, space, section);
    
    if (!kv.GotoFirstSubKey())
    {
        return;
    }

    do
    {
        LogKv(kv, depth + 1);
    }
    while (kv.GotoNextKey());
    
    kv.GoBack();
}


//Fills a string with whitespace.
stock void FillWhiteSpace(char[] buffer, int maxlen)
{
    int limit = maxlen - 1;
    for (int i = 0; i < limit; i++)
    {
        buffer[i] = ' ';
    }
    buffer[limit] = '\0';
}


stock void PrintNominationArray(ArrayList array)
{
    StringMap nom;
    char map[MAP_LENGTH], group[MAP_LENGTH];
    int size = array.Length;
    for (int i = 0; i < size; i++)
    {
        nom = view_as<StringMap>(array.Get(i));
        nom.GetString(MAP_TRIE_MAP_KEY, map, sizeof(map));
        nom.GetString(MAP_TRIE_GROUP_KEY, group, sizeof(group));
        //LogUMCMessage("%20s   |    %20s", map, group);
    }
}


stock bool VoteMenuToAllWithFlags(Menu menu, int time, const char[] flagstring = "")
{
    if (strlen(flagstring) > 0)
    {
        int flags = ReadFlagString(flagstring);
        int clients[MAXPLAYERS + 1];
        int count = 0;
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && (flags & GetUserFlagBits(i)))
            {
                clients[count++] = i;
            }
        }
        return VoteMenu(menu, clients, count, time);
    }
    else
    {
        return VoteMenuToAll(menu, time);
    }
}


stock void GetClientsWithFlags(const char[] flagstring, int[] clients, int maxlen, int &amt)
{
    bool checkFlags = strlen(flagstring) > 0;
    int flags = ReadFlagString(flagstring);
    int limit = (maxlen < MaxClients) ? maxlen : MaxClients;
    int count = 0;
    for (int i = 1; i <= limit; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && (!checkFlags || (flags & GetUserFlagBits(i))))
        {
            //DEBUG_MESSAGE("Client has correct flags: %L (%i) [F: %s]", i, i, flagstring)
            clients[count++] = i;
        }
    }
    amt = count;
}


stock int GetClientWithFlagsCount(const char[] flagstring)
{
    bool checkFlags = strlen(flagstring) > 0;
    int flags = ReadFlagString(flagstring);
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && (!checkFlags || (flags & GetUserFlagBits(i))))
        {
            count++;
        }
    }
    return count;
}


stock bool ClientHasAdminFlags(int client, const char[] flagString)
{
    return strlen(flagString) == 0 || (ReadFlagString(flagString) & GetUserFlagBits(client));
}


//Filters a mapcycle with all invalid entries filtered out. 
// NOTE: Our journey starts here! This gets called first and runs through the KV that we sent to it.
// First, it deletes all groups and maps that have been excluded from the search before we return to the first
// sub key in the KV to run the search.
// Second, it searchs the updated KV for the group that our map is in and filters the information until we only
// have the map and group information left over.
stock void FilterMapcycleFromArrays(KeyValues kv, ArrayList exMaps, ArrayList exGroups, int numExGroups, bool deleteEmpty = false)
{
    int size = exGroups.Length;
    int len = (size < numExGroups) ? size : numExGroups;
    char group[MAP_LENGTH];
    for (int i = 0; i < len; i++)
    {
        exGroups.GetString(i, group, sizeof(group));
        if (!deleteEmpty)
        {
            kv.JumpToKey(group);
            KvDeleteAllSubKeys(kv);
            kv.GoBack();
        }
        else
        {
            KvDeleteSubKey(kv, group);
        }
    }
    
    if (!kv.GotoFirstSubKey())
    {
        return;
    }
    
    for ( ; ; )
    {
        FilterMapGroupFromArrays(kv, exMaps, exGroups);
        
        //Delete the group if there are no valid maps in it.
        if (deleteEmpty) 
        {
            if (!kv.GotoFirstSubKey())
            {
                //DEBUG_MESSAGE("Removing empty group \"%s\".", group)
                if (kv.DeleteThis() == -1)
                {
                   // DEBUG_MESSAGE("Mapcycle filtering completed.")
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
    
    kv.GoBack();
    
    //DEBUG_MESSAGE("Mapcycle filtering completed.")
}


//Filters the kv at the level of the map group.
stock void FilterMapGroupFromArrays(KeyValues kv, ArrayList exMaps, ArrayList exGroups)
{
    char group[MAP_LENGTH];
    kv.GetSectionName(group, sizeof(group));
    
    if (!kv.GotoFirstSubKey())
    {
        return;
    }
    
    //DEBUG_MESSAGE("Starting filtering of map group \"%s\".", group)
    
    char mapName[MAP_LENGTH];
    for ( ; ; )
    {
        kv.GetSectionName(mapName, sizeof(mapName));
        if (IsMapInArrays(mapName, group, exMaps, exGroups))
        {
            //DEBUG_MESSAGE("Removing invalid map \"%s\" from group \"%s\".", mapName, group)
            if (kv.DeleteThis() == -1)
            {
                //DEBUG_MESSAGE("Map Group filtering completed for group \"%s\".", group)
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
    
    //DEBUG_MESSAGE("Map Group filtering completed for group \"%s\".", group)
}


stock bool IsMapInArrays(const char[] map, const char[] group, ArrayList exMaps, ArrayList exGroups)
{
    //DEBUG_MESSAGE("Starting exclusion traversal...")
    int index = -1;
    bool isExcluded = false;
    char exGroup[MAP_LENGTH];
    if (exMaps != null && exGroups != null)
    {
        int gSize = exGroups.Length;
        do
        {
            index = FindStringInArrayEx(exMaps, map, index+1);
            if (index >= 0 && index < gSize)
            {
                //DEBUG_MESSAGE("Map found at %i", index)
                exGroups.GetString(index, exGroup, sizeof(exGroup));
                isExcluded = StrEqual(exGroup, group, false);
                //DEBUG_MESSAGE("Map Excluded? %i (%s | %s)", _:isExcluded, exGroup, group)
            }
        }
        while (!isExcluded && index != -1);
    }
    
    return isExcluded;
}


stock bool GroupExcludedPreviouslyPlayed(const char[] group, ArrayList exGroups, int numExGroups)
{
    if (numExGroups <= 0) 
    {
        return false;
    }
    
    int i = FindStringInArray(exGroups, group);
    return i != -1 && i < numExGroups;
}


stock bool MapExcludedPreviouslyPlayed(const char[] map, const char[] group, ArrayList exMaps, ArrayList exGroups, int numExGroups)
{
    return GroupExcludedPreviouslyPlayed(group, exGroups, numExGroups) || IsMapInArrays(map, group, exMaps, exGroups);
}


stock bool KvDeleteSubKey(KeyValues kv, const char[] name)
{
    return kv.JumpToKey(name) && (kv.DeleteThis() == -1 || kv.GoBack());
}


stock void KvDeleteAllSubKeys(KeyValues kv)
{
    if (!kv.GotoFirstSubKey())
    {
        return;
    }
    
    for ( ; ; )
    {
        if (kv.DeleteThis() == -1)
        {
            return;
        }
    }
}


stock Handle CloseAndClone(Handle hndl, Handle newOwner)
{
    Handle result = CloneHandle(hndl, newOwner);
    CloseHandle(hndl);
    return result;
}


stock void ConvertClientsToUserIDs(const int[] clients, int[] userIds, int amt)
{
    for (int i = 0; i < amt; i++)
    {
        userIds[i] = GetClientUserId(clients[i]);
    }
}


stock void ConvertUserIDsToClients(const int[] userIds, int[] clients, int amt)
{
    for (int i = 0; i < amt; i++)
    {
        clients[i] = GetClientOfUserId(userIds[i]);
    }
}


stock bool GetTrieArray2(StringMap trie, const char[] key, any[] arr, int max_size, int &size = 0) 
{ 
    bool result = trie.GetArray(key, arr, max_size, size); 
    if (!result) 
    {
        result = trie.GetValue(key, arr[0]); 
        if (result) 
        { 
            size = 1;
        }
    }
    
    return result; 
}


stock int ArrayMin(const int[] arr, int maxlen, int &idx = 0)
{
    if (maxlen <= 0)
    {
        return 0;
    }
    
    int minIdx = 0;
    int min = arr[0];
    int tmp;
    for (int i = 1; i < maxlen; i++)
    {
        tmp = arr[i];
        if (tmp < min)
        {
            min = tmp;
            minIdx = i;
        }
    }

    idx = minIdx;

    return min;
}


stock int ArrayMax(const int[] arr, int maxlen, int &idx = 0)
{
    if (maxlen <= 0)
    {
        return 0;
    }
    
    int maxIdx = 0;
    int max = arr[0];
    int tmp;
    for (int i = 1; i < maxlen; i++)
    {
        tmp = arr[i];
        if (tmp > max)
        {
            max = tmp;
            maxIdx = i;
        }
    }

    idx = maxIdx;

    return max;
}