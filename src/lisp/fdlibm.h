
/* @(#)fdlibm.h 1.5 04/04/22 */
/*
 * ====================================================
 * Copyright (C) 2004 by Sun Microsystems, Inc. All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice 
 * is preserved.
 * ====================================================
 */

#ifndef FDLIBM_H
#define FDLIBM_H
/* Sometimes it's necessary to define __LITTLE_ENDIAN explicitly
   but these catch some common cases. */

#if defined(i386) || defined(i486) || \
	defined(intel) || defined(x86) || defined(i86pc) || \
	defined(__alpha) || defined(__osf__)
#define __LITTLE_ENDIAN
#endif

#ifdef __LITTLE_ENDIAN
enum { HIWORD = 1, LOWORD = 0 };
#else
enum { HIWORD = 0, LOWORD = 1 };
#endif

enum FDLIBM_EXCEPTION {
  FDLIBM_DIVIDE_BY_ZERO,
  FDLIBM_UNDERFLOW,
  FDLIBM_OVERFLOW,
  FDLIBM_INVALID,
  FDLIBM_INEXACT
};

extern double fdlibm_setexception(double x, enum FDLIBM_EXCEPTION);

#endif
