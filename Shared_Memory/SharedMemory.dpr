program SharedMemory;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  pasMain in 'pasMain.pas';

begin
  Login();
  Connect();
  Run();
  Disconnect();
end.
