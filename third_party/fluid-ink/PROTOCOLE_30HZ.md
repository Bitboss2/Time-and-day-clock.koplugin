# Vérification de la 5.0 à 30 et 60 ips ciblées

Séquence recommandée sur cette unité.

1. À 30 ips, comparer Moteur 4.5 et Moteur 5.0, tous deux à deux phases. Utiliser un défilement auto de même durée et photographier le fond sous la courbe à 30 s puis à 3 min, avant et après pause. Répéter en ordre inverse avec le même éclairage.
2. À 60 ips, filmer la mire haute cadence ou Zone 96² à 120/240 i/s dans chaque conduite. Compter les positions distinctes avec un contraste suffisant sur plusieurs secondes. Un scan confirmé ou une nouvelle source soumise ne garantit pas une position discernable.
3. À cadence cible et conduite identiques, comparer Zone 96² et Page en mouvement. Utiliser `worker_cpu_pct` avec `position_work_pct`, puis mesurer séparément le coût du moteur graphique ou de l’émulateur pour estimer la marge réelle.
4. Conserver le CSV, le rapport de phases et la vidéo originale. Exclure les premières secondes de GC16/DU du calcul de cadence.

---

# Mesurer l’encrassement en 4.5

Comparer Moteur 4.5 (+2), Blanc +4, Fusion seule (+0) et Moteur 4.0 avec Impulsions 2, File 1, cible 30, Bayer 8×8 et mêmes température/éclairage. Chaque changement de conduite refait la référence constructeur : démarrer les essais après cette préparation.

Sur une à trois minutes de défilement comparable, conserver les CSV et photographier les mêmes zones pendant le mouvement puis après pause. Inverser l’ordre des conduites pour limiter un effet de température ou d’ordre. Garder une référence au début de chaque essai et répéter s’il varie fortement. Les deux photos seules ne donnent pas une vitesse d’encrassement.

Fusion seule permet d’isoler les +2/+4 doses puisque son calcul est identique à celui de la 4.5. Moteur 4.0 permet d’isoler la fusion. Comparer simultanément la lisibilité, les traces, les contours en mouvement, `source_submit_fps`, `phase_scan_fps` et `phase_cycle_mean_ms`, hors activations. Un blanc plus propre avec une transition plus lente reste un compromis à documenter.

`fused_mean_ms` est déjà compris dans `plan_mean_ms` ; ne pas l’additionner une seconde fois. La baisse de `quant_mean_ms` reflète le regroupement du travail, pas sa disparition. La cible de supplément blanc n’est pas une mesure des doses optiquement suffisantes.

---
Protocole de cadence et de contraste :

# Vérifier la fluidité, le contraste et les traces

## Ce que la démonstration peut établir

Une amélioration reproductible sur la même dalle, avec les mêmes tensions et le même matériel, montrerait que le logiciel et le séquencement influencent fortement ses possibilités. Cela ne démontrerait pas une restriction volontaire, une capacité identique pour tous les écrans, ni l’absence de compromis avec contraste, température ou durée de transition.

## Comparaison 3.5 / 4.0

- Utiliser le même éclairage, la même température, le même niveau de lumière frontale et les mêmes réglages photographiques. Garder A2, Bayer 8×8, File 1, deux impulsions, cible 30 et aucun nettoyage automatique.
- Commencer par Moteur 3.5, puis Moteur 4.0 ; répéter dans l’ordre inverse. Exclure les préparations GC16/DU et les premières secondes après changement. La 3.5 originale est aussi fournie pour confirmer le comparateur.
- Effectuer le même défilement automatique et comparer des passages correspondants. Enregistrer une dizaine de secondes par conduite, avec les CSV. Répéter si le débit varie fortement.
- Photographier la mire Contraste avant mouvement, pendant mouvement et après pause. Vérifier que les références fixes restent distinctes des zones animées. Une image plus rapide mais durablement grise ne remplit pas l’objectif.

## Mesure optique

Filmer la mire de cadence à fréquence élevée, idéalement 120 ou 240 images/s avec exposition et mise au point fixes. Conserver le fichier original et sa cadence réelle ; un ralenti exporté peut modifier les horodatages. Éviter les reflets et un éclairage qui scintille.

Suivre image par image la position de la barre et le code d’image. Compter les états effectivement discernables sur plusieurs secondes et leurs durées ; signaler les états manquants, superposés ou trop peu contrastés. Le code encode une image composée par l’interface : sa présence ne prouve pas qu’elle a été présentée entièrement ni stabilisée.

L’aplat alterné à 15 Hz change de cible 30 fois/s : un résultat gris peut révéler une transition incomplète ou une intégration par la caméra. Ce test seul ne suffit pas. Comparer avec l’alternance lente, la barre mobile et les références noires/blanches. Une capture fixe ne permet pas de conclure sur une cadence.

## Critères à conserver séparément

| Observation | Ce qu’elle établit |
|---|---|
| Interface à 30 Hz | Rendu logiciel disponible |
| 30 nouvelles cibles soumises/s | Transport de cibles ; certaines transitions peuvent rester incomplètes |
| 30 scans confirmés/s | Débit des requêtes ; inclut les scans de finition |
| 30 positions distinctes et lisibles/s en vidéo | Résolution temporelle visible de cette scène |
| Noir et blanc proches des références pendant mouvement | Contraste conservé pour la scène testée |
| Absence de traces après déplacement et stabilisation | Rémanence faible dans les conditions testées |

L’objectif complet demande fluidité, contraste et faibles traces simultanément. La non-régression logicielle est testée hors appareil ; la non-régression optique doit être observée sur la Kobo.
