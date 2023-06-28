/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *                               Ultimate Mapchooser - Time Limits                               *
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
	name		= "[UMC] Time Limits",
	author		= PL_AUTHOR,
	description = "Allows users to specify time limits for maps.",
	version		= PL_VERSION,
	url			= "http://forums.alliedmods.net/showthread.php?t=134190"
}

#define TIMELIMIT_KEY_MAP_MIN	"min_time"
#define TIMELIMIT_KEY_MAP_MAX	"max_time"
#define TIMELIMIT_KEY_GROUP_MIN "default_min_time"
#define TIMELIMIT_KEY_GROUP_MAX "default_max_time"

#define DEFAULT_MIN				0
#define DEFAULT_MAX				2359

ConVar cvar_nom_ignore;
ConVar cvar_display_ignore;

public void OnPluginStart()
{
	cvar_nom_ignore = CreateConVar(
		"sm_umc_timelimits_ignorenominations",
		"0",
		"Determines if nominations are exempt from being excluded due to Time Limits.",
		0, true, 0.0, true, 1.0);

	cvar_display_ignore = CreateConVar(
		"sm_umc_timelimits_ignoredisplay",
		"0",
		"Determines if maps being displayed are exempt from being excluded due to Time Limits.",
		0, true, 0.0, true, 1.0);

	AutoExecConfig(true, "umc-timelimits");
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

	int defaultMin, defaultMax;
	int min, max;

	kv.Rewind();
	if (kv.JumpToKey(group))
	{
		defaultMin = kv.GetNum(TIMELIMIT_KEY_GROUP_MIN, DEFAULT_MIN);
		defaultMax = kv.GetNum(TIMELIMIT_KEY_GROUP_MAX, DEFAULT_MAX);

		if (kv.JumpToKey(map))
		{
			min = kv.GetNum(TIMELIMIT_KEY_MAP_MIN, defaultMin);
			max = kv.GetNum(TIMELIMIT_KEY_MAP_MAX, defaultMax);
			kv.GoBack();
		}
		kv.GoBack();
	}

	if (IsTimeBetween(min, max))
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
		defaultMin = kv.GetNum(TIMELIMIT_KEY_GROUP_MIN, DEFAULT_MIN);
		defaultMax = kv.GetNum(TIMELIMIT_KEY_GROUP_MAX, DEFAULT_MAX);

		if (kv.JumpToKey(map))
		{
			min = kv.GetNum(TIMELIMIT_KEY_MAP_MIN, defaultMin);
			max = kv.GetNum(TIMELIMIT_KEY_MAP_MAX, defaultMax);
			kv.GoBack();
		}
		kv.GoBack();
	}

	char minString[3], maxString[3];
	TL_FormatTime(minString, sizeof(minString), min);
	TL_FormatTime(maxString, sizeof(maxString), max);

	char minSearch[20], maxSearch[20];
	Format(minSearch, sizeof(minSearch), "{%s}", TIMELIMIT_KEY_MAP_MIN);
	Format(maxSearch, sizeof(maxSearch), "{%s}", TIMELIMIT_KEY_MAP_MAX);

	ReplaceString(template, maxlen, minSearch, minString, false);
	ReplaceString(template, maxlen, maxSearch, maxString, false);
}

stock void TL_FormatTime(char[] buffer, int maxlen, int time)
{
	int hours	= time / 100;
	int minutes = time % 100;

	Format(buffer, maxlen, "%02i:%02i", hours, minutes);
}