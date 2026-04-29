param(
    [Parameter(Mandatory = $true)]
    [string]$Username,
    [Parameter(Mandatory = $true)]
    [string]$Password,
    [Parameter(Mandatory = $true)]
    [string]$TokenFile
)

$body = @{
    username = $Username
    password = $Password
} | ConvertTo-Json -Compress

try {
    $response = Invoke-RestMethod -Uri 'http://localhost:8000/api/v1/chat/authenticate' -Method Post -ContentType 'application/json' -Body $body
    if (-not $response.access_token) {
        exit 1
    }

    Set-Content -Path $TokenFile -Value $response.access_token -Encoding ASCII
    exit 0
}
catch {
    exit 1
}