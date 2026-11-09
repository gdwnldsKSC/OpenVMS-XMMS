/*
 * XMMS native OpenVMS MMOV declarations.
 * Copyright (C) 2026 OpenVMS-XMMS contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * MMOV.OLB exports the SDK entry points in uppercase. XMMS and GTK use
 * case-preserved external names, so change the compiler naming policy only
 * while reading the external vendor declarations, then restore it.
 * The proprietary MMOV SDK remains an external build dependency.
 */
#ifndef XMMS_MMOV_API_H
#define XMMS_MMOV_API_H

#ifdef __VMS
#pragma names save
#pragma names uppercase
#endif
#include <mme/mme_api.h>
#ifdef __VMS
#pragma names restore
#endif

#endif
