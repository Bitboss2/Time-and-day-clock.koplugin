# Réutiliser le moteur InkMotion

Le moteur natif est distinct du contenu de démonstration. `native/inkmotion.h` et `inkmotion.koplugin/native.lua` exposent un producteur d’images en niveaux de gris, une boîte aux lettres à trois emplacements et un worker d’affichage. Ils peuvent servir de base à une autre interface ou à un émulateur ; aucun émulateur Game Boy ni moteur HTML n’est livré en 5.1.

## Contrat actuel

- Le producteur compose une image 8 bits en niveaux de gris. `im_publish` copie le dernier rendu complet ; le tramage, le masque électrique et les budgets restent dans le worker. Une publication refusée ou remplacée n’est pas une image optiquement présentée.
- Le worker s’exécute dans un processus enfant du créateur. Le contexte partagé est créé avant le fork. `im_run` est bloquant côté worker ; le producteur continue les entrées et le rendu. Ne pas supposer qu’une configuration arbitraire de threads et de fork est compatible.
- Le backend KOReader configure les dimensions, le framebuffer, le transport spécifique à la plateforme et son marqueur initial. Le chemin personnalisé exige actuellement cette géométrie 758×1024, BB8 sans rotation/inversion, ce noyau reconnu et une identité intégrale de la waveform résidente. Les profils constructeur supplémentaires sont listés dans `PORTAGE_FR.md`.
- Un seul composant doit posséder les écritures/rafraîchissements pendant la session. Un autre moteur graphique ne doit pas lancer ses propres ioctl simultanément. À la veille et à la fermeture, attendre l’arrêt du worker et la restauration confirmée avant de rendre le framebuffer à l’application.
- Les noms de conduites sont des réglages de cette expérimentation, pas encore une API standard stable. L’ABI 6500 contrôle le chargement de la bonne bibliothèque et la taille des statistiques.

## Interface défilante

Le rendu de document ou des widgets alimente l’image source ; les gestes et l’inertie restent du côté de l’interface. Les polices, images et animations sont alors tramées ensemble. Le moteur conserve le dernier rendu disponible au lieu d’accumuler une file d’anciennes positions. La finesse du tramage et le coût du rendu de page doivent être mesurés avec le backend, sur le CPU partagé de cette Kobo.

## Émulateur Game Boy

L’émulation et l’affichage doivent avoir leurs cadences séparées. Le moteur peut échantillonner la dernière image terminée à une cible de 30 ou 60 publications/s pendant que l’émulateur traite ses pas de temps et ses entrées. Cela ne signifie pas qu’il faut ralentir la logique du jeu à 30 images/s. Un adaptateur fournit une image en niveaux de gris, choisit une mise à l’échelle et gère les commandes tactiles ou une manette disponible.

Un petit contenu pourrait réduire le coût du rendu et de la conversion à la source, mais la version 5.0 peut ignorer les bandes de calcul au repos, et la requête A2 couvre encore l’écran. Elle n’est pas un backend d’actualisations uniquement dans le rectangle du jeu. La cadence d’émulation, le son et la fluidité optique restent à mesurer sur le cœur Cortex-A9 de la Kobo. Une performance obtenue sur le SSD1681 d’InkBoy ne prouve pas celle de cette machine.

## Pour en faire un standard réutilisable

Il faudra séparer une interface de présentation stable du backend matériel, définir explicitement propriété du framebuffer, succès de soumission, fin de scan, abandon d’image, veille et restauration, puis ajouter des backends validés appareil par appareil. La calibration du noir, du blanc, de la température et des traces doit accompagner les profils. Le protocole de mesure doit distinguer débit logiciel et réponse optique.

Le travail actuel fournit un prototype de moteur réutilisable, des comparateurs et des régressions. Il ne constitue pas encore un standard multi-liseuses ni une garantie de 30 images contrastées/s sur n’importe quelle scène.
