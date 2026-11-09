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

#define SLOT_COUNT 8
#define POLL_USEC 5000
#define RESET_POLLS 400
#define SLOT_FREE 0
#define SLOT_READY 1
#define SLOT_ACTIVE 2

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
    pthread_t thread;
    int running, initialized, failed, closing, poisoned;
    int opened, close_seen, resetting;
    int rate, channels, sample_bytes, input_frame, slot_frames;
    AFormat format;
    int fill_slot, send_slot, desired_pause, hardware_pause, priming;
    int free_polls, force_start;
    int flush_request, flush_done, flush_time, base_time;
    unsigned int next_token;
    guint64 written_frames, submitted_frames, completed_frames, played_frames;
    guint64 position_wrap;
    unsigned int previous_position, position_type;
    MmovShared *shared;
    MmovSlot slots[SLOT_COUNT];
} MmovState;

static MmovState state;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int left_volume = 100, right_volume = 100;
static void mmov_close(void);

static int count_slots(int kind)
{
    int i, count = 0;
    for (i = 0; i < SLOT_COUNT; ++i)
        if (state.slots[i].state == kind)
            ++count;
    return count;
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
            if (!state.resetting)
                state.completed_frames += slot->frames;
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
    for (i = 0; i < SLOT_COUNT; ++i)
        state.slots[i].state = SLOT_FREE;
    state.fill_slot = state.send_slot = 0;
    state.written_frames = state.submitted_frames = 0;
    state.completed_frames = state.played_frames = 0;
    state.previous_position = state.position_type = 0;
    state.position_wrap = 0;
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
    result = waveOutOpen(&state.shared->handle, WAVE_MAPPER,
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
    open_device();
    state.initialized = 1;
    pthread_cond_broadcast(&changed);
    while (!state.closing && !state.failed) {
        pump_callbacks();
        if (state.flush_done != state.flush_request) {
            if (!reset_device())
                break;
            state.base_time = state.flush_time;
            state.priming = 1;
            if (!set_hardware_pause(1))
                break;
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
            break;
        if (state.priming &&
            (count_slots(SLOT_ACTIVE) >= 2 || state.force_start))
            state.priming = 0;
        i = state.desired_pause || state.priming;
        if (i != state.hardware_pause && !set_hardware_pause(i))
            break;
        update_position();
        timed_wait();
    }
    close_device();
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
    int frame, channel, sample, volume;
    for (frame = 0; frame < frames; ++frame)
        for (channel = 0; channel < state.channels; ++channel) {
            sample = frame_sample(in);
            volume = channel ? right_volume : left_volume;
            sample = sample * volume / 100;
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
    if (state.poisoned) {
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
    state.slot_frames = rate / 50; /* 20 ms per slot; at most 160 ms queued. */
    state.running = 1;
    result = pthread_create(&state.thread, NULL, worker, NULL);
    if (result) {
        state.running = 0;
        fprintf(stderr, "XMMS MMOV: pthread_create failed (%d)\n", result);
        pthread_mutex_unlock(&lock);
        return 0;
    }
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
               state.flush_request == epoch && !state.failed && !state.closing)
            pthread_cond_wait(&changed, &lock);
        if (state.failed || state.closing || state.flush_request != epoch)
            break;
        slot = &state.slots[state.fill_slot];
        take = frames < state.slot_frames ? frames : state.slot_frames;
        convert_frames(slot->data, input, take);
        if (++state.next_token == 0)
            ++state.next_token;
        slot->token = state.next_token;
        slot->frames = take;
        slot->state = SLOT_READY;
        state.written_frames += take;
        state.fill_slot = (state.fill_slot + 1) % SLOT_COUNT;
        input += take * state.input_frame;
        frames -= take;
        pthread_cond_broadcast(&changed);
    }
done:
    pthread_mutex_unlock(&lock);
}

static void mmov_close(void)
{
    pthread_t thread;
    pthread_mutex_lock(&lock);
    if (!state.running) {
        pthread_mutex_unlock(&lock);
        return;
    }
    state.closing = 1;
    thread = state.thread;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&lock);
    pthread_join(thread, NULL);
    pthread_mutex_lock(&lock);
    state.running = 0;
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
    int bytes = 0;
    pthread_mutex_lock(&lock);
    if (state.running && !state.closing) {
        bytes = (state.failed ? SLOT_COUNT : count_slots(SLOT_FREE)) *
                state.slot_frames * state.input_frame;
        if (++state.free_polls >= 2)
            state.force_start = 1;
        pthread_cond_broadcast(&changed);
    }
    pthread_mutex_unlock(&lock);
    return bytes;
}

static int mmov_playing(void)
{
    int playing;
    pthread_mutex_lock(&lock);
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
    pthread_mutex_lock(&lock);
    *left = left_volume;
    *right = right_volume;
    pthread_mutex_unlock(&lock);
}

static void mmov_set_volume(int left, int right)
{
    pthread_mutex_lock(&lock);
    left_volume = left < 0 ? 0 : left > 100 ? 100 : left;
    right_volume = right < 0 ? 0 : right > 100 ? 100 : right;
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
