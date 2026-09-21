# Core software verification

Ordinary developer suite (NCNN reference corpus may skip):

```text
powershell -File tool/verify_core.ps1
```

Release-candidate mode: missing required Core fixtures **fail**, they do not skip.

```text
powershell -File tool/verify_core.ps1 -Rc
```

`-Rc` passes `--dart-define=BAGDAR_RC=true` so
`test/ncnn_reference_correlation_test.dart` executes and fails if
`test/fixtures/ncnn_contract/reference_outputs.json` is absent.

A green ordinary run is not a Core Safety RC. Hardware, TalkBack, walking,
and corpus gates remain separate.
