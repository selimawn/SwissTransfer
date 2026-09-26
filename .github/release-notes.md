Client macOS.

Après avoir déplacé `SwissTransfer.app` dans Applications :

```sh
xattr -dr com.apple.quarantine /Applications/SwissTransfer.app
```

Si l'app est dans le dossier personnel, remplace le chemin par `~/Applications/SwissTransfer.app`.
