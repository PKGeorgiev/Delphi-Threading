unit Unit2;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Pkg.Threading.CancellationToken,
  Pkg.Threading, Pkg.Threading.SyncObjs, Vcl.StdCtrls, generics.collections, system.Diagnostics;

type
  TForm2 = class(TForm)
    Memo1: TMemo;
    Button1: TButton;
    Button2: TButton;
    Button3: TButton;
    Button4: TButton;
    procedure FormCreate(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure Button3Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
    cts1, cts2, cts3: IPkgCancellationTokenSource;
    lcts1, lcts2, lcts3: IPkgCancellationTokenSource;
    ctsList: TList<IPkgCancellationTokenSource>;
  end;

var
  Form2: TForm2;

implementation

{$R *.dfm}

procedure TForm2.Button1Click(Sender: TObject);
begin
  RunInThread(
    procedure
    begin
      lcts3.Token.WaitHandle.WaitFor(INFINITE);
      lcts3.Token.ThrowIfCancellationRequested;
      RunInVcl(
        procedure
        begin
          memo1.Lines.Add('Finished1');
        end
      );
    end
  );
end;

procedure TForm2.Button2Click(Sender: TObject);
begin
  cts3.Cancel('Yooo');
//  ApplicationCancellationTokenSource.Cancel();
end;


procedure TForm2.Button3Click(Sender: TObject);
var
  sw: TStopwatch;
  k: Integer;
  cts: IPkgCancellationTokenSource;
begin
  ctsList.Clear;
  sw := TStopwatch.StartNew;
  sw.Start;
  for k := 1 to 1000 do
  begin
    cts := TPkgCancellationTokenSource.Create;
    ctsList.Add(cts);
  end;

  sw.Stop;
  memo1.Lines.Add(format('Create: %d', [sw.ElapsedMilliseconds]));
end;

procedure TForm2.Button4Click(Sender: TObject);
var
  sw: TStopwatch;
  k: Integer;
  cts: IPkgCancellationTokenSource;
begin

  sw := TStopwatch.StartNew;
  sw.Start;
  //ctsList.Clear;
  ApplicationCancellationTokenSource.Cancel();

  sw.Stop;
  memo1.Lines.Add(format('Cancel: %d', [sw.ElapsedMilliseconds]));
end;

procedure TForm2.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if ApplicationCancellationTokenSource.IsCancellationRequested then
    CanClose := true
  else
  begin
    CanClose := false;
    ApplicationCancellationTokenSource.Cancel();
  end;
end;

procedure TForm2.FormCreate(Sender: TObject);
begin

  cts1 := TPkgCancellationTokenSource.Create;
  cts2 := TPkgCancellationTokenSource.Create;
  cts3 := TPkgCancellationTokenSource.Create;
//
  lcts1 := TPkgCancellationTokenSource.CreateLinkedTokenSource([cts1.Token]);
  lcts2 := TPkgCancellationTokenSource.CreateLinkedTokenSource([lcts1.Token, cts2.Token]);
  lcts3 := TPkgCancellationTokenSource.CreateLinkedTokenSource([lcts2.Token, cts3.Token]);

  ctsList := TList<IPkgCancellationTokenSource>.Create;
end;

end.
