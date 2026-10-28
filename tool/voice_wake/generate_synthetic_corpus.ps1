param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$root = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $root | Out-Null
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$phrases = @(
    @{ text='Багдар'; target=$true },
    @{ text='Бағдар'; target=$true },
    @{ text='багаж'; target=$false },
    @{ text='Багдад'; target=$false },
    @{ text='благодарю'; target=$false },
    @{ text='дар'; target=$false },
    @{ text='богат'; target=$false },
    @{ text='не Багдар'; target=$false },
    @{ text='пример Багдар'; target=$false },
    @{ text='Багдар выключить микрофон'; target=$false },
    @{ text='проверь состояние камеры'; target=$false },
    @{ text='тишина вокруг'; target=$false }
)
$records = @()
$sequence = 0
try {
    foreach ($voice in @('Microsoft Irina', 'Microsoft Pavel')) {
        $synth.SelectVoice($voice)
        foreach ($rate in @(-2,0,2)) {
            $synth.Rate = $rate
            foreach ($phrase in $phrases) {
                $sequence++
                $name = 'sapi-{0:D3}.wav' -f $sequence
                $synth.SetOutputToWaveFile((Join-Path $root $name), $format)
                $synth.Speak($phrase.text)
                $synth.SetOutputToNull()
                $records += @{ id=('sapi-{0:D3}' -f $sequence); wav=$name; target=$phrase.target; text=$phrase.text; voice=$voice; rate=$rate; origin='synthetic_sapi'; language='ru'; speakerGroup=$voice }
            }
        }
    }
} finally { $synth.Dispose() }
@{ schema=1; evidence='synthetic_only'; sampleRate=16000; recordings=$records } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'manifest.json') -Encoding utf8
