# Storyteller on skepsis

The library is served at `https://storyteller.kroac.net`. Source media is copied into Storyteller's own assets; BookOrbit's library mount is read-only. Do not delete source files or caches to diagnose slow processing.

The container has a four-CPU allowance and 4 GiB maximum memory. Native settings use whisper.cpp, the `tiny` model (`tiny.en` for English), one transcription at a time, and turbo setting 1. Turbo 1 already starts Whisper with four CPU threads; it does not mean one CPU thread. The worker runs one book at a time. Keep these settings unless measured throughput or alignment quality justifies a change; extra parallel tracks would share the same CPU allowance.

Use BCP 47 language codes: the six Stormlight entries had `english`, which this version passes through and uses to select a multilingual model. Their language was corrected to `en` through the native metadata API. All eight processing/queued books now use `en`. Check this when importing further books.

On 2026-09-21, investigation of slow overnight transcription found that all five previously aligned books, including Elantris, recorded `alignedWith=whisper.cpp:tiny` from Storyteller 2.3.16. The new run used `small`; its initial two-CPU limit also slowed early work before the allowance was raised to four. The current binary reports AVX2/FMA support. Overnight small.en processing was active, completing 9.11 hours of audio in 4.18 hours across the last twenty saved tracks. The 42 saved Rhythm of War tracks covered 22.16 of 57.45 audio hours, despite the native UI showing about 30%.

A controlled benchmark used the installed whisper.cpp 1.8.3-st.2 CPU binary and the same 120-second excerpt, beginning ten minutes into Rhythm of War's third track. Only the active transcription subprocess was briefly suspended for the comparison, then resumed. The production CPU allowance and Whisper options were retained: English, flash attention, non-speech suppression, one processor, and full JSON timestamps.

| Model | CPU threads | Wall time |
| --- | --- | --- |
| small.en | 4 | 59.3 seconds |
| tiny.en | 4 | 11.4 seconds |
| tiny.en | 2 | 18.0 seconds |

Tiny.en was 5.2 times faster on this excerpt, with some additional word/name errors. This is a transcription benchmark, not proof of finished alignment quality or a whole-book ETA. The native settings API changed only `whisperModel` to `tiny`. Rhythm of War was stopped and continued without a restart argument; all 42 completed JSON checkpoints were hash-verified unchanged and the entire queue order was retained. The active process was verified to use `ggml-tiny.en.bin`. Existing small-model checkpoints remain valid cached inputs; do not discard them merely to make the model consistent. Check the finished readaloud in the reader before deciding that a larger model or paid service is necessary.

The first full chapter after the change (track 43, 37m54s of audio) completed in 3m42s, about 10.2 times real time. Its saved transcript contained 5,115 words with ordered timestamps through the end of the chapter, and processing advanced to track 44. This validates ongoing transcription, not final ebook/audio synchronization. [Storyteller recommends tiny for most English books](https://storyteller-platform.dev/docs/settings/#transcribing-locally); check unusual names and alignment in the finished result.

Read the live queue with `npm run --silent books -- queue` from `/home/avirut/qm`. This uses the supported Storyteller API and reads cached transcript-file counts; it does not modify the database. Check `docker stats --no-stream storyteller`, `docker top storyteller`, and recent `docker logs` to distinguish active transcription from a stopped worker. A chapter's transcript is saved when that chapter finishes, so a quiet checkpoint timestamp alone is not evidence of a stall.

In web-v2.14.21, the UI has a current-book indicator but does not expose the stored queue order. Stage/progress reporting also has known limitations confirmed in the shipped source: stages change only on progress callbacks, the last split-track update can exceed 100%, and cached transcript progress can overcount by one. Continuing cached work can also drop the displayed percentage to zero while the saved transcripts are reused. Reported percentages are per stage, not whole-book percentages. The queue command includes actual completed-track counts alongside the app's reported percentage.

The owner requested Rhythm of War first. It was moved ahead of Death’s End, The Way of Kings, Oathbringer, Words of Radiance, Edgedancer, Dawnshard, and The Three-Body Problem using supported stop/continue APIs. The Three-Body Problem's eight completed transcript files were retained. Always read the live queue before making further changes.

To reorder, hold QM's `var/books/operations.lock` so its sync cannot race the change. Use `DELETE /api/v2/books/<uuid>/process` to stop/dequeue, wait for STOPPED, then `POST` to the same endpoint without a restart argument to continue with cached work. Never delete the book or request a full/transcription restart for queue ordering. After stopping an active job, verify that the next queued book actually starts: this version left the next job queued until it was explicitly stopped and continued. A queued label alone does not prove a worker is running.

Stopping a job can leave its old whisper-cli subprocess consuming CPU after a new worker starts. Inspect process IDs, input WAV paths, model arguments, and state. If the cancelled job's exact subprocess remains active, terminate only that verified abandoned process; do not kill all Whisper processes or restart unrelated services. A zombie process consumes no CPU. Remove only abandoned temporary audio after checking that no active transcription uses it.
