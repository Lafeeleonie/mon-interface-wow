local f = CreateFrame("Frame")
local DB
local MainUI
local HPUI
local PassiveUI
local PetHealthBar
local MinimapButton
local inCombat = false
local isMovingMain = false
local isMovingHP = false
local isMovingPassive = false
local hpAlphaCurve = nil
local OpenPetAlertOptions
local previewToken = 0

local function IsFramePreviewing(ui)
    return ui and ui._petAlertMode == "preview" and ui._petAlertPreviewToken == previewToken
end

PetAlert = PetAlert or {}

-- =========================
-- Defaults
-- =========================

local DEFAULTS = {
    point = "CENTER",
    x = 0,
    y = 0,

    hpPoint = "CENTER",
    hpX = 160,
    hpY = 0,

    passivePoint = "CENTER",
    passiveX = -160,
    passiveY = 0,

    missingAlertEnabled = true,
    lowHPAlertEnabled = true,
    passiveAlertEnabled = true,
    lowHPThreshold = 25,
    alertsOutOfCombat = false,
    audioAlertEnabled = false,
    audioAlertSound = "RAID_WARNING",
    minimalMode = false,
    customIconEnabled = false,
    customIcon = "",
    minimapButtonEnabled = true,
    minimapButtonAngle = 225,
    minimapButtonLocked = false,
    petHealthBarEnabled = false,
    petHealthBarX = 0,
    petHealthBarY = -128,
    petHealthBarWidth = 168,
    petHealthBarHeight = 16,
    petHealthBarR = 0.29,
    petHealthBarG = 0.90,
    petHealthBarB = 0.42,
    petHealthBarTheme = "emerald",
    petHealthBarTexture = "raid",
    petHealthBarFrameStyle = "glass",
    petHealthBarShowIcon = true,
    petHealthBarShowPercent = true,
    petHealthBarShowShine = true,
    petHealthBarBgAlpha = 88,
    petHealthBarBorderAlpha = 85,

    mainSize = 140,
    hpSize = 140,
    passiveSize = 140,
}

-- =========================
-- Localization
-- =========================

local LOCALIZED_ALERTS = {
    WARLOCK = {
        enUS = "FELGUARD !",
        enGB = "FELGUARD !",
        frFR = "GANGREGARDE !",
        deDE = "TEUFELSWACHE !",
        esES = "GUARDIA VIL !",
        esMX = "GUARDIA VIL !",
        itIT = "FELGUARDIA !",
        ruRU = "ГНЕВНЫЙ СТРАЖ !",
        koKR = "지옥수호병 !",
        zhCN = "恶魔卫士 !",
        zhTW = "惡魔守衛 !",
    },
    DEATHKNIGHT = {
        enUS = "GHOUL !",
        enGB = "GHOUL !",
        frFR = "GOULE !",
        deDE = "GHUL !",
        esES = "NECRÓFAGO !",
        esMX = "NECRÓFAGO !",
        itIT = "GHOUL !",
        ruRU = "ГУЛЬ !",
        koKR = "구울 !",
        zhCN = "食尸鬼 !",
        zhTW = "食屍鬼 !",
    },
    HUNTER = {
        enUS = "PET !",
        enGB = "PET !",
        frFR = "FAMILIER !",
        deDE = "BEGLEITER !",
        esES = "MASCOTA !",
        esMX = "MASCOTA !",
        itIT = "PET !",
        ruRU = "ПИТОМЕЦ !",
        koKR = "야수 !",
        zhCN = "宠物 !",
        zhTW = "寵物 !",
    },
    MAGE = {
        enUS = "ELEMENTAL !",
        enGB = "ELEMENTAL !",
        frFR = "ÉLÉMENTAIRE !",
        deDE = "ELEMENTAR !",
        esES = "ELEMENTAL !",
        esMX = "ELEMENTAL !",
        itIT = "ELEMENTALE !",
        ruRU = "ЭЛЕМЕНТАЛЬ !",
        koKR = "정령 !",
        zhCN = "元素 !",
        zhTW = "元素 !",
    },
    LOW_HP = {
        enUS = "LOW PET HP !",
        enGB = "LOW PET HP !",
        frFR = "PV DU FAMILIER FAIBLES !",
        deDE = "WENIG BEGLEITER-LEBEN !",
        esES = "¡POCA VIDA DE LA MASCOTA!",
        esMX = "¡POCA VIDA DE LA MASCOTA!",
        itIT = "PET CON POCA VITA !",
        ruRU = "МАЛО ЗДОРОВЬЯ У ПИТОМЦА !",
        koKR = "소환수 생명력 낮음 !",
        zhCN = "宠物血量过低 !",
        zhTW = "寵物血量過低 !",
    },
    PASSIVE = {
        enUS = "PET PASSIVE !",
        enGB = "PET PASSIVE !",
        frFR = "FAMILIER PASSIF !",
        deDE = "BEGLEITER PASSIV !",
        esES = "¡MASCOTA PASIVA!",
        esMX = "¡MASCOTA PASIVA!",
        itIT = "PET PASSIVO !",
        ruRU = "ПИТОМЕЦ ПАССИВНЫЙ !",
        koKR = "소환수 수동 !",
        zhCN = "宠物被动 !",
        zhTW = "寵物被動 !",
    },
}

local function GetPlayerLocale()
    if GetLocale then
        return GetLocale()
    end
    return "enUS"
end

local function GetLocalizedAlertText(classTag)
    local locale = GetPlayerLocale()
    local classTable = LOCALIZED_ALERTS[classTag]
    if classTable then
        return classTable[locale] or classTable.enUS
    end
    return "PET !"
end

local LOCALIZED_UI = {
    enUS = {
        optionsNotReady = "options are not ready yet. Try /reload or /pa.",
        minimapTooltipOpen = "Left-click: Open options",
        minimapTooltipUnlock = "Right-click: Unlock position",
        minimapTooltipDrag = "Drag: Move around the minimap",
        minimapTooltipLock = "Right-click: Lock position",
        minimapMsgLocked = "minimap button locked.",
        minimapMsgUnlocked = "minimap button unlocked.",
        minimapMsgEnabled = "minimap button enabled.",
        minimapMsgDisabled = "minimap button disabled.",
        minimapMsgReset = "minimap button reset.",
        customIconReset = "custom icon reset.",
        customIconSet = "custom icon set to: %s",
        commandsHeader = "commands:",
        soundRaidWarning = "Raid Warning",
        soundReadyCheck = "Ready Check",
        soundAlarmClock = "Alarm Clock",
        soundPvpQueue = "PvP Queue",
        soundLevelUp = "Level Up",
        presetApplied = "%s preset applied.",
        previewStopped = "alert preview stopped.",
        heroSubtitle = "Premium combat pet alert console",
        badgeMissing = "MISSING",
        badgeLowHP = "LOW HP",
        badgePassive = "PASSIVE",
        globalTitle = "Control Surface",
        globalSubtitle = "Global alert behavior, sound, and visual identity.",
        behaviorTitle = "Behavior",
        alertsOutOfCombat = "Enable alerts out of combat",
        minimalMode = "Minimal icon-only alerts",
        petHealthBarTitle = "Pet Health Bar",
        petHealthBarEnable = "Show pet health bar",
        petHealthBarPreview = "Preview Bar",
        petHealthBarPreviewHide = "Hide Preview",
        petHealthBarDragHint = "Preview: drag to move. In combat: Shift+Drag.",
        petHealthBarWidth = "Bar Width",
        petHealthBarHeight = "Bar Height",
        petHealthBarRed = "Bar Red",
        petHealthBarGreen = "Bar Green",
        petHealthBarBlue = "Bar Blue",
        petHealthBarThemes = "Bar Themes",
        petHealthBarTextures = "Bar Texture",
        petHealthBarThemeEmerald = "Emerald",
        petHealthBarThemeArcane = "Arcane",
        petHealthBarThemeInferno = "Inferno",
        petHealthBarThemeFrost = "Frost",
        petHealthBarTextureRaid = "Raid",
        petHealthBarTextureStatus = "Status",
        petHealthBarTextureFlat = "Flat",
        petHealthBarStyles = "Frame Style",
        petHealthBarStyleGlass = "Glass",
        petHealthBarStyleTactical = "Tactical",
        petHealthBarStyleMinimal = "Minimal",
        petHealthBarStyleNeon = "Neon",
        petHealthBarDisplay = "Display",
        petHealthBarShowIcon = "Show icon",
        petHealthBarShowPercent = "Show percent",
        petHealthBarShowShine = "Show shine",
        petHealthBarBgAlpha = "Background",
        petHealthBarBorderAlpha = "Border",
        audioTitle = "Audio",
        enableAudio = "Enable audio alert",
        previous = "Previous",
        next = "Next",
        testSound = "Test",
        identityTitle = "Visual Identity",
        chooseIcon = "Choose Icon",
        automaticIcon = "Automatic",
        automaticClassIcon = "Automatic class icon",
        customIconPrefix = "Custom icon: %s",
        minimapTitle = "Minimap Shortcut",
        minimapBadge = "MINIMAP",
        showMinimap = "Show minimap button",
        lockMinimap = "Lock minimap position",
        resetPosition = "Reset Position",
        minimapWait = "Waiting for saved settings.",
        minimapHidden = "Hidden from the minimap. Saved position is kept.",
        minimapVisibleLocked = "Visible on the minimap, position locked.",
        minimapVisibleUnlocked = "Visible on the minimap, drag to reposition.",
        livePreview = "Live Preview",
        position = "Position",
        move = "Move",
        lock = "Lock",
        reset = "Reset",
        iconSize = "Icon Size",
        mainKicker = "Primary Alert",
        mainTitle = "Missing Pet Alert",
        mainDesc = "Warns when the monitored character has no active living combat pet.",
        mainBadge = "CRITICAL",
        mainEnable = "Enable missing pet alert",
        hpKicker = "Health Alert",
        hpTitle = "Low HP Alert",
        hpDesc = "Warns when the active pet drops under the configured health threshold.",
        hpBadge = "THRESHOLD",
        hpEnable = "Enable low HP alert",
        hpThreshold = "Low HP Threshold (%)",
        passiveKicker = "Command Alert",
        passiveTitle = "Passive Mode Alert",
        passiveDesc = "Warns when the active pet is left in Passive mode during alert conditions.",
        passiveBadge = "COMMAND",
        passiveEnable = "Alert when pet is in Passive mode",
        testCenterTitle = "Test Center",
        testCenterSubtitle = "Trigger the real alert frames without changing combat state.",
        testMissing = "Missing",
        testLowHP = "Low HP",
        testPassive = "Passive",
        testSequence = "Sequence",
        testStop = "Stop",
        testReady = "Ready to preview the live alert stack.",
        testShowingMissing = "Previewing missing pet alert.",
        testShowingHP = "Previewing low HP alert.",
        testShowingPassive = "Previewing passive mode alert.",
        testShowingSequence = "Running full alert sequence.",
        testStopped = "Preview stopped.",
        presetsTitle = "Presets",
        presetsSubtitle = "Apply a tuned visual baseline, then adjust details.",
        presetCompact = "Compact",
        presetReadable = "Readable",
        presetStreamer = "Streamer",
        presetMinimal = "Minimal",
        presetAppliedStatus = "%s preset applied. Fine-tune below.",
        iconPickerTitle = "Choose Alert Icon",
        iconPickerSubtitle = "Macro icon pool, applied to all alert previews.",
        close = "Close",
        pageFormat = "Page %d / %d",
        useAutomaticIcon = "Use Automatic Icon",
    },
    frFR = {
        optionsNotReady = "les options ne sont pas encore prêtes. Essaie /reload ou /pa.",
        minimapTooltipOpen = "Clic gauche : ouvrir les options",
        minimapTooltipUnlock = "Clic droit : déverrouiller la position",
        minimapTooltipDrag = "Glisser : déplacer autour de la minimap",
        minimapTooltipLock = "Clic droit : verrouiller la position",
        minimapMsgLocked = "bouton minimap verrouillé.",
        minimapMsgUnlocked = "bouton minimap déverrouillé.",
        minimapMsgEnabled = "bouton minimap activé.",
        minimapMsgDisabled = "bouton minimap désactivé.",
        minimapMsgReset = "bouton minimap réinitialisé.",
        customIconReset = "icône personnalisée réinitialisée.",
        customIconSet = "icône personnalisée définie sur : %s",
        commandsHeader = "commandes :",
        soundRaidWarning = "Alerte de raid",
        soundReadyCheck = "Appel prêt",
        soundAlarmClock = "Alarme",
        soundPvpQueue = "File JcJ",
        soundLevelUp = "Gain de niveau",
        presetApplied = "préréglage %s appliqué.",
        previewStopped = "prévisualisation arrêtée.",
        heroSubtitle = "Console premium d'alertes de familier",
        badgeMissing = "ABSENT",
        badgeLowHP = "PV BAS",
        badgePassive = "PASSIF",
        globalTitle = "Surface de contrôle",
        globalSubtitle = "Comportement global, son et identité visuelle.",
        behaviorTitle = "Comportement",
        alertsOutOfCombat = "Activer les alertes hors combat",
        minimalMode = "Alertes minimales en icône seule",
        petHealthBarTitle = "Barre de vie du familier",
        petHealthBarEnable = "Afficher la barre de vie du familier",
        petHealthBarPreview = "Aperçu barre",
        petHealthBarPreviewHide = "Masquer l'aperçu",
        petHealthBarDragHint = "Aperçu : glisser pour déplacer. En combat : Maj+glisser.",
        petHealthBarWidth = "Largeur barre",
        petHealthBarHeight = "Hauteur barre",
        petHealthBarRed = "Rouge barre",
        petHealthBarGreen = "Vert barre",
        petHealthBarBlue = "Bleu barre",
        petHealthBarThemes = "Thèmes de barre",
        petHealthBarTextures = "Texture de barre",
        petHealthBarThemeEmerald = "Émeraude",
        petHealthBarThemeArcane = "Arcanique",
        petHealthBarThemeInferno = "Infernal",
        petHealthBarThemeFrost = "Givre",
        petHealthBarTextureRaid = "Raid",
        petHealthBarTextureStatus = "Statut",
        petHealthBarTextureFlat = "Plate",
        petHealthBarStyles = "Style de cadre",
        petHealthBarStyleGlass = "Verre",
        petHealthBarStyleTactical = "Tactique",
        petHealthBarStyleMinimal = "Minimal",
        petHealthBarStyleNeon = "Néon",
        petHealthBarDisplay = "Affichage",
        petHealthBarShowIcon = "Afficher l'icône",
        petHealthBarShowPercent = "Afficher le pourcentage",
        petHealthBarShowShine = "Afficher le reflet",
        petHealthBarBgAlpha = "Fond",
        petHealthBarBorderAlpha = "Bordure",
        audioTitle = "Audio",
        enableAudio = "Activer l'alerte sonore",
        previous = "Précédent",
        next = "Suivant",
        testSound = "Tester",
        identityTitle = "Identité visuelle",
        chooseIcon = "Choisir l'icône",
        automaticIcon = "Automatique",
        automaticClassIcon = "Icône automatique de classe",
        customIconPrefix = "Icône personnalisée : %s",
        minimapTitle = "Raccourci minimap",
        minimapBadge = "MINIMAP",
        showMinimap = "Afficher le bouton minimap",
        lockMinimap = "Verrouiller la position minimap",
        resetPosition = "Réinitialiser",
        minimapWait = "En attente des réglages sauvegardés.",
        minimapHidden = "Masqué sur la minimap. La position est conservée.",
        minimapVisibleLocked = "Visible sur la minimap, position verrouillée.",
        minimapVisibleUnlocked = "Visible sur la minimap, glisse pour déplacer.",
        livePreview = "Aperçu live",
        position = "Position",
        move = "Déplacer",
        lock = "Verrouiller",
        reset = "Réinitialiser",
        iconSize = "Taille d'icône",
        mainKicker = "Alerte principale",
        mainTitle = "Familier absent",
        mainDesc = "Avertit quand le personnage surveillé n'a pas de familier de combat vivant.",
        mainBadge = "CRITIQUE",
        mainEnable = "Activer l'alerte familier absent",
        hpKicker = "Alerte santé",
        hpTitle = "PV faibles",
        hpDesc = "Avertit quand le familier actif passe sous le seuil de santé configuré.",
        hpBadge = "SEUIL",
        hpEnable = "Activer l'alerte PV faibles",
        hpThreshold = "Seuil PV faibles (%)",
        passiveKicker = "Alerte ordre",
        passiveTitle = "Mode passif",
        passiveDesc = "Avertit quand le familier actif reste en mode Passif.",
        passiveBadge = "ORDRE",
        passiveEnable = "Alerter quand le familier est en Passif",
        testCenterTitle = "Centre de test",
        testCenterSubtitle = "Déclenche les vraies alertes sans modifier l'état de combat.",
        testMissing = "Absent",
        testLowHP = "PV bas",
        testPassive = "Passif",
        testSequence = "Séquence",
        testStop = "Stop",
        testReady = "Prêt à prévisualiser les alertes réelles.",
        testShowingMissing = "Prévisualisation de l'alerte familier absent.",
        testShowingHP = "Prévisualisation de l'alerte PV faibles.",
        testShowingPassive = "Prévisualisation de l'alerte mode passif.",
        testShowingSequence = "Séquence complète en cours.",
        testStopped = "Prévisualisation arrêtée.",
        presetsTitle = "Préréglages",
        presetsSubtitle = "Applique une base visuelle, puis ajuste les détails.",
        presetCompact = "Compact",
        presetReadable = "Lisible",
        presetStreamer = "Streamer",
        presetMinimal = "Minimal",
        presetAppliedStatus = "Préréglage %s appliqué. Ajuste les détails ci-dessous.",
        iconPickerTitle = "Choisir l'icône d'alerte",
        iconPickerSubtitle = "Bibliothèque d'icônes macro, appliquée aux aperçus.",
        close = "Fermer",
        pageFormat = "Page %d / %d",
        useAutomaticIcon = "Utiliser l'icône automatique",
    },
    deDE = {
        optionsNotReady = "Optionen sind noch nicht bereit. Versuche /reload oder /pa.",
        minimapTooltipOpen = "Linksklick: Optionen öffnen",
        minimapTooltipUnlock = "Rechtsklick: Position entsperren",
        minimapTooltipDrag = "Ziehen: um die Minimap verschieben",
        minimapTooltipLock = "Rechtsklick: Position sperren",
        minimapMsgLocked = "Minimap-Schaltfläche gesperrt.",
        minimapMsgUnlocked = "Minimap-Schaltfläche entsperrt.",
        minimapMsgEnabled = "Minimap-Schaltfläche aktiviert.",
        minimapMsgDisabled = "Minimap-Schaltfläche deaktiviert.",
        minimapMsgReset = "Minimap-Schaltfläche zurückgesetzt.",
        customIconReset = "Benutzerdefiniertes Symbol zurückgesetzt.",
        customIconSet = "Benutzerdefiniertes Symbol gesetzt auf: %s",
        commandsHeader = "Befehle:",
        soundRaidWarning = "Schlachtzugswarnung",
        soundReadyCheck = "Bereitschaftscheck",
        soundAlarmClock = "Alarm",
        soundPvpQueue = "PvP-Warteschlange",
        soundLevelUp = "Stufenaufstieg",
        presetApplied = "Voreinstellung %s angewendet.",
        previewStopped = "Warnvorschau gestoppt.",
        heroSubtitle = "Premium-Konsole für Begleiterwarnungen",
        badgeMissing = "FEHLT",
        badgeLowHP = "WENIG LP",
        badgePassive = "PASSIV",
        globalTitle = "Kontrollfläche",
        globalSubtitle = "Globales Verhalten, Sound und visuelle Identität.",
        behaviorTitle = "Verhalten",
        alertsOutOfCombat = "Warnungen außerhalb des Kampfes aktivieren",
        minimalMode = "Minimale Warnungen nur mit Symbol",
        petHealthBarTitle = "Begleiter-Lebensleiste",
        petHealthBarEnable = "Begleiter-Lebensleiste anzeigen",
        petHealthBarPreview = "Leiste ansehen",
        petHealthBarPreviewHide = "Vorschau ausblenden",
        petHealthBarDragHint = "Vorschau: ziehen zum Verschieben. Im Kampf: Umschalt+Ziehen.",
        petHealthBarWidth = "Leistenbreite",
        petHealthBarHeight = "Leistenhöhe",
        petHealthBarRed = "Rot",
        petHealthBarGreen = "Grün",
        petHealthBarBlue = "Blau",
        petHealthBarThemes = "Leistenthemen",
        petHealthBarTextures = "Leistentextur",
        petHealthBarThemeEmerald = "Smaragd",
        petHealthBarThemeArcane = "Arkan",
        petHealthBarThemeInferno = "Inferno",
        petHealthBarThemeFrost = "Frost",
        petHealthBarTextureRaid = "Schlachtzug",
        petHealthBarTextureStatus = "Status",
        petHealthBarTextureFlat = "Flach",
        audioTitle = "Audio",
        enableAudio = "Akustische Warnung aktivieren",
        previous = "Zurück",
        next = "Weiter",
        testSound = "Test",
        identityTitle = "Visuelle Identität",
        chooseIcon = "Symbol wählen",
        automaticIcon = "Automatisch",
        automaticClassIcon = "Automatisches Klassensymbol",
        customIconPrefix = "Benutzerdefiniertes Symbol: %s",
        minimapTitle = "Minimap-Verknüpfung",
        minimapBadge = "MINIMAP",
        showMinimap = "Minimap-Schaltfläche anzeigen",
        lockMinimap = "Minimap-Position sperren",
        resetPosition = "Position zurücksetzen",
        minimapWait = "Warte auf gespeicherte Einstellungen.",
        minimapHidden = "Auf der Minimap ausgeblendet. Position bleibt gespeichert.",
        minimapVisibleLocked = "Auf der Minimap sichtbar, Position gesperrt.",
        minimapVisibleUnlocked = "Auf der Minimap sichtbar, zum Verschieben ziehen.",
        livePreview = "Live-Vorschau",
        position = "Position",
        move = "Bewegen",
        lock = "Sperren",
        reset = "Zurücksetzen",
        iconSize = "Symbolgröße",
        mainKicker = "Primärwarnung",
        mainTitle = "Begleiter fehlt",
        mainDesc = "Warnt, wenn der überwachte Charakter keinen lebenden Kampf-Begleiter hat.",
        mainBadge = "KRITISCH",
        mainEnable = "Warnung für fehlenden Begleiter aktivieren",
        hpKicker = "Gesundheitswarnung",
        hpTitle = "Wenig Leben",
        hpDesc = "Warnt, wenn der aktive Begleiter unter den eingestellten Lebensschwellwert fällt.",
        hpBadge = "SCHWELLE",
        hpEnable = "Warnung bei wenig Leben aktivieren",
        hpThreshold = "Schwellwert wenig Leben (%)",
        passiveKicker = "Befehlswarnung",
        passiveTitle = "Passiver Modus",
        passiveDesc = "Warnt, wenn der aktive Begleiter im passiven Modus bleibt.",
        passiveBadge = "BEFEHL",
        passiveEnable = "Warnen, wenn der Begleiter passiv ist",
        testCenterTitle = "Testcenter",
        testCenterSubtitle = "Löst echte Warnframes aus, ohne den Kampfstatus zu ändern.",
        testMissing = "Fehlt",
        testLowHP = "Wenig LP",
        testPassive = "Passiv",
        testSequence = "Sequenz",
        testStop = "Stopp",
        testReady = "Bereit für die Live-Warnvorschau.",
        testShowingMissing = "Vorschau: fehlender Begleiter.",
        testShowingHP = "Vorschau: wenig Leben.",
        testShowingPassive = "Vorschau: passiver Modus.",
        testShowingSequence = "Komplette Warnsequenz läuft.",
        testStopped = "Vorschau gestoppt.",
        presetsTitle = "Voreinstellungen",
        presetsSubtitle = "Visuelle Basis anwenden und danach feinjustieren.",
        presetCompact = "Kompakt",
        presetReadable = "Lesbar",
        presetStreamer = "Streamer",
        presetMinimal = "Minimal",
        presetAppliedStatus = "Voreinstellung %s angewendet. Unten feinjustieren.",
        iconPickerTitle = "Warnsymbol wählen",
        iconPickerSubtitle = "Makro-Symbolpool, angewendet auf alle Vorschauen.",
        close = "Schließen",
        pageFormat = "Seite %d / %d",
        useAutomaticIcon = "Automatisches Symbol nutzen",
    },
    esES = {
        optionsNotReady = "las opciones aún no están listas. Prueba /reload o /pa.",
        minimapTooltipOpen = "Clic izquierdo: abrir opciones",
        minimapTooltipUnlock = "Clic derecho: desbloquear posición",
        minimapTooltipDrag = "Arrastrar: mover alrededor del minimapa",
        minimapTooltipLock = "Clic derecho: bloquear posición",
        minimapMsgLocked = "botón del minimapa bloqueado.",
        minimapMsgUnlocked = "botón del minimapa desbloqueado.",
        minimapMsgEnabled = "botón del minimapa activado.",
        minimapMsgDisabled = "botón del minimapa desactivado.",
        minimapMsgReset = "botón del minimapa restablecido.",
        customIconReset = "icono personalizado restablecido.",
        customIconSet = "icono personalizado establecido en: %s",
        commandsHeader = "comandos:",
        soundRaidWarning = "Aviso de banda",
        soundReadyCheck = "Comprobación de preparados",
        soundAlarmClock = "Alarma",
        soundPvpQueue = "Cola JcJ",
        soundLevelUp = "Subida de nivel",
        presetApplied = "preajuste %s aplicado.",
        previewStopped = "vista previa detenida.",
        heroSubtitle = "Consola premium de alertas de mascota",
        badgeMissing = "AUSENTE",
        badgeLowHP = "SALUD BAJA",
        badgePassive = "PASIVO",
        globalTitle = "Panel de control",
        globalSubtitle = "Comportamiento global, sonido e identidad visual.",
        behaviorTitle = "Comportamiento",
        alertsOutOfCombat = "Activar alertas fuera de combate",
        minimalMode = "Alertas mínimas solo con icono",
        petHealthBarTitle = "Barra de salud de mascota",
        petHealthBarEnable = "Mostrar barra de salud de mascota",
        petHealthBarPreview = "Vista de barra",
        petHealthBarPreviewHide = "Ocultar vista",
        petHealthBarDragHint = "Vista previa: arrastra para mover. En combate: Mayús+arrastrar.",
        petHealthBarWidth = "Ancho de barra",
        petHealthBarHeight = "Alto de barra",
        petHealthBarRed = "Rojo barra",
        petHealthBarGreen = "Verde barra",
        petHealthBarBlue = "Azul barra",
        petHealthBarThemes = "Temas de barra",
        petHealthBarTextures = "Textura de barra",
        petHealthBarThemeEmerald = "Esmeralda",
        petHealthBarThemeArcane = "Arcano",
        petHealthBarThemeInferno = "Infernal",
        petHealthBarThemeFrost = "Escarcha",
        petHealthBarTextureRaid = "Banda",
        petHealthBarTextureStatus = "Estado",
        petHealthBarTextureFlat = "Plana",
        audioTitle = "Audio",
        enableAudio = "Activar alerta sonora",
        previous = "Anterior",
        next = "Siguiente",
        testSound = "Probar",
        identityTitle = "Identidad visual",
        chooseIcon = "Elegir icono",
        automaticIcon = "Automático",
        automaticClassIcon = "Icono automático de clase",
        customIconPrefix = "Icono personalizado: %s",
        minimapTitle = "Acceso del minimapa",
        minimapBadge = "MINIMAPA",
        showMinimap = "Mostrar botón del minimapa",
        lockMinimap = "Bloquear posición del minimapa",
        resetPosition = "Restablecer posición",
        minimapWait = "Esperando ajustes guardados.",
        minimapHidden = "Oculto del minimapa. La posición se conserva.",
        minimapVisibleLocked = "Visible en el minimapa, posición bloqueada.",
        minimapVisibleUnlocked = "Visible en el minimapa, arrastra para mover.",
        livePreview = "Vista previa",
        position = "Posición",
        move = "Mover",
        lock = "Bloquear",
        reset = "Restablecer",
        iconSize = "Tamaño del icono",
        mainKicker = "Alerta principal",
        mainTitle = "Mascota ausente",
        mainDesc = "Avisa cuando el personaje vigilado no tiene una mascota de combate viva.",
        mainBadge = "CRÍTICO",
        mainEnable = "Activar alerta de mascota ausente",
        hpKicker = "Alerta de salud",
        hpTitle = "Salud baja",
        hpDesc = "Avisa cuando la mascota activa baja del umbral de salud configurado.",
        hpBadge = "UMBRAL",
        hpEnable = "Activar alerta de salud baja",
        hpThreshold = "Umbral de salud baja (%)",
        passiveKicker = "Alerta de orden",
        passiveTitle = "Modo pasivo",
        passiveDesc = "Avisa cuando la mascota activa queda en modo Pasivo.",
        passiveBadge = "ORDEN",
        passiveEnable = "Alertar cuando la mascota esté en Pasivo",
        testCenterTitle = "Centro de pruebas",
        testCenterSubtitle = "Dispara los marcos reales sin cambiar el estado de combate.",
        testMissing = "Ausente",
        testLowHP = "Salud baja",
        testPassive = "Pasivo",
        testSequence = "Secuencia",
        testStop = "Parar",
        testReady = "Listo para previsualizar las alertas reales.",
        testShowingMissing = "Vista previa de mascota ausente.",
        testShowingHP = "Vista previa de salud baja.",
        testShowingPassive = "Vista previa de modo pasivo.",
        testShowingSequence = "Secuencia completa en curso.",
        testStopped = "Vista previa detenida.",
        presetsTitle = "Preajustes",
        presetsSubtitle = "Aplica una base visual y ajusta los detalles.",
        presetCompact = "Compacto",
        presetReadable = "Legible",
        presetStreamer = "Streamer",
        presetMinimal = "Minimal",
        presetAppliedStatus = "Preajuste %s aplicado. Ajusta abajo.",
        iconPickerTitle = "Elegir icono de alerta",
        iconPickerSubtitle = "Pool de iconos de macro aplicado a las vistas previas.",
        close = "Cerrar",
        pageFormat = "Página %d / %d",
        useAutomaticIcon = "Usar icono automático",
    },
    itIT = {
        optionsNotReady = "le opzioni non sono ancora pronte. Prova /reload o /pa.",
        minimapTooltipOpen = "Clic sinistro: apri opzioni",
        minimapTooltipUnlock = "Clic destro: sblocca posizione",
        minimapTooltipDrag = "Trascina: sposta intorno alla minimappa",
        minimapTooltipLock = "Clic destro: blocca posizione",
        minimapMsgLocked = "pulsante minimappa bloccato.",
        minimapMsgUnlocked = "pulsante minimappa sbloccato.",
        minimapMsgEnabled = "pulsante minimappa attivato.",
        minimapMsgDisabled = "pulsante minimappa disattivato.",
        minimapMsgReset = "pulsante minimappa reimpostato.",
        customIconReset = "icona personalizzata reimpostata.",
        customIconSet = "icona personalizzata impostata su: %s",
        commandsHeader = "comandi:",
        soundRaidWarning = "Avviso incursione",
        soundReadyCheck = "Controllo pronti",
        soundAlarmClock = "Allarme",
        soundPvpQueue = "Coda PvP",
        soundLevelUp = "Aumento livello",
        presetApplied = "preset %s applicato.",
        previewStopped = "anteprima avviso fermata.",
        heroSubtitle = "Console premium per avvisi del famiglio",
        badgeMissing = "ASSENTE",
        badgeLowHP = "SALUTE BASSA",
        badgePassive = "PASSIVO",
        globalTitle = "Superficie di controllo",
        globalSubtitle = "Comportamento globale, audio e identità visiva.",
        behaviorTitle = "Comportamento",
        alertsOutOfCombat = "Attiva avvisi fuori combattimento",
        minimalMode = "Avvisi minimi solo icona",
        petHealthBarTitle = "Barra salute pet",
        petHealthBarEnable = "Mostra barra salute pet",
        petHealthBarPreview = "Anteprima barra",
        petHealthBarPreviewHide = "Nascondi anteprima",
        petHealthBarDragHint = "Anteprima: trascina per spostare. In combattimento: Maiusc+trascina.",
        petHealthBarWidth = "Larghezza barra",
        petHealthBarHeight = "Altezza barra",
        petHealthBarRed = "Rosso barra",
        petHealthBarGreen = "Verde barra",
        petHealthBarBlue = "Blu barra",
        petHealthBarThemes = "Temi barra",
        petHealthBarTextures = "Texture barra",
        petHealthBarThemeEmerald = "Smeraldo",
        petHealthBarThemeArcane = "Arcano",
        petHealthBarThemeInferno = "Inferno",
        petHealthBarThemeFrost = "Gelo",
        petHealthBarTextureRaid = "Incursione",
        petHealthBarTextureStatus = "Stato",
        petHealthBarTextureFlat = "Piatta",
        audioTitle = "Audio",
        enableAudio = "Attiva avviso sonoro",
        previous = "Precedente",
        next = "Successivo",
        testSound = "Test",
        identityTitle = "Identità visiva",
        chooseIcon = "Scegli icona",
        automaticIcon = "Automatico",
        automaticClassIcon = "Icona classe automatica",
        customIconPrefix = "Icona personalizzata: %s",
        minimapTitle = "Scorciatoia minimappa",
        minimapBadge = "MINIMAPPA",
        showMinimap = "Mostra pulsante minimappa",
        lockMinimap = "Blocca posizione minimappa",
        resetPosition = "Reimposta posizione",
        minimapWait = "In attesa delle impostazioni salvate.",
        minimapHidden = "Nascosto dalla minimappa. La posizione resta salvata.",
        minimapVisibleLocked = "Visibile sulla minimappa, posizione bloccata.",
        minimapVisibleUnlocked = "Visibile sulla minimappa, trascina per spostare.",
        livePreview = "Anteprima live",
        position = "Posizione",
        move = "Sposta",
        lock = "Blocca",
        reset = "Reimposta",
        iconSize = "Dimensione icona",
        mainKicker = "Avviso principale",
        mainTitle = "Famiglio assente",
        mainDesc = "Avvisa quando il personaggio monitorato non ha un famiglio da combattimento vivo.",
        mainBadge = "CRITICO",
        mainEnable = "Attiva avviso famiglio assente",
        hpKicker = "Avviso salute",
        hpTitle = "Salute bassa",
        hpDesc = "Avvisa quando il famiglio attivo scende sotto la soglia di salute configurata.",
        hpBadge = "SOGLIA",
        hpEnable = "Attiva avviso salute bassa",
        hpThreshold = "Soglia salute bassa (%)",
        passiveKicker = "Avviso comando",
        passiveTitle = "Modalità passiva",
        passiveDesc = "Avvisa quando il famiglio attivo resta in modalità Passiva.",
        passiveBadge = "COMANDO",
        passiveEnable = "Avvisa quando il famiglio è Passivo",
        testCenterTitle = "Centro test",
        testCenterSubtitle = "Attiva i veri frame di avviso senza cambiare il combattimento.",
        testMissing = "Assente",
        testLowHP = "Salute bassa",
        testPassive = "Passivo",
        testSequence = "Sequenza",
        testStop = "Stop",
        testReady = "Pronto per l'anteprima degli avvisi reali.",
        testShowingMissing = "Anteprima avviso famiglio assente.",
        testShowingHP = "Anteprima avviso salute bassa.",
        testShowingPassive = "Anteprima avviso modalità passiva.",
        testShowingSequence = "Sequenza completa in corso.",
        testStopped = "Anteprima fermata.",
        presetsTitle = "Preset",
        presetsSubtitle = "Applica una base visiva e poi rifinisci.",
        presetCompact = "Compatto",
        presetReadable = "Leggibile",
        presetStreamer = "Streamer",
        presetMinimal = "Minimal",
        presetAppliedStatus = "Preset %s applicato. Rifinisci sotto.",
        iconPickerTitle = "Scegli icona avviso",
        iconPickerSubtitle = "Pool icone macro applicato alle anteprime.",
        close = "Chiudi",
        pageFormat = "Pagina %d / %d",
        useAutomaticIcon = "Usa icona automatica",
    },
    ptBR = {
        optionsNotReady = "as opções ainda não estão prontas. Tente /reload ou /pa.",
        minimapTooltipOpen = "Clique esquerdo: abrir opções",
        minimapTooltipUnlock = "Clique direito: desbloquear posição",
        minimapTooltipDrag = "Arraste: mover ao redor do minimapa",
        minimapTooltipLock = "Clique direito: bloquear posição",
        minimapMsgLocked = "botão do minimapa bloqueado.",
        minimapMsgUnlocked = "botão do minimapa desbloqueado.",
        minimapMsgEnabled = "botão do minimapa ativado.",
        minimapMsgDisabled = "botão do minimapa desativado.",
        minimapMsgReset = "botão do minimapa redefinido.",
        customIconReset = "ícone personalizado redefinido.",
        customIconSet = "ícone personalizado definido como: %s",
        commandsHeader = "comandos:",
        soundRaidWarning = "Aviso de raide",
        soundReadyCheck = "Verificação de prontidão",
        soundAlarmClock = "Alarme",
        soundPvpQueue = "Fila JxJ",
        soundLevelUp = "Subida de nível",
        presetApplied = "predefinição %s aplicada.",
        previewStopped = "prévia de alerta parada.",
        heroSubtitle = "Console premium de alertas de ajudante",
        badgeMissing = "AUSENTE",
        badgeLowHP = "VIDA BAIXA",
        badgePassive = "PASSIVO",
        globalTitle = "Painel de controle",
        globalSubtitle = "Comportamento global, som e identidade visual.",
        behaviorTitle = "Comportamento",
        alertsOutOfCombat = "Ativar alertas fora de combate",
        minimalMode = "Alertas mínimos só com ícone",
        petHealthBarTitle = "Barra de vida do ajudante",
        petHealthBarEnable = "Mostrar barra de vida do ajudante",
        petHealthBarPreview = "Prévia da barra",
        petHealthBarPreviewHide = "Ocultar prévia",
        petHealthBarDragHint = "Prévia: arraste para mover. Em combate: Shift+arrastar.",
        petHealthBarWidth = "Largura da barra",
        petHealthBarHeight = "Altura da barra",
        petHealthBarRed = "Vermelho da barra",
        petHealthBarGreen = "Verde da barra",
        petHealthBarBlue = "Azul da barra",
        petHealthBarThemes = "Temas da barra",
        petHealthBarTextures = "Textura da barra",
        petHealthBarThemeEmerald = "Esmeralda",
        petHealthBarThemeArcane = "Arcano",
        petHealthBarThemeInferno = "Inferno",
        petHealthBarThemeFrost = "Gelo",
        petHealthBarTextureRaid = "Raide",
        petHealthBarTextureStatus = "Status",
        petHealthBarTextureFlat = "Plana",
        audioTitle = "Áudio",
        enableAudio = "Ativar alerta sonora",
        previous = "Anterior",
        next = "Próximo",
        testSound = "Testar",
        identityTitle = "Identidade visual",
        chooseIcon = "Escolher ícone",
        automaticIcon = "Automático",
        automaticClassIcon = "Ícone automático de classe",
        customIconPrefix = "Ícone personalizado: %s",
        minimapTitle = "Atalho do minimapa",
        minimapBadge = "MINIMAPA",
        showMinimap = "Mostrar botão do minimapa",
        lockMinimap = "Bloquear posição do minimapa",
        resetPosition = "Redefinir posição",
        minimapWait = "Aguardando configurações salvas.",
        minimapHidden = "Oculto do minimapa. A posição foi mantida.",
        minimapVisibleLocked = "Visível no minimapa, posição bloqueada.",
        minimapVisibleUnlocked = "Visível no minimapa, arraste para mover.",
        livePreview = "Prévia ao vivo",
        position = "Posição",
        move = "Mover",
        lock = "Bloquear",
        reset = "Redefinir",
        iconSize = "Tamanho do ícone",
        mainKicker = "Alerta principal",
        mainTitle = "Ajudante ausente",
        mainDesc = "Avisa quando o personagem monitorado não tem um ajudante de combate vivo.",
        mainBadge = "CRÍTICO",
        mainEnable = "Ativar alerta de ajudante ausente",
        hpKicker = "Alerta de vida",
        hpTitle = "Vida baixa",
        hpDesc = "Avisa quando o ajudante ativo fica abaixo do limite de vida configurado.",
        hpBadge = "LIMITE",
        hpEnable = "Ativar alerta de vida baixa",
        hpThreshold = "Limite de vida baixa (%)",
        passiveKicker = "Alerta de comando",
        passiveTitle = "Modo passivo",
        passiveDesc = "Avisa quando o ajudante ativo fica no modo Passivo.",
        passiveBadge = "COMANDO",
        passiveEnable = "Alertar quando o ajudante estiver Passivo",
        testCenterTitle = "Central de testes",
        testCenterSubtitle = "Aciona os alertas reais sem mudar o estado de combate.",
        testMissing = "Ausente",
        testLowHP = "Vida baixa",
        testPassive = "Passivo",
        testSequence = "Sequência",
        testStop = "Parar",
        testReady = "Pronto para pré-visualizar os alertas reais.",
        testShowingMissing = "Prévia de ajudante ausente.",
        testShowingHP = "Prévia de vida baixa.",
        testShowingPassive = "Prévia de modo passivo.",
        testShowingSequence = "Sequência completa em execução.",
        testStopped = "Prévia parada.",
        presetsTitle = "Predefinições",
        presetsSubtitle = "Aplique uma base visual e ajuste os detalhes.",
        presetCompact = "Compacto",
        presetReadable = "Legível",
        presetStreamer = "Streamer",
        presetMinimal = "Minimal",
        presetAppliedStatus = "Predefinição %s aplicada. Ajuste abaixo.",
        iconPickerTitle = "Escolher ícone de alerta",
        iconPickerSubtitle = "Pool de ícones de macro aplicado às prévias.",
        close = "Fechar",
        pageFormat = "Página %d / %d",
        useAutomaticIcon = "Usar ícone automático",
    },
    ruRU = {
        optionsNotReady = "настройки ещё не готовы. Попробуйте /reload или /pa.",
        minimapTooltipOpen = "ЛКМ: открыть настройки",
        minimapTooltipUnlock = "ПКМ: разблокировать позицию",
        minimapTooltipDrag = "Перетащите: переместить вокруг миникарты",
        minimapTooltipLock = "ПКМ: закрепить позицию",
        minimapMsgLocked = "кнопка миникарты закреплена.",
        minimapMsgUnlocked = "кнопка миникарты разблокирована.",
        minimapMsgEnabled = "кнопка миникарты включена.",
        minimapMsgDisabled = "кнопка миникарты отключена.",
        minimapMsgReset = "кнопка миникарты сброшена.",
        customIconReset = "пользовательский значок сброшен.",
        customIconSet = "пользовательский значок установлен: %s",
        commandsHeader = "команды:",
        soundRaidWarning = "Рейдовое предупреждение",
        soundReadyCheck = "Проверка готовности",
        soundAlarmClock = "Сигнал",
        soundPvpQueue = "Очередь PvP",
        soundLevelUp = "Новый уровень",
        presetApplied = "пресет %s применён.",
        previewStopped = "предпросмотр оповещения остановлен.",
        heroSubtitle = "Премиальная консоль оповещений питомца",
        badgeMissing = "НЕТ",
        badgeLowHP = "МАЛО HP",
        badgePassive = "ПАССИВ",
        globalTitle = "Панель управления",
        globalSubtitle = "Общее поведение, звук и визуальный стиль.",
        behaviorTitle = "Поведение",
        alertsOutOfCombat = "Включить оповещения вне боя",
        minimalMode = "Минимальные оповещения только значком",
        petHealthBarTitle = "Полоса здоровья питомца",
        petHealthBarEnable = "Показывать полосу здоровья питомца",
        petHealthBarPreview = "Предпросмотр полосы",
        petHealthBarPreviewHide = "Скрыть предпросмотр",
        petHealthBarDragHint = "Предпросмотр: перетащите для перемещения. В бою: Shift+перетаскивание.",
        petHealthBarWidth = "Ширина полосы",
        petHealthBarHeight = "Высота полосы",
        petHealthBarRed = "Красный полосы",
        petHealthBarGreen = "Зелёный полосы",
        petHealthBarBlue = "Синий полосы",
        petHealthBarThemes = "Темы полосы",
        petHealthBarTextures = "Текстура полосы",
        petHealthBarThemeEmerald = "Изумруд",
        petHealthBarThemeArcane = "Тайная магия",
        petHealthBarThemeInferno = "Инферно",
        petHealthBarThemeFrost = "Лёд",
        petHealthBarTextureRaid = "Рейд",
        petHealthBarTextureStatus = "Статус",
        petHealthBarTextureFlat = "Плоская",
        audioTitle = "Звук",
        enableAudio = "Включить звуковое оповещение",
        previous = "Назад",
        next = "Далее",
        testSound = "Тест",
        identityTitle = "Визуальный стиль",
        chooseIcon = "Выбрать значок",
        automaticIcon = "Авто",
        automaticClassIcon = "Автоматический значок класса",
        customIconPrefix = "Пользовательский значок: %s",
        minimapTitle = "Кнопка у миникарты",
        minimapBadge = "МИНИКАРТА",
        showMinimap = "Показывать кнопку миникарты",
        lockMinimap = "Закрепить позицию кнопки",
        resetPosition = "Сбросить позицию",
        minimapWait = "Ожидание сохранённых настроек.",
        minimapHidden = "Скрыто с миникарты. Позиция сохранена.",
        minimapVisibleLocked = "Видно у миникарты, позиция закреплена.",
        minimapVisibleUnlocked = "Видно у миникарты, перетащите для перемещения.",
        livePreview = "Предпросмотр",
        position = "Позиция",
        move = "Двигать",
        lock = "Закрепить",
        reset = "Сброс",
        iconSize = "Размер значка",
        mainKicker = "Главное оповещение",
        mainTitle = "Питомец отсутствует",
        mainDesc = "Предупреждает, когда у персонажа нет живого боевого питомца.",
        mainBadge = "КРИТИЧНО",
        mainEnable = "Включить оповещение об отсутствии питомца",
        hpKicker = "Оповещение здоровья",
        hpTitle = "Мало здоровья",
        hpDesc = "Предупреждает, когда здоровье активного питомца ниже заданного порога.",
        hpBadge = "ПОРОГ",
        hpEnable = "Включить оповещение о малом здоровье",
        hpThreshold = "Порог малого здоровья (%)",
        passiveKicker = "Оповещение команды",
        passiveTitle = "Пассивный режим",
        passiveDesc = "Предупреждает, когда активный питомец оставлен в пассивном режиме.",
        passiveBadge = "КОМАНДА",
        passiveEnable = "Оповещать, когда питомец пассивен",
        testCenterTitle = "Центр тестов",
        testCenterSubtitle = "Показывает реальные оповещения без изменения боя.",
        testMissing = "Нет питомца",
        testLowHP = "Мало HP",
        testPassive = "Пассив",
        testSequence = "Серия",
        testStop = "Стоп",
        testReady = "Готово к предпросмотру реальных оповещений.",
        testShowingMissing = "Предпросмотр: питомец отсутствует.",
        testShowingHP = "Предпросмотр: мало здоровья.",
        testShowingPassive = "Предпросмотр: пассивный режим.",
        testShowingSequence = "Полная серия оповещений запущена.",
        testStopped = "Предпросмотр остановлен.",
        presetsTitle = "Пресеты",
        presetsSubtitle = "Примените визуальную базу и настройте детали.",
        presetCompact = "Компакт",
        presetReadable = "Читаемый",
        presetStreamer = "Стример",
        presetMinimal = "Минимум",
        presetAppliedStatus = "Пресет %s применён. Настройте ниже.",
        iconPickerTitle = "Выбор значка оповещения",
        iconPickerSubtitle = "Набор значков макросов для всех предпросмотров.",
        close = "Закрыть",
        pageFormat = "Стр. %d / %d",
        useAutomaticIcon = "Автоматический значок",
    },
    koKR = {
        optionsNotReady = "옵션이 아직 준비되지 않았습니다. /reload 또는 /pa를 시도하세요.",
        minimapTooltipOpen = "왼쪽 클릭: 옵션 열기",
        minimapTooltipUnlock = "오른쪽 클릭: 위치 잠금 해제",
        minimapTooltipDrag = "드래그: 미니맵 주변으로 이동",
        minimapTooltipLock = "오른쪽 클릭: 위치 잠금",
        minimapMsgLocked = "미니맵 버튼이 잠겼습니다.",
        minimapMsgUnlocked = "미니맵 버튼 잠금이 해제되었습니다.",
        minimapMsgEnabled = "미니맵 버튼이 활성화되었습니다.",
        minimapMsgDisabled = "미니맵 버튼이 비활성화되었습니다.",
        minimapMsgReset = "미니맵 버튼이 초기화되었습니다.",
        customIconReset = "사용자 아이콘이 초기화되었습니다.",
        customIconSet = "사용자 아이콘 설정: %s",
        commandsHeader = "명령어:",
        soundRaidWarning = "공격대 경보",
        soundReadyCheck = "준비 확인",
        soundAlarmClock = "알람",
        soundPvpQueue = "PvP 대기열",
        soundLevelUp = "레벨 상승",
        presetApplied = "%s 프리셋이 적용되었습니다.",
        previewStopped = "알림 미리보기가 중지되었습니다.",
        heroSubtitle = "고급 전투 소환수 알림 콘솔",
        badgeMissing = "없음",
        badgeLowHP = "낮은 HP",
        badgePassive = "수동",
        globalTitle = "제어 패널",
        globalSubtitle = "전체 알림 동작, 소리, 시각 스타일.",
        behaviorTitle = "동작",
        alertsOutOfCombat = "전투 외 알림 사용",
        minimalMode = "아이콘만 표시하는 최소 알림",
        petHealthBarTitle = "소환수 생명력 바",
        petHealthBarEnable = "소환수 생명력 바 표시",
        petHealthBarPreview = "바 미리보기",
        petHealthBarPreviewHide = "미리보기 숨기기",
        petHealthBarDragHint = "미리보기: 드래그하여 이동. 전투 중: Shift+드래그.",
        petHealthBarWidth = "바 너비",
        petHealthBarHeight = "바 높이",
        petHealthBarRed = "바 빨강",
        petHealthBarGreen = "바 초록",
        petHealthBarBlue = "바 파랑",
        petHealthBarThemes = "바 테마",
        petHealthBarTextures = "바 텍스처",
        petHealthBarThemeEmerald = "에메랄드",
        petHealthBarThemeArcane = "비전",
        petHealthBarThemeInferno = "지옥불",
        petHealthBarThemeFrost = "서리",
        petHealthBarTextureRaid = "공격대",
        petHealthBarTextureStatus = "상태",
        petHealthBarTextureFlat = "평면",
        audioTitle = "소리",
        enableAudio = "소리 알림 사용",
        previous = "이전",
        next = "다음",
        testSound = "시험",
        identityTitle = "시각 스타일",
        chooseIcon = "아이콘 선택",
        automaticIcon = "자동",
        automaticClassIcon = "자동 직업 아이콘",
        customIconPrefix = "사용자 아이콘: %s",
        minimapTitle = "미니맵 바로가기",
        minimapBadge = "미니맵",
        showMinimap = "미니맵 버튼 표시",
        lockMinimap = "미니맵 위치 잠금",
        resetPosition = "위치 초기화",
        minimapWait = "저장된 설정을 기다리는 중.",
        minimapHidden = "미니맵에서 숨김. 위치는 유지됩니다.",
        minimapVisibleLocked = "미니맵에 표시됨, 위치 잠김.",
        minimapVisibleUnlocked = "미니맵에 표시됨, 드래그로 이동.",
        livePreview = "실시간 미리보기",
        position = "위치",
        move = "이동",
        lock = "잠금",
        reset = "초기화",
        iconSize = "아이콘 크기",
        mainKicker = "주 알림",
        mainTitle = "소환수 없음",
        mainDesc = "감시 중인 캐릭터에게 살아 있는 전투 소환수가 없으면 알립니다.",
        mainBadge = "치명",
        mainEnable = "소환수 없음 알림 사용",
        hpKicker = "생명력 알림",
        hpTitle = "낮은 생명력",
        hpDesc = "활성 소환수의 생명력이 설정한 임계값 아래로 떨어지면 알립니다.",
        hpBadge = "임계값",
        hpEnable = "낮은 생명력 알림 사용",
        hpThreshold = "낮은 생명력 임계값 (%)",
        passiveKicker = "명령 알림",
        passiveTitle = "수동 모드",
        passiveDesc = "활성 소환수가 수동 모드에 남아 있으면 알립니다.",
        passiveBadge = "명령",
        passiveEnable = "소환수가 수동이면 알림",
        testCenterTitle = "테스트 센터",
        testCenterSubtitle = "전투 상태를 바꾸지 않고 실제 알림을 표시합니다.",
        testMissing = "없음",
        testLowHP = "낮은 HP",
        testPassive = "수동",
        testSequence = "순서 실행",
        testStop = "중지",
        testReady = "실제 알림 미리보기를 준비했습니다.",
        testShowingMissing = "소환수 없음 알림 미리보기.",
        testShowingHP = "낮은 생명력 알림 미리보기.",
        testShowingPassive = "수동 모드 알림 미리보기.",
        testShowingSequence = "전체 알림 순서 실행 중.",
        testStopped = "미리보기가 중지되었습니다.",
        presetsTitle = "프리셋",
        presetsSubtitle = "시각 기준을 적용한 뒤 세부 조정하세요.",
        presetCompact = "컴팩트",
        presetReadable = "가독성",
        presetStreamer = "스트리머",
        presetMinimal = "미니멀",
        presetAppliedStatus = "%s 프리셋 적용됨. 아래에서 조정하세요.",
        iconPickerTitle = "알림 아이콘 선택",
        iconPickerSubtitle = "매크로 아이콘 목록을 모든 미리보기에 적용합니다.",
        close = "닫기",
        pageFormat = "%d / %d 페이지",
        useAutomaticIcon = "자동 아이콘 사용",
    },
    zhCN = {
        optionsNotReady = "选项尚未准备好。请尝试 /reload 或 /pa。",
        minimapTooltipOpen = "左键：打开选项",
        minimapTooltipUnlock = "右键：解锁位置",
        minimapTooltipDrag = "拖动：围绕小地图移动",
        minimapTooltipLock = "右键：锁定位置",
        minimapMsgLocked = "小地图按钮已锁定。",
        minimapMsgUnlocked = "小地图按钮已解锁。",
        minimapMsgEnabled = "小地图按钮已启用。",
        minimapMsgDisabled = "小地图按钮已禁用。",
        minimapMsgReset = "小地图按钮已重置。",
        customIconReset = "自定义图标已重置。",
        customIconSet = "自定义图标设置为：%s",
        commandsHeader = "命令：",
        soundRaidWarning = "团队警报",
        soundReadyCheck = "就位确认",
        soundAlarmClock = "闹钟",
        soundPvpQueue = "PvP 队列",
        soundLevelUp = "升级",
        presetApplied = "已应用 %s 预设。",
        previewStopped = "警报预览已停止。",
        heroSubtitle = "高级战斗宠物警报控制台",
        badgeMissing = "缺失",
        badgeLowHP = "低生命",
        badgePassive = "被动",
        globalTitle = "控制面板",
        globalSubtitle = "全局警报行为、声音和视觉标识。",
        behaviorTitle = "行为",
        alertsOutOfCombat = "启用脱战警报",
        minimalMode = "仅图标的极简警报",
        petHealthBarTitle = "宠物生命条",
        petHealthBarEnable = "显示宠物生命条",
        petHealthBarPreview = "预览生命条",
        petHealthBarPreviewHide = "隐藏预览",
        petHealthBarDragHint = "预览：拖动以移动。战斗中：Shift+拖动。",
        petHealthBarWidth = "生命条宽度",
        petHealthBarHeight = "生命条高度",
        petHealthBarRed = "生命条红色",
        petHealthBarGreen = "生命条绿色",
        petHealthBarBlue = "生命条蓝色",
        petHealthBarThemes = "生命条主题",
        petHealthBarTextures = "生命条材质",
        petHealthBarThemeEmerald = "翡翠",
        petHealthBarThemeArcane = "奥术",
        petHealthBarThemeInferno = "炼狱",
        petHealthBarThemeFrost = "冰霜",
        petHealthBarTextureRaid = "团队",
        petHealthBarTextureStatus = "状态",
        petHealthBarTextureFlat = "扁平",
        audioTitle = "音频",
        enableAudio = "启用声音警报",
        previous = "上一页",
        next = "下一页",
        testSound = "测试",
        identityTitle = "视觉标识",
        chooseIcon = "选择图标",
        automaticIcon = "自动",
        automaticClassIcon = "自动职业图标",
        customIconPrefix = "自定义图标：%s",
        minimapTitle = "小地图快捷按钮",
        minimapBadge = "小地图",
        showMinimap = "显示小地图按钮",
        lockMinimap = "锁定小地图位置",
        resetPosition = "重置位置",
        minimapWait = "等待已保存设置。",
        minimapHidden = "已从小地图隐藏，位置仍保留。",
        minimapVisibleLocked = "小地图可见，位置已锁定。",
        minimapVisibleUnlocked = "小地图可见，可拖动调整位置。",
        livePreview = "实时预览",
        position = "位置",
        move = "移动",
        lock = "锁定",
        reset = "重置",
        iconSize = "图标大小",
        mainKicker = "主警报",
        mainTitle = "宠物缺失",
        mainDesc = "当监控角色没有存活的战斗宠物时发出警报。",
        mainBadge = "紧急",
        mainEnable = "启用宠物缺失警报",
        hpKicker = "生命警报",
        hpTitle = "低生命值",
        hpDesc = "当当前宠物低于设置的生命阈值时发出警报。",
        hpBadge = "阈值",
        hpEnable = "启用低生命值警报",
        hpThreshold = "低生命值阈值 (%)",
        passiveKicker = "命令警报",
        passiveTitle = "被动模式",
        passiveDesc = "当当前宠物处于被动模式时发出警报。",
        passiveBadge = "命令",
        passiveEnable = "宠物处于被动时警报",
        testCenterTitle = "测试中心",
        testCenterSubtitle = "触发真实警报框架，不改变战斗状态。",
        testMissing = "缺失",
        testLowHP = "低生命",
        testPassive = "被动",
        testSequence = "序列",
        testStop = "停止",
        testReady = "准备预览真实警报。",
        testShowingMissing = "正在预览宠物缺失警报。",
        testShowingHP = "正在预览低生命值警报。",
        testShowingPassive = "正在预览被动模式警报。",
        testShowingSequence = "正在运行完整警报序列。",
        testStopped = "预览已停止。",
        presetsTitle = "预设",
        presetsSubtitle = "应用调校好的视觉基线，再微调细节。",
        presetCompact = "紧凑",
        presetReadable = "易读",
        presetStreamer = "直播",
        presetMinimal = "极简",
        presetAppliedStatus = "已应用 %s 预设。可在下方微调。",
        iconPickerTitle = "选择警报图标",
        iconPickerSubtitle = "宏图标池，将应用到所有预览。",
        close = "关闭",
        pageFormat = "第 %d / %d 页",
        useAutomaticIcon = "使用自动图标",
    },
    zhTW = {
        optionsNotReady = "選項尚未準備好。請嘗試 /reload 或 /pa。",
        minimapTooltipOpen = "左鍵：開啟選項",
        minimapTooltipUnlock = "右鍵：解除鎖定位置",
        minimapTooltipDrag = "拖曳：沿小地圖周圍移動",
        minimapTooltipLock = "右鍵：鎖定位置",
        minimapMsgLocked = "小地圖按鈕已鎖定。",
        minimapMsgUnlocked = "小地圖按鈕已解除鎖定。",
        minimapMsgEnabled = "小地圖按鈕已啟用。",
        minimapMsgDisabled = "小地圖按鈕已停用。",
        minimapMsgReset = "小地圖按鈕已重設。",
        customIconReset = "自訂圖示已重設。",
        customIconSet = "自訂圖示設定為：%s",
        commandsHeader = "指令：",
        soundRaidWarning = "團隊警報",
        soundReadyCheck = "準備確認",
        soundAlarmClock = "鬧鐘",
        soundPvpQueue = "PvP 佇列",
        soundLevelUp = "升級",
        presetApplied = "已套用 %s 預設。",
        previewStopped = "警報預覽已停止。",
        heroSubtitle = "高級戰鬥寵物警報控制台",
        badgeMissing = "缺失",
        badgeLowHP = "低生命",
        badgePassive = "被動",
        globalTitle = "控制面板",
        globalSubtitle = "全域警報行為、音效與視覺識別。",
        behaviorTitle = "行為",
        alertsOutOfCombat = "啟用脫戰警報",
        minimalMode = "僅圖示的極簡警報",
        petHealthBarTitle = "寵物生命條",
        petHealthBarEnable = "顯示寵物生命條",
        petHealthBarPreview = "預覽生命條",
        petHealthBarPreviewHide = "隱藏預覽",
        petHealthBarDragHint = "預覽：拖曳以移動。戰鬥中：Shift+拖曳。",
        petHealthBarWidth = "生命條寬度",
        petHealthBarHeight = "生命條高度",
        petHealthBarRed = "生命條紅色",
        petHealthBarGreen = "生命條綠色",
        petHealthBarBlue = "生命條藍色",
        petHealthBarThemes = "生命條主題",
        petHealthBarTextures = "生命條材質",
        petHealthBarThemeEmerald = "翡翠",
        petHealthBarThemeArcane = "秘法",
        petHealthBarThemeInferno = "煉獄",
        petHealthBarThemeFrost = "冰霜",
        petHealthBarTextureRaid = "團隊",
        petHealthBarTextureStatus = "狀態",
        petHealthBarTextureFlat = "扁平",
        audioTitle = "音效",
        enableAudio = "啟用聲音警報",
        previous = "上一頁",
        next = "下一頁",
        testSound = "測試",
        identityTitle = "視覺識別",
        chooseIcon = "選擇圖示",
        automaticIcon = "自動",
        automaticClassIcon = "自動職業圖示",
        customIconPrefix = "自訂圖示：%s",
        minimapTitle = "小地圖快捷按鈕",
        minimapBadge = "小地圖",
        showMinimap = "顯示小地圖按鈕",
        lockMinimap = "鎖定小地圖位置",
        resetPosition = "重設位置",
        minimapWait = "等待已儲存設定。",
        minimapHidden = "已從小地圖隱藏，位置仍保留。",
        minimapVisibleLocked = "小地圖可見，位置已鎖定。",
        minimapVisibleUnlocked = "小地圖可見，可拖曳調整位置。",
        livePreview = "即時預覽",
        position = "位置",
        move = "移動",
        lock = "鎖定",
        reset = "重設",
        iconSize = "圖示大小",
        mainKicker = "主要警報",
        mainTitle = "寵物缺失",
        mainDesc = "當監控角色沒有存活的戰鬥寵物時發出警報。",
        mainBadge = "緊急",
        mainEnable = "啟用寵物缺失警報",
        hpKicker = "生命警報",
        hpTitle = "低生命值",
        hpDesc = "當目前寵物低於設定的生命閾值時發出警報。",
        hpBadge = "閾值",
        hpEnable = "啟用低生命值警報",
        hpThreshold = "低生命值閾值 (%)",
        passiveKicker = "命令警報",
        passiveTitle = "被動模式",
        passiveDesc = "當目前寵物處於被動模式時發出警報。",
        passiveBadge = "命令",
        passiveEnable = "寵物處於被動時警報",
        testCenterTitle = "測試中心",
        testCenterSubtitle = "觸發真實警報框架，不改變戰鬥狀態。",
        testMissing = "缺失",
        testLowHP = "低生命",
        testPassive = "被動",
        testSequence = "序列",
        testStop = "停止",
        testReady = "準備預覽真實警報。",
        testShowingMissing = "正在預覽寵物缺失警報。",
        testShowingHP = "正在預覽低生命值警報。",
        testShowingPassive = "正在預覽被動模式警報。",
        testShowingSequence = "正在執行完整警報序列。",
        testStopped = "預覽已停止。",
        presetsTitle = "預設",
        presetsSubtitle = "套用調校好的視覺基準，再微調細節。",
        presetCompact = "緊湊",
        presetReadable = "易讀",
        presetStreamer = "直播",
        presetMinimal = "極簡",
        presetAppliedStatus = "已套用 %s 預設。可在下方微調。",
        iconPickerTitle = "選擇警報圖示",
        iconPickerSubtitle = "巨集圖示池，會套用到所有預覽。",
        close = "關閉",
        pageFormat = "第 %d / %d 頁",
        useAutomaticIcon = "使用自動圖示",
    },
}

LOCALIZED_UI.enGB = LOCALIZED_UI.enUS
LOCALIZED_UI.esMX = LOCALIZED_UI.esES

local function L(key)
    local localeTable = LOCALIZED_UI[GetPlayerLocale()] or LOCALIZED_UI.enUS
    return localeTable[key] or LOCALIZED_UI.enUS[key] or key
end

function PetAlert:L(key)
    return L(key)
end

-- =========================
-- Helpers
-- =========================

local function Clamp(v, minv, maxv)
    if v < minv then return minv end
    if v > maxv then return maxv end
    return v
end

local function Atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end

    if x > 0 then
        return math.atan(y / x)
    end
    if x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    end
    if x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    end
    if x == 0 and y > 0 then
        return math.pi / 2
    end
    if x == 0 and y < 0 then
        return -math.pi / 2
    end

    return 0
end

local AUDIO_ALERT_SOUNDS = {
    { key = "RAID_WARNING", labelKey = "soundRaidWarning", label = "Raid Warning", soundKit = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959 },
    { key = "READY_CHECK", labelKey = "soundReadyCheck", label = "Ready Check", soundKit = SOUNDKIT and SOUNDKIT.READY_CHECK or 8960 },
    { key = "ALARM_CLOCK_WARNING_3", labelKey = "soundAlarmClock", label = "Alarm Clock", soundKit = SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3 or 12889 },
    { key = "PVP_THROUGH_QUEUE", labelKey = "soundPvpQueue", label = "PvP Queue", soundKit = SOUNDKIT and SOUNDKIT.PVP_THROUGH_QUEUE or 8458 },
    { key = "LEVEL_UP", labelKey = "soundLevelUp", label = "Level Up", soundKit = SOUNDKIT and SOUNDKIT.LEVEL_UP or 888 },
}

local AUDIO_ALERT_SOUND_BY_KEY = {}
for _, sound in ipairs(AUDIO_ALERT_SOUNDS) do
    AUDIO_ALERT_SOUND_BY_KEY[sound.key] = sound
end

local PRESET_ORDER = { "compact", "readable", "streamer", "minimal" }
local PRESETS = {
    compact = {
        labelKey = "presetCompact",
        values = {
            mainSize = 96,
            hpSize = 92,
            passiveSize = 92,
            lowHPThreshold = 25,
            minimalMode = false,
            audioAlertEnabled = false,
            alertsOutOfCombat = false,
        },
    },
    readable = {
        labelKey = "presetReadable",
        values = {
            mainSize = 140,
            hpSize = 132,
            passiveSize = 128,
            lowHPThreshold = 30,
            minimalMode = false,
            audioAlertEnabled = false,
            alertsOutOfCombat = false,
        },
    },
    streamer = {
        labelKey = "presetStreamer",
        values = {
            mainSize = 190,
            hpSize = 176,
            passiveSize = 168,
            lowHPThreshold = 35,
            minimalMode = false,
            audioAlertEnabled = true,
            alertsOutOfCombat = true,
        },
    },
    minimal = {
        labelKey = "presetMinimal",
        values = {
            mainSize = 78,
            hpSize = 74,
            passiveSize = 74,
            lowHPThreshold = 25,
            minimalMode = true,
            audioAlertEnabled = false,
            alertsOutOfCombat = false,
        },
    },
}

local function GetSelectedAlertSound()
    local key = (DB and DB.audioAlertSound) or DEFAULTS.audioAlertSound
    return AUDIO_ALERT_SOUND_BY_KEY[key] or AUDIO_ALERT_SOUNDS[1]
end

local function GetSoundDisplayLabel(sound)
    if not sound then
        return L("soundRaidWarning")
    end

    return (sound.labelKey and L(sound.labelKey)) or sound.label or sound.key or L("soundRaidWarning")
end

local function PlayConfiguredAlertSound(ui, force)
    if not DB or not ui then
        return
    end

    if not force and not DB.audioAlertEnabled then
        return
    end

    local sound = GetSelectedAlertSound()
    if sound and sound.soundKit and PlaySound then
        PlaySound(sound.soundKit, "Master")
    end
end

local function GetSpellTextureSafe(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellID)
        if tex then return tex end
    end

    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.iconID then
            return info.iconID
        end
    end

    if GetSpellTexture then
        local tex = GetSpellTexture(spellID)
        if tex then return tex end
    end

    return 136164
end

local function GetClassTag()
    local _, classTag = UnitClass("player")
    return classTag
end

local function GetCurrentSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex or not GetSpecializationInfo then
        return nil
    end
    return GetSpecializationInfo(specIndex)
end

local function PlayerKnowsSpell(spellID)
    if IsPlayerSpell then
        return IsPlayerSpell(spellID) == true
    end

    if IsSpellKnown then
        return IsSpellKnown(spellID) == true
    end

    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(spellID) == true
    end

    return false
end

local function IsPlayerMounted()
    return IsMounted and IsMounted() == true
end

local function AlertsAllowedNow()
    if not DB then
        return false
    end

    if DB.alertsOutOfCombat then
        return true
    end

    return inCombat == true
end

-- =========================
-- Secret-safe low HP curve
-- =========================

local function RebuildHPAlphaCurve()
    hpAlphaCurve = nil

    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then
        return
    end

    if not Enum or not Enum.LuaCurveType then
        return
    end

    if not CreateColor then
        return
    end

    local threshold = Clamp((DB and DB.lowHPThreshold or DEFAULTS.lowHPThreshold) / 100, 0.01, 0.99)
    local epsilon = 0.001

    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)

    curve:AddPoint(0.0, CreateColor(1, 1, 1, 1))
    curve:AddPoint(threshold, CreateColor(1, 1, 1, 1))

    local dropPoint = math.min(threshold + epsilon, 1.0)
    curve:AddPoint(dropPoint, CreateColor(1, 1, 1, 0))
    curve:AddPoint(1.0, CreateColor(1, 1, 1, 0))

    hpAlphaCurve = curve
end

local function ApplySecretLowHPAlpha(frame)
    if not frame then return end

    if not UnitExists("pet") or UnitIsDead("pet") or UnitIsDeadOrGhost("pet") then
        frame:SetAlpha(0)
        return
    end

    if not UnitHealthPercent or not hpAlphaCurve then
        frame:SetAlpha(1)
        return
    end

    local color = UnitHealthPercent("pet", true, hpAlphaCurve)
    if color and color.GetRGBA then
        local _, _, _, a = color:GetRGBA()
        frame:SetAlpha(a)
    else
        frame:SetAlpha(1)
    end
end

-- =========================
-- Spec IDs
-- =========================

local SPEC_UNHOLY_DK = 252
local SPEC_FROST_MAGE = 64
local SPEC_DEMONOLOGY_WARLOCK = 266
local SPEC_MARKSMAN_HUNTER = 254
local UNBREAKABLE_BOND_SPELL_ID = 1223323
local UNBREAKABLE_BOND_BUFF_SPELL_ID = 1298446
local PASSIVE_SPELL_ID = 16266

-- =========================
-- Monitored classes
-- =========================

local MONITORED_CLASS_CONFIG = {
    WARLOCK = {
        enabled = function()
            local specID = GetCurrentSpecID()
            return specID == SPEC_DEMONOLOGY_WARLOCK
        end,
        textClass = "WARLOCK",
        iconSpellID = 30146,
        anyPetIsValid = false,
        validFamilies = {
            ["Felguard"] = true,
            ["Gangregarde"] = true,
            ["Teufelswache"] = true,
            ["Guardia vil"] = true,
            ["Felguardia"] = true,
            ["Гневный страж"] = true,
            ["지옥수호병"] = true,
        },
    },

    DEATHKNIGHT = {
        enabled = function()
            local specID = GetCurrentSpecID()
            return specID == SPEC_UNHOLY_DK
        end,
        textClass = "DEATHKNIGHT",
        iconSpellID = 46584,
        anyPetIsValid = false,
        validFamilies = {
            ["Ghoul"] = true,
            ["Goule"] = true,
            ["Ghul"] = true,
            ["Necrófago"] = true,
            ["Гуль"] = true,
            ["구울"] = true,
        },
    },

    HUNTER = {
        enabled = function()
            local specID = GetCurrentSpecID()

            if specID == SPEC_MARKSMAN_HUNTER then
                return PlayerKnowsSpell(UNBREAKABLE_BOND_SPELL_ID) or PlayerKnowsSpell(UNBREAKABLE_BOND_BUFF_SPELL_ID)
            end

            return true
        end,
        textClass = "HUNTER",
        iconSpellID = 883,
        anyPetIsValid = true,
    },

    MAGE = {
        enabled = function()
            local specID = GetCurrentSpecID()

            if specID ~= SPEC_FROST_MAGE then
                return false
            end

            if not PlayerKnowsSpell(31687) then
                return false
            end

            return true
        end,

        textClass = "MAGE",
        iconSpellID = 31687,
        anyPetIsValid = false,

        validFamilies = {
            ["Water Elemental"] = true,
            ["Élémentaire d'eau"] = true,
            ["Wasserelementar"] = true,
            ["Elemental de agua"] = true,
            ["Elementale dell'acqua"] = true,
            ["Элементаль воды"] = true,
            ["물의 정령"] = true,
            ["水元素"] = true,
        },
    },
}

local function GetActiveConfig()
    local classTag = GetClassTag()
    local config = MONITORED_CLASS_CONFIG[classTag]
    if not config then
        return nil
    end

    if config.enabled and not config.enabled() then
        return nil
    end

    return config
end

local function HasAlivePet()
    if not UnitExists("pet") then return false end
    if UnitIsDead("pet") then return false end
    if UnitIsDeadOrGhost("pet") then return false end
    return true
end

local function IsExpectedPetActive()
    local config = GetActiveConfig()
    if not config then
        return true
    end

    if not HasAlivePet() then
        return false
    end

    return true
end

local function IsPetPassive()
    if not HasAlivePet() then
        return false
    end

    for slot = 1, 10 do
        local name, _, isToken, isActive = GetPetActionInfo(slot)
        if isToken and name == "PET_MODE_PASSIVE" then
            return isActive == true
        end
    end

    return false
end


local function NormalizeCustomIconValue(value)
    if value == nil then
        return nil
    end

    if type(value) == "number" then
        if value > 0 then
            return value
        end
        return nil
    end

    if type(value) ~= "string" then
        return nil
    end

    local trimmed = value:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        return nil
    end

    local numeric = tonumber(trimmed)
    if numeric and numeric > 0 then
        return numeric
    end

    return trimmed
end

local function GetCustomAlertIcon()
    if not DB or not DB.customIconEnabled then
        return nil
    end

    return NormalizeCustomIconValue(DB.customIcon)
end

local function GetDefaultAlertIcon()
    local config = GetActiveConfig()
    if config and config.iconSpellID then
        return GetSpellTextureSafe(config.iconSpellID)
    end
    return 136164
end

local function GetAlertIcon()
    local customIcon = GetCustomAlertIcon()
    if customIcon then
        return customIcon
    end

    return GetDefaultAlertIcon()
end

local function GetAlertText()
    local config = GetActiveConfig()
    if config and config.textClass then
        return GetLocalizedAlertText(config.textClass)
    end
    return "PET !"
end

local function GetLowHPAlertText()
    return GetLocalizedAlertText("LOW_HP")
end

local function GetPassiveAlertText()
    return GetLocalizedAlertText("PASSIVE")
end

-- =========================
-- UI
-- =========================

local ALERT_WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local function SetTextureColor(texture, r, g, b, a)
    if texture then
        texture:SetVertexColor(r, g, b, a)
    end
end

local function ApplyAlertFrameColor(ui, r, g, b)
    if not ui then return end

    ui._r = r
    ui._g = g
    ui._b = b

    SetTextureColor(ui.edgeTop, r, g, b, 1)
    SetTextureColor(ui.edgeBottom, r, g, b, 1)
    SetTextureColor(ui.edgeLeft, r, g, b, 1)
    SetTextureColor(ui.edgeRight, r, g, b, 1)

    if ui.text then
        ui.text:SetTextColor(r, g, b, 1)
    end
end

local function ApplyAlertFrameSize(ui, size)
    if not ui then return end

    local s = Clamp(size or DEFAULTS.mainSize, 40, 300)
    ui:SetSize(s, s)

    local iconSize = math.max(32, s * 0.94)
    local lineSize = Clamp(math.floor(s * 0.018 + 0.5), 1, 3)

    if ui.tex then
        ui.tex:SetSize(iconSize, iconSize)
    end

    if ui.edgeTop then
        ui.edgeTop:ClearAllPoints()
        ui.edgeTop:SetPoint("TOPLEFT", ui.tex, "TOPLEFT", 0, 0)
        ui.edgeTop:SetPoint("TOPRIGHT", ui.tex, "TOPRIGHT", 0, 0)
        ui.edgeTop:SetHeight(lineSize)
    end
    if ui.edgeBottom then
        ui.edgeBottom:ClearAllPoints()
        ui.edgeBottom:SetPoint("BOTTOMLEFT", ui.tex, "BOTTOMLEFT", 0, 0)
        ui.edgeBottom:SetPoint("BOTTOMRIGHT", ui.tex, "BOTTOMRIGHT", 0, 0)
        ui.edgeBottom:SetHeight(lineSize)
    end
    if ui.edgeLeft then
        ui.edgeLeft:ClearAllPoints()
        ui.edgeLeft:SetPoint("TOPLEFT", ui.tex, "TOPLEFT", 0, 0)
        ui.edgeLeft:SetPoint("BOTTOMLEFT", ui.tex, "BOTTOMLEFT", 0, 0)
        ui.edgeLeft:SetWidth(lineSize)
    end
    if ui.edgeRight then
        ui.edgeRight:ClearAllPoints()
        ui.edgeRight:SetPoint("TOPRIGHT", ui.tex, "TOPRIGHT", 0, 0)
        ui.edgeRight:SetPoint("BOTTOMRIGHT", ui.tex, "BOTTOMRIGHT", 0, 0)
        ui.edgeRight:SetWidth(lineSize)
    end

    if ui.text then
        ui.text:ClearAllPoints()
        ui.text:SetPoint("TOP", ui.tex, "BOTTOM", 0, -math.max(5, s * 0.045))
    end
end

local function CreateAlertFrame(globalName, r, g, b)
    local ui = CreateFrame("Frame", globalName, UIParent)
    ui:SetSize(140, 140)
    ui:SetFrameStrata("HIGH")
    ui:SetFrameLevel(999)
    ui:SetClampedToScreen(true)
    ui:SetMovable(true)
    ui:EnableMouse(false)
    ui:Hide()

    ui.tex = ui:CreateTexture(nil, "ARTWORK")
    ui.tex:SetPoint("CENTER", ui, "CENTER", 0, 0)
    ui.tex:SetTexture(136164)
    ui.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    ui.edgeTop = ui:CreateTexture(nil, "OVERLAY")
    ui.edgeTop:SetTexture(ALERT_WHITE_TEXTURE)
    ui.edgeLeft = ui:CreateTexture(nil, "OVERLAY")
    ui.edgeLeft:SetTexture(ALERT_WHITE_TEXTURE)
    ui.edgeBottom = ui:CreateTexture(nil, "OVERLAY")
    ui.edgeBottom:SetTexture(ALERT_WHITE_TEXTURE)
    ui.edgeRight = ui:CreateTexture(nil, "OVERLAY")
    ui.edgeRight:SetTexture(ALERT_WHITE_TEXTURE)

    ui.text = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    ui.text:SetPoint("TOP", ui, "BOTTOM", 0, -6)
    ui.text:SetText("ALERT !")
    ui.text:SetShadowColor(0, 0, 0, 0.82)
    ui.text:SetShadowOffset(1, -1)

    ui.fadeIn = ui:CreateAnimationGroup()
    local fi = ui.fadeIn:CreateAnimation("Alpha")
    fi:SetOrder(1)
    fi:SetDuration(0.16)
    fi:SetFromAlpha(0)
    fi:SetToAlpha(1)
    fi:SetSmoothing("OUT")

    ui.fadeOut = ui:CreateAnimationGroup()
    local fo = ui.fadeOut:CreateAnimation("Alpha")
    fo:SetOrder(1)
    fo:SetDuration(0.18)
    fo:SetFromAlpha(1)
    fo:SetToAlpha(0)
    fo:SetSmoothing("IN")
    ui.fadeOut:SetScript("OnFinished", function()
        if ui._pendingHideSerial == ui._visibilitySerial and ui._wantedVisible ~= true then
            ui:Hide()
            ui:SetAlpha(1)
        end
        ui._pendingHideSerial = nil
    end)

    ui.shake = ui:CreateAnimationGroup()
    local up = ui.shake:CreateAnimation("Translation")
    up:SetOrder(1)
    up:SetDuration(0.55)
    up:SetOffset(0, 4)
    up:SetSmoothing("IN_OUT")

    local down = ui.shake:CreateAnimation("Translation")
    down:SetOrder(2)
    down:SetDuration(0.55)
    down:SetOffset(0, -4)
    down:SetSmoothing("IN_OUT")

    ui.shake:SetLooping("REPEAT")

    ApplyAlertFrameColor(ui, r, g, b)
    ApplyAlertFrameSize(ui, 140)

    return ui
end

local function GetPetHealthBarIcon()
    local icon = GetPetIcon and GetPetIcon()
    if icon and icon ~= "" then
        return icon
    end

    return GetAlertIcon() or 136164
end

local PET_HEALTH_BAR_TEXTURES = {
    raid = {
        labelKey = "petHealthBarTextureRaid",
        path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    },
    status = {
        labelKey = "petHealthBarTextureStatus",
        path = "Interface\\TargetingFrame\\UI-StatusBar",
    },
    flat = {
        labelKey = "petHealthBarTextureFlat",
        path = "Interface\\Buttons\\WHITE8x8",
    },
}

local PET_HEALTH_BAR_TEXTURE_ORDER = { "raid", "status", "flat" }

local PET_HEALTH_BAR_THEMES = {
    emerald = { labelKey = "petHealthBarThemeEmerald", r = 0.29, g = 0.90, b = 0.42, texture = "raid", bg = { 0.035, 0.055, 0.045, 0.88 } },
    arcane = { labelKey = "petHealthBarThemeArcane", r = 0.42, g = 0.66, b = 1.00, texture = "status", bg = { 0.030, 0.040, 0.070, 0.90 } },
    inferno = { labelKey = "petHealthBarThemeInferno", r = 1.00, g = 0.34, b = 0.20, texture = "raid", bg = { 0.070, 0.035, 0.030, 0.90 } },
    frost = { labelKey = "petHealthBarThemeFrost", r = 0.54, g = 0.92, b = 1.00, texture = "status", bg = { 0.030, 0.052, 0.068, 0.90 } },
}

local PET_HEALTH_BAR_THEME_ORDER = { "emerald", "arcane", "inferno", "frost" }

local PET_HEALTH_BAR_FRAME_STYLES = {
    glass = {
        labelKey = "petHealthBarStyleGlass",
        showIcon = true,
        showPercent = true,
        showShine = true,
        bgAlpha = 88,
        borderAlpha = 78,
        height = 16,
    },
    tactical = {
        labelKey = "petHealthBarStyleTactical",
        showIcon = true,
        showPercent = true,
        showShine = false,
        bgAlpha = 96,
        borderAlpha = 100,
        height = 18,
    },
    minimal = {
        labelKey = "petHealthBarStyleMinimal",
        showIcon = false,
        showPercent = false,
        showShine = false,
        bgAlpha = 62,
        borderAlpha = 50,
        height = 10,
    },
    neon = {
        labelKey = "petHealthBarStyleNeon",
        showIcon = true,
        showPercent = true,
        showShine = true,
        bgAlpha = 82,
        borderAlpha = 100,
        height = 14,
    },
}

local PET_HEALTH_BAR_FRAME_STYLE_ORDER = { "glass", "tactical", "minimal", "neon" }

local function GetPetHealthBarTexturePath()
    local key = DB and DB.petHealthBarTexture or DEFAULTS.petHealthBarTexture
    local texture = PET_HEALTH_BAR_TEXTURES[key] or PET_HEALTH_BAR_TEXTURES[DEFAULTS.petHealthBarTexture]
    return texture.path
end

local function GetPetHealthBarTheme()
    local key = DB and DB.petHealthBarTheme or DEFAULTS.petHealthBarTheme
    return PET_HEALTH_BAR_THEMES[key] or PET_HEALTH_BAR_THEMES[DEFAULTS.petHealthBarTheme]
end

local function SavePetHealthBarPosition(frame)
    if not frame or not DB then return end

    local left = frame:GetLeft()
    local bottom = frame:GetBottom()
    if not left or not bottom then return end

    local scale = frame:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    local x = ((left + frame:GetWidth() / 2) * scale / uiScale) - (UIParent:GetWidth() / 2)
    local y = ((bottom + frame:GetHeight() / 2) * scale / uiScale) - (UIParent:GetHeight() / 2)

    DB.petHealthBarX = x
    DB.petHealthBarY = y
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function ApplyPetHealthBarLayout()
    if not PetHealthBar or not DB then return end

    local width = Clamp(DB.petHealthBarWidth or DEFAULTS.petHealthBarWidth, 96, 260)
    local height = Clamp(DB.petHealthBarHeight or DEFAULTS.petHealthBarHeight, 10, 28)
    local showIcon = DB.petHealthBarShowIcon ~= false
    local iconSize = height + 8
    local barX = showIcon and (iconSize + 8) or 4
    local totalWidth = width + barX + 4
    local totalHeight = iconSize + 4

    PetHealthBar:SetSize(totalWidth, totalHeight)

    local r = Clamp(DB.petHealthBarR or DEFAULTS.petHealthBarR, 0, 1)
    local g = Clamp(DB.petHealthBarG or DEFAULTS.petHealthBarG, 0, 1)
    local b = Clamp(DB.petHealthBarB or DEFAULTS.petHealthBarB, 0, 1)
    local theme = GetPetHealthBarTheme()
    local bg = theme.bg or { 0.035, 0.042, 0.055, 0.88 }
    local bgAlpha = Clamp((DB.petHealthBarBgAlpha or DEFAULTS.petHealthBarBgAlpha) / 100, 0, 1)
    local borderAlpha = Clamp((DB.petHealthBarBorderAlpha or DEFAULTS.petHealthBarBorderAlpha) / 100, 0, 1)

    PetHealthBar.bg:SetColorTexture(bg[1], bg[2], bg[3], bgAlpha)

    PetHealthBar.icon:ClearAllPoints()
    PetHealthBar.icon:SetSize(iconSize, iconSize)
    PetHealthBar.icon:SetPoint("LEFT", PetHealthBar, "LEFT", 2, 0)
    PetHealthBar.icon:SetShown(showIcon)

    PetHealthBar.iconBorder:ClearAllPoints()
    PetHealthBar.iconBorder:SetPoint("TOPLEFT", PetHealthBar.icon, "TOPLEFT", 0, 0)
    PetHealthBar.iconBorder:SetPoint("TOPRIGHT", PetHealthBar.icon, "TOPRIGHT", 0, 0)
    PetHealthBar.iconBorder:SetHeight(1)
    PetHealthBar.iconBorder:SetShown(showIcon)

    PetHealthBar.barBg:ClearAllPoints()
    PetHealthBar.barBg:SetPoint("LEFT", PetHealthBar, "LEFT", barX, 0)
    PetHealthBar.barBg:SetPoint("RIGHT", PetHealthBar, "RIGHT", -2, 0)
    PetHealthBar.barBg:SetHeight(height)

    PetHealthBar.bar:ClearAllPoints()
    PetHealthBar.bar:SetPoint("LEFT", PetHealthBar, "LEFT", barX, 0)
    PetHealthBar.bar:SetPoint("RIGHT", PetHealthBar, "RIGHT", -2, 0)
    PetHealthBar.bar:SetHeight(height)
    PetHealthBar.bar:SetStatusBarTexture(GetPetHealthBarTexturePath())
    PetHealthBar.bar:GetStatusBarTexture():SetVertexColor(r, g, b, 1)
    PetHealthBar.edgeTop:SetVertexColor(r, g, b, borderAlpha)
    PetHealthBar.edgeBottom:SetVertexColor(r, g, b, borderAlpha * 0.58)
    PetHealthBar.edgeLeft:SetVertexColor(r, g, b, borderAlpha * 0.80)
    PetHealthBar.edgeRight:SetVertexColor(r, g, b, borderAlpha * 0.80)
    PetHealthBar.iconBorder:SetVertexColor(r, g, b, 1)

    PetHealthBar.edgeLeft:ClearAllPoints()
    PetHealthBar.edgeLeft:SetPoint("TOPLEFT", PetHealthBar, "TOPLEFT", 0, 0)
    PetHealthBar.edgeLeft:SetPoint("BOTTOMLEFT", PetHealthBar, "BOTTOMLEFT", 0, 0)
    PetHealthBar.edgeLeft:SetWidth(1)

    PetHealthBar.edgeRight:ClearAllPoints()
    PetHealthBar.edgeRight:SetPoint("TOPRIGHT", PetHealthBar, "TOPRIGHT", 0, 0)
    PetHealthBar.edgeRight:SetPoint("BOTTOMRIGHT", PetHealthBar, "BOTTOMRIGHT", 0, 0)
    PetHealthBar.edgeRight:SetWidth(1)

    PetHealthBar.shine:ClearAllPoints()
    PetHealthBar.shine:SetPoint("TOPLEFT", PetHealthBar.bar, "TOPLEFT", 0, 0)
    PetHealthBar.shine:SetPoint("TOPRIGHT", PetHealthBar.bar, "TOPRIGHT", 0, 0)
    PetHealthBar.shine:SetHeight(math.max(2, math.floor(height * 0.38)))
    PetHealthBar.shine:SetVertexColor(1, 1, 1, 0.18)
    PetHealthBar.shine:SetShown(DB.petHealthBarShowShine ~= false)

    PetHealthBar.labelFrame:ClearAllPoints()
    PetHealthBar.labelFrame:SetAllPoints(PetHealthBar.barBg)
    PetHealthBar.labelFrame:SetFrameLevel(PetHealthBar.bar:GetFrameLevel() + 5)
    PetHealthBar.label:SetShown(DB.petHealthBarShowPercent ~= false)
end

local function ApplyPetHealthBarPosition()
    if not PetHealthBar or not DB then return end

    PetHealthBar:ClearAllPoints()
    PetHealthBar:SetPoint(
        "CENTER",
        UIParent,
        "CENTER",
        DB.petHealthBarX or DEFAULTS.petHealthBarX,
        DB.petHealthBarY or DEFAULTS.petHealthBarY
    )
end

local function RefreshPetHealthBarValue()
    if not PetHealthBar then return end

    PetHealthBar.icon:SetTexture(GetPetHealthBarIcon())

    if PetHealthBar._preview then
        PetHealthBar.bar:SetValue(0.64)
        PetHealthBar.label:SetText("|cffffff0064%|r")
        return
    end

    if not UnitExists("pet") or UnitIsDead("pet") or UnitIsDeadOrGhost("pet") then
        PetHealthBar.bar:SetValue(0)
        PetHealthBar.label:SetText("")
        return
    end

    if UnitHealthPercent and CurveConstants and CurveConstants.ZeroToOne then
        PetHealthBar.bar:SetValue(UnitHealthPercent("pet", false, CurveConstants.ZeroToOne))
        if CurveConstants.ScaleTo100 then
            PetHealthBar.label:SetFormattedText("|cffffff00%.0f%%|r", UnitHealthPercent("pet", false, CurveConstants.ScaleTo100))
        end
        return
    end

    PetHealthBar.bar:SetValue(0)
    PetHealthBar.label:SetText("")
end

local function UpdatePetHealthBarVisibility()
    if not PetHealthBar or not DB then return end

    if PetHealthBar._preview then
        PetHealthBar:Show()
        RefreshPetHealthBarValue()
        return
    end

    local shouldShow =
        DB.petHealthBarEnabled == true
        and AlertsAllowedNow()
        and not IsPlayerMounted()
        and UnitExists("pet")
        and not UnitIsDead("pet")
        and not UnitIsDeadOrGhost("pet")

    if shouldShow then
        PetHealthBar:Show()
        RefreshPetHealthBarValue()
    else
        PetHealthBar:Hide()
    end
end

local function CreatePetHealthBarFrame()
    local frame = CreateFrame("Frame", "PetAlertPetHealthBar", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(20)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0.035, 0.042, 0.055, 0.88)

    frame.edgeTop = frame:CreateTexture(nil, "BORDER")
    frame.edgeTop:SetTexture(ALERT_WHITE_TEXTURE)
    frame.edgeTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.edgeTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.edgeTop:SetHeight(1)
    frame.edgeTop:SetVertexColor(0.29, 0.90, 0.70, 0.85)

    frame.edgeBottom = frame:CreateTexture(nil, "BORDER")
    frame.edgeBottom:SetTexture(ALERT_WHITE_TEXTURE)
    frame.edgeBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.edgeBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.edgeBottom:SetHeight(1)
    frame.edgeBottom:SetVertexColor(0.29, 0.90, 0.70, 0.45)

    frame.edgeLeft = frame:CreateTexture(nil, "BORDER")
    frame.edgeLeft:SetTexture(ALERT_WHITE_TEXTURE)

    frame.edgeRight = frame:CreateTexture(nil, "BORDER")
    frame.edgeRight:SetTexture(ALERT_WHITE_TEXTURE)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    frame.iconBorder = frame:CreateTexture(nil, "OVERLAY")
    frame.iconBorder:SetTexture(ALERT_WHITE_TEXTURE)
    frame.iconBorder:SetVertexColor(0.29, 0.90, 0.70, 1)

    frame.barBg = frame:CreateTexture(nil, "ARTWORK")
    frame.barBg:SetColorTexture(0, 0, 0, 0.68)

    frame.bar = CreateFrame("StatusBar", nil, frame)
    frame.bar:SetStatusBarTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
    frame.bar:SetMinMaxValues(0, 1)
    frame.bar:SetValue(1)
    frame.bar:GetStatusBarTexture():SetVertexColor(0.29, 0.90, 0.42, 1)

    frame.shine = frame.bar:CreateTexture(nil, "OVERLAY")
    frame.shine:SetTexture(ALERT_WHITE_TEXTURE)
    frame.shine:SetBlendMode("ADD")

    frame.labelFrame = CreateFrame("Frame", nil, frame)
    frame.label = frame.labelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.label:SetPoint("CENTER", frame.labelFrame, "CENTER", 0, 0)
    frame.label:SetShadowColor(0, 0, 0, 0.90)
    frame.label:SetShadowOffset(1, -1)

    frame:SetScript("OnDragStart", function(self)
        if self._preview or IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePetHealthBarPosition(self)
    end)
    frame:SetScript("OnEnter", function(self)
        if not self._preview then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L("petHealthBarDragHint"), 1, 1, 1, nil, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame:SetScript("OnUpdate", function(self)
        if self:IsShown() then
            RefreshPetHealthBarValue()
        end
    end)

    PetHealthBar = frame
    ApplyPetHealthBarLayout()
    ApplyPetHealthBarPosition()
    return frame
end

local function ApplyMainPosition()
    if not MainUI or not DB then return end
    MainUI:ClearAllPoints()
    MainUI:SetPoint(DB.point or "CENTER", UIParent, DB.point or "CENTER", DB.x or 0, DB.y or 0)
end

local function ApplyHPPosition()
    if not HPUI or not DB then return end
    HPUI:ClearAllPoints()
    HPUI:SetPoint(DB.hpPoint or "CENTER", UIParent, DB.hpPoint or "CENTER", DB.hpX or 160, DB.hpY or 0)
end

local function ApplyPassivePosition()
    if not PassiveUI or not DB then return end
    PassiveUI:ClearAllPoints()
    PassiveUI:SetPoint(DB.passivePoint or "CENTER", UIParent, DB.passivePoint or "CENTER", DB.passiveX or -160, DB.passiveY or 0)
end

local function ApplyMainSize()
    if not MainUI or not DB then return end
    local s = Clamp(DB.mainSize or DEFAULTS.mainSize, 40, 300)
    ApplyAlertFrameSize(MainUI, s)
end

local function ApplyHPSize()
    if not HPUI or not DB then return end
    local s = Clamp(DB.hpSize or DEFAULTS.hpSize, 40, 300)
    ApplyAlertFrameSize(HPUI, s)
end

local function ApplyPassiveSize()
    if not PassiveUI or not DB then return end
    local s = Clamp(DB.passiveSize or DEFAULTS.passiveSize, 40, 300)
    ApplyAlertFrameSize(PassiveUI, s)
end

local function ApplyMinimalMode(ui)
    if not ui or not ui.text then return end

    if DB and DB.minimalMode then
        ui.text:Hide()
    else
        ui.text:Show()
    end
end

local function RefreshMainVisuals()
    if not MainUI then return end
    MainUI.tex:SetTexture(GetAlertIcon())
    MainUI.text:SetText(GetAlertText())
    ApplyAlertFrameColor(MainUI, 1, 0.18, 0.16)
    ApplyMinimalMode(MainUI)
end

local function RefreshHPVisuals()
    if not HPUI then return end
    HPUI.tex:SetTexture(GetAlertIcon())
    HPUI.text:SetText(GetLowHPAlertText())
    ApplyAlertFrameColor(HPUI, 1, 0.72, 0.18)
    ApplyMinimalMode(HPUI)
end

local function RefreshPassiveVisuals()
    if not PassiveUI then return end
    PassiveUI.tex:SetTexture(GetCustomAlertIcon() or GetSpellTextureSafe(PASSIVE_SPELL_ID))
    PassiveUI.text:SetText(GetPassiveAlertText())
    ApplyAlertFrameColor(PassiveUI, 0.29, 0.90, 0.70)
    ApplyMinimalMode(PassiveUI)
end

local function StopAlertFrameAnimations(ui)
    if not ui then return end

    if ui.fadeOut and ui.fadeOut:IsPlaying() then
        ui.fadeOut:Stop()
    end

    if ui.fadeIn and ui.fadeIn:IsPlaying() then
        ui.fadeIn:Stop()
    end

    if ui.shake and ui.shake:IsPlaying() then
        ui.shake:Stop()
    end
end

local function ShowFrame(ui, forceSound, suppressSound, mode, token, preserveAlpha)
    if not ui then return end

    ui._wantedVisible = true
    ui._visibilitySerial = (ui._visibilitySerial or 0) + 1
    ui._pendingHideSerial = nil
    ui._petAlertMode = mode or "live"

    if mode == "preview" then
        ui._petAlertPreviewToken = token
    else
        ui._petAlertPreviewToken = nil
    end

    local wasShown = ui:IsShown()

    StopAlertFrameAnimations(ui)

    -- Direct show: avoids stale parent alpha animations hiding the alert after ~1 second.
    ui:Show()
    if not preserveAlpha then
        ui:SetAlpha(1)
    end

    if mode ~= "move" and ui.shake and not ui.shake:IsPlaying() then
        ui.shake:Play()
    end

    if not suppressSound and (forceSound or not wasShown) then
        PlayConfiguredAlertSound(ui, forceSound)
    end
end

local function HideFrame(ui)
    if not ui then return end

    ui._wantedVisible = false
    ui._pendingHideSerial = nil

    if ui._petAlertMode == "preview" then
        ui._petAlertPreviewToken = nil
    end
    ui._petAlertMode = "hidden"

    StopAlertFrameAnimations(ui)

    -- Direct hide: no delayed fadeOut, so no old animation can hide a freshly shown alert.
    if ui:IsShown() then
        ui:Hide()
    end
    ui:SetAlpha(1)
end

function HideMainAlert()
    if not MainUI then return end
    if not isMovingMain then
        HideFrame(MainUI)
    end
end

function HideHPAlert()
    if not HPUI then return end
    if not isMovingHP then
        HideFrame(HPUI)
    end
end

function HidePassiveAlert()
    if not PassiveUI then return end
    if not isMovingPassive then
        HideFrame(PassiveUI)
    end
end

local function HideAllAlerts()
    HideMainAlert()
    HideHPAlert()
    HidePassiveAlert()
end

local function ShowMainAlert()
    if not MainUI then return end
    RefreshMainVisuals()
    ApplyMainSize()
    MainUI:SetAlpha(1)
    ShowFrame(MainUI, false, false, "live")
end

local function ShowHPAlert()
    if not HPUI then return end
    RefreshHPVisuals()
    ApplyHPSize()
    ShowFrame(HPUI, false, true, "live", nil, true)
    ApplySecretLowHPAlpha(HPUI)
end

local function ShowPassiveAlert()
    if not PassiveUI then return end
    RefreshPassiveVisuals()
    ApplyPassiveSize()
    PassiveUI:SetAlpha(1)
    ShowFrame(PassiveUI, false, false, "live")
end

-- =========================
-- Update logic
-- =========================

local function UpdateMainAlert()
    if not MainUI or not DB then return end

    if IsFramePreviewing(MainUI) then
        return
    end

    if isMovingMain then
        RefreshMainVisuals()
        ApplyMainSize()
        MainUI:SetAlpha(1)
        ShowFrame(MainUI, false, false, "move")
        return
    end

    if IsPlayerMounted() then
        HideMainAlert()
        return
    end

    local config = GetActiveConfig()
    if not config then
        HideMainAlert()
        return
    end

    local shouldShow = DB.missingAlertEnabled and AlertsAllowedNow() and (not IsExpectedPetActive())

    if shouldShow then
        ShowMainAlert()
    else
        HideMainAlert()
    end
    UpdatePetHealthBarVisibility()
end

local function UpdateHPAlert()
    if not HPUI or not DB then return end

    if IsFramePreviewing(HPUI) then
        return
    end

    if isMovingHP then
        RefreshHPVisuals()
        ApplyHPSize()
        HPUI:SetAlpha(1)
        ShowFrame(HPUI, false, true, "move")
        return
    end

    if IsPlayerMounted() then
        HideHPAlert()
        return
    end

    local config = GetActiveConfig()
    if not config then
        HideHPAlert()
        return
    end

    local shouldExist =
        AlertsAllowedNow()
        and DB.lowHPAlertEnabled
        and IsExpectedPetActive()
        and UnitExists("pet")
        and not UnitIsDead("pet")
        and not UnitIsDeadOrGhost("pet")

    if not shouldExist then
        HideHPAlert()
        return
    end

    ShowHPAlert()
    ApplySecretLowHPAlpha(HPUI)
    UpdatePetHealthBarVisibility()
end

local function UpdatePassiveAlert()
    if not PassiveUI or not DB then return end

    if IsFramePreviewing(PassiveUI) then
        return
    end

    if isMovingPassive then
        RefreshPassiveVisuals()
        ApplyPassiveSize()
        PassiveUI:SetAlpha(1)
        ShowFrame(PassiveUI, false, false, "move")
        return
    end

    if IsPlayerMounted() then
        HidePassiveAlert()
        return
    end

    local config = GetActiveConfig()
    if not config then
        HidePassiveAlert()
        return
    end

    local shouldShow =
        AlertsAllowedNow()
        and DB.passiveAlertEnabled
        and IsExpectedPetActive()
        and IsPetPassive()

    if shouldShow then
        ShowPassiveAlert()
    else
        HidePassiveAlert()
    end
    UpdatePetHealthBarVisibility()
end

local function UpdateAll()
    if IsPlayerMounted() then
        if not IsFramePreviewing(MainUI) then
            HideMainAlert()
        end
        if not IsFramePreviewing(HPUI) then
            HideHPAlert()
        end
        if not IsFramePreviewing(PassiveUI) then
            HidePassiveAlert()
        end
        UpdatePetHealthBarVisibility()
        return
    end

    UpdateMainAlert()
    UpdateHPAlert()
    UpdatePassiveAlert()
    UpdatePetHealthBarVisibility()
end

-- =========================
-- Minimap button
-- =========================

local MINIMAP_BUTTON_TEXTURE = "Interface\\AddOns\\PetAlert\\media\\icon"

local function GetMinimapButtonRadius()
    if not Minimap or not Minimap.GetWidth then
        return 82
    end

    local width = Minimap:GetWidth() or 140
    local radius = (width / 2) + 10
    return Clamp(radius, 72, 104)
end

local function ApplyMinimapButtonPosition()
    if not MinimapButton then return end

    local parent = Minimap or UIParent
    local angle = math.rad((DB and tonumber(DB.minimapButtonAngle)) or DEFAULTS.minimapButtonAngle)
    local radius = GetMinimapButtonRadius()
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius

    MinimapButton:ClearAllPoints()
    MinimapButton:SetPoint("CENTER", parent, "CENTER", x, y)
end

local function RefreshMinimapButton()
    if not MinimapButton or not DB then return end

    ApplyMinimapButtonPosition()

    if DB.minimapButtonEnabled then
        MinimapButton:Show()
    else
        MinimapButton:SetScript("OnUpdate", nil)
        MinimapButton._dragging = false
        MinimapButton:Hide()
    end
end

local function UpdateMinimapButtonDrag(self)
    if not DB or DB.minimapButtonLocked or not Minimap or not GetCursorPosition then
        return
    end

    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale() or 1

    px = px / scale
    py = py / scale

    local angle = math.deg(Atan2(py - my, px - mx))
    if angle < 0 then
        angle = angle + 360
    end

    DB.minimapButtonAngle = angle
    ApplyMinimapButtonPosition()
end

local function StopMinimapButtonDrag(self)
    self:SetScript("OnUpdate", nil)

    if self._dragging then
        self._dragging = false
        self._suppressClickUntil = GetTime and (GetTime() + 0.25) or true
    end

    ApplyMinimapButtonPosition()
end

local function RefreshMinimapConfigControls()
    if PetAlert and PetAlert.RefreshMinimapConfigControls then
        PetAlert:RefreshMinimapConfigControls()
    end
end

local function CreateMinimapButton()
    if MinimapButton then
        return
    end

    local parent = Minimap or UIParent
    MinimapButton = CreateFrame("Button", "PetAlertMinimapButton", parent)
    MinimapButton:SetSize(32, 32)
    MinimapButton:SetFrameStrata("MEDIUM")
    MinimapButton:SetFrameLevel(8)
    MinimapButton:SetClampedToScreen(false)
    MinimapButton:EnableMouse(true)
    MinimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    MinimapButton:RegisterForDrag("LeftButton")

    MinimapButton.icon = MinimapButton:CreateTexture(nil, "ARTWORK")
    MinimapButton.icon:SetTexture(MINIMAP_BUTTON_TEXTURE)
    MinimapButton.icon:SetSize(22, 22)
    MinimapButton.icon:SetPoint("CENTER", 0, 0)
    MinimapButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    MinimapButton.border = MinimapButton:CreateTexture(nil, "OVERLAY")
    MinimapButton.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    MinimapButton.border:SetSize(54, 54)
    MinimapButton.border:SetPoint("TOPLEFT", 0, 0)

    MinimapButton.highlight = MinimapButton:CreateTexture(nil, "HIGHLIGHT")
    MinimapButton.highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    MinimapButton.highlight:SetBlendMode("ADD")
    MinimapButton.highlight:SetSize(32, 32)
    MinimapButton.highlight:SetPoint("CENTER")

    MinimapButton:SetScript("OnEnter", function(self)
        if not GameTooltip then return end

        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("PetAlert", 1, 0.25, 0.25)
        GameTooltip:AddLine(L("minimapTooltipOpen"), 1, 1, 1)

        if DB and DB.minimapButtonLocked then
            GameTooltip:AddLine(L("minimapTooltipUnlock"), 0.72, 0.82, 0.92)
        else
            GameTooltip:AddLine(L("minimapTooltipDrag"), 0.72, 0.82, 0.92)
            GameTooltip:AddLine(L("minimapTooltipLock"), 0.72, 0.82, 0.92)
        end

        GameTooltip:Show()
    end)

    MinimapButton:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    MinimapButton:SetScript("OnMouseDown", function(self)
        self.icon:ClearAllPoints()
        self.icon:SetPoint("CENTER", 1, -1)
    end)

    MinimapButton:SetScript("OnMouseUp", function(self)
        self.icon:ClearAllPoints()
        self.icon:SetPoint("CENTER", 0, 0)

        if self._dragging then
            StopMinimapButtonDrag(self)
        end
    end)

    MinimapButton:SetScript("OnClick", function(self, button)
        if self._suppressClickUntil then
            local now = GetTime and GetTime()
            if self._suppressClickUntil == true or not now or now <= self._suppressClickUntil then
                self._suppressClickUntil = nil
                return
            end
            self._suppressClickUntil = nil
        end

        -- Opening the addon options, refreshing Settings controls, or changing minimap
        -- layout state during combat can taint Blizzard's protected interface panels.
        -- Keep the minimap button clickable, but do not perform UI-affecting actions
        -- while WoW is in combat lockdown.
        if InCombatLockdown and InCombatLockdown() then
            print("|cffff4040PetAlert|r Options indisponibles en combat.")
            return
        end

        if button == "RightButton" and DB then
            DB.minimapButtonLocked = not DB.minimapButtonLocked
            print("|cffff4040PetAlert|r " .. (DB.minimapButtonLocked and L("minimapMsgLocked") or L("minimapMsgUnlocked")))
            RefreshMinimapConfigControls()
            return
        end

        if OpenPetAlertOptions then
            OpenPetAlertOptions()
        end
    end)

    MinimapButton:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then
            return
        end

        if DB and not DB.minimapButtonLocked then
            self._dragging = true
            self._suppressClickUntil = nil
            self:SetScript("OnUpdate", UpdateMinimapButtonDrag)
            UpdateMinimapButtonDrag(self)
        end
    end)

    MinimapButton:SetScript("OnDragStop", function(self)
        StopMinimapButtonDrag(self)
    end)

    RefreshMinimapButton()
end

-- =========================
-- Public API for config
-- =========================

function PetAlert:GetDB()
    return DB
end

function PetAlert:RefreshAll()
    if not DB then return end

    DB.mainSize = Clamp(DB.mainSize or DEFAULTS.mainSize, 40, 300)
    DB.hpSize = Clamp(DB.hpSize or DEFAULTS.hpSize, 40, 300)
    DB.passiveSize = Clamp(DB.passiveSize or DEFAULTS.passiveSize, 40, 300)
    DB.lowHPThreshold = Clamp(DB.lowHPThreshold or DEFAULTS.lowHPThreshold, 1, 99)
    DB.minimapButtonAngle = Clamp(tonumber(DB.minimapButtonAngle) or DEFAULTS.minimapButtonAngle, 0, 360)
    DB.petHealthBarWidth = Clamp(DB.petHealthBarWidth or DEFAULTS.petHealthBarWidth, 96, 260)
    DB.petHealthBarHeight = Clamp(DB.petHealthBarHeight or DEFAULTS.petHealthBarHeight, 10, 28)
    DB.petHealthBarR = Clamp(DB.petHealthBarR or DEFAULTS.petHealthBarR, 0, 1)
    DB.petHealthBarG = Clamp(DB.petHealthBarG or DEFAULTS.petHealthBarG, 0, 1)
    DB.petHealthBarB = Clamp(DB.petHealthBarB or DEFAULTS.petHealthBarB, 0, 1)
    if not PET_HEALTH_BAR_THEMES[DB.petHealthBarTheme or ""] then
        DB.petHealthBarTheme = DEFAULTS.petHealthBarTheme
    end
    if DB.petHealthBarTexture == "mana" or DB.petHealthBarTexture == "smooth" then
        DB.petHealthBarTexture = "status"
    end
    if not PET_HEALTH_BAR_TEXTURES[DB.petHealthBarTexture or ""] then
        DB.petHealthBarTexture = DEFAULTS.petHealthBarTexture
    end
    if not PET_HEALTH_BAR_FRAME_STYLES[DB.petHealthBarFrameStyle or ""] then
        DB.petHealthBarFrameStyle = DEFAULTS.petHealthBarFrameStyle
    end
    DB.petHealthBarBgAlpha = Clamp(DB.petHealthBarBgAlpha or DEFAULTS.petHealthBarBgAlpha, 0, 100)
    DB.petHealthBarBorderAlpha = Clamp(DB.petHealthBarBorderAlpha or DEFAULTS.petHealthBarBorderAlpha, 0, 100)

    RebuildHPAlphaCurve()
    RefreshMinimapButton()
    ApplyPetHealthBarLayout()
    ApplyPetHealthBarPosition()

    ApplyMainPosition()
    ApplyHPPosition()
    ApplyPassivePosition()
    ApplyMainSize()
    ApplyHPSize()
    ApplyPassiveSize()

    RefreshMainVisuals()
    RefreshHPVisuals()
    RefreshPassiveVisuals()

    if MainUI and MainUI:IsShown() then
        ApplyMainSize()
    end
    if HPUI and HPUI:IsShown() then
        ApplyHPSize()
    end
    if PassiveUI and PassiveUI:IsShown() then
        ApplyPassiveSize()
    end

    UpdateAll()
end

function PetAlert:SetPetHealthBarEnabled(enabled)
    if not DB then return end
    DB.petHealthBarEnabled = enabled == true
    if PetHealthBar then
        PetHealthBar._preview = false
        PetHealthBar:SetFrameStrata("MEDIUM")
        PetHealthBar:SetFrameLevel(20)
    end
    UpdatePetHealthBarVisibility()
end

function PetAlert:TogglePetHealthBarPreview()
    if not DB then return false end
    if not PetHealthBar then
        CreatePetHealthBarFrame()
    end

    PetHealthBar._preview = not PetHealthBar._preview
    if PetHealthBar._preview then
        PetHealthBar:SetFrameStrata("FULLSCREEN_DIALOG")
        PetHealthBar:SetFrameLevel(100)
        ApplyPetHealthBarLayout()
        ApplyPetHealthBarPosition()
        RefreshPetHealthBarValue()
        PetHealthBar:Show()
    else
        PetHealthBar:SetFrameStrata("MEDIUM")
        PetHealthBar:SetFrameLevel(20)
        UpdatePetHealthBarVisibility()
    end

    return PetHealthBar._preview == true
end

function PetAlert:IsPetHealthBarPreviewing()
    return PetHealthBar and PetHealthBar._preview == true
end

function PetAlert:GetPetHealthBarThemes()
    local themes = {}
    for _, key in ipairs(PET_HEALTH_BAR_THEME_ORDER) do
        local theme = PET_HEALTH_BAR_THEMES[key]
        themes[#themes + 1] = {
            key = key,
            label = L(theme.labelKey),
            r = theme.r,
            g = theme.g,
            b = theme.b,
        }
    end
    return themes
end

function PetAlert:GetPetHealthBarTextures()
    local textures = {}
    for _, key in ipairs(PET_HEALTH_BAR_TEXTURE_ORDER) do
        local texture = PET_HEALTH_BAR_TEXTURES[key]
        textures[#textures + 1] = {
            key = key,
            label = L(texture.labelKey),
        }
    end
    return textures
end

function PetAlert:GetPetHealthBarFrameStyles()
    local styles = {}
    for _, key in ipairs(PET_HEALTH_BAR_FRAME_STYLE_ORDER) do
        local style = PET_HEALTH_BAR_FRAME_STYLES[key]
        styles[#styles + 1] = {
            key = key,
            label = L(style.labelKey),
        }
    end
    return styles
end

function PetAlert:ApplyPetHealthBarTheme(key)
    if not DB then return end
    local theme = PET_HEALTH_BAR_THEMES[key]
    if not theme then return end

    DB.petHealthBarTheme = key
    DB.petHealthBarTexture = theme.texture or DB.petHealthBarTexture or DEFAULTS.petHealthBarTexture
    DB.petHealthBarR = theme.r
    DB.petHealthBarG = theme.g
    DB.petHealthBarB = theme.b
    ApplyPetHealthBarLayout()
    UpdatePetHealthBarVisibility()
end

function PetAlert:SetPetHealthBarTexture(key)
    if not DB or not PET_HEALTH_BAR_TEXTURES[key] then return end
    DB.petHealthBarTexture = key
    ApplyPetHealthBarLayout()
    UpdatePetHealthBarVisibility()
end

function PetAlert:ApplyPetHealthBarFrameStyle(key)
    if not DB then return end
    local style = PET_HEALTH_BAR_FRAME_STYLES[key]
    if not style then return end

    DB.petHealthBarFrameStyle = key
    DB.petHealthBarShowIcon = style.showIcon
    DB.petHealthBarShowPercent = style.showPercent
    DB.petHealthBarShowShine = style.showShine
    DB.petHealthBarBgAlpha = style.bgAlpha
    DB.petHealthBarBorderAlpha = style.borderAlpha
    DB.petHealthBarHeight = style.height or DB.petHealthBarHeight
    ApplyPetHealthBarLayout()
    UpdatePetHealthBarVisibility()
end

function PetAlert:SetPetHealthBarDisplayOption(key, enabled)
    if not DB then return end
    if key == "icon" then
        DB.petHealthBarShowIcon = enabled == true
    elseif key == "percent" then
        DB.petHealthBarShowPercent = enabled == true
    elseif key == "shine" then
        DB.petHealthBarShowShine = enabled == true
    end
    ApplyPetHealthBarLayout()
    UpdatePetHealthBarVisibility()
end

function PetAlert:GetSoundOptions()
    return AUDIO_ALERT_SOUNDS
end

function PetAlert:GetSelectedSoundLabel()
    local sound = GetSelectedAlertSound()
    return GetSoundDisplayLabel(sound)
end

function PetAlert:SelectPreviousSound()
    if not DB then return end

    local current = DB.audioAlertSound or DEFAULTS.audioAlertSound
    local index = 1
    for i, sound in ipairs(AUDIO_ALERT_SOUNDS) do
        if sound.key == current then
            index = i
            break
        end
    end

    index = index - 1
    if index < 1 then
        index = #AUDIO_ALERT_SOUNDS
    end

    DB.audioAlertSound = AUDIO_ALERT_SOUNDS[index].key
end

function PetAlert:SelectNextSound()
    if not DB then return end

    local current = DB.audioAlertSound or DEFAULTS.audioAlertSound
    local index = 1
    for i, sound in ipairs(AUDIO_ALERT_SOUNDS) do
        if sound.key == current then
            index = i
            break
        end
    end

    index = index + 1
    if index > #AUDIO_ALERT_SOUNDS then
        index = 1
    end

    DB.audioAlertSound = AUDIO_ALERT_SOUNDS[index].key
end

function PetAlert:PreviewAlertSound()
    PlayConfiguredAlertSound({}, true)
end

local function ShowPreviewAlert(which, token, duration, restoreAfter)
    if not DB then return end

    local ui
    if which == "main" then
        RefreshMainVisuals()
        ApplyMainSize()
        ui = MainUI
    elseif which == "hp" then
        RefreshHPVisuals()
        ApplyHPSize()
        ui = HPUI
    elseif which == "passive" then
        RefreshPassiveVisuals()
        ApplyPassiveSize()
        ui = PassiveUI
    end

    if not ui then return end

    ui:SetAlpha(1)
    ShowFrame(ui, true, false, "preview", token)

    if C_Timer and C_Timer.After then
        C_Timer.After(duration or 2.35, function()
            if token ~= previewToken or ui._petAlertMode ~= "preview" or ui._petAlertPreviewToken ~= token then
                return
            end

            HideFrame(ui)
            if restoreAfter ~= false then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.24, function()
                        if token == previewToken then
                            UpdateAll()
                        end
                    end)
                else
                    UpdateAll()
                end
            end
        end)
    end
end

function PetAlert:PreviewAlert(which)
    if not DB then return end

    which = which or "all"
    previewToken = previewToken + 1
    local token = previewToken

    if which == "main" or which == "missing" then
        ShowPreviewAlert("main", token, 2.35, true)
        return
    end

    if which == "hp" or which == "lowhp" then
        ShowPreviewAlert("hp", token, 2.35, true)
        return
    end

    if which == "passive" then
        ShowPreviewAlert("passive", token, 2.35, true)
        return
    end

    ShowPreviewAlert("main", token, 1.55, false)
    if C_Timer and C_Timer.After then
        C_Timer.After(1.18, function()
            if token == previewToken then
                ShowPreviewAlert("hp", token, 1.55, false)
            end
        end)
        C_Timer.After(2.36, function()
            if token == previewToken then
                ShowPreviewAlert("passive", token, 1.85, true)
            end
        end)
    end
end

function PetAlert:StopAlertPreview()
    previewToken = previewToken + 1
    if MainUI then MainUI._petAlertPreviewToken = nil end
    if HPUI then HPUI._petAlertPreviewToken = nil end
    if PassiveUI then PassiveUI._petAlertPreviewToken = nil end
    HideFrame(MainUI)
    HideFrame(HPUI)
    HideFrame(PassiveUI)

    if C_Timer and C_Timer.After then
        C_Timer.After(0.24, UpdateAll)
    else
        UpdateAll()
    end
end

function PetAlert:GetPresetOptions()
    return PRESET_ORDER, PRESETS
end

function PetAlert:ApplyPreset(name)
    if not DB then return false end

    local preset = PRESETS[name or ""]
    if not preset then
        return false
    end

    for key, value in pairs(preset.values) do
        DB[key] = value
    end

    RebuildHPAlphaCurve()
    PetAlert:RefreshAll()
    return true, L(preset.labelKey)
end


function PetAlert:SetCustomIcon(value)
    if not DB then return end

    local normalized = NormalizeCustomIconValue(value)
    if normalized then
        DB.customIcon = normalized
        DB.customIconEnabled = true
    else
        DB.customIcon = ""
        DB.customIconEnabled = false
    end

    PetAlert:RefreshAll()
end

function PetAlert:ResetCustomIcon()
    if not DB then return end

    DB.customIcon = ""
    DB.customIconEnabled = false

    PetAlert:RefreshAll()
end

function PetAlert:GetCustomIconDisplayText()
    if not DB then return "" end
    return tostring(DB.customIcon or "")
end

function PetAlert:GetDefaultAlertIcon()
    return GetDefaultAlertIcon()
end

function PetAlert:SetMinimapButtonEnabled(enabled)
    if not DB then return end

    DB.minimapButtonEnabled = enabled == true
    RefreshMinimapButton()
    RefreshMinimapConfigControls()
end

function PetAlert:SetMinimapButtonLocked(locked)
    if not DB then return end

    DB.minimapButtonLocked = locked == true
    RefreshMinimapButton()
    RefreshMinimapConfigControls()
end

function PetAlert:ResetMinimapButton()
    if not DB then return end

    DB.minimapButtonAngle = DEFAULTS.minimapButtonAngle
    DB.minimapButtonLocked = false
    DB.minimapButtonEnabled = true
    RefreshMinimapButton()
    RefreshMinimapConfigControls()
end

function PetAlert:IsMinimapButtonEnabled()
    return DB and DB.minimapButtonEnabled == true
end

function PetAlert:IsMinimapButtonLocked()
    return DB and DB.minimapButtonLocked == true
end

function PetAlert:GetPreviewData(which)
    local size = 64
    local icon = GetAlertIcon()
    local text = "ALERT !"
    local r, g, b = 1, 1, 1

    if which == "main" then
        size = Clamp((DB and DB.mainSize) or DEFAULTS.mainSize, 32, 84)
        text = GetAlertText()
        r, g, b = 1, 0, 0
    elseif which == "hp" then
        size = Clamp((DB and DB.hpSize) or DEFAULTS.hpSize, 32, 84)
        text = GetLowHPAlertText()
        r, g, b = 1, 0.82, 0
    else
        size = Clamp((DB and DB.passiveSize) or DEFAULTS.passiveSize, 32, 84)
        icon = GetCustomAlertIcon() or GetSpellTextureSafe(PASSIVE_SPELL_ID)
        text = GetPassiveAlertText()
        r, g, b = 0.4, 0.8, 1
    end

    if DB and DB.minimalMode then
        text = ""
    end

    return {
        icon = icon,
        text = text,
        size = size,
        r = r,
        g = g,
        b = b,
    }
end

function PetAlert:MoveMain()
    if not MainUI or not DB then return end

    isMovingMain = true
    MainUI:EnableMouse(true)
    MainUI:RegisterForDrag("LeftButton")

    MainUI:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    MainUI:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        DB.point = point or "CENTER"
        DB.x = math.floor((x or 0) + 0.5)
        DB.y = math.floor((y or 0) + 0.5)
    end)

    RefreshMainVisuals()
    ApplyMainSize()
    MainUI:SetAlpha(1)
    ShowFrame(MainUI, false, false, "move")
end

function PetAlert:LockMain()
    if not MainUI then return end

    isMovingMain = false
    MainUI:EnableMouse(false)
    MainUI:RegisterForDrag()
    MainUI:SetScript("OnDragStart", nil)
    MainUI:SetScript("OnDragStop", nil)
    UpdateMainAlert()
end

function PetAlert:ResetMain()
    if not DB then return end
    DB.point = DEFAULTS.point
    DB.x = DEFAULTS.x
    DB.y = DEFAULTS.y
    ApplyMainPosition()
    self:LockMain()
end

function PetAlert:MoveHP()
    if not HPUI or not DB then return end

    isMovingHP = true
    HPUI:EnableMouse(true)
    HPUI:RegisterForDrag("LeftButton")

    HPUI:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    HPUI:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        DB.hpPoint = point or "CENTER"
        DB.hpX = math.floor((x or 0) + 0.5)
        DB.hpY = math.floor((y or 0) + 0.5)
    end)

    RefreshHPVisuals()
    ApplyHPSize()
    HPUI:SetAlpha(1)
    ShowFrame(HPUI, false, true, "move")
end

function PetAlert:LockHP()
    if not HPUI then return end

    isMovingHP = false
    HPUI:EnableMouse(false)
    HPUI:RegisterForDrag()
    HPUI:SetScript("OnDragStart", nil)
    HPUI:SetScript("OnDragStop", nil)
    UpdateHPAlert()
end

function PetAlert:ResetHP()
    if not DB then return end
    DB.hpPoint = DEFAULTS.hpPoint
    DB.hpX = DEFAULTS.hpX
    DB.hpY = DEFAULTS.hpY
    ApplyHPPosition()
    self:LockHP()
end

function PetAlert:MovePassive()
    if not PassiveUI or not DB then return end

    isMovingPassive = true
    PassiveUI:EnableMouse(true)
    PassiveUI:RegisterForDrag("LeftButton")

    PassiveUI:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    PassiveUI:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        DB.passivePoint = point or "CENTER"
        DB.passiveX = math.floor((x or 0) + 0.5)
        DB.passiveY = math.floor((y or 0) + 0.5)
    end)

    RefreshPassiveVisuals()
    ApplyPassiveSize()
    PassiveUI:SetAlpha(1)
    ShowFrame(PassiveUI, false, false, "move")
end

function PetAlert:LockPassive()
    if not PassiveUI then return end

    isMovingPassive = false
    PassiveUI:EnableMouse(false)
    PassiveUI:RegisterForDrag()
    PassiveUI:SetScript("OnDragStart", nil)
    PassiveUI:SetScript("OnDragStop", nil)
    UpdatePassiveAlert()
end

function PetAlert:ResetPassive()
    if not DB then return end
    DB.passivePoint = DEFAULTS.passivePoint
    DB.passiveX = DEFAULTS.passiveX
    DB.passiveY = DEFAULTS.passiveY
    ApplyPassivePosition()
    self:LockPassive()
end


-- =========================
-- Options helper
-- =========================

OpenPetAlertOptions = function()
    if PetAlert and PetAlert.OpenOptions then
        PetAlert:OpenOptions()
    else
        print("|cffff4040PetAlert|r " .. L("optionsNotReady"))
    end
end

-- =========================
-- Slash commands
-- =========================

SLASH_PETALERT1 = "/pa"
SLASH_PETALERT2 = "/petalert"

SlashCmdList["PETALERT"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "" or msg == "options" or msg == "config" then
        OpenPetAlertOptions()
        return
    end


    if msg == "move" then
        PetAlert:MoveMain()
        return
    end

    if msg == "lock" then
        PetAlert:LockMain()
        return
    end

    if msg == "reset" then
        PetAlert:ResetMain()
        return
    end

    if msg == "ooc on" then
        DB.alertsOutOfCombat = true
        UpdateAll()
        return
    end

    if msg == "ooc off" then
        DB.alertsOutOfCombat = false
        UpdateAll()
        return
    end

    local x, y = msg:match("^(-?%d+)%s+(-?%d+)$")
    if x and y and DB then
        DB.point = "CENTER"
        DB.x = tonumber(x)
        DB.y = tonumber(y)
        ApplyMainPosition()
        PetAlert:LockMain()
        return
    end

    if msg == "hpmove" then
        PetAlert:MoveHP()
        return
    end

    if msg == "hplock" then
        PetAlert:LockHP()
        return
    end

    if msg == "hpreset" then
        PetAlert:ResetHP()
        return
    end

    if msg == "hp on" then
        DB.lowHPAlertEnabled = true
        UpdateHPAlert()
        return
    end

    if msg == "hp off" then
        DB.lowHPAlertEnabled = false
        UpdateHPAlert()
        return
    end

    local hpThreshold = msg:match("^hp%s+(%d+)$")
    if hpThreshold then
        hpThreshold = Clamp(tonumber(hpThreshold) or 25, 1, 99)
        DB.lowHPThreshold = hpThreshold
        RebuildHPAlphaCurve()
        UpdateHPAlert()
        return
    end

    local hpx, hpy = msg:match("^hp%s+(-?%d+)%s+(-?%d+)$")
    if hpx and hpy and DB then
        DB.hpPoint = "CENTER"
        DB.hpX = tonumber(hpx)
        DB.hpY = tonumber(hpy)
        ApplyHPPosition()
        PetAlert:LockHP()
        return
    end

    if msg == "passivemove" then
        PetAlert:MovePassive()
        return
    end

    if msg == "passivelock" then
        PetAlert:LockPassive()
        return
    end

    if msg == "passivereset" then
        PetAlert:ResetPassive()
        return
    end

    if msg == "passive on" then
        DB.passiveAlertEnabled = true
        UpdatePassiveAlert()
        return
    end

    if msg == "passive off" then
        DB.passiveAlertEnabled = false
        UpdatePassiveAlert()
        return
    end

    local px, py = msg:match("^passive%s+(-?%d+)%s+(-?%d+)$")
    if px and py and DB then
        DB.passivePoint = "CENTER"
        DB.passiveX = tonumber(px)
        DB.passiveY = tonumber(py)
        ApplyPassivePosition()
        PetAlert:LockPassive()
        return
    end


    if msg == "icon reset" or msg == "icon off" then
        PetAlert:ResetCustomIcon()
        print("|cffff4040PetAlert|r " .. L("customIconReset"))
        return
    end

    local iconValue = msg:match("^icon%s+(.+)$")
    if iconValue and DB then
        PetAlert:SetCustomIcon(iconValue)
        print("|cffff4040PetAlert|r " .. string.format(L("customIconSet"), tostring(DB.customIcon or "")))
        return
    end

    if msg == "minimap on" then
        PetAlert:SetMinimapButtonEnabled(true)
        print("|cffff4040PetAlert|r " .. L("minimapMsgEnabled"))
        return
    end

    if msg == "minimap off" then
        PetAlert:SetMinimapButtonEnabled(false)
        print("|cffff4040PetAlert|r " .. L("minimapMsgDisabled"))
        return
    end

    if msg == "minimap lock" then
        PetAlert:SetMinimapButtonLocked(true)
        print("|cffff4040PetAlert|r " .. L("minimapMsgLocked"))
        return
    end

    if msg == "minimap unlock" then
        PetAlert:SetMinimapButtonLocked(false)
        print("|cffff4040PetAlert|r " .. L("minimapMsgUnlocked"))
        return
    end

    if msg == "minimap reset" then
        PetAlert:ResetMinimapButton()
        print("|cffff4040PetAlert|r " .. L("minimapMsgReset"))
        return
    end

    if msg == "test" or msg == "test all" then
        PetAlert:PreviewAlert("all")
        return
    end

    if msg == "test stop" then
        PetAlert:StopAlertPreview()
        print("|cffff4040PetAlert|r " .. L("previewStopped"))
        return
    end

    local testTarget = msg:match("^test%s+(main|missing|hp|lowhp|passive)$")
    if testTarget then
        PetAlert:PreviewAlert(testTarget)
        return
    end

    local presetName = msg:match("^preset%s+(compact|readable|streamer|minimal)$")
    if presetName then
        local ok, label = PetAlert:ApplyPreset(presetName)
        if ok then
            print("|cffff4040PetAlert|r " .. string.format(L("presetApplied"), label or presetName))
        end
        return
    end

    print("|cffff4040PetAlert|r " .. L("commandsHeader"))
    print("  /pa or /pa options")
    print("  /pa move")
    print("  /pa lock")
    print("  /pa reset")
    print("  /pa X Y")
    print("  /pa ooc on")
    print("  /pa ooc off")
    print("  /pa hpmove")
    print("  /pa hplock")
    print("  /pa hpreset")
    print("  /pa hp on")
    print("  /pa hp off")
    print("  /pa hp 25")
    print("  /pa hp X Y")
    print("  /pa passivemove")
    print("  /pa passivelock")
    print("  /pa passivereset")
    print("  /pa passive on")
    print("  /pa passive off")
    print("  /pa passive X Y")
    print("  /pa icon <textureID or texture path>")
    print("  /pa icon reset")
    print("  /pa minimap on")
    print("  /pa minimap off")
    print("  /pa minimap lock")
    print("  /pa minimap unlock")
    print("  /pa minimap reset")
    print("  /pa test")
    print("  /pa test main|hp|passive|stop")
    print("  /pa preset compact|readable|streamer|minimal")
end

-- =========================
-- Events
-- =========================

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        PetAlertDB = PetAlertDB or {}
        DB = PetAlertDB

        for k, v in pairs(DEFAULTS) do
            if DB[k] == nil then
                DB[k] = v
            end
        end

        DB.mainSize = Clamp(DB.mainSize, 40, 300)
        DB.hpSize = Clamp(DB.hpSize, 40, 300)
        DB.passiveSize = Clamp(DB.passiveSize, 40, 300)
        DB.lowHPThreshold = Clamp(DB.lowHPThreshold, 1, 99)
        DB.minimapButtonAngle = Clamp(tonumber(DB.minimapButtonAngle) or DEFAULTS.minimapButtonAngle, 0, 360)
        DB.minimapButtonEnabled = DB.minimapButtonEnabled == true
        DB.minimapButtonLocked = DB.minimapButtonLocked == true
        DB.petHealthBarEnabled = DB.petHealthBarEnabled == true
        DB.petHealthBarWidth = Clamp(DB.petHealthBarWidth or DEFAULTS.petHealthBarWidth, 96, 260)
        DB.petHealthBarHeight = Clamp(DB.petHealthBarHeight or DEFAULTS.petHealthBarHeight, 10, 28)
        DB.petHealthBarR = Clamp(DB.petHealthBarR or DEFAULTS.petHealthBarR, 0, 1)
        DB.petHealthBarG = Clamp(DB.petHealthBarG or DEFAULTS.petHealthBarG, 0, 1)
        DB.petHealthBarB = Clamp(DB.petHealthBarB or DEFAULTS.petHealthBarB, 0, 1)
        if not PET_HEALTH_BAR_THEMES[DB.petHealthBarTheme or ""] then
            DB.petHealthBarTheme = DEFAULTS.petHealthBarTheme
        end
        if DB.petHealthBarTexture == "mana" or DB.petHealthBarTexture == "smooth" then
            DB.petHealthBarTexture = "status"
        end
        if not PET_HEALTH_BAR_TEXTURES[DB.petHealthBarTexture or ""] then
            DB.petHealthBarTexture = DEFAULTS.petHealthBarTexture
        end
        if not PET_HEALTH_BAR_FRAME_STYLES[DB.petHealthBarFrameStyle or ""] then
            DB.petHealthBarFrameStyle = DEFAULTS.petHealthBarFrameStyle
        end
        DB.petHealthBarShowIcon = DB.petHealthBarShowIcon ~= false
        DB.petHealthBarShowPercent = DB.petHealthBarShowPercent ~= false
        DB.petHealthBarShowShine = DB.petHealthBarShowShine ~= false
        DB.petHealthBarBgAlpha = Clamp(DB.petHealthBarBgAlpha or DEFAULTS.petHealthBarBgAlpha, 0, 100)
        DB.petHealthBarBorderAlpha = Clamp(DB.petHealthBarBorderAlpha or DEFAULTS.petHealthBarBorderAlpha, 0, 100)

        if not AUDIO_ALERT_SOUND_BY_KEY[DB.audioAlertSound or ""] then
            DB.audioAlertSound = DEFAULTS.audioAlertSound
        end

        DB.customIcon = NormalizeCustomIconValue(DB.customIcon) or ""
        DB.customIconEnabled = DB.customIconEnabled == true and DB.customIcon ~= ""

        RebuildHPAlphaCurve()

        MainUI = CreateAlertFrame("PetAlertFrame", 1, 0, 0)
        HPUI = CreateAlertFrame("PetAlertHPFrame", 1, 0.82, 0)
        PassiveUI = CreateAlertFrame("PetAlertPassiveFrame", 0.4, 0.8, 1)
        CreatePetHealthBarFrame()
        CreateMinimapButton()

        ApplyMainPosition()
        ApplyHPPosition()
        ApplyPassivePosition()
        ApplyPetHealthBarPosition()
        ApplyMainSize()
        ApplyHPSize()
        ApplyPassiveSize()
        ApplyPetHealthBarLayout()

        inCombat = InCombatLockdown()
        UpdateAll()
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        UpdateAll()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        UpdateAll()
        return
    end

    if event == "UNIT_PET" then
        local unit = ...
        if unit == "player" then
            UpdateAll()
            UpdatePetHealthBarVisibility()
        end
        return
    end

    if event == "UNIT_FLAGS" or event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        local unit = ...
        if unit == "pet" then
            UpdateHPAlert()
            UpdatePassiveAlert()
            UpdatePetHealthBarVisibility()
        end
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "SPELLS_CHANGED"
        or event == "PET_BAR_UPDATE"
        or event == "PET_UI_UPDATE" then
        UpdateAll()
        return
    end
end)

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("UNIT_PET")
f:RegisterUnitEvent("UNIT_FLAGS", "pet")
f:RegisterUnitEvent("UNIT_HEALTH", "pet")
f:RegisterUnitEvent("UNIT_MAXHEALTH", "pet")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("PLAYER_TALENT_UPDATE")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("PET_BAR_UPDATE")
f:RegisterEvent("PET_UI_UPDATE")
