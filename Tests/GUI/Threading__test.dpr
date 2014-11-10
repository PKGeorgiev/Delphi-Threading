program Threading__test;

uses
  Vcl.Forms,
  Unit2 in 'Unit2.pas' {Form2},
  Pkg.Threading.CancellationToken in '..\..\Pkg.Threading.CancellationToken.pas',
  Pkg.Threading in '..\..\Pkg.Threading.pas',
  Pkg.Threading.SyncObjs in '..\..\Pkg.Threading.SyncObjs.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm2, Form2);
  Application.Run;
end.
