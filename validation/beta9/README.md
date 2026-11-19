# Preuves natives bêta 9

KOReader officiel v2026.07.1 Linux SDL, x86_64 et ARMv7 via QEMU user mode Cortex-A9, 758×1024 à 212 DPI. Chaque run vérifie la version du plugin, les dix paquets, l’éditeur, l’export, les rendus à la minute et le paysage. Le code Lua de production est identique à celui chargé par ces runs.

Le runtime reçoit seulement une protection du message de log SDL_GetBasePath contre NULL. QEMU user mode n’amorce pas le noyau Kobo et ne reproduit pas sa dalle, sa PMIC ou sa consommation. Les durées CPU des captures dépendent de l’hôte. La batterie SDL ne représente pas la batterie de l’appareil. L’utilisateur emploie v2026.07.2 : la différence est conservée comme limite.

Le cycle de puissance est couvert séparément par les fonctions natives KOReader avec témoins d’horloge/RTC/périphériques. Le rejeu des modules exacts de bêta 8 reproduit son unique pont puis son repli dans le modèle corrigé. Les preuves sont dans les JSON du dossier docs du plugin et les tests sont inclus. Aucune valeur de ces simulations ne certifie le facteur énergétique ×7.
