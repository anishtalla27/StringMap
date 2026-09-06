# Starry integration: access checkpoint

## Current decision

Keep HOMR as the default. Starry is not integrated or deployed. The requested experimental integration is paused at the explicit model/license access prerequisite, not at an accuracy or implementation difficulty.

The replacement report was read first. Its two successful Starry trials remain comparative evidence only; they do not qualify all 15 pages. The current goal requires **each** locked printed page to reach at least 90% exact note-event F1, with no dropped staves or voices. An aggregate average is insufficient.

## Access rechecked on 2026-09-06

- The public [Starry repository](https://github.com/FindLab-org/starry) says the core code will be organized and released. Its root listing has no explicit license.
- The public [Space source](https://huggingface.co/spaces/k-l-lambda/starry/tree/main) is available. The locally inspected checkout is revision `3584b5f328714bafebebeb5cc3667c30981bb711`.
- Its `docker-entrypoint.sh` sets `HF_REPO=k-l-lambda/starry` and retrieves `starry-dist/models.yaml` using `HF_TOKEN` before resolving the model files.
- A fresh unauthenticated GET to `https://huggingface.co/k-l-lambda/starry/resolve/main/starry-dist/models.yaml` returned **HTTP 401**. This establishes that anonymous access failed; it does not establish which account or permission would grant access. No credentials were searched for or exposed.
- `backend/cluster-server/package.json` declares `private: true` and `license: UNLICENSED`. Another component declaring ISC does not establish permission for the complete service and weights.
- No Starry weights were downloaded, no upstream implementation was copied into StringMap, no customer endpoint was changed, and no author message was sent.

## Exact external input needed

Obtain an author-approved model download/release and explicit terms covering commercial hosted recognition, the required service components, and the model weights. Establish whether redistribution is permitted or whether the deployment must download private artifacts. Credentials should be installed locally through the provider's authentication flow, never pasted into a task or committed.

Draft for the authors (not sent):

> We are evaluating Starry for StringMap, an iPhone/iPad app that converts printed single-part guitar notation into reviewed notes, tablature, and playback. Two public-demo trials were promising. May we commercially self-host the required Starry recognition, layout, regulation/BeadSolver, and export components and model weights? Please provide the applicable licenses and an authorized model download or deployment route, including any redistribution restrictions. We also need a documented way to submit externally detected single-staff regions when full-page layout fails. We can share benchmark findings and a reproducible layout failure.

## Work to resume after access

1. Pin authorized source and model hashes; implement a disabled-by-default experimental adapter with HOMR fallback. Do not use the public demo as the application's backend.
2. Verify Starry's actual region and regulated-score interfaces. Reuse StringMap preprocessing and complete staff detection if layout fails; preserve all detected regions and fail into review if coverage cannot be established.
3. Convert regulated measures through the existing MusicXML importer or directly into `NormalizedScore`. Preserve event identity, pitch/octave, chords, voice membership, rests, ties, exact onset/duration, signatures, and review warnings. Do not infer missing voices from a convenient tab assignment.
4. Run all 15 `printed_guitar` entries in the locked `manifest.csv`, keeping reference files out of recognition. Preserve raw results and independently verify staff/voice coverage; successful XML export is not coverage evidence.
5. For every page, verify exact rendering, playback timing at multiple selected BPM values, and guitar-fretboard/source-note correspondence. Report recognition F1 separately from faithful downstream playback.
6. Switch no default until every page reaches the requested threshold and coverage checks pass. Provisional references and simulated photo conditions still do not establish physical-camera release qualification.

The goal remains incomplete. The adapter, hybrid layout path, full 15-page Starry benchmark, and downstream Starry playback/fretboard validation have not been completed.
