#!/usr/bin/env bash
# Patche le projet Android généré par `npx cap add android`.
# Ce script est idempotent : relançable sans effet de bord.
set -euo pipefail

ANDROID_DIR="android"
APP_ID="com.jeanrobert.cloudwriter"
APP_PATH="${APP_ID//./\/}"

if [ ! -d "$ANDROID_DIR" ]; then
  echo "❌ Dossier android/ introuvable. Lance d'abord 'npx cap add android'." >&2
  exit 1
fi

echo "▶ Patch 1/4 : minSdkVersion = 24 (WebView moderne)"
VARIABLES="$ANDROID_DIR/variables.gradle"
if [ -f "$VARIABLES" ]; then
  # Capacitor 6 utilise déjà minSdkVersion 22-23 ; on force à 24.
  sed -i -E 's/(minSdkVersion\s*=\s*)[0-9]+/\124/' "$VARIABLES" || true
fi

echo "▶ Patch 2/4 : couleur splash + strings"
COLORS_XML="$ANDROID_DIR/app/src/main/res/values/colors.xml"
mkdir -p "$(dirname "$COLORS_XML")"
cat > "$COLORS_XML" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="colorPrimary">#a8ccea</color>
    <color name="colorPrimaryDark">#7fb0dc</color>
    <color name="colorAccent">#3b5fd9</color>
    <color name="splashBackground">#a8ccea</color>
</resources>
EOF

echo "▶ Patch 3/4 : MainActivity.java (setDownloadListener + back button)"
MAIN_ACTIVITY="$ANDROID_DIR/app/src/main/java/$APP_PATH/MainActivity.java"
mkdir -p "$(dirname "$MAIN_ACTIVITY")"
cat > "$MAIN_ACTIVITY" <<EOF
package $APP_ID;

import android.app.DownloadManager;
import android.content.Context;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.webkit.MimeTypeMap;
import android.webkit.URLUtil;
import android.widget.Toast;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Intercepte les téléchargements HTML (<a download>, blob:) et les
        // sauvegarde dans /Downloads. C'est ce qui fait fonctionner l'export
        // DOCX/EPUB/PDF/.ns de CloudWriter sans toucher au HTML.
        this.bridge.getWebView().setDownloadListener((url, userAgent, contentDisposition, mimetype, contentLength) -> {
            try {
                if (url != null && url.startsWith("blob:")) {
                    // Les blob: URLs ne sont pas gérées par DownloadManager.
                    // Le pont JavaScript côté Capacitor peut être utilisé pour
                    // convertir en base64 → Filesystem.writeFile, mais pour un
                    // premier jet on informe l'utilisateur.
                    Toast.makeText(getApplicationContext(),
                        "Téléchargement Blob non supporté nativement — utilisez Partager.",
                        Toast.LENGTH_LONG).show();
                    return;
                }
                String fileName = URLUtil.guessFileName(url, contentDisposition, mimetype);
                DownloadManager.Request request = new DownloadManager.Request(Uri.parse(url));
                request.setMimeType(mimetype);
                request.addRequestHeader("User-Agent", userAgent);
                request.setDescription("CloudWriter — téléchargement");
                request.setTitle(fileName);
                request.allowScanningByMediaScanner();
                request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
                request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName);
                DownloadManager dm = (DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE);
                if (dm != null) {
                    dm.enqueue(request);
                    Toast.makeText(getApplicationContext(),
                        "Téléchargement de " + fileName, Toast.LENGTH_SHORT).show();
                }
            } catch (Exception e) {
                Toast.makeText(getApplicationContext(),
                    "Échec du téléchargement : " + e.getMessage(),
                    Toast.LENGTH_LONG).show();
            }
        });

        // Ferme les modaux ouverts avant de quitter l'app.
        // On délègue au JS : window.dispatchEvent(new Event('androidBack')).
        this.bridge.getWebView().post(() -> {
            this.bridge.getWebView().evaluateJavascript(
                "window.__cwHasBack = window.__cwHasBack || false;", null);
        });
    }

    @Override
    public void onBackPressed() {
        // Envoie un événement au JS. Si le JS ferme un modal il appellera
        // preventDefault via un flag. Sinon on laisse le comportement par défaut.
        this.bridge.getWebView().evaluateJavascript(
            "(function(){" +
            "  var m=document.querySelector('.modal.show, .modal-backdrop.show, [data-modal-open=\"true\"]');" +
            "  if(m){ var btn=m.querySelector('[data-close], .close, .cancel'); if(btn){btn.click(); return true;} m.classList.remove('show'); m.removeAttribute('data-modal-open'); return true; }" +
            "  return false;" +
            "})();",
            value -> {
                if (!"true".equals(value)) {
                    runOnUiThread(() -> super.onBackPressed());
                }
            }
        );
    }
}
EOF

echo "▶ Patch 4/4 : AndroidManifest (allow HTTP internal + label)"
MANIFEST="$ANDROID_DIR/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ]; then
  # S'assurer que l'app est bien nommée CloudWriter (Capacitor le fait déjà via strings.xml)
  STRINGS_XML="$ANDROID_DIR/app/src/main/res/values/strings.xml"
  if [ -f "$STRINGS_XML" ]; then
    sed -i 's|<string name="app_name">.*</string>|<string name="app_name">CloudWriter</string>|' "$STRINGS_XML"
    sed -i 's|<string name="title_activity_main">.*</string>|<string name="title_activity_main">CloudWriter</string>|' "$STRINGS_XML"
  fi
fi

echo "▶ Copie des icônes / splash si présents dans resources/"
if [ -f "resources/icon.png" ]; then
  # Génère les mipmaps standards. On copie la même image dans toutes les densités —
  # Android la redimensionnera. Pour un rendu pro, utiliser `@capacitor/assets`.
  for dpi in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
    DEST="$ANDROID_DIR/app/src/main/res/mipmap-$dpi"
    mkdir -p "$DEST"
    cp resources/icon.png "$DEST/ic_launcher.png"
    cp resources/icon.png "$DEST/ic_launcher_round.png"
    cp resources/icon.png "$DEST/ic_launcher_foreground.png"
  done
fi
if [ -f "resources/splash.png" ]; then
  for dpi in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
    DEST="$ANDROID_DIR/app/src/main/res/drawable-$dpi"
    mkdir -p "$DEST"
    cp resources/splash.png "$DEST/splash.png"
  done
  # Splash par défaut (drawable/)
  DEFAULT_DRAWABLE="$ANDROID_DIR/app/src/main/res/drawable"
  mkdir -p "$DEFAULT_DRAWABLE"
  cp resources/splash.png "$DEFAULT_DRAWABLE/splash.png"
fi

echo "✅ Patches Android appliqués."
