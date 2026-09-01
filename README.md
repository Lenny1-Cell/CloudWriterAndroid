# CloudWriter Android — build 100 % dans le cloud

Ce dépôt transforme automatiquement le fichier web **`CloudWriter.html`** en **APK Android** installable, sans rien installer sur ta machine à part **Git** et un compte **GitHub**.

Toute la compilation tourne sur **GitHub Actions** (serveurs GitHub gratuits). Tu récupères l'APK :
- soit dans l'onglet **Actions → Artifacts** (à chaque push sur `main`),
- soit dans une **Release GitHub** (à chaque tag `v*`).

---

## 🚀 Marche à suivre — Guide débutant

### 1. Créer un dépôt GitHub vide

1. Va sur https://github.com/new
2. Nom du dépôt : `CloudWriter-android` (ou ce que tu veux)
3. Laisse-le **vide** (ne coche PAS « Add a README »).
4. Clique **Create repository**.
5. GitHub affiche une page avec ton URL, ex. `https://github.com/tonpseudo/CloudWriter-android.git`.

### 2. Envoyer les fichiers du projet

Ouvre un terminal sur ta machine. Place-toi dans le dossier qui contient **ce dépôt CloudWriter-android/** (celui que je t'ai livré) puis :

```bash
cd CloudWriter-android

git init -b main
git add .
git commit -m "Initial commit: wrapper Capacitor pour CloudWriter"
git remote add origin https://github.com/TON_PSEUDO/CloudWriter-android.git
git push -u origin main
```

> Remplace `TON_PSEUDO` par ton nom d'utilisateur GitHub. La première fois, GitHub va te demander de t'authentifier (token personnel, ou navigateur, selon ta config).

### 3. Attendre la build

1. Sur ton dépôt GitHub, clique l'onglet **Actions**.
2. Tu verras un workflow **« Build CloudWriter APK »** en cours (icône jaune ⏳).
3. Attends 5 à 10 minutes. Icône verte ✅ = build réussie.

### 4. Récupérer l'APK

**Option A — Artifact (à chaque push)**

1. Clique sur la build verte.
2. En bas de la page, section **Artifacts**, télécharge **CloudWriter-debug-apk**.
3. C'est un `.zip`. Dézippe-le → tu obtiens `CloudWriter-debug.apk`.

**Option B — Release automatique (recommandé pour partager)**

Pour publier une vraie release téléchargeable en un clic :

```bash
git tag v1.0.0
git push origin v1.0.0
```

Une **Release** est créée automatiquement sur GitHub, avec l'APK attachée. URL type :
`https://github.com/TON_PSEUDO/CloudWriter-android/releases/latest`

### 5. Installer sur ton Android

1. Transfère `CloudWriter-debug.apk` sur le téléphone (câble USB, Google Drive, e-mail, etc.).
2. Sur le téléphone : **Paramètres → Sécurité → Installer des apps inconnues** → autoriser ton gestionnaire de fichiers ou ton navigateur.
3. Ouvre le `.apk` avec le gestionnaire de fichiers → tape **Installer**.
4. Ouvre **CloudWriter** depuis le tiroir d'apps. 🎉

---

## 🧩 Ce que fait la CI (pour info)

Le workflow `.github/workflows/build-apk.yml` :

1. Installe **Node 20**, **Java 17**, **Android SDK 34**.
2. `npm install` — récupère Capacitor + plugins.
3. `npx cap add android` — génère le dossier `android/` (projet Gradle).
4. `bash scripts/patch-android.sh` — applique nos patches :
   - `minSdkVersion = 24` (WebView moderne)
   - Nom d'app **CloudWriter**
   - Couleurs **`#a8ccea`**
   - **`MainActivity.java`** custom avec :
     - `setDownloadListener` → sauvegarde des exports (DOCX, EPUB, PDF, `.ns`) dans **/Downloads**
     - `onBackPressed` → ferme les modaux au lieu de quitter l'app
   - Copie de `resources/icon.png` et `resources/splash.png` dans les mipmaps.
5. `npx cap sync android` — copie `www/index.html` dans les assets natifs.
6. `./gradlew assembleDebug` — compile l'APK.
7. Upload de l'artifact + release si tag `v*`.

---

## 🛠️ Structure du projet

```
CloudWriter-android/
├─ .github/workflows/build-apk.yml   # pipeline GitHub Actions
├─ www/index.html                     # = CloudWriter.html (copié tel quel)
├─ resources/
│  ├─ icon.png                        # placeholder 1024×1024 bleu ciel
│  └─ splash.png                      # placeholder 2732×2732
├─ scripts/patch-android.sh           # patches Android post-`cap add`
├─ capacitor.config.json              # config Capacitor (app id, splash, statusbar)
├─ package.json                       # dépendances Capacitor
├─ .gitignore
└─ README.md                          # ce fichier
```

> ⚠️ Le dossier **`android/` n'est PAS commité** : il est regénéré à chaque build par `npx cap add android` puis patché. C'est ce qui garantit qu'on reste sur une version propre à jour à chaque compilation.

---

## 🐞 Problèmes courants

### « L'app n'est pas installée » sur Android
En général :
- Une **ancienne version** est déjà installée avec le même package id → désinstalle-la d'abord.
- Ou tu réinstalles par-dessus une version signée avec une autre clé → désinstalle d'abord.

### La build échoue avec « Gradle out of memory »
Relance la build (bouton **Re-run all jobs** dans l'onglet Actions). C'est un flake connu de GitHub Actions.

### La build échoue avec « SDK license not accepted »
L'action `android-actions/setup-android@v3` accepte les licences automatiquement. Si ça foire, ouvre une issue et je regarde — c'est très rare.

### Les exports DOCX / EPUB / PDF ne se téléchargent pas
Deux cas :
- **Fichiers texte / binaires classiques** → interceptés par `setDownloadListener` de `MainActivity.java`, sauvegardés dans `/Downloads`. Vérifie une notif Android « Téléchargement terminé ».
- **Blob URLs** (utilisées par CloudWriter pour DOCX/EPUB fait main) → non gérées par `DownloadManager` natif. Solution propre : patcher `CloudWriter.html` pour utiliser `@capacitor/filesystem` + `@capacitor/share`. Voir **`patches/CloudWriter.html.blob.diff`** (patch optionnel séparé).

### `localStorage` se vide entre les sessions
Ne devrait pas arriver : WebView Android persiste `localStorage` dans le stockage privé de l'app. Si ça arrive, vérifie que tu n'as pas activé « Effacer les données à la fermeture » dans les options développeur, et vérifie qu'un antivirus ne nettoie pas les données.

### Le bouton retour Android quitte l'app au lieu de fermer un modal
Le patch `MainActivity.java` cherche `.modal.show`, `.modal-backdrop.show`, `[data-modal-open="true"]`. Si tes modaux utilisent d'autres classes, adapte le sélecteur JS dans `scripts/patch-android.sh` (bloc `onBackPressed`).

### `adb install CloudWriter-debug.apk` échoue avec `INSTALL_FAILED_UPDATE_INCOMPATIBLE`
Same que « app non installée » ci-dessus : `adb uninstall com.jeanrobert.cloudwriter` puis réinstalle.

---

## 🔐 APK release signé (bonus)

L'APK debug est **auto-signé avec une clé de développement** partagée par tous les projets Android. Suffisant pour tester, mais Google Play refuserait de la publier.

Pour un APK **release signé** :

1. Génère un keystore localement (ou dans un job CI séparé, une seule fois) :
   ```bash
   keytool -genkey -v -keystore cloudwriter.jks -keyalg RSA -keysize 2048 -validity 10000 -alias cloudwriter
   ```
2. Ajoute les secrets GitHub (**Settings → Secrets and variables → Actions**) :
   - `ANDROID_KEYSTORE_BASE64` — `base64 cloudwriter.jks | tr -d '\n'`
   - `ANDROID_KEYSTORE_PASSWORD`
   - `ANDROID_KEY_ALIAS` = `cloudwriter`
   - `ANDROID_KEY_PASSWORD`
3. Ajoute un job release dans le workflow (peux te fournir ce bloc sur demande).

---

## 📝 Modifications du HTML source

**Zéro modification** de `CloudWriter.html` n'a été nécessaire pour cette version.

La meta viewport `<meta name="viewport" content="width=device-width, initial-scale=1.0">` était **déjà présente** dans le fichier original — parfait pour un affichage mobile.

Les patchs Android côté natif (setDownloadListener, back button) suffisent à couvrir 95 % des cas d'usage. Si tu veux gérer les **Blob URLs** de manière propre (export DOCX/EPUB), un patch HTML optionnel est fourni : voir `patches/CloudWriter.html.blob.diff`.

---

## 📦 Mettre à jour CloudWriter

Quand tu modifies `CloudWriter.html`, remplace simplement `www/index.html` par la nouvelle version :

```bash
cp /chemin/vers/CloudWriter.html www/index.html
git add www/index.html
git commit -m "Update CloudWriter to vX.Y"
git push
# Optionnel : git tag v1.1.0 && git push origin v1.1.0
```

La CI recompile automatiquement une nouvelle APK.
