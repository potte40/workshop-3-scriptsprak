
#Läs in JSON
$data = Get-Content -Path "ad_export.json" -Raw -Encoding UTF8 | ConvertFrom-Json


function Get-InactiveAccounts {
    param (
        [Parameter(Mandatory = $true)]
        $Data,

        [int]$Days = 30
    )

    $cutoffDate = (Get-Date).AddDays(-$Days)

    $inactiveUsers = $Data.users |
    Where-Object { [datetime]$_.lastLogon -lt $cutoffDate } |
    Select-Object samAccountName, displayName, email, department, site, lastLogon, accountExpires,
    @{Name = 'DaysInactive'; Expression = { (New-TimeSpan -Start ([datetime]$_.lastLogon) -End (Get-Date)).Days } } |
    Sort-Object -Property DaysInactive -Descending

    return $inactiveUsers
}


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