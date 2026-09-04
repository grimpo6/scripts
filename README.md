# Scripts

Collection de script pour Grimpo6.

## Mise en place

Copier `.env.template` ver `.env` et générer les identifiants pour HelloAsso et OVH.
Télécharger la liste des adhérents au format csv depuis HelloAsso, puis placer le sous le nom `membres.csv` dans le dossier courant.

## `download_documents.sh`

Permet de télécharger les attestations et certificats médicaux dans le dossier `output`.

## `generate_mailing_list.sh`

Permet de générer des fichiers au formats csv qui peuvent être importés dans l'interface de gestion d'OVH.

## `sync_list.sh`

Permet de synchroniser les listes mail avec les fichiers générés par `generate_mailing_list.sh`.