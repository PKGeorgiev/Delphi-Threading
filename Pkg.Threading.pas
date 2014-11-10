unit Pkg.Threading;

interface
uses sysUtils, classes;



  procedure RunInThread(AHandler: TProc);
  procedure RunInVcl(AHandler: TProc);

implementation

  procedure RunInThread(AHandler: TProc);
  begin
    TThread.CreateAnonymousThread(AHandler).Start();
  end;

  procedure RunInVcl(AHandler: TProc);
  begin
    TThread.Synchronize(nil, TThreadProcedure(AHandler));
  end;

end.
