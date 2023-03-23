#pragma semicolon 1

#include <sourcemod>
#include <umc-core>
#include <umc_utils>

#pragma newdecls required

public Plugin myinfo =
{
    name = "umc-custom-crash-handler",
    author = "monera",
    description = "If the game crashes, after the restart, The plugins sets the map to map voted previously.",
    version = "1.0.0",
    url = ""
}

public void OnPluginStart()
{
    HookEvent("teamplay_round_active", Event_TeamplayRoundActive, EventHookMode_PostNoCopy);
}

public void Event_TeamplayRoundActive(Event event, const char[] name, bool dontBroadcast)
{
    CheckChangeMap();
}

void CheckChangeMap()
{
    if(!FileExists("voted_map.txt"))
    {
        LogMessage("voted_map.txt does not exist");

        return;
    }


    File voted_map = OpenFile("voted_map.txt", "r");
    if(voted_map == null)
    {
        LogMessage("OpenFile failed");

        return;
    }


    char time[128];

    voted_map.ReadLine(time, sizeof(time));
    TrimString(time);

    LogMessage("GetEG: %f, Saved Time: %f", GetEngineTime(), StringToFloat(time));

    if(GetEngineTime() >= StringToFloat(time))
    {
        LogMessage("GetEG >= Saved Time");

        voted_map.Close();
        DeleteFile("voted_map.txt");
        return;
    }


    char map[128], current_map[128];

    voted_map.ReadLine(map, sizeof(map));
    TrimString(map);
    GetCurrentMap(current_map, sizeof(current_map));

    LogMessage("map: %s, current_map: %s", map, current_map);

    if(strcmp(map, current_map) == 0)
    {
        LogMessage("strcmp(map, current_map) == 0");

        voted_map.Close();
        DeleteFile("voted_map.txt");
        return;
    }


    char group[128];

    voted_map.ReadLine(group, sizeof(group));
    TrimString(group);


    voted_map.Close();
    DeleteFile("voted_map.txt");

    Handle umc_mapcycle = UMC_GetMapcycle();

    if(umc_mapcycle == null)
    {
        LogMessage("umc_mapcycle.txt does not exist");

        return;
    }
    
    UMC_SetNextMap(umc_mapcycle, map, group, ChangeMapTime_Now);
}

public int UMC_OnNextmapSet(Handle kv, const char[] map, const char[] group, const char[] display)
{
    File voted_map = OpenFile("voted_map.txt", "w");

    voted_map.WriteLine("%f", GetEngineTime());
    voted_map.WriteLine("%s", map);
    voted_map.WriteLine("%s", group);

    voted_map.Close();
}

stock Handle UMC_GetMapcycle()
{
    //Get the kv handle from the file.
    Handle result = GetKvFromFile("umc_mapcycle.txt", "umc_rotation");
    
    //Log an error and return empty handle if the mapcycle file failed to parse.
    if (result == INVALID_HANDLE)
    {
        LogError("SETUP: Mapcycle failed to load!");
        return null;
    }
    
    //Success!
    return result;
}