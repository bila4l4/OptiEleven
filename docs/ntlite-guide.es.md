# Guía NTLite: Windows 11 limpio para jugar

Objetivo: una ISO de Windows 11 **Pro** sin basura, que se instale sola (cuenta local, sin pantallas de privacidad) y que **siga recibiendo actualizaciones**. Las optimizaciones finas (servicios, tweaks de juego) NO van en la ISO: las aplica el **OptiEleven** después, porque así se pueden revertir.

Necesitas [NTLite](https://www.ntlite.com) y una ISO oficial de Windows 11 ([descarga de Microsoft](https://www.microsoft.com/software-download/windows11)). Suele traer `install.esd` con varias ediciones.

> ⚠️ Esto termina en un formateo. Haz copia de tus datos antes y apunta tu clave/licencia (si es digital, se reactiva sola).

---

## 0. Antes de empezar: exporta tus drivers

En PowerShell **como administrador** (así la instalación nueva tendrá Wi‑Fi, touchpad y chipset desde el primer minuto):

```powershell
dism /online /export-driver /destination:C:\DriversBackup
```

## 1. Cargar la imagen

1. NTLite → **Add → Image file (ISO)** → elige `Windows.iso`. Te pedirá una carpeta para extraerla, por ejemplo `C:\NTLite\Win11`.
2. Verás varias ediciones. **Borra todas menos Windows 11 Pro** (clic derecho → Delete). Así la ISO pesa menos y la instalación no pregunta.
3. Clic derecho en *Pro* → **Convert → WIM** (el ESD no se puede editar bien) y luego **Load**.
4. Mira la versión (por ejemplo 24H2 o 25H2). Debe ser una versión **estable**, no Insider.

## 2. Components: qué quitar

Primero pulsa **Compatibility** (arriba en la página Components) y marca lo que quieres proteger. Así NTLite bloquea lo que rompería algo:

- ✅ **Windows Update**: protégelo siempre.
- ✅ **Microsoft Store / App Installer**: hacen falta para winget, Game Pass y los drivers de AMD de la Store.
- ✅ **Xbox**: protégelo si usas Game Pass o la app Xbox.
- ✅ **Wi‑Fi, Bluetooth, Audio, Camera**: mantenlos si los usas (en un portátil, siempre).
- ✅ **Windows Hello**: si usas cara o PIN.

Después quita esto (todo es seguro para jugar):

| Categoría | Quitar |
|---|---|
| Apps preinstaladas | Clipchamp, Bing News/Weather/Search, Get Help, Tips, Solitaire, Feedback Hub, To Do, Power Automate, Maps, People, Movies & TV, Office Hub, Outlook (new), Teams personal, Copilot, Quick Assist |
| Sistema | Windows Media Player legacy, Work Folders, Steps Recorder, WordPad (si aparece), Math Input, Internet Explorer/IE mode, Windows To Go, Language packs que no uses |
| Privacidad | Customer Experience Improvement Program, Diagnostics Hub si aparece, Recall/AI Components si tu versión los trae |
| Opcional | OneDrive (si no lo usas), Mixed Reality, Speech recognition, Handwriting (sin pantalla táctil con lápiz) |

**NO quites** aunque parezca que sobra:
- **Edge WebView2**: muchos launchers (Riot, EA, Battle.net…) lo necesitan. Puedes quitar Edge, pero deja WebView2.
- **Search / Start Menu / ShellExperienceHost**: rompen el menú Inicio.
- **.NET, Visual C++ y DirectX**: los juegos los necesitan.
- **Hyper‑V / plataforma de virtualización**: si algún anticheat o WSL lo necesita. VBS se puede desactivar luego desde el panel.
- **Defender**: déjalo. Se puede ajustar, pero quitarlo por completo da más problemas que FPS.

## 3. Features

- **Activar .NET Framework 3.5** (NetFx3): muchos juegos antiguos lo piden.
- Desactivar: Windows Media Player legacy, Work Folders, Recall (si aparece).
- SMB1 y PowerShell 2.0 deben quedar desactivados (ya lo están por defecto).

## 4. Updates

Descarga del **Microsoft Update Catalog** la última *Cumulative Update* de tu versión (x64) y la de *.NET Framework*, y añádelas en **Updates → Add**. La instalación sale ya parcheada.

## 5. Drivers

**Drivers → Add → Folder** → `C:\DriversBackup` (lo del paso 0). Puedes desmarcar impresoras y periféricos antiguos.
Después de instalar, pon el driver actual de tu gráfica desde amd.com, nvidia.com o intel.com.

## 6. Registry (lo único que tocamos aquí)

**Registry → Add → New**:

| Clave | Valor | Para qué |
|---|---|---|
| `HKLM\SYSTEM\CurrentControlSet\Control\BitLocker` | `PreventDeviceEncryption` = DWORD `1` | Evita que 24H2 cifre el disco automáticamente al iniciar sesión con una cuenta Microsoft |

Todo lo demás lo hace el panel (es reversible).

## 7. Unattended (instalación desatendida)

Activa **Unattended mode** y configura:
- **Idioma, teclado y región**: es‑ES (o tu país).
- **Users**: crea tu **cuenta local** con contraseña y del grupo Administradores. Así te saltas la cuenta Microsoft obligatoria.
- **Skip OOBE / privacy screens**: ProtectYourPC = 3 (todas las opciones de privacidad en "no").
- **Zona horaria**.
- **No** pongas la clave de producto si tu licencia es digital.
- La partición la puedes dejar manual, para elegir tú el disco al instalar (más seguro).

## 8. Post‑Setup (opcional)

Puedes meter la carpeta `OptiEleven` en la ISO con **Post‑Setup → Add → Folder** para tenerla ya en el sistema. Recomiendo **no** ejecutarla automáticamente: ábrela tú tras el primer inicio de sesión, para que los ajustes de usuario (HKCU) se apliquen a tu cuenta y no a SYSTEM.

## 9. Generar la ISO

**Apply** → marca **Create ISO** → procesa (tarda un rato).
Grábala en un USB con **Rufus** (GPT/UEFI) o con **Ventoy**.

## 10. Después de instalar

1. Windows Update hasta que no quede nada pendiente, más el driver de la gráfica.
2. Ejecuta `OptiEleven\OptiEleven.cmd` → **System → Restore point** (Sistema → Punto de restauración) → preset **Recommended** (Recomendado) → Aplicar → reinicia.
3. Juega un par de días. Si va bien, prueba el preset **Avanzado** (Advanced), o sus ajustes de uno en uno.
