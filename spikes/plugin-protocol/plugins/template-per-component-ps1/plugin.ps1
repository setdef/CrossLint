# PowerShell plugin: every component has an HTML template. The Windows counterpart of plugin.sh,
# with ConvertFrom-Json in place of jq.
$ErrorActionPreference = 'Stop'

while ($null -ne ($line = [Console]::In.ReadLine())) {
  $request = $line | ConvertFrom-Json
  if ($request.method -eq 'handshake') {
    $reply = @{ id = $request.id; result = @{ protocol = 1; name = 'template-per-component' } }
  } elseif ($request.method -eq 'check') {
    $violations = @()
    foreach ($item in $request.params.items) {
      if (-not $item.companions.template.exists) {
        $violations += @{ rule = 'component-has-template'; path = $item.path; message = "no template at $($item.companions.template.path)" }
      }
    }
    $reply = @{ id = $request.id; result = @{ violations = [object[]]$violations } }
  } else {
    $reply = @{ id = $request.id; error = @{ code = 'unknown-method'; message = $request.method } }
  }
  [Console]::Out.WriteLine((ConvertTo-Json -InputObject $reply -Depth 6 -Compress))
  [Console]::Out.Flush()
}
