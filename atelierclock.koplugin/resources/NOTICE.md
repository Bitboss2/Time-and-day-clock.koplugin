# Ressources et dépendances

Le code, les compositions et les textures de ce projet ont été écrits indépendamment. Aucun module ni cadran de Time & Day Clock/dtdisplay n’est incorporé.

Le plugin utilise les bibliothèques de l’installation KOReader ; elles ne sont pas redistribuées dans le ZIP installable. Les fichiers officiels employés par les tests de développement sont téléchargés séparément et restent sous leurs licences propres : https://github.com/koreader/koreader et https://github.com/koreader/koreader-base .

Les textures géométriques et manifestes `.clock` originaux sont placés sous CC0-1.0. Les aperçus ont été produits par le moteur Lua du plugin avec un framebuffer de test Pillow et la police DejaVu Sans. La police elle-même n’est pas embarquée ; le rendu sur KOReader utilise les polices qui y sont installées. Licence DejaVu et mentions des aperçus : `DEJAVU-LICENSE.txt`.

Les tables horaires dérivent des données IANA installées sur le système de construction, identifiées par le champ `source` de `timezones.json`. Les données de fuseau IANA sont dans le domaine public ; le code de génération de ce projet est sous MIT. Aucune connexion n’est requise pour les lire à l’exécution.
