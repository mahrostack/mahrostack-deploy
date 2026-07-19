[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Must match ssl_certificate / ssl_certificate_key in nginx includes.
$Domain = 'mahrostack.test'
$certDirectory = Join-Path $PSScriptRoot 'nginx\certs'
$opensslImage = 'alpine/openssl'

New-Item -ItemType Directory -Force -Path $certDirectory | Out-Null
$certDirectory = (Resolve-Path $certDirectory).Path
$mount = "${certDirectory}:/certs"

Write-Host "Certificates directory: $certDirectory"

function Invoke-OpenSsl {
    param([Parameter(Mandatory)][string[]] $Arguments)

    & docker run --rm --user 0:0 --volume $mount $opensslImage @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "OpenSSL failed with exit code $LASTEXITCODE."
    }
}

function Invoke-ChmodReadable {
    param([Parameter(Mandatory)][string[]] $Paths)

    # nginxinc/nginx-unprivileged runs as uid 101. OpenSSL writes keys as 0600,
    # which appears as root:root on Docker Desktop bind mounts and causes:
    #   BIO_new_file() ... Permission denied
    $chmodArgs = [string[]](@('644') + $Paths)
    & docker run --rm --user 0:0 --volume $mount --entrypoint chmod $opensslImage $chmodArgs
    if ($LASTEXITCODE -ne 0) {
        throw "chmod failed with exit code $LASTEXITCODE."
    }
}

$extFile = Join-Path $certDirectory "$Domain.ext"
if (-not (Test-Path $extFile)) {
    @"
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$Domain,DNS:*.$Domain
"@ | Set-Content -Path $extFile -Encoding ascii
    Write-Host "Created extension file: $extFile"
}

Invoke-OpenSsl @(
    'genrsa',
    '-out', '/certs/mahrostack-local-ca.key',
    '2048'
)

Invoke-OpenSsl @(
    'req', '-x509', '-new',
    '-key', '/certs/mahrostack-local-ca.key',
    '-sha256', '-days', '3650',
    '-subj', '/CN=MahroStack Local Development CA',
    '-out', '/certs/mahrostack-local-ca.pem'
)

Invoke-OpenSsl @(
    'genrsa',
    '-out', "/certs/$Domain-key.pem",
    '2048'
)

Invoke-OpenSsl @(
    'req', '-new',
    '-key', "/certs/$Domain-key.pem",
    '-subj', "/CN=$Domain",
    '-out', "/certs/$Domain.csr"
)

Invoke-OpenSsl @(
    'x509', '-req',
    '-in', "/certs/$Domain.csr",
    '-CA', '/certs/mahrostack-local-ca.pem',
    '-CAkey', '/certs/mahrostack-local-ca.key',
    '-CAcreateserial',
    '-out', "/certs/$Domain.pem",
    '-days', '825', '-sha256',
    '-extfile', "/certs/$Domain.ext"
)

# Make leaf cert + key readable by the unprivileged nginx user.
Invoke-ChmodReadable @(
    "/certs/$Domain.pem",
    "/certs/$Domain-key.pem",
    '/certs/mahrostack-local-ca.pem'
)

Remove-Item -Force -ErrorAction SilentlyContinue `
    (Join-Path $certDirectory "$Domain.csr"), `
    (Join-Path $certDirectory 'mahrostack-local-ca.srl')

& certutil.exe -user -addstore Root (Join-Path $certDirectory 'mahrostack-local-ca.pem')
if ($LASTEXITCODE -ne 0) {
    throw "Could not trust the local CA; certutil exited with code $LASTEXITCODE."
}

Write-Host ""
Write-Host "Created certificate for $Domain and *.$Domain."
Write-Host "  Cert: $certDirectory\$Domain.pem"
Write-Host "  Key:  $certDirectory\$Domain-key.pem"
Write-Host "Trusted MahroStack Local Development CA for the current Windows user."
