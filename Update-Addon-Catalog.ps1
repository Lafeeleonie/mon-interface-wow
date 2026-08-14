[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$addonsRoot = Join-Path $repoRoot "Interface\AddOns"
$readmePath = Join-Path $repoRoot "README.md"

if (-not (Test-Path -LiteralPath $addonsRoot)) {
    throw "Dossier d'addons introuvable : $addonsRoot"
}

function Get-CleanMetadataText {
    param([AllowNull()] [string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return ($Value `
        -replace '\|c[0-9A-Fa-f]{8}', '' `
        -replace '\|r', '' `
        -replace '\|T[^|]+\|t', '' `
        -replace '\|n', ' ' `
        -replace '\s+', ' ').Trim()
}

function ConvertTo-MarkdownCell {
    param([AllowNull()] [string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "—"
    }

    return $Value.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
}

function Get-AddonCategory {
    param([Parameter(Mandatory)] [string] $Folder)

    switch -Regex ($Folder) {
        '^(?i:lafee|__recap)' {
            return "Addons personnels"
        }
        '^(?i:AddOnSkins|BetterCooldownManager|ElvUI|MiniAuras|MiniCC|Plater|WIM_ElvUI_Skin)' {
            return "Interface et affichage"
        }
        '^(?i:ArchonTooltip|DBM-|Decursive|Details|EXBoss|EXBOSS-|ExwindCore|LoggerHeadLite|MDTHelper|MonkStaggerBarPrime|MPlusMarker|MRT|MythicDungeonTools|MythicPlusPullReEstimated|Oilvl|PetAlert|RaiderIO|Simulationcraft|WarpDeplete)' {
            return "Combat, donjons et raids"
        }
        '^(?i:Auctionator|BetterBags|BetterFishing|FarmHud|KeystoneLoot|MajesticBeastTracker|MyusKnowledgePointsTracker|SimpleDisenchant|Vaultloom)' {
            return "Sacs, économie et collections"
        }
        default {
            return "Confort et outils"
        }
    }
}

function Get-PrimaryToc {
    param([Parameter(Mandatory)] [System.IO.DirectoryInfo] $Directory)

    $tocFiles = @(Get-ChildItem -LiteralPath $Directory.FullName -File -Filter "*.toc" -ErrorAction SilentlyContinue)
    $toc = $tocFiles | Where-Object BaseName -EQ $Directory.Name | Select-Object -First 1

    if (-not $toc) {
        $toc = $tocFiles | Where-Object Name -Match '(?i)(_Mainline|_Retail)\.toc$' | Select-Object -First 1
    }

    if (-not $toc) {
        $toc = $tocFiles | Select-Object -First 1
    }

    return $toc
}

$addons = foreach ($directory in (Get-ChildItem -LiteralPath $addonsRoot -Directory -Force | Sort-Object Name)) {
    $toc = Get-PrimaryToc -Directory $directory
    $metadata = @{}

    if ($toc) {
        foreach ($line in (Get-Content -LiteralPath $toc.FullName -ErrorAction SilentlyContinue)) {
            if ($line -match '^##\s*([^:]+):\s*(.*)$') {
                $metadata[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
    }

    $title = if ($metadata["Title-frFR"]) {
        $metadata["Title-frFR"]
    } elseif ($metadata["Title"]) {
        $metadata["Title"]
    } else {
        $directory.Name
    }

    $description = if ($metadata["Notes-frFR"]) {
        $metadata["Notes-frFR"]
    } elseif ($metadata["Notes"]) {
        $metadata["Notes"]
    } elseif ($toc) {
        "Module ou extension de $(Get-CleanMetadataText -Value $title)."
    } else {
        "Dossier auxiliaire sans fichier TOC."
    }

    [pscustomobject]@{
        Folder = $directory.Name
        Title = Get-CleanMetadataText -Value $title
        Description = Get-CleanMetadataText -Value $description
        Version = Get-CleanMetadataText -Value $metadata["Version"]
        Author = Get-CleanMetadataText -Value $(if ($metadata["Author"]) { $metadata["Author"] } else { $metadata["Authors"] })
        Category = Get-AddonCategory -Folder $directory.Name
        HasToc = [bool] $toc
    }
}

$categoryOrder = @(
    "Addons personnels",
    "Interface et affichage",
    "Combat, donjons et raids",
    "Sacs, économie et collections",
    "Confort et outils"
)

$catalogAddons = @($addons | Where-Object { $_.Folder -notmatch '^(?i:RaiderIO)' })

$builder = [System.Text.StringBuilder]::new()
$moduleCount = @($catalogAddons | Where-Object HasToc).Count
$auxiliaryCount = $catalogAddons.Count - $moduleCount

[void] $builder.AppendLine("Ce catalogue référence **$($catalogAddons.Count) dossiers**, dont **$moduleCount modules WoW détectés** par leur fichier ``.toc``.")
if ($auxiliaryCount -gt 0) {
    if ($auxiliaryCount -eq 1) {
        [void] $builder.AppendLine("Le **dossier auxiliaire** sans ``.toc`` est également indiqué pour que l'inventaire reste exhaustif.")
    } else {
        [void] $builder.AppendLine("Les **$auxiliaryCount dossiers auxiliaires** sans ``.toc`` sont également indiqués pour que l'inventaire reste exhaustif.")
    }
}
[void] $builder.AppendLine()
[void] $builder.AppendLine("Les descriptions et versions proviennent directement des métadonnées installées ; leur langue peut donc varier selon l'addon.")
[void] $builder.AppendLine()

foreach ($category in $categoryOrder) {
    $items = @($catalogAddons | Where-Object Category -EQ $category | Sort-Object Title, Folder)
    if ($items.Count -eq 0) {
        continue
    }

    [void] $builder.AppendLine("<details>")
    [void] $builder.AppendLine("<summary><strong>$category</strong> — $($items.Count) dossier(s)</summary>")
    [void] $builder.AppendLine()
    [void] $builder.AppendLine("| Addon | Version | Auteur | Présentation |")
    [void] $builder.AppendLine("|---|---:|---|---|")

    foreach ($addon in $items) {
        $encodedFolder = [Uri]::EscapeDataString($addon.Folder)
        $titleCell = ConvertTo-MarkdownCell -Value $addon.Title
        $folderCell = ConvertTo-MarkdownCell -Value $addon.Folder
        $versionCell = ConvertTo-MarkdownCell -Value $addon.Version
        $authorCell = ConvertTo-MarkdownCell -Value $addon.Author
        $descriptionCell = ConvertTo-MarkdownCell -Value $addon.Description
        [void] $builder.AppendLine("| [$titleCell](Interface/AddOns/$encodedFolder)<br><sub>$folderCell</sub> | $versionCell | $authorCell | $descriptionCell |")
    }

    [void] $builder.AppendLine()
    [void] $builder.AppendLine("</details>")
    [void] $builder.AppendLine()
}

$readme = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8
$startMarker = "<!-- ADDON_CATALOG_START -->"
$endMarker = "<!-- ADDON_CATALOG_END -->"
$pattern = [regex]::Escape($startMarker) + '.*?' + [regex]::Escape($endMarker)

if (-not [regex]::IsMatch($readme, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
    throw "Marqueurs du catalogue introuvables dans README.md."
}

$replacement = $startMarker + "`r`n" + $builder.ToString().TrimEnd() + "`r`n" + $endMarker
$updatedReadme = [regex]::Replace($readme, $pattern, [System.Text.RegularExpressions.MatchEvaluator] { param($match) $replacement }, [System.Text.RegularExpressions.RegexOptions]::Singleline)

if ($updatedReadme -NE $readme) {
    Set-Content -LiteralPath $readmePath -Value $updatedReadme -Encoding UTF8 -NoNewline
}

Write-Host "Catalogue mis à jour : $($catalogAddons.Count) dossiers, $moduleCount modules WoW."
