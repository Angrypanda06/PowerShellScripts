$Asn = 'AS43444'
$Uri = "https://stat.ripe.net/data/announced-prefixes/data.json?resource=$Asn"

function Convert-IPv4ToUInt32 {
    param([Parameter(Mandatory)][string]$Ip)
    $bytes = [System.Net.IPAddress]::Parse($Ip).GetAddressBytes()
    if ($bytes.Length -ne 4) { throw "Not an IPv4 address: $Ip" }
    [array]::Reverse($bytes)
    [BitConverter]::ToUInt32($bytes, 0)
}

function Convert-UInt32ToIPv4 {
    param([Parameter(Mandatory)][UInt32]$Value)
    $bytes = [BitConverter]::GetBytes($Value)
    [array]::Reverse($bytes)
    ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Convert-CIDRToRange {
    param([Parameter(Mandatory)][string]$Cidr)

    $parts = $Cidr.Split('/')
    if ($parts.Count -ne 2) { throw "Invalid CIDR: $Cidr" }

    $ip = $parts[0]
    $prefix = [int]$parts[1]

    if ($prefix -lt 0 -or $prefix -gt 32) {
        throw "Invalid prefix length in $Cidr"
    }

    $ipNum = [uint64](Convert-IPv4ToUInt32 $ip)

    if ($prefix -eq 0) {
        $mask = [uint64]0
        $size = [uint64]4294967296
    }
    elseif ($prefix -eq 32) {
        $mask = [uint64]4294967295
        $size = [uint64]1
    }
    else {
        $hostBits = 32 - $prefix
        $size = [uint64][math]::Pow(2, $hostBits)
        $mask = [uint64](4294967296 - $size)
    }

    $start = $ipNum -band $mask
    $end   = $start + $size - 1

    [pscustomobject]@{
        CIDR  = $Cidr
        Start = [uint64]$start
        End   = [uint64]$end
    }
}

function Get-FloorLog2 {
    param([Parameter(Mandatory)][UInt64]$Value)
    $n = 0
    while ($Value -gt 1) {
        $Value = [UInt64]($Value / 2)
        $n++
    }
    $n
}

function Convert-RangeToCidrs {
    param(
        [Parameter(Mandatory)][UInt64]$Start,
        [Parameter(Mandatory)][UInt64]$End
    )

    $result = New-Object System.Collections.Generic.List[string]
    $current = $Start

    while ($current -le $End) {
        if ($current -eq 0) {
            $maxBlock = [uint64]4294967296
        }
        else {
            $maxBlock = [uint64]1
            while (($current % ($maxBlock * 2)) -eq 0 -and ($maxBlock * 2) -le 4294967296) {
                $maxBlock = [uint64]($maxBlock * 2)
            }
        }

        $remaining = [uint64]($End - $current + 1)

        while ($maxBlock -gt $remaining) {
            $maxBlock = [uint64]($maxBlock / 2)
        }

        $prefix = 32 - (Get-FloorLog2 $maxBlock)
        $cidr = ("{0}/{1}" -f (Convert-UInt32ToIPv4 ([uint32]$current)), $prefix)
        $result.Add($cidr)

        $current = [uint64]($current + $maxBlock)
    }

    $result
}

$data = Invoke-RestMethod -Uri $Uri -Method Get

$prefixes = $data.data.prefixes |
    ForEach-Object { $_.prefix } |
    Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$' } |
    Sort-Object -Unique

if (-not $prefixes) {
    throw "No IPv4 prefixes returned for $Asn"
}

$ranges = $prefixes |
    ForEach-Object { Convert-CIDRToRange $_ } |
    Sort-Object Start, End

$merged = New-Object System.Collections.Generic.List[object]
$current = $ranges[0]

for ($i = 1; $i -lt $ranges.Count; $i++) {
    $next = $ranges[$i]

    if ($next.Start -le ($current.End + 1)) {
        if ($next.End -gt $current.End) {
            $current.End = $next.End
        }
    }
    else {
        $merged.Add([pscustomobject]@{
            Start = $current.Start
            End   = $current.End
        })
        $current = $next
    }
}

$merged.Add([pscustomobject]@{
    Start = $current.Start
    End   = $current.End
})

$collapsed = foreach ($r in $merged) {
    Convert-RangeToCidrs -Start $r.Start -End $r.End
}

$collapsed |
    Sort-Object {
        $p = $_.Split('/')
        [uint32](Convert-IPv4ToUInt32 $p[0])
    }, {
        [int](($_.Split('/'))[1])
    }
