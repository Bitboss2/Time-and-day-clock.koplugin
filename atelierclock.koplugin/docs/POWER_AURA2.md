# Actualisation à la minute — retour bêta 5 et correction bêta 6

## Diagnostic du retour utilisateur

Les photos de bêta 3 identifient `Kobo_star`, 212 DPI, 758×1024 : 7 points perdus en 337 minutes (environ 1,25 point/heure sur cet intervalle), rendu CPU 7 ms, surface 9,3 %, aucun retard ni rattrapage indiqué. Ces éléments montrent une consommation insatisfaisante ; ils ne prouvent pas que le dessin soit le poste dominant ni que le noyau ait dormi correctement à chaque cycle.

Le champ de suspension provenait de `Device.last_suspend_time`, au format fixe `ui/time`, puis était affiché sans décodage. 2 787 663 unités représentent **2,787663 secondes**, pas 32 jours. Ce dernier sommeil peut avoir été interrompu par le réveil utilisateur ; il ne représente pas la moyenne de la session.

## Changements livrés

1. Conversion officielle des temps natifs. Le seuil de validation de sommeil est une vraie seconde. Un retour de quelques millisecondes ne remet plus à zéro le budget d’échecs KOReader. Un drapeau noyau explicitement remis à zéro interdit également cette validation.
2. Réutilisation conditionnelle de la préparation de suspension déjà active. Après un réveil propre à l’horloge, la préparation de deux secondes n’est pas répétée si le sommeil précédent est nouveau/valide, le drapeau noyau est toujours à 1 et le rafraîchissement écran est terminé via une API déclarée fiable. La vérification du drapeau est répétée à l’exécution.
3. Conservation de la phase native finale : synchronisation des fichiers, demande de sommeil profond, gestion d’échec et garde RTC. La première suspension reste complète. Le bouton et la couverture continuent d’annuler la tâche native différée.
4. Repli vers la préparation complète si un cycle réutilisé dort moins d’une seconde. Cette réutilisation reste désactivée jusqu’à la prochaine session ; les échecs de suspension restent comptés par KOReader.
5. Les alarmes étrangères futures ne créent plus automatiquement une période d’attente éveillée de 30 secondes ; leur échéance RTC est conservée. Les tâches imminentes ou déjà en traitement conservent leur fenêtre native.
6. Les mises à jour régulières utilisent la catégorie de rafraîchissement `ui`, sans consommer le compteur de pages du lecteur. Le nettoyage complet configuré dans Atelier reste actif.
7. Mesure du sommeil cumulé, de la proportion endormie et du délai entre réveil et prochaine demande de sommeil. Les mesures restent en RAM jusqu’à un export demandé.

Le profil **Veille → Optimiser Aura 2 → Appliquer** active le garde rapide, la réutilisation et la marge après affichage de 0,1 s. La fréquence reste au choix existant : conserver **1 minute**. Aucun passage implicite à cinq minutes ni pause nocturne ajoutée.

## Fondement du chemin réutilisé

Dans le code Kobo étudié, `Kobo:suspend()` écrit 1 dans `state-extended`, puis programme `_doSuspend` deux secondes plus tard. `_doSuspend` exécute `sync`, demande `mem`, puis programme le garde RTC au réveil. Le chemin de réveil utilisateur remet le drapeau à 0 ; l’échec de `mem` le remet également à 0.

Le noyau Kobo publié pour la famille i.MX6SL fournit une lecture du drapeau et ignore une nouvelle écriture de 1 lorsque ce drapeau vaut déjà 1. Cette observation justifie d’étudier la suppression de la préparation répétée, après fin de l’affichage. Elle ne démontre pas que tous les firmwares acceptent le même timing : le code reste conditionnel et réversible.

Source officielle : https://github.com/kobolabs/Kobo-Reader/tree/master/hw/imx6sl-auraonetwo — membre `kernel/power/main.c` de `kernel.tar.bz2`, consulté le 30 octobre 2026.
SHA256 du fichier source étudié : 3ecf182539c3c6e9413e89188ba68e60bc99bb20350103bf2f61728c49865c57

Les sources KOReader des tests sont épinglées dans `tools/fetch_test_dependencies.py`. Aucun morceau du code noyau Kobo n’est incorporé au plugin ; la voie finale appelle la fonction native déjà chargée par KOReader.

## Ce que le test utilisateur doit permettre de distinguer

- **Préparations réutilisées > 0**, forte proportion de sommeil, durée d’éveil courte : le nouveau chemin est effectivement utilisé.
- **Préparations réutilisées = 0** : consulter le motif de retour en veille ; le plugin a gardé le chemin natif.
- **Sommeils très courts / repli** : le noyau ou un périphérique empêche le sommeil ; le diagnostic ne masquera plus ces échecs.
- **Sommeil majoritaire mais décharge importante** : mesurer le coût de veille de base et de la dalle, avec la même batterie et les mêmes conditions.

Le temps d’éveil affiché jusqu’à la demande native exclut le travail effectué ensuite à l’intérieur de `_doSuspend`, dont `sync`. Le ratio de sommeil utilise le cumul natif et inclut ce coût dans la différence avec le temps de session. Les données de jauge ne sont pas une mesure de courant.

La durée de préparation évitée ne permet pas d’annoncer un pourcentage d’économie de batterie. La bêta 4 doit être comparée sur le même cadran, au même intervalle et dans les mêmes conditions que la bêta 3.

## Cible électrique ×7 et limite physique

La demande porte sur la consommation totale observée avec une actualisation par minute. La référence de la photo est 7 points en 337 minutes, environ 1,246 point/heure. Diviser cette consommation par sept donne **0,178 point/heure**, soit **1 point sur 337 minutes**. L’équivalent linéaire de 4,27 points sur 24 h sert uniquement de repère : la jauge, la température et la batterie peuvent être non linéaires.

Le bilan comporte le coût de veille de base, les transitions noyau réveil/sommeil et les mises à jour e‑ink. Un processeur qui dort davantage ne réduit pas automatiquement la consommation totale dans le même rapport. Si la part fixe de l’énergie de référence est `f` et que la part optimisable est divisée par `r`, le gain total vaut `1 / (f + (1-f)/r)`. Si `f = 10 %`, il faut diviser la part restante par 21 pour atteindre un gain total de 7. Si la veille de base dépasse à elle seule un septième de la consommation de référence, la cible totale est inaccessible en ne réduisant que le travail de l’horloge. **La valeur de cette part fixe n’est pas connue pour cette Kobo.**

Le plugin ne revendique donc aucun gain électrique ×7. Le diagnostic exporte la cible et `hardware_verified=false`, séparément du facteur de réduction des fenêtres graphiques. Ni un ratio de sommeil ni une surface mise à jour ne sont convertis en autonomie fictive.

## Bêta 5 : réduire le travail du contrôleur sans changer les cadrans

Le moteur conserve déjà l’ancienne tuile BB8 et construit la nouvelle quand sa donnée change. Le nouveau module `render/delta.lua` compare leurs octets en tenant compte du pas mémoire de chaque ligne. Il groupe les différences en huit bandes au maximum par tuile, puis fusionne les régions selon le coût de surface jusqu’à n’en garder que quatre sur l’écran. Les chevauchements sont fusionnés selon le comportement de UIManager. L’ancienne enveloppe prudente est conservée si le regroupement serait plus grand, sauf si les pixels prouvent que cette enveloppe est incomplète.

Le scan est borné à 1 048 576 pixels par tuile. Il exige un buffer BB8 sans rotation, une inversion identique et LuaJIT actif. Format inconnu, lecture impossible ou erreur : repli sur les anciennes régions. Il ne lit pas le framebuffer matériel, ne crée pas de copie complète supplémentaire en production et ne change aucun pixel de l’image. Les fonds, l’anticrénelage et le mode sombre restent identiques. Les images inchangées malgré une nouvelle clé de donnée ne produisent plus de rafraîchissement inutile.

La catégorie native `ui` reste utilisée. Le backend officiel Kobo mappe déjà ce rafraîchissement sur `WAVEFORM_MODE_AUTO` ; forcer DU ou A2 pour des textes anticrénelés et des textures grises ne constitue pas une garantie d’économie ou de qualité. Le nettoyage complet et l’attente de fin du contrôleur restent actifs. Source officielle étudiée : https://github.com/koreader/koreader-base/blob/007ac6a81e2de4822c8df7ce57b8dbb06aa3b8ea/ffi/framebuffer_mxcfb.lua

Le comparatif de 60 minutes par cadran, polices de substitution et framebuffer Pillow, donne des surfaces moyennes réduites de ×1,5 à ×11,8 selon le modèle. Il n’inclut pas le coût CPU réel du scan sur ARM, les nettoyages complets, les transitions du noyau ni les courants de la dalle. Ces facteurs ne se multiplient donc pas avec les deux secondes de préparation évitées pour annoncer un gain électrique.

## Validation sur appareil encore nécessaire

1. Remplacer entièrement le plugin, conserver ses préférences, choisir le même cadran et ses mêmes complications que la référence.
2. Activer **Veille → Optimiser Aura 2 → Appliquer**, avec **1 minute**. Garder éclairage, nettoyage, pause nocturne et Wi-Fi identiques pour la comparaison ; ne pas recharger pendant la mesure.
3. Mesurer idéalement 24 à 48 h et exporter le diagnostic. Relever le débit de décharge, le temps de sommeil, les replis et le CPU de rendu, qui inclut désormais le scan. Une baisse de 1 point sur seulement quelques heures est trop proche de la résolution de la jauge pour certifier un facteur précis.
4. Comparer avec une veille statique dans les mêmes conditions afin d’estimer le coût de base. Pour valider un facteur exact, répéter aussi la mesure de référence bêta 3, la courte observation photographiée ne constituant pas à elle seule un banc énergétique contrôlé.

L’objectif reste non atteint au sens de la validation tant que cette mesure physique ne le confirme pas. Le logiciel fournit une nouvelle réduction concrète du travail, pas une promesse fondée sur un multiplicateur de surface.

## Retour physique du 31 octobre 2026 — bêta 5

Les quatre nouvelles photos donnent 10 points perdus en 679 minutes, 23 ms CPU, 6,5 % de surface demandée et une réduction graphique ×1,13. Le diagnostic affiche 27 324,907 s cumulées dans les appels natifs, soit 67 %, une seule préparation réutilisée et un seul repli avec le motif « suspension trop courte ». Le dernier appel natif a duré 0,462 s. **Ce dernier appel peut aussi avoir été interrompu par le réveil utilisateur ; il ne démontre pas à lui seul une panne récurrente du noyau.**

Le débit observé est 0,884 point/heure, contre 1,246 pour le précédent essai bêta 3 : rapport ≈1,41. La cible reste 0,178 point/heure, soit environ 2,01 points sur 679 minutes. Ces débits sont ceux de jauges sur deux intervalles, pas des mesures de courant dans des conditions contrôlées.

Le repli après la première réutilisation est confirmé. Les photos ne disent pas combien de fois les tentatives natives suivantes sont revenues trop tôt, ni pourquoi. Le code natif étudié attend 15 secondes avant de contrôler un réveil non attribué à une alarme. Une répétition de ce délai après chaque actualisation constitue une hypothèse cohérente avec le faible temps passé dans `mem`, mais elle doit être vérifiée dans le diagnostic ou le journal KOReader.

## Correction ciblée de bêta 6

Après une actualisation réussie et l’armement de la prochaine alarme propre, le plugin ouvre une fenêtre de récupération de 12 secondes. Si une tentative revient en moins d’une seconde, le **même contrôle natif** peut être programmé après 1 seconde, puis après 2 secondes au maximum pour ce cycle. Il est ensuite laissé au garde natif de 15 secondes. Les conditions exigent la même session/génération/mise à jour, une alarme propre en tête et suffisamment future, l’absence de grâce étrangère, le Wi-Fi éteint et l’absence de charge. Une demande externe explicite de replanification révoque la fenêtre.

Cette récupération ne réactive pas une préparation réutilisée qui a échoué : elle conserve la préparation complète de deux secondes avant chaque nouvel essai, le `sync`, l’appel `mem` et le budget natif d’échecs. Le bouton et la couverture conservent l’annulation du contrôle natif. La première suspension et les retours sans preuve d’appartenance à l’horloge gardent le comportement normal. Aucun appel sysfs supplémentaire de suspension n’est introduit par le plugin.

Le test contrôlé avec un refus de 0,462 s après chaque minute reproduit 67,610 % du temps dans les appels natifs sur 90 cycles. Le contrôle rapproché donne 90,682 % dans le même scénario ; les temps de sommeil BOOTTIME/MONOTONIC simulés sont respectivement 66,848 % et 89,921 %. Le nombre de tentatives est identique. **Ce ne sont ni des résultats physiques, ni une preuve que le scénario est celui de cette liseuse.** Voir `RECOVERY_SIMULATION.json` et `tests/test_power_recovery.py`.

L’ancien compteur appelait « sommeil » la durée bloquée dans `mem`, ce qui pouvait inclure les refus et les phases actives du noyau. La bêta 6 garde ces durées comme telles et calcule séparément le sommeil par BOOTTIME moins MONOTONIC, uniquement si le module natif confirme la disponibilité de BOOTTIME. Les 120 dernières tentatives contiennent le chemin, les durées, le type de garde et son délai demandé. Ce délai demandé peut être annulé par un événement utilisateur : il n’est pas présenté comme une attente effectivement parcourue. Trois premiers retours courts peuvent aussi conserver les statistiques de suspension si le noyau les expose déjà ; rien n’est monté ou écrit pour les obtenir.

La comparaison BB8 utilise maintenant `memcmp` pour sauter les lignes identiques. Après trois scans dont le gain total de surface est inférieur à 20 %, elle est suspendue pendant sept changements puis sondée à nouveau. Ce choix échange une partie des petites économies de surface contre moins de travail CPU. Il ne modifie pas les images ou les nettoyages ; son temps CPU réel sur ARM doit être mesuré.

Avant remplacement, exporter et joindre **le diagnostic JSON bêta 5** déjà disponible. Les photos ne montrent pas ses derniers échantillons de durées/chemins. Le JSON de bêta 6 permet ensuite de confirmer ou réfuter l’hypothèse des gardes de 15 secondes. Un journal KOReader montrant l’erreur `mem` reste nécessaire si le noyau refuse systématiquement l’entrée ; le plugin ne devine pas un code d’erreur à partir d’une durée courte.


## Bêta 7 — investigation du noyau et des journaux réels

Voir [INVESTIGATION_BETA7.md](INVESTIGATION_BETA7.md) pour les comptages des sessions bêta 5 et 6, les fonctions PMIC étudiées, le défaut d’appartenance de callback reproduit, la nouvelle sauvegarde automatique et les limites exactes de l’émulation ARM. Les demandes propres utilisent désormais un marqueur explicite au lieu d’une comparaison entre domaines d’horloge. Le pilote peut imposer une décharge après l’affichage ; aucune temporisation électrique n’est réduite. Le gain énergétique total ×7 reste à démontrer sur matériel.


## Bêta 8 — pilote FP9928 confirmé

Les nouveaux rapports identifient explicitement l’attente VEE du FP9928. Le pont de veille légère natif pendant la décharge, ses conditions, son alarme intermédiaire et ses replis sont détaillés dans [INVESTIGATION_BETA8.md](INVESTIGATION_BETA8.md). Il ne raccourcit pas le délai électrique et conserve la préparation native de veille profonde. Le sommeil vérifié inclut désormais la veille légère mesurée séparément ; l’objectif énergétique ×7 reste non validé.


## Bêta 9 — retrait du pont court

Les essais utilisateur invalident l’amélioration attendue de bêta 8. Le code de production utilise désormais la veille RTC native jusqu’à l’alarme minute, sans pont ni alarme auxiliaire. Les courants STOP/DORMANT restent inconnus ; aucun gain ×7 n’est certifié. Voir [INVESTIGATION_BETA9.md](INVESTIGATION_BETA9.md) pour les logs, le rejeu de l’ancien code, les refus longs et les conditions du nouveau chemin. Les sections précédentes sont historiques.
