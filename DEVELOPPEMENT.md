# Atelier Clock — développement

Le dossier `atelierclock.koplugin` est le seul à copier dans `KOReader/plugins`. Tout son code source est inclus. `tools` et `tests` servent au développement sur ordinateur Linux.

## Dépendances et tests

Python 3.12 utilisé pour cette livraison ; Pillow, Lupa (moteur `luajit21`), jsonschema et `libarchive.so.13` sur Linux x86_64. DejaVu Sans est utilisé pour les images de test ; aucun fichier de police n’est requis par le plugin lui-même.

```sh
python -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements-test.txt
python tools/fetch_test_dependencies.py
PYTHONPATH=tests python -m unittest discover -s tests -p 'test_*.py' -v
```

Les sources officielles téléchargées par les tests sont épinglées à leurs commits et ne sont pas nécessaires à l’installation. Elles gardent leurs licences propres. Le framebuffer et les événements de test sont des substituts, pas une exécution complète de KOReader.

## Reconstruire les cadrans

```sh
python tools/build_assets.py
PYTHONPATH=tests python -m unittest discover -s tests -p 'test_*.py' -v
```

La génération crée les dix paquets v2 et leurs textures géométriques originales. Les tables IANA hors ligne déjà fournies restent conservées. La suite de rendu remplace les aperçus des paquets par des aperçus dessinés via le vrai moteur de scène Lua, avec une police de substitution. Les sorties graphiques sont sous `tests/output`.

Pour mesurer le travail de rendu, puis produire le ZIP :

```sh
PYTHONPATH=tests python tools/measure_render.py
PYTHONPATH=tests python -m unittest discover -s tests -p 'test_*.py' -v > tests/test-results.txt 2>&1
python tools/build_release.py
```

`render/face_v2.lua` conserve les tuiles stables ; `ui/faces.lua` gère la collection et l’édition des emplacements. `tests/fixtures/legacy.clock` est un témoin v1 de la précédente version de notre propre plugin, pas un cadran préinstallé ni une ressource de l’ancien projet.

## Architecture

`core` : données, calendrier, import littéral. `packages` : validation ZIP/JSON et extraction. `render` : moteurs v1/v2, tuiles conservées et régions modifiées. `power` : tâche RTC unique et adaptateur Kobo optionnel. `integration` : menu et contenu du screensaver. `ui` : galerie et atelier natif. `main.lua` partage un seul service entre les instances lecteur et fichiers.

Le code fourni ne repose pas sur le code de l’ancien plugin. Le présent logiciel est sous MIT ; les manifestes/textures originaux sont sous CC0. Les dépendances de KOReader ne sont pas redistribuées ici. Consulter également les notices des aperçus.


La bêta 4 utilise aussi le vrai module `ui/time.lua` dans les tests et couvre le cycle natif complet de suspension. `tests/test_power_efficiency.py` substitue uniquement l’horloge, les accès noyau et le contrôleur pour vérifier les branches. Aucune mesure électrique ne vient du simulateur. Lire `docs/POWER_AURA2.md` pour le chemin conditionnel de réutilisation.

La bêta 5 ajoute `render/delta.lua`, qui compare les BB8 retenus avant libération de l’ancienne tuile et borne les demandes à quatre fenêtres. `tests/test_delta.py` vérifie les données natives FFI, les pas mémoire différents, l’effacement de gris, les limites, les replis et la couverture exacte des pixels sur les dix cadrans. Le framebuffer Pillow matérialise ses pixels en BB8 pour exécuter le même scan ; ce coût de transfert ne fait pas partie du code de production. Le facteur de réduction des fenêtres n’est pas une mesure énergétique.

La bêta 6 ajoute un garde rapproché borné après un retour court suivant la minute propre à l’horloge, tout en conservant le contrôle et la préparation natifs. `tests/test_power_recovery.py` utilise le même code officiel et couvre les échecs récurrents, la borne de deux essais, les demandes étrangères et le réveil utilisateur. Le temps dans `mem` et le sommeil BOOTTIME/MONOTONIC sont distincts dans le diagnostic. Le scan des tuiles saute les lignes identiques via `memcmp` et espace les comparaisons de faible bénéfice. La suite complète compte 116 tests. Aucune valeur du simulateur ne certifie un gain électrique.


La bêta 7 centralise la version dans `core/version.lua` pour l’interface et les rapports ; la construction vérifie sa cohérence avec `_meta.lua`. `tests/test_power_evidence.py` couvre la propriété explicite des callbacks, la lecture bornée du journal noyau et l’unique sauvegarde de sortie. La suite complète compte 127 tests.

`tools/native_koreader_integration.lua` est un patch utilisateur tardif destiné à un profil de test isolé du KOReader officiel SDL. Les preuves x86_64 et ARMv7/QEMU sont sous `validation/beta7` dans cette distribution. Elles ne simulent pas les périphériques Kobo. `tools/test_vendor_suspend.py` compile et exécute les fonctions de suspension originales du noyau publié avec des témoins périphériques C ; il exige les sources Kobo exactes vérifiées par SHA256 et un compilateur C sur l’hôte. Ce test n’amorce pas un noyau et ne mesure pas l’électricité.


La bêta 8 ajoute `power/settle.lua` et `power/alarm.lua`. Le pont FP9928 n’est activé qu’après preuve fraîche et utilise `device:standby()` ; les écritures de suspension restent celles de KOReader. L’adaptateur RTC observe le résultat de la programmation native sans doubler la même écriture. `tests/test_pmic_settle.py` ajoute 21 tests, dont un scénario de 186 minutes et les erreurs/collisions/annulations. La suite complète compte 148 tests. `tools/analyze_session.py` résume le diagnostic et le journal dans l’intervalle de session, sans redistribuer les fichiers utilisateur ou le numéro de série. `tools/test_vendor_suspend.py` ajoute sept vérifications du FP9928 avec témoins C. Les preuves natives récentes sont dans `validation/beta8` ; aucune simulation ne valide un gain électrique ×7.


La bêta 9 remplace le pont court de `power/settle.lua` par la veille native jusqu’à l’alarme minute existante. Il n’y a plus d’alarme auxiliaire ni de passage immédiat à `mem`. La fixture `tests/fixtures/beta8_power.json` contient les modules exacts du ZIP bêta 8 sous leur licence d’origine du projet et permet de reproduire son repli avec le modèle de temps corrigé. La suite compte 156 tests, dont un refus natif de 4,46 s détecté par son drapeau, les sessions successives et les interruptions dans les hooks. La simulation reste distincte de la consommation physique. Preuves courantes : `validation/beta9` et `docs/INVESTIGATION_BETA9.md` dans le plugin.


## Version 0.3.0 : interface 30 Hz et Fluid Ink

`engine/fluidink` contient les fichiers d'exécution de Fluid Ink 6.5.0, copiés sans modification : `native.lua`, `platform.lua`, `startup.lua`, les binaires ARM (ABI 6500) et `noise64.bin`. Les sources C correspondantes sont dans `third_party/fluid-ink`. `factory-reference.bin` est une copie personnelle de waveform : il n'est pas versionné (voir `.gitignore`) et se copie à la main depuis son propre paquet Fluid Ink pour activer « Impulsions 2 » sur l'Aura 2 v1.

| Fichier | Rôle |
|---|---|
| `engine/profile.lua` | Choisit le profil (Impulsions 2 / Débit, v6 sans impulsions, classique) |
| `engine/display.lua` | Possède l'écran : sonde, worker, publication, surveillance, libération, veille, reprise |
| `ui/motion.lua` | Interpolations, ressorts, défileur inertiel avec élastique et accrochage |
| `ui/kit.lua` | Système visuel et composants |
| `ui/icons.lua` | Icônes redessinées |
| `ui/studio.lua` | Composition par couches, boucle d'animation, gestes, feuilles, transitions |
| `ui/views.lua` | Lignes de réglages, Veille, Diagnostic, éditeur v1 |
| `ui/faces.lua` | Carrousel, catalogue, édition v2, feuille des modules |
| `power/capabilities.lua`, `power/kindle.lua` | RTC selon la liseuse, garde Kindle |

`tests/test_fluid_ui.py` remplace uniquement la bibliothèque native, avec une fausse `native_factory`, et fait tourner le vrai code avec une horloge déterministe. `tests/test_rtc_devices.py` utilise `wakeupmgr.lua`, `kindle/mockrtc.lua` et les fonctions de réveil de `kindle/powerd.lua`, épinglés au commit KOReader de `fetch_test_dependencies.py`. La suite compte 169 tests.

Pour reproduire la livraison, lancer ces quatre commandes dans l'ordre :

```sh
PYTHONPATH=tests python tools/build_screenshots.py
```

```sh
PYTHONPATH=tests python -m unittest discover -s tests -p 'test_*.py' -v > tests/test-results.txt 2>&1
```

```sh
python tools/build_release.py
```

```sh
python3 <skill koreader-plugin>/scripts/check_plugin.py atelierclock.koplugin --koreader /tmp/koreader-src
```

`build_screenshots.py` enregistre les images réellement publiées à 30 Hz par l'atelier (moteur simulé) et produit les captures du plugin (`atelierclock.koplugin/docs/atelier-*.png`), puis les GIF, le visuel d'en-tête et la simulation de tramage Bayer (`docs/media`). Les visuels et l’interface sont en anglais. Si `factory-reference.bin` est présent localement, `build_release.py` l'inclut dans le ZIP produit : ce ZIP est alors personnel et ne doit pas être publié.
