# Recognition hosting — Hobby active, deployment pending

User authorized up to $20/month for StringMap recognition hosting on September 5, 2026. The user purchased Hobby; account access is verified and an empty StringMap recognition service is created. No container is deployed.

The previous oemer estimate is superseded by measured HOMR performance. Hobby is active. Verified limits: $10 compute alert, $15 compute hard stop (conservative headroom within the $20 budget), and $0 Railway Agent limit. The Linux ARM64 container now builds and passes the 150-input controlled-image run. Real Railway hardware, HTTPS and App Attest remain to be validated.

## Measured local Linux configuration

- Python 3.12.13, pinned HOMR `457e7c6518a10ba755db2e60883419e56c4d7369`, ONNX CPU inference.
- Local Colima Linux ARM64 VM: 2 CPUs, 4 GB RAM. Container limit: 2 CPUs and 3 GiB; one recognizer subprocess at a time.
- 183 jobs including the initial startup-race run, negatives, and the complete 150-input validation: median 2.81 s processing / 4.95 CPU-seconds; maximum 15.73 s / 28.73 CPU-seconds.
- Container memory high-water mark: 1,232,928,768 bytes (1.15 GiB). Lifetime child peak RSS: 1,247,158,272 bytes. Idle Docker memory: 59.16 MiB; idle CPU snapshot: 0.30%.
- No image/intermediate directories remained after the batch. Exact model and corresponding-source checks passed. App worker runs as UID 10001; local Python environments are excluded from the image.

Evidence: `artifacts/engine-evaluation/linux-resources-summary.json`, `linux-container.log`, `container-validation.json`, `linux-http-ready-v2/`, `linux-rhythm-v2/`. Xcode and Simulator also ran on the Mac, so these are observed local Linux measurements, not isolated Railway throughput promises. API benchmark times include polling overhead.

## Proposed staging allocation and cost

Use Railway Hobby, one replica, a 2-vCPU/3-GB ceiling, and a private 1-GB volume. Free's published 0.5-GB allowance is insufficient. Keep defaults of 20 scans/device/hour and 100/day globally, four active/queued jobs, one per device, and a 180-second total recognition deadline.

Railway rates checked September 5, 2026: CPU $0.00000772/vCPU-second, memory $0.00000386/GB-second, volume $0.00000006/GB-second, egress $0.05/GB; Hobby has a $5 monthly minimum including usage credit. [Published pricing](https://railway.com/pricing).

Using median CPU time and conservatively charging 1.25 GB throughout a 2.81-second page gives approximately $0.000052 active compute per page. The slowest observed case gives approximately $0.00030. An entire 180-second timeout at both CPU cores and all 3 GB costs approximately $0.0049. These calculations exclude idle API, storage, traffic, build costs and provider-specific memory accounting.

| Monthly scans | Observed-workload active compute estimate | Initial monthly planning budget |
| --- | --- | --- |
| 100 | $0.01–0.03 | $5–10 |
| 1,000 | $0.05–0.30 | $5–10 |
| 3,000 | $0.16–0.90 | $5–10 |

A month of worst-case timeouts could consume about $15 active compute instead. **Approved authorization: up to $20/month for StringMap recognition hosting**, with an alert at $10 and an enforced stop at $20 where the provider permits a limit scoped to this service. Do not modify a shared account's spending limit if it affects unrelated projects. Confirm actual billing controls before opening public traffic; request a revised limit if the provider cannot enforce this scope.

Before production: test authenticated HTTPS on a physical signed build, cancellation/restart/expiry on the hosted volume, provider log retention, readiness monitoring and billing alerts. Keep the source-offer endpoint accessible. Do not enable volume snapshots/backups containing temporary scans. The Apple App ID prefix and allowed distributed builds must be verified from actual signing/provisioning, not inferred from a certificate name.

## Billing controls verified September 5, 2026

Railway documents compute hard limits at workspace scope, covering CPU, memory, storage and egress. Inspect the signed-in workspace before changing limits; use a StringMap-only workspace to avoid shutting down unrelated projects. Configure a $10 alert and a conservative hard limit within the approved $20 total monthly budget after checking subscription and applicable taxes. Railway Agent usage is separate and is not needed for this deployment. Source: https://docs.railway.com/pricing/cost-control

Live provisioning details and outstanding gates are recorded in `hosting-deployment.json`. Apple signing is still unverified; production app identity is intentionally unset until obtained from a real provisioning profile.

## Dense guitar-page checkpoint, September 6, 2026

The rebuilt crop-recovery container was tested locally with the same 2-CPU/3-GiB limit. The supplied seven-staff Fancy page took **107.17 seconds and 200.87 CPU-seconds**; the service's lifetime child peak RSS reached **1,776,025,600 bytes**. The returned 332-note score matches the macOS result (96.4% provisional written note-event F1), and its guitar tab/notation MIDI checks pass. Three short controls preserve 112/112 reference events. These measurements include concurrent Mac/Xcode work and are not Railway throughput promises.

The earlier 2.81-second median and table describe short controlled inputs and must not be generalized to dense classical-guitar pages. Using measured CPU time and conservatively charging the full 3 GB throughout this page gives approximately **$0.00279 active compute per page**, or **$2.79 per 1,000 / $8.38 per 3,000** similar pages, before idle service, volume, traffic, builds and taxes. This is a workload calculation, not a hosting quote; the existing spending cap remains unchanged. Rates were rechecked against [Railway pricing](https://railway.com/pricing) on September 6.

Evidence: `artifacts/crop-retry-linux-build.log`, `artifacts/crop-retry-linux-server.log`, `artifacts/crop-retry-linux-controls/`, `artifacts/crop-retry-linux-fancy/`. No hosted deployment or billing change was made.
