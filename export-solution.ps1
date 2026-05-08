# export-solution.ps1
param(
    [string]$OutputFile = "solution_export_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
)

$includeExtensions = @(
    "*.cs", "*.razor", "*.cshtml",
    "*.csproj", "*.fsproj", "*.vbproj",
    "*.sln", "*.slnx",
    "*.json", "*.jsonl",
    "*.config", "*.conf", "*.cfg", "*.ini",
    "*.xml", "*.xsd", "*.xsl",
    "*.ps1", "*.psm1", "*.psd1",
    "*.md", "*.txt",
    "*.yaml", "*.yml", "*.toml",
    "*.sh", "*.bash", "*.zsh",
    "*.sql",
    "*.props", "*.targets", "*.editorconfig",
    "*.env", "*.env.*",
    "*.example", "*.sample",
    "*.csv", "*.tsv",
    "*.html", "*.css", "*.js", "*.ts", "*.tsx"
)

# Include important files with no extension or special names
$includeFileNames = @(
    "Dockerfile",
    "Dockerfile.*",
    ".gitignore",
    ".gitattributes",
    ".dockerignore",
    ".editorconfig",
    ".env",
    ".env.*",
    "Makefile",
    "makefile",
    "docker-compose.yml",
    "docker-compose.*.yml"
)

$excludeDirs = @(
    "bin", "obj", ".vs", ".git", "node_modules", "packages",
    ".idea", ".vscode", "TestResults", "artifacts"
)

$excludeFiles = @(
    "solution_export_*.txt"
)

$rootPath = (Get-Location).Path

function Test-IsExcludedDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullName,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    foreach ($exDir in $excludeDirs) {
        if ($Name -ieq $exDir) {
            return $true
        }

        if ($FullName -like "*\$exDir\*" -or $FullName -like "*/$exDir/*") {
            return $true
        }
    }

    return $false
}

function Test-IsExcludedFile {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )

    foreach ($exDir in $excludeDirs) {
        if ($File.FullName -like "*\$exDir\*" -or $File.FullName -like "*/$exDir/*") {
            return $true
        }
    }

    foreach ($exFile in $excludeFiles) {
        if ($File.Name -like $exFile) {
            return $true
        }
    }

    return $false
}

function Test-IsIncludedFile {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )

    foreach ($pattern in $includeExtensions) {
        if ($File.Name -like $pattern) {
            return $true
        }
    }

    foreach ($pattern in $includeFileNames) {
        if ($File.Name -like $pattern) {
            return $true
        }
    }

    return $false
}

$output = @()
$output += "=== SOLUTION EXPORT ==="
$output += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$output += "Root: $rootPath"
$output += ""
$output += "=== DIRECTORY STRUCTURE ==="
$output += ""

# Include root marker
$output += "[ROOT] $(Split-Path $rootPath -Leaf)"

# All directories including empty
Get-ChildItem -Path $rootPath -Recurse -Directory -Force |
    Where-Object {
        -not (Test-IsExcludedDirectory -FullName $_.FullName -Name $_.Name)
    } |
    Sort-Object FullName |
    ForEach-Object {
        $relativePath = $_.FullName.Substring($rootPath.Length + 1)
        $depth = ($relativePath -split '[\\/]').Count

        # True empty folder = no immediate children after exclusions
        $visibleChildren = Get-ChildItem -LiteralPath $_.FullName -Force | Where-Object {
            if ($_.PSIsContainer) {
                -not (Test-IsExcludedDirectory -FullName $_.FullName -Name $_.Name)
            }
            else {
                -not (Test-IsExcludedFile -File $_)
            }
        }

        $isEmpty = @($visibleChildren).Count -eq 0
        $marker = if ($isEmpty) { "[DIR-EMPTY]" } else { "[DIR]" }

        $output += ("  " * $depth) + "$marker $($_.Name)"
    }

$output += ""
$output += "=== FILES ==="
$output += ""

# Collect matching files
Get-ChildItem -Path $rootPath -Recurse -File -Force |
    Where-Object {
        -not (Test-IsExcludedFile -File $_) -and (Test-IsIncludedFile -File $_)
    } |
    Sort-Object FullName |
    ForEach-Object {
        $relativePath = $_.FullName.Substring($rootPath.Length + 1)

        $output += ""
        $output += "========================================"
        $output += "FILE: $relativePath"
        $output += "SIZE: $($_.Length) bytes"
        $output += "MODIFIED: $($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
        $output += "========================================"

        try {
            $content = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop
            $output += $content
        }
        catch {
            $output += "[ERROR READING FILE] $($_.Exception.Message)"
        }
    }

$output | Out-File -FilePath $OutputFile -Encoding UTF8
Write-Host "Exported to: $OutputFile"
Write-Host "File count: $(($output | Select-String -Pattern '^FILE:').Matches.Count)"