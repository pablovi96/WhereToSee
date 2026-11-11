#!/usr/bin/env python3
"""Ajusta la carpeta android/ que genera `flutter create`:
- permiso de Internet y nombre visible de la app en el manifiesto,
- permiso para abrir enlaces web (JustWatch),
- firma de publicación leyendo android/key.properties si existe.
Falla en voz alta si la plantilla de Flutter cambia y no encuentra lo que busca.
"""
import re
import sys
from pathlib import Path

APP_LABEL = "Where to See"
ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
APP = ROOT / "android" / "app"


def fail(msg):
    print(f"::error::patch_android: {msg}")
    sys.exit(1)


# ---------------------------------------------------------------- manifiesto
manifest = APP / "src" / "main" / "AndroidManifest.xml"
if not manifest.exists():
    fail(f"no existe {manifest}")
m = manifest.read_text(encoding="utf-8")

if "android.permission.INTERNET" not in m:
    m, n = re.subn(r"(<manifest\b[^>]*>)",
                   r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>', m, count=1)
    if n != 1:
        fail("no encuentro la etiqueta <manifest>")

m, n = re.subn(r'android:label="[^"]*"', f'android:label="{APP_LABEL}"', m, count=1)
if n != 1:
    fail("no encuentro android:label")

view_intent = ('        <intent>\n'
               '            <action android:name="android.intent.action.VIEW"/>\n'
               '            <data android:scheme="https"/>\n'
               '        </intent>\n')
if 'android:scheme="https"' not in m:
    if "<queries>" in m:
        m = m.replace("<queries>\n", "<queries>\n" + view_intent, 1)
    else:
        m = m.replace("</manifest>", "    <queries>\n" + view_intent + "    </queries>\n</manifest>", 1)
manifest.write_text(m, encoding="utf-8")
print("Manifiesto ajustado")

# ---------------------------------------------------------------- identificador
APP_ID = "com.WhereToSee"  # registrado así en Play Console; no cambiar nunca
for gradle_file in (APP / "build.gradle.kts", APP / "build.gradle"):
    if gradle_file.exists():
        t = gradle_file.read_text(encoding="utf-8")
        t, n = re.subn(r'applicationId\s*=\s*"[^"]*"', f'applicationId = "{APP_ID}"', t, count=1)
        if n != 1:
            fail(f"no encuentro applicationId en {gradle_file.name}")
        gradle_file.write_text(t, encoding="utf-8")
        print(f"applicationId = {APP_ID}")

# ---------------------------------------------------------------- firma
kts = APP / "build.gradle.kts"
groovy = APP / "build.gradle"

if kts.exists():
    g = kts.read_text(encoding="utf-8")
    if "keystoreProperties" not in g:
        g = "import java.io.FileInputStream\nimport java.util.Properties\n\n" + g
        g, n = re.subn(r"^android \{", (
            'val keystoreProperties = Properties()\n'
            'val keystorePropertiesFile = rootProject.file("key.properties")\n'
            'if (keystorePropertiesFile.exists()) {\n'
            '    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n'
            '}\n\n'
            'android {'), g, count=1, flags=re.M)
        if n != 1:
            fail("no encuentro 'android {' en build.gradle.kts")
        g, n = re.subn(r"^([ \t]*)buildTypes \{", lambda mm: (
            f'{mm.group(1)}signingConfigs {{\n'
            f'{mm.group(1)}    create("release") {{\n'
            f'{mm.group(1)}        keyAlias = keystoreProperties["keyAlias"] as String?\n'
            f'{mm.group(1)}        keyPassword = keystoreProperties["keyPassword"] as String?\n'
            f'{mm.group(1)}        storeFile = keystoreProperties["storeFile"]?.let {{ file(it) }}\n'
            f'{mm.group(1)}        storePassword = keystoreProperties["storePassword"] as String?\n'
            f'{mm.group(1)}    }}\n'
            f'{mm.group(1)}}}\n\n'
            f'{mm.group(1)}buildTypes {{'), g, count=1, flags=re.M)
        if n != 1:
            fail("no encuentro 'buildTypes {' en build.gradle.kts")
        g, n = re.subn(r'signingConfig = signingConfigs\.getByName\("debug"\)',
                       'signingConfig = if (keystorePropertiesFile.exists()) '
                       'signingConfigs.getByName("release") else signingConfigs.getByName("debug")', g, count=1)
        if n != 1:
            fail("no encuentro la firma debug en build.gradle.kts")
    kts.write_text(g, encoding="utf-8")
    print("build.gradle.kts ajustado")
elif groovy.exists():
    g = groovy.read_text(encoding="utf-8")
    if "keystoreProperties" not in g:
        g, n = re.subn(r"^android \{", (
            'def keystoreProperties = new Properties()\n'
            'def keystorePropertiesFile = rootProject.file("key.properties")\n'
            'if (keystorePropertiesFile.exists()) {\n'
            '    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n'
            '}\n\n'
            'android {'), g, count=1, flags=re.M)
        if n != 1:
            fail("no encuentro 'android {' en build.gradle")
        g, n = re.subn(r"^([ \t]*)buildTypes \{", lambda mm: (
            f'{mm.group(1)}signingConfigs {{\n'
            f'{mm.group(1)}    release {{\n'
            f'{mm.group(1)}        keyAlias = keystoreProperties["keyAlias"]\n'
            f'{mm.group(1)}        keyPassword = keystoreProperties["keyPassword"]\n'
            f'{mm.group(1)}        storeFile = keystoreProperties["storeFile"] ? file(keystoreProperties["storeFile"]) : null\n'
            f'{mm.group(1)}        storePassword = keystoreProperties["storePassword"]\n'
            f'{mm.group(1)}    }}\n'
            f'{mm.group(1)}}}\n\n'
            f'{mm.group(1)}buildTypes {{'), g, count=1, flags=re.M)
        if n != 1:
            fail("no encuentro 'buildTypes {' en build.gradle")
        g, n = re.subn(r"signingConfig = signingConfigs\.debug",
                       "signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug",
                       g, count=1)
        if n != 1:
            fail("no encuentro la firma debug en build.gradle")
    groovy.write_text(g, encoding="utf-8")
    print("build.gradle ajustado")
else:
    fail("no encuentro android/app/build.gradle(.kts)")
