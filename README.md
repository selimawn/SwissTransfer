# SwissTransfer

Client macOS natif pour envoyer des fichiers avec [SwissTransfer](https://www.swisstransfer.com). Ce n’est pas une application Infomaniak.

Au premier lancement, SwissTransfer confirme l’adresse e-mail avec un code à 6 caractères. Aucun compte n’est nécessaire, et aucun compte n’est créé.

## Installer

1. Ouvre la [dernière release](https://github.com/selimawn/SwissTransfer/releases/latest).
2. Télécharge `SwissTransfer.zip`.
3. Décompresse l’archive.
4. Déplace `SwissTransfer.app` dans `/Applications`, ou dans `~/Applications` si tu n’as pas les droits d’écriture.

macOS marque les apps téléchargées et refuse souvent de les ouvrir (« endommagée » ou bloquée par Gatekeeper). Enlève cet attribut :

```sh
xattr -dr com.apple.quarantine /Applications/SwissTransfer.app
```

Si tu l’as mise dans ton dossier personnel :

```sh
xattr -dr com.apple.quarantine ~/Applications/SwissTransfer.app
```

Ouvre ensuite SwissTransfer. Dans le Finder, un clic droit sur un fichier puis **Ouvrir avec → SwissTransfer** l’ajoute au transfert.

## Compiler

```sh
./scripts/build-app.sh
```

Le script installe l’app dans `~/Applications`. Une release GitHub est publiée à chaque tag `v*`.
