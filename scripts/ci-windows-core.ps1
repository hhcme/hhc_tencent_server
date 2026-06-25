$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$testProject = Join-Path $repoRoot "HHCServerManager.Windows/tests/HHCServerManager.Windows.Tests/HHCServerManager.Windows.Tests.csproj"

dotnet --info
dotnet test $testProject --configuration Release --nologo
