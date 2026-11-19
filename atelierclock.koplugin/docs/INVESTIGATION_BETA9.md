# Bêta 9 — veille RTC native sur Aura 2

1er novembre 2026. La bêta 8 n’a pas apporté le gain attendu sur l’appareil. **L’objectif de consommation totale divisée par sept reste non validé.** Cette livraison remplace son pont de veille par un autre chemin natif et conserve un repli borné.

## Ce que disent les nouveaux fichiers

| Session bêta 8, heure de Paris | Durée | Baisse de jauge | Veilles du pont | Résultat du pont |
|---|---:|---:|---:|---|
| 31/10 22:14:20 → 01/11 15:00:45 | 16 h 46 min 25 s | 7 points | 1 | Nouveau refus profond, pont désactivé |
| 01/11 15:06:10 → 19:02:51 | 3 h 56 min 41 s | 4 points | 1 | Même repli |

La première session comporte 1 006 mises à jour ; la seconde 236. Le second export affichait 1 242 car les compteurs s’additionnaient entre sessions. La bêta 9 corrige aussi ce défaut de diagnostic. Les erreurs de rendu et retards déclarés sont nuls, mais les appels de veille sont souvent refusés : l’absence d’erreur de rendu ne prouve pas une veille correcte.

Le pont suspend effectivement le noyau une fois, puis le passage à la veille profonde échoue avec le motif `Veille profonde refusée après décharge`. Le reste de la session reprend donc l’ancien chemin et ses essais répétés. Le problème ne se résume pas à une mauvaise option activée par l’utilisateur.

À 18:24:03, un refus de `mem` correspond à une durée native rapportée de **4,469610 s**, puis au garde de 15 s. Le critère de durée « moins d’une seconde » manquait ce refus. La nouvelle version tient aussi compte du drapeau que la fonction native remet à zéro lorsqu’elle refuse `mem`. Le budget d’échecs reste conservé. Le diagnostic distingue désormais `native_rejected`.

Données résumées dans `BETA8_FIELD_REPORT.json`. Les journaux bruts, les réglages transmis et le numéro de série ne sont pas incorporés à la distribution.

## Pourquoi le modèle de bêta 8 était insuffisant

Le délai FP9928 est exprimé en `jiffies`, avec un début lié à une transition d’alimentation. Le pont utilisait une échéance BOOTTIME après le dessin et supposait que l’attente suspendue pouvait ensuite satisfaire la transition profonde. Ces références ne sont pas interchangeables. Les horloges monotoniques s’arrêtent pendant la suspension ; la gestion des ticks dépend aussi du noyau et de son architecture. Les traces montrent en outre des différences de domaine d’horloge proches de 4,295 s. Elles ne permettent pas de traiter aveuglément une durée BOOTTIME comme une preuve de décharge du pilote installé.

Le modèle a été corrigé pour tester un délai de pilote qui s’arrête pendant la suspension. **Le code exact du pont bêta 8**, extrait du ZIP livré et conservé comme référence, reproduit alors le symptôme observé : une seule utilisation puis le même refus profond et le même repli. `BETA8_REPLAY.json` et `tests/fixtures/beta8_power.json` rendent ce test reproductible. Ce test n’est pas une preuve de chaque détail interne du firmware ; il invalide l’hypothèse sur laquelle reposait le précédent pont.

La nouvelle stratégie fonctionne dans les deux modèles de temps : délai qui avance ou qui s’arrête pendant la suspension. Elle ne tente plus de prévoir l’expiration du délai profond à partir de cette attente.

Sources primaires : [horloges Linux](https://docs.kernel.org/core-api/timekeeping.html), [Linux v3.0 timekeeping.c](https://github.com/torvalds/linux/blob/v3.0/kernel/time/timekeeping.c), [noyau Kobo publié](https://github.com/kobolabs/Kobo-Reader/tree/master/hw/imx6sl-auraonetwo). Le noyau source publié est une référence, pas une copie démontrée du binaire installé.

## Nouveau fonctionnement

Après confirmation fraîche du refus FP9928 sur `Kobo_star` et Linux 3.0.35, le plugin utilise **`Kobo:standby()` jusqu’à la prochaine alarme minute existante**. Il ne crée aucune alarme technique et ne repasse pas aussitôt en veille profonde.

À chaque minute, le noyau se réveille, KOReader traite l’alarme, l’horloge redessine ses régions modifiées, puis attend la fin du contrôleur. Une marge UI d’au moins une seconde permet l’arrêt différé de sa sortie ; une marge utilisateur supérieure est respectée. La veille native reprend jusqu’à l’échéance suivante. Le processeur n’exécute pas de boucle de scrutation pendant cet intervalle.

Le premier sommeil reste celui de KOReader. Une première tentative refusée peut être nécessaire pour obtenir la preuve FP9928 et le drapeau natif zéro. Une fois le mode choisi, les minutes suivantes ne répètent pas les écritures profondes, leurs refus et leurs préparations de deux secondes.

Le mode natif `standby` correspond à STOP ; le mode `mem` à DORMANT dans la documentation NXP. STOP suspend le processeur et conserve la mémoire, mais son coût résiduel peut être supérieur à celui de DORMANT. Le bilan total doit donc être mesuré : diminuer le temps éveillé ne garantit pas le même facteur de batterie. Aucune temporisation électrique, adresse mémoire, image noyau, commande GPIO ou valeur de tension n’est modifiée par le plugin.

Source : [i.MX 6SoloLite Linux Reference Manual, chapitre 14](https://community.nxp.com/pwmxy87654/attachments/pwmxy87654/imx-processors/37232/2/i.MX_6SoloLite_Linux_Reference_Manual.pdf), et chemin `mx6_suspend_enter` du noyau publié. Le modèle conserve également le cas spécifique SoloLite `STOP_XTAL_ON` comme limite à toute estimation abstraite des courants.

## Stabilité et compatibilité

Le mode exige une trace FP9928 nouvelle et vérifiée, le support natif `standby`, une alarme propre future en tête, un drapeau zéro, le Wi-Fi éteint, l’absence de charge et des horloges utilisables. Une alarme étrangère prioritaire conserve le chemin natif. Les autres tâches ne sont ni supprimées ni exécutées par ce module.

Le retour passe par la boucle d’événements et le callback natif que bouton/couverture annulent déjà. Une reprise utilisateur ou une demande étrangère pendant un hook natif ne peut pas être suivie d’une nouvelle demande de sommeil de l’horloge. Les réveils anticipés réellement suspendus autorisent au plus deux réentrées dans le même intervalle ; les échecs, exceptions ou réveils répétés désactivent le mode pour la session. Le chemin natif de repli et sa limite d’échecs restent actifs. Le budget n’est remis à zéro qu’après un sommeil et une alarme propre vérifiés.

La restauration native du gouverneur CPU est conservée, y compris après exception. La première erreur du mode conserve un instantané noyau borné et une trace versionnée ; il n’y a pas de collecte noyau à chaque minute. La première activation réussie apparaît une fois dans `crash.log`.

Les dix cadrans, les régions de rendu, les gris, les complications, la cadence minute, les nettoyages et les réglages restent disponibles. STOP conserve un autre état des périphériques que la veille profonde, notamment la possibilité native de réveil par entrée : ce choix est une modification du chemin de puissance, pas une prétention à une équivalence électrique entre les deux états.

## Résultats des tests

**156 tests automatisés réussis**, dont le rejeu bêta 8 et les contrôles du mode minute, des horloges, des sessions, des erreurs, des hooks et des alarmes. Les vraies fonctions natives KOReader sont exécutées avec des périphériques et horloges contrôlés.

| Scénario de 240 minutes, mêmes hypothèses | Repli profond | Veille RTC minute |
|---|---:|---:|
| Tentatives `mem` | 718 | 2 |
| Retours courts/refusés | 478 | 1 |
| Appels `standby` | 0 | 239 |
| Temps éveillé simulé | 2 538,020 s | 458,330 s |
| Part suspendue selon horloges simulées | 82,376 % | 96,817 % |
| Alarmes auxiliaires ajoutées | 0 | 0 |

Ce sont des résultats de contrôle logiciel. Le coût actif d’une transition réussie est notamment simplifié et aucun courant STOP/DORMANT n’est modélisé. **Ni ce tableau ni la réduction du nombre d’appels ne valident un gain énergétique ×7.** Hypothèses : `RTC_STANDBY_SIMULATION.json`.

Les tests vérifient aussi des sessions successives, la conservation de l’intervalle réel dans l’export après arrêt, le refus de `mem` dont la durée rapportée dépasse une seconde, les erreurs de RTC, le réveil anticipé borné, la charge, le réseau et les interruptions utilisateur. Le compteur de rendu et celui des erreurs de veille ne sont pas confondus.

KOReader officiel v2026.07.1 Linux SDL est exécuté en x86_64 et ARMv7/QEMU Cortex-A9 : chargement des dix paquets, éditeur, export, mises à jour et paysage. Les résultats sont dans `validation/beta9` à la racine du ZIP. Le firmware utilisateur utilise v2026.07.2 ; cette différence demeure. QEMU user mode utilise le noyau hôte et ne reproduit pas la dalle, la PMIC ou les courants. Les tests C des fonctions publiées utilisent eux aussi des témoins périphériques et n’amorcent pas un noyau Kobo.

## Rapport de la prochaine session

Après remplacement et redémarrage, les réglages transmis (`fast_rtc=true`, intervalle 60 s) activent déjà la sélection conditionnelle. Dans `settings/atelierclock/last-session.json` :

- `power.pmic_settle.mode` : `native_rtc_standby` ;
- `cycles` : intervalles minute achevés ; `early_wakes`, `failures`, `reason` : éventuels replis ;
- `auxiliary_alarms` : zéro ; `samples` : douze derniers intervalles au maximum ;
- `power.timing.standby_verified_sleep_s` : durée suspendue dans ce chemin ;
- `rtc.cycles`, `metrics.refreshes` et les compteurs de garde : remis à zéro à chaque session.

`awake_s` suit maintenant le total des horloges noyau incluant la veille minute ; `outside_mem_s` conserve l’ancienne différence qui ne comptait pas ce sommeil. L’export manuel garde aussi les bornes de la dernière session en mémoire au lieu de les remplacer par l’heure d’export.

Le coût total doit encore être comparé physiquement, à cadran, éclairage, réseau et conditions comparables. La cible de référence est 0,178 point/heure ; les baisses observées en bêta 8 ne la valident pas. Cette version fournit un nouveau chemin testable et un repli, pas une certification électrique obtenue sans appareil.
