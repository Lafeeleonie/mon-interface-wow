[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$repoParent = Split-Path -Parent $repoRoot
$wowRoot = if (Test-Path -LiteralPath (Join-Path $repoParent "Wow.exe")) {
    $repoParent
} else {
    Join-Path $repoParent "_retail_"
}
$sourceInterface = Join-Path $wowRoot "Interface"
$sourceWtf = Join-Path $wowRoot "WTF"

if (-not (Test-Path -LiteralPath (Join-Path $wowRoot "Wow.exe"))) {
    throw "Installation WoW Retail introuvable. Placez le dépôt à côté de _retail_."
}

if (Get-Process -Name "Wow", "WowClassic" -ErrorAction SilentlyContinue) {
    throw "World of Warcraft est ouvert. Fermez le jeu avant de construire la version publique."
}

function Remove-TreeIfPresent {
    param([Parameter(Mandatory)] [string] $Path)

    if (Test-Path -LiteralPath $Path) {
        $resolvedRepo = [IO.Path]::GetFullPath($repoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $resolvedTarget = [IO.Path]::GetFullPath($Path)
        if (-not $resolvedTarget.StartsWith($resolvedRepo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Suppression refusée hors du dépôt : $resolvedTarget"
        }
        Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
    }
}

function Copy-PublicAddons {
    $destination = Join-Path $repoRoot "Interface"
    Remove-TreeIfPresent -Path $destination
    New-Item -ItemType Directory -Path $destination -Force | Out-Null

    $excludedDirectories = @(
        ".git",
        (Join-Path $sourceInterface "AddOns\RaiderIO\db"),
        (Join-Path $sourceInterface "AddOns\ArchonTooltip\DB"),
        (Join-Path $sourceInterface "AddOns\Lafee_music_player"),
        (Join-Path $sourceInterface "AddOns\CustomLust")
    )

    $roboArgs = @(
        $sourceInterface,
        $destination,
        "/E",
        "/R:2",
        "/W:1",
        "/COPY:DAT",
        "/DCOPY:DAT",
        "/XJ",
        "/NP",
        "/NFL",
        "/NDL",
        "/XF", "*.bak", "*.old", "*.tmp", "*.temp",
        "/XD"
    ) + $excludedDirectories

    & robocopy @roboArgs
    if ($LASTEXITCODE -ge 8) {
        throw "Robocopy a échoué pendant la copie des addons (code $LASTEXITCODE)."
    }
}

function Get-PublicSavedVariableNames {
    @(
        "AddOnSkins.lua",
        "AdiBags.lua",
        "Baggins.lua",
        "BetterBags.lua",
        "BetterCooldownManager.lua",
        "BigWigs.lua",
        "Clique.lua",
        "CooldownManagerCentered.lua",
        "DandersFrames.lua",
        "DBM-Core.lua",
        "DBM-StatusBarTimers.lua",
        "Decursive.lua",
        "DynamicCam.lua",
        "ElvUI.lua",
        "ElvUI_SLE.lua",
        "FarmHud.lua",
        "FishingBuddy.lua",
        "FrameSort.lua",
        "GTFO.lua",
        "MikScrollingBattleText.lua",
        "MythicDungeonTools.lua",
        "NephUI.lua",
        "NPCScan.lua",
        "OmniCC.lua",
        "OmniCD.lua",
        "Pawn.lua",
        "Plater.lua",
        "PremadeGroupsFilter.lua",
        "RareScanner.lua",
        "TalentLoadoutManager.lua",
        "TalentTreeTweaks.lua",
        "TomTom.lua",
        "WarpDeplete.lua",
        "WeakAuras.lua",
        "WeakAurasOptions.lua",
        "ls_Glass.lua"
    )
}

function Add-Replacement {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[object]] $List,
        [Parameter(Mandatory)] [string] $Original,
        [Parameter(Mandatory)] [string] $Replacement
    )

    if (-not [string]::IsNullOrWhiteSpace($Original)) {
        $List.Add([pscustomobject]@{ Original = $Original; Replacement = $Replacement })
    }
}

function Redact-TextFile {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [System.Collections.Generic.List[object]] $LiteralReplacements
    )

    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

    foreach ($item in ($LiteralReplacements | Sort-Object { $_.Original.Length } -Descending)) {
        $text = [regex]::Replace(
            $text,
            [regex]::Escape($item.Original),
            [System.Text.RegularExpressions.MatchEvaluator] { param($match) $item.Replacement },
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }

    $text = [regex]::Replace($text, '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', 'redacted@example.invalid')
    $text = [regex]::Replace($text, '(?i)\b[\p{L}\p{N}_-]{2,24}#\d{4,10}\b', 'BattleTag#0000')
    $text = [regex]::Replace($text, '(?i)https://(?:canary\.|ptb\.)?discord(?:app)?\.com/api/webhooks/[^\s"'']+', 'https://discord.invalid/webhook/REDACTED')
    $text = [regex]::Replace($text, '(?i)\b(?:Player|Account|BattlePet|Creature|Pet|GameObject|Vehicle)-[0-9A-F-]{6,}\b', 'REDACTED-GUID')
    $text = [regex]::Replace($text, '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])', '0.0.0.0')
    $text = [regex]::Replace($text, '(?i)C:\\Users\\[^\\\s"'']+', 'C:\Users\USER')
    $text = [regex]::Replace($text, '\b\d{17,20}\b', '000000000000000000')
    $text = [regex]::Replace(
        $text,
        '(?im)((?:api[_-]?key|access[_-]?token|auth[_-]?token|password|passwd|client[_-]?secret)\s*["'']?\s*\]?\s*=\s*["''])[^"''\r\n]+',
        '${1}REDACTED'
    )

    Set-Content -LiteralPath $Path -Value $text -Encoding UTF8 -NoNewline
}

function Copy-SanitizedSettings {
    $destinationWtf = Join-Path $repoRoot "WTF"
    Remove-TreeIfPresent -Path $destinationWtf

    $sourceAccountRoot = Join-Path $sourceWtf "Account"
    $sourceAccount = Get-ChildItem -LiteralPath $sourceAccountRoot -Directory |
        Where-Object Name -ne "SavedVariables" |
        Select-Object -First 1

    if (-not $sourceAccount) {
        throw "Aucun compte WoW trouvé dans $sourceAccountRoot."
    }

    $sourceSavedVariables = Join-Path $sourceAccount.FullName "SavedVariables"
    $destinationSavedVariables = Join-Path $destinationWtf "Account\ACCOUNT\SavedVariables"
    New-Item -ItemType Directory -Path $destinationSavedVariables -Force | Out-Null

    foreach ($name in Get-PublicSavedVariableNames) {
        $source = Join-Path $sourceSavedVariables $name
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $destinationSavedVariables $name)
        }
    }

    $replacements = [System.Collections.Generic.List[object]]::new()
    Add-Replacement -List $replacements -Original $sourceAccount.Name -Replacement "ACCOUNT"

    $realmIndex = 0
    $characterIndex = 0
    foreach ($realm in (Get-ChildItem -LiteralPath $sourceAccount.FullName -Directory | Where-Object Name -ne "SavedVariables" | Sort-Object Name)) {
        $realmIndex++
        Add-Replacement -List $replacements -Original $realm.Name -Replacement ("REALM_{0:D2}" -f $realmIndex)

        foreach ($character in (Get-ChildItem -LiteralPath $realm.FullName -Directory | Sort-Object Name)) {
            $characterIndex++
            Add-Replacement -List $replacements -Original $character.Name -Replacement ("CHARACTER_{0:D2}" -f $characterIndex)
        }
    }

    Get-ChildItem -LiteralPath $destinationWtf -File -Recurse | ForEach-Object {
        Redact-TextFile -Path $_.FullName -LiteralReplacements $replacements
    }

    $settingsReadme = @'
# Réglages assainis

Ce dossier ne contient que des profils d'interface sélectionnés au niveau du compte.

Les dossiers et données propres aux personnages, ainsi que les historiques de discussion, combat, guilde, enchères, macros et erreurs, ont été exclus. Les identifiants personnels détectables ont été remplacés par des valeurs génériques.

Copiez les fichiers voulus dans `WTF/Account/<votre-compte>/SavedVariables` avec WoW fermé. Gardez une sauvegarde de vos propres réglages avant de les remplacer.
'@
    Set-Content -LiteralPath (Join-Path $destinationWtf "README.md") -Value $settingsReadme -Encoding UTF8
}

Copy-PublicAddons
Copy-SanitizedSettings
Remove-TreeIfPresent -Path (Join-Path $repoRoot "Fonts")
& (Join-Path $repoRoot "Update-Addon-Catalog.ps1")

Write-Host "Version publique reconstruite et assainie. Vérifiez les changements avec : git status"
