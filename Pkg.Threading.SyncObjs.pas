unit Pkg.Threading.SyncObjs;

interface
uses syncObjs, {$IFDEF MSWINDOWS}Windows,{$ENDIF MSWINDOWS} sysUtils,
  generics.collections, system.threading;

type

  IPkgWaitHandle = interface ['{A11FED0F-204A-4FE6-BED1-5E2D902A7A4F}']
    function WaitFor(Timeout: LongWord): TWaitResult;
    function ToWaitHandle: IPkgWaitHandle;
  end;

  IPkgEvent = interface(IPkgWaitHandle) ['{F1CD8006-91EB-4ED7-BB15-423D9C4F3792}']
    procedure setEvent;
    procedure resetEvent;
  end;

  IPkgSemaphore = interface(IPkgWaitHandle) ['{0960C375-C6AA-470D-ABA9-EEBE28D0E942}']
    procedure Acquire;
    procedure Release;
  end;

  //  For accessing TTask's protected members
  TPkgTaskHack = class(System.Threading.TTask)
  end;

  IPkgTaskWaiter = interface(IPkgWaitHandle) ['{6D28E618-8FEF-441B-92EB-4F1F92130BF2}']
  end;

  TPkgWaitHandle = class(TInterfacedObject, IPkgWaitHandle)
    private
      FPadlock: TObject;
      FNotifyList: TList<TProc<IPkgWaitHandle>>;
      FWaiterCount: integer;
      FIsManualReset: boolean;
    protected
      procedure incWaiters;
      procedure decWaiters;
      procedure doNotify(ANotifyCount: integer);
      procedure atomic(AHandler: TProc);
      procedure lock;
      procedure unlock;
      procedure addWaiter(AWaiter: TProc<IPkgWaitHandle>);
      procedure removeWaiter(AWaiter: TProc<IPkgWaitHandle>);

    public
      constructor Create(AManualResetEvent: boolean);
      destructor Destroy; override;

      function WaitFor(Timeout: LongWord): TWaitResult; virtual;

      class function WaitAny1(AItems: array of IPkgWaitHandle; ATimeout: LongWord): integer;
      class function WaitAny(AItems: array of const; ATimeout: LongWord): integer; overload;
      class function WaitAny(AItems: TArray<IPkgWaitHandle>; ATimeout: LongWord): integer; overload;
      class function WaitList(AItems: array of const): TArray<IPkgWaitHandle>;

      function ToWaitHandle: IPkgWaitHandle;
  end;

  TPkgEvent = class(TPkgWaitHandle, IPkgWaitHandle, IPkgEvent)
    private
      FEvent: TEvent;
    protected
    public
      constructor Create(AManualResetEvent, AInitialState: boolean);
      destructor Destroy; override;

      procedure setEvent;
      procedure resetEvent;
      function WaitFor(ATimeout: LongWord): TWaitResult; override;
  end;

  TPkgSemaphore = class(TPkgWaitHandle, IPkgWaitHandle, IPkgSemaphore)
    private
      FSemaphore: TSemaphore;
      FInitialCount,
      FCurrentCount,
      FMaxCount: integer;
    protected
    public
      constructor Create(AInitialCount, AMaximumCount: Integer);
      destructor Destroy; override;

      procedure Acquire;
      procedure Release;
      function WaitFor(ATimeout: LongWord): TWaitResult; override;
  end;

  TPkgTaskWaiter = class(TPkgWaitHandle, IPkgWaitHandle, IPkgTaskWaiter)
    private
      FTask: ITask;
      FEvent: TLightweightEvent;
      FTaskCompletionHandler: TProc<ITask>;
    protected
    public
      constructor Create(ATask: ITask);
      destructor Destroy; override;

      function WaitFor(ATimeout: LongWord): TWaitResult; override;
  end;

  TPkgAbstractExternalWaitHandle = class abstract(TPkgWaitHandle, IPkgWaitHandle)

  end;

  TPkgExternalEvent = class(TPkgEvent, IPkgEvent)

  end;





implementation
uses strUtils;



{ TPkgWaitable }

constructor TPkgWaitHandle.Create(AManualResetEvent: boolean);
begin
  inherited Create;
  FPadlock := TObject.Create;
  FNotifyList := TList<TProc<IPkgWaitHandle>>.Create;
  FIsManualReset := AManualResetEvent;
end;


procedure TPkgWaitHandle.decWaiters;
begin
  TMonitor.Enter(FPadlock);
  try
    dec(FWaiterCount);
  finally
    TMonitor.Exit(FPadlock);
  end;
end;

destructor TPkgWaitHandle.Destroy;
begin
  FreeAndNil(FNotifyList);
  FreeAndNil(FPadlock);
  inherited;
end;

procedure TPkgWaitHandle.incWaiters;
begin
  TMonitor.Enter(FPadlock);
  try
    inc(FWaiterCount);
  finally
    TMonitor.Exit(FPadlock);
  end;
end;

class function TPkgWaitHandle.WaitAny(AItems: array of const;
  ATimeout: LongWord): integer;
begin
  result := WaitAny(TPkgWaitHandle.WaitList(AItems), ATimeout);
end;

class function TPkgWaitHandle.WaitAny(AItems: TArray<IPkgWaitHandle>;
  ATimeout: LongWord): integer;
var
  LItems: array of IPkgWaitHandle;
  k: Integer;
begin
  setLength(LItems, length(AItems));
  for k := low(AItems) to high(AItems) do
    LItems[k] := AItems[k];

  result := waitAny1(LItems, ATimeout);
  setLength(LItems, 0);



end;

function TPkgWaitHandle.WaitFor(Timeout: LongWord): TWaitResult;
begin
  raise Exception.Create('Not Implemented!');
end;

class function TPkgWaitHandle.WaitList(
  AItems: array of const): TArray<IPkgWaitHandle>;
var
  k: Integer;
  i: IInterface;
  o: TObject;
  LClassName: string;
begin
  setLength(result, length(AItems));
  for k := low(AItems) to high(AItems) do
  begin
    if TVarRec(AItems[k]).VType <> vtInterface then
      raise Exception.CreateFmt('Element %d is not an interface!', [k]);

    i := IInterface(AItems[k].VInterface);
    o := TObject(i);
    LClassName := LowerCase(o.QualifiedClassName);

    if not o.InheritsFrom(TPkgWaitHandle) then
      if o.InheritsFrom(System.Threading.TTask) then
        i := TPkgTaskWaiter.Create(ITask(i))
      else
        raise Exception.CreateFmt('Parameter %d must be a Waitable or an ITask!', [k]);

    result[k] := (i as IPkgWaitHandle);
  end;
end;

class function TPkgWaitHandle.WaitAny1(AItems: array of IPkgWaitHandle;
  ATimeout: LongWord): integer;
var
  LWaitable, LSignaledWaitable: IPkgWaitHandle;
  k: integer;
  LEvent: TLightweightEvent;
  LSignaledProc: TProc<IPkgWaitHandle>;
  LWaitRes: TWaitResult;
begin
  LSignaledWaitable := nil;
  result := -1;
  //  First check if we have already signalled events
  for k := low(AItems) to high(AItems) do
  begin
    LWaitable := AItems[k];
    if LWaitable.WaitFor(0) = wrSignaled then
    begin
      exit(k);
    end;
  end;

  if (result = -1) AND (length(AItems) > 0) then
  begin
    LEvent := TLightweightEvent.Create(false);
    try
      //  Local OnSignaled handler
      LSignaledProc :=
        procedure(AWaitable: IPkgWaitHandle)
        begin
          if TInterlocked.CompareExchange(pointer(LSignaledWaitable), pointer(AWaitable), pointer(nil)) = nil then
          begin
            LEvent.SetEvent;
          end;

          TPkgWaitHandle(AWaitable).removeWaiter(LSignaledProc);

        end;

      for k := low(AItems) to high(AItems) do
      begin
        LWaitable := AItems[k];
        TPkgWaitHandle(LWaitable).lock;
        try
          //  Again, check for already signaled events
          if LWaitable.WaitFor(0) = wrSignaled then
          begin
            //  Execute Local Handler
            LSignaledProc(LWaitable);
            break;
          end
          else
            //  Add Local Handler to Event's Notify list
            TPkgWaitHandle(LWaitable).FNotifyList.Add(LSignaledProc);
        finally
          TPkgWaitHandle(LWaitable).unlock;
        end;

      end;

      LWaitRes := LEvent.WaitFor(ATimeout);

      //  Update Event Index and remove Local Handlers
      for k := low(AItems) to high(AItems) do
      begin
        LWaitable := AItems[k];
        TPkgWaitHandle(LWaitable).lock;
        try
          if (LSignaledWaitable = LWaitable) AND (LWaitRes <> wrTimeout) then
            result := k;

          TPkgWaitHandle(LWaitable).FNotifyList.Remove(LSignaledProc);

        finally
          TPkgWaitHandle(LWaitable).unlock;
        end;
      end;

    finally
      FreeAndNil(LEvent);
    end;
  end;


end;

procedure TPkgWaitHandle.doNotify(ANotifyCount: integer);
var
  LNotifyProc: TProc<IPkgWaitHandle>;
  k, cnt: integer;
begin
  cnt := 0;
  if FWaiterCount = 0 then
  begin
    for k := FNotifyList.Count - 1 downto 0 do
    begin
      LNotifyProc := FNotifyList[k];
      LNotifyProc(self as IPkgWaitHandle);
      inc(cnt);
      if (ANotifyCount > 0) AND (cnt >= ANotifyCount) then exit;
    end;
  end;
end;

procedure TPkgWaitHandle.addWaiter(AWaiter: TProc<IPkgWaitHandle>);
begin
  TMonitor.Enter(FPadlock);
  try
    FNotifyList.Add(AWaiter);
  finally
    TMonitor.Exit(FPadlock);
  end;
end;

procedure TPkgWaitHandle.atomic(AHandler: TProc);
begin
  TMonitor.Enter(FPadlock);
  try
    AHandler;
  finally
    TMonitor.Exit(FPadlock);
  end;
end;

procedure TPkgWaitHandle.lock;
begin
  TMonitor.Enter(FPadlock);
end;

procedure TPkgWaitHandle.removeWaiter(AWaiter: TProc<IPkgWaitHandle>);
begin
  TMonitor.Enter(FPadlock);
  try
    FNotifyList.Remove(AWaiter);
  finally
    TMonitor.Exit(FPadlock);
  end;
end;

function TPkgWaitHandle.ToWaitHandle: IPkgWaitHandle;
begin
  result := self as IPkgWaitHandle;
end;

procedure TPkgWaitHandle.unlock;
begin
  TMonitor.Exit(FPadlock);
end;


{ TPkgEvent }



constructor TPkgEvent.Create(AManualResetEvent, AInitialState: boolean);
begin
  inherited Create(AManualResetEvent);
  FEvent := TEvent.Create(nil, AManualResetEvent, AInitialState, '');
end;

destructor TPkgEvent.Destroy;
begin
  FreeAndNil(FEvent);
  inherited;
end;

procedure TPkgEvent.resetEvent;
begin
  TMonitor.Enter(FPadlock);
  try
    FEvent.ResetEvent;
  finally
    TMonitor.Exit(FPadlock);
  end;
end;

procedure TPkgEvent.setEvent;
begin
  TMonitor.Enter(FPadlock);
  try
    FEvent.SetEvent;
    if FIsManualReset then
      doNotify(1)
    else
      doNotify(-1);
  finally
    TMonitor.Exit(FPadlock);
  end;
end;



function TPkgEvent.WaitFor(ATimeout: LongWord): TWaitResult;
begin
  incWaiters;
  try
    result := FEvent.WaitFor(ATimeout);
  finally
    decWaiters;
  end;
end;

{ TPkgSemaphore }

procedure TPkgSemaphore.Acquire;
begin
  WaitFor(INFINITE);
end;

constructor TPkgSemaphore.Create(AInitialCount, AMaximumCount: Integer);
begin
  inherited Create(true);
  FSemaphore := TSemaphore.Create(nil, AInitialCount, AMaximumCount, '');
  FInitialCount := AInitialCount;
  FCurrentCount := AInitialCount;
  FMaxCount := AMaximumCount;
end;

destructor TPkgSemaphore.Destroy;
begin
  FreeAndNil(FSemaphore);
  inherited;
end;

procedure TPkgSemaphore.Release;
var
  LNotifyCount: integer;
begin
  TMonitor.Enter(FPadlock);
  try
    FSemaphore.Release;
    inc(FCurrentCount);
    if FWaiterCount = 0 then
    begin
      LNotifyCount := FMaxCount - FCurrentCount;
      doNotify(LNotifyCount);
    end;
  finally
    TMonitor.Exit(FPadlock);
  end;
end;

function TPkgSemaphore.WaitFor(ATimeout: LongWord): TWaitResult;
var
  LNotifyCount: integer;
begin
  result := wrTimeout;
  incWaiters;
  try
    result := FSemaphore.WaitFor(ATimeout);
  finally
    TMonitor.Enter(FPadlock);
    try
      if result = wrSignaled then
        dec(FCurrentCount);
      decWaiters;
      //  In case when this is the last waiter
      if (result = wrSignaled) AND (FWaiterCount = 0) then
      begin
        LNotifyCount := FMaxCount - FCurrentCount;
        doNotify(LNotifyCount);
      end;
    finally
      TMonitor.Exit(FPadlock);
    end;
  end;
end;

{ TPkgTaskWaiter }

constructor TPkgTaskWaiter.Create(ATask: ITask);
begin
  inherited Create(true);
  FEvent := TLightweightEvent.Create(false);
  FTask := ATask;

  FTaskCompletionHandler :=
    procedure(ATask: ITask)
    begin
      FEvent.SetEvent;
      ATask := nil;
      TMonitor.Enter(FPadlock);
      try
        doNotify(-1);
      finally
        TMonitor.Exit(FPadlock);
      end;
    end;

  TPkgTaskHack(TTask(FTask)).AddCompleteEvent(FTaskCompletionHandler);

end;

destructor TPkgTaskWaiter.Destroy;
begin
  TPkgTaskHack(TTask(FTask)).RemoveCompleteEvent(FTaskCompletionHandler);
  FTaskCompletionHandler := nil;
  FTask := nil;
  FreeAndNil(FEvent);
  inherited;
end;

function TPkgTaskWaiter.WaitFor(ATimeout: LongWord): TWaitResult;
begin
  result := wrTimeout;
  incWaiters;
  try
    result := FEvent.WaitFor(ATimeout);
  finally
    TMonitor.Enter(FPadlock);
    try
      decWaiters;
      //  In case when this is the last waiter
      if result = wrSignaled then
        doNotify(-1);
    finally
      TMonitor.Exit(FPadlock);
    end;
  end;
end;

end.
