# Non-régression : fonctions de 0.2.5-beta.9 → 0.3.0

Chaque fonction de l'interface 0.2.5-beta.9 et son emplacement en 0.3.0. ✅ = conservée, ➕ = nouvelle.

## Cadrans

| 0.2.5-beta.9 | 0.3.0 | |
|---|---|---|
| Mes cadrans : un grand aperçu, flèches ‹ › et balayage | Carrousel : glisser, lancer, accrocher, toucher un voisin, balayage | ✅ |
| Parcourir ne change pas le cadran actif | Inchangé (test `test_10`) | ✅ |
| + Ajouter (catalogue des dix modèles et des imports) | Segment **Catalogue** | ✅ |
| Ajouter ce cadran → variante et éditeur | **Ajouter**, ou toucher la carte → onglet Modifier | ✅ |
| Importer .clock (chemin complet) | **Importer** (catalogue) | ✅ |
| Personnaliser | **Modifier**, ou toucher la carte | ✅ |
| Utiliser (sélectionner et enregistrer) | **Utiliser** | ✅ |
| Dupliquer (24 variantes au plus) | Feuille **⋯ → Dupliquer** | ✅ |
| Retirer (confirmation, au moins un cadran) | Feuille **⋯ → Retirer**, puis feuille de confirmation | ✅ |
| Afficher (essai plein écran) | Bouton ▶, ou **⋯ → Afficher en plein écran** (zoom animé) | ✅ |
| Renommer (dans les Options) | Aussi dans **⋯ → Renommer** | ✅ ➕ |
| — | Appui long sur la carte → actions | ➕ |

## Modifier (cadrans v2)

| 0.2.5-beta.9 | 0.3.0 | |
|---|---|---|
| Modes Style, Modules et Options (boutons) | Contrôle segmenté à pastille glissante, et balayage horizontal | ✅ |
| Modules : cadres + sur l'aperçu | Cadres avec pastille « + » | ✅ |
| Sélecteur paginé de complications rendues en direct | Feuille défilante, toutes les complications visibles, cadre volant | ✅ |
| Fuseau de la seconde horloge (bouton en bas du sélecteur) | Bouton **Fuseau : …** dans la feuille | ✅ |
| Style : Plein, Fin, Contour | Pastilles avec spécimen « 12 » | ✅ |
| Apparence : Papier, Encre, Auto | Segments avec icônes soleil, goutte et auto | ✅ |
| Options : Renommer, Exporter .clock | Groupe **Variante** | ✅ |
| Orientation, format horaire, langue, format de date | Groupe **Heure et date** (feuilles de choix) | ✅ |
| Taille de l'interface | Groupe **Lisibilité** (curseur, − et +) | ✅ |
| Le balayage ne déplace jamais une complication | Inchangé (test `test_11`) | ✅ |

## Éditeur libre (imports v1)

| 0.2.5-beta.9 | 0.3.0 | |
|---|---|---|
| Aperçu interactif, glisser un élément | Inchangé, glissé suivi en direct | ✅ |
| Choisir l'élément (6 éléments) | Feuille **Élément à modifier** | ✅ |
| Sections Disposition, Typographie, Habillage, Informations, Images, Lisibilité | Six tuiles, puis liste défilante avec bouton Retour | ✅ |
| Tous les réglages de ces sections (`ui/controls.lua`) | Mêmes clés : interrupteurs, curseurs, choix et textes | ✅ |
| Afficher | Bouton **Afficher** (zoom) | ✅ |

## Veille

| 0.2.5-beta.9 | 0.3.0 | |
|---|---|---|
| Horloge sur l'écran de veille (activer et rétablir l'écran précédent) | Carte principale avec interrupteur | ✅ |
| Fréquence : 1 min, 5 min, 15 min, Statique | Contrôle segmenté, précision affichée dessous | ✅ |
| Réveil prioritaire Aura 2 (refusé hors modèle) | Carte **Réveil** | ✅ |
| Optimiser Aura 2 | **Optimiser pour Aura 2** | ✅ |
| Autres réglages : marge, réutilisation, nettoyage, seuil batterie, pause nocturne, début et fin | **Réglages avancés** dans la même liste | ✅ |
| — | Capacité RTC du modèle (Kobo, Kindle via powerd, indisponible) | ➕ |

## Diagnostic

| 0.2.5-beta.9 | 0.3.0 | |
|---|---|---|
| Jauge de batterie, état de l'horloge, avis | Carte principale | ✅ |
| Mises à jour, rattrapages | Tuiles à compteurs animés | ✅ |
| Prochaine actualisation | Carte | ✅ |
| Détails techniques (liste paginée) | Dépliés dans la liste défilante, avec en plus les lignes moteur et RTC | ✅ ➕ |
| Exporter le diagnostic | **Outils → Exporter le diagnostic** | ✅ |
| Importer / exporter un profil (JSON ou ancien Lua) | **Outils → Profil** | ✅ |
| — | Section **Affichage** : moteur, profil, cadences, réglages, nettoyer, réessayer | ➕ |

## Général

| 0.2.5-beta.9 | 0.3.0 | |
|---|---|---|
| Brouillon, Annuler, Appliquer | Barre **Brouillon** affichée quand il y a des modifications | ✅ |
| Fermer en abandonnant un brouillon (confirmation) | Feuille **Abandonner le brouillon ?** | ✅ |
| Ligne d'état | Notifications brèves | ✅ |
| Onglets Cadrans, Modifier, Veille, Diagnostic | Barre à pastille glissante, transitions latérales | ✅ |
| Touche Retour | Ferme la feuille, puis la sous-vue, puis l'atelier | ✅ |
| Interface adaptée au DPI, en paysage, taille réglable | Inchangé (tests sur 5 tailles et densités) | ✅ |
| Horloge manuelle : un toucher ferme, un appui long ouvre l'atelier | Inchangé | ✅ |
| Option **Horloge Atelier** du menu de veille KOReader | Inchangé | ✅ |
| Actions Dispatcher *atelier* et *afficher* | Inchangé | ✅ |
