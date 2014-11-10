unit Pkg.Threading.CancellationToken;

//  A cancellation framework for Delphi
//  Inspired by .NET's cancellation framework with the following differences:
//  - Introduces AppTermCTS: a central place for cancellation
//  - All CTS' are linked in nature. There's no single CTS.
//  - All CTS' are linked to the AppTermCTS
//  - The properties of the token that caused cancellation are preserved
//    So ThrowIfCancelled will raise it's exception class and message
//    Can be used to propagate custom data

interface
uses Pkg.Threading.SyncObjs, sysUtils, generics.collections, syncObjs, classes;

const
  COperationCancelled = 'Operation Cancelled!';
  CApplicationTerminated = 'Operation cancelled due to program termination!';

type

  EOperationCancelled = class(Exception);
  EApplicationTerminated = class(EOperationCancelled);
  ETokenCanNotBeCancelled = class(EOperationCancelled);

  ECancellationClass = class of Exception;

  IPkgCancellationToken = interface;

  IPkgCancellationToken = interface ['{8E60410D-56B5-40BE-9B25-0FE125A8F79A}']
    function  getWaitHandle: IPkgWaitHandle;
    function  getIsCancellationRequested: boolean;
    property  WaitHandle: IPkgWaitHandle read getWaitHandle;
    property  IsCancellationRequested: boolean read getIsCancellationRequested;
    procedure AddOnCancel(AHandler: TProc<IPkgCancellationToken>);
    procedure RemoveOnCancel(AHandler: TProc<IPkgCancellationToken>);
    procedure ThrowIfCancellationRequested;
  end;

  IPkgCancellationTokenSource = interface ['{E3633859-8D65-4F6B-B9E6-78E8BEAAE4C9}']
    function getToken: IPkgCancellationToken;
    function getIsCancellationRequested: boolean;
    property Token: IPkgCancellationToken read getToken;
    property IsCancellationRequested: boolean read getIsCancellationRequested;
    function Cancel(AMessage: string = ''; AExceptionClass: ECancellationClass = nil; AThrowOnFirstException: boolean = false): boolean;
  end;

  TPkgLinkedCancellationTokenSource = class;
  TPkgCancellationToken = class(TInterfacedObject, IPkgCancellationToken)
    private
      //  Weak ref to the parent CTS
      FCancellationTokenSource: TPkgLinkedCancellationTokenSource;
      //  It's a pointer to be able to use Interlocked.CompareExchange
      //  I.e. to skip TMonitor for synchronization
      FIsCancelled: Pointer;
      FCanBeCancelled: boolean;
      //  TDictionary performs *much* better on item removal!
      FNotifyList: TDictionary<TProc<IPkgCancellationToken>, byte>;
      FEvent: IPkgEvent;
      FExceptionClass: ECancellationClass;
      FExceptionMessage: string;
      FAllowAttributeChange: boolean;
      FThrowOnFirstException: boolean;
      function getWaitHandle: IPkgWaitHandle;
    protected
      function InternalCancel(ACancellationToken: IPkgCancellationToken): boolean;
      function getIsCancellationRequested: boolean;
      procedure checkCancellable;
      function DoCancel(ACancellationToken: IPkgCancellationToken; AOnCancelHandler: TProc<TPkgCancellationToken>): boolean;
    public
      constructor Create(AIsCancelled: boolean);
      destructor Destroy; override;
      procedure AddOnCancel(AHandler: TProc<IPkgCancellationToken>);
      procedure RemoveOnCancel(AHandler: TProc<IPkgCancellationToken>);
      procedure ThrowIfCancellationRequested; virtual;
      property WaitHandle: IPkgWaitHandle read getWaitHandle;
      property IsCancellationRequested: boolean read getIsCancellationRequested;
      class function None: IPkgCancellationToken;
  end;

  TPkgLinkedCancellationTokenSource = class(TInterfacedObject, IPkgCancellationTokenSource)
    private
      FCancellationToken: IPkgCancellationToken;
      FLinkedCancellationTokens: TList<IPkgCancellationToken>;
      FNotifyProc: TProc<IPkgCancellationToken>;
      function getToken: IPkgCancellationToken;
      function getIsCancellationRequested: boolean;
    protected
    public
      constructor Create(ATokens: array of IPkgCancellationToken);
      destructor Destroy; override;
      property Token: IPkgCancellationToken read getToken;
      function Cancel(AMessage: string = ''; AExceptionClass: ECancellationClass = nil; AThrowOnFirstException: boolean = false): boolean;
      property IsCancellationRequested: boolean read getIsCancellationRequested;
  end;

  //  By default all CTS are linked to the AppTermCTS
  //  So TPkgCancellationTokenSource is just an illusion
  TPkgCancellationTokenSource = class(TPkgLinkedCancellationTokenSource, IPkgCancellationTokenSource)
    private
    protected
    public
      constructor Create;
      destructor Destroy; override;
      class function CreateLinkedTokenSource(ATokens: array of IPkgCancellationToken): IPkgCancellationTokenSource;
  end;

  //  Returns AppTermCTS
  function ApplicationCancellationTokenSource: IPkgCancellationTokenSource;

implementation

type
  //  The AppTermCTS. All CTS are linked to the AppTermCTS
  //  So it is possible to cancel all CTS from one place
  //  This class replaces only default ExceptionMessage and ExceptionClass
  TPkgApplicationCancellationTokenSource = class(TPkgCancellationTokenSource, IPkgCancellationTokenSource)
    public
      constructor Create;
  end;

var
  AppCancellationTokenSource, TmpAppCancellationTokenSource: IPkgCancellationTokenSource;

function ApplicationCancellationTokenSource: IPkgCancellationTokenSource;
begin
  result := AppCancellationTokenSource;
end;

{ TPkgCancellationToken }

function TPkgCancellationToken.InternalCancel(ACancellationToken: IPkgCancellationToken): boolean;
var
  LHandler: TProc<IPkgCancellationToken>;
begin
  result := true;
  FEvent.setEvent;
  TMonitor.Enter(FNotifyList);
  try
    for LHandler in FNotifyList.Keys do
    begin
      LHandler(ACancellationToken);
    end;
  finally
    TMonitor.Exit(FNotifyList);
  end;
end;

procedure TPkgCancellationToken.checkCancellable;
begin
  if not FCanBeCancelled then
    raise ETokenCanNotBeCancelled.Create('The Cancellation Token does not support cancellation!');
end;

constructor TPkgCancellationToken.Create(AIsCancelled: boolean);
begin
  inherited Create;
  FCanBeCancelled := true;
  FExceptionClass := EOperationCancelled;
  FExceptionMessage := COperationCancelled;
  FAllowAttributeChange := true;

  if AIsCancelled then
    FIsCancelled := Pointer(1)
  else
    FIsCancelled := nil;

  FNotifyList := TDictionary<TProc<IPkgCancellationToken>, byte>.Create; //TInterfaceList.Create;// TList<TProc<IPkgCancellationToken>>.Create;
  FEvent := TPkgEvent.Create(true, false);
end;

destructor TPkgCancellationToken.Destroy;
begin
  FreeAndNil(FNotifyList);
  inherited;
end;

function TPkgCancellationToken.DoCancel(ACancellationToken: IPkgCancellationToken; AOnCancelHandler: TProc<TPkgCancellationToken>): boolean;
begin
  checkCancellable;
  if TInterlocked.CompareExchange(Pointer(FIsCancelled), Pointer(1), Pointer(0)) = Pointer(0) then
  begin
    result := true;
    AOnCancelHandler(self);
    InternalCancel(ACancellationToken);
  end
  else
    result := false;
end;

function TPkgCancellationToken.getIsCancellationRequested: boolean;
begin
  result := FIsCancelled <> nil;
end;

function TPkgCancellationToken.getWaitHandle: IPkgWaitHandle;
begin
  result := FEvent.ToWaitHandle;
end;

class function TPkgCancellationToken.None: IPkgCancellationToken;
begin
  result := TPkgCancellationToken.Create(false);
  TPkgCancellationToken(result).FCanBeCancelled := false;
end;

procedure TPkgCancellationToken.RemoveOnCancel(
  AHandler: TProc<IPkgCancellationToken>);
var
  i: IInterface absolute AHandler;
begin
  TMonitor.Enter(FNotifyList);
  try
    FNotifyList.Remove(AHandler);
  finally
    TMonitor.Exit(FNotifyList);
  end;
end;

procedure TPkgCancellationToken.AddOnCancel(AHandler: TProc<IPkgCancellationToken>);
var
  i: IInterface absolute AHandler;
begin
  if FIsCancelled <> nil then
    AHandler(self as IPkgCancellationToken)
  else
  begin
    TMonitor.Enter(FNotifyList);
    try
      FNotifyList.Add(AHandler, 0);
    finally
      TMonitor.Exit(FNotifyList);
    end;
  end;
end;

procedure TPkgCancellationToken.ThrowIfCancellationRequested;
begin
  if FIsCancelled <> nil then
    raise FExceptionClass.Create(FExceptionMessage);
end;

{ TPkgLinkedCancellationTokenSource }

function TPkgLinkedCancellationTokenSource.Cancel(AMessage: string; AExceptionClass: ECancellationClass; AThrowOnFirstException: boolean): boolean;
var
  LToken: TPkgCancellationToken;
begin
  LToken := TPkgCancellationToken(FCancellationToken);
  result := LToken.DoCancel(FCancellationToken,
    procedure(AToken: TPkgCancellationToken)
    begin
      //  Setup Initiator token's properties
      if AMessage <> '' then
        AToken.FExceptionMessage := AMessage;

      if AExceptionClass <> nil then
        AToken.FExceptionClass := AExceptionClass;

      AToken.FThrowOnFirstException := AThrowOnFirstException;
    end
  );
end;

constructor TPkgLinkedCancellationTokenSource.Create(
  ATokens: array of IPkgCancellationToken);
var
  LToken: IPkgCancellationToken;
begin
  inherited Create;
  FCancellationToken := TPkgCancellationToken.Create(false);
  TPkgCancellationToken(FCancellationToken).FCancellationTokenSource := self;
  FLinkedCancellationTokens := TList<IPkgCancellationToken>.Create;
  //  Add the Application Cancellation Token Source
  //  This way if the Application was terminated all cancellation listeners will cancel
  if not (self is TPkgApplicationCancellationTokenSource) then
    FLinkedCancellationTokens.Add(ApplicationCancellationTokenSource.Token);
  FLinkedCancellationTokens.AddRange(ATokens);

  FNotifyProc :=
    procedure(AToken: IPkgCancellationToken)
    begin
      if TPkgCancellationToken(FCancellationToken).DoCancel(AToken,
        procedure(BToken: TPkgCancellationToken)
        begin
          //  Bubble up source token's attributes
          //  i.e. ThowIfCancelled will raise FExceptionClass with FExceptionMessage
          BToken.FExceptionClass := TPkgCancellationToken(AToken).FExceptionClass;
          BToken.FExceptionMessage := TPkgCancellationToken(AToken).FExceptionMessage;
          BToken.FThrowOnFirstException := TPkgCancellationToken(AToken).FThrowOnFirstException;
        end
      ) then
      begin
        //  This will be executed only once! NOP for now
      end
    end;

  for LToken in FLinkedCancellationTokens do
  begin
    LToken.AddOnCancel(FNotifyProc);
  end;
end;

destructor TPkgLinkedCancellationTokenSource.Destroy;
var
  LToken: IPkgCancellationToken;
begin
  for LToken in FLinkedCancellationTokens do
  begin
    LToken.RemoveOnCancel(FNotifyProc);
  end;
  FCancellationToken := nil;
  FreeAndNil(FLinkedCancellationTokens);
  inherited;
end;

function TPkgLinkedCancellationTokenSource.getIsCancellationRequested: boolean;
begin
  result := FCancellationToken.IsCancellationRequested;
end;

function TPkgLinkedCancellationTokenSource.getToken: IPkgCancellationToken;
begin
  result := FCancellationToken;
end;

{ TPkgCancellationTokenSource }

constructor TPkgCancellationTokenSource.Create();
begin
  inherited Create([]);
end;

class function TPkgCancellationTokenSource.CreateLinkedTokenSource(
  ATokens: array of IPkgCancellationToken): IPkgCancellationTokenSource;
begin
  result := TPkgLinkedCancellationTokenSource.Create(ATokens) as IPkgCancellationTokenSource;
end;

destructor TPkgCancellationTokenSource.Destroy;
begin
  inherited;
end;

{ TPkgApplicationCancellationTokenSource }

constructor TPkgApplicationCancellationTokenSource.Create;
begin
  inherited Create;
  TPkgCancellationToken(FCancellationToken).FExceptionClass := EApplicationTerminated;
  TPkgCancellationToken(FCancellationToken).FExceptionMessage := CApplicationTerminated;
end;

initialization

  //  Create the only one AppTermCTS
  TmpAppCancellationTokenSource := TPkgApplicationCancellationTokenSource.Create();
  if TInterlocked.CompareExchange(Pointer(AppCancellationTokenSource), Pointer(TmpAppCancellationTokenSource), Pointer(nil)) <> nil then
    TmpAppCancellationTokenSource := nil;

finalization
  //  Just for clarity
  TInterlocked.CompareExchange(Pointer(AppCancellationTokenSource), Pointer(nil), Pointer(AppCancellationTokenSource));

end.
