#pragma semicolon 1

#include <sourcemod>
#include <umc-core>
#include <umc_utils>

#pragma newdecls required

public Plugin myinfo =
{
    name = "umc-rebase-map",
    author = "monera",
    description = "Sets map as default.",
    version = "1.0.0",
    url = ""
}

public void OnPluginStart()
{
    RegAdminCmd("sm_umc_rebase", UMC_Rebase, ADMFLAG_CHANGEMAP, "Restores mapcycle");
}

public Action UMC_Rebase(int client, int args)
{
    Handle umc_mapcycle = UMC_GetMapcycle();

    char map[PLATFORM_MAX_PATH] = "trade_minecraft_neon_v182";
    char group[PLATFORM_MAX_PATH] = "숨 좀 돌리는";

    UMC_SetNextMap(umc_mapcycle, map, group, ChangeMapTime_Now);

    return Plugin_Handled;
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