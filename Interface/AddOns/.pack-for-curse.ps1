$ErrorActionPreference = 'Stop'

$Source = $env:CURSE_SOURCE
if ([string]::IsNullOrWhiteSpace($Source)) {
    throw 'Le dossier source de l''addon est introuvable.'
}

$Source = (Get-Item -LiteralPath $Source).FullName.TrimEnd([char]'\')
$Name = Split-Path -Path $Source -Leaf
$Output = Join-Path -Path $Source -ChildPath ($Name + '.zip')
$Temp = Join-Path -Path $env:TEMP -ChildPath ('curse-package-' + [guid]::NewGuid())
$Stage = Join-Path -Path $Temp -ChildPath $Name

try {
    New-Item -ItemType Directory -Path $Stage -Force | Out-Null

    Get-ChildItem -LiteralPath $Source -Force -Recurse -File | Where-Object {
        $relative = $_.FullName.Substring($Source.Length).TrimStart([char]'\')
        $parts = $relative -split '[\\/]'
        ($parts -notcontains '.git') -and
        ($parts -notcontains '.github') -and
        ($parts -notcontains '.agents') -and
        ($parts -notcontains '.codex') -and
        ($parts -notcontains '.vscode') -and
        ($_.Name -notlike 'README*') -and
        ($_.Name -notlike '*.bat') -and
        ($_.Name -notlike '*.zip')
    } | ForEach-Object {
        $relative = $_.FullName.Substring($Source.Length).TrimStart([char]'\')
        $destination = Join-Path -Path $Stage -ChildPath $relative
        New-Item -ItemType Directory -Path (Split-Path -Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
    }

    if (Test-Path -LiteralPath $Output) {
        Remove-Item -LiteralPath $Output -Force
    }
    Compress-Archive -LiteralPath $Stage -DestinationPath $Output -Force
    Write-Host "Archive créée : $Output"
}
finally {
    if (Test-Path -LiteralPath $Temp) {
        Remove-Item -LiteralPath $Temp -Recurse -Force
    }
}
