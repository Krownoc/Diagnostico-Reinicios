
# ============================================================
# DIAGNOSTICO DE REINICIOS - WINDOWS 11
# Analisis de eventos de sistema de los ultimos 7 dias
# Salida: Escritorio\Diagnostico_Reinicios.txt
# ============================================================

$ErrorActionPreference = 'SilentlyContinue'

# Configuracion
$desde = (Get-Date).AddDays(-7)
$escritorio = [Environment]::GetFolderPath('Desktop')
$archivoLog = Join-Path $escritorio 'Diagnostico_Reinicios.txt'

# IDs relevantes del registro Sistema
$ids = @(
    41, 6008, 1074, 1001, 6005, 6006,
    12, 13, 161, 19, 20, 46
)

# Crear encabezado del informe
@"
============================================================
 DIAGNOSTICO DE REINICIOS - WINDOWS
============================================================
Equipo:       $env:COMPUTERNAME
Usuario:      $env:USERNAME
Sistema:      $([Environment]::OSVersion.VersionString)
Fecha informe: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Periodo desde: $($desde.ToString('yyyy-MM-dd HH:mm:ss'))
Periodo hasta: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
============================================================

"@ | Out-File -FilePath $archivoLog -Encoding utf8

# ------------------------------------------------------------
# 1. Resumen de ultimos arranques
# ------------------------------------------------------------

"`r`n========== ULTIMOS ARRANQUES DEL SISTEMA ==========`r`n" |
    Out-File $archivoLog -Append -Encoding utf8

Get-CimInstance Win32_OperatingSystem |
    Select-Object CSName, LastBootUpTime |
    Format-List |
    Out-String |
    Out-File $archivoLog -Append -Encoding utf8

# ------------------------------------------------------------
# 2. Eventos principales de reinicio y apagado
# ------------------------------------------------------------

"`r`n========== EVENTOS DE REINICIO Y APAGADO ==========`r`n" |
    Out-File $archivoLog -Append -Encoding utf8

$eventos = Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    Id        = $ids
    StartTime = $desde
} -ErrorAction SilentlyContinue |
    Sort-Object TimeCreated -Descending

if ($eventos) {
    foreach ($evento in $eventos) {
        @"
------------------------------------------------------------
Fecha:    $($evento.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))
ID:       $($evento.Id)
Nivel:    $($evento.LevelDisplayName)
Origen:   $($evento.ProviderName)
Mensaje:
$($evento.Message)

"@ | Out-File $archivoLog -Append -Encoding utf8
    }
}
else {
    "No se encontraron eventos coincidentes en el periodo." |
        Out-File $archivoLog -Append -Encoding utf8
}

# ------------------------------------------------------------
# 3. Errores y advertencias relevantes del sistema
# ------------------------------------------------------------

"`r`n========== ERRORES Y ADVERTENCIAS RELEVANTES ==========`r`n" |
    Out-File $archivoLog -Append -Encoding utf8

$errores = Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    StartTime = $desde
    Level     = 1, 2, 3
} -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProviderName -match
        'Kernel-Power|WHEA-Logger|BugCheck|volmgr|EventLog|User32|Kernel-General'
    } |
    Sort-Object TimeCreated -Descending |
    Select-Object -First 300

if ($errores) {
    foreach ($evento in $errores) {
        @"
------------------------------------------------------------
Fecha:    $($evento.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))
ID:       $($evento.Id)
Nivel:    $($evento.LevelDisplayName)
Origen:   $($evento.ProviderName)
Mensaje:
$($evento.Message)

"@ | Out-File $archivoLog -Append -Encoding utf8
    }
}
else {
    "No se encontraron errores o advertencias coincidentes." |
        Out-File $archivoLog -Append -Encoding utf8
}

# ------------------------------------------------------------
# 4. Historial de pantallazos azules (BugCheck)
# ------------------------------------------------------------

"`r`n========== EVENTOS BUGCHECK / PANTALLAZOS AZULES ==========`r`n" |
    Out-File $archivoLog -Append -Encoding utf8

Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'
    StartTime = $desde
} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, Message |
    Format-List |
    Out-String |
    Out-File $archivoLog -Append -Encoding utf8

# ------------------------------------------------------------
# 5. Resumen estadistico de eventos principales
# ------------------------------------------------------------

"`r`n========== RESUMEN POR ID DE EVENTO ==========`r`n" |
    Out-File $archivoLog -Append -Encoding utf8

if ($eventos) {
    $eventos |
        Group-Object Id |
        Sort-Object Count -Descending |
        ForEach-Object {
            "ID $($_.Name): $($_.Count) evento(s)"
        } |
        Out-File $archivoLog -Append -Encoding utf8
}
else {
    "Sin eventos para resumir." |
        Out-File $archivoLog -Append -Encoding utf8
}

# ------------------------------------------------------------
# Finalizacion
# ------------------------------------------------------------

"`r`n========== FIN DEL INFORME ==========`r`n" |
    Out-File $archivoLog -Append -Encoding utf8

Write-Host ""
Write-Host "Diagnostico finalizado." -ForegroundColor Green
Write-Host "Archivo generado: $archivoLog" -ForegroundColor Cyan
Write-Host ""

# Abrir el informe automaticamente
if (Test-Path $archivoLog) {
    Invoke-Item $archivoLog
}
