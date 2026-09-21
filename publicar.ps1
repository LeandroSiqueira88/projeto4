# publicar.ps1
# ============
# Compila o app Flutter Web e publica no Firebase Hosting.
#
# Uso, a partir da raiz do projeto:
#   .\publicar.ps1
#   .\publicar.ps1 -SoRegras     (publica so as regras do Firestore)
#
# Se o PowerShell bloquear a execucao do script:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned

param(
    [switch]$SoRegras
)

$ErrorActionPreference = "Stop"
$raiz = $PSScriptRoot

function Etapa($texto) {
    Write-Host ""
    Write-Host "=== $texto ===" -ForegroundColor Cyan
}

if ($SoRegras) {
    Etapa "Publicando regras do Firestore"
    Set-Location $raiz
    firebase deploy --only firestore:rules
    exit $LASTEXITCODE
}

# --- 1. compilar ---
Etapa "Compilando o app Flutter para web"
Set-Location (Join-Path $raiz "app_flutter")

flutter build web --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "Falha na compilacao. Publicacao cancelada." -ForegroundColor Red
    exit 1
}

# --- 2. conferir a saida ---
$saida = Join-Path $raiz "app_flutter\build\web\index.html"
if (-not (Test-Path $saida)) {
    Write-Host "index.html nao encontrado em app_flutter\build\web" -ForegroundColor Red
    Write-Host "A compilacao terminou mas nao gerou os arquivos esperados." -ForegroundColor Red
    exit 1
}

# --- 3. publicar ---
Etapa "Publicando no Firebase Hosting"
Set-Location $raiz

firebase deploy --only hosting
if ($LASTEXITCODE -ne 0) {
    Write-Host "Falha na publicacao." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Publicado. A URL aparece acima, em 'Hosting URL'." -ForegroundColor Green
Write-Host "Lembre-se: toda alteracao no codigo exige rodar este script de novo." -ForegroundColor DarkGray
