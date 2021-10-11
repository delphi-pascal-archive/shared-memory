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
   hSharedMemory: THandle; // Handle de la mémoire paratagée
   hMutex: THandle;        // Handle du mutex à posséder pour avoir le droit d'écrire
   hEvent: THandle;        // Handle de l'event qui est déclenché quand il faut lire le buffer
   lpListener: TListener;  // Thread de lecture de la mémoire partagée

const
  SHARED_MEMORY_SIZE = 65536;

implementation

//
// Ce thread va afficher les messages des autres utilisateurs dans
// la console courante.
//
procedure TListener.Execute();
var
  lpData: Pointer;     // Pointeur sur la mémoire partagé
  nLineSize: Integer;  // Taille de la chaîne
  lpLine: string;      // Récupération de la ligne
begin
  while not Self.Terminated do
  begin
    WaitForSingleObject(hEvent, INFINITE);
    ResetEvent(hEvent);

    // On récupère un pointeur pour pouvoir lire la mémoire.
    lpData:= MapViewOfFile(hSharedMemory, FILE_MAP_READ, 0, 0, SHARED_MEMORY_SIZE);
    if lpData = nil then
    begin
      WriteLn('Echec de la recuperation du pointeur.');
      Exit;
    end;

    // Récupération de la taille de la ligne
    nLineSize:= Integer(lpData^);

    // Récupération de la ligne
    SetLength(lpLine, nLineSize);
    CopyMemory(PChar(lpLine),Pointer(Integer(lpData) + 4) , nLineSize);

    // On signale que l'on a fini de travailler avec la mémoire
    UnmapViewOfFile(lpData);

    // Ecriture de la chaîne dans la console
    WriteLn(lpLine);
  end;
end;

//
// Récupère les handles des différents objets systèmes.
//
procedure RetrieveHandles();
begin
  // On tente de créer la mémoire partagée.
  // Si une mémoire partagée ayant le même nom existe déjà,
  // windows renvoie un handle valide sur l'éxistante.
  hSharedMemory:= CreateFileMapping(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0, SHARED_MEMORY_SIZE, 'DelphiChatSharedMemory');
  if hSharedMemory = 0 then
  begin
    RaiseLastOSError();
    Halt;
  end;

  // De même, on récupère un handle de mutex
  hMutex:= CreateMutex(nil, False, 'DelphiChatMutex');
  if hMutex = 0 then
  begin
    CloseHandle(hSharedMemory);
    RaiseLastOSError();
    Halt;
  end;

  // Une dernière création ou récupération, pour l'event
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
// Ferme les handles des objets systèmes.
//
procedure CloseHandles();
begin
  CloseHandle(hSharedMemory);
  CloseHandle(hMutex);
  Closehandle(hEvent);
end;

//
// Permet à l'utilisateur d'entrer un pseudo.
//
procedure Login();
begin
  Write('Entrer you Nickname: ');
  ReadLn(lpPseudo);
//==============================================================================
// TODO : Vérif diverses sur le pseudo.
//==============================================================================
end;

//
// Ecriture dans la mémoire partagée
//
procedure WriteInSharedMemory(const lpLine: String);
var
  lpData: Pointer;  // Pointeur sur la mémoire partagé
begin
  // On prend possession du mutex pour empècher les autres processus
  // d'écrire dans notre mémoire.
  WaitForSingleObject(hMutex, INFINITE);

  // On récupère un pointeur pour pouvoir écrire dans la mémoire.
  // On demande la taille de notre chaîne + 32 bits pour spécifier la taille de celle-ci.
  lpData:= MapViewOfFile(hSharedMemory, FILE_MAP_WRITE, 0, 0, Length(lpLine) + 4);
  if lpData = nil then
  begin
    WriteLn('Echec de la recuperation du pointeur');
    Exit;
  end;

  // Ecriture de la taille de la chaîne dans les 32 premiers bits de la mémoire partagée
  Integer(lpData^):= Length(lpLine);

  // Ecriture de la chaîne
  CopyMemory(Pointer(Integer(lpData) + 4), PChar(lpLine), Length(lpLine));

  // On signale que l'on a fini de travailler avec la mémoire
  UnmapViewOfFile(lpData);

  // On signale que l'on a mis des données dans la mémoire
  PulseEvent(hEvent);

  // On libère le mutex
  ReleaseMutex(hMutex)
end;

//
// Connexion à la mémoire partagée.
//
procedure Connect();
begin
  RetrieveHandles();
  WriteLn('Welcome to chat. Enter exit to quit.');
  lpListener:= TListener.Create(False);
  WriteInSharedMemory(lpPseudo + ' connected.');
end;

//
// Gère le dialogue.
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
// Déconnexion de la mémoire partagée.
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
