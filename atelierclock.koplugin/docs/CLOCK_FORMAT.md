# Atelier `.clock` v2

Un `.clock` est un ZIP compressé en DEFLATE (ou stocké), avec `manifest.json`, un aperçu PNG et les textures PNG déclarées. Aucun script n’est exécuté. Le moteur 0.2.0 lit également le [format v1](CLOCK_FORMAT_V1.md). Les dix modèles livrés utilisent v2.

## Pourquoi une nouvelle version

La v1 décrivait des calques libres et des réglages globaux par source. La v2 décrit une composition lisible en portrait et paysage, ses styles, et des **emplacements de complications**. Une variante personnelle stocke le modèle choisi, l’apparence et le contenu de chaque emplacement. Ajouter deux variantes d’un modèle crée deux réglages indépendants.

La composition du modèle est déclarative et modifiable par un auteur de paquet ; l’utilisateur choisit le contenu de ses emplacements dans l’éditeur graphique. Aucun déplacement libre n’est nécessaire pour obtenir une disposition lisible.

## Exemple minimal

```json
{
  "format": "atelier-clock",
  "schema_version": 2,
  "engine_min": "0.2.0",
  "id": "exemple-v2",
  "name": "Exemple",
  "author": "Votre nom",
  "license": "CC0-1.0",
  "version": "1.0.0",
  "canvas": {"width": 758, "height": 1024},
  "preview": "preview.png",
  "assets": {"paper": "textures/paper.png"},
  "texture": "paper",
  "styles": ["plein", "fin", "contour"],
  "slots": [{
    "id": "bottom", "label": "Sous l’heure", "family": "inline",
    "default": "date", "allowed": ["none", "date", "battery", "world"]
  }],
  "layouts": {
    "portrait": {
      "blocks": [{"id":"time", "type":"digits", "part":"time", "box":[0.06,0.20,0.88,0.34]}],
      "slots": {"bottom":[0.08,0.78,0.84,0.12]}
    },
    "landscape": {
      "blocks": [{"id":"time", "type":"digits", "part":"time", "box":[0.05,0.15,0.60,0.55]}],
      "slots": {"bottom":[0.70,0.30,0.25,0.32]}
    }
  }
}
```

`box` est `[x, y, largeur, hauteur]` en fractions du viewport réel. Le moteur adapte le dessin à la case. Une case doit rester dans l’écran et mesurer plus de 2 % dans chaque direction. Les cases des blocs et des complications ne se superposent pas ; le validateur le vérifie. Réserver le bas de l’écran après `y=0.95` à la mention d’approximation/arrêt.

`texture` est facultatif. `texture_landscape`, également facultatif, désigne une texture paysage différente dans `assets`. En son absence, le paysage garde un fond uni ; il n’étire pas automatiquement le décor portrait. Les textures ne contiennent pas l’heure ni les données variables.

## Blocs graphiques

| Type | Données et dessin |
|---|---|
| `digits` | Chiffres ; `part` = `hour`, `minute` ou `time`. `invert:true` donne un panneau contrasté. |
| `segments` | Afficheur géométrique à sept segments ; mêmes parties. |
| `analog` | Aiguilles sans secondes ; `design` = `baton`, `cardinal` ou `sector`. |
| `calendar` | Mois courant, semaine commençant lundi, jour courant encadré. |
| `words` | Heure écrite en français, formulation numérique en anglais. |
| `timeline` | Règle de 24 heures ; verticale ou horizontale selon la case. Repère indicatif mis à jour par pas de cinq minutes. |
| `label` | Texte fixe `text`, au plus 120 octets. |

Le moteur ne choisit pas le dessin à partir d’un identifiant de cadran : un autre paquet peut recombiner les mêmes types de blocs. Les styles sont choisis parmi `plein`, `fin`, `contour`. Un paquet ne doit proposer que des styles ayant un effet sur son dessin ; les modèles analogiques et Signal n’offrent que plein/fin. Les polices natives KOReader sont employées, sans police propriétaire embarquée.

## Emplacements et sources

Chaque emplacement a un identifiant stable, un libellé, une famille (`inline`, `circle`, `rect`, `large`), une source par défaut et une liste de sources autorisées. Il doit disposer d’une case dans **les deux** orientations. Le rendu des aperçus dans le sélecteur provient du moteur réel.

Sources : `none`, `date`, `battery`, `day`, `week`, `world`, `book`. La batterie inconnue, le livre indisponible et les données absentes ne sont pas remplacés par des valeurs inventées. La progression de journée est indicative, par quarts d’heure. La lecture est un instantané des métadonnées KOReader au début de la scène.

Les modules ne créent pas d’alarme. L’heure principale et les modules sont actualisés lors des réveils déjà décidés par les réglages RTC. Aucun code réseau, URL de téléchargement ou fournisseur exécutable n’est autorisé par le moteur.

## Variantes et export

Les variantes restent dans `settings.json`, sous `collection`. Chaque enregistrement possède `uid`, `face`, `title`, `style`, `appearance` (`follow`, `paper`, `ink`) et `slots`. L’instance active est identifiée par `active_id` ; le champ `face` conserve la compatibilité avec les anciens réglages. Limite : 24 variantes.

Un export `.clock` peut inclure ce préréglage :

```json
"preset": {
  "style": "plein",
  "appearance": "paper",
  "slots": {
    "bottom": {"provider":"world", "zone":"Europe/Paris"}
  }
}
```

À l’ajout dans la collection, ce préréglage est copié dans la variante. Il ne référence pas les réglages d’une autre variante. Les fuseaux acceptés sont `UTC`, `Europe/Paris`, `Europe/London`, `America/New_York`, `Asia/Tokyo`.

L’export intègre les textures et un nouvel aperçu, utilise DEFLATE via l’archiveur KOReader, puis rouvre le ZIP avec le validateur avant de renommer le fichier temporaire. Il ne remplace pas un fichier déjà présent. L’identifiant de modèle exporté est différent pour permettre sa réimportation. Les réglages RTC globaux ne sont pas exportés avec le cadran.

## Validation et budgets

Le schéma `clock.schema.json` couvre v1/v2. Le validateur d’exécution vérifie en plus les chemins réellement présents, les intersections et les limites de ressources.

- ZIP : au plus 16 Mio compressés, 48 Mio déclarés décompressés, 128 fichiers ; 8 Mio par membre et 128 Kio pour le manifeste.
- Pas de chemin absolu, segment `.`/`..`, lien, fichier spécial, doublon, chiffrement, volume multiple ou ZIP64.
- PNG : au plus 4 mégapixels par image, 12 mégapixels cumulés.
- V2 : 24 blocs par orientation, 6 complications, 3 styles, 16 ressources déclarées.
- JSON : profondeur maximale 24. Noms de fichiers sûrs, identifiants bornés, types de blocs et fournisseurs connus.

Le moteur conserve un fond et une image finale, les tuiles indépendantes et des décors analogiques précomposés. Les éléments stables ne sont pas redessinés. Les buffers sont libérés à la fermeture de la scène. Le nombre exact d’allocations natives et la RAM sur Kobo restent à mesurer.

Ces contrôles garantissent des contraintes de structure et de ressources, pas l’authenticité d’un auteur. Aucun registre distant n’est utilisé.
