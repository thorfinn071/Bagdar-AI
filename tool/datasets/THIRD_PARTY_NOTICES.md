# Research bundle notices

These assets support reproducible software experiments. They do not establish
perception accuracy or authorize walking assistance.

- The research Kazakh speech bundle contains the unmodified
  `vosk-model-small-kz-0.42` model from
  [the Vosk model catalogue](https://alphacephei.com/vosk/models), its upstream
  README, Apache 2.0 license and Bagdar notice. The license is also available
  at [licenses/APACHE-2.0.txt](licenses/APACHE-2.0.txt).
- The three candidate ONNX detector exports are identified in
  [the candidate manifest](../../model_export/candidates/manifest.json), which
  records their source checkpoint hashes, export commands and Ultralytics
  8.4.41 provenance. That manifest identifies their license as AGPL-3.0.
  The license supplied with that installed Ultralytics package is preserved
  at [licenses/AGPL-3.0.txt](licenses/AGPL-3.0.txt). Upstream source:
  [Ultralytics v8.4.41](https://github.com/ultralytics/ultralytics/tree/v8.4.41).
- Synthetic scene fixtures, cached predictions, historical receipts and frozen
  source snapshots retain their original paths and identities. Source scripts
  and experiment protocols remain in the repository.
- The historical profiling executable is included only because an existing
  integrity contract records its checksum. Dataset restoration does not run it.

The repository's MIT license does not replace the licenses or provenance
requirements of third-party models and code. Candidate models remain research
artifacts; bundling does not promote them into the application's production
model selection.
