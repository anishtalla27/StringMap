# Printed guitar OMR replacement evaluation — 2026-09-06

## Decision

**Do not adopt Flat as the default if StringMap must avoid per-scan operating costs. Pursue a current ReadScoreLib SDK quote/evaluation or retain a self-hosted recognizer plus correction. Do not replace HOMR in the shipping path yet.**

Starry is the only tested research candidate that materially recovered difficult printed guitar pages that HOMR missed, but it is not a usable replacement: its public page-layout path crashed on one of three trials, its downloadable model artifacts require deployment credentials, the inspected cluster service declares itself `UNLICENSED`, and the complete service/model combination has no verified commercial license. The newly released open-source Transcoda model also failed the project accuracy gate. More untargeted GitHub searching is now lower-value than testing a licensable production engine on the locked pack.

The most immediately testable candidate is **Flat OMR**. Its documented Jobs API accepts photos/PDFs and returns MusicXML/MIDI, explicitly permits commercial customer-upload workflows, and exposes mobile-oriented page-by-page job capture. It fits StringMap's existing recognition-service architecture, but requires a Flat account/token and page credits. The best native alternative is **ReadScoreLib**, the on-device recognition engine behind PlayScore 2 and a product licensed to other developers. Its old public SDK description is no longer downloadable from its original URL, so current iOS deliverables, accuracy, and commercial terms require direct confirmation from Organum before treating it as available.

Flat's live catalog is a material product constraint: 30 pages cost $9.99 ($0.333/page), 70 cost $18.99 ($0.271/page), 300 cost $49.99 ($0.167/page), 1,000 cost $149 ($0.149/page), and 3,000 cost $300 ($0.10/page), before applicable tax. These are one-time credit packs rather than a subscription, but a successful customer scan always consumes capacity. Opuscan was installed and accepted the locked Fantasy image; conversion stopped before purchase because the app had zero credits. No charge or recognition occurred.

For accuracy qualification before API integration, use **Opuscan for macOS**: Tutteo documents that Opuscan and Flat OMR use the same in-house recognition engine, and the Mac app can run without a Flat account and export MusicXML. Installation was initiated from the Mac App Store on 2026-09-06 and is waiting for the user's required App Store identity confirmation. Page conversion may still require purchasing credits.

The current HOMR cohort remains the shipping baseline until those three blockers are closed.

## Direct benchmark results

All references were kept out of inference. Scores below compare recognizer output with the repository's provisional written-score references. These are controlled photo simulations, not real phone-camera qualification.

| Candidate / input | Written pitch F1 | Onset F1 | Duration F1 | Exact note-event F1 | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Current HOMR, 15-page cohort | 88.9% | 61.0% | 85.7% | 36.0% | Baseline; only 5/15 pages tab-playable |
| Starry, Fantasy p.5 flat | 100.0% | 99.1% | 98.5% | **97.1%** | Recovered a page HOMR failed completely; 343 recognized and 343 reference pitches |
| Starry, Galliard p.27 hard shadow | 99.4% | 99.4% | 95.2% | **90.6%** | Recovered a page HOMR failed completely; one extra measure and three extra notes |
| Starry, Fancy p.6 tilted | — | — | — | — | Full pipeline failed in layout: `Cannot set properties of null (setting 'areas')` |
| Starry, Fancy p.6 StringMap-normalized retry | — | — | — | — | Same layout failure; normalization alone does not fix it |
| Transcoda, Fantasy p.5 flat | 79.9% | 23.4% | 94.7% | **2.2%** | Reject: output converted, but timing/voice structure did not match; StringMap also rejected the generated multi-part MusicXML |
| Transcoda, Fancy p.6 tilted | 76.1% | 73.3% | 89.9% | **5.7%** | Reject: output converted, but exact events failed; StringMap rejected an unsupported grace note |
| Transcoda, Galliard p.27 hard shadow | — | — | — | — | Reject: generated `**kern` spine structure could not be converted (`Could not determine spineType`) |
| Polyphonic-TrOMR, three real staff crops | 67.5–96.4% | not structurally reliable | 90.9–94.7% | **2.6–10.0%** | Reject: marginal pitch is good, but independent voice timing is not represented reliably |
| Sheet Music Transformer camera-grandstaff | — | — | — | — | Reject: checkpoint is trained for two-staff piano systems; guitar crop produced invalid/runaway beKern |
| LEGATO public demo | — | — | — | — | Reject for now: API failed on both uploads and the built-in Bach example also returned `Error` |

Additional Starry checks:

- Fantasy: 20 measures; 333 exact events, 10 missing, 10 extra; 87/93 complete chord onsets; solver reported 19 solved measures, one issue, zero fatal, quality 0.913.
- Galliard: 37 recognized measures versus 36 in the provisional reference; 216 exact events, 21 missing, 24 extra; 39/56 complete chord onsets; solver reported 36 solved measures, zero issue/fatal, quality 0.987.
- These results substantially exceed the current cohort-wide HOMR exact event F1 of 0.360, but three pages are not enough to claim release readiness.

Machine-readable results are in `recognizer-replacement-results.json` beside this report.

## Open-source options reviewed

### Worth pursuing

- **Acai OMR** — MIT and has a published checkpoint, but it is pianoform-specific, expects a two-staff single system, and the checkpoint is about 1.2 GB. It is a lower-priority experiment, not a likely guitar-photo replacement.

### Tested and rejected for StringMap's first release

- **Polyphonic-TrOMR** — Apache-2.0 and locally runnable, but its representation deliberately omits voice information. That makes it unsuitable for tempo-correct playback of polyphonic guitar notation even when isolated pitch/duration scores look respectable.
- **Sheet Music Transformer** — MIT, but the available camera model targets two-staff piano grandstaff systems. The current repository revision is also incompatible with its 2024 public checkpoint; the matching historical revision ran, but did not generalize to a single guitar staff.
- **LEGATO** — MIT code, but the current model depends on a gated Llama 3.2 11B Vision base and the public service failed during evaluation. Runtime, model-license, and operational reliability are poor fits today.
- **Transcoda** — AGPL-3.0 code with a public 59M-parameter checkpoint. The exact released checkpoint was run locally on three locked guitar pages with references kept out of inference. Two outputs converted but scored only 2.2% and 5.7% exact written note-event F1; the third had invalid spine structure. It is not a replacement, even though its compact model could theoretically be optimized for mobile.
- **Starry** — impressive two-page research result, but reject as a product dependency unless its authors provide both authorized weights and explicit commercial licensing for the entire deployed stack.
- **ScoreFlip** — reject as non-credible. Its advertised App Store URL returned 404, and inspection of the public Image-to-MusicXML page's shipped JavaScript showed simulated progress and canned MusicXML generation instead of an image-recognition request. Marketing accuracy claims are not evidence of a working recognizer.
- **SQOMR** — MIT research code, but no bundled pretrained checkpoint suitable for a direct evaluation.
- **tf-end-to-end** — MIT with pretrained models, but monophonic only; it cannot satisfy stacked-note/polyphonic guitar requirements.
- **MuSViT / U-MusT** — research options with noncommercial licensing and/or gated piano-oriented models; unsuitable for a commercial first release.

## What is still needed

1. Decide whether any per-page operating cost is acceptable. If not, do not buy Flat/Opuscan credits or build the Flat adapter.
2. Request a current ReadScoreLib evaluation SDK and commercial terms from Organum, specifically asking about fixed licensing versus per-scan royalties and current iOS/Swift support.
3. If a small paid evaluation is acceptable, buy only the minimum Opuscan pack and use it to qualify the Flat engine before any API integration work.
4. Convert the winner's MusicXML into the existing `NormalizedScore` path; do not build a new renderer, player, or fretboard engine.
5. Keep HOMR and manual correction as fallback until the candidate passes native import, rendered-note playback at multiple BPM values, and fretboard mapping.
6. Require at least 90% exact note-event F1 across the locked provisional cohort, no dropped staves/voices, no regression on the easy pages, and deterministic failures that enter review instead of returning misleading playable output.
7. Audit the references and test new, genuinely independent real iPhone photos before making a release claim.

## Short GPT-6 Astra goal prompt

> Make StringMap's printed-guitar photo recognition release-ready; work only on scanning accuracy. Evaluate Flat OMR first and ReadScoreLib second against all 15 locked pages, keeping references out of inference. Feed the winning MusicXML into the existing `NormalizedScore`, notation, BPM playback, and fretboard pipeline. Require at least 90% exact pitch/onset/duration event F1, no dropped staves or voices, and reviewable failures before replacing HOMR. Continue autonomously and ask only when an account token, page credits, SDK trial, commercial terms, or physical-device input is genuinely required.

## Primary project links

- Starry: https://github.com/FindLab-org/starry
- Starry technical overview and demo: https://huggingface.co/blog/k-l-lambda/starry
- ReadScoreLib/PlayScore company information: https://www.playscore.co/about-playscore-2/
- ReadScoreLib developer-licensing interview: https://blog.dorico.com/2021/09/an-interview-with-playscore-creator-anthony-wilkes/
- PlayScore 2 evaluation app: https://apps.apple.com/us/app/playscore-2/id1449591118
- Flat OMR API: https://flat.io/developers/docs/api/omr/
- Opuscan: https://www.opuscan.com/
- Transcoda: https://github.com/btrkeks/transcoda
- Transcoda checkpoint: https://huggingface.co/btrkeks/transcoda-59M-zeroshot-v1
- Polyphonic-TrOMR: https://github.com/NetEase/Polyphonic-TrOMR
- Polyphonic-TrOMR paper: https://archives.ismir.net/ismir2021/paper/000020.pdf
- Sheet Music Transformer: https://github.com/antoniorv6/SMT
- Camera-grandstaff checkpoint: https://huggingface.co/antoniorv6/smt-camera-grandstaff
- LEGATO: https://github.com/guang-yng/legato
- Acai OMR: https://github.com/jsnchon/acai-omr
- SQOMR: https://github.com/MALerLab/sqomr
- tf-end-to-end: https://github.com/OMR-Research/tf-end-to-end
- MuSViT: https://github.com/OMR-PRAIG-UA-ES/MuSViT
- U-MusT: https://github.com/MALerLab/U-MusT
