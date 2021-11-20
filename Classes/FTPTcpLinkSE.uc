// complete copy-paste job, because "somebody" *cough*cough* uses word "final" too much :(
Class FTPTcpLinkSE extends TcpLink;

var string TempFileName;
var array<ServerStStats> PendingLoaders;
var array<StatsObject> ToSave;
var ServerPerksMutSE Mut;
var IpAddr SiteAddress;
var FTPUploadDataConnection UploadDataConnection;
var FTPDownloadDataConnection DownloadDataConnection;
var transient float WelcomeTimer;
var array<string> TotalList;
var byte RetryCounter;
var bool bConnectionBroken,bUploadAllStats,bTotalUpload,bFileInProgress,bPostUploadCheck,bIsAsciiMode;
var bool bFullVerbose,bLogAllCommands;
var protected transient bool bCheckedWeb;
var protected transient PlayerController WebAdmin;

function BeginEvent()
{
	Mut.SaveAllStats = SaveAllStats;
	Mut.RequestStats = RequestStats;
	if( Mut.bDebugDatabase ) {
		bLogAllCommands = true;
		bFullVerbose = Mut.bBroadcastFTPDebug;
	}

	LinkMode = MODE_Line;
	ReceiveMode = RMODE_Event;
	Resolve(Mut.RemoteDatabaseURL);
}

function Destroyed()
{
    if ( UploadDataConnection != none )
        UploadDataConnection.Destroy();
    if ( DownloadDataConnection != none )
        DownloadDataConnection.Destroy();
    super.Destroyed();
}

function CheckWebAdmin()
{
    local MessagingSpectator MS;

    bCheckedWeb = true;
    if ( Level.NetMode == NM_Standalone )
        WebAdmin = Level.GetLocalPlayerController();
    else {
        foreach AllActors(class'MessagingSpectator',MS) {
            WebAdmin = MS;
            break;
        }
    }
}

function DebugLog( string Str )
{
	if( !bCheckedWeb )
        CheckWebAdmin();

	if( WebAdmin!=None )
		WebAdmin.ClientMessage(Str,'FTP');
	Log(Str,'FTP');
}

function DebugMessage(string Msg, optional bool bError)
{
    local Controller C;
    local PlayerController PC;

    if ( bFullVerbose || (bError && Mut.bBroadcastFTPErrors) ) {
        for ( C = Level.ControllerList; C != none; C = C.nextController ) {
            PC = PlayerController(C);
            if ( PC != none && (!Mut.bBroadcastToAdminsOnly || (PC.PlayerReplicationInfo != none && PC.PlayerReplicationInfo.bAdmin)) )
                PC.ClientMessage(Msg,'FTP');
        }
    }
}


function ReportError( int Code, string InEr )
{
	if( !bConnectionBroken ) {
        DebugMessage(Code$" FTP Error: "$InEr, true);
        DebugLog(Code$" FTP Error: "$InEr);
	}
	bConnectionBroken = true;
	GoToState('ErrorState');
}
event Resolved( IpAddr Addr )
{
	SiteAddress = Addr;
	SiteAddress.Port = Mut.RemotePort;
	GoToState('Idle');
}
event ResolveFailed()
{
	ReportError(0,"Couldn't resolve address, aborting...");
}
event Closed()
{
	ReportError(1,"Connection was closed by FTP server!");
}

event ReceivedLine( string Text )
{
	if( bLogAllCommands )
		DebugLog("IN  "$GetStateName()$": "$Text);
	ProcessResponse(int(Left(Text,3)),Mid(Text,4));
}
function SendFTPLine( string Text, optional bool bNoLog )
{
	if( bLogAllCommands && !bNoLog )
		DebugLog("OUT "$GetStateName()$": "$Text);
	SendText(Text);
}

function SaveAllStats()
{
	local int i;

	if( bTotalUpload )
		return;
	ToSave = Mut.ActiveStats;
	for( i=0; i<ToSave.Length; ++i )
	{
		if( !ToSave[i].bStatsChanged )
			ToSave.Remove(i--,1);
	}
	if( ToSave.Length>0 )
		bUploadAllStats = true;
}
function RequestStats( ServerStStats Other )
{
	local int i;

	if( bTotalUpload )
		return;
	for( i=0; i<PendingLoaders.Length; ++i )
	{
		if( PendingLoaders[i]==None )
			PendingLoaders.Remove(i--,1);
		else if( PendingLoaders[i]==Other )
			return;
	}
	PendingLoaders[PendingLoaders.Length] = Other;
}
function FullUpload()
{
	TotalList = GetPerObjectNames("ServerPerksStat","StatsObject",9999999);
	bTotalUpload = true;
	bUploadAllStats = true;
	bFullVerbose = true;
	HasMoreStats();
	SaveAllStats();
}
function bool HasMoreStats()
{
	local byte i;
	local int j;

	if( TotalList.Length==0 )
		return false;
	j = ToSave.Length;
	for( i=0; i<Min(20,TotalList.Length); ++i )
	{
		ToSave.Length = j+1;
		ToSave[j] = new(None,TotalList[i]) Class'StatsObject';
		++j;
	}
	TotalList.Remove(0,20);
	return true;
}
function CheckNextCommand()
{
	while( PendingLoaders.Length>0 && PendingLoaders[0]==None )
		PendingLoaders.Remove(0,1);

	if( bUploadAllStats || (bTotalUpload && HasMoreStats()) )
		GoToState('UploadStats','Begin');
	else if( PendingLoaders.Length>0 )
		GoToState('DownloadStats','Begin');
	else
	{
		if( bFullVerbose )
			DebugMessage("FTP: All done!");
		if( Mut.FTPKeepAliveSec>0 && !Level.Game.bGameEnded )
			GoToState('KeepAlive');
		else
            GoToState('EndConnection');
	}
}
function ProcessResponse( int Code, string Line )
{
	switch( Code )
	{
	case 220: // Welcome
		if( WelcomeTimer<Level.TimeSeconds )
		{
			SendFTPLine("USER "$Mut.RemoteFTPUser, true);
			WelcomeTimer = Level.TimeSeconds+0.2;
		}
		break;
	case 331: // Password required
		SendFTPLine("PASS "$Mut.RemotePassword, true);
		break;
	case 230: // User logged in.
		if( Mut.RemoteFTPDir!="" )
			SendFTPLine("CWD "$Mut.RemoteFTPDir);
		else
		{
			SendFTPLine("TYPE A");
			bIsAsciiMode = true;
		}
		break;
	case 250: // CWD command successful.
		SendFTPLine("TYPE A");
		bIsAsciiMode = true;
		break;
	case 200: // Type set to A
		CheckNextCommand();
		break;
	case 226: // File successfully transferred
	case 125: // Data connection already open; Transfer starting.
	case 150: // Opening ASCII mode data connection
		break;
	case 421: // No transfer timeout: closing control connection
		if( bFullVerbose )
			DebugMessage("FTP: Connection timed out, reconnecting!");
		GoToState('EndConnection');
		break;
	case 221: // Good-bye
		Close();
		break;
	default:
		if( bFullVerbose )
			DebugMessage("FTP: Unknown FTP code '"$Code$"': "$Line);
		Log("Unknown FTP code '"$Code$"': "$Line,Class.Name);
	}
}
function DataReceived();

function Timer()
{
	ReportError(3,"FTP connection timed out!");
}

state Idle
{
Ignores Timer;

	function StartConnection()
	{
		local int i;

		for( i=0; i<40; ++i )
		{
			BindPort(1024+Rand(5000),true);
			if( OpenNoSteam(SiteAddress) )
			{
				GoToState('InitConnection');
				return;
			}
		}
		ReportError(4,"Port couldn't be bound or connection failed to open!");
	}
	function SaveAllStats()
	{
		Global.SaveAllStats();
		if( bUploadAllStats )
			StartConnection();
	}
	function RequestStats( ServerStStats Other )
	{
		Global.RequestStats(Other);
		StartConnection();
	}
Begin:
	Sleep(0.1f);
	if( bUploadAllStats || PendingLoaders.Length>0 )
		StartConnection();
}
state InitConnection
{
	function BeginState()
	{
		SetTimer(10,false);
	}
	event Closed()
	{
		ReportError(5,"Connection was closed by FTP server!");
	}
Begin:
	Sleep(5.f);
	SendFTPLine("USER "$Mut.RemoteFTPUser);
}
state ConnectionBase
{
	event Closed()
	{
		GoToState('Idle');
	}
Begin:
	while( true )
	{
		if( bUploadAllStats && Level.bLevelChange ) // Delay mapchange until all stats are uploaded.
			Level.NextSwitchCountdown = FMax(Level.NextSwitchCountdown,2.f);
		Sleep(0.5);
	}
}
state EndConnection extends ConnectionBase
{
	function BeginState()
	{
		SendFTPLine("QUIT");
		SetTimer(4,false);
	}
}
state KeepAlive extends ConnectionBase
{
Ignores Timer;

	function SaveAllStats()
	{
		Global.SaveAllStats();
		if( bUploadAllStats )
			StartConnection();
	}
	function RequestStats( ServerStStats Other )
	{
		Global.RequestStats(Other);
		StartConnection();
	}
	function StartConnection()
	{
		CheckNextCommand();
	}
Begin:
	while( true )
	{
		if( bUploadAllStats || PendingLoaders.Length>0 )
			StartConnection();
		Sleep(Mut.FTPKeepAliveSec);
		SendFTPLine("NOOP");
	}
}
state UploadStats extends ConnectionBase
{
	function BeginState()
	{
		bUploadAllStats = false;
		SetTimer(10,false);
	}

    function EndState()
    {
        if ( UploadDataConnection!= none )
            UploadDataConnection.Destroy();
    }

	function SaveAllStats();

    function bool OpenDataConnection( string S )
    {
        local int i,j;
        local IpAddr A;


        A = SiteAddress;
        // Get destination port
        S = Mid(S,InStr(S,"(")+1);
        for( i=0; i<4; ++i ) // Skip IP address
            S = Mid(S,InStr(S,",")+1);
        i = InStr(S,",");
        A.Port = int(Left(S,i))*256 + int(Mid(S,i+1));

        // Now attempt to bind port and open connection.
        i = 0;
        for( j=Mut.LastDataPortUsed+1; j!=Mut.LastDataPortUsed && (++i < 100); ++j ) {
            if ( j > Mut.DataPortRangeEnd )
                j = Mut.DataPortRangeStart;
            if( UploadDataConnection!=None )
                UploadDataConnection.Destroy();
            UploadDataConnection = Spawn(Class'FTPUploadDataConnection',Self);
            UploadDataConnection.BindPort(j,false);
            if( UploadDataConnection.OpenNoSteam(A) ) {
                DebugLog("PORT "$j$" bound for upload data connection");
                Mut.LastDataPortUsed = j;
                return true;
            }
        }
        Mut.LastDataPortUsed = j;
        UploadDataConnection.Destroy();
        ReportError(2,"Couldn't bind port for upload data connection!");
        return false;
    }

	function InitDataConnection( string S )
	{
        if ( bFileInProgress ) {
            ReportError(6, "Attempt to make new connection while file is in progress");
            return;
        }

        if( bFullVerbose )
            DebugMessage("FTP: Upload stats for "$ToSave[0].PlayerName$" ("$(ToSave.Length-1+TotalList.Length)$" remains)");

        if( OpenDataConnection(S) ) {
            UploadDataConnection.BufferSize = Mut.BufferSize;
			UploadDataConnection.Data = ToSave[0].GetSaveData();
			TempFileName = ToSave[0].Name$".txt.tmp";
			SendFTPLine("STOR "$TempFileName);
			bFileInProgress = true;
		}
	}

	function NextPackage()
	{
		RetryCounter = 0;
		ToSave[0].bStatsChanged = false;
		ToSave.Remove(0,1);
		if( ToSave.Length==0 )
			CheckNextCommand();
		else if( !bIsAsciiMode )
		{
			bIsAsciiMode = true;
			SendFTPLine("TYPE A");
		}
		else
            SendFTPLine("PASV");
	}
	function ProcessResponse( int Code, string Line )
	{
		switch( Code )
		{
		case 200: // Type set to A/I
			if( bPostUploadCheck )
			{
				SetTimer(5,false);
				SendFTPLine("SIZE "$TempFileName);
			}
			else
                SendFTPLine("PASV");
			break;
		case 227: // Entering passive mode
            InitDataConnection(Line);
			break;
        case 125: // Data connection already open; Transfer starting.
		case 150: // Opening ASCII mode data connection for file
			SetTimer(60,false);
			if( UploadDataConnection!=None )
				UploadDataConnection.BeginUpload();
			break;
		case 226: // File transfer completed.
			if( bFileInProgress )
			{
				SetTimer(5,false);
				bFileInProgress = false;
				bPostUploadCheck = true;
				SendFTPLine("TYPE I");
				bIsAsciiMode = false;
			}
			break;
		case 213: // File size response.
			if( bPostUploadCheck )
			{
				SetTimer(5,false);
				if( int(Line)<=5 )
				{
					bPostUploadCheck = false;
					if( ++RetryCounter>=5 )
						NextPackage();
					else
					{
						DebugMessage("213 FTP Error: Stats upload failed for "$ToSave[0].PlayerName$" retrying...", true);
						SendFTPLine("PASV");
					}
				}
				else SendFTPLine("RNFR "$TempFileName);
			}
			break;
		case 350: // Rename accepted.
			if( bPostUploadCheck )
			{
				SetTimer(5,false);
				SendFTPLine("RNTO "$Left(TempFileName,Len(TempFileName)-4));
			}
			break;
		case 250: // File successfully renamed or moved
            bPostUploadCheck = false;
			NextPackage();
			break;
		case 550: // Sorry, but that file doesn't exist
			if( bPostUploadCheck )
			{
				SetTimer(5,false);
				bPostUploadCheck = false;
				if( ++RetryCounter>=5 )
					NextPackage();
				else
				{
					DebugMessage("550 FTP Error: Stats upload failed for "$ToSave[0].PlayerName$" retrying...", true);
					SendFTPLine("PASV");
				}
			}
			break;
		default:
			Global.ProcessResponse(Code,Line);
		}
	}
Begin:
	if( !bIsAsciiMode )
	{
		SendFTPLine("TYPE A");
		bIsAsciiMode = true;
	}
	else
        SendFTPLine("PASV");
	while( true )
	{
		if( Level.bLevelChange ) // Delay mapchange until all stats are uploaded.
		{
			bFullVerbose = true;
			Level.NextSwitchCountdown = FMax(Level.NextSwitchCountdown,2.f);
		}
		Sleep(0.5);
	}
}
state DownloadStats extends ConnectionBase
{
	function BeginState()
	{
		SetTimer(10,false);
	}

    function EndState()
    {
        if ( DownloadDataConnection != none )
            DownloadDataConnection.Destroy();
    }

    function bool OpenDataConnection( string S )
    {
        local int i,j;
        local IpAddr A;

        A = SiteAddress;

        // Get destination port
        S = Mid(S,InStr(S,"(")+1);
        for( i=0; i<4; ++i ) // Skip IP address
            S = Mid(S,InStr(S,",")+1);
        i = InStr(S,",");
        A.Port = int(Left(S,i))*256 + int(Mid(S,i+1));

        // Now attempt to bind port and open connection.
        i = 0;
        for( j=Mut.LastDataPortUsed+1; j!=Mut.LastDataPortUsed && (++i < 100); ++j ) {
            if ( j > Mut.DataPortRangeEnd )
                j = Mut.DataPortRangeStart;
            if( DownloadDataConnection!=None )
                DownloadDataConnection.Destroy();
            DownloadDataConnection = Spawn(Class'FTPDownloadDataConnection',Self);
            DownloadDataConnection.BindPort(j,false);
            if( DownloadDataConnection.OpenNoSteam(A) ) {
                DebugLog("PORT "$j$" bound for download data connection");
                Mut.LastDataPortUsed = j;
                return true;
            }
        }
        Mut.LastDataPortUsed = j;
        DownloadDataConnection.Destroy();
        DownloadDataConnection = None;
        ReportError(2,"Couldn't bind port for download data connection!");
        return false;
    }

	function InitDataConnection( string S )
	{
		while( PendingLoaders.Length>0 && (PendingLoaders[0]==None || PendingLoaders[0].MyStatsObject == none) )
			PendingLoaders.Remove(0,1);
		if( PendingLoaders.Length==0 )
		{
			CheckNextCommand();
			return;
		}

		if( bFullVerbose )
			DebugMessage("FTP: Download stats for "$PendingLoaders[0].MyStatsObject.PlayerName$" ("$(PendingLoaders.Length-1)$" remains)");

		if( OpenDataConnection(S) )
		{
			SendFTPLine("RETR "$PendingLoaders[0].MyStatsObject.Name$".txt");
			bFileInProgress = true;
            SetTimer(10,false);
		}
	}
	function DataReceived()
	{
		bFileInProgress = false;
		if( PendingLoaders[0]!=None )
		{
			if( DownloadDataConnection!=None )
				PendingLoaders[0].GetData(DownloadDataConnection.Data);
			else
                PendingLoaders[0].GetData("");
		}
		PendingLoaders.Remove(0,1);
		while( PendingLoaders.Length>0 && PendingLoaders[0]==None )
			PendingLoaders.Remove(0,1);

        if ( DownloadDataConnection != none )
            DownloadDataConnection.Destroy();

		if( bUploadAllStats ) // Saving has higher priority.
			GoToState('UploadStats');
		else if( PendingLoaders.Length>0 )
			SendFTPLine("PASV");
		else
            CheckNextCommand();
	}
	function ProcessResponse( int Code, string Line )
	{
		switch( Code ) {
            case 125: // Data connection already open, transfer starting.
            case 150: // Opening ASCII mode data connection for file
                SetTimer(60,false);
                break;
            case 200: // Type set to A
                SendFTPLine("PASV");
                break;
            case 226: // File successfully transferred
                SetTimer(10,false);
                if ( bFileInProgress ) {
                    if ( DownloadDataConnection != none && !DownloadDataConnection.bClosed )
                        DownloadDataConnection.OnCompleted = DataReceived; // incoming data is still in progress. Is it possible?..
                    else
                        DataReceived();
                }
                break;
            case 227: // Entering passive mode
                if( !bFileInProgress )
                    InitDataConnection(Line);
                break;
            case 550: // No such file or directory
                SetTimer(10,false);
                if( bFileInProgress ) {
                    if( DownloadDataConnection!=None )
                        DownloadDataConnection.Destroy();
                    DataReceived();
                }
                break;
            default:
                Global.ProcessResponse(Code,Line);
		}
	}
Begin:
	if( !bIsAsciiMode )
	{
		bIsAsciiMode = true;
		SendFTPLine("TYPE A");
	}
	else
        SendFTPLine("PASV");
	while( true )
	{
		if( bUploadAllStats && Level.bLevelChange ) // Delay mapchange until all stats are uploaded.
		{
			bFullVerbose = true;
			Level.NextSwitchCountdown = FMax(Level.NextSwitchCountdown,2.f);
		}
		Sleep(0.5);
	}
}
state ErrorState
{
Ignores SaveAllStats,RequestStats;
Begin:
	Sleep(1.f);
	Mut.RespawnNetworkLink();
}

defaultproperties
{
}
