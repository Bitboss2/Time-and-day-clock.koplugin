# Bêta 8 — décharge FP9928 en veille légère

31 octobre 2026. Cette version conserve les dix cadrans, leurs réglages, les nettoyages et la mise à jour chaque minute. **La consommation totale divisée par sept n’est pas encore validée sur matériel.**

## Session reçue

Les quatre fichiers fournis correspondent à la bêta 7. La session enregistrée va du 31 octobre à **17:18:21 à 20:24:11, heure de Paris**, soit **3 h 05 min 50 s**. La batterie passe de 89 à 88 %. Les 186 mises à jour sont distribuées sans retard déclaré, sans rattrapage et sans erreur de rendu.

Le journal KOReader compte 372 refus de `mem` dans cette plage, généralement deux par minute. Le diagnostic compte 559 appels et 373 retours courts ; son dernier retour inclut l’interruption finale. Les horloges noyau donnent 80,708 % du temps suspendu, soit environ **35 min 51 s hors suspension**. Le rendu final prend 6 ms ; le délai restant se situe surtout dans la séquence de veille et ses reprises.

Trois différences de tampon noyau vérifiées contiennent explicitement :

```
fp9928_suspend():waiting for VEE stable ,please retry suspend later !!!
PM: Device imx_epdc_fb failed to suspend: error -1
```

La cause des premiers refus est donc identifiée : **le pilote FP9928 attend la décharge de VEE**. Le dernier instantané manuel montre aussi des refus pendant l’utilisation de l’interface, lorsque la sortie PMIC est encore activée. Ces événements après la fin de la session ne sont pas mélangés à la mesure de l’horloge.

Les réglages fournis activent déjà `fast_rtc=true`, `reuse_suspend=true`, intervalle 60 s, marge 0,5 s, cadran Duplex et nettoyage 690 s. Ils sont conservés. Le relevé de jauge correspond à environ 0,323 point/heure ; la cible issue de la bêta 3 est 0,178 point/heure. Un seul point de jauge ne suffit pas à établir un rapport énergétique précis. Voir `SESSION_BETA7_ANALYSIS.json`, reproductible avec `tools/analyze_session.py`.

## Différence entre veille légère et profonde

Source primaire : [noyau Kobo publié, imx6sl-auraonetwo](https://github.com/kobolabs/Kobo-Reader/tree/master/hw/imx6sl-auraonetwo), fonction `fp9928_suspend` dans `drivers/video/mxc/lk_fp9928.c`. Empreinte SHA256 : `e74b2fa53e6070cb1008224be8283870e67d472831beabc5329c19e3f63be7a5`.

Le pilote refuse tant que la sortie PMIC reste activée. Pour la veille profonde (`gSleep_Mode_Suspend=1`), il contrôle aussi une échéance de décharge. La branche publiée 1024×758 prévoit **6 500 ms**, plus l’arrêt différé de 50 ticks (500 ms avec HZ=100). Pour la veille légère, le même pilote conserve une autre configuration des sous-systèmes et ne demande pas la dernière transition électrique soumise à cette échéance. Il garde le contrôle de sortie PMIC activée. La valeur exacte du firmware n’est pas imposée par le plugin : la tentative finale profonde reste validée par le noyau.

KOReader possède déjà [une fonction native `Kobo:standby`](https://github.com/koreader/koreader/blob/master/frontend/device/kobo/device.lua), avec écran conservé et possibilité de réveil anticipé. La bêta 8 l’utilise sans réécrire son accès au noyau. Aucun module noyau, GPIO ou délai de décharge n’est modifié ; le plugin n’écrit pas directement `state-extended`.

## Nouveau chemin

1. Le réveil RTC affiche normalement la nouvelle minute et attend la fin de l’image.
2. Une première tentative native qui refuse pour VEE remet elle-même `state-extended` à zéro. Le plugin exige une trace FP9928 fraîche et vérifiée avant d’utiliser le nouveau chemin.
3. Il ajoute une alarme technique courte dans la file RTC partagée, en vérifie le résultat matériel et appelle **la veille légère native**. Le processeur peut être suspendu pendant l’attente au lieu de parcourir les gardes de 1 puis 2 secondes et une préparation de 2 secondes à chaque essai.
4. À la fin de cette attente, il retire seulement son alarme technique, restaure l’échéance partagée et repasse par la boucle d’événements. Le bouton ou la couverture peuvent annuler le même callback natif.
5. KOReader prépare à nouveau la veille profonde pendant ses deux secondes habituelles, synchronise et demande `mem`. Les protections électriques du pilote restent intactes.

Le repère de préparation est 7,5 s après la fin d’affichage, avec arrondi conservateur lié à la RTC. Ce repère organise l’attente ; il ne raccourcit aucune contrainte noyau. La veille légère ajoute **un réveil technique intermédiaire par minute** ; ce choix vise à remplacer du temps éveillé par une suspension. Le gain électrique réel dépend du coût de cet état et de ses transitions sur l’appareil.

Après une séquence veille légère → veille profonde validée, la préparation encore active peut à nouveau être réutilisée lors de la minute suivante. La bêta 7 la désactivait pour toute la session après le premier refus. Le nouveau chemin conserve un premier refus possible par minute ; il ne prétend pas supprimer toute transition matérielle.

## Conditions et replis

Le chemin exige `Kobo_star`, noyau Linux 3.0.35, mode natif `standby` disponible, confirmation FP9928 par des messages nouveaux vérifiés, session propre active, drapeau zéro, Wi-Fi éteint, absence de charge et horloges BOOTTIME/MONOTONIC utilisables. Aucune tâche étrangère imminente ne doit avoir besoin de la RTC pendant l’opération.

Il n’y a qu’une tentative de veille légère par mise à jour. Refus, retour beaucoup trop tôt, exception ou refus profond suivant : le chemin spécial se désactive pour cette session. L’ancienne récupération native bornée reste disponible. Les échecs ne sont pas effacés du budget KOReader et le premier sommeil reste natif. Une demande étrangère ou le réveil utilisateur révoque l’opération.

L’alarme technique est vérifiée avant la suspension et retirée après, y compris en cas d’erreur. Une restauration RTC échouée est réparée ou arrête visiblement l’actualisation ; elle ne laisse pas silencieusement l’horloge sans échéance. Si la fonction native échoue après avoir sélectionné son gouverneur rapide, sa restauration normale est également programmée. Les profils CPU ne sont pas modifiés de façon permanente.

L’armement normal observe désormais le résultat de l’écriture effectuée par WakeupMgr au lieu de réécrire la même alarme pour vérifier ce résultat. Le refus du pilote reste détecté. La veille légère implique cependant ses propres écritures RTC d’ajout/retrait ; il ne s’agit pas d’une réduction globale garantie de tous les accès RTC.

## Tests et résultats

**148 tests automatisés passent**, dont 21 nouveaux contrôles du chemin FP9928, des alarmes, des annulations et des mesures. Les fonctions de veille légère/profonde exécutées dans ces tests sont celles de KOReader ; les horloges, RTC, sysfs et délais périphériques sont remplacés par des témoins.

Un scénario de 186 minutes garde une attente écran de 0,5935 s, une marge de 0,5 s, une décharge de 6,5 s après 0,5 s d’arrêt et des coûts de rendu/synchronisation explicitement fixés. Il donne :

| Scénario contrôlé | Sans pont de veille | Avec pont de veille |
|---|---:|---:|
| Temps éveillé calculé par les horloges simulées | 2 035,807 s | 777,957 s |
| Part suspendue | 81,759 % | 93,030 % |
| Tentatives profondes | 556 | 371 |
| Retours courts | 370 | 185 |
| Veilles légères | 0 | 185 |

Le temps éveillé est réduit d’environ 62 % **dans ce scénario**, pas la consommation de batterie mesurée. Le coût actif d’une transition réussie est notamment simplifié à zéro dans ce modèle ; les courants de veille légère/profonde et les transitions réelles ne sont pas modélisés. Toutes les hypothèses figurent dans `PMIC_SIMULATION.json`. Le scénario vérifie une seule alarme de cadran, aucune alarme technique orpheline et des échantillons bornés.

Le test C du noyau ajoute sept vérifications FP9928 : avant/après l’échéance, absence de demande VIN/EP3V3 finale en veille légère et maintien du refus si la sortie est activée. Ces fonctions originales sont compilées avec des interactions matérielles remplacées. **Ce n’est pas un noyau Kobo amorcé ni un essai électrique.** Résultats dans `VENDOR_SUSPEND_TEST.json`.

KOReader officiel v2026.07.1 Linux SDL est aussi exécuté en x86_64 et ARMv7 via QEMU Cortex-A9, avec les dix cadrans et les vues à 212 DPI. Les preuves sont sous `validation/beta8` dans le ZIP. QEMU user mode utilise le noyau hôte et ne reproduit pas les rails, le contrôleur e-ink ou les courants. L’appareil utilisateur annonce KOReader v2026.07.2 ; cette différence reste une limite.

## Diagnostic du prochain essai

Tes réglages activent déjà le mécanisme. Après remplacement du plugin et une sortie de veille normale, `settings/atelierclock/last-session.json` contient `power.pmic_settle` : confirmation, nombre de veilles légères, échecs et douze derniers échantillons. `power.timing.standby_verified_sleep_s` distingue le sommeil pendant la décharge ; `verified_sleep_percent` additionne ce sommeil et celui des appels profonds sans double comptage. `sleep_s` garde sa signification historique de durée bloquée dans `mem`.

Le fichier automatique nécessite une fin normale de session. Les premières traces et l’export manuel `diagnostic.json` restent disponibles. Aucune écriture de rapport à chaque minute n’est ajoutée. La consommation doit être comparée physiquement dans les mêmes conditions avant de valider ×7 ; le logiciel n’annonce pas ce résultat à partir du ratio de sommeil.
