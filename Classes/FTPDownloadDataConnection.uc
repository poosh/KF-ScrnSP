Class FTPDownloadDataConnection extends FTPDataConnectionSE;

var bool bClosed;
delegate OnCompleted();

event ReceivedText( string Text )
{
    Data $= Text;
}

event Closed()
{
    bClosed = true;
	OnCompleted();
}
