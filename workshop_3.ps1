# Läs in JSON
$data = Get-Content -Path "ad_export.json" -Raw -Encoding UTF8 | ConvertFrom-Json

# Nu kan du komma åt data som objekt

# notera: detta skrivs till terminalen också (utan Write-Host)

#$data.domain                    # "techcorp.local"

#$data.users                     # Array med alla användare

#$data.users[0].displayName      # "Anna Andersson"

#$data.users.Count               # Antal användare


#Write-Host $data.users[1].displayName


#$data.domain
#$data.export_date

# Exempel: Användare som inte loggat in på 30 dagar


$thirtyDaysAgo = (Get-Date).AddDays(-30)

$inactiveUsers = $data.users | Where-Object { 

    [datetime]$_.lastLogon -lt $thirtyDaysAgo
}

$report = ""

$report += @"

Domännamn: $($data.domain)
Exporteringsdatum: $($data.export_date)

"@

foreach ($user in $inactiveUsers) {
    $report += @"

Namn: $($user.displayName)
E-Post: $($user.email)
Senast inloggad: $($user.lastLogon)

"@
}

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

Write-Host $report