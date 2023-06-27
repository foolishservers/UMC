/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *                          Ultimate Mapchooser - Post-Played Exclusion                          *
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

public Plugin myinfo =
{
	name		= "[UMC] Post-Played Exclusion",
	author		= "Sandy",
	description = "Allows users to specify an amount of time after a map is played that it should be excluded.",
	version		= PL_VERSION,
	url			= "http://forums.alliedmods.net/showthread.php?t=134190"
}

#define POSTEX_KEY_MAP		 "allow_every"
#define POSTEX_KEY_DEFAULT	 "default_allow_every"
#define POSTEX_KEY_GROUP	 "group_allow_every"
#define POSTEX_DEFAULT_VALUE 0

ConVar cvar_nom_ignore;
ConVar cvar_display_ignore;

StringMap time_played_trie;
StringMap time_played_groups_trie;

int time_penalty;

public void OnPluginStart()
{
	cvar_nom_ignore = CreateConVar(
		"sm_umc_postex_ignorenominations",
		"0",
		"Determines if nominations are exempt from being excluded due to Post-Played Exclusion.",
		0, true, 0.0, true, 1.0);

	cvar_display_ignore = CreateConVar(
		"sm_umc_postex_ignoredisplay",
		"0",
		"Determines if maps being displayed are exempt from being excluded due to Post-Played Exclusion.",
		0, true, 0.0, true, 1.0);

	AutoExecConfig(true, "umc-postexclude");

	time_played_trie		= new StringMap();
	time_played_groups_trie = new StringMap();
}

public void OnConfigsExecuted()
{
	char map[MAP_LENGTH], group[MAP_LENGTH];
	GetCurrentMap(map, sizeof(map));
	UMC_GetCurrentMapGroup(group, sizeof(group));

	StringMap groupMaps;
	if (!GetTrieValue(time_played_trie, group, groupMaps))
	{
		groupMaps = new StringMap();
		SetTrieValue(time_played_trie, group, groupMaps);
	}
	SetTrieValue(groupMaps, map, GetTime());
	SetTrieValue(time_played_groups_trie, group, GetTime() - time_penalty);

	time_penalty = 0;
}

bool IsMapStillDelayed(const char[] map, const char[] group, int minsDelayedMap, int minsDelayedGroup)
{
	StringMap groupMaps;
	if (!GetTrieValue(time_played_trie, group, groupMaps))
	{
		return false;
	}

	int	 timePlayedMap;
	char resolvedMap[MAP_LENGTH];

	FindMap(map, resolvedMap, sizeof(resolvedMap));

	if (!GetTrieValue(groupMaps, resolvedMap, timePlayedMap))
	{
		return false;
	}

	int minsSinceMapPlayed = GetTime() - timePlayedMap / 60;

	int timePlayedGroup;
	if (!GetTrieValue(time_played_groups_trie, group, timePlayedGroup))
	{
		return false;
	}

	int minsSinceGroupPlayed = GetTime() - timePlayedGroup / 60;

	if (timePlayedMap == timePlayedGroup)
	{
		if (minsDelayedMap < minsDelayedGroup)
		{
			return minsSinceMapPlayed <= minsDelayedMap;
		}
	}
	return minsSinceMapPlayed <= minsDelayedMap || minsSinceGroupPlayed <= minsDelayedGroup;
}

// Called when UMC wants to know if this map is excluded
public Action UMC_OnDetermineMapExclude(KeyValues kv, const char[] map, const char[] group, bool isNomination, bool forMapChange)
{
	if (isNomination && cvar_nom_ignore.BoolValue)
	{
		return Plugin_Continue;
	}

	if (!forMapChange && cvar_display_ignore.BoolValue)
	{
		return Plugin_Continue;
	}

	if (kv == null)
	{
		return Plugin_Continue;
	}

	int def, val, gDef;
	kv.Rewind();
	if (kv.JumpToKey(group))
	{
		gDef = kv.GetNum(POSTEX_KEY_GROUP, POSTEX_DEFAULT_VALUE);
		def	 = kv.GetNum(POSTEX_KEY_DEFAULT, POSTEX_DEFAULT_VALUE);

		if (kv.JumpToKey(map))
		{
			val = kv.GetNum(POSTEX_KEY_MAP, def);
			kv.GoBack();
		}
		else
		{
			val = def;
		}
		kv.GoBack();
	}

	if (IsMapStillDelayed(map, group, val, gDef))
	{
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

// Called when UMC has set the next map
public void UMC_OnNextmapSet(KeyValues kv, const char[] map, const char[] group, const char[] display)
{
	if (kv == null)
	{
		return;
	}

	int gDef, gVal;

	kv.Rewind();
	if (kv.JumpToKey(group))
	{
		gDef = kv.GetNum(POSTEX_KEY_GROUP, POSTEX_DEFAULT_VALUE);

		if (kv.JumpToKey(map))
		{
			gVal = kv.GetNum(POSTEX_KEY_GROUP, gDef);
			kv.GoBack();
		}
		else
		{
			gVal = gDef;
		}
		kv.GoBack();
	}

	int penalty	 = (gDef - gVal) * 60;
	time_penalty = penalty > 0 ? penalty : 0;
}
