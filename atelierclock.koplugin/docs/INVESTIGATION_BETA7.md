# Investigation Aura 2 — bêta 7

31 octobre 2026. Objectif conservé : afficher l’heure chaque minute, avec tous les cadrans et leurs réglages, en divisant la consommation totale de bêta 3 par sept. **Cet objectif n’est pas démontré. Cette livraison corrige un défaut reproductible et ajoute la preuve noyau qui manque encore.**

## Ce que les journaux reçus établissent

Les deux fichiers fournis sont préservés. Le second prolonge exactement le premier ; il contient bien la session supplémentaire allant jusqu’à 12:31. Le KOReader installé s’annonce v2026.07.2.

| Intervalle étudié, borne finale exclue | Cycles complets | Refus de `mem` | Délais entre refus et contrôle suivant |
|---|---:|---:|---|
| 30/10 21:27 → 31/10 08:46, code bêta 5 | 679 | 679 | 679 × 15 s |
| 31/10 09:58 → 12:30, bêta 6 | 152 | 227 | 75 × 1 s, 75 × 2 s, 77 × 15 s |

Dans la seconde plage, 75 minutes ont deux refus et les deux contrôles rapprochés ; 77 minutes ont un refus puis le contrôle natif de 15 s. Les attentes de contrôle totalisent 1 380 s, soit 23 minutes sur 152. Il faut y ajouter préparation, synchronisation et transitions du noyau ; ces chiffres ne sont pas une mesure de courant. Les événements après 12:30, lors du retour de l’utilisateur et de l’USB, sont exclus.

Un refus est suivi d’une tentative qui réussit : le message `Operation not permitted` ne prouve donc pas une absence permanente de permission sur le fichier. L’ancien compteur à zéro était celui des erreurs de rendu, pas celui des refus de suspension.

## Défaut logiciel reproduit et corrigé

La bêta 6 reconnaissait son appel différé avec une échéance provenant de BOOTTIME, comparée au moment d’exécution. Le planificateur UI emploie un autre domaine d’horloge, et les lectures/arrondis peuvent diverger. Un test avec seulement −0,5 ms par rapport à l’échéance fait perdre l’autorisation de récupération. Un déclenchement retardé au-delà de la fenêtre d’une seconde est également fragile. **Ce test démontre un défaut ; il ne démontre pas que tous les 77 cycles ont exactement cette cause.**

La bêta 7 attache un objet d’appartenance unique aux arguments de sa tâche. La référence de callback reste `device.suspend`, celle que le réveil natif annule. Le marqueur est retiré avant l’appel natif. Une demande étrangère ou un réveil utilisateur révoque l’autorisation ; le Wi-Fi, la charge, les alarmes étrangères, l’expiration de 12 s et la borne de deux essais restent contrôlés.

Cela supprime la dépendance à la concordance des horloges pour identifier le demandeur. Cela n’ignore pas les raisons pour lesquelles le matériel refuse le sommeil, et ne remet pas son compteur d’échecs à zéro après un refus.

## Ce que le noyau publié montre réellement

Source primaire : [Kobo-Reader, famille imx6sl-auraonetwo](https://github.com/kobolabs/Kobo-Reader/tree/master/hw/imx6sl-auraonetwo), archive `kernel.tar.bz2` consultée le 31 octobre 2026. La correspondance exacte avec le noyau installé n’est pas encore établie. Les empreintes des fichiers testés figurent dans `VENDOR_SUSPEND_TEST.json`.

Dans `drivers/video/mxc/mxc_epdc_fb.c`, fonction `mxc_epdc_fb_suspend`, le contrôleur peut refuser pour récupération d’une chute de tension, arrêt différé de l’éclairage, contrôleur d’écran encore alimenté ou refus du pilote d’alimentation de l’écran. Plusieurs refus internes deviennent `-1` à ce niveau, puis `EPERM` en espace utilisateur.

Dans `drivers/video/mxc/lk_tps65185.c`, fonction `tps65185_suspend`, le pilote refuse si un arrêt différé est encore en attente ou si la date de décharge n’est pas atteinte. Pour la branche de configuration 1024×758, il définit 400 ticks ; la configuration publiée contient `CONFIG_HZ=100`, soit **4 secondes dans cette configuration**. Le délai commence lors de la transition d’alimentation, pas nécessairement à la soumission du dessin. Cette valeur dépend des caractéristiques matérielles sélectionnées. Elle ne constitue pas une mesure du délai effectif sur la Kobo de l’utilisateur. Le pilote alternatif FP9928 comporte lui aussi un délai de stabilisation.

`waitForVSync()` attend une mise à jour e-ink. Il ne prouve pas que toutes les alimentations sont déchargées. De même, `FBIOBLANK` peut attendre l’arrêt du contrôleur sans constituer une preuve du dernier délai électrique. Réduire une boîte graphique ou attendre la fin d’une image ne résout pas forcément ce verrou.

Le test C extrait les deux fonctions de suspension sans en modifier le corps, puis remplace leurs interactions matérielles par des témoins contrôlés. Huit cas passent : avant et à l’échéance, travail différé, contrôleur alimenté, éclairage et récupération de tension. Avant l’échéance, le pilote PMIC renvoie `-2` et son appelant EPDC `-1`, ce qui explique comment `EPERM` peut apparaître sans problème d’accès aux fichiers. **Il ne démarre pas le noyau et ne mesure pas les rails.**

## Contournements examinés

| Technique | Résultat de l’examen |
|---|---|
| Reprise RTC et préparation natives | Conservées, avec l’identification explicite du demandeur et les contrôles rapprochés bornés. |
| Script de suspension de [Plato](https://github.com/baskerville/plato/blob/master/scripts/suspend.sh) | Attend deux secondes après le drapeau, puis synchronise et demande `mem`. Ne supprime pas la protection PMIC. |
| [TRMNL Kobo](https://github.com/usetrmnl/trmnl-kobo), `src/TRMNL/trmnlloop.sh` | Attend notamment cinq secondes avant la séquence et prévoit un deuxième essai. Aucune preuve d’un gain ×7 avec une mise à jour par minute. |
| Forcer DU/A2 | Peut modifier le rendu des gris et la qualité des cadrans. AUTO et les nettoyages configurés sont conservés. |
| Diminuer la temporisation de décharge | Change une contrainte électrique du pilote. Aucune preuve permettant de la réduire sans conséquence sur cette dalle. Non appliqué. |
| Veille intermédiaire pendant la décharge | Piste possible, mais ajoute une alarme et une transition, avec un autre état des périphériques. Sans vérifier la PMIC et le firmware réels, ce n’est pas une solution démontrée. Non activé. |
| Gouverneur CPU / noyau remplacé | Aucun gain ×7 vérifié ; ne traite pas automatiquement le refus périphérique. Aucun changement global appliqué. |

La recherche n’a pas trouvé de contournement parfait démontré pour ce modèle, ce firmware et cette cadence. L’existence d’une API ou le succès d’un tableau de bord à intervalle plus long ne suffisent pas à le démontrer.

## Traces nouvelles, bornées

À l’entrée de la session, le plugin relève l’identité noyau et un instantané de son tampon, si lisible. Aux trois premiers retours courts au maximum, il lit jusqu’à 16 Kio via `klogctl(3)` en lecture seule, conserve les nouveaux messages lorsqu’un recouvrement peut être vérifié et journalise jusqu’à 4 Kio avec la version et la raison du garde. Après ces trois occurrences, il ne continue pas à relever le noyau à chaque minute. Aucun montage debugfs ni vidage du tampon n’est effectué.

À la sortie normale, il écrit une seule fois `settings/atelierclock/last-session.json`, par fichier temporaire puis renommage. Le diagnostic manuel reste `settings/atelierclock/diagnostic.json`. Les premières traces sont également dans le `crash.log` de KOReader ; elles restent exploitables si l’application s’arrête avant sa sauvegarde de sortie. Si le journal noyau est interdit ou l’API absente, le rapport l’indique et les fonctions de l’horloge continuent.

Un premier essai de quelques minutes avec **Veille → Optimiser Aura 2 → Appliquer**, suivi d’un réveil normal, permet de chercher le pilote fautif dans `last-session.json`. Cela ne valide pas l’autonomie. La comparaison électrique doit ensuite mesurer bêta 3 et la nouvelle version dans les mêmes conditions, avec un témoin de veille statique. La cible issue de la photo est 0,178 point/heure ; la jauge seule sur une courte période ne certifie pas un facteur exact.

## Exécutions et limites

127 tests Lua/Python : réussis. KOReader officiel v2026.07.1 Linux x86_64 et ARMv7 sous QEMU user mode Cortex-A9 : les deux runs réussissent les 13 groupes de vérifications, avec dix cadrans chargés, éditeur et rendus à la minute. Les résultats natifs, journaux, exemples d’écran et diagnostics sont sous `validation/beta7` à la racine de cette distribution.

Cette émulation exécute les instructions ARM et les vraies bibliothèques KOReader, avec le noyau Linux hôte. Elle ne simule pas la PMIC, l’EPDC, la RTC ni les courants de l’Aura 2. Les durées CPU QEMU dépendent de la machine hôte et ne sont pas des mesures de performances physiques sur Kobo. Le test du noyau utilise des témoins C sur l’hôte, pas un noyau Kobo amorcé. **Aucun de ces tests ne permet d’annoncer une consommation divisée par sept.**
