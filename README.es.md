<div align="center">

<img src="docs/logo.png" width="96" alt="Logo de OptiEleven">

# OptiEleven

**Optimizador reversible de Windows 11 para jugar.**
Quita telemetría y basura, libera RAM antes de jugar y deshaz cualquier cambio con un clic.

[![Licencia: MIT](https://img.shields.io/badge/licencia-MIT-fc6b33)](LICENSE)
![Windows 11](https://img.shields.io/badge/Windows-11-14110f)
![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-14110f)
![Sin instalación](https://img.shields.io/badge/instalaci%C3%B3n-ninguna-14110f)

**Ábrelo con un comando.** Pega esto en PowerShell:

```powershell
irm https://raw.githubusercontent.com/bilal1122c/OptiEleven/main/run.ps1 | iex
```

o [⬇ descarga OptiEleven.zip](https://github.com/bilal1122c/OptiEleven/releases/latest/download/OptiEleven.zip), descomprímelo y haz doble clic en `OptiEleven.cmd`. No hay nada que compilar ni instalar.

[English](README.md) · Español

<img src="docs/screenshots/settings-dark.png" alt="Página de ajustes de OptiEleven con la vista previa de cambios y la hoja de cambios">

</div>

## Por qué OptiEleven

La mayoría de scripts de "debloat" son un montón de cambios en el registro que ejecutas una vez y cruzas los dedos. OptiEleven funciona al revés:

- **Ves antes de aplicar.** Cada ajuste muestra qué valores del registro, servicios y tareas programadas toca, con el valor actual y el que quedará.
- **Todo se puede revertir.** La primera vez que se aplica un ajuste se guarda el estado original. *Revertir* lo devuelve, aunque sea meses después.
- **No pasa nada hasta que pulsas Aplicar.** Los interruptores se apuntan en una hoja de cambios; la revisas, puedes crear un punto de restauración y se aplican juntos.
- **Sin instalación ni telemetría propia.** Es PowerShell + WPF. Lee el código, ejecútalo y borra la carpeta cuando quieras.

## Funciones

| | |
|---|---|
| **60 ajustes en 8 categorías** | Privacidad, Servicios, Rendimiento, Latencia, Juegos, Windows Update, Interfaz y Apps. Dos presets: *Recomendado* (seguro, quita casi todo lo que no sirve) y *Avanzado* (más agresivo, lee las notas). |
| **Boost FPS** | Un clic antes de jugar: cierra apps en segundo plano, pausa servicios, pone la energía al máximo, libera RAM y hace la limpieza completa. *Terminar y restaurar* lo devuelve todo. |
| **Game Booster** | Elige qué apps se cierran y qué servicios se pausan mientras juegas. |
| **Mis juegos** | Encuentra tus juegos de Steam, Epic y GOG y les pone GPU de alto rendimiento, prioridad alta o quita las optimizaciones de pantalla completa. |
| **Instalar apps** | Launchers, Discord, OBS, monitorización y librerías para juegos con winget, y actualizar todo. |
| **Inicio** | Lo que arranca con Windows, y apagarlo. |
| **Limpieza** | Temporales, restos de actualizaciones, volcados, caché de sombreadores, miniaturas y papelera. Primero ves cuánto ocupa cada cosa. |
| **Red** | Latencia al router y a Cloudflare, Google y Quad9, y cambiar de DNS con un clic. |
| **Reparar** | DISM + SFC, comprobar disco, restablecer red, Windows Update y la Store, caché de iconos e informe de batería. |
| **Equipo** | CPU, GPU, velocidad de la RAM, discos, arranque seguro, TPM, VBS y HAGS, con un informe para copiar. |
| **Perfiles** | Exporta tus ajustes a un `.json` e impórtalos en otro PC, o aplícalos por línea de comandos. |
| **Idiomas** | Inglés y español. Añadir otro idioma es un archivo JSON ([cómo](CONTRIBUTING.md#translations)). |
| **Temas** | Oscuro (por defecto) y claro. |

## Empezar

1. Clic derecho en el botón Inicio → **Terminal**, pega este comando y pulsa Intro. Acepta el permiso de administrador.

   ```powershell
   irm https://raw.githubusercontent.com/bilal1122c/OptiEleven/main/run.ps1 | iex
   ```

   Descarga la última versión en `%LOCALAPPDATA%\OptiEleven`, y si lo vuelves a ejecutar la actualiza. Puedes [leer el script](run.ps1) antes; es corto.

   ¿Prefieres un archivo? **[Descarga OptiEleven.zip](https://github.com/bilal1122c/OptiEleven/releases/latest/download/OptiEleven.zip)**, descomprímelo donde quieras y haz doble clic en **`OptiEleven.cmd`**.
2. El panel se abre como administrador.
3. Lee el aviso del inicio, ve a **Sistema → Punto de restauración**, elige el preset **Recomendado**, revisa la hoja de cambios y pulsa **Aplicar cambios**.
4. Reinicia si el panel te lo pide.

Sin permisos de administrador el panel se abre en modo solo lectura, para que puedas mirarlo todo antes.

El idioma se cambia con el botón **EN / ES** de arriba a la izquierda.

## ¿Es seguro?

OptiEleven cambia ajustes del sistema, así que lee lo que hace cada uno antes de aplicarlo. Está pensado para que no te metas en líos:

- Las copias del estado original están en `%ProgramData%\OptiEleven\secure`, una carpeta que solo pueden escribir los administradores.
- Antes de cada aplicación te ofrece crear un punto de restauración.
- Lo que no se puede deshacer desde el panel (por ejemplo desinstalar Edge u OneDrive) va marcado como **Sin vuelta atrás** y se repite en la confirmación.
- Los ajustes con riesgo van marcados como *Moderado* o *Avanzado* y dicen qué deja de funcionar.

Si algo falla, abre un [issue](../../issues) con el registro de **Actividad** (Sistema → Copias de seguridad abre la carpeta con `panel.log`).

## Instalación limpia de Windows (opcional)

Hay una [guía de NTLite](docs/ntlite-guide.es.md) paso a paso para hacer una ISO de Windows 11 Pro ligera que sigue recibiendo actualizaciones; después OptiEleven hace la parte reversible.

## Contribuir

Se agradecen informes de errores, ajustes nuevos y traducciones. Mira [CONTRIBUTING.md](CONTRIBUTING.md).

Si OptiEleven te ha servido, una ⭐ ayuda a que lo encuentre más gente.

## Licencia

[MIT](LICENSE). OptiEleven no tiene relación con Microsoft.
