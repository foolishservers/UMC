/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *                              Ultimate Mapchooser - Player Limits                              *
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
#include <umc-playerlimits>

public Plugin myinfo =
{
	name		= "[UMC] Player Limits",
	author		= PL_AUTHOR,
	description = "Allows users to specify player limits for maps.",
	version		= PL_VERSION,
	url			= "http://forums.alliedmods.net/showthread.php?t=134190"
}

ConVar cvar_nom_ignore;
ConVar cvar_display_ignore;

public void OnPluginStart()
{
	cvar_nom_ignore = CreateConVar(
		"sm_umc_playerlimits_nominations",
		"0",
		"Determines if nominations are exempt from being excluded due to Player Limits.",
		0, true, 0.0, true, 1.0);

	cvar_display_ignore = CreateConVar(
		"sm_umc_playerlimits_display",
		"0",
		"Determines if maps being displayed are exempt from being excluded due to Player Limits.",
		0, true, 0.0, true, 1.0);

	AutoExecConfig(true, "umc-playerlimits");
}

// Called when UMC wants to know if this map is excluded
public Action UMC_OnDetermineMapExclude(KeyValues kv, const char[] map, const char[] group, bool isNomination, bool forMapChange)
{
	if (isNomination && GetConVarBool(cvar_nom_ignore))
	{
		return Plugin_Continue;
	}

	if (!forMapChange && GetConVarBool(cvar_display_ignore))
	{
		return Plugin_Continue;
	}

	if (kv == null)
	{
		return Plugin_Continue;
	}

	int defaultMin, defaultMax;
	int min, max;

	kv.Rewind();
	if (kv.JumpToKey(group))
	{
		defaultMin = kv.GetNum(PLAYERLIMIT_KEY_GROUP_MIN, 0);
		defaultMax = kv.GetNum(PLAYERLIMIT_KEY_GROUP_MAX, MaxClients);

		if (kv.JumpToKey(map))
		{
			min = kv.GetNum(PLAYERLIMIT_KEY_MAP_MIN, defaultMin);
			max = kv.GetNum(PLAYERLIMIT_KEY_MAP_MAX, defaultMax);
			kv.GoBack();
		}
		kv.GoBack();
	}

	if (IsPlayerCountBetween(min, max))
	{
		return Plugin_Continue;
	}

	return Plugin_Stop;
}

// Display Template
public void UMC_OnFormatTemplateString(char[] template, int maxlen, KeyValues kv, const char[] map, const char[] group)
{
	int defaultMin, defaultMax;
	int min, max;

	kv.Rewind();
	if (kv.JumpToKey(group))
	{
		defaultMin = kv.GetNum(PLAYERLIMIT_KEY_GROUP_MIN, 0);
		defaultMax = kv.GetNum(PLAYERLIMIT_KEY_GROUP_MAX, MaxClients);

		if (kv.JumpToKey(map))
		{
			min = kv.GetNum(PLAYERLIMIT_KEY_MAP_MIN, defaultMin);
			max = kv.GetNum(PLAYERLIMIT_KEY_MAP_MAX, defaultMax);
			kv.GoBack();
		}
		kv.GoBack();
	}

	char minString[3], maxString[3];
	Format(minString, sizeof(minString), "%d", min);
	Format(maxString, sizeof(maxString), "%d", max);

	char minSearch[12], maxSearch[12];
	Format(minSearch, sizeof(minSearch), "{%s}", PLAYERLIMIT_KEY_MAP_MIN);
	Format(maxSearch, sizeof(maxSearch), "{%s}", PLAYERLIMIT_KEY_MAP_MAX);

	ReplaceString(template, maxlen, minSearch, minString, false);
	ReplaceString(template, maxlen, maxSearch, maxString, false);
}