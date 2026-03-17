$ErrorActionPreference = "Stop"

param(
    [string[]]$RemoteSubnet,
    [string]$DisplayName = "Allow Ollama from Docker Desktop",
    [int]$Port = 11434,
    [switch]$RemoveExisting
)

function Convert-IPv4ToUInt32 {
    param([Parameter(Mandatory = $true)][string]$IpAddress)

    $bytes = ([System.Net.IPAddress]::Parse($IpAddress)).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Convert-UInt32ToIPv4 {
    param([Parameter(Mandatory = $true)][uint32]$Value)

    $bytes = [BitConverter]::GetBytes($Value)
    [Array]::Reverse($bytes)
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Convert-ToCidr {
    param(
        [Parameter(Mandatory = $true)][string]$IpAddress,
        [Parameter(Mandatory = $true)][int]$PrefixLength
    )

    if ($PrefixLength -lt 0 -or $PrefixLength -gt 32) {
        throw "Invalid prefix length: $PrefixLength"
    }

    $ipValue = Convert-IPv4ToUInt32 -IpAddress $IpAddress
    $mask = if ($PrefixLength -eq 0) { [uint32]0 } else { [uint32]([uint64]0xFFFFFFFF -shl (32 - $PrefixLength)) }
    $networkValue = $ipValue -band $mask
    $networkIp = Convert-UInt32ToIPv4 -Value $networkValue
    return "$networkIp/$PrefixLength"
}

function Get-DockerRelatedSubnets {
    $addresses = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -notmatch '^169\.254\.' -and
            $_.PrefixLength -ge 0 -and
            $_.InterfaceAlias -match 'WSL|Docker'
        }

    $cidrs = $addresses |
        ForEach-Object { Convert-ToCidr -IpAddress $_.IPAddress -PrefixLength $_.PrefixLength } |
        Sort-Object -Unique

    if (-not $cidrs) {
        throw "No Docker or WSL IPv4 subnets were detected. Pass -RemoteSubnet manually, for example -RemoteSubnet 192.168.65.0/24."
    }

    return $cidrs
}

if (-not $RemoteSubnet -or $RemoteSubnet.Count -eq 0) {
    $RemoteSubnet = Get-DockerRelatedSubnets
}

$existingRules = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue

if ($existingRules) {
    if ($RemoveExisting) {
        $existingRules | Remove-NetFirewallRule
    }
    else {
        throw "A firewall rule named '$DisplayName' already exists. Re-run with -RemoveExisting to replace it."
    }
}

New-NetFirewallRule `
    -DisplayName $DisplayName `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort $Port `
    -RemoteAddress $RemoteSubnet

Write-Host "Created firewall rule '$DisplayName' for port $Port." -ForegroundColor Green
Write-Host "Allowed remote subnets: $($RemoteSubnet -join ', ')"
