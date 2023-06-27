/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *                                Ultimate Mapchooser - Map Weight                               *
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

public Plugin myinfo =
{
	name		= "[UMC] Map Weight",
	author		= "Sandy",
	description = "Allows users to specify weights for maps and groups, making them more or less likely to be picked randomly.",
	version		= PL_VERSION,
	url			= "http://forums.alliedmods.net/showthread.php?t=134190"
}

#define WEIGHT_KEY_MAP	 "weight"
#define WEIGHT_KEY_GROUP "group_weight"

// Excludes maps with a set weight of 0
public Action UMC_OnDetermineMapExclude(KeyValues kv, const char[] map, const char[] group, bool isNomination, bool forMapChange)
{
	if (kv == null)
	{
		return Plugin_Continue;
	}

	kv.Rewind();

	if (kv.JumpToKey(group))
	{
		if (kv.JumpToKey(map))
		{
			if (kv.GetFloat(WEIGHT_KEY_MAP, 1.0) == 0.0)
			{
				kv.GoBack();
				kv.GoBack();
				return Plugin_Stop;
			}
			kv.GoBack();
		}
		kv.GoBack();
	}
	return Plugin_Continue;
}

// Reweights a map when UMC requests.
public void UMC_OnReweightMap(KeyValues kv, const char[] map, const char[] group)
{
	if (kv == null)
	{
		return;
	}

	kv.Rewind();
	if (kv.JumpToKey(group))
	{
		if (kv.JumpToKey(map))
		{
			UMC_AddWeightModifier(kv.GetFloat(WEIGHT_KEY_MAP, 1.0));
			kv.GoBack();
		}
		kv.GoBack();
	}
}

// Reweights a group when UMC requests.
public void UMC_OnReweightGroup(KeyValues kv, const char[] group)
{
	if (kv == null)
	{
		return;
	}

	kv.Rewind();
	if (kv.JumpToKey(group))
	{
		UMC_AddWeightModifier(kv.GetFloat(WEIGHT_KEY_GROUP, 1.0));
		kv.GoBack();
	}
}