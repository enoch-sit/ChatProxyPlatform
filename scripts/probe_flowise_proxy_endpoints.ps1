param(
    [Parameter(Mandatory = $true)]
    [string]$Username,
    [Parameter(Mandatory = $true)]
    [string]$Password,
    [string]$BaseUrl = 'http://localhost:8000',
    [string]$FlowiseApiKey = ''
)

$body = @{
    username = $Username
    password = $Password
} | ConvertTo-Json -Compress

Write-Host '  --- POST /api/v1/chat/authenticate (bridge login path) ---'

try {
    $authResponse = Invoke-RestMethod -Uri "$BaseUrl/api/v1/chat/authenticate" -Method Post -ContentType 'application/json' -Body $body
}
catch {
    Write-Host '  [WARN] bridge authenticate failed.'
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        Write-Host ("  status={0}" -f [int]$_.Exception.Response.StatusCode)
    }
    exit 1
}

if (-not $authResponse.access_token) {
    Write-Host '  [WARN] bridge authenticate returned no access token.'
    exit 1
}

$headers = @{ Authorization = "Bearer $($authResponse.access_token)" }
Write-Host '  [OK] bridge authenticate returned an access token.'

function Invoke-ProbeGet {
    param(
        [string]$Label,
        [string]$Url,
        [hashtable]$Headers
    )

    Write-Host ''
    Write-Host "  --- $Label ---"
    try {
        $response = Invoke-WebRequest -Uri $Url -Headers $Headers -Method Get -UseBasicParsing
        Write-Host ("  status={0}" -f [int]$response.StatusCode)
        Write-Host '  body:'
        if ($response.Content) {
            Write-Host $response.Content
        }
        else {
            Write-Host '  <empty>'
        }
    }
    catch {
        $statusCode = $null
        $content = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $content = $reader.ReadToEnd()
                $reader.Close()
            }
            catch {
            }
        }

        if ($statusCode -ne $null) {
            Write-Host ("  status={0}" -f $statusCode)
        }
        else {
            Write-Host '  status=<request failed>'
        }

        Write-Host '  body:'
        if ($content) {
            Write-Host $content
        }
        else {
            Write-Host ("  {0}" -f $_.Exception.Message)
        }
    }
}

function Invoke-ProbePostJson {
    param(
        [string]$Label,
        [string]$Url,
        [hashtable]$Headers,
        [object]$Body
    )

    Write-Host ''
    Write-Host "  --- $Label ---"
    try {
        $jsonBody = $Body | ConvertTo-Json -Compress
        $response = Invoke-WebRequest -Uri $Url -Headers $Headers -Method Post -ContentType 'application/json' -Body $jsonBody -UseBasicParsing
        Write-Host ("  status={0}" -f [int]$response.StatusCode)
        Write-Host '  body:'
        if ($response.Content) {
            Write-Host $response.Content
        }
        else {
            Write-Host '  <empty>'
        }
    }
    catch {
        $statusCode = $null
        $content = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $content = $reader.ReadToEnd()
                $reader.Close()
            }
            catch {
            }
        }

        if ($statusCode -ne $null) {
            Write-Host ("  status={0}" -f $statusCode)
        }
        else {
            Write-Host '  status=<request failed>'
        }

        Write-Host '  body:'
        if ($content) {
            Write-Host $content
        }
        else {
            Write-Host ("  {0}" -f $_.Exception.Message)
        }
    }
}

Invoke-ProbeGet -Label 'GET /api/v1/chatflows/my-chatflows (auth)' -Url "$BaseUrl/api/v1/chatflows/my-chatflows" -Headers $headers
Invoke-ProbeGet -Label 'GET /api/v1/chat/sessions (auth)' -Url "$BaseUrl/api/v1/chat/sessions" -Headers $headers
Invoke-ProbeGet -Label 'GET /api/v1/admin/chatflows' -Url "$BaseUrl/api/v1/admin/chatflows" -Headers $headers
Invoke-ProbeGet -Label 'GET /api/v1/admin/chatflows/stats' -Url "$BaseUrl/api/v1/admin/chatflows/stats" -Headers $headers
Invoke-ProbeGet -Label 'GET /api/v1/admin/settings/flowise-api-key' -Url "$BaseUrl/api/v1/admin/settings/flowise-api-key" -Headers $headers

if ($FlowiseApiKey) {
    Invoke-ProbePostJson -Label 'POST /api/v1/admin/settings/flowise-api-key' -Url "$BaseUrl/api/v1/admin/settings/flowise-api-key" -Headers $headers -Body @{ api_key = $FlowiseApiKey }
    Invoke-ProbePostJson -Label 'POST /api/v1/admin/settings/flowise-api-key/test' -Url "$BaseUrl/api/v1/admin/settings/flowise-api-key/test" -Headers $headers -Body @{ api_key = $FlowiseApiKey }
}