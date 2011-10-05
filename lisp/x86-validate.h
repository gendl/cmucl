/*
 *
 * This code was written as part of the CMU Common Lisp project at
 * Carnegie Mellon University, and has been placed in the public domain.
 *
 *  $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/lisp/x86-validate.h,v 1.34 2010/12/22 05:55:22 rtoy Exp $
 *
 */

#ifndef _X86_VALIDATE_H_
#define _X86_VALIDATE_H_

/*
 * Also look in compiler/x86/parms.lisp for some of the parameters.
 *
 * Address map:
 *
 *  FreeBSD:
 *	0x00000000->0x0E000000  224M C program and memory allocation.
 *	0x0E000000->0x10000000   32M Foreign segment.
 *	0x10000000->0x20000000  256M Read-Only Space.
 *	0x20000000->0x28000000  128M Reserved for shared libraries.
 *	0x28000000->0x38000000  256M Static Space.
 *	0x38000000->0x40000000  128M Binding stack growing up.
 *	0x40000000->0x48000000  128M Control stack growing down.
 *	0x48000000->0xB0000000 1664M Dynamic Space.
 *      0xB0000000->0xB1000000       Foreign Linkage Table
 *	0xE0000000->            256M C stack - Alien stack.
 *
 *  OpenBSD:
 *	0x00000000->0x0E000000  224M C program and memory allocation.
 *	0x0E000000->0x10000000   32M Foreign segment.
 *	0x10000000->0x20000000  256M Read-Only Space.
 *	0x20000000->0x28000000  128M Binding stack growing up.
 *	0x28000000->0x38000000  256M Static Space.
 *	0x38000000->0x40000000  128M Control stack growing down.
 *	0x40000000->0x48000000  128M Reserved for shared libraries.
 *	0x48000000->0xB0000000 1664M Dynamic Space.
 *      0xB0000000->0xB1000000   16M Foreign Linkage Table
 *	0xE0000000->            256M C stack - Alien stack.
 *
 *  NetBSD:
 *	0x00000000->0x0E000000  224M C program and memory allocation.
 *	0x0E000000->0x10000000   32M Foreign segment.
 *	0x10000000->0x20000000  256M Read-Only Space.
 *	0x28000000->0x38000000  256M Static Space.
 *	0x38000000->0x40000000  128M Binding stack growing up.
 *	0x40000000->0x48000000  128M Control stack growing down.
 *	0x48800000->0xB0000000 1656M Dynamic Space.
 *      0xB0000000->0xB1000000   16M Foreign Linkage Table
 *	0xE0000000->            256M C stack - Alien stack.
 *
 *  Linux:
 *	0x00000000->0x08000000  128M Unused.
 *	0x08000000->0x10000000  128M C program and memory allocation.
 *	0x10000000->0x20000000  256M Read-Only Space.
 *	0x20000000->0x28000000  128M Binding stack growing up.
 *	0x28000000->0x38000000  256M Static Space.
 *	0x38000000->0x40000000  128M Control stack growing down.
 *	0x40000000->0x48000000  128M Reserved for shared libraries.
 *      0x58000000->0x58100000   16M Foreign Linkage Table
 *	0x58100000->0xBE000000 1631M Dynamic Space.
 *      0xBFFF0000->0xC0000000       Unknown Linux mapping
 *
 *      (Note: 0x58000000 allows us to run on a Linux system on an AMD
 *      x86-64.  Hence we have a gap of unused memory starting at
 *      0x48000000.)
 */

#ifdef __FreeBSD__
#define READ_ONLY_SPACE_START   (0x10000000)
#define READ_ONLY_SPACE_SIZE    (0x0ffff000)	/* 256MB - 1 page */

#define STATIC_SPACE_START	(0x28f00000)
#define STATIC_SPACE_SIZE	(0x0f0ff000)	/* 241MB - 1 page */

#define BINDING_STACK_SIZE	(0x07fff000)	/* 128MB - 1 page */
#define CONTROL_STACK_SIZE	0x07fd8000	/* 128MB - SIGSTKSZ */
#define SIGNAL_STACK_START	0x47fd8000
#define SIGNAL_STACK_SIZE	SIGSTKSZ

#define DYNAMIC_0_SPACE_START	(0x48000000UL)
#ifdef GENCGC
#define DYNAMIC_SPACE_SIZE	(0x78000000UL)	/* May be up to 1.7 GB */
#else
#define DYNAMIC_SPACE_SIZE	(0x04000000UL)	/* 64MB */
#endif
#define DEFAULT_DYNAMIC_SPACE_SIZE	(0x20000000UL)	/* 512MB */
#ifdef LINKAGE_TABLE
#define FOREIGN_LINKAGE_SPACE_START ((unsigned long) LinkageSpaceStart)
#define FOREIGN_LINKAGE_SPACE_SIZE (0x100000UL)	/* 1MB */
#endif
#endif /* __FreeBSD__ */


#ifdef __OpenBSD__
#define READ_ONLY_SPACE_START   (0x10000000)
#define READ_ONLY_SPACE_SIZE    (0x0ffff000)	/* 256MB - 1 page */

#define STATIC_SPACE_START	(0x28000000)
#define STATIC_SPACE_SIZE	(0x0ffff000)	/* 256MB - 1 page */

#define BINDING_STACK_START	(0x38000000)
#define BINDING_STACK_SIZE	(0x07fff000)	/* 128MB - 1 page */

#define CONTROL_STACK_START	(0x40000000)
#define CONTROL_STACK_SIZE	(0x07fd8000)	/* 128MB - SIGSTKSZ */

#define SIGNAL_STACK_START	(0x47fd8000)
#define SIGNAL_STACK_SIZE	SIGSTKSZ

#define DYNAMIC_0_SPACE_START	(0x48000000)
#ifdef GENCGC
#define DYNAMIC_SPACE_SIZE	(0x68000000)	/* 1.625GB */
#else
#define DYNAMIC_SPACE_SIZE	(0x04000000)	/* 64MB */
#endif
#define DEFAULT_DYNAMIC_SPACE_SIZE	(0x20000000)	/* 512MB */
#endif

#if defined(__NetBSD__) || defined(DARWIN)
#define READ_ONLY_SPACE_START   (SpaceStart_TargetReadOnly)
#define READ_ONLY_SPACE_SIZE    (0x0ffff000)	/* 256MB - 1 page */

#define STATIC_SPACE_START	(SpaceStart_TargetStatic)
#define STATIC_SPACE_SIZE	(0x0ffff000)	/* 256MB - 1 page */

#if !defined(DARWIN)
#define BINDING_STACK_START	(0x38000000)
#endif
#define BINDING_STACK_SIZE	(0x07fff000)	/* 128MB - 1 page */

#if !defined(DARWIN)
#define CONTROL_STACK_START	(0x40000000)
#endif
#if defined(DARWIN)
/*
 * According to /usr/include/sys/signal.h, MINSIGSTKSZ is 32K and
 * SIGSTKSZ is 128K.  We should account for that appropriately.
 */
#define CONTROL_STACK_SIZE	(0x07fdf000)	/* 128MB - SIGSTKSZ - 1 page */

#if 0
#define SIGNAL_STACK_START	(0x47fe0000)    /* One page past the end of the control stack */
#endif
#define SIGNAL_STACK_SIZE	SIGSTKSZ
#else
#define CONTROL_STACK_SIZE	(0x07fd8000)	/* 128MB - SIGSTKSZ */

#define SIGNAL_STACK_START	(0x47fd8000)
#define SIGNAL_STACK_SIZE	SIGSTKSZ
#endif

#define DYNAMIC_0_SPACE_START	(SpaceStart_TargetDynamic)
#ifdef GENCGC
#if defined(DARWIN)
/*
 * On Darwin, /usr/lib/dyld appears to always be loaded at address
 * #x8fe2e000.  Hence, the maximum dynamic space size is 1206050816
 * bytes, or just over 1.150 GB.  Set the limit to 1.150 GB.
 */
#define DYNAMIC_SPACE_SIZE	(0x47E00000U)	/* 1.150GB */
#else
#define DYNAMIC_SPACE_SIZE	(0x67800000U)	/* 1.656GB */
#endif
#else
#define DYNAMIC_SPACE_SIZE	(0x04000000U)	/* 64MB */
#endif
#define DEFAULT_DYNAMIC_SPACE_SIZE	(0x20000000U)	/* 512MB */
#ifdef LINKAGE_TABLE
#define FOREIGN_LINKAGE_SPACE_START (LinkageSpaceStart)
#define FOREIGN_LINKAGE_SPACE_SIZE (0x100000)	/* 1MB */
#endif
#endif /* __NetBSD__ || DARWIN */

#ifdef __linux__
#define READ_ONLY_SPACE_START   (SpaceStart_TargetReadOnly)
#define READ_ONLY_SPACE_SIZE    (0x0ffff000)	/* 256MB - 1 page */

#define STATIC_SPACE_START	(SpaceStart_TargetStatic)
#define STATIC_SPACE_SIZE	(0x0ffff000)	/* 256MB - 1 page */

#if 0
#define BINDING_STACK_START	(0x20000000)
#endif
#define BINDING_STACK_SIZE	(0x07fff000)	/* 128MB - 1 page */

#if 0
#define CONTROL_STACK_START	0x38000000
#endif
#define CONTROL_STACK_SIZE	(0x07fff000 - 8192)

#if 0
#define SIGNAL_STACK_START	CONTROL_STACK_END
#endif
#define SIGNAL_STACK_SIZE	SIGSTKSZ

#define DYNAMIC_0_SPACE_START	(SpaceStart_TargetDynamic)

#ifdef GENCGC
#define DYNAMIC_SPACE_SIZE	(0x66000000)	/* 1.632GB */
#else
#define DYNAMIC_SPACE_SIZE	(0x04000000)	/* 64MB */
#endif
#define DEFAULT_DYNAMIC_SPACE_SIZE	(0x20000000)	/* 512MB */
#ifdef LINKAGE_TABLE
#define FOREIGN_LINKAGE_SPACE_START (LinkageSpaceStart)
#define FOREIGN_LINKAGE_SPACE_SIZE (0x100000)	/* 1MB */
#endif
#endif

#ifdef SOLARIS
/*
 * The memory map for Solaris/x86 looks roughly like
 *
 *	0x08045000->0x08050000   C stack?
 *      0x08050000->             Code + C heap
 *      0x10000000->0x20000000   256 MB read-only space
 *	0x20000000->0x28000000   128M Binding stack growing up.
 *	0x28000000->0x30000000   256M Static Space.
 *      0x30000000->0x31000000   16M Foreign linkage table
 *	0x38000000->0x40000000   128M Control stack growing down.
 *	0x40000000->0xD0000000   2304M Dynamic Space.
 *
 * Starting at 0xd0ce0000 there is some mapped anon memory.  libc
 * seems to start at 0xd0d40000 and other places.  Looks like memory
 * above 0xd0ffe000 or so is not mapped.
 */

#define READ_ONLY_SPACE_START   (SpaceStart_TargetReadOnly)
#define READ_ONLY_SPACE_SIZE    (0x0ffff000)	/* 256MB - 1 page */

#define STATIC_SPACE_START	(SpaceStart_TargetStatic)
#define STATIC_SPACE_SIZE	(0x0ffff000)	/* 256MB - 1 page */

#define BINDING_STACK_START	(0x20000000)
#define BINDING_STACK_SIZE	(0x07fff000)	/* 128MB - 1 page */

#define CONTROL_STACK_START	0x38000000
#define CONTROL_STACK_SIZE	(0x07fff000 - 8192)
#define SIGNAL_STACK_START	CONTROL_STACK_END
#define SIGNAL_STACK_SIZE	SIGSTKSZ

#define DYNAMIC_0_SPACE_START	(SpaceStart_TargetDynamic)

#ifdef GENCGC
#define DYNAMIC_SPACE_SIZE	(0x90000000)	/* 2.304GB */
#else
#define DYNAMIC_SPACE_SIZE	(0x04000000)	/* 64MB */
#endif
#define DEFAULT_DYNAMIC_SPACE_SIZE	(0x20000000)	/* 512MB */
#ifdef LINKAGE_TABLE
#define FOREIGN_LINKAGE_SPACE_START (LinkageSpaceStart)
#define FOREIGN_LINKAGE_SPACE_SIZE (0x100000)	/* 1MB */
#endif
#endif

#define CONTROL_STACK_END	(CONTROL_STACK_START + control_stack_size)

/* Note that GENCGC only uses dynamic_space 0. */
#define DYNAMIC_1_SPACE_START	(DYNAMIC_0_SPACE_START + DYNAMIC_SPACE_SIZE)

#endif /* _X86_VALIDATE_H_ */
