# Validation — 0.2.5-beta.9

1er novembre 2026. **156 tests automatisés réussis, deux runs KOReader x86/ARM, 15 vérifications C des fonctions publiées. Aucun gain électrique ×7 certifié.**

La suite ajoute le rejeu du code bêta 8 livré, qui reproduit une utilisation du pont puis le même repli observé dans les logs. Le modèle distingue le temps actif du délai de pilote et le temps suspendu. Le nouveau chemin passe avec un délai arrêté ou avançant pendant la suspension, sans alarme technique et sans transition profonde à chaque minute. Les bornes de réveil anticipé, les exceptions, la restauration du gouverneur, les changements de session et l’annulation pendant des hooks natifs sont testés.

Les compteurs sont remis à zéro à la session ; l’export après arrêt conserve son intervalle réel. Un refus natif mesuré à 4,46 s reste détecté par le drapeau, avec les protections d’échecs conservées. Les résultats et hypothèses sont dans `RTC_STANDBY_SIMULATION.json`, `BETA8_REPLAY.json` et `BETA8_FIELD_REPORT.json`. Le détail courant est [INVESTIGATION_BETA9.md](INVESTIGATION_BETA9.md).

KOReader officiel v2026.07.1 Linux SDL est exécuté en x86_64 et ARMv7/QEMU Cortex-A9, 758×1024 à 212 DPI : dix paquets, éditeur, export, rendus à la minute et paysage. Le runtime ne reçoit qu’une protection d’un message de log SDL_GetBasePath contre NULL. Le firmware utilisateur a v2026.07.2. QEMU user mode utilise le noyau hôte et ne reproduit pas les courants ou périphériques Kobo. Les contrôles C sont des fonctions originales avec témoins périphériques. Ces tests démontrent des chemins logiciels, pas une consommation. Preuves sous `validation/beta9` dans le ZIP.

Les sections suivantes documentent aussi les mécanismes et scénarios historiques conservés. Le pont court de bêta 8 est retiré du code de production ; ses sources de référence restent dans les fixtures de test.

## Suite exécutée

156 tests automatisés, dont 19 contrôles v2, 28 contrôles du cycle de suspension à la minute, 14 contrôles de récupération 12 contrôles de différence de pixels 11 contrôles de propriété des callbacks, de lecture noyau et de sauvegarde, et 28 contrôles FP9928/alarmes et le contrôle supplémentaire des refus longs. Le résultat complet se trouve dans `tests/test-results.txt` à la racine de la distribution.

- Compilation des modules par LuaJIT 2.1, syntaxe Lua 5.1.
- Ouverture des dix ZIP réels avec l’archiveur officiel KOReader et `libarchive.so.13` ; validation de manifeste, PNG et enveloppe ZIP.
- Rejet des chemins traversants, liens, chiffrement, troncatures, ressources trop grandes, types de blocs inconnus, dispositions hors écran ou superposées, fournisseurs et préréglages invalides.
- Validation des dix manifestes v2 et du témoin v1 par le schéma JSON et par le lecteur Lua.
- Collection persistante, duplication indépendante des complications, limites de taille et traitement des enregistrements incorrects.
- Export réel DEFLATE d’une variante, réimport par le lecteur réel, conservation du style/fuseau, refus d’écrasement et suppression des fichiers temporaires.
- Dessin des dix cadrans en portrait/paysage et clair/sombre, comparaison de chaque style proposé, rendu de tous les fournisseurs dans les familles déclarées.
- Stabilité : aucun redessin de tuile à données identiques ; minutes indépendantes des heures pour les modèles empilés ; calendrier et date conservés tant qu’ils ne changent pas.
- Couverture **des pixels réellement modifiés** par l’ensemble des rectangles de rafraîchissement : chaque cadran, deux orientations, minute normale et frontières de jour/mois.
- Midi/minuit en 12 h, changement de mois bissextile, transitions de fuseaux et reprise de pause nocturne.
- Navigation sans changement implicite de sélection, ajout au brouillon, toucher de complication → choix graphique → sauvegarde ; balayage sans déplacement accidentel.
- Vues à 600×800/167 DPI, 758×1024/212 DPI et 1072×1448/300 DPI ; paysage et interface 140 % ; zones tactiles dans leur écran et hors du pied de page.
- Réutilisation de la mesure de batterie du cycle, instantané de lecture lu une seule fois, absence de nouveaux timers de complications et libération des buffers retenus.
- Maintien des nettoyages complets configurés et de la compatibilité d’import des anciens `.clock` v1, y compris leur éditeur de positionnement et fonds JSON par image.
- **10 080 cycles RTC simulés** avec la vraie file WakeupMgr : une seule tâche propre, conservation des alarmes étrangères, annulation après réveil utilisateur.
- **90 cycles avec les méthodes Kobo officielles**, collisions périodiques d’alarmes, retard de 75 secondes, erreur de validation RTC, grâce étrangère de 29 secondes et ordres inversés de callbacks.
- Préservation de la protection contre les échecs de suspension ; une ancienne durée de sommeil ne suffit pas à réinitialiser le budget natif. Arrêt après trois erreurs de rendu consécutives ; les erreurs transitoires séparées ne s’additionnent pas en arrêt fatal.
- Échec d’armement matériel malgré un cache RTC mis à jour, marge avant suspension, absence de déclenchement accéléré avant l’échéance.
- Intégration répétée dans le vrai menu screensaver, service partagé lecteur/navigateur, réouverture, restauration de rotation et fermeture manuelle.

## Mesures de travail de rendu

`tools/measure_render.py` exécute 60 minutes simulées pour chaque nouveau cadran, au même instant initial et avec les mêmes réglages. `docs/RENDER_MEASUREMENTS.json` donne le nombre de tuiles redessinées et les surfaces demandées, avant alignement/promotion par KOReader et le contrôleur.

Les chiffres du JSON sont recalculés avec le scan adaptatif de bêta 6. Le scan peut être sauté pendant sept changements après trois observations de faible gain ; la surface peut alors augmenter, afin d’éviter un coût CPU répété pour une économie graphique mineure. Ce comparatif exclut le dessin initial et les nettoyages complets configurés ; il ne mesure ni l’énergie ni la vitesse du scan sur ARM.

Le nombre de tuiles retenues est comparé à une reconstruction complète **du même nouveau dessin**. Il ne s’agit pas d’un comparatif énergétique avec un ancien cadran graphiquement différent. Aucun pourcentage d’économie électrique n’est dérivé de ces mesures.

## Dépendances de référence

- KOReader `cad5c8d72dd02b39dee388c6e0c43170bcd91dab` : file de réveil, méthodes Kobo et menu de veille.
- koreader-base `007ac6a81e2de4822c8df7ce57b8dbb06aa3b8ea` : archiveur FFI, entêtes libarchive/posix.

`tools/fetch_test_dependencies.py` récupère les fichiers nécessaires. L’archiveur est réellement exécuté ; les surfaces et interfaces sont simulées. Le rendu Pillow utilise des polices de substitution DejaVu. Les tests ne constituent pas un lancement complet de KOReader SDL.

## Limites matérielles

Les 10 080 cycles, 90 cycles et 180 cycles du nouveau chemin sont accélérés en avançant le temps ; ce ne sont ni sept jours ni 90 minutes d’endurance physique. Le noyau, le contrôleur e‑ink, la batterie, les entrées tactiles et les temps d’éveil ne sont pas mesurés. Un appel de retour en veille ne démontre pas à lui seul la réussite de `mem`.

Le dessin v2 conserve davantage de buffers pour éviter les calculs répétés. Les fermetures sont vérifiées par la suite, mais la stabilité de la RAM native doit être contrôlée sur Kobo. Les traces résiduelles après rafraîchissements très resserrés, notamment les aiguilles de Halo, doivent également être observées sur appareil.

Le réveil d’affichage reste à la minute ; la veille RTC minute utilise l’alarme existante sans réveil technique intermédiaire. La première suspension conserve toutes les étapes de préparation natives. Après un vrai sommeil RTC et la fin du rafraîchissement, la nouvelle voie peut réutiliser la préparation encore active et appeler la phase native `_doSuspend`. Elle conserve `sync`, l’écriture `mem`, les erreurs et le contrôle de réveil du code officiel. Elle ne modifie pas le gouverneur CPU et ne désactive pas les protections natives. **Aucune autonomie hebdomadaire précise n’est validée.**

## Prochaine comparaison physique

Garder l’intervalle, l’éclairage, le Wi-Fi et le réglage RTC identiques à l’essai précédent. Essayer plusieurs heures avec Halo ou Journal, puis exporter Diagnostic pour relever : début/fin de charge, temps de session, dernière surface demandée, temps CPU de rendu, retard d’alarme et durée de sommeil native. Vérifier bouton, sleepcover et absence de résidus. Une veille témoin avec les mêmes conditions distingue le coût de base du surcoût de l’horloge.

Les problèmes de gel traités en bêta 2 restent couverts par leurs scénarios de régression : ce mécanisme n’a pas été réécrit pour la collection v2.


## Régression d’unité et séquence native complète

Les tests utilisent maintenant le vrai module `ui/time.lua` : `time.s(55)` est bien une valeur fixe en microsecondes, distincte du nombre 55. Les anciens tests synthétiques mettaient des secondes dans les champs natifs ; ils masquaient le bug. La conversion sert à la fois à l’affichage et au seuil d’une seconde qui autorise la remise à zéro du budget d’échecs. Un échec natif de 50 ms ne passe plus ce seuil.

La nouvelle suite exécute les vraies méthodes `Kobo:suspend`, `_doSuspend`, `resume`, `rescheduleSuspend`, le garde de réveil et `WakeupMgr`, avec une horloge virtuelle. Les écritures noyau, la durée du contrôleur et `sync` sont substitués. Le premier sommeil passe bien par la préparation de deux secondes. Après un réveil valide, l’attente de deux secondes n’est plus reprogrammée si l’écran est terminé et le drapeau encore actif.

Dans le scénario contrôlé, le garde de 0,2 s, une attente écran **supposée** de 0,12 s et une marge de 0,3 s donnent 0,62 s entre réveil et appel de la phase finale, contre 2,62 s avec la préparation complète. `sync` reste ensuite exécuté dans les deux cas. **Ces durées sont celles du scénario, pas des mesures sur Aura 2.** Le test démontre le chemin de contrôle et les deux secondes évitées, pas une économie électrique de 76 %.

180 cycles simulés vérifient une seule alarme propre et 179 préparations réutilisées, après la préparation initiale. Les contrôles couvrent aussi : drapeau absent/inactif, changement de drapeau avant exécution, API modifiée par un autre plugin, attente écran absente/en erreur/non fiable/explicitement contournée, réveil utilisateur, désactivation après sommeil trop court et rétablissement du mode natif. La protection après 21 échecs natifs reste effective.

Une alarme étrangère future à 29 secondes ne maintient plus automatiquement le CPU éveillé pendant cet intervalle : elle reste armée dans la RTC partagée. Les alarmes imminentes et les délais de traitement d’une tâche déjà réveillée conservent leur fenêtre native.

Le cumul du sommeil et le temps écoulé utilisent les conversions officielles ; le ratio est figé à la sortie de la session. Les 120 derniers échantillons restent en RAM. Une lecture native inchangée n’est pas comptée deux fois. L’export JSON contient des champs avec suffixe `_s` pour les secondes et les capacités détectées.

La voie de réutilisation est limitée au modèle **Kobo_star** identifié sur les photos. La révision `Kobo_star_r2` conserve la voie native de suspension. Le comportement du noyau et les traces d’affichage doivent être validés physiquement sur le firmware installé.

Le réseau et la charge sont vérifiés avant planification et de nouveau avant la phase réutilisée. Wi-Fi actif, charge en cours ou statut inconnu gardent la préparation native complète, qui traite ces conditions. Une nouvelle demande de suspension complète d’un autre composant remplace également toute demande de réutilisation en attente.

## Retours courts — scénario ajouté après les photos bêta 5

Le scénario de `docs/RECOVERY_SIMULATION.json` introduit un retour natif de 0,462 s après chaque mise à jour, puis une entrée réussie au second essai. Il utilise les vraies méthodes natives avec horloge/écran/sysfs simulés, une attente écran supposée de 0,12 s, une marge de 0,3 s et un `sync` supposé de 0,015 s. En conservant les 15 s de garde, 90 cycles donnent 67,610 % du temps dans les appels natifs, dont 66,848 % de sommeil selon les horloges simulées. Avec le garde borné, ces valeurs deviennent 90,682 % et 89,921 %. Le nombre de tentatives reste le même ; seule l’attente après le retour court est raccourcie. **Ce scénario n’établit ni la cause réelle sur la Kobo, ni une économie électrique.**

Les tests vérifient le garde 1 s puis 2 s, le retour à 15 s après deux essais, l’expiration à 12 s, le maintien de la préparation complète, l’annulation par réveil utilisateur ou demande étrangère, la conservation des grâces/tâches étrangères et du budget d’échecs. Ils couvrent un refus de `mem` et un vrai sommeil très court. La première suspension n’est pas accélérée.

La mesure BOOTTIME moins MONOTONIC distingue un refus de 50 ms (zéro sommeil vérifié) d’une véritable suspension. Si ces horloges ne sont pas disponibles, aucun pourcentage de sommeil vérifié n’est fabriqué ; les durées natives restent exportées séparément. Les 120 dernières tentatives sont bornées en RAM, avec trois premiers rapports courts au maximum et des statistiques noyau seulement si déjà accessibles.

Le scan natif des lignes identiques conserve la couverture des pixels sur les dix cadrans et les données FFI avec pas mémoire différents. Le mode adaptatif saute les faibles gains puis réévalue le scan ; les modèles clair/sombre, les styles et les nettoyages restent inchangés.


## Bêta 7 : propriété, traces et sortie

Une demande propre reste reconnue avec une lecture d’horloge décalée de −0,5 ms ou une exécution retardée de 1,25 s. Son marqueur n’est pas transmis à la fonction native. Une demande externe révoque l’autorisation et `resume()` annule toujours la même référence de callback. Les conditions réseau/charge, les tâches étrangères, l’expiration et les bornes d’échecs restent vérifiées par la suite existante.

Le lecteur de journal utilise `klogctl(3)`, lecture seule et bornée à 16 Kio. Il ne vide pas le tampon. Le refus d’accès, l’absence du symbole libc et les appareils non Kobo sont couverts. Les différences de tampon ne sont marquées vérifiées qu’après vérification du recouvrement. Les captures cessent après les trois premiers retours courts. Le rapport `last-session.json` est écrit une seule fois à la sortie, par fichier temporaire puis renommage. Erreur de disque, de sérialisation ou de renommage : le réveil utilisateur et l’arrêt de la tâche RTC restent possibles.

## 0.3.0 — interface 30 Hz, Fluid Ink, RTC multi-liseuses

- 169 tests passent, dont 13 nouveaux :
  - `test_fluid_ui.py`, 8 tests : profils, mouvement, démarrage Impulsions 2 / Débit sans rafraîchissement KOReader, carrousel et feuille, libération et reprise pour la saisie, veille et réveil, impulsions refusées, chien de garde, animations réduites ;
  - `test_rtc_devices.py`, 5 tests : sept Kobo, chaîne `dodgy_rtc`, trois Kindle via powerd et mockrtc, Kindle sans écran de veille KOReader, profil 10 minutes complet.
- Le moteur natif est **simulé** dans les tests. Ni la cadence optique, ni les traces, ni le coût CPU réel de l'atelier à 30 Hz sur Cortex-A9, ni le réveil Kindle n'ont été mesurés sur appareil.
- Les captures et les GIF de `docs/media` sont des images réellement composées par le plugin, avec des polices de substitution. Ce ne sont pas des photos de dalle.
