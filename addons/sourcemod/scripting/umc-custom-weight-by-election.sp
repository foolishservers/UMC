#pragma semicolon 1

#include <sourcemod>
#include <umc-core>
#include <umc_utils>

#pragma newdecls required

bool db_createTableSuccess = false;

char db_createTable[] = "CREATE TABLE IF NOT EXISTS `umc_weight` (`map` VARCHAR(256) PRIMARY KEY, `weight` INT NOT NULL);";
char db_insertRow[] = "INSERT IGNORE INTO `umc_weight` (`map`, `weight`) VALUES ('%s', 0);";
char db_selectRow[] = "SELECT `weight` FROM `umc_weight` WHERE `map` = '%s' LIMIT 1;";
char db_updateRow[] = "UPDATE `umc_weight` SET `weight` = %d WHERE `map` = '%s';";

ConVar g_cvarPointAdd;
int g_iPointAdd = 3;

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
	LoadTranslations("common.phrases");

	g_cvarPointAdd = CreateConVar("umcc_pointadd", "3", "", _, true, 1.0);

	g_cvarPointAdd.AddChangeHook(CVC_PointAdd);
}

Database connect2DB()
{
	char error[255];
	Database db;
	
	if(SQL_CheckConfig("umc_weight"))
	{
		db = SQL_Connect("umc_weight", true, error, sizeof(error));
	}
	else
	{
		db = SQL_Connect("default", true, error, sizeof(error));
	}
	
	if(db == null)
	{
		LogError("Could not connect to database: %s", error);
	}

	if(!db_createTableSuccess && !SQL_FastQuery(db, db_createTable))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);
	}

	db_createTableSuccess = true;
	
	return db;
}

public int UMC_OnReweightMap(Handle kv, const char[] map, const char[] group)
{
	Database db = connect2DB();
	if(db == null)
	{
		return 0;
	}

	int point = 0;

	char error[255];

	int escapedMapNameLength = strlen(map) * 2 + 1;
	char[] escapedMapName = new char[escapedMapNameLength];
	db.Escape(map, escapedMapName, escapedMapNameLength);

	{
		int queryStatementLength = sizeof(db_insertRow) + strlen(escapedMapName);
		char[] queryStatement = new char[queryStatementLength];
		Format(queryStatement, queryStatementLength, db_insertRow, escapedMapName);

		if(!SQL_FastQuery(db, queryStatement))
		{
			SQL_GetError(db, error, sizeof(error));
			LogError("Could not query to database: %s", error);

			return 0;
		}
	}

	{
		DBResultSet hQuery;

		int queryStatementLength = sizeof(db_selectRow) + strlen(escapedMapName);
		char[] queryStatement = new char[queryStatementLength];
		Format(queryStatement, queryStatementLength, db_selectRow, escapedMapName);

		if((hQuery = SQL_Query(db, queryStatement)) == null)
		{
			SQL_GetError(db, error, sizeof(error));
			LogError("Could not query to database: %s", error);

			return 0;
		}

		if(SQL_FetchRow(hQuery))
		{
			point = SQL_FetchInt(hQuery, 0);
		}

		delete hQuery;
	}
	
	UMC_AddWeightModifier(1 + (point * 0.1));
	point += g_iPointAdd;
	
	{
		int queryStatementLength = sizeof(db_updateRow) + strlen(escapedMapName) + 11;
		char[] queryStatement = new char[queryStatementLength];
		Format(queryStatement, queryStatementLength, db_updateRow, point, escapedMapName);

		if(!SQL_FastQuery(db, queryStatement))
		{
			SQL_GetError(db, error, sizeof(error));
			LogError("Could not query to database: %s", error);

			return 0;
		}
	}

	delete db;
	
	return 0;
}

public void OnMapEnd()
{
	Database db = connect2DB();
	if(db == null)
	{
		return;
	}

	char nextmap[PLATFORM_MAX_PATH];
	GetNextMap(nextmap, sizeof(nextmap));
	
	char error[255];

	int escapedMapNameLength = strlen(nextmap) * 2 + 1;
	char[] escapedMapName = new char[escapedMapNameLength];
	db.Escape(nextmap, escapedMapName, escapedMapNameLength);

	{
		int queryStatementLength = sizeof(db_insertRow) + strlen(escapedMapName);
		char[] queryStatement = new char[queryStatementLength];
		Format(queryStatement, queryStatementLength, db_insertRow, escapedMapName);

		if(!SQL_FastQuery(db, queryStatement))
		{
			SQL_GetError(db, error, sizeof(error));
			LogError("Could not query to database: %s", error);

			return;
		}
	}

	{
		int queryStatementLength = sizeof(db_updateRow) + strlen(escapedMapName) + 11;
		char[] queryStatement = new char[queryStatementLength];
		Format(queryStatement, queryStatementLength, db_updateRow, 0, escapedMapName);

		if(!SQL_FastQuery(db, queryStatement))
		{
			SQL_GetError(db, error, sizeof(error));
			LogError("Could not query to database: %s", error);

			return;
		}
	}

	delete db;
}

public void CVC_PointAdd(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_iPointAdd = StringToInt(newValue);
}