# Recherche et choix de conception — 30 octobre 2026

Sources consultées directement dans les documentations Apple et KOReader. Les références orientent les interactions et les familles de composition ; aucun code ou graphisme Apple n’est importé.

| Source primaire | Principe retenu et adaptation e‑ink |
|---|---|
| [StandBy / iPhone Duo](https://support.apple.com/guide/iphone/use-standby-iph878d77632/ios) | Ajouter des cadrans, parcourir une collection et séparer style/contenu. Un grand aperçu immobile remplace les transitions animées. |
| [Changer le cadran de l’Apple Watch](https://support.apple.com/fr-fr/guide/watch/-apda6559ad78/watchos) | Choix visuel puis modification du cadran. La navigation ne sélectionne pas silencieusement la variante. |
| [Fonctionnalités des cadrans Watch](https://support.apple.com/en-euro/guide/watch/apde9218b440/27/watchos/27) | Familles typographiques, analogiques et modulaires ; emplacements de complications limités et lisibles. Compositions et noms entièrement originaux. |
| [Apple HomeView](https://www.apple.com/apple-homeview/) | Lisibilité à distance et vues spécialisées. Reprise de l’idée de calendrier, grand chiffre et modules ; absence d’animations, de capteurs de présence et de dépendances réseau. |
| [Présentation HomeView](https://www.apple.com/newsroom/2026/10/meet-apple-homeview-a-new-way-to-enjoy-entertainment-and-manage-the-home/) | Hiérarchie du contenu sur écran de table. Le HomeView décrit par Apple dispose de 7 pouces ; l’Aura édition 2 dispose de 6 pouces : limiter le nombre de complications et donner la priorité à l’heure. |
| [Kobo Aura édition 2](https://help.kobo.com/hc/fr/articles/360019203933-Kobo-Aura-%C3%A9dition-2) et [identification Kobo](https://help.kobo.com/hc/fr/articles/360019676973-Identifier-votre-liseuse-Kobo-ou-votre-tablette-Kobo) | Référence du modèle N236 et écran de 6 pouces. La résolution et le DPI effectifs sont lus dans KOReader au lieu d’être supposés pour toute la gamme. |
| [UIManager KOReader](https://github.com/koreader/koreader/blob/master/frontend/ui/uimanager.lua) | Rafraîchissements partiels, fenêtres disjointes et promotion par le gestionnaire natif. Pas de contournement du contrôleur écran. |
| [Kobo device](https://github.com/koreader/koreader/blob/master/frontend/device/kobo/device.lua) et [RTC](https://github.com/koreader/koreader-base/blob/master/ffi/rtc.lua) | Conservation de la préparation de suspension, du contrôle des réveils et de la file d’alarmes partagée. Une optimisation du dessin n’annule pas ce coût fixe. |

## Conséquences concrètes

Les nouveaux cadrans définissent leurs blocs, positions et emplacements dans un format déclaratif. Les familles ligne/anneau/rectangle produisent des prévisualisations issues du même moteur que le screensaver. Les variantes sauvegardées ne se modifient pas mutuellement.

Le dessin e‑ink repose sur de grands aplats noirs et blancs, des contours visibles et des chiffres sans secondes. Les textures sont fixes et originales. Chaque modèle possède une composition paysage spécifique ; il ne s’agit pas d’une image portrait étirée. Les dates et calendriers se conservent jusqu’à ce que leur donnée change.

La météo, les événements personnels et la domotique demanderaient des sources et politiques de synchronisation supplémentaires. Cette version se limite aux informations locales réellement disponibles ; elle ne simule pas ces services.
