/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *                              Ultimate Mapchooser - Native Voting                              *
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
#include <sdktools_sound>
#include <umc-core>
#include <umc_utils>
#include <nativevotes>
#include <emitsoundany>

// From core
#define NOTHING_OPTION "?nothing?"

bool vote_active;
NativeVote g_vote;
ConVar cvar_logging;

// Plugin Information
public Plugin myinfo =
{
	name		= "[UMC] Native Voting",
	author		= PL_AUTHOR,
	description = "Extends Ultimate Mapchooser to allow usage of Native Votes.",
	version		= PL_VERSION,
	url			= "http://forums.alliedmods.net/showthread.php?t=134190"
};

public void OnPluginStart()
{
	LoadTranslations("ultimate-mapchooser.phrases");
}

//
public void OnAllPluginsLoaded()
{
	cvar_logging = FindConVar("sm_umc_logging_verbose");

	if (LibraryExists("nativevotes") && NativeVotes_IsVoteTypeSupported(NativeVotesType_NextLevelMult))
	{
		UMC_RegisterVoteManager("core", VM_MapVote, VM_GroupVote, VM_CancelVote);
	}
}

//
public void OnPluginEnd()
{
	UMC_UnregisterVoteManager("core");
}

//************************************************************************************************//
//                                        CORE VOTE MANAGER                                       //
//************************************************************************************************//
public bool VM_IsVoteInProgress()
{
	return NativeVotes_IsVoteInProgress();
}

//
public Action VM_MapVote(int duration, ArrayList vote_items, const int[] clients, int numClients, const char[] startSound)
{
	if (VM_IsVoteInProgress())
	{
		LogUMCMessage("Could not start core vote, another NativeVotes vote is already in progress.");
		return Plugin_Stop;
	}

	bool verboseLogs = (cvar_logging != null && cvar_logging.BoolValue);

	int	 clientArr[MAXPLAYERS + 1];
	int	 count = 0;
	int	 client;
	for (int i = 0; i < numClients; i++)
	{
		client = clients[i];
		if (client != 0 && IsClientInGame(client))
		{
			if (verboseLogs)
			{
				LogUMCMessage("%i: %N (%i)", i, client, client);
			}
			clientArr[count++] = client;
		}
	}

	if (count == 0)
	{
		LogUMCMessage("Could not start core vote, no players to display vote to!");
		return Plugin_Stop;
	}

	// new Handle:menu = BuildVoteMenu(vote_items, "Map Vote Menu Title", Handle_MapVoteResults);
	// g_menu = BuildVoteMenu(vote_items, Handle_MapVoteResults);
	g_vote = BuildVoteMenu(vote_items, Handle_MapVoteResults, NativeVotesType_NextLevelMult);

	vote_active = true;

	if (g_vote != null && NativeVotes_Display(g_vote, clientArr, count, duration))
	{
		if (strlen(startSound) > 0)
		{
			EmitSoundToAllAny(startSound);
		}
		return Plugin_Continue;
	}

	vote_active = false;

	// ClearVoteArrays();
	LogError("Could not start native vote.");
	return Plugin_Stop;
}

public Action VM_GroupVote(int duration, ArrayList vote_items, const int[] clients, int numClients, const char[] startSound)
{
	if (VM_IsVoteInProgress())
	{
		LogUMCMessage("Could not start core vote, another NativeVotes vote is already in progress.");
		return Plugin_Stop;
	}

	bool verboseLogs = (cvar_logging != null && cvar_logging.BoolValue);

	int	 clientArr[MAXPLAYERS + 1];
	int	 count = 0;
	int	 client;
	for (int i = 0; i < numClients; i++)
	{
		client = clients[i];
		if (client != 0 && IsClientInGame(client))
		{
			if (verboseLogs)
			{
				LogUMCMessage("%i: %N (%i)", i, client, client);
			}
			clientArr[count++] = client;
		}
	}

	if (count == 0)
	{
		LogUMCMessage("Could not start core vote, no players to display vote to!");
		return Plugin_Stop;
	}

	// new Handle:menu = BuildVoteMenu(vote_items, "Map Vote Menu Title", Handle_MapVoteResults);
	g_vote = BuildVoteMenu(vote_items, Handle_MapVoteResults, NativeVotesType_Custom_Mult, "Group Vote Menu Title");

	vote_active = true;

	if (g_vote != null && NativeVotes_Display(g_vote, clientArr, count, duration))
	{
		if (strlen(startSound) > 0)
		{
			EmitSoundToAllAny(startSound);
		}
		return Plugin_Continue;
	}

	vote_active = false;

	// ClearVoteArrays();
	LogError("Could not start native vote.");
	return Plugin_Stop;
}

//
NativeVote BuildVoteMenu(ArrayList vote_items, NativeVotes_VoteHandler callback, NativeVotesType type, const char[] title = "")
{
	bool verboseLogs = (cvar_logging != null && cvar_logging.BoolValue);

	if (verboseLogs)
	{
		LogUMCMessage("VOTE MENU:");
	}

	int size = GetArraySize(vote_items);
	if (size <= 1)
	{
		DEBUG_MESSAGE("Not enough items in the vote. Aborting.")
		LogError("VOTING: Not enough maps to run a map vote. %i maps available.", size);
		return null;
	}

	// Begin creating menu
	NativeVote menu = NativeVotes_Create(Handle_VoteMenu, type, NATIVEVOTES_ACTIONS_DEFAULT | MenuAction_VoteCancel | MenuAction_Display | MenuAction_DisplayItem);

	if (title[0] != '\0')
	{
		NativeVotes_SetTitle(menu, title);
		// NativeVotes_SetDetails(menu, "Group Vote Menu Title");
	}

	NativeVotes_SetResultCallback(menu, callback);	  // Set callback

	StringMap voteItem;
	char info[MAP_LENGTH], display[MAP_LENGTH];
	for (int i = 0; i < size; i++)
	{
		voteItem = vote_items.Get(i);
		GetTrieString(voteItem, "info", info, sizeof(info));
		GetTrieString(voteItem, "display", display, sizeof(display));

		NativeVotes_AddItem(menu, info, display);

		if (verboseLogs)
		{
			LogUMCMessage("%i: %s (%s)", i + 1, display, info);
		}
	}

	return menu;	// Return the finished menu.
}

//
public void VM_CancelVote()
{
	if (vote_active)
	{
		vote_active = false;
		NativeVotes_Cancel();
	}
}

// Called when a vote has finished.
public int Handle_VoteMenu(NativeVote vote, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (cvar_logging != null && cvar_logging.BoolValue)
			{
				LogUMCMessage("%L selected menu item %i", param1, param2);
			}

			// TODO
			UMC_VoteManagerClientVoted("core", param1, null);
		}
		case MenuAction_Display:
		{
			NativeVotesType type = NativeVotes_GetType(vote);
			if (type == NativeVotesType_Custom_Mult)
			{
				char phrase[255];
				NativeVotes_GetTitle(vote, phrase, sizeof(phrase));

				char buffer[255];
				FormatEx(buffer, sizeof(buffer), "%T", phrase, param1);

				NativeVotes_RedrawVoteTitle(buffer);
				return 1;
			}
		}
		case MenuAction_VoteCancel:
		{
			switch (param1)
			{
				case VoteCancel_Generic:
				{
					NativeVotes_DisplayFail(g_vote, NativeVotesFail_Generic);
				}
				case VoteCancel_NoVotes:
				{
					NativeVotes_DisplayFail(g_vote, NativeVotesFail_NotEnoughVotes);
				}
			}
			if (vote_active)
			{
				DEBUG_MESSAGE("Vote Cancelled")
				vote_active = false;
				UMC_VoteManagerVoteCancelled("core");
			}
		}
		case MenuAction_End:
		{
			DEBUG_MESSAGE("MenuAction_End")
			NativeVotes_Close(vote);
		}
		case MenuAction_DisplayItem:
		{
			char map[MAP_LENGTH], display[MAP_LENGTH];
			NativeVotes_GetItem(vote, param2, map, MAP_LENGTH, display, MAP_LENGTH);

			if (StrEqual(map, EXTEND_MAP_OPTION) || StrEqual(map, DONT_CHANGE_OPTION) || (StrEqual(map, NOTHING_OPTION) && strlen(display) > 0))
			{
				char buffer[255];
				FormatEx(buffer, sizeof(buffer), "%T", display, param1);

				NativeVotes_RedrawVoteItem(buffer);
				return 1;
			}
		}
	}
	return 0;
}

// Handles the results of a vote.
public void Handle_MapVoteResults(NativeVote vote, int num_votes, int num_clients, const int[] client_indexes, const int[] client_votes, int num_items, const int[] item_indexes, const int[] item_votes)
{
	ArrayList results = ConvertVoteResults(vote, num_clients, client_indexes, client_votes, num_items, item_indexes);

	UMC_VoteManagerVoteCompleted("core", results, Handle_UMCVoteResponse);

	// Free Memory
	int		  size = GetArraySize(results);
	StringMap item;
	ArrayList clients;
	for (int i = 0; i < size; i++)
	{
		item = GetArrayCell(results, i);
		GetTrieValue(item, "clients", clients);
		CloseHandle(clients);
		CloseHandle(item);
	}
	CloseHandle(results);
}

// Converts results of a vote to the format required for UMC to process votes.
ArrayList ConvertVoteResults(NativeVote vote, int num_clients, const int[] client_indexes, const int[] client_votes, int num_items, const int[] item_indexes)
{
	ArrayList result = new ArrayList();
	int		  itemIndex;
	StringMap voteItem;
	ArrayList voteClientArray;
	char	  info[MAP_LENGTH], disp[MAP_LENGTH];
	for (int i = 0; i < num_items; i++)
	{
		itemIndex = item_indexes[i];
		NativeVotes_GetItem(vote, itemIndex, info, sizeof(info), disp, sizeof(disp));

		voteItem		= new StringMap();
		voteClientArray = new ArrayList();

		SetTrieString(voteItem, "info", info);
		SetTrieString(voteItem, "display", disp);
		SetTrieValue(voteItem, "clients", voteClientArray);

		result.Push(voteItem);

		for (int j = 0; j < num_clients; j++)
		{
			if (client_votes[j] == itemIndex)
			{
				voteClientArray.Push(client_indexes[j]);
			}
		}
	}
	return result;
}

public void Handle_UMCVoteResponse(UMC_VoteResponse response, const char[] param)
{
	switch (response)
	{
		case VoteResponse_Success:
		{
			if (StrEqual(param, EXTEND_MAP_OPTION))
			{
				NativeVotes_DisplayPassEx(g_vote, NativeVotesPass_Extend);
			}
			else if (StrEqual(param, DONT_CHANGE_OPTION))
			{
				NativeVotes_DisplayPassCustom(g_vote, "%t", "Map Unchanged");
			}
			else
			{
				char map[MAP_LENGTH];
				strcopy(map, sizeof(map), param);
				if (NativeVotes_GetType(g_vote) == NativeVotesType_Custom_Mult)
				{
					// NativeVotes_DisplayPassEx(g_menu, NativeVotesPass_NextLevel, map);
					NativeVotes_DisplayPassCustom(g_vote, "%t", map);
				}
				else
				{
					NativeVotes_DisplayPass(g_vote, map);
				}
			}
		}
		case VoteResponse_Runoff:
		{
			NativeVotes_DisplayFail(g_vote, NativeVotesFail_NotEnoughVotes);
		}
		case VoteResponse_Tiered:
		{
			char map[MAP_LENGTH];
			strcopy(map, sizeof(map), param);
			// NativeVotes_DisplayPass(g_menu, map);
			NativeVotes_DisplayPassCustom(g_vote, "%t", map);
		}
		case VoteResponse_Fail:
		{
			NativeVotes_DisplayFail(g_vote, NativeVotesFail_NotEnoughVotes);
		}
	}
}
