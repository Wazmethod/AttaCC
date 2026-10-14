-- Explanations for editable settings, shared by profilectl menus.
-- New application modules may extend this catalogue with their own help metadata.
local M = {}
local entries = {
    ["app.modules"] = "Modules applicatifs charges sur cette machine. Separes par des virgules.",
    ["app.displayModule"] = "Module responsable de l'interface locale de l'application.",
    ["motor.direction"] = "Sens physique de rotation du moteur. 1 = normal, -1 = inverse.",
    ["sensors.rpm.multiplier"] = "Signe de la vitesse mesuree par le speedometer. -1 inverse le sens logique des RPM.",
    ["peripherals.target"] = "Nom du Create Target utilise par SteamPlant; auto recherche le premier compatible.",
    ["peripherals.speedometer"] = "Nom du speedometer pour lire la vitesse de rotation.",
    ["peripherals.stressometer"] = "Nom du stressometer pour mesurer la contrainte.",
    ["peripherals.motor"] = "Nom du moteur electrique Create a piloter.",
    ["peripherals.accumulator"] = "Nom de l'accumulateur pour les mesures d'energie.",
    ["peripherals.redstoneRelay"] = "Nom du relais redstone optionnel.",
    ["redstone.mode"] = "Mode de sortie: auto, relais redstone ou sorties directes du computer.",
    ["redstone.relayName"] = "Nom exact du relais redstone si plusieurs sont presents.",
    ["redstone.mainClutch"] = "Face redstone commandant l'embrayage principal.",
    ["redstone.alternatorClutch"] = "Face redstone commandant l'embrayage de l'alternateur.",
    ["redstone.genClutch"] = "Face redstone commandant l'embrayage du generateur.",
    ["bootState.main"] = "Etat de l'embrayage principal au demarrage sans etat persistant.",
    ["bootState.alternator"] = "Etat de l'embrayage alternateur au demarrage sans etat persistant.",
    ["bootState.gen"] = "Etat de l'embrayage generateur au demarrage sans etat persistant.",
    ["bootState.motorRPM"] = "RPM de demarrage si aucun etat sauvegarde n'est present.",
    ["procedure.motorRPM"] = "Vitesse du moteur pendant la procedure de demarrage.",
    ["procedure.minRPM"] = "RPM minimum pour confirmer la sequence de demarrage.",
    ["procedure.stableMs"] = "Duree minimale de stabilite en millisecondes.",
    ["procedure.timeoutMs"] = "Delai maximum de la procedure en millisecondes.",
    ["procedure.transferDelayMs"] = "Delai avant transfert mecanique, en millisecondes.",
    ["procedure.autoRestartDelayMs"] = "Attente avant tentative de redemarrage automatique, en millisecondes.",
    ["procedure.verifyRunningMs"] = "Delai pour verifier que la chaudiere passe en RUNNING.",
    ["procedure.maxAutoAttempts"] = "Nombre maximum de tentatives de redemarrage automatique.",
    ["procedure.retryDelayMs"] = "Attente entre deux tentatives automatiques.",
    ["detection.offlineRpm"] = "Seuil RPM sous lequel une machine peut etre consideree a l'arret.",
    ["detection.offlineCapacity"] = "Seuil de capacite pour detection de l'arret.",
    ["detection.onlineRpm"] = "Seuil RPM pour une machine consideree active.",
    ["detection.onlineCapacity"] = "Seuil de capacite pour detection du fonctionnement.",
    ["detection.offlineConfirmMs"] = "Duree de confirmation avant de signaler l'arret.",
    ["detection.recoveryConfirmMs"] = "Duree de confirmation avant de signaler le retour.",
    ["display.preferred"] = "Backend d'affichage: text, auto ou ccgraphics.",
    ["display.textScale"] = "Echelle des caracteres des moniteurs CraftOS en mode texte.",
    ["display.graphicsMode"] = "Resolution graphique CC:Graphics demandee.",
    ["display.forceTextScale"] = "Appliquer l'echelle texte avant la detection du mode graphique.",
    ["display.touchProfile"] = "Profil de correspondance des zones tactiles du moniteur.",
    ["display.textPages"] = "Ordre des pages en mode texte.",
    ["display.tabs"] = "Onglets affiches par l'interface graphique.",
    ["display.graphicsToggle"] = "Autoriser le changement manuel entre affichages texte et graphique.",
    ["pocket.transport"] = "Source de donnees: master pour le relais central ou direct pour la machine.",
    ["pocket.sourceModule"] = "Module de machine prefere comme source de donnees sur le Pocket.",
    ["timing.appTickSeconds"] = "Intervalle entre deux rafraichissements applicatifs.",
    ["timing.masterPushSeconds"] = "Intervalle des envois de statut Master vers Pocket.",
    ["timing.sourceStaleMs"] = "Anciennete maximale avant qu'une source soit signalee stale.",
    ["timing.masterTimeoutMs"] = "Temps sans nouvelles avant de considerer le Master indisponible.",
    ["timing.commandRetryMs"] = "Delai entre les tentatives de commande.",
    ["timing.commandMaxRetries"] = "Nombre maximal de tentatives de commande.",
    ["events.historySize"] = "Nombre d'evenements conserves localement.",
    ["storage.backend"] = "Type de stockage serveur: auto, local ou drive. A changer sur l'hote.",
    ["storage.driveLabel"] = "Label du disque utilise par l'hote Storage.",
    ["storage.drivePath"] = "Chemin relatif du fichier de donnees sur le disque.",
    ["storage.file"] = "Chemin du fichier Storage local.",
}
function M.describe(path)
    if entries[path] then return entries[path] end
    if path:match("^channels%.") then return "Canal de communication modem. Changer uniquement de facon coherente sur tout le reseau." end
    if path:match("^io%.bindings%.") then return "Liaison I/O logique; definit quel peripherique ou face redstone utiliser." end
    if path:match("^peripherals%.") then return "Nom du peripherique physique, ou auto pour la recherche automatique." end
    if path:match("^master%.home%.") then return "Visibilite du widget correspondant sur la page d'accueil Master." end
    return "Parametre " .. path .. " defini par le preset ou le module; consulter la documentation du module avant modification."
end
return M
