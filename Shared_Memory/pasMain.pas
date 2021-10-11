unit pasMain;

interface

uses
  Windows, SysUtils, Classes;

  procedure Login();
  procedure Connect();
  procedure Run();
  procedure Disconnect();

  type TListener = class(TThread)
   protected
     procedure Execute(); override;
  end;

  var
   lpPseudo: string;       // Pseudo de choisi par l'utilisateur
   hSharedMemory: THandle; // Handle de la m�moire paratag�e
   hMutex: THandle;        // Handle du mutex � poss�der pour avoir le droit d'�crire
   hEvent: THandle;        // Handle de l'event qui est d�clench� quand il faut lire le buffer
   lpListener: TListener;  // Thread de lecture de la m�moire partag�e

const
  SHARED_MEMORY_SIZE = 65536;

implementation

//
// Ce thread va afficher les messages des autres utilisateurs dans
// la console courante.
//
procedure TListener.Execute();
var
  lpData: Pointer;     // Pointeur sur la m�moire partag�
  nLineSize: Integer;  // Taille de la cha�ne
  lpLine: string;      // R�cup�ration de la ligne
begin
  while not Self.Terminated do
  begin
    WaitForSingleObject(hEvent, INFINITE);
    ResetEvent(hEvent);

    // On r�cup�re un pointeur pour pouvoir lire la m�moire.
    lpData:= MapViewOfFile(hSharedMemory, FILE_MAP_READ, 0, 0, SHARED_MEMORY_SIZE);
    if lpData = nil then
    begin
      WriteLn('Echec de la recuperation du pointeur.');
      Exit;
    end;

    // R�cup�ration de la taille de la ligne
    nLineSize:= Integer(lpData^);

    // R�cup�ration de la ligne
    SetLength(lpLine, nLineSize);
    CopyMemory(PChar(lpLine),Pointer(Integer(lpData) + 4) , nLineSize);

    // On signale que l'on a fini de travailler avec la m�moire
    UnmapViewOfFile(lpData);

    // Ecriture de la cha�ne dans la console
    WriteLn(lpLine);
  end;
end;

//
// R�cup�re les handles des diff�rents objets syst�mes.
//
procedure RetrieveHandles();
begin
  // On tente de cr�er la m�moire partag�e.
  // Si une m�moire partag�e ayant le m�me nom existe d�j�,
  // windows renvoie un handle valide sur l'�xistante.
  hSharedMemory:= CreateFileMapping(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0, SHARED_MEMORY_SIZE, 'DelphiChatSharedMemory');
  if hSharedMemory = 0 then
  begin
    RaiseLastOSError();
    Halt;
  end;

  // De m�me, on r�cup�re un handle de mutex
  hMutex:= CreateMutex(nil, False, 'DelphiChatMutex');
  if hMutex = 0 then
  begin
    CloseHandle(hSharedMemory);
    RaiseLastOSError();
    Halt;
  end;

  // Une derni�re cr�ation ou r�cup�ration, pour l'event
  hEvent:= CreateEvent(nil, True, False, 'DelphiChatEvent');
  if hEvent = 0 then
  begin
    CloseHandle(hMutex);
    CloseHandle(hSharedMemory);
    RaiseLastOSError();
    Halt;
  end;
end;

//
// Ferme les handles des objets syst�mes.
//
procedure CloseHandles();
begin
  CloseHandle(hSharedMemory);
  CloseHandle(hMutex);
  Closehandle(hEvent);
end;

//
// Permet � l'utilisateur d'entrer un pseudo.
//
procedure Login();
begin
  Write('Entrer you Nickname: ');
  ReadLn(lpPseudo);
//==============================================================================
// TODO : V�rif diverses sur le pseudo.
//==============================================================================
end;

//
// Ecriture dans la m�moire partag�e
//
procedure WriteInSharedMemory(const lpLine: String);
var
  lpData: Pointer;  // Pointeur sur la m�moire partag�
begin
  // On prend possession du mutex pour emp�cher les autres processus
  // d'�crire dans notre m�moire.
  WaitForSingleObject(hMutex, INFINITE);

  // On r�cup�re un pointeur pour pouvoir �crire dans la m�moire.
  // On demande la taille de notre cha�ne + 32 bits pour sp�cifier la taille de celle-ci.
  lpData:= MapViewOfFile(hSharedMemory, FILE_MAP_WRITE, 0, 0, Length(lpLine) + 4);
  if lpData = nil then
  begin
    WriteLn('Echec de la recuperation du pointeur');
    Exit;
  end;

  // Ecriture de la taille de la cha�ne dans les 32 premiers bits de la m�moire partag�e
  Integer(lpData^):= Length(lpLine);

  // Ecriture de la cha�ne
  CopyMemory(Pointer(Integer(lpData) + 4), PChar(lpLine), Length(lpLine));

  // On signale que l'on a fini de travailler avec la m�moire
  UnmapViewOfFile(lpData);

  // On signale que l'on a mis des donn�es dans la m�moire
  PulseEvent(hEvent);

  // On lib�re le mutex
  ReleaseMutex(hMutex)
end;

//
// Connexion � la m�moire partag�e.
//
procedure Connect();
begin
  RetrieveHandles();
  WriteLn('Welcome to chat. Enter exit to quit.');
  lpListener:= TListener.Create(False);
  WriteInSharedMemory(lpPseudo + ' connected.');
end;

//
// G�re le dialogue.
//
procedure Run();
var
  lpBuffer: String;
begin
  ReadLn(lpBuffer);
  while LowerCase(lpBuffer) <> 'exit' do
  begin
    lpBuffer:='"' + lpPseudo + '" say: ' + lpBuffer;
    WriteInSharedMemory(lpBuffer);
    ReadLn(lpBuffer);
  end;
end;

//
// D�connexion de la m�moire partag�e.
//
procedure Disconnect();
begin
  // On demande au thread de se terminer au prochain message
  lpListener.Terminate;
  
  WriteInSharedMemory(lpPseudo + ' is deconnected.');

  // On attend que le thread de lecture se termine avant de fermer les handles
  lpListener.WaitFor();
  lpListener.Free;
  
  //WaitForSingleObject(lpListener.Handle, INFINITE);
  CloseHandles();
end;

end.
