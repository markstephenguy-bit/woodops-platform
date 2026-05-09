# fix-woodops-solution.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message"
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Backup-File {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $backupRoot = Join-Path (Get-Location) ".woodops-fix-backups"
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $relative = Resolve-Path -LiteralPath $Path | ForEach-Object {
        $_.Path.Substring((Get-Location).Path.Length).TrimStart('\', '/')
    }

    $backupPath = Join-Path $backupRoot "$timestamp\$relative"
    $backupDir = Split-Path -Parent $backupPath

    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
}

function Save-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$repoRoot = Get-Location

# Detect solution root dynamically
$slnx = Get-ChildItem -Recurse -Filter "*.slnx" | Select-Object -First 1

if (-not $slnx) {
    throw "No .slnx file found under $repoRoot"
}

$solutionRoot = $slnx.Directory.FullName
$slnxPath = $slnx.FullName

Write-Info "Detected solution root: $solutionRoot"

if (-not (Test-Path -LiteralPath $slnxPath)) {
    throw "Expected solution file not found: $slnxPath"
}

Write-Info "Repository root: $repoRoot"
Write-Info "Solution root: $solutionRoot"

# 1. Fix Processing Dockerfile entrypoint.
$processingDockerfile = Join-Path $solutionRoot "src\Hosts\WoodOps.Host.Processing\Dockerfile"
if (Test-Path -LiteralPath $processingDockerfile) {
    Backup-File $processingDockerfile
    $content = Get-Content -LiteralPath $processingDockerfile -Raw
    $updated = $content.Replace(
        'ENTRYPOINT ["dotnet", "WoodOps.Host.Connectors.dll"]',
        'ENTRYPOINT ["dotnet", "WoodOps.Host.Processing.dll"]'
    )

    if ($updated -ne $content) {
        Save-Utf8NoBom -Path $processingDockerfile -Content $updated
        Write-Pass "Fixed Processing Dockerfile entrypoint"
    }
    else {
        Write-Info "Processing Dockerfile entrypoint did not require change"
    }
}
else {
    Write-Fail "Processing Dockerfile not found"
}

# 2. Remove TargetFramework from Portal csproj.
$portalCsproj = Join-Path $solutionRoot "src\Hosts\WoodOps.Host.Portal\WoodOps.Host.Portal.csproj"
if (Test-Path -LiteralPath $portalCsproj) {
    Backup-File $portalCsproj
    [xml]$xml = Get-Content -LiteralPath $portalCsproj -Raw

    $changed = $false
    foreach ($propertyGroup in $xml.Project.PropertyGroup) {
        $nodes = $propertyGroup.SelectNodes("TargetFramework")
foreach ($node in $nodes) {
    $propertyGroup.RemoveChild($node) | Out-Null
    $changed = $true
}
    }

    if ($changed) {
        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Indent = $true
        $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

        $writer = [System.Xml.XmlWriter]::Create($portalCsproj, $settings)
        $xml.Save($writer)
        $writer.Close()

        Write-Pass "Removed TargetFramework from Portal csproj"
    }
    else {
        Write-Info "Portal csproj TargetFramework did not require change"
    }
}
else {
    Write-Fail "Portal csproj not found"
}

# 3. Remove duplicate Nullable and ImplicitUsings from csproj files.
$csprojFiles = Get-ChildItem -LiteralPath $solutionRoot -Recurse -Filter "*.csproj" |
    Where-Object { $_.FullName -notmatch "\\bin\\|\\obj\\" }

foreach ($file in $csprojFiles) {
    Backup-File $file.FullName

    [xml]$xml = Get-Content -LiteralPath $file.FullName -Raw
    $changed = $false

    foreach ($propertyGroup in $xml.Project.PropertyGroup) {
        foreach ($name in @("Nullable", "ImplicitUsings")) {
    $nodes = $propertyGroup.SelectNodes($name)
    foreach ($node in $nodes) {
        $propertyGroup.RemoveChild($node) | Out-Null
        $changed = $true
    }
}
    }

    if ($changed) {
        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Indent = $true
        $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

        $writer = [System.Xml.XmlWriter]::Create($file.FullName, $settings)
        $xml.Save($writer)
        $writer.Close()

        Write-Pass "Removed inherited build properties from $($file.FullName.Substring($solutionRoot.Length + 1))"
    }
}

# 4. Add controller-based API health endpoint.
$controllersDir = Join-Path $solutionRoot "src\Hosts\WoodOps.Host.Api\Controllers"
$healthController = Join-Path $controllersDir "HealthController.cs"

New-Item -ItemType Directory -Force -Path $controllersDir | Out-Null

if (-not (Test-Path -LiteralPath $healthController)) {
    $healthControllerContent = @'
using Microsoft.AspNetCore.Mvc;

namespace WoodOps.Host.Api.Controllers;

[ApiController]
[Route("health")]
public sealed class HealthController : ControllerBase
{
    [HttpGet]
    public IActionResult Get()
    {
        return Ok(new
        {
            status = "healthy",
            service = "WoodOps.Host.Api"
        });
    }
}
'@

    Save-Utf8NoBom -Path $healthController -Content $healthControllerContent
    Write-Pass "Added API HealthController"
}
else {
    Write-Info "HealthController already exists"
}

# 5. Add Placeholder.cs to deferred projects.
$deferredProjects = @(
    @{
        Path = "src\Infrastructure\WoodOps.Graph"
        Namespace = "WoodOps.Graph"
    },
    @{
        Path = "src\Infrastructure\WoodOps.Retrieval"
        Namespace = "WoodOps.Retrieval"
    },
    @{
        Path = "src\Processing\WoodOps.Projection"
        Namespace = "WoodOps.Projection"
    },
    @{
        Path = "src\AI\WoodOps.Intelligence"
        Namespace = "WoodOps.Intelligence"
    }
)

foreach ($project in $deferredProjects) {
    $projectDir = Join-Path $solutionRoot $project.Path
    $placeholderPath = Join-Path $projectDir "Placeholder.cs"

    if (-not (Test-Path -LiteralPath $projectDir)) {
        Write-Fail "Deferred project directory not found: $($project.Path)"
        continue
    }

    if (-not (Test-Path -LiteralPath $placeholderPath)) {
        $placeholderContent = @"
namespace $($project.Namespace);

// Deferred — not implemented in this phase.
"@

        Save-Utf8NoBom -Path $placeholderPath -Content $placeholderContent
        Write-Pass "Added Placeholder.cs to $($project.Path)"
    }
    else {
        Write-Info "Placeholder already exists in $($project.Path)"
    }
}

# 6. Remove empty root-level Directory.Packages.props only if truly empty.
$rootPackagesProps = Join-Path $repoRoot "Directory.Packages.props"
$innerPackagesProps = Join-Path $solutionRoot "Directory.Packages.props"

if ((Test-Path -LiteralPath $rootPackagesProps) -and (Test-Path -LiteralPath $innerPackagesProps)) {
    $rootItem = Get-Item -LiteralPath $rootPackagesProps
    if ($rootItem.Length -eq 0) {
        Backup-File $rootPackagesProps
        Remove-Item -LiteralPath $rootPackagesProps -Force
        Write-Pass "Removed empty root-level Directory.Packages.props"
    }
    else {
        Write-Info "Root-level Directory.Packages.props is not empty; left unchanged"
    }
}

# 7. Build solution.
Push-Location $solutionRoot
try {
    Write-Info "Running dotnet build"
    dotnet build .\woodops-platform.slnx

    if ($LASTEXITCODE -eq 0) {
        Write-Pass "dotnet build succeeded"
    }
    else {
        Write-Fail "dotnet build failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}
finally {
    Pop-Location
}

Write-Pass "WoodOps solution mechanical cleanup complete"