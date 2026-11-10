/*
 * XMMS native OpenVMS MMOV output.
 * Copyright (C) 2026 OpenVMS-XMMS contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * MMOV callbacks are dispatched by mmeProcessCallbacks(), not by an AST.
 * Only the worker calls MMOV. Its callbacks record state and never call MMOV.
 * WAVEHDR addresses delivered to callbacks are temporary copies: dwUser is
 * the completion identity, not the WAVEHDR pointer or its original dwFlags.
 */
#include "config.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <pthread.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>
#include "xmms/plugin.h"
#include "mmov_api.h"

#ifdef __VMS
/* The MMOV client and callback ABI carry pointers in 32-bit values. */
typedef char mmov_requires_32_bit_pointers[(sizeof(void *) == 4) ? 1 : -1];
#endif

#define OUTPUT_DEVICE_ID 0 /* The first native waveform output device. */
#define SLOT_COUNT 4
#define POLL_USEC 5000
#define RESET_POLLS 400
#define SLOT_FREE 0
#define SLOT_READY 1
#define SLOT_ACTIVE 2
#define SLOT_PARTIAL 3
#define POSITION_INTERVAL_MS 1000
#define MIXER_INTERVAL_MS 1000

typedef struct {
    PCMWAVEFORMAT format;
    HWAVEOUT handle;
    MMTIME position;
    WAVEHDR header[SLOT_COUNT];
} MmovShared;

typedef struct {
    unsigned char *data;
    unsigned int token;
    int state;
    int frames;
} MmovSlot;

typedef struct {
    int running, initialized, finished, failed, closing, poisoned;
    int opened, close_seen, resetting;
    int rate, channels, sample_bytes, input_frame, slot_frames;
    AFormat format;
    int fill_slot, send_slot, desired_pause, hardware_pause, priming;
    int free_polls, force_start;
    int flush_request, flush_done, flush_time, base_time;
    unsigned int next_token;
    guint64 written_frames, submitted_frames, completed_frames, played_frames;
    guint64 position_wrap, next_position_poll;
    unsigned int previous_position, position_type;
    MmovShared *shared;
    MmovSlot slots[SLOT_COUNT];
} MmovState;

static MmovState state;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static pthread_t worker_thread;
static int worker_started, worker_quit, shutdown_registered;
static unsigned int mixer_request, mixer_done;
static int mixer_busy, mixer_set, mixer_left = -1, mixer_right = -1;
static DWORD mixer_desired, *mixer_shared;
static MMRESULT mixer_status, mixer_reported_error;
static guint64 mixer_cache_until;
static void mmov_close(void);
static void mmov_shutdown(void);
static void *worker(void *unused);

static guint64 clock_milliseconds(void)
{
    struct timeval now;
    if (gettimeofday(&now, NULL))
        return 0;
    return (guint64)now.tv_sec * 1000 + now.tv_usec / 1000;
}

/* Preserve one MMOV API thread while idle, playing, and between tracks. */
static int ensure_worker(void)
{
    int result;
    if (worker_quit)
        return 0;
    if (worker_started)
        return 1;
    if (!shutdown_registered) {
        if (atexit(mmov_shutdown)) {
            fprintf(stderr, "XMMS MMOV: cannot register audio cleanup\n");
            return 0;
        }
        shutdown_registered = 1;
    }
    result = pthread_create(&worker_thread, NULL, worker, NULL);
    if (result) {
        fprintf(stderr, "XMMS MMOV: pthread_create failed (%d)\n", result);
        return 0;
    }
    worker_started = 1;
    return 1;
}

/* Device volume is global in MMOV. Only a user's set_volume request writes it;
 * startup and polling merely query it. Query before SET also initializes the
 * legacy ENSAUDIO mixer cache before it can overwrite the first requested SET.
 * The returned word must be in MMOV shared memory, even while no stream is open.
 */
static void process_mixer(void)
{
    MMRESULT result;
    if (!mixer_shared)
        mixer_shared = (DWORD *)mmeAllocMem(sizeof(*mixer_shared));
    result = mixer_shared ? waveOutGetVolume(OUTPUT_DEVICE_ID, mixer_shared) :
                            MMSYSERR_NOMEM;
    if (result == MMSYSERR_NOERROR && mixer_set) {
        result = waveOutSetVolume(OUTPUT_DEVICE_ID, mixer_desired);
        if (result == MMSYSERR_NOERROR)
            result = waveOutGetVolume(OUTPUT_DEVICE_ID, mixer_shared);
    }
    mixer_status = result;
    if (result == MMSYSERR_NOERROR) {
        mixer_left = (int)((*mixer_shared & 0xffffUL) * 100UL / 65535UL);
        mixer_right = (int)(((*mixer_shared >> 16) & 0xffffUL) * 100UL / 65535UL);
        mixer_reported_error = MMSYSERR_NOERROR;
        mixer_cache_until = clock_milliseconds() + MIXER_INTERVAL_MS;
    } else {
        mixer_left = mixer_right = -1;
        mixer_cache_until = 0;
        if (result != mixer_reported_error)
            fprintf(stderr, "XMMS MMOV: device volume %s failed (MMRESULT 0x%08lx)\n",
                    mixer_set ? "change" : "query", (unsigned long)result);
        mixer_reported_error = result;
    }
    mixer_done = mixer_request;
    pthread_cond_broadcast(&changed);
}

/* Called with lock held. No MMOV call runs on the GUI or decoder thread. */
static int request_mixer(int setting, DWORD value)
{
    unsigned int request;
    int okay;
    if (state.poisoned || !ensure_worker())
        return 0;
    while (mixer_busy)
        pthread_cond_wait(&changed, &lock);
    if (state.poisoned || worker_quit)
        return 0;
    mixer_busy = 1;
    mixer_set = setting;
    mixer_desired = value;
    request = ++mixer_request;
    pthread_cond_broadcast(&changed);
    while (mixer_done != request)
        pthread_cond_wait(&changed, &lock);
    okay = mixer_status == MMSYSERR_NOERROR;
    mixer_busy = 0;
    pthread_cond_broadcast(&changed);
    return okay;
}

static int count_slots(int kind)
{
    int i, count = 0;
    for (i = 0; i < SLOT_COUNT; ++i)
        if (state.slots[i].state == kind)
            ++count;
    return count;
}

/* The producer owns at most one partial slot. Seal only a full buffer or
 * a short tail requested by the decoder's drain/backpressure protocol. */
static void seal_partial(void)
{
    MmovSlot *slot = &state.slots[state.fill_slot];
    if (slot->state != SLOT_PARTIAL || !slot->frames)
        return;
    if (++state.next_token == 0)
        ++state.next_token;
    slot->token = state.next_token;
    slot->state = SLOT_READY;
    state.fill_slot = (state.fill_slot + 1) % SLOT_COUNT;
    pthread_cond_broadcast(&changed);
}

static void mmov_error(const char *operation, MMRESULT status)
{
    if (!state.failed)
        fprintf(stderr, "XMMS MMOV: %s failed (MMRESULT 0x%08lx)\n",
                operation, (unsigned long)status);
    state.failed = 1;
    pthread_cond_broadcast(&changed);
}

static void callback(HWAVEOUT handle, UINT message, DWORD instance,
                     LPARAM parameter, LPARAM unused)
{
    WAVEHDR *header;
    int i;
    (void)instance;
    (void)unused;
    if (!state.shared || handle != state.shared->handle)
        return;
    if (message == WOM_CLOSE) {
        state.close_seen = 1;
        return;
    }
    if (message != WOM_DONE || !parameter)
        return;
    header = (WAVEHDR *)parameter;
    for (i = 0; i < SLOT_COUNT; ++i) {
        MmovSlot *slot = &state.slots[i];
        if (slot->state == SLOT_ACTIVE && slot->token == header->dwUser) {
            if (!state.resetting) {
                state.completed_frames += slot->frames;
                if (state.completed_frames > state.played_frames)
                    state.played_frames = state.completed_frames;
            }
            slot->state = SLOT_FREE;
            return;
        }
    }
}

/* Called with lock held; callbacks run synchronously on this same thread. */
static void pump_callbacks(void)
{
    if (mmeCheckForCallbacks())
        mmeProcessCallbacks();
    pthread_cond_broadcast(&changed);
}

static int reset_device(void)
{
    MMRESULT result;
    int i;
    state.resetting = 1;
    result = waveOutReset(state.shared->handle);
    if (result != MMSYSERR_NOERROR) {
        mmov_error("waveOutReset", result);
        return 0;
    }
    for (i = 0; i < RESET_POLLS; ++i) {
        pump_callbacks();
        if (!count_slots(SLOT_ACTIVE))
            break;
        usleep(POLL_USEC);
    }
    if (count_slots(SLOT_ACTIVE)) {
        fprintf(stderr, "XMMS MMOV: timed out waiting for reset completions\n");
        state.failed = 1;
        return 0;
    }
    for (i = 0; i < SLOT_COUNT; ++i) {
        state.slots[i].state = SLOT_FREE;
        state.slots[i].frames = 0;
    }
    state.fill_slot = state.send_slot = 0;
    state.written_frames = state.submitted_frames = 0;
    state.completed_frames = state.played_frames = 0;
    state.previous_position = state.position_type = 0;
    state.position_wrap = 0;
    state.next_position_poll = 0;
    state.free_polls = state.force_start = 0;
    state.resetting = 0;
    return 1;
}

static int set_hardware_pause(int paused)
{
    MMRESULT result;
    result = paused ? waveOutPause(state.shared->handle) :
                      waveOutRestart(state.shared->handle);
    if (result != MMSYSERR_NOERROR) {
        mmov_error(paused ? "waveOutPause" : "waveOutRestart", result);
        return 0;
    }
    state.hardware_pause = paused;
    state.next_position_poll = 0;
    return 1;
}

static int open_device(void)
{
    MMRESULT result;
    int i;
    state.shared = (MmovShared *)mmeAllocMem(sizeof(MmovShared));
    if (!state.shared) {
        mmov_error("mmeAllocMem", MMSYSERR_NOMEM);
        return 0;
    }
    memset(state.shared, 0, sizeof(MmovShared));
    state.shared->format.wf.wFormatTag = WAVE_FORMAT_PCM;
    state.shared->format.wf.nChannels = (WORD)state.channels;
    state.shared->format.wf.nSamplesPerSec = state.rate;
    state.shared->format.wf.nBlockAlign = (WORD)(state.channels * 2);
    state.shared->format.wf.nAvgBytesPerSec = state.rate * state.channels * 2;
    state.shared->format.wBitsPerSample = 16;
    for (i = 0; i < SLOT_COUNT; ++i) {
        state.slots[i].data = (unsigned char *)
            mmeAllocBuffer(state.slot_frames * state.channels * 2);
        if (!state.slots[i].data) {
            mmov_error("mmeAllocBuffer", MMSYSERR_NOMEM);
            return 0;
        }
    }
    result = waveOutOpen(&state.shared->handle, OUTPUT_DEVICE_ID,
                        (LPWAVEFORMAT)&state.shared->format,
                        (void (*)())callback, 0,
                        CALLBACK_FUNCTION | WAVE_OPEN_SHAREABLE);
    if (result != MMSYSERR_NOERROR) {
        mmov_error("waveOutOpen", result);
        return 0;
    }
    state.opened = 1;
    state.priming = 1;
    return set_hardware_pause(1);
}

static void close_device(void)
{
    int i, safe = 1;
    MMRESULT result;
    if (state.opened) {
        safe = reset_device();
        if (safe) {
            result = waveOutClose(state.shared->handle);
            if (result != MMSYSERR_NOERROR) {
                mmov_error("waveOutClose", result);
                safe = 0;
            } else {
                for (i = 0; i < RESET_POLLS && !state.close_seen; ++i) {
                    pump_callbacks();
                    if (!state.close_seen)
                        usleep(POLL_USEC);
                }
                safe = state.close_seen;
            }
        }
    }
    if (!safe) {
        /* Never release memory that the server might still be using. */
        fprintf(stderr, "XMMS MMOV: retaining outstanding buffers; "
                        "restart XMMS before reopening audio\n");
        state.poisoned = 1;
        return;
    }
    state.opened = 0;
    for (i = 0; i < SLOT_COUNT; ++i) {
        if (state.slots[i].data)
            mmeFreeBuffer(state.slots[i].data);
        state.slots[i].data = NULL;
    }
    if (state.shared)
        mmeFreeMem(state.shared);
    state.shared = NULL;
}

static void update_position(void)
{
    MMTIME *position = &state.shared->position;
    guint64 units, frames;
    unsigned int raw;
    position->wType = TIME_BYTES;
    if (waveOutGetPosition(state.shared->handle, position, sizeof(*position))
        != MMSYSERR_NOERROR) {
        if (state.completed_frames > state.played_frames)
            state.played_frames = state.completed_frames;
        return;
    }
    if (position->wType == TIME_BYTES)
        raw = position->u.cb;
    else if (position->wType == TIME_SAMPLES)
        raw = position->u.sample;
    else if (position->wType == TIME_MS)
        raw = position->u.ms;
    else
        return;
    if (state.position_type != position->wType) {
        state.position_wrap = 0;
        state.previous_position = 0;
        state.position_type = position->wType;
    }
    if (raw < state.previous_position &&
        state.previous_position - raw > 0x80000000U)
        state.position_wrap += ((guint64)1 << 32);
    state.previous_position = raw;
    units = state.position_wrap + raw;
    if (position->wType == TIME_BYTES)
        frames = units / (state.channels * 2);
    else if (position->wType == TIME_MS)
        frames = units * state.rate / 1000;
    else
        frames = units;
    if (frames < state.completed_frames)
        frames = state.completed_frames;
    if (frames > state.submitted_frames)
        frames = state.submitted_frames;
    if (frames > state.played_frames)
        state.played_frames = frames;
}

static void timed_wait(void)
{
    struct timeval now;
    struct timespec until;
    gettimeofday(&now, NULL);
    until.tv_sec = now.tv_sec;
    until.tv_nsec = (now.tv_usec + POLL_USEC) * 1000;
    if (until.tv_nsec >= 1000000000L) {
        ++until.tv_sec;
        until.tv_nsec -= 1000000000L;
    }
    pthread_cond_timedwait(&changed, &lock, &until);
}

static void *worker(void *unused)
{
    int i;
    MMRESULT result;
    (void)unused;
    pthread_mutex_lock(&lock);
    while (!worker_quit) {
        if (mixer_request != mixer_done)
            process_mixer();
        if (!state.running || state.finished) {
            pthread_cond_wait(&changed, &lock);
            continue;
        }
        if (!state.initialized) {
            open_device();
            state.initialized = 1;
            pthread_cond_broadcast(&changed);
        }
        if (state.closing || state.failed) {
            close_device();
            state.finished = 1;
            pthread_cond_broadcast(&changed);
            continue;
        }
        pump_callbacks();
        if (state.flush_done != state.flush_request) {
            if (!reset_device())
                continue;
            state.base_time = state.flush_time;
            state.priming = 1;
            if (!set_hardware_pause(1))
                continue;
            state.flush_done = state.flush_request;
            pthread_cond_broadcast(&changed);
        }
        for (i = 0; i < SLOT_COUNT; ++i) {
            int index = state.send_slot;
            MmovSlot *slot = &state.slots[index];
            WAVEHDR *header = &state.shared->header[index];
            if (slot->state != SLOT_READY)
                break;
            memset(header, 0, sizeof(*header));
            header->lpData = (LPSTR)slot->data;
            header->dwBufferLength = slot->frames * state.channels * 2;
            header->dwUser = slot->token;
            slot->state = SLOT_ACTIVE;
            result = waveOutWrite(state.shared->handle, header, sizeof(*header));
            if (result != MMSYSERR_NOERROR) {
                slot->state = SLOT_FREE;
                mmov_error("waveOutWrite", result);
                break;
            }
            state.submitted_frames += slot->frames;
            state.send_slot = (index + 1) % SLOT_COUNT;
        }
        if (state.failed)
            continue;
        if (state.priming &&
            (count_slots(SLOT_ACTIVE) >= 2 || state.force_start))
            state.priming = 0;
        i = state.desired_pause || state.priming;
        if (i != state.hardware_pause && !set_hardware_pause(i))
            continue;
        if (state.submitted_frames &&
            (!state.hardware_pause || !state.next_position_poll)) {
            guint64 now = clock_milliseconds();
            if (!state.next_position_poll || !now || now >= state.next_position_poll) {
                update_position();
                state.next_position_poll = clock_milliseconds() + POSITION_INTERVAL_MS;
            }
        }
        if (!count_slots(SLOT_ACTIVE) && !count_slots(SLOT_READY))
            pthread_cond_wait(&changed, &lock);
        else
            timed_wait();
    }
    if (state.running && !state.finished) {
        close_device();
        state.finished = 1;
    }
    if (mixer_shared)
        mmeFreeMem(mixer_shared);
    mixer_shared = NULL;
    mixer_status = MMSYSERR_ERROR;
    mixer_done = mixer_request;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&lock);
    return NULL;
}

static int frame_sample(const unsigned char *p)
{
    unsigned int value;
    if (state.sample_bytes == 1)
        return state.format == FMT_U8 ? ((int)p[0] - 128) * 256 :
               ((p[0] & 128) ? (int)p[0] - 256 : p[0]) * 256;
    if (state.format == FMT_U16_BE || state.format == FMT_S16_BE)
        value = ((unsigned int)p[0] << 8) | p[1];
    else if (state.format == FMT_U16_NE || state.format == FMT_S16_NE) {
        unsigned short native;
        memcpy(&native, p, sizeof(native));
        value = native;
    } else
        value = p[0] | ((unsigned int)p[1] << 8);
    if (state.format == FMT_U16_LE || state.format == FMT_U16_BE ||
        state.format == FMT_U16_NE)
        return (int)value - 32768;
    return (value & 32768) ? (int)value - 65536 : (int)value;
}

static void convert_frames(unsigned char *out, const unsigned char *in, int frames)
{
    int frame, channel, sample;
    for (frame = 0; frame < frames; ++frame)
        for (channel = 0; channel < state.channels; ++channel) {
            sample = frame_sample(in);
            out[0] = (unsigned char)(sample & 255);
            out[1] = (unsigned char)((unsigned int)sample >> 8);
            in += state.sample_bytes;
            out += 2;
        }
}

static int mmov_open(AFormat format, int rate, int channels)
{
    unsigned int next_token;
    int result;
    mmov_close();
    if (rate < 1000 || rate > 192000 || channels < 1 || channels > 2 ||
        format < FMT_U8 || format > FMT_S16_NE)
        return 0;
    pthread_mutex_lock(&lock);
    if (state.poisoned || !ensure_worker()) {
        pthread_mutex_unlock(&lock);
        return 0;
    }
    next_token = state.next_token;
    memset(&state, 0, sizeof(state));
    state.next_token = next_token;
    state.format = format;
    state.rate = rate;
    state.channels = channels;
    state.sample_bytes = format == FMT_U8 || format == FMT_S8 ? 1 : 2;
    state.input_frame = channels * state.sample_bytes;
    /* Native MMOV writes can take hundreds of milliseconds. Accumulate small
     * decoder fragments into one-second buffers; four slots bound the queue. */
    state.slot_frames = rate;
    state.running = 1;
    pthread_cond_broadcast(&changed);
    while (!state.initialized)
        pthread_cond_wait(&changed, &lock);
    result = !state.failed;
    pthread_mutex_unlock(&lock);
    if (!result)
        mmov_close();
    return result;
}

static void mmov_write(void *buffer, int length)
{
    const unsigned char *input = (const unsigned char *)buffer;
    int frames, take, epoch;
    pthread_mutex_lock(&lock);
    if (!state.running || state.failed || state.closing || length <= 0)
        goto done;
    if (!input || length % state.input_frame) {
        mmov_error("unaligned PCM input", MMSYSERR_INVALPARAM);
        goto done;
    }
    while (state.flush_request != state.flush_done &&
           !state.failed && !state.closing)
        pthread_cond_wait(&changed, &lock);
    if (state.failed || state.closing)
        goto done;
    frames = length / state.input_frame;
    epoch = state.flush_request;
    state.free_polls = state.force_start = 0;
    while (frames && !state.failed && !state.closing) {
        MmovSlot *slot;
        while (state.slots[state.fill_slot].state != SLOT_FREE &&
               state.slots[state.fill_slot].state != SLOT_PARTIAL &&
               state.flush_request == epoch && !state.failed && !state.closing)
            pthread_cond_wait(&changed, &lock);
        if (state.failed || state.closing || state.flush_request != epoch)
            break;
        slot = &state.slots[state.fill_slot];
        if (slot->state == SLOT_FREE) {
            slot->frames = 0;
            slot->state = SLOT_PARTIAL;
        }
        take = state.slot_frames - slot->frames;
        if (take > frames)
            take = frames;
        convert_frames(slot->data + slot->frames * state.channels * 2, input, take);
        slot->frames += take;
        state.written_frames += take;
        input += take * state.input_frame;
        frames -= take;
        if (slot->frames == state.slot_frames)
            seal_partial();
    }
done:
    pthread_mutex_unlock(&lock);
}

static void mmov_close(void)
{
    pthread_mutex_lock(&lock);
    if (state.running) {
        state.closing = 1;
        pthread_cond_broadcast(&changed);
        while (!state.finished)
            pthread_cond_wait(&changed, &lock);
        state.running = 0;
    }
    pthread_mutex_unlock(&lock);
}

static void mmov_shutdown(void)
{
    pthread_t thread;
    mmov_close();
    pthread_mutex_lock(&lock);
    if (!worker_started) {
        pthread_mutex_unlock(&lock);
        return;
    }
    worker_quit = 1;
    thread = worker_thread;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&lock);
    pthread_join(thread, NULL);
    pthread_mutex_lock(&lock);
    worker_started = 0;
    pthread_mutex_unlock(&lock);
}

static void mmov_flush(int time)
{
    pthread_mutex_lock(&lock);
    if (state.running && !state.failed && !state.closing) {
        state.flush_time = time < 0 ? 0 : time;
        ++state.flush_request;
        pthread_cond_broadcast(&changed);
        while (state.flush_done != state.flush_request &&
               !state.failed && !state.closing)
            pthread_cond_wait(&changed, &lock);
    }
    pthread_mutex_unlock(&lock);
}

static void mmov_pause(short paused)
{
    pthread_mutex_lock(&lock);
    state.desired_pause = paused != 0;
    if (!paused)
        state.force_start = 1;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&lock);
}

static int mmov_free(void)
{
    int bytes = 0, i;
    pthread_mutex_lock(&lock);
    if (state.running && !state.closing) {
        if (state.failed)
            bytes = SLOT_COUNT * state.slot_frames * state.input_frame;
        else {
            if (++state.free_polls >= 2) {
                seal_partial();
                if (!state.force_start) {
                    state.force_start = 1;
                    pthread_cond_broadcast(&changed);
                }
            }
            for (i = 0; i < SLOT_COUNT; ++i) {
                if (state.slots[i].state == SLOT_FREE)
                    bytes += state.slot_frames * state.input_frame;
                else if (state.slots[i].state == SLOT_PARTIAL)
                    bytes += (state.slot_frames - state.slots[i].frames) * state.input_frame;
            }
        }
    }
    pthread_mutex_unlock(&lock);
    return bytes;
}

static int mmov_playing(void)
{
    int playing;
    pthread_mutex_lock(&lock);
    if (state.running && !state.failed && !state.closing)
        seal_partial();
    state.force_start = 1; /* EOF must also drain a single short buffer. */
    playing = state.running && !state.failed && !state.closing &&
              count_slots(SLOT_FREE) != SLOT_COUNT;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&lock);
    return playing;
}

static int frames_to_time(guint64 frames)
{
    guint64 time = state.base_time;
    if (state.rate)
        time += frames * 1000 / state.rate;
    return time > INT_MAX ? INT_MAX : (int)time;
}

static int mmov_output_time(void)
{
    int time;
    pthread_mutex_lock(&lock);
    time = frames_to_time(state.played_frames);
    pthread_mutex_unlock(&lock);
    return time;
}

static int mmov_written_time(void)
{
    int time;
    pthread_mutex_lock(&lock);
    time = frames_to_time(state.written_frames);
    pthread_mutex_unlock(&lock);
    return time;
}

static void mmov_get_volume(int *left, int *right)
{
    guint64 now;
    pthread_mutex_lock(&lock);
    now = clock_milliseconds();
    if ((!state.poisoned && mixer_left >= 0 && now && now < mixer_cache_until) ||
        request_mixer(0, 0)) {
        *left = mixer_left;
        *right = mixer_right;
    } else
        *left = *right = -1;
    pthread_mutex_unlock(&lock);
}

static void mmov_set_volume(int left, int right)
{
    DWORD packed;
    left = left < 0 ? 0 : left > 100 ? 100 : left;
    right = right < 0 ? 0 : right > 100 ? 100 : right;
    packed = (DWORD)((unsigned long)left * 65535UL / 100UL) |
             (DWORD)(((unsigned long)right * 65535UL / 100UL) << 16);
    pthread_mutex_lock(&lock);
    request_mixer(1, packed);
    pthread_mutex_unlock(&lock);
}

static OutputPlugin mmov_plugin = {
    NULL, NULL, "OpenVMS MMOV audio", NULL, NULL, NULL,
    mmov_get_volume, mmov_set_volume, mmov_open, mmov_write, mmov_close,
    mmov_flush, mmov_pause, mmov_free, mmov_playing,
    mmov_output_time, mmov_written_time
};

OutputPlugin *get_mmov_op(void)
{
    return &mmov_plugin;
}

#ifndef XMMS_STATIC_PLUGINS
OutputPlugin *get_oplugin_info(void)
{
    return get_mmov_op();
}
#endif
