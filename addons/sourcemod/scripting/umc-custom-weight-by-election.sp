#pragma semicolon 1

#include <sourcemod>
#include <umc-core>
#include <umc_utils>

#pragma newdecls required

Handle g_sqlMain;
Handle g_hMapTable;

ConVar g_cvarPointAdd;
ConVar g_cvarPointSub;
int g_iPointAdd = 3;
int g_iPointSub = 6;

public Plugin myinfo =
{
	name = "[UMC Custom] Weight by election",
	author = "Yuumi-Peusah, Foolish, Jobggun",
	description = "For Foolish server",
	version = "1.0",
	url = ""
};

public void OnPluginStart()
{
	g_cvarPointAdd = CreateConVar("umcc_pointadd", "3", "", _, true, 1.0);
	g_cvarPointSub = CreateConVar("umcc_pointsum", "6", "", _, true, 1.0);
	g_cvarPointAdd.AddChangeHook(CVC_PointAdd);
	g_cvarPointSub.AddChangeHook(CVC_PointSum);
	
	HookEvent("tf_game_over", OnGameOver);
}

public int UMC_OnReweightMap(Handle kv, const char[] map, const char[] group)
{
	int point;
	
	// fetch point by map, create data if not exist ...
	//point = fetched_value;
	
	UMC_AddWeightModifier(1 + (point * 0.1));
	point += g_iPointAdd;
	
	// save point to sql
	
	//return 0;
}

public void OnGameOver(Event event, const char[] name, bool dontBroadcast)
{
	char nextmap[48];
	GetNextMap(nextmap, sizeof(nextmap));
	
	int fetched_point; // fetch point from sql
	fetched_point -= g_iPointSub;
}

public void CVC_PointAdd(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_iPointAdd = StringToInt(newValue);
}

public void CVC_PointSum(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_iPointSub = StringToInt(newValue);
}