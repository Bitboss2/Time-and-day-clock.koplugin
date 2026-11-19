# Atelier Clock

**0.3.0 « Fluide » — 19 novembre 2026.** Dix cadrans `.clock`, collection, éditeur de complications et un atelier plein écran animé, pensé pour le moteur **Fluid Ink 6.5**.

## Affichage fluide

L'atelier compose ses images en niveaux de gris 8 bits à partir de couches gardées en mémoire, puis les transmet au moteur Fluid Ink embarqué (`engine/fluidink`) :

- **Kobo Aura Edition 2 v1** : Fluid Ink v6, **Impulsions 2**, profil **Débit** (file 1, Bayer 8×8, sans gamma), 30 ips ciblées. Le profil à impulsions a besoin de **votre** copie `factory-reference.bin`, à placer dans `engine/fluidink/` ; elle n'est pas redistribuée. Sans elle, ou si le noyau refuse les impulsions, le plugin bascule en v6 sans impulsions.
- **Autres liseuses compatibles avec Fluid Ink** (Aura 2 v2, Aura H2O 2, Glo HD, Aura One, Clara HD, Kindle PW2/PW3/Voyage) : Fluid Ink v6 sans impulsions, A2 en mouvement et DU au repos.
- **Partout ailleurs**, ou si la vérification du moteur échoue : affichage classique de KOReader, avec les mêmes écrans et les animations remplacées par leur état final.

Le moteur est vérifié en mémoire dans un processus séparé avant toute utilisation. Il reste le seul à écrire sur l'écran pendant l'atelier :

- Pour une saisie de texte, il s'arrête, restaure la table d'origine, puis reprend. Le premier affichage après la reprise peut flasher (GC16).
- Avant chaque veille, il s'arrête de façon synchrone. L'horloge de veille n'utilise jamais Fluid Ink.
- En paysage ou en mode nuit, l'atelier reste en affichage classique.

**Diagnostic → Affichage** montre le moteur actif, son profil et les cibles et scans par seconde. On y règle aussi le moteur (Automatique, Fluide, Classique), la cadence (30, 45, 60 Hz), le nettoyage au repos et les animations (complètes ou réduites), et on peut nettoyer l'écran ou réessayer le moteur. Les compteurs ne mesurent pas la cadence optique : celle-ci se vérifie à la caméra sur la dalle.

## Réveil selon la liseuse

- **Kobo** : RTC matériel par `WakeupMgr`, suspension gérée par KOReader. C'est le cas des sept modèles compatibles avec Fluid Ink.
- **Kindle** Paperwhite 2/3 et Voyage : `WakeupMgr` avec `mockrtc`, via powerd. Il faut que KOReader gère l'écran de veille. powerd suspend lui-même la liseuse ; un garde rattrape la minute si la liseuse est restée éveillée ou si une alarme passée a été supprimée. La précision est d'environ 15 s, et 5 minutes sont conseillées.
- **Sans réveil programmable** : l'horloge est figée à l'endormissement, avec un message.

## Activer le profil Aura 2

Après mise à jour, ouvrir **Veille → Optimiser pour Aura 2 → Appliquer**. Ce bouton active le traitement rapide du réveil propre à l’horloge, la réutilisation conditionnelle de la préparation de suspension et une marge après affichage de 0,1 seconde. Il ne modifie pas l’intervalle choisi : conserver **1 minute**. Il ne modifie pas non plus la pause nocturne ou le nettoyage configuré.

La réutilisation exige une API native compatible, un sommeil précédent validé, une attente écran fiable, le Wi-Fi éteint, l’absence de charge et le drapeau noyau `state-extended` encore à 1. Elle est revalidée au moment de s’exécuter. Le mode RTC minute confirmé utilise à la place la veille native `standby` avec son drapeau zéro ; les autres cas conservent la préparation native complète. L’option se désactive dans les autres réglages d’énergie.

Un retour trop court désactive la réutilisation de la préparation profonde. Sur le modèle FP9928 confirmé, la veille RTC minute peut prendre le relais ; un échec de ce mode conserve le repli natif pour la session. Les autres alarmes restent dans la file native. Le réveil utilisateur annule la demande différée. Aucun gouverneur CPU, noyau, pilote ou état sysfs n’est modifié directement par le plugin.

## Installation ou mise à jour

1. Quitter complètement KOReader.
2. **Remplacer le dossier entier** `atelierclock.koplugin` dans le dossier `plugins` de KOReader par celui de ce ZIP. Éviter de fusionner les dossiers : cela conserverait les dix anciens cadrans. Sur de nombreuses Kobo, le chemin est `.adds/koreader/plugins/atelierclock.koplugin`.
3. **Conserver `settings/atelierclock`**, qui contient les préférences et les imports personnels. Les réglages RTC, de nettoyage, d’orientation et de taille de l’interface sont conservés.
4. Éjecter la Kobo, relancer KOReader et ouvrir **Outils → Plus d’outils → Atelier Clock**. Activer l’extension dans la gestion des plugins si nécessaire.
5. Dans **Veille**, activer l’horloge. L’option **Horloge Atelier** est aussi présente dans le menu natif d’écran de veille KOReader, dans le lecteur et dans le navigateur de fichiers.

Au premier lancement de la nouvelle collection, le cadran actuellement disponible est ajouté à « Mes cadrans ». Si l’ancien modèle a été retiré de la collection fournie, **Totem** prend sa place. Les anciens paramètres ne sont pas effacés ; les déplacements libres, polices personnalisées et fonds par image concernent les imports `.clock` v1. Les nouvelles compositions v2 utilisent leurs styles et emplacements propres.

## Parcourir et personnaliser

- **Cadrans → Mes cadrans** : un carrousel à faire glisser du doigt ; il garde l'élan puis s'accroche à un cadran, et les voisins dépassent sur les bords. Parcourir ne change pas l'horloge active. **Utiliser** sélectionne et enregistre. **▶** lance l'essai plein écran, avec un zoom depuis l'aperçu.
- **⋯** (ou un appui long sur la carte) ouvre une feuille : **Dupliquer**, **Renommer**, **Afficher en plein écran**, **Retirer**. On peut avoir jusqu'à 24 variantes ; retirer une variante conserve son modèle dans le catalogue.
- **Catalogue** : les dix modèles et vos imports. **Ajouter** crée une variante personnelle et ouvre l'éditeur. **Importer** accepte le chemin complet d'un `.clock`.
- **Modifier → Style** : Plein, Fin ou Contour selon le cadran, et apparence Papier, Encre ou Auto.
- **Modifier → Modules** : toucher un cadre **+**. Une feuille monte avec le rendu réel de chaque complication compatible ; le contenu choisi rejoint son emplacement.
- **Modifier → Options** : nommer la variante, exporter un `.clock`, choisir l'orientation, le format horaire, la langue, le format de date et la taille de l'interface.

Les modifications restent dans un **brouillon**. La barre *Brouillon · Annuler · Appliquer* n'apparaît que lorsqu'il y a quelque chose à appliquer, et fermer l'atelier avec un brouillon demande confirmation. Les listes défilent avec de l'inertie et un bord élastique ; un balayage horizontal change d'onglet, ou de mode dans Modifier. L'éditeur libre reste disponible pour les imports v1 : faire glisser les éléments sur l'aperçu, puis passer par les six sections de réglages.

Les aperçus reflètent l'heure au moment du dessin. L'interface tient compte du DPI, se réorganise en paysage et sur les écrans compacts, et peut être agrandie.

## Les dix modèles inclus

| Fichier | Composition originale |
|---|---|
| `totem.clock` | Deux étages de chiffres monumentaux ; date et anneau de batterie. |
| `duplex.clock` | Deux panneaux contrastés et deux complications rectangulaires. |
| `index.clock` | Règle de 24 heures, heure décentrée, deux cartouches. |
| `halo.clock` | Aiguilles et graduations fines, deux anneaux personnalisables. |
| `journal.clock` | Grande heure et vrai calendrier mensuel, jour courant encadré. |
| `lisiere.clock` | Paysage à l’encre, heure sobre et sceau circulaire. |
| `mosaique.clock` | Un grand module et deux petits autour de l’heure. |
| `octant.clock` | Médaillon de l’heure courante et arc des minutes. |
| `typo.clock` | Le temps écrit en mots, composition littéraire. |
| `signal.clock` | Afficheur géométrique à sept segments, sans animation. |

Chaque modèle possède une vraie disposition portrait **et une autre disposition paysage**. Les dix `.clock` sont des ZIP DEFLATE avec JSON, textures PNG originales et aperçu produit par le moteur Lua. Aucune heure n’est gravée dans les textures.

## Complications hors ligne

Les sept contenus disponibles sont : **Vide**, **Date**, **Batterie**, **Journée**, **Semaine**, **Autre fuseau** et **Lecture**. Les familles sont ligne, anneau et rectangle. Leur rendu s’adapte à la place prévue.

- Le calendrier se calcule localement et prend en compte les longueurs de mois et les années bissextiles.
- Journée est une progression indicative par quarts d’heure ; la règle Index évolue toutes les cinq minutes. L’heure principale continue à suivre le profil RTC choisi.
- Les fuseaux embarqués sont UTC, Paris, Londres, New York et Tokyo, avec transitions IANA 1970–2100. Pour changer de ville, rouvrir le module de seconde horloge puis toucher le bouton du fuseau en bas du sélecteur.
- Lecture affiche le titre et le pourcentage enregistrés par KOReader au début de la scène. Cette photographie de lecture ne crée aucune tâche ni lecture de métadonnées à chaque minute. Si elle est indisponible, le module affiche un tiret et une indication explicite.
- Une charge de batterie inconnue reste indiquée comme inconnue.

Aucune météo fictive, connexion réseau ou tâche de synchronisation n’est créée pour ces modules.

## Importer et exporter

Dans le catalogue, **Importer** accepte le chemin complet d’un fichier. Les v1 restent lisibles ; les nouveaux exports sont en v2. Un identifiant de modèle déjà présent est refusé ; pour créer plusieurs versions visuelles du même modèle, utiliser **Dupliquer**.

Depuis **Modifier → Options → Exporter en .clock**, choisir un nouveau chemin. L’export contient la composition, les textures, un aperçu de la variante et son préréglage de style/complications. Il est validé avant publication et peut être réimporté, avec un nouvel identifiant. Il n’écrase pas un fichier existant. Le chemin proposé est `settings/atelierclock/exports/…`. Les exports de cadrans ne contiennent pas les réglages RTC personnels.

Un profil de tous les réglages reste importable/exportable via **Diagnostic → Outils → Profil** : chemin JSON existant pour importer, nouveau chemin pour exporter. L’import d’anciens fichiers Lua analyse uniquement les tables littérales et n’exécute aucun code.

## Rendu et énergie

Le moteur v2 garde le fond et les éléments déjà dessinés en mémoire. Date, calendrier, décor et progression de lecture ne sont pas recalculés à chaque minute. Les heures et minutes sont séparées dans Totem, Duplex et Signal. Les graduations analogiques sont mises en cache ; les nouveaux et anciens tracés d’aiguilles sont inclus dans la zone à effacer.

Les fenêtres de rafraîchissement disjointes restent séparées jusqu’à quatre fenêtres ; au-delà, le plugin demande une fenêtre englobante. Pour les chiffres et les aiguilles ordinaires, les fenêtres sont resserrées sur les anciens et nouveaux tracés. Les nettoyages complets configurés et les protections KOReader sont conservés. Les rafraîchissements réguliers de veille utilisent le mode `ui` : ils ne consomment plus le compteur de pages du lecteur, qui pouvait provoquer des nettoyages supplémentaires indépendants du réglage du cadran. La mesure de batterie nécessaire au seuil d’arrêt est réutilisée par les complications durant le même réveil.

La séquence simulée de 60 minutes à 758×1024 a été recalculée avec le scan adaptatif. **Les fenêtres demandées ne sont pas une mesure d’économie de batterie.** Les peintures initiales et nettoyages complets sont exclus de ce comparatif et restent actifs. KOReader et le contrôleur peuvent aligner ou promouvoir les rafraîchissements. Les chiffres complets et les limites sont dans `docs/RENDER_MEASUREMENTS.json`.

À une minute, le nombre d’alarmes reste identique. La première suspension conserve sa préparation native complète. Après un réveil propre à l’horloge, la bêta 4 peut éviter sa répétition : elle appelle la phase native `_doSuspend` après avoir attendu la fin du rafraîchissement, uniquement si le drapeau de préparation est encore actif. La synchronisation disque native, la suspension `mem` et la gestion des erreurs restent exécutées. On ne peut donc pas promettre quelques points de batterie par semaine à partir de ces seules optimisations graphiques.

**Veille** conserve les profils 1 minute, 5 minutes, 15 minutes et statique, avec mention visible lorsque l’heure est approximative ou figée. La pause nocturne suspend les actualisations jusqu’à l’heure de reprise. Ces compromis ne sont jamais activés silencieusement. Le seuil de batterie arrête les réveils pour la session.

L’option de réveil prioritaire/RTC accéléré reste limitée aux Aura 2 reconnues (`Kobo_star`, `Kobo_star_r2`) et désactivée par défaut sur une installation neuve. Une préférence existante est conservée. Elle utilise le contrôle natif KOReader à 0,2 seconde après une échéance propre au plugin ; les autres alarmes, délais de grâce et protections de suspension restent respectés. Sans accélération, le garde natif peut attendre environ 15 secondes.

## Vérifier sur la Kobo

**Diagnostic → Outils → Détails techniques** indique maintenant le sommeil cumulé, sa proportion dans la session, le délai entre réveil et nouvelle demande de sommeil, les préparations réutilisées, le motif d’un retour au mode natif et notamment le temps CPU du rendu, la surface de rafraîchissement demandée, le délai d’alarme, les rattrapages et l’évolution de la charge pendant la dernière session. Le temps CPU du dessin n’est pas la durée totale d’éveil. **Suspension précédente** est maintenant décodée via `ui/time` : les `2787663 s` de la bêta 3 représentaient en réalité **2,787663 secondes**. La conversion est également appliquée au seuil de validation de sommeil, pour ne plus confondre une suspension de quelques microsecondes avec une seconde. Les chiffres de charge sont des points de la jauge, pas une mesure électrique calibrée.

Pour une comparaison utile avec l’essai précédent, garder le même intervalle, l’option RTC et l’éclairage, commencer à charge comparable et relever les heures de début/fin. Un essai avec **Halo** est intéressant pour son petit rectangle d’aiguilles ; vérifier aussi l’absence de traces résiduelles après plusieurs heures. Le cumul est figé à la sortie de la session, pour que le temps passé à consulter le diagnostic ne soit pas ajouté à l’éveil de cette session. Le rapport JSON contient également les capacités détectées, la version du noyau et les 120 derniers échantillons de sommeil, conservés en RAM. L’export manuel écrit `settings/atelierclock/diagnostic.json` ; la fin normale de session écrit une fois `settings/atelierclock/last-session.json`.

L’horloge manuelle se ferme au toucher ; l’appui long ouvre l’atelier. Elle ne bloque pas l’auto-suspension. Pendant la vraie veille Kobo, utiliser le bouton ou la sleepcover : le tactile n’est pas nécessairement alimenté. Les écrans d’extinction et de redémarrage restent gérés par KOReader.

Pour retirer le plugin, désactiver d’abord l’horloge dans **Veille**, quitter KOReader puis supprimer son dossier. Si le dossier est déjà supprimé, sélectionner un écran de veille standard dans KOReader.

Format et limites : `docs/CLOCK_FORMAT.md`. Tests et limites matérielles : `docs/VALIDATION.md`. Références de conception : `docs/DESIGN_RESEARCH.md`.
