$DnsName   = ''
$IpAddress = ''
$Port      = 

$script:ServerCert  = $null
$script:PolicyError = $null
$script:ChainRows   = @()
$script:ChainErrors = @()

$callback = [System.Net.Security.RemoteCertificateValidationCallback]{
    param(
        $Sender,
        $Certificate,
        $Chain,
        $SslPolicyErrors
    )

    $script:ServerCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $Certificate
    )

    $script:PolicyError = $SslPolicyErrors

    if ($null -ne $Chain) {
        $script:ChainErrors = @(
            $Chain.ChainStatus | ForEach-Object {
                "$($_.Status): $($_.StatusInformation.Trim())"
            }
        )

        $script:ChainRows = @(
            for ($i = 0; $i -lt $Chain.ChainElements.Count; $i++) {
                $Element = $Chain.ChainElements[$i]

                $ElementStatus = @(
                    $Element.ChainElementStatus | ForEach-Object {
                        "$($_.Status): $($_.StatusInformation.Trim())"
                    }
                )

                [pscustomobject]@{
                    Level      = $i
                    Subject    = $Element.Certificate.Subject
                    Issuer     = $Element.Certificate.Issuer
                    ValidFrom  = $Element.Certificate.NotBefore
                    ValidUntil = $Element.Certificate.NotAfter
                    Status     = if ($ElementStatus.Count) {
                        $ElementStatus -join '; '
                    } else {
                        'OK'
                    }
                }
            }
        )
    }

    # Allow the handshake to complete so we can display all errors.
    return $true
}

$Tcp = [System.Net.Sockets.TcpClient]::new()
$Ssl = $null

try {
    $Tcp.Connect($IpAddress, $Port)

    $Ssl = [System.Net.Security.SslStream]::new(
        $Tcp.GetStream(),
        $false,
        $callback
    )

    # Using the DNS name here sends the correct SNI value.
    $Ssl.AuthenticateAsClient($DnsName)

    $SanExtension = $script:ServerCert.Extensions |
        Where-Object { $_.Oid.Value -eq '2.5.29.17' } |
        Select-Object -First 1

    Write-Host "`n=== TLS CONNECTION ===" -ForegroundColor Cyan
    [pscustomobject]@{
        ConnectedTo      = "${IpAddress}:$Port"
        SNIHostname      = $DnsName
        TLSProtocol      = $Ssl.SslProtocol
        Cipher           = $Ssl.CipherAlgorithm
        CipherStrength   = $Ssl.CipherStrength
        SSLPolicyErrors  = $script:PolicyError
    } | Format-List

    Write-Host "=== SERVER CERTIFICATE ===" -ForegroundColor Cyan
    [pscustomobject]@{
        Subject    = $script:ServerCert.Subject
        Issuer     = $script:ServerCert.Issuer
        SAN        = if ($SanExtension) { $SanExtension.Format($false) } else { 'None' }
        ValidFrom  = $script:ServerCert.NotBefore
        ValidUntil = $script:ServerCert.NotAfter
        Thumbprint = $script:ServerCert.Thumbprint
    } | Format-List

    Write-Host "=== CERTIFICATE CHAIN ===" -ForegroundColor Cyan
    $script:ChainRows | Format-Table -AutoSize -Wrap

    Write-Host "=== OVERALL CHAIN STATUS ===" -ForegroundColor Cyan

    if (
        $script:PolicyError -eq [System.Net.Security.SslPolicyErrors]::None -and
        $script:ChainErrors.Count -eq 0
    ) {
        Write-Host 'PASS: Windows successfully validated the certificate chain.' -ForegroundColor Green
    }
    else {
        Write-Host "FAIL: SSL policy errors: $script:PolicyError" -ForegroundColor Red

        if ($script:ChainErrors.Count) {
            $script:ChainErrors | ForEach-Object {
                Write-Host " - $_" -ForegroundColor Red
            }
        }
    }
}
catch {
    Write-Host "Connection or TLS handshake failed: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($null -ne $Ssl) {
        $Ssl.Dispose()
    }

    $Tcp.Dispose()
}
