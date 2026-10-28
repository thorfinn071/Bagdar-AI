param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$root = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path (Join-Path $root 'wav') | Out-Null
$manifestPath = Join-Path $root 'sapi-manifest.json'
if (Test-Path -LiteralPath $manifestPath) { Write-Output 'SAPI holdout already exists'; exit 0 }
$protocol = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'protocol.json') -Raw | ConvertFrom-Json
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$records = @()
$sequence = 0
try {
    foreach ($spec in @(@{name='Microsoft Irina'; language='ru'}, @{name='Microsoft Pavel'; language='ru'}, @{name='Microsoft Zira Desktop'; language='en'})) {
        $synth.SelectVoice($spec.name)
        $lang = $spec.language
        $phrases = @()
        foreach ($text in $protocol.positivePhrases.$lang) { $phrases += @{ text=$text; target=$true } }
        foreach ($text in $protocol.negativePhrases.$lang.test) { $phrases += @{ text=$text; target=$false } }
        foreach ($rate in @(-2,0,2)) {
            $synth.Rate = $rate
            foreach ($phrase in $phrases) {
                $sequence++
                $id = 'sapi-held-{0:D4}' -f $sequence
                $path = Join-Path $root ('wav/' + $id + '.wav')
                if (-not (Test-Path -LiteralPath $path)) {
                    $synth.SetOutputToWaveFile($path, $format)
                    $synth.Speak($phrase.text)
                    $synth.SetOutputToNull()
                }
                $records += @{ id=$id; wav=('wav/' + $id + '.wav'); target=$phrase.target; split='test'; language=$lang; text=$phrase.text; rate=$rate; speakerGroup=('sapi-' + $spec.name); origin='synthetic_sapi'; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
            }
        }
    }
} finally { $synth.Dispose() }
@{schema=1; recordings=$records} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
