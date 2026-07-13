[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$certDirectory = Join-Path $PSScriptRoot 'nginx\certs'
$opensslImage = 'nginxinc/nginx-unprivileged:alpine'

New-Item -ItemType Directory -Force -Path $certDirectory | Out-Null
$certDirectory = (Resolve-Path $certDirectory).Path
$mount = "${certDirectory}:/certs"

function Invoke-OpenSsl {
    param([Parameter(Mandatory)][string[]] $Arguments)

    & docker run --rm --user 0:0 --volume $mount --entrypoint openssl $opensslImage @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "OpenSSL failed with exit code $LASTEXITCODE."
    }
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
    '-out', '/certs/mahrostack.local-key.pem',
    '2048'
)

Invoke-OpenSsl @(
    'req', '-new',
    '-key', '/certs/mahrostack.local-key.pem',
    '-subj', '/CN=mahrostack.local',
    '-out', '/certs/mahrostack.local.csr'
)

Invoke-OpenSsl @(
    'x509', '-req',
    '-in', '/certs/mahrostack.local.csr',
    '-CA', '/certs/mahrostack-local-ca.pem',
    '-CAkey', '/certs/mahrostack-local-ca.key',
    '-CAcreateserial',
    '-out', '/certs/mahrostack.local.pem',
    '-days', '825', '-sha256',
    '-extfile', '/certs/mahrostack.local.ext'
)

Remove-Item -Force -ErrorAction SilentlyContinue `
    (Join-Path $certDirectory 'mahrostack.local.csr'), `
    (Join-Path $certDirectory 'mahrostack-local-ca.srl')

& certutil.exe -user -addstore Root (Join-Path $certDirectory 'mahrostack-local-ca.pem')
if ($LASTEXITCODE -ne 0) {
    throw "Could not trust the local CA; certutil exited with code $LASTEXITCODE."
}

Write-Host 'Created a certificate for mahrostack.local and *.mahrostack.local.'
Write-Host 'Trusted MahroStack Local Development CA for the current Windows user.'
