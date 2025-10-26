
#Läs in JSON
$data = Get-Content -Path "ad_export.json" -Raw -Encoding UTF8 | ConvertFrom-Json

### Function för inaktiva accounts ###
function Get-InactiveAccounts {
    param (
        [Parameter(Mandatory = $true)]
        $Data,

        [int]$Days = 30
    )

    $cutoffDate = $today.AddDays(-$Days)

    $inactiveUsers = $Data.users |
    Where-Object { [datetime]$_.lastLogon -lt $cutoffDate } |
    Select-Object samAccountName, displayName, email, department, site, lastLogon, accountExpires,
    @{Name = 'DaysInactive'; Expression = { (New-TimeSpan -Start ([datetime]$_.lastLogon) -End $today).Days } } |
    Sort-Object -Property DaysInactive -Descending

    return $inactiveUsers
}

### Function för Safedate ###
function SafeParseDate {
    param([string]$DateString)
    try {
        return [datetime]::Parse($DateString)
    }
    catch {
        Write-Warning "Kunde inte tolka datumet: $DateString"
        return $null
    }
}


### Function för att hitta expiring accounts ###
$reportDate = if ($data.export_date) { [datetime]$data.export_date } else { Get-Date }

$expiringAccounts = $data.users | Where-Object {

    if (-not $_.accountExpires -or $_.accountExpires -eq '') { return $false }

    try {
        $exp = [datetime]$_.accountExpires
    }
    catch {
        return $false
    }

    $daysUntil = (New-TimeSpan -Start $reportDate -End $exp).Days
    return ($daysUntil -ge 0 -and $daysUntil -le 30)
}
