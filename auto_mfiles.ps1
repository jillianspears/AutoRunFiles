param(
  [Parameter(Mandatory=$true)][string]$InputDir,
  [Parameter(Mandatory=$true)][string]$ResultsDir
)

$Matlab = "C:\Program Files\MATLAB\R2024a\bin\matlab.exe"
if (-not (Test-Path $Matlab)) { throw "MATLAB not found: $Matlab" }

New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
$MFiles = Get-ChildItem -Path $InputDir -Filter *.m -File
if ($MFiles.Count -eq 0) { Write-Host "No .m files in $InputDir"; exit }

foreach ($f in $MFiles) {
  $func = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
  $ts   = Get-Date -Format "yyyyMMdd_HHmmss"
  $work = New-Item -ItemType Directory -Path ([System.IO.Path]::GetTempPath()) -Name ("ml_" + [guid]::NewGuid())
  $out  = Join-Path $ResultsDir "$func" + "_" + $ts
  New-Item -ItemType Directory -Force -Path $out | Out-Null
  $log  = Join-Path $out "console.log"

  $matlabCmd = @"
try
    addpath(genpath('$InputDir'.replace('\','/')));
    cd('$($work.FullName)'.replace('\','/'));
    feval('$func');
catch ME
    fid = fopen(fullfile(pwd,'ERROR.txt'),'w');
    fprintf(fid,'%s\n\n%s\n', ME.identifier, getReport(ME,'extended','hyperlinks',false));
    fclose(fid);
end
exit
"@

  & $Matlab -batch $matlabCmd 2>&1 | Tee-Object -FilePath $log

  Get-ChildItem -Path $work.FullName -Force | ForEach-Object {
    Move-Item -LiteralPath $_.FullName -Destination $out -Force
  }
  Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $out $f.Name) -Force
  Remove-Item $work.FullName -Force -Recurse
  Write-Host "Done: $func -> $out"
}
