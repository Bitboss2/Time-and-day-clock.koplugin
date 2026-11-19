# Journal des changements

Ce document compare **Atelier Clock 0.3.0** à la **dernière version publiée sur GitHub**, *Time & Day* (`dtdisplay`, commit `58930ab`). Les changements sont regroupés selon leur origine :

- **Partie A** : le travail d'Atelier Clock jusqu'à la **0.2.5-beta.9** (l'archive fournie, qui sert de base).
- **Partie B** : la **0.3.0**, refonte de l'interface à 30 Hz, intégration de Fluid Ink et RTC multi-liseuses.

La Partie C fait correspondre les fonctions de *Time & Day* à leur équivalent actuel.

---

## Vue d'ensemble

| | GitHub : Time & Day | 0.2.5-beta.9 | **0.3.0** |
|---|---|---|---|
| Nom et dossier | `dtdisplay`, fichiers à la racine | `atelierclock.koplugin` | idem |
| Cadrans | 5 styles codés en dur | 10 cadrans `.clock` v2 (ZIP + JSON + textures), import v1/v2 | idem |
| Personnalisation | Customizer par menus et curseurs | Collection, variantes, emplacements de complications, éditeur libre v1 | Même périmètre, interface redessinée |
| Interface | Widgets KOReader | Canevas natif plein écran, pages numérotées | **Canevas animé 30 Hz : défilement inertiel, carrousel, feuilles, transitions** |
| Affichage | Rafraîchissements KOReader | Rafraîchissements KOReader, fenêtres resserrées (≤ 4) | **Fluid Ink 6.5 embarqué** (Impulsions 2 / v6), repli classique |
| RTC | Boucle de réveil à la minute | Tâche RTC unique, adaptateur Kobo Aura 2, veille FP9928 | **+ Kindle (powerd/mockrtc), vérification sur 10 modèles, correctifs** |
| Diagnostic | — | Détails, export JSON, rapport de session | **+ moteur d'affichage et capacité RTC** |
| Tests | Aucun | 156 | **168** |
| Licence | AGPL-3.0 | MIT (code) + CC0 (cadrans) | MIT (code Atelier) + moteur GPL/AGPL, ensemble selon `LICENSE` |

---

## Partie A — de Time & Day à Atelier Clock 0.2.5-beta.9

Cette partie résume les bêtas 1 à 9. Atelier Clock y est une réécriture indépendante : son code ne reprend pas celui de *Time & Day* ou de `dtdisplay`.

### Architecture

- Le plugin est découpé en modules :
  - `core` : réglages, calendrier, fuseaux, collection, import littéral des anciens profils ;
  - `packages` : lecture et validation ZIP/JSON, export ;
  - `render` : moteurs v1/v2, tuiles conservées, régions modifiées ;
  - `power` : tâche RTC, adaptateur Kobo, mesures, preuves noyau ;
  - `integration` : écran de veille et menus ;
  - `ui` : galerie et atelier.
- Un seul service est partagé entre les instances lecteur et gestionnaire de fichiers. Aucun `package.path` global n'est modifié.
- Les réglages sont validés par schéma, écrits de façon atomique dans `settings/atelierclock/settings.json`, et tolèrent les anciennes valeurs.

### Cadrans

- **Format `.clock` v2** : une archive ZIP DEFLATE avec manifeste JSON, textures PNG originales et aperçu produit par le moteur Lua. Le schéma est dans `docs/clock.schema.json` et `docs/CLOCK_FORMAT.md`. Le format v1 reste lisible.
- **Dix cadrans originaux** : Totem, Duplex, Index, Halo, Journal, Lisière, Mosaïque, Octant, Typo, Signal. Chacun a une disposition portrait **et** une disposition paysage.
- **Styles** Plein, Fin et Contour. **Apparences** Papier, Encre et Auto.
- **Complications hors ligne** : Vide, Date, Batterie, Journée, Semaine, Autre fuseau (transitions IANA 1970–2100 embarquées) et Lecture. Elles existent en trois familles : ligne, anneau et rectangle.
- **Collection** « Mes cadrans » : jusqu'à 24 variantes indépendantes, à dupliquer, renommer ou retirer.
- **Import et export** de `.clock` validés, sans écraser un fichier existant.
- **Profils de réglages** en JSON, plus l'import des anciens fichiers Lua (tables littérales seulement, aucun code exécuté).

### Rendu

- Moteur v2 à tuiles conservées : fond, décor et date ne sont pas recalculés chaque minute, et les heures et les minutes sont séparées.
- Comparaison BB8 des tuiles (`render/delta.lua`), avec au plus quatre fenêtres de rafraîchissement, des lignes identiques sautées par `memcmp` et des replis bornés.
- Rafraîchissements de veille en mode `ui`, sans consommer le compteur de pages du lecteur. Nettoyages complets configurables.
- Interface adaptée au DPI réel, réorganisée en paysage et sur les petits écrans.
- Fonds par image ou en diaporama PNG, réglages par image (`image.png.json`), inversion en mode sombre.

### Énergie et RTC

- Une seule tâche RTC, avec une référence de callback stable. Les mutations sont différées hors de `wakeupAction`, la file des autres alarmes est respectée, et l'alarme physique est effacée si elle nous appartient.
- Profils de fréquence : 1 min, 5 min, 15 min ou statique. Pause nocturne, et seuil de batterie qui arrête les réveils.
- Garde contre les alarmes trop proches pendant la préparation de la suspension (marge minimale de 4 s).
- Optimisations Kobo Aura 2 :
  - réveil prioritaire (`fast_rtc`) ;
  - réutilisation conditionnelle de la préparation de suspension (`_doSuspend`) ;
  - relances bornées après un retour court ;
  - veille native jusqu'à l'alarme minute quand le refus FP9928 est confirmé (bêta 9).
- Mesures du sommeil (horloges BOOTTIME/MONOTONIC), lecture bornée du journal noyau, rapports `diagnostic.json` et `last-session.json`.

### Interface 0.2.5

- Atelier plein écran à quatre onglets : Cadrans, Modifier, Veille, Diagnostic.
- Navigateur de cadrans à flèches et balayage, catalogue « + Ajouter ».
- Éditeur par emplacements avec sélecteur de complications rendues en direct.
- Brouillon avec Annuler et Appliquer.
- Diagnostic paginé.

### Validation

- 156 tests sur ordinateur, avec LuaJIT, les vrais modules KOReader épinglés et libarchive.
- Rejeux des sessions utilisateur, simulations PMIC et RTC.
- Intégration native KOReader sur x86_64 et ARMv7 (QEMU).
- Aucune mesure électrique n'est revendiquée.

---

## Partie B — de 0.2.5-beta.9 à 0.3.0 (ce travail)

### 1. Moteur Fluid Ink 6.5 intégré

**Nouveaux fichiers**

- `engine/fluidink/` : copie **non modifiée** des fichiers `native.lua`, `platform.lua` et `startup.lua`, des binaires `libinkmotion-arm.so` et `libinkmotion-kindlepw2.so` (ABI 6500), et de `noise64.bin`, `COPYING` et `THIRD_PARTY_NOTICES.md`.
- `third_party/fluid-ink/` : les sources C correspondantes, le script de compilation et les documents de protocole. La copie personnelle `factory-reference.bin` n'est **pas** redistribuée (voir `.gitignore`).
- `engine/profile.lua` choisit le profil d'affichage :

| Cas | Profil |
|---|---|
| `Kobo_star` avec chemin personnalisé vérifié | **Fluid Ink v6** (conduite 12), **Impulsions 2**, **Débit** (file 1, Bayer 8×8, sans gamma), A2, 30 ips |
| Autres modèles compatibles | **v6 sans impulsions** (conduite 2 constructeur, ou 12 en personnalisé), A2 en mouvement et DU au repos |
| Impulsions refusées (`phase_errno`) | Bascule vers v6 sans impulsions, sans quitter le moteur |
| Réglage « Classique », ou modèle hors liste | Classique |

- `engine/display.lua` est le seul propriétaire de l'écran de l'atelier. Il reproduit le cycle de vie de `demo.lua` de Fluid Ink :
  - vérification RAM dans un processus enfant (`startup.lua`), dont le résultat est gardé en cache pour la session ;
  - démarrage du worker, puis `setPhase(2, 12)` sur l'Aura 2 v1 ;
  - publication des images avec l'indicateur de repos (`im_set_still`) ;
  - surveillance des erreurs EPDC, de l'arrêt du worker et du chien de garde : attente de la neutralisation, libération, puis repli classique ;
  - libération asynchrone (stop → reap → `free`, qui restaure la LUT et la capture) et version synchrone bornée pour la veille et la fermeture d'urgence ;
  - reprise après une saisie de texte ou un réveil.
- Le moteur reste inactif en paysage, en mode nuit, sans framebuffer mxcfb, ou si la vérification échoue. La raison s'affiche dans le Diagnostic.

**Nouveaux réglages** : `display_engine` (auto, fluid, classic), `display_fps` (30, 45, 60), `display_rest` et `motion` (full, reduced). Ils sont validés dans `core/settings.lua`.

**Diagnostic**

- La section *Affichage* montre le moteur actif, le profil, les cibles et scans par seconde en direct, et les réglages. Elle propose aussi « Nettoyer l'écran » et « Réessayer le moteur fluide ».
- `diagnostic.json` contient désormais `display` et `rtc_capability`.

### 2. Interface redessinée pour 30 Hz

Le rendu est entièrement nouveau (`ui/studio.lua`, `ui/views.lua`, `ui/faces.lua`, `ui/studio_actions.lua`) :

- **Composition par couches** dans un tampon 8 bits : en-tête, contenu défilant, carrousel, barre de brouillon, notification, barre d'onglets, feuille.
  - Les textes et les aperçus de cadrans sont rendus une fois et gardés en cache.
  - Chaque image n'est qu'un assemblage de blits, plus quelques formes.
  - Les éléments animés (interrupteurs, compteurs, segments, curseurs) se redessinent sur place.
- **Boucle d'animation unique** à la cadence choisie, avec saut des échéances manquées et jamais de file d'images anciennes. Elle s'arrête au repos, publie une dernière image « immobile », puis une surveillance lente prend le relais.
- **En mode classique ou en animations réduites**, tout se termine immédiatement. Pendant un glissement du doigt, au plus un rafraîchissement `fast` toutes les 0,2 s.
- **`ui/motion.lua`** : interpolations, ressorts amortis, défileur inertiel (vitesse filtrée et décroissance exponentielle, à la manière de `engine.lua`) avec bord élastique continu et accrochage, et gestion des échéances.
- **`ui/kit.lua`** : système visuel complet.
  - Couleurs : papier, encre, et trois gris clairs (lavis, ombre, filet).
  - Tailles de texte : 6.
  - Composants : cartes à ombre douce, boutons en pilule, bouton icône, interrupteur, contrôle segmenté, ligne de réglage, titres de section, jauge, points de pagination.
  - Majuscules accentuées correctes.
- **`render/draw.lua`** : rectangles arrondis et contours par lignes de balayage, traits à bouts ronds, arcs.
- **`ui/icons.lua`** : 38 icônes redessinées sur une grille de 24, avec un trait arrondi.

**Écran par écran**

- **Cadrans**
  - Carrousel : glisser, lancer (au moins une carte, au plus trois), accrocher. Les voisins dépassent et s'estompent, avec des points de pagination.
  - Bascule *Mes cadrans / Catalogue* à pastille glissante.
  - Actions ⋯, Modifier, Utiliser et Afficher. La feuille ⋯ propose Dupliquer, Renommer, Afficher et Retirer.
  - Un appui long sur la carte ouvre les actions.
- **Modifier**
  - Segments *Style / Modules / Options* avec transition latérale. Un balayage horizontal change de mode.
  - Les emplacements portent une pastille « + ».
  - La **feuille des modules** montre les complications rendues en direct. Quand on choisit, un cadre vole jusqu'à l'emplacement puis pulse.
  - Style : pastilles de spécimen « 12 », et Papier / Encre / Auto avec icônes.
  - Options : liste groupée (nom, export, orientation, format, langue, date, taille de l'interface).
- **Veille**
  - Carte principale avec l'interrupteur de l'écran de veille.
  - Fréquence en contrôle segmenté, avec la précision sous le contrôle.
  - Carte *Réveil* : capacité RTC du modèle, réveil prioritaire Aura 2, « Optimiser pour Aura 2 ».
  - Réglages avancés dans la même liste défilante, sans sous-page.
- **Diagnostic**
  - Jauge de batterie et compteurs qui montent jusqu'à leur valeur.
  - Prochaine actualisation et section Affichage.
  - Outils : détails techniques dépliés dans la liste, export et profil.
- **Éditeur libre v1** : aperçu déplaçable, choix de l'élément dans une feuille, six tuiles de sections, réglages en liste.

**Navigation**

- Barre d'onglets à pastille glissante, transitions latérales entre les onglets, balayage horizontal pour changer d'onglet.
- Bouton Retour dans l'en-tête des sous-vues, touche Retour qui ferme d'abord la feuille ouverte.
- Retour visuel d'appui : légère teinte sur la zone touchée. Le doigt arrête net un défilement en cours.

**Autres changements**

- Confirmations et choix dans des feuilles maison : KOReader ne reprend plus l'écran pour un simple « Retirer ? ».
- Notifications brèves à la place de la ligne d'état.
- Barre *Brouillon* qui n'apparaît que lorsqu'il y a des modifications.
- « Afficher » zoome l'aperçu jusqu'au plein écran avec le redimensionneur MuPDF de KOReader. S'il n'est pas disponible, l'aperçu se révèle par recadrage, jamais par la boucle Lua `BlitBuffer:scale`.
- Changement de rotation : libération du moteur, puis nouvelle mise en page.
- Mise en veille : arrêt synchrone, avant que l'écran de veille ne dessine.

### 3. RTC sur toutes les liseuses compatibles

- `power/capabilities.lua` détecte, d'après les classes d'appareils de KOReader, si le réveil passe par le RTC Kobo, par powerd sur Kindle, ou s'il est indisponible.
- `power/kindle.lua` est nouveau. Sur Kindle, powerd suspend la liseuse et KOReader programme `setRtcWakeup` à `readyToSuspend`. Un garde placé juste après chaque échéance appelle `recoverDue()` dans deux cas :
  - la liseuse est restée éveillée en mode écran de veille ;
  - `readyToSuspend` a supprimé une alarme déjà passée.

  Il n'exécute jamais le callback d'une autre tâche.
- **Correctif** : sans `WakeupMgr`, la session était marquée active sans alarme. Elle est maintenant inactive, et le message « RTC INDISPONIBLE / HEURE FIGÉE » s'affiche.
- **Correctif** : sur un RTC i.MX5 (`dodgy_rtc`), le premier maillon de la chaîne d'alarmes d'une longue pause nocturne restait programmé après l'arrêt. Il est maintenant effacé s'il nous appartient.
- Diagnostic et rapport : capacité RTC, et rattrapages Kindle.

### 4. Tests et outils

- **`tests/test_rtc_devices.py`** (nouveau, 4 tests) : les 7 Kobo, la chaîne `dodgy_rtc`, et les 3 Kindle dans quatre scénarios (réveil programmé avec avance de 10 s, éveil prolongé, alarme supprimée, arrêt), plus un Kindle sans écran de veille KOReader. Ces tests utilisent le vrai `wakeupmgr.lua`, le vrai `kindle/mockrtc.lua` et les fonctions de réveil de `kindle/powerd.lua`.
- **`tests/test_fluid_ui.py`** (nouveau, 8 tests) :
  - profils par modèle et modèles de mouvement ;
  - démarrage Impulsions 2 / Débit sans aucun rafraîchissement KOReader pendant le moteur ;
  - carrousel et feuille des modules ;
  - saisie de texte avec libération puis reprise ;
  - veille et réveil, impulsions refusées, chien de garde ;
  - animations réduites et interrupteur animé ;
  - images en mouvement.
- Tests existants adaptés :
  - le test de contraste admet les trois gris du système visuel, mais interdit toujours les aplats de gris moyen ;
  - la version est lue depuis `core/version.lua`.
- Le harnais gagne `darkenRect`, `lightenRect` et un `ui/renderimage` de test. `fetch_test_dependencies.py` récupère `kindle/mockrtc.lua` et `kindle/powerd.lua`.
- **`tools/build_screenshots.py`** produit les captures et les GIF à partir d'images réellement publiées à 30 Hz, avec une horloge déterministe, plus une simulation du tramage Bayer 8×8.
- `tools/build_release.py` : version 0.3.0, au moins 168 tests, et bloc `display` / `rtc_models` dans `RELEASE.json`.
- Le validateur KOReader (skill `koreader-plugin`) : 0 erreur. Le seul avertissement concerne le champ `name` de `_meta.lua`, conservé.

### 5. Dépôt et documentation

- Le dépôt adopte la structure Atelier : `atelierclock.koplugin/`, `tools/`, `tests/`, `validation/`, `third_party/` et `docs/media/`. Les anciens fichiers de *Time & Day* restent dans l'historique git.
- Nouveaux `README.md`, `CHANGELOG.md` et `docs/FONCTIONS.md`. Mise à jour du README du plugin et de `DEVELOPPEMENT.md`.
- Licences : le code Atelier reste MIT et les cadrans CC0. Le moteur porte des en-têtes GPL-3.0-or-later, mais son paquet est livré avec le texte de l'AGPL-3.0 : ce point est à confirmer par l'auteur du moteur. L'ensemble distribué suit le fichier `LICENSE` (AGPL-3.0, comme le dépôt auparavant).

### Limites connues

- Aucune mesure sur liseuse n'a été possible ici. La cadence optique, le contraste, les traces, le coût CPU du rendu de l'atelier à 30 Hz et le réveil Kindle restent à vérifier sur appareil.
- Les polices des captures sont des substituts (DejaVu).

---

## Partie C — Que sont devenues les fonctions de Time & Day ?

| Time & Day (GitHub) | Atelier Clock 0.3.0 |
|---|---|
| Style **Classic** (heure, date, batterie) | Cadrans Mosaïque, Duplex, Signal, et tout cadran avec les complications Date et Batterie |
| Style **Fullscreen** (chiffres empilés) | Cadran **Totem** |
| Style **Outlined** (contour sur fond PNG) | Style **Contour**, réglage *Contour des chiffres* de l'éditeur v1, fonds PNG |
| Style **Analog** (graduations, aiguilles, chiffres) | Cadrans **Halo** et **Octant**. Éditeur v1 : chiffres arabes, romains ou aucun, épaisseur des aiguilles |
| **Word Clock** (heure en toutes lettres) | Cadran **Typo**, en français et en anglais |
| Customizer visuel par appui long | Appui long sur l'horloge → **atelier**, avec aperçu en direct et brouillon |
| Auto-layout anti-chevauchement, espacement | Emplacements conçus des cadrans v2. Éditeur v1 : *Disposition automatique* et *Espacement* |
| Séparateurs et cadres décoratifs | Éditeur v1 → Habillage : *Séparateur* (ligne, points, losange, ornement) et *Cadre* (simple, double, coins) |
| Polices de l'heure et de la date | Éditeur v1 → Typographie : police par élément (nom KOReader ou chemin TTF) |
| Taille du texte | Taille par élément, échelle du cadran, taille de l'interface |
| Format 12/24 h, orientation, mode nuit | Options : format, orientation (suivre ou quatre sens). Apparence Papier, Encre ou Auto (mode nuit) |
| Superposition PNG, image ou dossier, intervalle | Éditeur v1 → Images : image unique ou diaporama, portrait et paysage, durée, inversion en mode sombre |
| Rafraîchissement complet au changement d'image | *Nettoyer l'écran au changement* |
| Réglages par image (`*.lua`) | Réglages par image `image.png.json`, plus import des anciens profils Lua (tables littérales) |
| Éclairage de l'horloge (-1 = désactivé) | *Éclairage manuel* (-1 = conserver) |
| Intervalle de rafraîchissement complet | *Nettoyage complet* (minutes, 0 = désactivé) |
| Durée d'éveil du CPU après rafraîchissement | *Marge après fin d'affichage* (0,1 à 5 s) |
| Réveil RTC à la minute, suspension rapide | Tâche RTC unique et profils 1, 5 ou 15 min ou statique. Optimisations Aura 2, Kindle via powerd |
| Lancement par menu et action Dispatcher | **Outils → Plus d'outils → Atelier Clock**, actions *atelier* et *afficher* |
| Option d'écran de veille « Show clock on sleep screen » | Option **Horloge Atelier** dans le menu de veille, et interrupteur dans **Veille** |
