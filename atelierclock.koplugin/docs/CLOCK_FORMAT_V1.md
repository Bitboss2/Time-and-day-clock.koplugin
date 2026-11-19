# Format Atelier `.clock` v1

Archive ZIP dont les fichiers sont stockés ou compressés avec DEFLATE. L’extension du fichier est `.clock`. Le plugin effectue une validation de l’enveloppe ZIP avant de confier la décompression à `ffi.archiver` de KOReader.

Entrées minimales : `manifest.json`, un aperçu PNG et les textures PNG désignées par le manifeste. Les entrées de répertoire explicites sont refusées : créer l’archive en ajoutant directement les fichiers avec leurs chemins relatifs. Seuls les fichiers ordinaires sont acceptés ; pas de liens, chiffrement, ZIP64 ou volumes multiples.

Exemple :

```json
{
  "format": "atelier-clock",
  "schema_version": 1,
  "engine_min": "0.1.0",
  "id": "mon-cadran",
  "name": "Mon cadran",
  "author": "Votre nom",
  "license": "CC0-1.0",
  "version": "1.0.0",
  "canvas": {"width": 758, "height": 1024},
  "orientations": ["portrait", "landscape"],
  "preview": "preview.png",
  "assets": {"background": "textures/background.png"},
  "layers": [
    {"id":"background","type":"image","asset":"background","x":0,"y":0,"w":1,"h":1,"z":0},
    {"id":"hour","type":"text","source":"time","x":0.5,"y":0.36,"size":130,"bold":true},
    {"id":"date","type":"text","source":"date","x":0.5,"y":0.58,"size":24},
    {"id":"battery","type":"text","source":"battery","x":0.5,"y":0.86,"size":20}
  ]
}
```

Le schéma lisible par machine est `clock.schema.json`. Le validateur d’exécution ajoute les vérifications de fichiers présents, tailles ZIP et dimensions PNG. Aucun fichier Lua, JavaScript, shell, HTML ni téléchargement externe n’est accepté dans le paquet.

## Calques

| Type | Usage |
|---|---|
| `image` | Texture statique désignée par `asset`. Composée dans le fond une fois. |
| `text` | Texte statique `text` ou valeur dynamique `source`. |
| `hands` | Aiguilles et graduations d’une horloge analogique. |
| `stack` | Heure et minutes superposées. |
| `words` | Heure exprimée en mots français, valeurs numériques en anglais. |
| `dual` | Heure locale et seconde horloge. |
| `progress` | Progression de la journée locale. |
| `rule` | Ligne horizontale. |

Les `x`, `y`, `w`, `h` sont des fractions du viewport, alors que `size` est une taille de référence en pixels ajustée au canevas et aux réglages. `radius` est une fraction de la plus petite dimension. `align` vaut `left`, `center` ou `right`. `grey` est une valeur de 0 à 255, inversée dans le thème sombre. Les noms de police de paquet sont limités à `cfont`, `tfont`, `ffont` ; l’utilisateur peut ensuite choisir ses propres polices.

Sources : `time`, `date`, `battery`, `wifi`, `memory`, `world`, `ampm`, `label`. La source `label` est utilisée pour les textes statiques de décoration. Pour une horloge analogique, indiquer `source: "time"`.

Le réglage utilisateur de taille de l’heure agit comme un pourcentage sur les chiffres de référence. Les paramètres par élément modifient sa police, sa position, son calque et sa visibilité. Les images sont des fonds dans la v1 ; le champ `z` de l’image ne permet pas de les intercaler entre les textes. Les champs `orientations` décrivent les dispositions prévues ; les coordonnées relatives adaptent la scène à l’orientation réelle.

## Limites et intégrité

- Paquet : 16 Mio compressés, 48 Mio déclarés décompressés, 128 fichiers maximum.
- Manifeste : 128 Kio, profondeur JSON 24 maximum, 48 calques.
- Fichier individuel : 8 Mio dans l’archive ; PNG individuel : quatre mégapixels ; total PNG du paquet : douze mégapixels.
- Noms : caractères ASCII alphanumériques, `_`, `-`, `.`, `/` ; pas de segment `.`/`..`, chemin absolu, séparateur inverse, nom dupliqué ou fichier spécial.
- L’index central et les entêtes locaux doivent désigner les mêmes membres, sans régions superposées.

Les contrôles d’intégrité et le cache ne constituent pas une signature d’auteur. Aucun registre en ligne n’est consulté. Le cache des PNG est sur disque ; les scènes gardent deux buffers gris de la taille de leur viewport et décodent les textures du fond à la construction. Les plafonds PNG limitent la RAM potentielle, mais la mémoire native complète n’a pas été mesurée sur Kobo.

## Fabriquer une archive

```python
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

source = Path("mon-cadran")
with ZipFile("mon-cadran.clock", "w", ZIP_DEFLATED) as z:
    for p in sorted(source.rglob("*")):
        if p.is_file():
            z.write(p, p.relative_to(source).as_posix())
```

Importer ensuite le fichier depuis la Galerie. Un identifiant déjà installé est refusé, pour éviter de remplacer silencieusement un cadran existant.
