### Function för SafeParseDate ###
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

### Function för inaktiva konton ###
function Get-InactiveAccounts {
    param (
        [Parameter(Mandatory = $true)]
        $Data,

        [int]$Days = 30,

        [datetime]$Today
    )

    if (-not $Today) { $Today = Get-Date }

    $cutoffDate = $Today.AddDays(-$Days)

    $inactiveUsers = $Data.users |
    Where-Object { 
        $lastLogon = [datetime]$_.lastLogon
        $lastLogon -lt $cutoffDate
    } |
    Select-Object samAccountName, displayName, email, department, site, lastLogon, accountExpires,
    @{Name = 'DaysInactive'; Expression = { 
            $last = [datetime]$_.lastLogon
            (New-TimeSpan -Start $last -End $Today).Days
        }
    } |
    Sort-Object -Property DaysInactive -Descending

    return $inactiveUsers
}

### Function för expiring accounts ###
function Get-ExpiringAccounts {
    param (
        [Parameter(Mandatory = $true)]
        $Data,

        [datetime]$today
    )

    if (-not $today) { $today = Get-Date }

    $expiringAccounts = $Data.users | Where-Object {
        if (-not $_.accountExpires -or $_.accountExpires -eq '') { return $false }
        try { $exp = [datetime]$_.accountExpires } catch { return $false }
        $daysUntil = (New-TimeSpan -Start $today -End $exp).Days
        return ($daysUntil -ge 0 -and $daysUntil -le 30)
    }

    return $expiringAccounts
}
