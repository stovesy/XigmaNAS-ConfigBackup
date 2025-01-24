# XigmaNAS details
$XigmaNAS_IP = "" # Replace with your XigmaNAS IP address
$Username = "" # Replace with your XigmaNAS username
$Password = "" # Replace with your XigmaNAS password
$BackupPath = "C:\" # Replace with your desired backup folder
$BackupFileName = "XigmaNAS_Backup_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').config"
$BackupFilePath = Join-Path -Path $BackupPath -ChildPath $BackupFileName
$MaxBackupCount=50 # Number of backup files to keep in the BackupPath


# Create the backup directory if it doesn't exist
if (-not (Test-Path $BackupPath)) {
    New-Item -ItemType Directory -Path $BackupPath | Out-Null
}

# API Endpoints
$LoginUrl = "http://$XigmaNAS_IP/login.php"
$BackupUrl = "http://$XigmaNAS_IP/system_backup.php"

# Step 1: Open session and get login page
$Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$LoginPageResponse = Invoke-WebRequest -Uri $LoginUrl -WebSession $Session

# Step 2: Log in to establish session by sending form data
$LoginFormData = @{
    username = $Username
    password = $Password
}

$LoginResponse = Invoke-WebRequest -Uri $LoginUrl -Method POST -Body $LoginFormData -WebSession $Session

# Exit if login failed
if ($LoginResponse.StatusCode -ne 200 -or $LoginResponse.Content -match "login") {
    Write-Error "Login failed. Verify your credentials."
    return
}

Write-Host "Login successful!"

# Step 3: Extract PHPSESSID from the session cookies
$PHPSESSID = ($Session.Cookies.GetCookies($LoginUrl) | Where-Object {$_.Name -eq "PHPSESSID"}).Value
if (-not $PHPSESSID) {
    Write-Error "PHPSESSID cookie not found!"
    return
}

Write-Host "PHPSESSID cookie found: $PHPSESSID"

# Step 4: Get the system_backup page to retrieve the authtoken
$BackupPageResponse = Invoke-WebRequest -Uri $BackupUrl -WebSession $Session
$BackupPageHtml = $BackupPageResponse.Content

# Extract the authtoken from the backup page
$AuthtokenPattern = 'name="authtoken" type="hidden" value="([^"]+)"'
if (-not ($BackupPageHtml -match $AuthtokenPattern)) {
    Write-Error "Authtoken not found on the backup page."
    return
}

$Authtoken = $matches[1]
Write-Host "Authtoken extracted: $Authtoken"

# Step 5: Prepare the multipart/form-data request for the backup
$Boundary = "----WebKitFormBoundary" + [Guid]::NewGuid().ToString("N")
$SubmitData = @"
--$Boundary
Content-Disposition: form-data; name="submit"

download
--$Boundary
Content-Disposition: form-data; name="authtoken"

$Authtoken
--$Boundary

"@

# Step 6: Send the multipart/form-data request to download the backup
# HTTP Headers
$BackupHeaders = @{
    "Host" = $XigmaNAS_IP
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0"
    "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    "Accept-Language" = "en-GB,en;q=0.5"
    "Accept-Encoding" = "gzip, deflate"
    "Content-Type" = "multipart/form-data; boundary=$Boundary"
    "Origin" = "http://$XigmaNAS_IP"
    "Referer" = "http://$XigmaNAS_IP/system_backup.php"
    "Cookie" = "PHPSESSID=$PHPSESSID"
    "Upgrade-Insecure-Requests" = "1"
    "DNT" = "1"
    "Sec-GPC" = "1"
}

# Send the POST request for backup
Write-Host "Sending backup request..."
Invoke-WebRequest -Uri $BackupUrl -Method POST -Body $SubmitData -Headers $BackupHeaders -WebSession $Session -OutFile $BackupFilePath

# Check if the backup file was saved
if (-not (Test-Path $BackupFilePath)) {
    Write-Error "Failed to save the backup file."
    return
}

Write-Host "Backup saved successfully to: $BackupFilePath"

# Step 7: Backup retention logic
$BackupFiles = Get-ChildItem -Path $BackupPath -Filter "XigmaNAS_Backup_*.config" | Sort-Object LastWriteTime
$BackupCount = $BackupFiles.Count

if ($BackupCount -gt $MaxBackupCount) {
    $FilesToDelete = $BackupFiles | Select-Object -First ($BackupCount - $MaxBackupCount)
    foreach ($File in $FilesToDelete) {
        Remove-Item -Path $File.FullName -Force
        Write-Host "Deleted old backup: $($File.FullName)"
    }
}
