# Composants tiers

Le code InkMotion est sous GPL-3.0-or-later ; voir `COPYING`.

`inkmotion.koplugin/noise64.bin` contient les 4096 octets de la texture `rtl/noise.mem` de Caster, version `2f714ab7c217e6441c46cfd647764d9a74967aec`. Le README de Caster indique que cette texture provient de Christoph Peters, Moments in Graphics, et est dans le domaine public :

- https://github.com/Modos-Labs/Caster
- https://momentsingraphics.de/BlueNoise.html

Aucun circuit RTL, ROM de jeu, firmware InkBoy ou pilote de contrôleur tiers n’est embarqué. La référence personnelle de waveform ajoutée en v1 est décrite ci-dessous. Les outils Glider servent uniquement à vérifier hors appareil le format de la fixture de laboratoire ; ils ne font pas partie du plugin distribué.

Le binaire ARM 5.0.0 est compilé depuis `native/inkmotion.c`, `native/collector.c` et `native/phase.c`, avec la chaîne KOReader **koxtoolchain kobo 2026.08**, GCC 14.4.0, et utilise les bibliothèques système glibc de la Kobo. Les routines libgcc incorporées sont couvertes par GPLv3 avec l’exception d’exécution GCC ; les textes figurent dans `native/toolchain-licenses/`. La chaîne de compilation n’est pas distribuée.

Les textes de licence de l’ancienne chaîne Zig restent dans ce dossier pour documenter les versions antérieures ; le binaire 5.0.0 ne provient pas de cette chaîne.

Le format d’en-tête du slot NTX est documenté par [Andreas Kemnade, kobo-firmware-extractor](https://github.com/akemnade/kobo-firmware-extractor), projet MIT. Le collecteur InkMotion applique des validations supplémentaires (bornes MBR, taille, version et refus d’écrasement) et n’installe aucun contenu extrait.

## Référence personnelle de la v1

`inkmotion.koplugin/factory-reference.bin` est la copie de waveform fournie par l’utilisateur pour cette Kobo. Elle sert à comparer les octets de la table résidente avant l’essai et à les restaurer. La licence GPL des sources InkMotion n’est pas une attribution de licence au contenu de ce fichier fournisseur. Cette archive est préparée pour cet appareil, pas comme firmware générique à redistribuer.

Les principes de compteurs et de réorientation s’inspirent des descriptions Glider/Caster et InkBoy. Aucun RTL ou pilote SSD1681 de ces projets n’est incorporé ; l’implémentation EPDC et le superviseur sont dans les sources fournies.

Le noyau officiel Kobo #5031 a été analysé hors appareil avec vmlinux-to-elf (Marin Moulinier, GPL-3.0-or-later) et les outils binaires ARM de la chaîne Kobo. Aucun de ces outils ni l’image du noyau n’est distribué dans cette archive ; les faits de provenance figurent dans `KERNEL_5031_ANALYSIS.json`.
