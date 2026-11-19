# Portage Fluid Ink v6

Le firmware Kobo 4.38.23684 étudié contient deux entrées `uImage-E60QL0` et `uImage-E70Q00` dont les octets ont le même SHA-256 `1ad0d01274030beba80ca446fc0c5057818417a62fc21832b90651a2deb1854e`. Ce point de départ facilite l’étude du pilote commun. Les tables des dalles candidates, leurs limites thermiques et leur comportement optique restent à vérifier. Les variantes Mk7 et Kindle Carta passent par d’autres interfaces.

Pour les modèles NTX constructeurs Aura One, Aura H2O Edition 2 v1 et Glo HD, le bouton **Exporter LUT** tente une collecte en lecture seule. La collecte se limite aux deux chemins firmware documentés et à l’emplacement fixe NTX avant les partitions. Elle vérifie le type et la taille du fichier, la signature et la limite de l’emplacement fixe, et la cohérence du numéro de mode avec sysfs. Cette variante n’ouvre pas la mémoire noyau. Le rapport peut servir à documenter un port ultérieur. L’export ne valide pas qu’une copie du fichier correspond exactement à l’allocation résidente.

Les profils à impulsions restent réservés à la cible validée, Kobo Aura Edition 2 v1 avec la référence exacte. Le nom de la dalle, le SoC et l’ABI constructeur ne donnent pas les impulsions de transition ni la neutralisation du matériel.

---

# Portage InkMotion 5.1

Les modèles ajoutés utilisent les rafraîchissements constructeur. Le tramage global, la composition, les listes de régions modifiées, la boîte aux lettres et les mesures sont réutilisables. Le moteur à impulsions de l’Aura 2 v1 reste attaché à cette cible et à sa référence résidente. Les noms commerciaux seuls ne suffisent pas à distinguer les révisions.

| Modèles reconnus par KOReader | Soumission | Attente | Bibliothèque |
|---|---:|---:|---|
| `Kobo_star`, `Kobo_daylight`, `Kobo_snow`, `Kobo_alyssum` | NTX 68 octets, `0x4044462e` | 4 octets, `0x4004462f` | ARMv7 hard-float Kobo |
| `Kobo_star_r2`, `Kobo_snow_r2`, `Kobo_nova` | V2 72 octets, `0x4048462e` | 8 octets, `0xc008462f` | ARMv7 hard-float Kobo |
| `KindlePaperWhite2`, `KindlePaperWhite3`, `KindleVoyage` | Amazon 72 octets, `0x4048462e` | 8 octets, `0xc008462f` | ARMv7 softfp Kindle PW2 |

Les deux structures de 72 octets ont des champs différents malgré leur même code ioctl. Les Kindle placent deux modes d’histogramme avant la température automatique 4097. Kobo utilise la température ambiante 4096, puis les flags et les champs de tramage matériel laissés à zéro. Les pixels du worker sont déjà binaires. L’attente large réserve deux mots et initialise le champ collision à zéro.

Les modèles ajoutés utilisent un seul marqueur en vol et attendent la fin de la demande avant de réutiliser le framebuffer. La file du pilote reste celle choisie par KOReader. Sur les Kobo compatibles, l’appel de réveil EPDC est repris lorsque KOReader l’expose. Le moteur choisit DU pour sa première image binaire.

## Validation du portage

Les déclarations FFI de KOReader ont été confrontées aux profils sous LuaJIT ARM. Les tests natifs simulent la soumission et l’attente, vérifient les champs, le second mot de l’attente, les zones tournées, les transitions DU/A2/GC16, la limite d’un marqueur et le refus de l’accès aux impulsions hors Aura 2 v1. Les deux bibliothèques ont été chargées sous QEMU avec LuaJIT ARM et les conventions d’appel correspondantes, sur glibc 2.15 armhf et armel. Le démarrage inclus vérifie le binaire et la FFI en mémoire privée, avec fd=-1.

Aucun des modèles ajoutés n’a reçu d’ioctl sur un appareil physique. Leur qualité visuelle, leur cadence, leur réveil et leur comportement selon la température restent à mesurer. Sur une mise à jour de firmware ou de KOReader, une autre structure ou une autre convention d’appel peut rendre le profil incompatible.

## Ce qu’il faudrait pour porter l’affichage à impulsions

L’Aura One et l’Aura H2O Edition 2 v1 sont des candidats d’étude côté NTX. Les révisions Mk7 et les Kindle Carta demandent aussi un portage spécifique du chemin d’impulsions du pilote. Il faut identifier la table propre à la dalle, son chargement en RAM, les limites thermiques, les transitions source/destination et les garanties de neutralisation et de restauration. Ensuite, il faut vérifier physiquement la réflectance, la rémanence et la cadence. La taille de l’appel ioctl ou l’appartenance à la famille i.MX6 ne suffit pas à établir ces propriétés.

## Sources

Les liseuses de lecture consacrent surtout leur budget d’affichage à une page nette qui reste longtemps fixe. La bistabilité permet à la dalle de garder cette page sans alimentation d’entretien. En animation, le contrôleur et le processeur travaillent de façon répétée et les transitions courtes rendent les traces plus visibles. Kobo propose un réglage de rafraîchissement périodique pour réduire ces traces. BOOX fournit pour sa part des modes rapides en plus du mode dédié à la lecture. Ces choix documentés expliquent l’intérêt de profils différents selon l’usage.

- [E Ink, bistabilité et consommation](https://www.eink.com/tech/detail/Benefits)
- [Kobo, rémanence et rafraîchissement](https://help.kobo.com/hc/en-us/articles/44388182029079-How-to-reduce-ghosting-on-your-Kobo-eReader-screen)
- [BOOX, modes Super Refresh](https://shop.boox.com/blogs/news/boox-super-refresh-bsr-technology)
- [KOReader, modèles Kobo](https://github.com/koreader/koreader/blob/eb8fe6a3e4b0a8aefce4f8875083ae922963c4e2/frontend/device/kobo/device.lua)
- [KOReader, modèles Kindle](https://github.com/koreader/koreader/blob/eb8fe6a3e4b0a8aefce4f8875083ae922963c4e2/frontend/device/kindle/device.lua)
- [KOReader, transport mxcfb](https://github.com/koreader/koreader-base/blob/2ec21d4121d5172b5e719e5aa13f8d7221f7c7d6/ffi/framebuffer_mxcfb.lua)
- [KOReader, déclaration Kobo](https://github.com/koreader/koreader-base/blob/2ec21d4121d5172b5e719e5aa13f8d7221f7c7d6/ffi/mxcfb_kobo_h.lua)
- [KOReader, déclaration Kindle](https://github.com/koreader/koreader-base/blob/2ec21d4121d5172b5e719e5aa13f8d7221f7c7d6/ffi/mxcfb_kindle_h.lua)
- [KOReader, cibles de compilation](https://github.com/koreader/koxtoolchain#notes)
