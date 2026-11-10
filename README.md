# ¿Dónde la veo?

App Android (Flutter) que busca una película o serie y te dice en qué plataformas y en qué países está disponible.
Por ejemplo: «Netflix, en 17 países», con la lista de países.

Datos: JustWatch, a través de la API de TMDB. Gratis para uso no comercial: la app no lleva anuncios ni es de pago.

## Cómo se compila (sin instalar nada)

GitHub compila la app solo cada vez que subes cambios a `main` (`.github/workflows/compilar.yml`).
Al terminar, en la pestaña **Actions** → la última ejecución → **Artifacts** tienes:

- `apk-para-probar` → descomprímelo e instala el `.apk` en tu móvil para probarla.
- `aab-para-play-store` → el `.aab` es lo que se sube a Play Console.

### Secretos necesarios (Settings → Secrets and variables → Actions)

| Nombre | Valor |
|---|---|
| `TMDB_KEY` | Tu clave de TMDB (themoviedb.org → Ajustes → API) |
| `KEY_ALIAS` | `upload` |
| `KEYSTORE_PASSWORD` | La contraseña de tu clave de firma |
| `KEYSTORE_BASE64` | El archivo `upload-keystore.jks` en base64 |

La clave de TMDB nunca se guarda en el código: se mete al compilar.

## Publicar en Google Play

1. **Cuenta de desarrollador** en play.google.com/console (pago único de 25 $ y verificación de identidad).
2. **Crear la app** → nombre «¿Dónde la veo?», gratis, app.
3. **Ficha de Play Store:** icono 512×512 (`icono-play-512.png`), capturas del móvil, descripción corta y larga.
4. **Política de privacidad:** la URL pública de `PRIVACY.md` de este repositorio.
5. **Formularios de la app:** seguridad de los datos (no recoge datos), clasificación de contenido, público objetivo (mayores de 13 años), sin anuncios.
6. **Firma de apps de Google Play:** déjala activada (opción por defecto). Tu `upload-keystore.jks` es la «clave de subida».
7. **Prueba cerrada obligatoria** (cuentas personales nuevas): sube el `.aab`, invita a **12 testers como mínimo** y mantenlos apuntados **14 días seguidos**. Conviene invitar a 15 o más, por si alguno se borra.
8. **Solicitar acceso a producción** en Play Console, contestando el cuestionario sobre la prueba, y después publicar.

Cada subida a Play necesita un número de versión nuevo: el workflow lo incrementa solo en cada compilación.
Para cambiar la versión visible (1.0.0 → 1.1.0), edita `version:` en `pubspec.yaml`.

## Atribución

Los créditos a TMDB y JustWatch están en la pantalla «Acerca de», como exigen sus condiciones.
TMDB pide además mostrar su logotipo oficial en esa pantalla: descárgalo de themoviedb.org/about/logos-attribution y añádelo antes de publicar.
