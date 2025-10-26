# Läs in JSON
$data = Get-Content -Path "ad_export.json" -Raw -Encoding UTF8 | ConvertFrom-Json

### Anropa functionsfilen ###
. "$PSScriptRoot\functions.ps1"

### Anropa funktionen inactiveUsers ###
$inactiveUsers = Get-InactiveAccounts -Data $data -Days 30

########### Jag använder mig utav funktionen istället, skulle kunna plocka bort det här men låter det vara. ###########
# Exempel: Användare som inte loggat in på 30 dagar
#$thirtyDaysAgo = (Get-Date).AddDays(-30)

# Filtrera användare som inte loggat in på 30+ dagar
#$inactiveUsers = $data.users |
#Where-Object { [datetime]$_.lastLogon -lt $thirtyDaysAgo } |
#Select-Object samAccountName, displayName, email, department, site, lastLogon, accountExpires,
#@{Name = 'DaysInactive'; Expression = { (New-TimeSpan -Start ([datetime]$_.lastLogon) -End (Get-Date)).Days } } |
#Sort-Object -Property DaysInactive -Descending


# Exportera inaktiva användare till CSV
$inactiveUsers | Export-Csv -Path "$PSScriptRoot\inactive_users.csv" -NoTypeInformation -Encoding UTF8
Write-Host "`nCSV-fil skapad: inactive_users.csv"

# Gruppera användare per avdelning
$deptGroups = $data.users | Group-Object -Property department

# Visa resultat
Write-Host `n"ANVÄNDARE PER AVDELNING:"
Write-Host $("-" * 40)
foreach ($group in $deptGroups) {
    Write-Host "$($group.Name): $($group.Count) användare"
}

Write-Host `n"ANVÄNDARE PER SITE:"
Write-Host $("-" * 40)
$data.computers | 
Group-Object -Property site | 
Sort-Object -Property Count -Descending |
ForEach-Object {
    Write-Host "$($_.Name): $($_.Count) datorer"
}


### Beräkna lösenordsålder ###

$today = SafeParseDate $data.export_date

$passwordAges = $data.users |
Where-Object { -not $_.passwordNeverExpires } |
Select-Object samAccountName, displayName, passwordLastSet, email,
@{Name = 'PasswordAgeDays'; Expression = { 
        (New-TimeSpan -Start (SafeParseDate $_.passwordLastSet) -End $today).Days 
    }
} |
Sort-Object -Property PasswordAgeDays -Descending

### Exportera till CSV ### 
$passwordAges | Export-Csv -Path "$PSScriptRoot\password_age.csv" -NoTypeInformation -Encoding UTF8
Write-Host "`nCSV-fil skapad: password_age.csv"

### Skriv ut topplistan i terminalen ###
Write-Host "`nANVÄNDARE MED ÄLDST LÖSENORD:"
Write-Host $("-" * 45)
foreach ($user in $passwordAges | Select-Object -First 10) {
    Write-Host ("{0,-25} | {1,-35} | {2,3} dagar" -f `
            $user.displayName, $user.email, $user.PasswordAgeDays)
}


### Skapa copmuter_status.csv ###
$computerStatus = $data.computers |
Group-Object -Property site |
ForEach-Object {
    $siteName = $_.Name
    $total = $_.Count
    $active = ($_.Group | Where-Object { (New-TimeSpan -Start (SafeParseDate $_.lastLogon) -End $today).Days -le 7 }).Count
    $inactive = $total - $active
    $win10 = ($_.Group | Where-Object { $_.operatingSystem -match "Windows 10" }).Count
    $win11 = ($_.Group | Where-Object { $_.operatingSystem -match "Windows 11" }).Count
    $winServer = ($_.Group | Where-Object { $_.operatingSystem -match "Windows Server" }).Count

    [PSCustomObject]@{
        Site              = $siteName
        TotalComputers    = $total
        ActiveComputers   = $active
        InactiveComputers = $inactive
        Windows10         = $win10
        Windows11         = $win11
        WindowsServer     = $winServer
    }
}

### Exportera till CSV ###
$computerStatus | Export-Csv -Path "$PSScriptRoot\computer_status.csv" -NoTypeInformation -Encoding UTF8

Write-Host "`nCSV-fil skapad: computer_status.csv"

### Visa i terminalen ###
Write-Host "`nDatorstatistik per site:"
$computerStatus | Format-Table -AutoSize


# ===========================
#         Rapporten         #
# ===========================

### Dynamisk räknare för datorer ###
$activeComputersCount = ($data.computers | Where-Object { (New-TimeSpan -Start (SafeParseDate $_.lastLogon) -End $today).Days -le 7 }).Count
$inactiveComputersCount = ($data.computers | Where-Object { (New-TimeSpan -Start (SafeParseDate $_.lastLogon) -End $today).Days -ge 30 }).Count

$report = @"
================================================================================
                    ACTIVE DIRECTORY AUDIT REPORT
================================================================================
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Domain: $($data.domain)
Export Date: $($data.export_date)

EXECUTIVE SUMMARY
-----------------

"@

### Dynamiska varningar ###
if ($expiringAccounts -and $expiringAccounts.Count -gt 0) {
    $report += "⚠ CRITICAL: $($expiringAccounts.Count) user accounts expiring within 30 days`n"
}
if ($inactiveUsers.Count -gt 0) {
    $report += "⚠ WARNING: $($inactiveUsers.Count) users haven't logged in for 30+ days`n"
}
if ($inactiveComputersCount -gt 0) {
    $report += "⚠ WARNING: $inactiveComputersCount computers not seen in 30+ days`n"
}
if ($passwordAges.Count -gt 0) {
    $report += "⚠ SECURITY: $($passwordAges.Count) users with passwords older than 90 days`n"
}

### POSITIV statistik ###
$win11Count = ($data.computers | Where-Object { $_.operatingSystem -match "Windows 11" }).Count
$win11Percent = if ($totalComputers -gt 0) { [math]::Round(($win11Count / $totalComputers) * 100) } else { 0 }
$report += "✓ POSITIVE: $win11Percent`% of computers running Windows 11`n`n"

### USER ACCOUNT STATUS ###

$totalUsers = $data.users.Count
$activeUsers = ($data.users | Where-Object { $_.enabled }).Count
$disabledUsers = ($data.users | Where-Object { -not $_.enabled }).Count

$report += @"
USER ACCOUNT STATUS
-------------------
Total Users: $totalUsers
Active Users: $activeUsers ($([math]::Round(($activeUsers / $totalUsers) * 100))%)
Disabled Accounts: $disabledUsers
`n
INACTIVE USERS (No login >30 days)
-----------------------------------
Username        Name                  Department   Last Login             Days Inactive

"@

foreach ($user in $inactiveUsers | Sort-Object -Property lastLogon) {
    $daysInactive = (New-TimeSpan -Start (SafeParseDate $user.lastLogon) -End $today).Days
    $report += "{0,-15} {1,-21} {2,-12} {3,-32} {4,3}`n" -f $user.samAccountName, $user.displayName, $user.department, $user.lastLogon, $daysInactive
}

### USERS PER DEPARTMENT ###
$report += "`nUSERS PER DEPARTMENT
--------------------`n"
foreach ($group in $deptGroups | Sort-Object -Property Count -Descending) {
    $report += "{0,-20} {1} users`n" -f $group.Name, $group.Count
}


### COMPUTER STATUS ###

$report += "`nCOMPUTER STATUS
---------------`n"
$report += @"
Total Computers: $totalComputers
Active (seen <7 days): $activeComputersCount
Inactive (>30 days): $inactiveComputersCount

"@

### COMPUTERS BY OPERATING SYSTEM ###

# Gruppindelning och sortering
$osGroups = @($data.computers) | Group-Object -Property operatingSystem | Sort-Object -Property Count -Descending

$report += "`nCOMPUTERS BY OPERATING SYSTEM
------------------------------`n"

foreach ($os in $osGroups) {
    # Skydda mot division-by-zero
    $percent = if ($totalComputers -gt 0) {
        [math]::Round(($os.Count / $totalComputers) * 100)
    }
    else {
        0
    }

    $osName = if ($os.Name) { $os.Name } else { "<Unknown OS>" }
    $needsUpgrade = if ($osName -match "Windows 10") { " ⚠ Needs upgrade" } else { "" }

    $report += "{0,-35} {1,3} ({2}%)$needsUpgrade`n" -f ($osName.Trim()), $os.Count, $percent
}

# ===========================
#      SPARA TILL FIL       #
# ===========================
$reportPath = Join-Path -Path $PSScriptRoot -ChildPath "ad_audit_report.txt"
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`nAudit report skapad: $reportPath"


