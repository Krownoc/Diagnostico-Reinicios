
# ================================================================
# DIAGNOSTICO INTEGRAL DE REINICIOS - WINDOWS 10 / 11
# Version 2.0
# Genera un informe TXT en el Escritorio
#
# Incluye:
# - Reinicios y apagados inesperados
# - Kernel-Power 41 con todos sus campos XML
# - BugCheck / pantallazos azules
# - Errores WHEA y hardware
# - Errores de disco, NTFS y controladores
# - Reinicios solicitados por procesos
# - Eventos de arranque y apagado
# - Errores de Windows Update
# - Estado del sistema y tiempo desde el ultimo arranque
# - Eventos relevantes de los ultimos 7 dias
# - Eventos Kernel-Power 41 de los ultimos 30 dias
#
# Solo lectura: no modifica configuraciones del sistema.
# ================================================================

$ErrorActionPreference = 'SilentlyContinue'

# ---------------- CONFIGURACION ----------------

$fechaInforme = Get-Date
$desde7 = $fechaInforme.AddDays(-7)
$desde30 = $fechaInforme.AddDays(-30)

$escritorio = [Environment]::GetFolderPath('Desktop')
$archivoLog = Join-Path $escritorio 'Diagnostico_Reinicios.txt'

# Eventos relevantes del registro System
$idsSistema = @(
    1, 2, 3, 4,
    12, 13,
    17, 18, 19, 20, 21,
    41, 46,
    55, 98,
    1001, 1074,
    129, 153, 157, 161,
    4101,
    6005, 6006, 6008
)

# Evitar que un informe anterior se mezcle con el nuevo
@"
================================================================
 INFORME DE DIAGNOSTICO DE REINICIOS
================================================================
Equipo:          $env:COMPUTERNAME
Usuario:         $env:USERDOMAIN\$env:USERNAME
Fecha del informe: $($fechaInforme.ToString('yyyy-MM-dd HH:mm:ss'))
Periodo general: ultimos 7 dias
Periodo Kernel-Power 41: ultimos 30 dias
================================================================

"@ | Out-File -FilePath $archivoLog -Encoding utf8

function Add-Log {
    param([string]$Texto)

    $Texto | Out-File -FilePath $archivoLog -Append -Encoding utf8
}

function Add-EventDetail {
    param($Evento)

    Add-Log @"

----------------------------------------------------------------
Fecha:    $($Evento.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))
ID:       $($Evento.Id)
Nivel:    $($Evento.LevelDisplayName)
Origen:   $($Evento.ProviderName)
Registro: $($Evento.LogName)
Mensaje:
$($Evento.Message)

"@
}

# ---------------- 1. DATOS DEL SISTEMA ----------------

Add-Log "`r`n========== 1. INFORMACION DEL SISTEMA =========="

try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS

    Add-Log @"

Nombre del equipo: $($cs.Name)
Fabricante: $($cs.Manufacturer)
Modelo: $($cs.Model)
Sistema operativo: $($os.Caption)
Version: $($os.Version)
Build: $($os.BuildNumber)
Ultimo arranque: $($os.LastBootUpTime)
BIOS: $($bios.SMBIOSBIOSVersion)
Fabricante BIOS: $($bios.Manufacturer)
"@

    if ($os.LastBootUpTime) {
        $uptime = (Get-Date) - $os.LastBootUpTime
        Add-Log ("Tiempo desde el ultimo arranque: {0} dias, {1} horas, {2} minutos" -f
            $uptime.Days, $uptime.Hours, $uptime.Minutes)
    }
}
catch {
    Add-Log "No se pudo obtener toda la informacion del sistema."
}

# ---------------- 2. EVENTOS SYSTEM - 7 DIAS ----------------

Add-Log "`r`n========== 2. EVENTOS DE SISTEMA - ULTIMOS 7 DIAS =========="

$eventos = @(
    Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        StartTime = $desde7
        Id = $idsSistema
    } -ErrorAction SilentlyContinue |
    Sort-Object TimeCreated -Descending
)

if ($eventos.Count -gt 0) {
    foreach ($evento in $eventos) {
        Add-EventDetail -Evento $evento
    }
}
else {
    Add-Log "No se encontraron eventos coincidentes."
}

# ---------------- 3. CAMPOS XML DE KERNEL-POWER 41 ----------------

Add-Log "`r`n========== 3. KERNEL-POWER 41: DATOS INTERNOS - 30 DIAS =========="

$eventos41 = @(
    Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        Id = 41
        StartTime = $desde30
    } -ErrorAction SilentlyContinue |
    Sort-Object TimeCreated -Descending
)

if ($eventos41.Count -gt 0) {
    foreach ($evento in $eventos41) {
        Add-Log @"

----------------------------------------------------------------
Kernel-Power 41
Fecha de registro: $($evento.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))
Record ID: $($evento.RecordId)
"@

        try {
            $xml = [xml]$evento.ToXml()
            $datos = $xml.Event.EventData.Data

            if ($datos) {
                foreach ($dato in $datos) {
                    $nombre = $dato.GetAttribute('Name')
                    $valor = $dato.InnerText

                    if ([string]::IsNullOrWhiteSpace($nombre)) {
                        $nombre = '(campo sin nombre)'
                    }

                    Add-Log ("{0} = {1}" -f $nombre, $valor)
                }
            }
            else {
                Add-Log "El evento no contiene campos EventData."
            }
        }
        catch {
            Add-Log "No se pudieron interpretar los campos XML del evento."
        }

        Add-Log "`r`nMensaje original:"
        Add-Log $evento.Message
    }
}
else {
    Add-Log "No se encontraron eventos Kernel-Power 41 en los ultimos 30 dias."
}

# ---------------- 4. BUGCHECK Y PANTALLAZOS AZULES ----------------

Add-Log "`r`n========== 4. BUGCHECK / PANTALLAZOS AZULES =========="

$proveedoresBugcheck = @(
    'Microsoft-Windows-WER-SystemErrorReporting',
    'BugCheck'
)

$bugchecks = @(
    Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        StartTime = $desde30
    } -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProviderName -in $proveedoresBugcheck -or
        $_.Id -eq 1001
    } |
    Sort-Object TimeCreated -Descending
)

if ($bugchecks.Count -gt 0) {
    foreach ($evento in $bugchecks) {
        Add-EventDetail -Evento $evento
    }
}
else {
    Add-Log "No se encontraron eventos BugCheck coincidentes en el registro System."
}

Add-Log "`r`n========== ARCHIVOS DE VOLCADO =========="

$dumpPaths = @(
    "$env:SystemRoot\MEMORY.DMP",
    "$env:SystemRoot\Minidump"
)

foreach ($ruta in $dumpPaths) {
    if (Test-Path $ruta) {
        Add-Log "`r`nRuta: $ruta"

        if ((Get-Item $ruta).PSIsContainer) {
            Get-ChildItem $ruta -File |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 30 Name, Length, LastWriteTime |
                ForEach-Object {
                    Add-Log ("Archivo: {0} | Bytes: {1} | Fecha: {2}" -f
                        $_.Name, $_.Length, $_.LastWriteTime)
                }
        }
        else {
            $archivo = Get-Item $ruta
            Add-Log ("Archivo: {0} | Bytes: {1} | Fecha: {2}" -f
                $archivo.Name, $archivo.Length, $archivo.LastWriteTime)
        }
    }
}

# ---------------- 5. ERRORES DE HARDWARE ----------------

Add-Log "`r`n========== 5. WHEA / ERRORES DE HARDWARE =========="

$eventosHardware = @(
    Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        StartTime = $desde30
    } -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProviderName -match 'WHEA-Logger|disk|storahci|stornvme|Ntfs|volmgr|Display|nvlddmkm|amdkmdag' -and
        $_.Level -in @(1, 2, 3)
    } |
    Sort-Object TimeCreated -Descending |
    Select-Object -First 300
)

if ($eventosHardware.Count -gt 0) {
    foreach ($evento in $eventosHardware) {
        Add-EventDetail -Evento $evento
    }
}
else {
    Add-Log "No se encontraron eventos coincidentes de hardware o almacenamiento."
}

# ---------------- 6. WINDOWS UPDATE ----------------

Add-Log "`r`n========== 6. WINDOWS UPDATE - ULTIMOS 7 DIAS =========="

$eventosUpdate = @(
    Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
        StartTime = $desde7
    } -ErrorAction SilentlyContinue |
    Sort-Object TimeCreated -Descending |
    Select-Object -First 150
)

if ($eventosUpdate.Count -gt 0) {
    foreach ($evento in $eventosUpdate) {
        Add-EventDetail -Evento $evento
    }
}
else {
    Add-Log "No se encontraron eventos de Windows Update en el registro System."
}

# ---------------- 7. HISTORIAL DE APAGADOS Y ARRANQUES ----------------

Add-Log "`r`n========== 7. SECUENCIA CRONOLOGICA DE ARRANQUES =========="

$idsSecuencia = @(12, 13, 41, 1074, 6005, 6006, 6008)

$secuencia = @(
    Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        Id = $idsSecuencia
        StartTime = $desde30
    } -ErrorAction SilentlyContinue |
    Sort-Object TimeCreated
)

if ($secuencia.Count -gt 0) {
    foreach ($evento in $secuencia) {
        Add-Log ("{0} | ID {1} | {2} | {3}" -f
            $evento.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'),
            $evento.Id,
            $evento.ProviderName,
            (($evento.Message -replace '\s+', ' ').Trim()))
    }
}
else {
    Add-Log "No se encontraron eventos de secuencia."
}

# ---------------- 8. RESUMEN ESTADISTICO ----------------

Add-Log "`r`n========== 8. RESUMEN DE EVENTOS - 7 DIAS =========="

if ($eventos.Count -gt 0) {
    $eventos |
        Group-Object Id |
        Sort-Object Count -Descending |
        ForEach-Object {
            Add-Log ("ID {0}: {1} evento(s)" -f $_.Name, $_.Count)
        }
}
else {
    Add-Log "No hay eventos para resumir."
}

# ---------------- 9. FINAL ----------------

Add-Log @"

================================================================
 FIN DEL INFORME
================================================================
Generado: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
Archivo: $archivoLog

NOTA:
Los eventos indican lo que Windows pudo registrar.
La ausencia de un evento no descarta una falla.
Kernel-Power 41 no identifica por si solo la causa.
================================================================
"@

Write-Host ""
Write-Host "Diagnostico finalizado." -ForegroundColor Green
Write-Host "Informe guardado en:" -ForegroundColor Cyan
Write-Host $archivoLog -ForegroundColor Yellow
Write-Host ""

if (Test-Path $archivoLog) {
    Invoke-Item $archivoLog
}
