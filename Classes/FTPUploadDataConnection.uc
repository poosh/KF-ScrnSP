Class FTPUploadDataConnection extends FTPDataConnectionSE;

var bool bWasOpened;

event Opened()
{
	BeginUpload();
}
event Closed()
{
    Destroy(); 
}

event ReceivedText( string Text )
{
    Log(Text,'FTPUP'); // shouldn't happen
}
function BeginUpload()
{
	if( bWasOpened )
		GoToState('Uploading');
	else 
        bWasOpened = true;
}

state Uploading
{
	function BeginState()
	{
		Tick(0.f);
	}
	function Tick( float Delta )
	{
		if( Data!="" ) {
            if ( len(data) > BufferSize ) {
                SendText(Left(Data,BufferSize));
                Data = Mid(Data,BufferSize);
            }
            else {
                SendText(Data);
                Data = "";
            }
		}
		else 
            Close();
	}
}
